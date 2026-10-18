import Foundation

/// Writes small [MS-CFB] compound files for tests: version 3 (512-byte sectors) or 4 (4096-byte sectors), storages,
/// mini-stream and regular streams, and DIFAT sectors when the allocation table needs more than 109 sectors.
/// The layout it returns lets tests corrupt specific structures.
struct CFBWriter {
    indirect enum Node {
        case stream(String, Data)
        case storage(String, [Node])
    }

    var majorVersion = 3
    var nodes: [Node] = []
    /// Free sectors appended after the streams (to make large allocation tables).
    var paddingSectors = 0

    struct Layout {
        var sectorSize: Int
        var fatSectors: [Int]
        var difatSectors: [Int]
        var dirStart: Int
        var dirSectorCount: Int
        var miniFATStart: Int?
        /// Path → first sector (regular streams) or first mini sector (mini streams).
        var streamStart: [String: Int] = [:]
        var isMini: [String: Bool] = [:]
        /// Path → directory entry index (root is 0).
        var entryIndex: [String: Int] = [:]

        func sectorOffset(_ s: Int) -> Int { (s + 1) * sectorSize }
        /// Directory sectors are contiguous in files written by this writer.
        func dirEntryOffset(_ i: Int) -> Int { sectorOffset(dirStart) + 128 * i }
        func fatEntryOffset(_ s: Int) -> Int { sectorOffset(fatSectors[s / (sectorSize / 4)]) + (s % (sectorSize / 4)) * 4 }
        func miniFATEntryOffset(_ m: Int) -> Int { sectorOffset(miniFATStart! + m / (sectorSize / 4)) + (m % (sectorSize / 4)) * 4 }
    }

    static let freeSect: UInt32 = 0xFFFF_FFFF
    static let endOfChain: UInt32 = 0xFFFF_FFFE
    static let fatSect: UInt32 = 0xFFFF_FFFD
    static let difSect: UInt32 = 0xFFFF_FFFC
    static let noStream: UInt32 = 0xFFFF_FFFF

    private struct Entry {
        var name: String
        var type: UInt8
        var data: Data?
        var path: String
        var children: [Int] = []
        var left = noStream, right = noStream, child = noStream
        var start: UInt32 = endOfChain
        var size: UInt64 = 0
    }

    func build() -> (Data, Layout) {
        let ss = majorVersion == 4 ? 4096 : 512
        let perSector = ss / 4
        // Flatten the tree.
        var entries = [Entry(name: "Root Entry", type: 5, data: nil, path: "")]
        func add(_ ns: [Node], parent: Int, prefix: String) {
            for n in ns {
                switch n {
                case .stream(let name, let d):
                    let p = prefix.isEmpty ? name : prefix + "/" + name
                    entries.append(Entry(name: name, type: 2, data: d, path: p))
                    entries[parent].children.append(entries.count - 1)
                case .storage(let name, let kids):
                    let p = prefix.isEmpty ? name : prefix + "/" + name
                    entries.append(Entry(name: name, type: 1, data: nil, path: p))
                    let me = entries.count - 1
                    entries[parent].children.append(me)
                    add(kids, parent: me, prefix: p)
                }
            }
        }
        add(nodes, parent: 0, prefix: "")
        // Sibling chains: child → first, each → right → next.
        for i in entries.indices where !entries[i].children.isEmpty {
            let kids = entries[i].children
            entries[i].child = UInt32(kids[0])
            for (k, c) in kids.enumerated() where k + 1 < kids.count { entries[c].right = UInt32(kids[k + 1]) }
        }
        // Mini stream.
        var miniStream = Data()
        var miniFAT: [UInt32] = []
        var layout = Layout(sectorSize: ss, fatSectors: [], difatSectors: [], dirStart: 0, dirSectorCount: 0)
        for (i, e) in entries.enumerated() {
            if i > 0 { layout.entryIndex[e.path] = i }
            guard let d = e.data, d.count < 4096, !d.isEmpty else { continue }
            let first = miniStream.count / 64
            let n = (d.count + 63) / 64
            for k in 0..<n { miniFAT.append(k + 1 < n ? UInt32(first + k + 1) : CFBWriter.endOfChain) }
            miniStream.append(d)
            miniStream.append(Data(count: n * 64 - d.count))
            entries[i].start = UInt32(first)
            entries[i].size = UInt64(d.count)
            layout.streamStart[e.path] = first
            layout.isMini[e.path] = true
        }
        let dirSectors = (entries.count * 128 + ss - 1) / ss
        let miniFATSectors = (miniFAT.count * 4 + ss - 1) / ss
        let miniStreamSectors = (miniStream.count + ss - 1) / ss
        let big = entries.enumerated().filter { ($0.element.data?.count ?? 0) >= 4096 }
        let bigSectors = big.reduce(0) { $0 + ($1.element.data!.count + ss - 1) / ss }
        let other = dirSectors + miniFATSectors + miniStreamSectors + bigSectors + paddingSectors
        var F = 1, D = 0
        while true {
            let total = F + D + other
            let f2 = (total + perSector - 1) / perSector
            let d2 = f2 > 109 ? (f2 - 109 + perSector - 2) / (perSector - 1) : 0
            if f2 == F && d2 == D { break }
            F = f2; D = d2
        }
        var next = 0
        func take(_ n: Int) -> Int { defer { next += n }; return next }
        layout.fatSectors = Array(take(F)..<(F))
        let difatStart = take(D)
        layout.difatSectors = Array(difatStart..<(difatStart + D))
        layout.dirStart = take(dirSectors)
        layout.dirSectorCount = dirSectors
        let miniFATStart = miniFATSectors > 0 ? take(miniFATSectors) : -1
        layout.miniFATStart = miniFATSectors > 0 ? miniFATStart : nil
        let miniStreamStart = miniStreamSectors > 0 ? take(miniStreamSectors) : -1
        var bigStart: [Int: Int] = [:]
        for (i, e) in big {
            let n = (e.data!.count + ss - 1) / ss
            bigStart[i] = take(n)
            entries[i].start = UInt32(bigStart[i]!)
            entries[i].size = UInt64(e.data!.count)
            layout.streamStart[e.path] = bigStart[i]!
            layout.isMini[e.path] = false
        }
        _ = take(paddingSectors)
        let totalSectors = next

        // FAT.
        var fat = [UInt32](repeating: CFBWriter.freeSect, count: F * perSector)
        for s in layout.fatSectors { fat[s] = CFBWriter.fatSect }
        for s in layout.difatSectors { fat[s] = CFBWriter.difSect }
        func chain(_ start: Int, _ n: Int) { for k in 0..<n { fat[start + k] = k + 1 < n ? UInt32(start + k + 1) : CFBWriter.endOfChain } }
        chain(layout.dirStart, dirSectors)
        if miniFATSectors > 0 { chain(miniFATStart, miniFATSectors) }
        if miniStreamSectors > 0 { chain(miniStreamStart, miniStreamSectors) }
        for (i, e) in big { chain(bigStart[i]!, (e.data!.count + ss - 1) / ss) }
        entries[0].start = miniStreamSectors > 0 ? UInt32(miniStreamStart) : CFBWriter.endOfChain
        entries[0].size = UInt64(miniStream.count)

        // Assemble.
        var out = Data(count: ss * (totalSectors + 1))
        func put16(_ o: Int, _ v: UInt16) { out[o] = UInt8(v & 0xff); out[o + 1] = UInt8(v >> 8) }
        func put32(_ o: Int, _ v: UInt32) { for k in 0..<4 { out[o + k] = UInt8((v >> (8 * UInt32(k))) & 0xff) } }
        func put64(_ o: Int, _ v: UInt64) { for k in 0..<8 { out[o + k] = UInt8((v >> (8 * UInt64(k))) & 0xff) } }
        out.replaceSubrange(0..<8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        put16(24, 0x3E)
        put16(26, UInt16(majorVersion))
        put16(28, 0xFFFE)
        put16(30, majorVersion == 4 ? 12 : 9)
        put16(32, 6)
        put32(40, majorVersion == 4 ? UInt32(dirSectors) : 0)
        put32(44, UInt32(F))
        put32(48, UInt32(layout.dirStart))
        put32(56, 4096)
        put32(60, miniFATSectors > 0 ? UInt32(miniFATStart) : CFBWriter.endOfChain)
        put32(64, UInt32(miniFATSectors))
        put32(68, D > 0 ? UInt32(difatStart) : CFBWriter.endOfChain)
        put32(72, UInt32(D))
        for i in 0..<109 { put32(76 + 4 * i, i < F ? UInt32(layout.fatSectors[i]) : CFBWriter.freeSect) }
        // DIFAT sectors.
        var remaining = Array(layout.fatSectors.dropFirst(109))
        for (k, s) in layout.difatSectors.enumerated() {
            let base = layout.sectorOffset(s)
            for j in 0..<(perSector - 1) { put32(base + 4 * j, remaining.isEmpty ? CFBWriter.freeSect : UInt32(remaining.removeFirst())) }
            put32(base + 4 * (perSector - 1), k + 1 < D ? UInt32(layout.difatSectors[k + 1]) : CFBWriter.endOfChain)
        }
        // FAT sectors.
        for (k, s) in layout.fatSectors.enumerated() {
            for j in 0..<perSector { put32(layout.sectorOffset(s) + 4 * j, fat[k * perSector + j]) }
        }
        // Directory (unused slots: empty entries with no siblings).
        for i in 0..<(dirSectors * ss / 128) {
            let o = layout.dirEntryOffset(i)
            guard i < entries.count else {
                put32(o + 68, CFBWriter.noStream); put32(o + 72, CFBWriter.noStream); put32(o + 76, CFBWriter.noStream)
                continue
            }
            let e = entries[i]
            let units = Array(e.name.utf16.prefix(31))
            for (k, u) in units.enumerated() { put16(o + 2 * k, u) }
            put16(o + 64, UInt16((units.count + 1) * 2))
            out[o + 66] = e.type
            out[o + 67] = 1
            put32(o + 68, e.left); put32(o + 72, e.right); put32(o + 76, e.child)
            put32(o + 116, e.type == 1 ? 0 : e.start)
            put64(o + 120, e.size)
        }
        // Mini FAT, mini stream and regular streams.
        if miniFATSectors > 0 {
            for (k, v) in miniFAT.enumerated() { put32(layout.sectorOffset(miniFATStart) + 4 * k, v) }
            for k in miniFAT.count..<(miniFATSectors * perSector) { put32(layout.sectorOffset(miniFATStart) + 4 * k, CFBWriter.freeSect) }
        }
        if miniStreamSectors > 0 {
            let o = layout.sectorOffset(miniStreamStart)
            out.replaceSubrange(o..<(o + miniStream.count), with: miniStream)
        }
        for (i, e) in big {
            let o = layout.sectorOffset(bigStart[i]!)
            out.replaceSubrange(o..<(o + e.data!.count), with: e.data!)
        }
        return (out, layout)
    }
}

enum TestData {
    static func utf16LE(_ s: String) -> Data {
        var d = Data()
        for u in s.utf16 { d.append(UInt8(u & 0xff)); d.append(UInt8(u >> 8)) }
        return d
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return c ^ 0xFFFF_FFFF
    }

    /// A tiny, well-formed PNG (IHDR, IDAT, IEND with correct CRCs).
    static func png(width: UInt32 = 2, height: UInt32 = 2) -> Data {
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
            let t = Array(type.utf8)
            return be(UInt32(data.count)) + t + data + be(crc32(t + data))
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(width) + be(height) + [8, 2, 0, 0, 0])
        // Stored (uncompressed) zlib block of the raw scanlines.
        let raw = [UInt8](repeating: 0x80, count: Int(height) * (1 + Int(width) * 3))
        var adlerA: UInt32 = 1, adlerB: UInt32 = 0
        for b in raw { adlerA = (adlerA + UInt32(b)) % 65521; adlerB = (adlerB + adlerA) % 65521 }
        let len = UInt16(raw.count)
        var z: [UInt8] = [0x78, 0x01, 0x01, UInt8(len & 0xff), UInt8(len >> 8), UInt8(~len & 0xff), UInt8(~len >> 8)]
        z += raw
        z += be((adlerB << 16) | adlerA)
        out += chunk("IDAT", z)
        out += chunk("IEND", [])
        return Data(out)
    }

    /// Text resembling a BasicFileInfo stream: UTF-16LE strings separated by binary noise.
    static func basicFileInfo(_ strings: [String]) -> Data {
        var d = Data([0x0A, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
        for (k, s) in strings.enumerated() {
            d.append(contentsOf: [UInt8(truncatingIfNeeded: s.count), 0x00, 0x00, 0x00])
            d.append(utf16LE(s))
            d.append(contentsOf: [0x00, 0x00, UInt8(k & 0xff), 0x07])
        }
        return d
    }

    /// A synthetic Revit-like container (no Revit content): preview and file info streams plus a few other streams.
    static func revitContainer(majorVersion: Int = 3, previewPrefix: Int = 300, info: [String]? = nil, preview: Data? = TestData.png(),
                               largeStream: Int = 0) -> Data {
        var w = CFBWriter()
        w.majorVersion = majorVersion
        var previewStream = Data(repeating: 0x11, count: previewPrefix)
        if let preview { previewStream.append(preview) }
        previewStream.append(Data(repeating: 0x22, count: 40))
        let infoData = basicFileInfo(info ?? ["Worksharing: Not enabled", "Username: ", "Autodesk Revit 2024 (Build: 20230308_1635(x64))",
                                             "Format: 2024", "Build: 20230308_1635(x64)", "C:\\Projects\\Small House.rvt"])
        w.nodes = [
            .stream("BasicFileInfo", infoData),
            .stream("RevitPreview4.0", previewStream),
            .stream("TransmissionData", Data(repeating: 0x33, count: 90)),
            .storage("Formats", [.stream("Latest", Data(repeating: 0x44, count: 5000))]),
            .storage("Global", [.stream("ElemTable", Data(repeating: 0x55, count: 200)), .stream("Latest", Data(repeating: 0x66, count: largeStream))]),
        ]
        return w.build().0
    }
}

/// Deterministic pseudo-random numbers for fuzz tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
