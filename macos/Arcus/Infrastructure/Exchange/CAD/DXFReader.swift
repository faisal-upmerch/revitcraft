import Foundation
import ArcusGeometry
import ArcusDomain

/// Native DXF reader (ASCII and binary DXF, R12 through 2018).
///
/// Parsing is a single streaming pass over the bytes (linear time, no backtracking), checks `isCancelled`
/// periodically and never trusts counts stored in the file for allocation. Corrupt input yields either a
/// `CADError` (when nothing usable could be read) or a partial document with warnings.
public enum DXFReader {
    public static func read(_ data: Data, fileName: String, options: CADReadOptions = .init(),
                            progress: @Sendable (Double) -> Void = { _ in },
                            isCancelled: @Sendable () -> Bool = { false }) throws -> CADDocument {
        try withoutActuallyEscaping(progress) { progress in
            try withoutActuallyEscaping(isCancelled) { isCancelled in
                try data.withUnsafeBytes { raw -> CADDocument in
                    let buf = raw.bindMemory(to: UInt8.self)
                    let parser = try DXFParser(bytes: buf, fileName: fileName, options: options, progress: progress, isCancelled: isCancelled)
                    return try parser.parse()
                }
            }
        }
    }

    /// True if the data starts like a DXF file (ASCII group "0 SECTION"/comment, or the binary sentinel).
    public static func looksLikeDXF(_ data: Data) -> Bool {
        if data.starts(with: Array("AutoCAD Binary DXF".utf8)) { return true }
        let head = String(decoding: data.prefix(256), as: UTF8.self)
        let lines = head.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2 else { return false }
        return (lines[0] == "0" && lines[1].uppercased() == "SECTION") || lines[0] == "999"
    }
}

/// One group (code/value pair). Values are byte ranges into the file (or decoded numbers for binary DXF).
struct DXFGroup {
    var code: Int
    var start: Int
    var end: Int
    var num: Double
    var hasNum: Bool
    var line: Int
}

private struct DXFSyntaxError: Error { var message: String; var line: Int }

private struct BlockBuilder {
    var name: String
    var base: Vec2
    var flags: Int
    var xrefPath: String?
    var ownerHandle: String
    var entities: [CADEntity] = []
}

private struct LayoutObject {
    var name: String = ""
    var recordHandle: String = ""
    var paper: Vec2?
    var tabOrder: Int = 0
}

final class DXFParser {
    let b: UnsafeBufferPointer<UInt8>
    let n: Int
    let fileName: String
    let options: CADReadOptions
    let progress: @Sendable (Double) -> Void
    let isCancelled: @Sendable () -> Bool

    // Tokenizer state.
    private var pos = 0
    private var line = 1
    private let binary: Bool
    private var binaryShortCodes = false
    private var term: UInt8 = 10
    private var pending: DXFGroup?
    private var cur = DXFGroup(code: 0, start: 0, end: 0, num: 0, hasNum: false, line: 0)
    private var tokenCount = 0
    /// A syntax error met while collecting an entity; raised on the next read so the entity read so far is kept.
    private var deferredError: DXFSyntaxError?
    private var utf8 = false
    private var encoding: String.Encoding = .windowsCP1252

    // Scratch group list for the entity being read.
    private var gs: [DXFGroup] = []

    // Results.
    private var header: [String: String] = [:]
    private var layers: [CADLayer] = []
    private var layerSlot: [String: Int] = [:]
    private var lineTypes: [CADLineType] = []
    private var styles: [CADTextStyle] = []
    private var blockRecords: [String: String] = [:]   // handle → name
    private var blocks: [String: CADBlock] = [:]
    private var layoutBlocks: [String: CADBlock] = [:]
    private var modelSpace: [CADEntity] = []
    private var paperSpace: [CADEntity] = []
    private var layoutObjects: [LayoutObject] = []
    private var imageDefs: [String: String] = [:]      // handle → path
    private var imageDefOrder: [String] = []
    private var entityCounts: [String: Int] = [:]
    private var unsupported: [String: Int] = [:]
    private var warnings: [String] = []
    private var invalidCount = 0
    private var invalidTypes: [String: Int] = [:]
    private var totalEntities = 0
    private var sawEOF = false
    private var sawSection = false
    private var truncated = false
    private var hasImages = false

    init(bytes: UnsafeBufferPointer<UInt8>, fileName: String, options: CADReadOptions,
         progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool) throws {
        self.b = bytes; self.n = bytes.count; self.fileName = fileName; self.options = options
        self.progress = progress; self.isCancelled = isCancelled
        let sentinel = Array("AutoCAD Binary DXF\r\n\u{1A}\0".utf8)
        if n >= sentinel.count && (0..<sentinel.count).allSatisfy({ bytes[$0] == sentinel[$0] }) {
            binary = true
            pos = sentinel.count
            // R12 binary DXF uses 1-byte group codes; R13+ uses 2-byte codes. "0 SECTION" disambiguates.
            binaryShortCodes = !(pos + 1 < n && bytes[pos] == 0 && bytes[pos + 1] == 0)
        } else {
            binary = false
            if n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { pos = 3; utf8 = true }
            // Old Mac files use CR-only line ends.
            let probe = min(n, 4096)
            var hasLF = false, hasCR = false
            for i in pos..<probe { if bytes[i] == 10 { hasLF = true; break }; if bytes[i] == 13 { hasCR = true } }
            if !hasLF && hasCR { term = 13 }
        }
    }

    // MARK: Tokenizer

    /// Reads the next group into `cur`. Returns false at end of input.
    private func next() throws -> Bool {
        if let p = pending { cur = p; pending = nil; return true }
        if let e = deferredError { throw e }
        tokenCount += 1
        if tokenCount & 0x3FFF == 0 {
            if isCancelled() { throw CancellationError() }
            progress(n > 0 ? Double(pos) / Double(n) : 1)
        }
        return binary ? try nextBinary() : try nextASCII()
    }

    private func nextASCII() throws -> Bool {
        guard pos < n else { return false }
        let codeLine = line
        var i = pos
        while i < n && (b[i] == 32 || b[i] == 9) { i += 1 }
        var neg = false
        if i < n && b[i] == 45 { neg = true; i += 1 }
        var code = 0, digits = 0
        while i < n && b[i] >= 48 && b[i] <= 57 && digits < 7 { code = code * 10 + Int(b[i] - 48); i += 1; digits += 1 }
        while i < n && (b[i] == 32 || b[i] == 9 || b[i] == 13) && b[i] != term { i += 1 }
        if i >= n {
            if digits > 0 { truncated = true }
            pos = n
            return false
        }
        guard b[i] == term, digits > 0 else {
            if digits == 0 && b[i] == term {
                // Blank line: tolerated only as trailing whitespace at the end of the file.
                var j = i
                while j < n && (b[j] == 10 || b[j] == 13 || b[j] == 32 || b[j] == 9 || b[j] == 0) { j += 1 }
                if j >= n { pos = n; return false }
            }
            throw DXFSyntaxError(message: "Invalid group code", line: codeLine)
        }
        let vStart = i + 1
        var vEnd: Int
        if vStart >= n {
            truncated = true
            pos = n
            return false
        }
        if let p = memchr(b.baseAddress! + vStart, Int32(term), n - vStart) {
            vEnd = b.baseAddress!.distance(to: p.assumingMemoryBound(to: UInt8.self))
            pos = vEnd + 1
        } else {
            vEnd = n
            pos = n
        }
        var e = vEnd
        if e > vStart && (b[e - 1] == 13 || b[e - 1] == 10) { e -= 1 }
        line += 2
        cur = DXFGroup(code: neg ? -code : code, start: vStart, end: e, num: 0, hasNum: false, line: codeLine + 1)
        return true
    }

    private enum BinKind { case string, double, int16, int32, int64, bool, bytes }

    private func binKind(_ c: Int) -> BinKind {
        switch c {
        case 10...59, 110...149, 210...239, 460...469, 1010...1059: return .double
        case 60...79, 170...179, 270...289, 370...389, 400...409, 1060...1070: return .int16
        case 90...99, 420...429, 440...459, 1071: return .int32
        case 160...169: return .int64
        case 290...299: return binaryShortCodes ? .int16 : .bool
        case 310...319, 1004: return .bytes
        default: return .string
        }
    }

    private func nextBinary() throws -> Bool {
        guard pos < n else { return false }
        let start = pos
        var code: Int
        if binaryShortCodes {
            code = Int(b[pos]); pos += 1
            if code == 255 {
                guard pos + 2 <= n else { truncated = true; pos = n; return false }
                code = Int(Int16(bitPattern: UInt16(b[pos]) | UInt16(b[pos + 1]) << 8)); pos += 2
            }
        } else {
            guard pos + 2 <= n else { truncated = true; pos = n; return false }
            code = Int(Int16(bitPattern: UInt16(b[pos]) | UInt16(b[pos + 1]) << 8)); pos += 2
        }
        func le(_ count: Int) -> UInt64 {
            var v: UInt64 = 0
            for k in 0..<count { v |= UInt64(b[pos + k]) << (8 * UInt64(k)) }
            return v
        }
        var g = DXFGroup(code: code, start: pos, end: pos, num: 0, hasNum: true, line: start)
        switch binKind(code) {
        case .double:
            guard pos + 8 <= n else { truncated = true; pos = n; return false }
            g.num = Double(bitPattern: le(8)); pos += 8
        case .int16:
            guard pos + 2 <= n else { truncated = true; pos = n; return false }
            g.num = Double(Int16(bitPattern: UInt16(le(2)))); pos += 2
        case .int32:
            guard pos + 4 <= n else { truncated = true; pos = n; return false }
            g.num = Double(Int32(bitPattern: UInt32(le(4)))); pos += 4
        case .int64:
            guard pos + 8 <= n else { truncated = true; pos = n; return false }
            g.num = Double(Int64(bitPattern: le(8))); pos += 8
        case .bool:
            guard pos + 1 <= n else { truncated = true; pos = n; return false }
            g.num = Double(b[pos]); pos += 1
        case .bytes:
            guard pos + 1 <= n else { truncated = true; pos = n; return false }
            let len = Int(b[pos]); pos += 1
            guard pos + len <= n else { truncated = true; pos = n; return false }
            g.start = pos; g.end = pos + len; g.hasNum = false; pos += len
        case .string:
            g.hasNum = false
            if let p = memchr(b.baseAddress! + pos, 0, n - pos) {
                let e = b.baseAddress!.distance(to: p.assumingMemoryBound(to: UInt8.self))
                g.start = pos; g.end = e; pos = e + 1
            } else {
                truncated = true; pos = n; return false
            }
        }
        cur = g
        return true
    }

    // MARK: Values

    private static let pow10: [Double] = (0...22).map { pow(10.0, Double($0)) }

    func double(_ g: DXFGroup) -> Double? {
        if g.hasNum { return g.num.isFinite ? g.num : nil }
        var i = g.start
        let e = g.end
        while i < e && (b[i] == 32 || b[i] == 9) { i += 1 }
        var neg = false
        if i < e && (b[i] == 45 || b[i] == 43) { neg = b[i] == 45; i += 1 }
        var mant: UInt64 = 0, digits = 0, frac = 0, any = false
        while i < e && b[i] >= 48 && b[i] <= 57 {
            if digits < 18 { mant = mant * 10 + UInt64(b[i] - 48); if mant > 0 { digits += 1 } } else { frac -= 1 }
            i += 1; any = true
        }
        if i < e && b[i] == 46 {
            i += 1
            while i < e && b[i] >= 48 && b[i] <= 57 {
                if digits < 18 { mant = mant * 10 + UInt64(b[i] - 48); frac += 1; if mant > 0 { digits += 1 } }
                i += 1; any = true
            }
        }
        var exp = 0
        if i < e && (b[i] == 101 || b[i] == 69) {
            i += 1
            var eneg = false
            if i < e && (b[i] == 45 || b[i] == 43) { eneg = b[i] == 45; i += 1 }
            var ed = 0
            while i < e && b[i] >= 48 && b[i] <= 57 && ed < 5 { exp = exp * 10 + Int(b[i] - 48); i += 1; ed += 1 }
            if ed == 0 { return slowDouble(g) }
            if eneg { exp = -exp }
        }
        while i < e && (b[i] == 32 || b[i] == 9 || b[i] == 13) { i += 1 }
        guard any, i == e else { return slowDouble(g) }
        let p10 = exp - frac
        if mant < (1 << 53) && abs(p10) <= 22 {
            var v = Double(mant)
            v = p10 >= 0 ? v * Self.pow10[p10] : v / Self.pow10[-p10]
            return neg ? -v : v
        }
        return slowDouble(g)
    }

    private func slowDouble(_ g: DXFGroup) -> Double? {
        let s = rawString(g).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count < 64, let v = Double(s), v.isFinite else { return nil }
        // Reject textual forms Double() accepts but DXF never uses ("nan", "inf", hex floats).
        if s.lowercased().contains("n") || s.lowercased().contains("x") { return nil }
        return v
    }

    func int(_ g: DXFGroup) -> Int? {
        if g.hasNum { return g.num.isFinite && abs(g.num) < 9.2e18 ? Int(g.num) : nil }
        var i = g.start
        let e = g.end
        while i < e && (b[i] == 32 || b[i] == 9) { i += 1 }
        var neg = false
        if i < e && (b[i] == 45 || b[i] == 43) { neg = b[i] == 45; i += 1 }
        var v = 0, d = 0
        while i < e && b[i] >= 48 && b[i] <= 57 && d < 18 { v = v * 10 + Int(b[i] - 48); i += 1; d += 1 }
        while i < e && (b[i] == 32 || b[i] == 9 || b[i] == 13) { i += 1 }
        if d > 0 && i == e { return neg ? -v : v }
        // Some writers emit integers as reals.
        if let x = double(g), abs(x) < 9.2e18 { return Int(x) }
        return nil
    }

    func rawString(_ g: DXFGroup) -> String {
        guard g.end > g.start else { return "" }
        let slice = UnsafeBufferPointer(rebasing: b[g.start..<g.end])
        var ascii = true
        for c in slice where c >= 0x80 { ascii = false; break }
        if ascii || utf8 {
            return String(decoding: slice, as: UTF8.self)
        }
        let data = Data(slice)
        if let s = String(data: data, encoding: encoding) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: slice, as: UTF8.self)
    }

    /// Name or text value with `\U+XXXX` escapes decoded.
    func string(_ g: DXFGroup) -> String { CADTextDecoder.decodeUnicodeEscapes(rawString(g)) }

    private func isValue(_ g: DXFGroup, _ literal: StaticString) -> Bool {
        let len = literal.utf8CodeUnitCount
        guard g.end - g.start == len else {
            // Allow trailing spaces.
            guard g.end - g.start > len else { return false }
            for k in (g.start + len)..<g.end where b[k] != 32 { return false }
            return compare(g.start, literal)
        }
        return compare(g.start, literal)
    }

    private func compare(_ start: Int, _ literal: StaticString) -> Bool {
        let p = literal.utf8Start
        for k in 0..<literal.utf8CodeUnitCount {
            var c = b[start + k]
            if c >= 97 && c <= 122 { c -= 32 }
            if c != p[k] { return false }
        }
        return true
    }

    // MARK: Group helpers (over `gs`)

    private func find(_ code: Int) -> DXFGroup? {
        for g in gs where g.code == code { return g }
        return nil
    }
    private func d(_ code: Int) -> Double? { find(code).flatMap(double) }
    private func i(_ code: Int) -> Int? { find(code).flatMap(int) }
    private func s(_ code: Int) -> String? { find(code).map(string) }
    /// Coordinate value: finite and within a sane magnitude.
    private func c(_ code: Int) -> Double? {
        guard let v = d(code), abs(v) <= 1e15 else { return nil }
        return v
    }
    private func point2(_ x: Int) -> Vec2? {
        guard let px = c(x), let py = c(x + 10) else { return nil }
        return Vec2(px, py)
    }
    private func point3(_ x: Int) -> Vec3? {
        guard let px = c(x), let py = c(x + 10) else { return nil }
        return Vec3(px, py, c(x + 20) ?? 0)
    }

    /// Collects groups up to (not including) the next code-0 group. Skips `102 {…}` application groups and xdata.
    private func collect() throws {
        gs.removeAll(keepingCapacity: true)
        var depth = 0
        do {
            while try next() {
                if cur.code == 0 { pending = cur; return }
                if cur.code == 102 {
                    if cur.end > cur.start && b[cur.start] == 123 { depth += 1 } else if depth > 0 { depth -= 1 }
                    continue
                }
                if depth > 0 || cur.code >= 1000 { continue }
                gs.append(cur)
            }
        } catch let e as DXFSyntaxError {
            deferredError = e
        }
    }

    // MARK: Driver

    func parse() throws -> CADDocument {
        guard n > 0 else { throw CADError("The file is empty.") }
        do {
            try parseTopLevel()
        } catch let e as DXFSyntaxError {
            if !sawSection { throw CADError("This file is not a readable DXF file (\(e.message.lowercased())).", line: e.line) }
            warnings.append("\(e.message) at line \(e.line); the rest of the file was ignored and the drawing may be incomplete.")
        }
        if !sawSection { throw CADError("This file is not a readable DXF file (no sections found).") }
        if truncated || !sawEOF {
            warnings.append("The file ends unexpectedly (truncated at about line \(line)); content after that point is missing.")
        }
        progress(1)
        return finish()
    }

    private func parseTopLevel() throws {
        while try next() {
            guard cur.code == 0 else { continue }
            if isValue(cur, "SECTION") {
                guard try next() else { return }
                guard cur.code == 2 else { pending = cur; continue }
                sawSection = true
                let name = rawString(cur).uppercased().trimmingCharacters(in: .whitespaces)
                switch name {
                case "HEADER": try parseHeader()
                case "TABLES": try parseTables()
                case "BLOCKS": try parseBlocks()
                case "ENTITIES": try parseEntities()
                case "OBJECTS": try parseObjects()
                default: try skipSection()
                }
            } else if isValue(cur, "EOF") {
                sawEOF = true
                return
            }
        }
    }

    /// True when the current code-0 token ends the section (ENDSEC), or starts a new one / EOF (missing ENDSEC).
    private func atSectionEnd() -> Bool {
        if isValue(cur, "ENDSEC") { return true }
        if isValue(cur, "SECTION") || isValue(cur, "EOF") { pending = cur; return true }
        return false
    }

    private func skipSection() throws {
        while try next() {
            if cur.code == 0 && atSectionEnd() { return }
        }
    }

    // MARK: HEADER

    private func parseHeader() throws {
        var name = ""
        var values: [String] = []
        func flush() {
            guard !name.isEmpty, header.count < 20_000 else { return }
            header[name] = values.joined(separator: ",")
            if name == "$ACADVER", let v = header[name] { applyVersion(v) }
            if name == "$DWGCODEPAGE", let v = header[name], !utf8 { encoding = DXFParser.encoding(forCodepage: v) }
        }
        while try next() {
            if cur.code == 0 {
                flush()
                if isValue(cur, "ENDSEC") { return }
                pending = cur
                return
            }
            if cur.code == 9 {
                flush()
                name = rawString(cur).trimmingCharacters(in: .whitespaces)
                values = []
            } else if values.count < 16 {
                if cur.hasNum { values.append(DXFParser.format(cur.num)) } else { values.append(rawString(cur).trimmingCharacters(in: .whitespaces)) }
            }
        }
        flush()
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 { return String(Int64(v)) }
        return String(v)
    }

    private func applyVersion(_ v: String) {
        let code = v.uppercased()
        if code >= "AC1021" && code.hasPrefix("AC") { utf8 = true }
    }

    static func encoding(forCodepage cp: String) -> String.Encoding {
        let u = cp.uppercased().replacingOccurrences(of: "ANSI_", with: "").replacingOccurrences(of: "DOS", with: "")
        func cf(_ e: CFStringEncodings) -> String.Encoding {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue)))
        }
        switch u {
        case "1250": return .windowsCP1250
        case "1251": return .windowsCP1251
        case "1253": return .windowsCP1253
        case "1254": return .windowsCP1254
        case "1255": return cf(.windowsHebrew)
        case "1256": return cf(.windowsArabic)
        case "1257": return cf(.windowsBalticRim)
        case "1258": return cf(.windowsVietnamese)
        case "874": return cf(.dosThai)
        case "932": return .shiftJIS
        case "936": return cf(.GB_18030_2000)
        case "949": return cf(.dosKorean)
        case "950": return cf(.big5)
        case "UTF8", "UTF-8": return .utf8
        default: return .windowsCP1252
        }
    }

    // MARK: TABLES

    private func parseTables() throws {
        while try next() {
            guard cur.code == 0 else { continue }
            if atSectionEnd() { return }
            let type = rawString(cur).uppercased()
            try collect()
            switch type {
            case "LAYER": readLayer()
            case "LTYPE": readLineType()
            case "STYLE": readStyle()
            case "BLOCK_RECORD":
                if let h = s(5), let name = s(2) { blockRecords[h.uppercased()] = name }
            default: break
            }
        }
    }

    private func readLayer() {
        guard let name = s(2), !name.isEmpty else { return }
        let flags = i(70) ?? 0
        let color = i(62) ?? 7
        var lw: Double?
        if let w = i(370), w >= 0, w <= 211 { lw = Double(w) / 100 }
        let tc = i(420).map(ACIColor.trueColor)
        var plots = true
        if let p = i(290) { plots = p != 0 }
        let layer = CADLayer(name: name, colorIndex: color == 0 ? 7 : abs(color), trueColor: tc, lineType: s(6) ?? "Continuous", lineWeight: lw,
                             isOn: color >= 0, isFrozen: flags & 1 != 0, isLocked: flags & 4 != 0, plots: plots)
        let key = name.uppercased()
        if let idx = layerSlot[key] { layers[idx] = layer } else { layerSlot[key] = layers.count; layers.append(layer) }
    }

    private func readLineType() {
        guard let name = s(2) else { return }
        var pattern: [Double] = []
        for g in gs where g.code == 49 { if let v = double(g), pattern.count < 64 { pattern.append(v) } }
        lineTypes.append(CADLineType(name: name, description: s(3) ?? "", pattern: pattern))
    }

    private func readStyle() {
        let name = s(2) ?? ""
        let flags = i(70) ?? 0
        let font = s(3) ?? ""
        styles.append(CADTextStyle(name: name, fontFile: font, bigFontFile: s(4) ?? "", isShapeFile: flags & 1 != 0))
    }

    // MARK: BLOCKS

    private func parseBlocks() throws {
        var current: BlockBuilder?
        while try next() {
            guard cur.code == 0 else { continue }
            if atSectionEnd() {
                if let c = current { store(c) }
                return
            }
            if isValue(cur, "BLOCK") {
                if let c = current { store(c) }
                try collect()
                let name = s(2) ?? s(3) ?? ""
                let flags = i(70) ?? 0
                var path = s(1)
                if path?.isEmpty == true { path = nil }
                current = BlockBuilder(name: name, base: point2(10) ?? .zero, flags: flags, xrefPath: path, ownerHandle: (s(330) ?? "").uppercased())
                continue
            }
            if isValue(cur, "ENDBLK") {
                try collect()
                if let c = current { store(c) }
                current = nil
                continue
            }
            let type = rawString(cur).uppercased()
            if let e = try readEntity(type) {
                if current != nil { current!.entities.append(e) } else { modelSpace.append(e) }
            }
        }
        if let c = current { store(c) }
    }

    private func store(_ bb: BlockBuilder) {
        guard !bb.name.isEmpty else { return }
        let isXref = bb.flags & 4 != 0 || bb.flags & 8 != 0
        let block = CADBlock(name: bb.name, basePoint: bb.base, entities: bb.entities, isXref: isXref,
                             xrefPath: isXref ? (bb.xrefPath ?? "") : nil, isAnonymous: bb.flags & 1 != 0 || bb.name.hasPrefix("*"),
                             recordHandle: bb.ownerHandle)
        let u = bb.name.uppercased()
        if u.hasPrefix("*MODEL_SPACE") || u.hasPrefix("*PAPER_SPACE") || u == "$MODEL_SPACE" || u.hasPrefix("$PAPER_SPACE") {
            layoutBlocks[bb.name] = block
        } else {
            blocks[bb.name] = block
        }
    }

    // MARK: ENTITIES

    private func parseEntities() throws {
        while try next() {
            guard cur.code == 0 else { continue }
            if atSectionEnd() { return }
            let type = rawString(cur).uppercased()
            if let e = try readEntity(type) {
                if e.props.paperSpace { paperSpace.append(e) } else { modelSpace.append(e) }
            }
        }
    }

    private func count(_ type: String) throws {
        totalEntities += 1
        entityCounts[type, default: 0] += 1
        if totalEntities > options.maxEntities {
            throw CADError("The drawing contains more than \(options.maxEntities) entities, which exceeds the import limit.")
        }
    }

    private func invalid(_ type: String) {
        invalidCount += 1
        invalidTypes[type, default: 0] += 1
    }

    private static let noBoundsTypes: Set<String> = [
        "3DSOLID", "REGION", "BODY", "SURFACE", "EXTRUDEDSURFACE", "LOFTEDSURFACE", "REVOLVEDSURFACE", "SWEPTSURFACE",
        "PLANESURFACE", "NURBSURFACE", "MESH", "XLINE", "RAY", "VIEWPORT", "WIPEOUT", "OLE2FRAME", "OLEFRAME", "LIGHT", "SUN",
        "PDFUNDERLAY", "DWFUNDERLAY", "DGNUNDERLAY", "SECTIONOBJECT", "HELIX", "ACAD_TABLE", "TABLE", "ARCALIGNEDTEXT", "RTEXT",
    ]

    /// Reads one entity whose type token was just consumed. Returns nil for entities that produce nothing.
    private func readEntity(_ type: String) throws -> CADEntity? {
        try collect()
        switch type {
        case "VERTEX", "SEQEND", "ATTRIB":
            // Orphaned sub-entities (their owner was malformed); ignore.
            return nil
        case "ENDBLK", "BLOCK", "ENDSEC", "EOF", "SECTION":
            return nil
        default: break
        }
        try count(type)
        let p = props()
        switch type {
        case "LINE":
            guard let a = point3(10), let e = point3(11) else { invalid(type); return nil }
            return .line(a, e, p)
        case "POINT":
            guard let a = point3(10) else { invalid(type); return nil }
            return .point(a, p)
        case "CIRCLE":
            guard let ctr = point2(10), let r = c(40), r > 0 else { invalid(type); return nil }
            return mapCircle(ctr, r, 0, Angle.twoPi, full: true, p)
        case "ARC":
            guard let ctr = point2(10), let r = c(40), r > 0, let sa = d(50), let ea = d(51) else { invalid(type); return nil }
            return mapCircle(ctr, r, Angle.radians(sa), Angle.radians(ea), full: false, p)
        case "ELLIPSE": return readEllipse(p)
        case "LWPOLYLINE": return readLWPolyline(p)
        case "POLYLINE": return try readPolyline(p)
        case "SPLINE": return readSpline(p)
        case "TEXT":
            guard let t = readText(verticalCode: 73) else { invalid(type); return nil }
            return .text(t, p)
        case "ATTDEF":
            guard let t = readText(verticalCode: 74) else { invalid(type); return nil }
            let flags = i(70) ?? 0
            return .attributeDefinition(CADAttribute(tag: s(2) ?? "", text: t, isInvisible: flags & 1 != 0, isConstant: flags & 2 != 0, prompt: s(3) ?? ""), p)
        case "MTEXT": return readMText(p)
        case "HATCH": return readHatch(p)
        case "SOLID", "TRACE":
            guard let a = point2(10), let b2 = point2(11), let c3 = point2(12) else { invalid(type); return nil }
            let d4 = point2(13) ?? c3
            var pts = [a, b2, d4, c3]
            if d4.isAlmostEqual(c3, tolerance: 0) { pts = [a, b2, c3] }
            if let t = ocs() { pts = pts.map(t.apply) }
            return .solid(pts, p)
        case "3DFACE":
            guard let a = point3(10), let b2 = point3(11), let c3 = point3(12) else { invalid(type); return nil }
            let d4 = point3(13) ?? c3
            return .face3D(d4.isAlmostEqual(c3, tolerance: 0) ? [a, b2, c3] : [a, b2, c3, d4], p)
        case "INSERT": return try readInsert(p)
        case "DIMENSION", "ARC_DIMENSION", "LARGE_RADIAL_DIMENSION": return readDimension(p)
        case "LEADER":
            var pts: [Vec2] = []
            var x: Double?
            for g in gs {
                if g.code == 10 { x = double(g) } else if g.code == 20, let xx = x, let y = double(g), abs(xx) <= 1e15, abs(y) <= 1e15 { pts.append(Vec2(xx, y)); x = nil }
            }
            guard pts.count >= 2 else { invalid(type); return nil }
            return .leader(points: pts, arrow: (i(71) ?? 1) != 0, p)
        case "MULTILEADER", "MLEADER": return readMultiLeader(p)
        case "IMAGE":
            guard let o = point2(10), let u = point2(11), let v = point2(12) else { invalid(type); return nil }
            let w = max(1, c(13) ?? 1), h = max(1, c(23) ?? 1)
            let corners = [o, o + u * w, o + u * w + v * h, o + v * h]
            hasImages = true
            return .image(path: "\u{1}" + (s(340) ?? "").uppercased(), corners: corners, p)
        case "ACAD_PROXY_ENTITY":
            unsupported[type, default: 0] += 1
            return .proxy(typeName: type, bounds: gatherBounds(), p)
        default:
            unsupported[type, default: 0] += 1
            if DXFParser.noBoundsTypes.contains(type) { return .unsupported(typeName: type, p) }
            if let r = gatherBounds() { return .proxy(typeName: type, bounds: r, p) }
            return .unsupported(typeName: type, p)
        }
    }

    /// Bounds from any coordinate pairs of an unknown entity (codes 10…18 / 20…28).
    private func gatherBounds() -> Rect2? {
        var r = Rect2.empty
        var xs: [Int: Double] = [:]
        for g in gs {
            if g.code >= 10 && g.code <= 18 { xs[g.code] = double(g) } else if g.code >= 20 && g.code <= 28, let x = xs[g.code - 10], let y = double(g),
                abs(x) <= 1e15, abs(y) <= 1e15 {
                r.include(Vec2(x, y))
                xs[g.code - 10] = nil
            }
        }
        return r.isEmpty ? nil : r
    }

    private func props() -> CADEntityProps {
        var p = CADEntityProps()
        var ownerSet = false
        for g in gs {
            switch g.code {
            case 5: p.handle = rawString(g).trimmingCharacters(in: .whitespaces).uppercased()
            case 8: p.layer = string(g)
            case 6:
                let lt = string(g)
                p.lineType = lt.uppercased() == "BYLAYER" ? nil : lt
            case 62:
                if let v = int(g) {
                    if v == 0 { p.color = .byBlock } else if v == 256 { p.color = .byLayer } else if abs(v) <= 255 { p.color = .index(abs(v)) }
                }
            case 420:
                if let v = int(g) { p.color = .rgb(ACIColor.trueColor(v)) }
            case 370:
                if let v = int(g) {
                    if v >= 0 && v <= 211 { p.lineWeight = Double(v) / 100 } else if v == -2 { p.lineWeightByBlock = true }
                }
            case 67: p.paperSpace = (int(g) ?? 0) == 1
            case 330:
                if !ownerSet { p.owner = rawString(g).uppercased(); ownerSet = true }
            default: break
            }
        }
        if p.layer.isEmpty { p.layer = "0" }
        return p
    }

    private func extrusion() -> Vec3? {
        guard let x = d(210), let y = d(220), let z = d(230) else { return nil }
        return Vec3(x, y, z)
    }

    private func ocs(elevation: Double = 0) -> Transform2? {
        extrusion().flatMap { CADGeometry.ocsTransform($0, elevation: elevation) }
    }

    private func mapCircle(_ c: Vec2, _ r: Double, _ s: Double, _ e: Double, full: Bool, _ p: CADEntityProps) -> CADEntity {
        guard let t = ocs(elevation: d(30) ?? 0) else {
            return full ? .circle(center: c, radius: r, p) : .arc(center: c, radius: r, startAngle: s, endAngle: e, p)
        }
        let m = CADGeometry.mapArc(center: c, radius: r, start: s, end: e, t)
        if let a = m.arc { return full ? .circle(center: a.0, radius: a.1, p) : .arc(center: a.0, radius: a.1, startAngle: a.2, endAngle: a.3, p) }
        return .ellipse(m.ellipse!, p)
    }

    private func readEllipse(_ p: CADEntityProps) -> CADEntity? {
        guard let ctr = point2(10), var major = point2(11), var ratio = c(40), ratio > 0, major.length > 0 else { invalid("ELLIPSE"); return nil }
        var s = d(41) ?? 0, e = d(42) ?? Angle.twoPi
        if ratio > 1 {
            // Normalize: the "major" axis given is the minor one.
            major = major.perpendicular * ratio
            ratio = 1 / ratio
            s -= .pi / 2; e -= .pi / 2
        }
        if let n = extrusion(), n.z < 0 {
            // Parameters run clockwise when viewed from +Z.
            let ns = -e, ne = -s
            s = ns; e = ne
        }
        return .ellipse(Ellipse2(center: ctr, majorAxis: major, ratio: min(1, ratio), startParam: s, endParam: e), p)
    }

    private func readLWPolyline(_ p: CADEntityProps) -> CADEntity? {
        var pts: [Vec3] = []
        var bulges: [Double] = []
        var x: Double?
        let elev = d(38) ?? 0
        var bad = false
        for g in gs {
            switch g.code {
            case 10: x = double(g)
            case 20:
                if let xx = x, let y = double(g), abs(xx) <= 1e15, abs(y) <= 1e15 { pts.append(Vec3(xx, y, elev)); bulges.append(0) } else { bad = true }
                x = nil
            case 42:
                if !bulges.isEmpty, let v = double(g), abs(v) < 1e6 { bulges[bulges.count - 1] = v }
            default: break
            }
        }
        guard !pts.isEmpty, !(bad && pts.count < 2) else { invalid("LWPOLYLINE"); return nil }
        let flags = i(70) ?? 0
        var poly = CADPolyline(points: pts, bulges: bulges, closed: flags & 1 != 0, constantWidth: d(43) ?? 0)
        if let t = ocs(elevation: elev) {
            poly.points = poly.points.map { let q = t.apply($0.xy); return Vec3(q.x, q.y, $0.z) }
            if t.isMirroring { poly.bulges = poly.bulges.map { -$0 } }
        }
        return .polyline(poly, p)
    }

    private func readPolyline(_ p: CADEntityProps) throws -> CADEntity? {
        let flags = i(70) ?? 0
        let meshM = i(71) ?? 0, meshN = i(72) ?? 0
        let elev = d(30) ?? 0
        let t = ocs(elevation: elev)
        var pts: [Vec3] = []
        var bulges: [Double] = []
        var faces: [[Int]] = []
        let isPolyface = flags & 64 != 0
        let isMesh = flags & 16 != 0
        let is3D = flags & 8 != 0
        // Sub-entities: VERTEX … SEQEND.
        while try next() {
            guard cur.code == 0 else { continue }
            if isValue(cur, "VERTEX") {
                try collect()
                let vf = i(70) ?? 0
                if isPolyface && vf & 128 != 0 && vf & 64 == 0 {
                    var face: [Int] = []
                    for code in 71...74 { if let k = i(code), k != 0, abs(k) <= 1_000_000 { face.append(abs(k) - 1) } }
                    if face.count >= 3 { faces.append(face) }
                    continue
                }
                if vf & 16 != 0 { continue } // spline frame control point
                guard let v = point3(10) else { continue }
                pts.append(Vec3(v.x, v.y, (is3D || isMesh || isPolyface) ? v.z : elev))
                bulges.append(d(42).flatMap { abs($0) < 1e6 ? $0 : nil } ?? 0)
            } else if isValue(cur, "SEQEND") {
                try collect()
                break
            } else {
                pending = cur
                break
            }
        }
        guard !pts.isEmpty else { invalid("POLYLINE"); return nil }
        if isPolyface {
            faces = faces.filter { $0.allSatisfy { $0 >= 0 && $0 < pts.count } }
            return .polyline(CADPolyline(points: pts, closed: false, is3D: true, meshFaces: faces), p)
        }
        if isMesh, meshM > 0, meshN > 0, meshM * meshN <= pts.count {
            var fs: [[Int]] = []
            let closedM = flags & 1 != 0, closedN = flags & 32 != 0
            let mMax = closedM ? meshM : meshM - 1, nMax = closedN ? meshN : meshN - 1
            if mMax > 0 && nMax > 0 {
                for a in 0..<mMax {
                    for c in 0..<nMax {
                        let a1 = (a + 1) % meshM, c1 = (c + 1) % meshN
                        fs.append([a * meshN + c, a * meshN + c1, a1 * meshN + c1, a1 * meshN + c])
                    }
                }
            }
            return .polyline(CADPolyline(points: pts, closed: false, is3D: true, meshFaces: fs), p)
        }
        var poly = CADPolyline(points: pts, bulges: is3D ? [] : bulges, closed: flags & 1 != 0, is3D: is3D)
        if !is3D, let t {
            poly.points = poly.points.map { let q = t.apply($0.xy); return Vec3(q.x, q.y, $0.z) }
            if t.isMirroring { poly.bulges = poly.bulges.map { -$0 } }
        }
        return .polyline(poly, p)
    }

    private func readSpline(_ p: CADEntityProps) -> CADEntity? {
        let flags = i(70) ?? 0
        let degree = i(71) ?? 3
        var knots: [Double] = [], weights: [Double] = [], ctrl: [Vec2] = [], fit: [Vec2] = []
        var cx: Double?, fx: Double?
        for g in gs {
            switch g.code {
            case 40: if let v = double(g) { knots.append(v) }
            case 41: if let v = double(g) { weights.append(v) }
            case 10: cx = double(g)
            case 20: if let x = cx, let y = double(g), abs(x) <= 1e15, abs(y) <= 1e15 { ctrl.append(Vec2(x, y)) }; cx = nil
            case 11: fx = double(g)
            case 21: if let x = fx, let y = double(g), abs(x) <= 1e15, abs(y) <= 1e15 { fit.append(Vec2(x, y)) }; fx = nil
            default: break
            }
        }
        var spline: BSpline2?
        if degree >= 1 && degree <= 25 && !ctrl.isEmpty {
            let w: [Double]? = (weights.count == ctrl.count && weights.contains { $0 != 1 }) ? weights : nil
            let sp = BSpline2(degree: degree, controlPoints: ctrl, knots: knots, weights: w)
            if sp.isValid { spline = sp } else {
                let k2 = BSpline2.clampedUniformKnots(count: ctrl.count, degree: degree)
                let sp2 = BSpline2(degree: degree, controlPoints: ctrl, knots: k2, weights: w)
                if sp2.isValid { spline = sp2; warnOnce("Some splines had inconsistent knot vectors and were rebuilt with uniform knots.") }
            }
        }
        guard spline != nil || fit.count >= 2 || ctrl.count >= 2 else { invalid("SPLINE"); return nil }
        if spline == nil && fit.count < 2 { fit = ctrl }
        return .spline(spline, fitPoints: fit, closed: flags & 1 != 0, p)
    }

    private func readText(verticalCode: Int) -> CADText? {
        guard let pos = point2(10) else { return nil }
        let h = c(40) ?? 0
        guard h >= 0 else { return nil }
        var t = CADText(text: CADTextDecoder.decodeText(find(1).map(rawString) ?? ""),
                        position: pos, alignmentPoint: point2(11), height: h, rotation: Angle.radians(d(50) ?? 0),
                        widthFactor: d(41) ?? 1, style: s(7) ?? "Standard",
                        horizontal: CADHorizontalAlignment(rawValue: i(72) ?? 0) ?? .left,
                        vertical: CADVerticalAlignment(rawValue: i(verticalCode) ?? 0) ?? .baseline)
        if let tr = ocs(elevation: d(30) ?? 0) {
            t.position = tr.apply(t.position)
            t.alignmentPoint = t.alignmentPoint.map(tr.apply)
            t.rotation = tr.applyVector(Vec2.fromAngle(t.rotation)).angle
        }
        return t
    }

    private func readMText(_ p: CADEntityProps) -> CADEntity? {
        guard let pos = point2(10) else { invalid("MTEXT"); return nil }
        var raw = ""
        var last = ""
        for g in gs {
            if g.code == 3 { raw += rawString(g) } else if g.code == 1 { last = rawString(g) }
        }
        raw += last
        var rot = Angle.radians(d(50) ?? 0)
        if let dir = point2(11), dir.length > 0 { rot = dir.angle }
        let h = c(40) ?? 0
        guard h >= 0 else { invalid("MTEXT"); return nil }
        let m = CADMText(rawText: raw, plainText: CADTextDecoder.plainMText(raw), position: pos, height: h, width: max(0, c(41) ?? 0),
                         rotation: rot, attachment: min(9, max(1, i(71) ?? 1)), style: s(7) ?? "Standard", lineSpacingFactor: d(44) ?? 1)
        return .mtext(m, p)
    }

    private func readHatch(_ p: CADEntityProps) -> CADEntity? {
        var loops: [[CADHatchEdge]] = []
        var k = 0
        let n = gs.count
        let name = s(2) ?? ""
        let solid = (i(70) ?? 0) == 1
        func dv(_ idx: Int) -> Double? { idx < n ? double(gs[idx]).flatMap { abs($0) <= 1e15 ? $0 : nil } : nil }
        // Advance to the loop count (91).
        while k < n && gs[k].code != 91 { k += 1 }
        guard k < n else { invalid("HATCH"); return nil }
        k += 1
        var bad = false
        // Parse loops sequentially until the pattern/style groups start (75).
        while k < n {
            let g = gs[k]
            if g.code == 75 || g.code == 98 { break }
            guard g.code == 92 else { k += 1; continue }
            let loopType = int(g) ?? 0
            k += 1
            var edges: [CADHatchEdge] = []
            if loopType & 2 != 0 {
                // Polyline loop: 72 has-bulge, 73 closed, 93 count, then 10/20[/42].
                var closed = true
                var pts: [Vec2] = [], bul: [Double] = []
                while k < n && gs[k].code != 10 && gs[k].code != 92 && gs[k].code != 97 {
                    if gs[k].code == 73 { closed = (int(gs[k]) ?? 1) != 0 }
                    k += 1
                }
                while k < n {
                    let c = gs[k].code
                    if c == 10 {
                        if let x = dv(k), k + 1 < n, gs[k + 1].code == 20, let y = dv(k + 1) { pts.append(Vec2(x, y)); bul.append(0); k += 2 } else { bad = true; k += 1 }
                    } else if c == 42 {
                        if !bul.isEmpty, let v = dv(k), abs(v) < 1e6 { bul[bul.count - 1] = v }
                        k += 1
                    } else { break }
                }
                if pts.count >= 2 { edges.append(.polyline(pts, bulges: bul, closed: closed)) }
            } else {
                // Edge loop: 93 edge count, then 72 edge type + data.
                while k < n && gs[k].code != 72 && gs[k].code != 92 && gs[k].code != 97 && gs[k].code != 75 { k += 1 }
                while k < n && gs[k].code == 72 {
                    let et = int(gs[k]) ?? 0
                    k += 1
                    func take(_ code: Int) -> Double? {
                        guard k < n, gs[k].code == code else { return nil }
                        defer { k += 1 }
                        return dv(k)
                    }
                    switch et {
                    case 1:
                        if let x1 = take(10), let y1 = take(20), let x2 = take(11), let y2 = take(21) { edges.append(.line(Vec2(x1, y1), Vec2(x2, y2))) } else { bad = true }
                    case 2:
                        if let x = take(10), let y = take(20), let r = take(40), let sa = take(50), let ea = take(51) {
                            let ccw = (take(73) ?? 1) != 0
                            if r > 0 {
                                // Clockwise arcs store mirrored angles.
                                edges.append(ccw ? .arc(center: Vec2(x, y), radius: r, start: Angle.radians(sa), end: Angle.radians(ea), ccw: true)
                                                 : .arc(center: Vec2(x, y), radius: r, start: -Angle.radians(sa), end: -Angle.radians(ea), ccw: false))
                            } else { bad = true }
                        } else { bad = true }
                    case 3:
                        if let x = take(10), let y = take(20), let mx = take(11), let my = take(21), let ratio = take(40), let sa = take(50), let ea = take(51) {
                            let ccw = (take(73) ?? 1) != 0
                            if ratio > 0, Vec2(mx, my).length > 0 {
                                let s0 = Angle.radians(sa), e0 = Angle.radians(ea)
                                let el = ccw ? Ellipse2(center: Vec2(x, y), majorAxis: Vec2(mx, my), ratio: min(1, ratio), startParam: s0, endParam: e0)
                                             : Ellipse2(center: Vec2(x, y), majorAxis: Vec2(mx, my), ratio: min(1, ratio), startParam: -e0, endParam: -s0)
                                edges.append(.ellipse(el, ccw: ccw))
                            } else { bad = true }
                        } else { bad = true }
                    case 4:
                        // 94 degree, 73 rational, 74 periodic, 95 knots, 96 control points, 40…, 10/20[/42], 97 fit, 11/21, 12/22, 13/23
                        var degree = 3
                        var knots: [Double] = [], ctrl: [Vec2] = [], weights: [Double] = [], fit: [Vec2] = []
                        while k < n {
                            let c = gs[k].code
                            if c == 72 || c == 92 { break }
                            if c == 94 { degree = int(gs[k]) ?? 3; k += 1 }
                            else if c == 73 || c == 74 || c == 95 || c == 96 || c == 97 { k += 1 }
                            else if c == 40 { if let v = dv(k) { knots.append(v) }; k += 1 }
                            else if c == 42 { if let v = dv(k) { weights.append(v) }; k += 1 }
                            else if c == 10 { if let x = dv(k), k + 1 < n, gs[k + 1].code == 20, let y = dv(k + 1) { ctrl.append(Vec2(x, y)); k += 2 } else { k += 1 } }
                            else if c == 11 { if let x = dv(k), k + 1 < n, gs[k + 1].code == 21, let y = dv(k + 1) { fit.append(Vec2(x, y)); k += 2 } else { k += 1 } }
                            else if c == 12 || c == 13 || c == 22 || c == 23 { k += 1 }
                            else { break }
                        }
                        let w: [Double]? = weights.count == ctrl.count && !weights.isEmpty ? weights : nil
                        let sp = BSpline2(degree: degree, controlPoints: ctrl, knots: knots, weights: w)
                        if sp.isValid { edges.append(.spline(sp)) } else if fit.count >= 2 { edges.append(.polyline(fit, bulges: [], closed: false)) } else if ctrl.count >= 2 {
                            edges.append(.polyline(ctrl, bulges: [], closed: false))
                        } else { bad = true }
                    default:
                        bad = true
                    }
                }
            }
            // Source boundary object references: 97 count then 330 handles.
            while k < n && (gs[k].code == 97 || gs[k].code == 330) { k += 1 }
            if !edges.isEmpty { loops.append(edges) }
        }
        if bad { warnOnce("Some hatch boundaries had malformed edges; those edges were skipped.") }
        guard !loops.isEmpty else { invalid("HATCH"); return nil }
        var hatch = CADHatch(loops: loops, isSolid: solid || name.uppercased() == "SOLID", patternName: name,
                             patternAngle: Angle.radians(d(52) ?? 0), patternScale: d(41) ?? 1)
        if let t = ocs(elevation: c(30) ?? 0) {
            hatch.loops = hatch.loops.map { $0.map { DXFParser.map($0, t) } }
        }
        return .hatch(hatch, p)
    }

    static func map(_ e: CADHatchEdge, _ t: Transform2) -> CADHatchEdge {
        switch e {
        case .line(let a, let b): return .line(t.apply(a), t.apply(b))
        case .arc(let c, let r, let s, let en, let ccw):
            // Express as a ccw arc, map, and keep the traversal direction.
            let (s0, e0) = ccw ? (s, en) : (en, s)
            let m = CADGeometry.mapArc(center: c, radius: r, start: s0, end: e0, t)
            if let a = m.arc { return .arc(center: a.0, radius: a.1, start: a.2, end: a.3, ccw: true) }
            return .ellipse(m.ellipse!, ccw: true)
        case .ellipse(let el, let ccw): return .ellipse(el.transformed(t), ccw: ccw)
        case .spline(let s): return .spline(s.transformed(t))
        case .polyline(let pts, let bul, let closed): return .polyline(pts.map(t.apply), bulges: t.isMirroring ? bul.map { -$0 } : bul, closed: closed)
        }
    }

    private func readInsert(_ p: CADEntityProps) throws -> CADEntity? {
        guard let name = s(2), !name.isEmpty, let pos = point2(10) else { invalid("INSERT"); try skipAttributes(); return nil }
        var sx = d(41) ?? 1, sy = d(42) ?? (d(41) ?? 1)
        if !(abs(sx) > 1e-12 && abs(sx) < 1e9) { sx = 1; warnOnce("Some block references had zero or invalid scale factors; a scale of 1 was used.") }
        if !(abs(sy) > 1e-12 && abs(sy) < 1e9) { sy = 1; warnOnce("Some block references had zero or invalid scale factors; a scale of 1 was used.") }
        var ins = CADInsert(blockName: name, position: pos, scale: Vec2(sx, sy), rotation: Angle.radians(d(50) ?? 0),
                            columns: max(1, min(i(70) ?? 1, 100_000)), rows: max(1, min(i(71) ?? 1, 100_000)),
                            columnSpacing: c(44) ?? 0, rowSpacing: c(45) ?? 0)
        if let t = ocs(elevation: d(30) ?? 0) {
            let det: Double = t.isMirroring ? -1 : 1
            ins.position = t.apply(ins.position)
            ins.rotation = t.applyVector(Vec2.fromAngle(ins.rotation)).angle
            ins.scale = Vec2(ins.scale.x, ins.scale.y * det)
            ins.rowSpacing *= det
        }
        // Attributes follow as ATTRIB … SEQEND (the 66 flag is not always written, so look regardless).
        while try next() {
            if cur.code == 0 && isValue(cur, "ATTRIB") {
                try collect()
                if let t = readText(verticalCode: 74) {
                    let flags = i(70) ?? 0
                    ins.attributes.append(CADAttribute(tag: s(2) ?? "", text: t, isInvisible: flags & 1 != 0, isConstant: flags & 2 != 0))
                }
                continue
            }
            if cur.code == 0 && isValue(cur, "SEQEND") { try collect(); break }
            pending = cur
            break
        }
        return .insert(ins, p)
    }

    private func skipAttributes() throws {
        while try next() {
            if cur.code == 0 && isValue(cur, "ATTRIB") { try collect(); continue }
            if cur.code == 0 && isValue(cur, "SEQEND") { try collect(); return }
            pending = cur
            return
        }
    }

    private func readDimension(_ p: CADEntityProps) -> CADEntity? {
        let block = s(2) ?? ""
        let def = point2(10) ?? .zero
        let mid = point2(11) ?? def
        let type = i(70) ?? 0
        let measurement = d(42)
        var text = s(1) ?? ""
        let kind = type & 0x0F
        let formatted: String = measurement.map { m in
            (kind == 2 || kind == 5) ? DXFParser.formatMeasurement(Angle.degrees(m)) + "°" : DXFParser.formatMeasurement(m)
        } ?? ""
        if text.isEmpty { text = formatted } else if text == " " { text = "" } else if text.contains("<>") { text = text.replacingOccurrences(of: "<>", with: formatted) }
        text = CADTextDecoder.plainMText(text)
        guard !block.isEmpty || measurement != nil else { invalid("DIMENSION"); return nil }
        return .dimension(CADDimension(blockName: block, measurement: measurement, text: text, dimensionType: type, definitionPoint: def, textMidpoint: mid, style: s(3) ?? "Standard"), p)
    }

    static func formatMeasurement(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    private func readMultiLeader(_ p: CADEntityProps) -> CADEntity? {
        var lines: [[Vec2]] = []
        var current: [Vec2]? = nil
        var inLeader = false
        var connection: Vec2?
        var text = ""
        var textPos: Vec2?
        var height = 0.0
        var inContext = false
        var x: Double?, x12: Double?
        for g in gs {
            switch g.code {
            case 300: inContext = true
            case 301: inContext = false
            case 302: inLeader = true; connection = nil
            case 303: inLeader = false
            case 304:
                let v = rawString(g)
                if v.hasPrefix("LEADER_LINE") { current = [] } else if inContext && text.isEmpty { text = CADTextDecoder.plainMText(v) }
            case 305:
                if var c = current {
                    if let conn = connection { c.append(conn) }
                    if c.count >= 2 { lines.append(c) }
                }
                current = nil
            case 10: x = double(g)
            case 20:
                if let xx = x, let y = double(g), abs(xx) <= 1e15, abs(y) <= 1e15 {
                    if current != nil { current!.append(Vec2(xx, y)) } else if inLeader { connection = Vec2(xx, y) }
                }
                x = nil
            case 12: x12 = double(g)
            case 22:
                if inContext, textPos == nil, let xx = x12, let y = double(g), abs(xx) <= 1e15, abs(y) <= 1e15 { textPos = Vec2(xx, y) }
            case 41:
                if inContext && !inLeader && height == 0 { height = double(g) ?? 0 }
            default: break
            }
        }
        guard !lines.isEmpty || !text.isEmpty else { invalid("MULTILEADER"); return nil }
        return .multileader(CADMultiLeader(leaderLines: lines, text: text, textPosition: textPos ?? lines.first?.last, textHeight: max(0, height)), p)
    }

    // MARK: OBJECTS

    private func parseObjects() throws {
        while try next() {
            guard cur.code == 0 else { continue }
            if atSectionEnd() { return }
            let type = rawString(cur).uppercased()
            try collect()
            switch type {
            case "LAYOUT":
                var lo = LayoutObject()
                var afterLayoutMarker = false
                var pw: Double?, ph: Double?
                for g in gs {
                    switch g.code {
                    case 100: afterLayoutMarker = rawString(g) == "AcDbLayout"
                    case 1: if afterLayoutMarker { lo.name = string(g) }
                    case 330: if afterLayoutMarker { lo.recordHandle = rawString(g).uppercased() }
                    case 44: pw = double(g)
                    case 45: ph = double(g)
                    case 71: if afterLayoutMarker { lo.tabOrder = int(g) ?? 0 }
                    default: break
                    }
                }
                if lo.name.isEmpty, let nm = s(1) { lo.name = nm }
                if let pw, let ph, pw > 0, ph > 0, pw < 1e6, ph < 1e6 { lo.paper = Vec2(pw, ph) }
                if !lo.name.isEmpty { layoutObjects.append(lo) }
            case "IMAGEDEF":
                if let h = s(5), let path = s(1) {
                    imageDefs[h.uppercased()] = path
                    imageDefOrder.append(path)
                }
            default: break
            }
        }
    }

    // MARK: Finish

    private var onceWarnings: Set<String> = []
    private func warnOnce(_ w: String) {
        if onceWarnings.insert(w).inserted { warnings.append(w) }
    }

    private func finish() -> CADDocument {
        let version = (header["$ACADVER"] ?? "").uppercased()
        var doc = CADDocument()
        doc.version = version.isEmpty ? "AC1009" : version
        doc.versionName = CADDocument.friendlyVersion(doc.version)
        doc.format = binary ? "DXF (binary)" : "DXF"
        doc.codepage = utf8 ? "UTF-8" : (header["$DWGCODEPAGE"] ?? "ANSI_1252")
        if let u = header["$INSUNITS"].flatMap({ Int($0) }) {
            if let cu = CADUnits(rawValue: u) { doc.units = cu } else { warnings.append("Unknown drawing units code \(u); treated as unitless.") }
        }
        doc.header = header
        doc.layers = layers
        if !doc.layers.contains(where: { $0.name == "0" }) { doc.layers.insert(CADLayer(name: "0"), at: 0) }
        // Layers referenced by entities but missing from the table.
        doc.lineTypes = lineTypes
        doc.textStyles = styles
        var fonts: [String] = []
        var seenFonts: Set<String> = []
        for st in styles {
            for f in [st.fontFile, st.bigFontFile] where !f.isEmpty && seenFonts.insert(f.uppercased()).inserted { fonts.append(f) }
        }
        doc.fonts = fonts
        var images: [String] = []
        var seenImages: Set<String> = []
        for p in imageDefOrder where seenImages.insert(p).inserted { images.append(p) }
        doc.images = images

        // Resolve image definition references.
        if hasImages {
            func fix(_ e: CADEntity) -> CADEntity {
                if case .image(let path, let corners, let p) = e, path.hasPrefix("\u{1}") {
                    let h = String(path.dropFirst())
                    return .image(path: imageDefs[h] ?? "", corners: corners, p)
                }
                return e
            }
            modelSpace = modelSpace.map(fix)
            paperSpace = paperSpace.map(fix)
            for (k, v) in blocks { var b = v; b.entities = b.entities.map(fix); blocks[k] = b }
            for (k, v) in layoutBlocks { var b = v; b.entities = b.entities.map(fix); layoutBlocks[k] = b }
        }

        doc.blocks = blocks
        doc.modelSpace = modelSpace
        doc.xrefs = blocks.values.filter(\.isXref).sorted { $0.name < $1.name }.map {
            CADXrefInfo(blockName: $0.name, path: $0.xrefPath ?? "", isOverlay: false)
        }

        // Layouts.
        var layouts: [CADLayout] = []
        var modelName = "Model"
        var paperLayouts: [CADLayout] = []
        var blockByRecord: [String: String] = [:]
        var layoutBlockByUpper: [String: CADBlock] = [:]
        for b in layoutBlocks.values {
            if !b.recordHandle.isEmpty { blockByRecord[b.recordHandle] = b.name }
            layoutBlockByUpper[b.name.uppercased()] = b
        }
        for lo in layoutObjects {
            let recName = blockRecords[lo.recordHandle] ?? blockByRecord[lo.recordHandle] ?? ""
            let u = recName.uppercased()
            if u == "*MODEL_SPACE" || lo.name.caseInsensitiveCompare("Model") == .orderedSame {
                modelName = lo.name
                continue
            }
            var ents: [CADEntity] = []
            if u == "*PAPER_SPACE" { ents = paperSpace }
            if !u.isEmpty, let blk = layoutBlockByUpper[u] { ents += blk.entities }
            paperLayouts.append(CADLayout(name: lo.name, isModelSpace: false, entities: ents, paperSize: lo.paper, tabOrder: lo.tabOrder))
        }
        if paperLayouts.isEmpty && (!paperSpace.isEmpty || layoutBlocks.keys.contains { $0.uppercased() == "*PAPER_SPACE" || $0.uppercased() == "$PAPER_SPACE" }) {
            let blockEnts = layoutBlocks.first { $0.key.uppercased() == "*PAPER_SPACE" || $0.key.uppercased() == "$PAPER_SPACE" }?.value.entities ?? []
            if !paperSpace.isEmpty || !blockEnts.isEmpty {
                paperLayouts.append(CADLayout(name: "Layout1", isModelSpace: false, entities: paperSpace + blockEnts, tabOrder: 1))
            }
        }
        layouts.append(CADLayout(name: modelName, isModelSpace: true, entities: modelSpace, tabOrder: 0))
        layouts.append(contentsOf: paperLayouts.sorted { ($0.tabOrder, $0.name) < ($1.tabOrder, $1.name) })
        doc.layouts = layouts

        // Layers used by entities but not declared.
        var known = Set(doc.layers.map { $0.name.uppercased() })
        func declare(_ ents: [CADEntity]) {
            for e in ents {
                let l = e.props.layer
                if !known.contains(l.uppercased()) { known.insert(l.uppercased()); doc.layers.append(CADLayer(name: l)) }
            }
        }
        declare(modelSpace); declare(paperSpace)
        for b in blocks.values { declare(b.entities) }

        doc.unsupportedCounts = unsupported
        doc.entityCounts = entityCounts
        if invalidCount > 0 {
            let detail = invalidTypes.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
            warnings.append("\(invalidCount) entities had invalid or out-of-range geometry and were skipped (\(detail)).")
        }
        doc.warnings = warnings

        // Extents: computed from geometry; header values as fallback.
        var calc = CADBoundsCalculator(doc: doc, maxDepth: options.maxBlockDepth)
        var ext = calc.bounds(of: modelSpace)
        if !CADGeometry.isFinite(ext) {
            let parse: (String) -> Vec2? = { key in
                guard let v = self.header[key]?.split(separator: ",").compactMap({ Double($0) }), v.count >= 2, abs(v[0]) < 1e15, abs(v[1]) < 1e15 else { return nil }
                return Vec2(v[0], v[1])
            }
            if let a = parse("$EXTMIN"), let b = parse("$EXTMAX"), a.x <= b.x, a.y <= b.y { ext = Rect2(min: a, max: b) } else { ext = .empty }
        }
        doc.extents = ext
        return doc
    }
}
