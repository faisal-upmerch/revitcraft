import Foundation

// A minimal, defensive reader for the Microsoft Compound File Binary format ([MS-CFB], an openly published
// specification). Revit .rvt/.rfa/.rte/.rft files are stored in this container. Arcus uses the reader only to list
// stream names and to read two streams whose content is standard data (an embedded PNG preview and plain UTF-16 text);
// it never interprets Revit's own model streams.
//
// Hostile-input rules: every offset is bounds-checked, every sector chain is cycle-checked and length-limited, the
// directory tree is walked iteratively with a visited set, and stream reads are capped by `CompoundFileLimits`.

/// Why a compound file could not be read.
public struct CompoundFileError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Hashable, Sendable {
        /// The data does not start with the CFB signature.
        case notCompoundFile
        /// Major version other than 3 or 4, or an unsupported sector size.
        case unsupportedVersion
        /// A structure is inconsistent (bad byte order mark, out-of-range sector, broken directory…).
        case malformed
        /// The file ends before a structure or stream does.
        case truncated
        /// A sector chain or the directory tree loops back on itself.
        case cycle
        /// A size limit from `CompoundFileLimits` was exceeded.
        case limitExceeded
        /// The requested stream does not exist.
        case notFound
        /// The file could not be read from disk.
        case io
    }
    public var kind: Kind
    public var message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
    public var description: String { message }
}

/// Size limits that bound the work done on untrusted files.
public struct CompoundFileLimits: Hashable, Sendable {
    /// Largest file accepted (bytes).
    public var maxFileSize: Int
    /// Largest number of directory entries parsed.
    public var maxDirectoryEntries: Int
    /// Default largest stream `read` returns (bytes); callers can pass a smaller cap per read.
    public var maxStreamSize: Int
    /// Deepest storage nesting walked.
    public var maxStorageDepth: Int

    public init(maxFileSize: Int = 8 << 30, maxDirectoryEntries: Int = 262_144, maxStreamSize: Int = 256 << 20, maxStorageDepth: Int = 64) {
        self.maxFileSize = maxFileSize; self.maxDirectoryEntries = maxDirectoryEntries
        self.maxStreamSize = maxStreamSize; self.maxStorageDepth = maxStorageDepth
    }
    public static let `default` = CompoundFileLimits()
}

/// A parsed compound file: header, allocation tables and the directory tree. Streams are read on demand.
public struct CompoundFile: Sendable {
    /// A storage or stream reachable from the root storage.
    public struct Entry: Hashable, Sendable {
        public enum Kind: UInt8, Hashable, Sendable { case storage = 1, stream = 2, root = 5 }
        /// Index in the directory sector chain.
        public let index: Int
        public let name: String
        /// Slash-separated path from the root, e.g. `"Formats/Latest"`.
        public let path: String
        public let kind: Kind
        /// Stream size in bytes (0 for storages).
        public let size: UInt64
        let startSector: UInt32
    }

    public static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

    // Special sector numbers ([MS-CFB] 2.1).
    static let maxRegSect: UInt32 = 0xFFFF_FFFA
    static let difSect: UInt32 = 0xFFFF_FFFC
    static let fatSect: UInt32 = 0xFFFF_FFFD
    static let endOfChain: UInt32 = 0xFFFF_FFFE
    static let freeSect: UInt32 = 0xFFFF_FFFF
    static let noStream: UInt32 = 0xFFFF_FFFF

    public let majorVersion: Int
    public let minorVersion: Int
    public let sectorSize: Int
    public let miniSectorSize: Int
    public let miniStreamCutoff: Int
    /// Storages and streams reachable from the root, depth first, siblings in directory order. The root is excluded.
    public let entries: [Entry]
    public let limits: CompoundFileLimits

    private let data: Data
    private let sectorCount: Int
    private let fat: [UInt32]
    private let miniFat: [UInt32]
    /// Regular sectors that hold the mini stream, in order.
    private let miniStreamSectors: [UInt32]
    /// Bytes of the mini stream actually backed by sectors.
    private let miniStreamAvailable: Int

    /// Streams only.
    public var streams: [Entry] { entries.filter { $0.kind == .stream } }
    /// Paths of all streams.
    public var streamPaths: [String] { streams.map(\.path) }

    /// Whether `data` begins with the compound file signature.
    public static func hasSignature(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual(signature)
    }

    /// Opens a file (memory-mapped) after checking its size.
    public init(contentsOf url: URL, limits: CompoundFileLimits = .default) throws(CompoundFileError) {
        let size: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            throw CompoundFileError(.io, "The file could not be read: \(error.localizedDescription)")
        }
        guard size <= limits.maxFileSize else {
            throw CompoundFileError(.limitExceeded, "The file is larger than the \(limits.maxFileSize >> 20) MB limit.")
        }
        let data: Data
        do { data = try Data(contentsOf: url, options: .alwaysMapped) } catch {
            throw CompoundFileError(.io, "The file could not be read: \(error.localizedDescription)")
        }
        try self.init(data: data, limits: limits)
    }

    public init(data: Data, limits: CompoundFileLimits = .default) throws(CompoundFileError) {
        self.data = data
        self.limits = limits
        let b = Bytes(data: data)
        guard data.count <= limits.maxFileSize else {
            throw CompoundFileError(.limitExceeded, "The file is larger than the \(limits.maxFileSize >> 20) MB limit.")
        }
        guard data.count >= 512, CompoundFile.hasSignature(data) else {
            throw CompoundFileError(.notCompoundFile, "The file is not a compound file (the container Revit uses): the signature is missing.")
        }
        let major = Int(b.u16(26)), minor = Int(b.u16(24))
        guard major == 3 || major == 4 else {
            throw CompoundFileError(.unsupportedVersion, "Compound file major version \(major) is not supported (expected 3 or 4).")
        }
        guard b.u16(28) == 0xFFFE else { throw CompoundFileError(.malformed, "The compound file header has an invalid byte order mark.") }
        let sectorShift = Int(b.u16(30))
        guard sectorShift == 9 || sectorShift == 12 else {
            throw CompoundFileError(.unsupportedVersion, "Compound file sector shift \(sectorShift) is not supported (expected 9 or 12).")
        }
        let miniShift = Int(b.u16(32))
        guard miniShift == 6 else { throw CompoundFileError(.malformed, "Compound file mini sector shift \(miniShift) is invalid (expected 6).") }
        let sectorSize = 1 << sectorShift
        let cutoff = Int(b.u32(56))
        guard cutoff == 4096 else { throw CompoundFileError(.malformed, "Compound file mini stream cutoff \(cutoff) is invalid (expected 4096).") }
        majorVersion = major; minorVersion = minor
        self.sectorSize = sectorSize; miniSectorSize = 1 << miniShift; miniStreamCutoff = cutoff
        // Sector 0 starts right after the header, which occupies one full sector (512 or 4096 bytes).
        let sectorCount = data.count > sectorSize ? (data.count - sectorSize + sectorSize - 1) / sectorSize : 0
        self.sectorCount = sectorCount

        let numFATSectors = Int(b.u32(44))
        let firstDirSector = b.u32(48)
        let firstMiniFATSector = b.u32(60)
        let numMiniFATSectors = Int(b.u32(64))
        let firstDIFATSector = b.u32(68)
        let numDIFATSectors = Int(b.u32(72))
        guard numFATSectors <= sectorCount else {
            throw CompoundFileError(.malformed, "The header lists \(numFATSectors) allocation sectors but the file has only \(sectorCount) sectors.")
        }
        guard numDIFATSectors <= sectorCount, numMiniFATSectors <= sectorCount else {
            throw CompoundFileError(.malformed, "The header lists more allocation sectors than the file contains.")
        }

        func sectorOffset(_ s: UInt32) -> Int { (Int(s) + 1) * sectorSize }
        func checkFullSector(_ s: UInt32, _ what: String) throws(CompoundFileError) {
            guard Int(s) < sectorCount else { throw CompoundFileError(.malformed, "\(what) refers to sector \(s), beyond the end of the file.") }
            guard sectorOffset(s) + sectorSize <= data.count else { throw CompoundFileError(.truncated, "\(what) sector \(s) is cut off at the end of the file.") }
        }

        // FAT sector locations: 109 in the header, the rest in the DIFAT chain.
        var fatSectors: [UInt32] = []
        fatSectors.reserveCapacity(numFATSectors)
        for i in 0..<min(109, numFATSectors) {
            let s = b.u32(76 + 4 * i)
            try checkFullSector(s, "The allocation table")
            fatSectors.append(s)
        }
        var next = firstDIFATSector
        var seenDIFAT = Set<UInt32>()
        let perDIFAT = sectorSize / 4 - 1
        while fatSectors.count < numFATSectors {
            guard next != CompoundFile.endOfChain, next != CompoundFile.freeSect else {
                throw CompoundFileError(.malformed, "The allocation table index lists \(fatSectors.count) of \(numFATSectors) sectors.")
            }
            try checkFullSector(next, "The allocation table index")
            guard seenDIFAT.insert(next).inserted else { throw CompoundFileError(.cycle, "The allocation table index chain loops back on itself.") }
            let base = sectorOffset(next)
            for j in 0..<perDIFAT where fatSectors.count < numFATSectors {
                let s = b.u32(base + 4 * j)
                try checkFullSector(s, "The allocation table")
                fatSectors.append(s)
            }
            next = b.u32(base + 4 * perDIFAT)
        }
        var fat: [UInt32] = []
        fat.reserveCapacity(fatSectors.count * sectorSize / 4)
        for s in fatSectors {
            let base = sectorOffset(s)
            for j in 0..<(sectorSize / 4) { fat.append(b.u32(base + 4 * j)) }
        }
        self.fat = fat

        // Walks a regular sector chain. Stops after `maxSectors`; throws on out-of-range sectors and cycles.
        func chain(_ start: UInt32, maxSectors: Int, _ what: String) throws(CompoundFileError) -> [UInt32] {
            var out: [UInt32] = []
            var seen = Set<UInt32>()
            var s = start
            while s != CompoundFile.endOfChain, out.count < maxSectors {
                guard Int(s) < fat.count, Int(s) < sectorCount else {
                    throw CompoundFileError(.malformed, "\(what) refers to sector \(s), which is outside the file.")
                }
                guard seen.insert(s).inserted else { throw CompoundFileError(.cycle, "\(what) sector chain loops back on itself.") }
                out.append(s)
                s = fat[Int(s)]
            }
            return out
        }

        // Directory.
        let perDirSector = sectorSize / 128
        let maxDirSectors = min(sectorCount, limits.maxDirectoryEntries / perDirSector + 1)
        let dirChain = try chain(firstDirSector, maxSectors: maxDirSectors, "The directory")
        guard !dirChain.isEmpty else { throw CompoundFileError(.malformed, "The compound file has no directory.") }
        var raw: [RawEntry] = []
        raw.reserveCapacity(dirChain.count * perDirSector)
        for s in dirChain {
            guard sectorOffset(s) + sectorSize <= data.count else { throw CompoundFileError(.truncated, "A directory sector is cut off at the end of the file.") }
            for k in 0..<perDirSector where raw.count < limits.maxDirectoryEntries {
                raw.append(RawEntry.parse(b, at: sectorOffset(s) + 128 * k, majorVersion: major))
            }
        }
        guard raw[0].type == 5 else { throw CompoundFileError(.malformed, "The first directory entry is not the root storage.") }

        // Mini FAT and mini stream.
        var miniFat: [UInt32] = []
        if firstMiniFATSector != CompoundFile.endOfChain && numMiniFATSectors > 0 {
            for s in try chain(firstMiniFATSector, maxSectors: numMiniFATSectors, "The mini allocation table") {
                guard sectorOffset(s) + sectorSize <= data.count else { throw CompoundFileError(.truncated, "A mini allocation sector is cut off at the end of the file.") }
                let base = sectorOffset(s)
                for j in 0..<(sectorSize / 4) { miniFat.append(b.u32(base + 4 * j)) }
            }
        }
        self.miniFat = miniFat
        let root = raw[0]
        if root.start != CompoundFile.endOfChain && root.start < CompoundFile.maxRegSect && root.size > 0 {
            let wanted = min(UInt64(sectorCount), (root.size + UInt64(sectorSize) - 1) / UInt64(sectorSize))
            let ms = try chain(root.start, maxSectors: Int(wanted), "The mini stream")
            miniStreamSectors = ms
            miniStreamAvailable = Int(min(root.size, UInt64(ms.count * sectorSize)))
        } else {
            miniStreamSectors = []
            miniStreamAvailable = 0
        }

        entries = try CompoundFile.walkTree(raw, limits: limits)
    }

    // MARK: Directory tree

    struct RawEntry {
        var name: String
        var type: UInt8
        var left: UInt32, right: UInt32, child: UInt32
        var start: UInt32
        var size: UInt64

        static func parse(_ b: Bytes, at o: Int, majorVersion: Int) -> RawEntry {
            let nameLength = Int(b.u16(o + 64))
            var units: [UInt16] = []
            if nameLength >= 2, nameLength <= 64, nameLength % 2 == 0 {
                for i in 0..<(nameLength / 2 - 1) {
                    let u = b.u16(o + 2 * i)
                    if u == 0 { break }
                    units.append(u)
                }
            }
            var size = b.u64(o + 120)
            // Version 3 files may leave garbage in the high 32 bits ([MS-CFB] 2.6.3).
            if majorVersion == 3 { size &= 0xFFFF_FFFF }
            return RawEntry(name: String(decoding: units, as: UTF16.self), type: b.u8(o + 66),
                            left: b.u32(o + 68), right: b.u32(o + 72), child: b.u32(o + 76),
                            start: b.u32(o + 116), size: size)
        }
    }

    /// Iterative walk of the red-black sibling trees below each storage. Every entry may be reached once.
    static func walkTree(_ raw: [RawEntry], limits: CompoundFileLimits) throws(CompoundFileError) -> [Entry] {
        var out: [Entry] = []
        var visited: Set<UInt32> = [0]
        // Storages whose children still need walking: (child tree root, path prefix, depth).
        var storages: [(UInt32, String, Int)] = [(raw[0].child, "", 1)]
        while let pending = storages.popLast() {
            let (treeRoot, prefix, depth) = pending
            guard treeRoot != noStream else { continue }
            guard depth <= limits.maxStorageDepth else {
                throw CompoundFileError(.limitExceeded, "Storages are nested more than \(limits.maxStorageDepth) levels deep.")
            }
            // In-order traversal of the sibling tree with an explicit stack.
            var stack: [UInt32] = []
            var cur = treeRoot
            var children: [(UInt32, String)] = []
            while cur != noStream || !stack.isEmpty {
                while cur != noStream {
                    guard Int(cur) < raw.count else {
                        throw CompoundFileError(.malformed, "A directory entry refers to entry \(cur), which does not exist.")
                    }
                    guard visited.insert(cur).inserted else { throw CompoundFileError(.cycle, "The directory tree loops back on itself.") }
                    stack.append(cur)
                    cur = raw[Int(cur)].left
                }
                let idx = stack.removeLast()
                let r = raw[Int(idx)]
                let path = prefix.isEmpty ? r.name : prefix + "/" + r.name
                switch r.type {
                case 1:
                    out.append(Entry(index: Int(idx), name: r.name, path: path, kind: .storage, size: 0, startSector: 0))
                    children.append((r.child, path))
                case 2:
                    out.append(Entry(index: Int(idx), name: r.name, path: path, kind: .stream, size: r.size, startSector: r.start))
                default:
                    break // Unallocated or unknown entries inside the tree are ignored.
                }
                cur = r.right
            }
            // Push in reverse so storages are expanded in directory order.
            for (child, path) in children.reversed() { storages.append((child, path, depth + 1)) }
        }
        return out
    }

    // MARK: Streams

    /// The stream at `path` (compared case-insensitively, as CFB names are).
    public func entry(atPath path: String) -> Entry? {
        entries.first { $0.path.caseInsensitiveCompare(path) == .orderedSame }
    }

    /// Reads a stream by path.
    public func read(path: String, maxBytes: Int? = nil) throws(CompoundFileError) -> Data {
        guard let e = entry(atPath: path), e.kind == .stream else { throw CompoundFileError(.notFound, "The file has no stream named “\(path)”.") }
        return try read(e, maxBytes: maxBytes)
    }

    /// Reads a stream's bytes. Throws `.limitExceeded` if it is larger than `maxBytes` (default `limits.maxStreamSize`).
    public func read(_ e: Entry, maxBytes: Int? = nil) throws(CompoundFileError) -> Data {
        guard e.kind == .stream else { throw CompoundFileError(.notFound, "“\(e.path)” is a storage, not a stream.") }
        let cap = min(maxBytes ?? limits.maxStreamSize, limits.maxStreamSize)
        guard e.size <= UInt64(cap) else {
            throw CompoundFileError(.limitExceeded, "Stream “\(e.path)” is \(e.size) bytes, more than the \(cap) byte limit.")
        }
        let size = Int(e.size)
        if size == 0 { return Data() }
        let b = Bytes(data: data)
        var out = Data()
        out.reserveCapacity(size)
        if size < miniStreamCutoff {
            // Mini stream: 64-byte sectors chained through the mini FAT, stored inside the root's regular sectors.
            let needed = (size + miniSectorSize - 1) / miniSectorSize
            var seen = Set<UInt32>()
            var m = e.startSector
            for _ in 0..<needed {
                guard Int(m) < miniFat.count else {
                    throw CompoundFileError(m == CompoundFile.endOfChain ? .truncated : .malformed, "Stream “\(e.path)” has a broken mini sector chain.")
                }
                guard seen.insert(m).inserted else { throw CompoundFileError(.cycle, "Stream “\(e.path)” mini sector chain loops back on itself.") }
                let streamOffset = Int(m) * miniSectorSize
                let count = min(miniSectorSize, size - out.count)
                guard streamOffset + count <= miniStreamAvailable else {
                    throw CompoundFileError(.truncated, "Stream “\(e.path)” extends beyond the mini stream.")
                }
                let sector = miniStreamSectors[streamOffset / sectorSize]
                let fileOffset = (Int(sector) + 1) * sectorSize + streamOffset % sectorSize
                guard fileOffset + count <= data.count else { throw CompoundFileError(.truncated, "Stream “\(e.path)” is cut off at the end of the file.") }
                out.append(b.slice(fileOffset, count))
                m = miniFat[Int(m)]
            }
        } else {
            let needed = (size + sectorSize - 1) / sectorSize
            var seen = Set<UInt32>()
            var s = e.startSector
            for _ in 0..<needed {
                guard Int(s) < fat.count, Int(s) < sectorCount else {
                    throw CompoundFileError(s == CompoundFile.endOfChain ? .truncated : .malformed, "Stream “\(e.path)” has a broken sector chain.")
                }
                guard seen.insert(s).inserted else { throw CompoundFileError(.cycle, "Stream “\(e.path)” sector chain loops back on itself.") }
                let count = min(sectorSize, size - out.count)
                let fileOffset = (Int(s) + 1) * sectorSize
                guard fileOffset + count <= data.count else { throw CompoundFileError(.truncated, "Stream “\(e.path)” is cut off at the end of the file.") }
                out.append(b.slice(fileOffset, count))
                s = fat[Int(s)]
            }
        }
        return out
    }
}

/// Bounds-checked little-endian reads. Out-of-range reads return zero; callers validate offsets before relying on them.
struct Bytes {
    let data: Data
    func u8(_ o: Int) -> UInt8 {
        guard o >= 0, o < data.count else { return 0 }
        return data[data.startIndex + o]
    }
    func u16(_ o: Int) -> UInt16 {
        guard o >= 0, o + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
    }
    func u32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
    }
    func u64(_ o: Int) -> UInt64 {
        guard o >= 0, o + 8 <= data.count else { return 0 }
        return data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt64.self)) }
    }
    func slice(_ o: Int, _ n: Int) -> Data {
        guard o >= 0, n >= 0, o + n <= data.count else { return Data() }
        return data.subdata(in: (data.startIndex + o)..<(data.startIndex + o + n))
    }
}
