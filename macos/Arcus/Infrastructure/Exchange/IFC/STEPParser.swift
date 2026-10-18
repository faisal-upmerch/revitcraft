import Foundation

/// Single-pass ISO 10303-21 reader.
///
/// The reader walks the bytes once (no backtracking, no regular expressions), so time and memory grow
/// linearly with file size. Limits guard against hostile input: entity count, list nesting depth,
/// string length and numeric id range. All failures throw `IFCError` with the 1-based line number.
public enum STEPParser {
    public struct Limits: Sendable {
        /// Maximum number of instances in the DATA section.
        public var maxEntities = 20_000_000
        /// Maximum nesting depth of lists / typed values inside one instance.
        public var maxNesting = 64
        /// Maximum length of a single string literal in bytes.
        public var maxStringBytes = 8 * 1024 * 1024
        /// Maximum input size in bytes.
        public var maxFileBytes = 2_000_000_000
        public init() {}
    }

    /// Parses a complete STEP physical file.
    public static func parse(_ data: Data, limits: Limits = Limits(), progress: (Double) -> Void = { _ in },
                             isCancelled: () -> Bool = { false }) throws -> STEPFile {
        guard data.count <= limits.maxFileBytes else {
            throw IFCError("The file is larger than the supported maximum of \(limits.maxFileBytes / 1_000_000) MB.")
        }
        guard !data.isEmpty else { throw IFCError("The file is empty.", line: 1) }
        let bytes = [UInt8](data)
        return try bytes.withUnsafeBufferPointer { buf in
            var r = Reader(p: buf, limits: limits)
            return try r.parseFile(progress: progress, isCancelled: isCancelled)
        }
    }

    /// Decodes the body of a Part 21 string literal (already stripped of quotes and `''` doubling).
    static func decodeString(_ b: [UInt8], line: Int) throws -> String {
        var hasEscape = false
        var hasHigh = false
        for c in b {
            if c == 0x5C { hasEscape = true }
            if c >= 0x80 { hasHigh = true }
        }
        if !hasEscape {
            return hasHigh ? decodeHighBytes(b[...]) : String(decoding: b, as: UTF8.self)
        }
        var out = String.UnicodeScalarView()
        var j = 0
        let n = b.count
        func hex(_ c: UInt8) -> UInt32? {
            switch c {
            case 0x30...0x39: return UInt32(c - 0x30)
            case 0x41...0x46: return UInt32(c - 0x41 + 10)
            case 0x61...0x66: return UInt32(c - 0x61 + 10)
            default: return nil
            }
        }
        func matches(_ s: [UInt8], at k: Int) -> Bool {
            guard k + s.count <= n else { return false }
            for (o, c) in s.enumerated() where b[k + o] != c { return false }
            return true
        }
        let x2: [UInt8] = Array("\\X2\\".utf8), x4: [UInt8] = Array("\\X4\\".utf8), x0: [UInt8] = Array("\\X0\\".utf8)
        let xOne: [UInt8] = Array("\\X\\".utf8), sOne: [UInt8] = Array("\\S\\".utf8)
        while j < n {
            let c = b[j]
            if c == 0x5C {
                if j + 1 < n && b[j + 1] == 0x5C { out.append("\\"); j += 2; continue }
                if matches(x2, at: j) || matches(x4, at: j) {
                    let width = matches(x2, at: j) ? 4 : 8
                    j += 4
                    var units: [UInt32] = []
                    while !matches(x0, at: j) {
                        guard j + width <= n else { throw IFCError("Unterminated \\X\(width / 2)\\ string escape.", line: line) }
                        var v: UInt32 = 0
                        for k in 0..<width {
                            guard let h = hex(b[j + k]) else { throw IFCError("Invalid hex digit in string escape.", line: line) }
                            v = v << 4 | h
                        }
                        units.append(v)
                        j += width
                    }
                    j += 4
                    if width == 4 {
                        var it = units.map { UInt16(truncatingIfNeeded: $0) }.makeIterator()
                        var dec = UTF16()
                        loop: while true {
                            switch dec.decode(&it) {
                            case .scalarValue(let s): out.append(s)
                            case .emptyInput: break loop
                            case .error: out.append("\u{FFFD}")
                            }
                        }
                    } else {
                        for u in units { out.append(Unicode.Scalar(u) ?? "\u{FFFD}") }
                    }
                    continue
                }
                if matches(xOne, at: j), j + 4 < n, let h1 = hex(b[j + 3]), let h2 = hex(b[j + 4]) {
                    out.append(Unicode.Scalar(UInt8(h1 << 4 | h2)))
                    j += 5
                    continue
                }
                if matches(sOne, at: j), j + 3 < n {
                    out.append(Unicode.Scalar(UInt8(truncatingIfNeeded: Int(b[j + 3]) + 128)))
                    j += 4
                    continue
                }
                if j + 3 < n, b[j + 1] == 0x50, b[j + 3] == 0x5C { j += 4; continue } // \PA\ code page switch
                out.append("\\")
                j += 1
            } else if c < 0x80 {
                out.append(Unicode.Scalar(c))
                j += 1
            } else {
                var k = j
                while k < n && b[k] >= 0x80 { k += 1 }
                out.append(contentsOf: decodeHighBytes(b[j..<k]).unicodeScalars)
                j = k
            }
        }
        return String(out)
    }

    /// Raw non-ASCII bytes are not valid Part 21 but common in the wild: accept UTF-8, else Latin-1.
    private static func decodeHighBytes(_ b: ArraySlice<UInt8>) -> String {
        if let s = String(validating: b, as: UTF8.self) { return s }
        return String(String.UnicodeScalarView(b.map { Unicode.Scalar($0) }))
    }
}

private struct Reader {
    let p: UnsafeBufferPointer<UInt8>
    let n: Int
    let limits: STEPParser.Limits
    var i = 0
    var line = 1
    var typeCache: [UInt64: [String]] = [:]
    var numBuf: [CChar] = []
    var strBuf: [UInt8] = []

    init(p: UnsafeBufferPointer<UInt8>, limits: STEPParser.Limits) {
        self.p = p; self.n = p.count; self.limits = limits
        numBuf.reserveCapacity(64)
    }

    func error(_ m: String) -> IFCError { IFCError(m, line: line) }

    mutating func skipWS() throws {
        while i < n {
            let c = p[i]
            if c == 0x0A { line += 1; i += 1 }
            else if c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0C || c == 0x0B { i += 1 }
            else if c == 0x2F && i + 1 < n && p[i + 1] == 0x2A {
                let startLine = line
                i += 2
                var closed = false
                while i + 1 < n {
                    if p[i] == 0x0A { line += 1 }
                    if p[i] == 0x2A && p[i + 1] == 0x2F { i += 2; closed = true; break }
                    i += 1
                }
                if !closed { throw IFCError("Unterminated comment.", line: startLine) }
            } else { break }
        }
    }

    mutating func peek() throws -> UInt8 {
        try skipWS()
        guard i < n else { throw error("Unexpected end of file. The file is truncated.") }
        return p[i]
    }

    mutating func expect(_ c: UInt8, _ what: String) throws {
        let got = try peek()
        guard got == c else { throw error("Expected \(what) but found '\(printable(got))'.") }
        i += 1
    }

    func printable(_ c: UInt8) -> String {
        c >= 0x20 && c < 0x7F ? String(UnicodeScalar(c)) : String(format: "0x%02X", c)
    }

    static func isKeywordChar(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D
    }

    /// Reads a keyword (upper-cased, interned).
    mutating func keyword() throws -> String {
        let c = try peek()
        guard (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x21 else {
            throw error("Expected a keyword but found '\(printable(c))'.")
        }
        let start = i
        if c == 0x21 { i += 1 } // user-defined keywords start with '!'
        while i < n && Reader.isKeywordChar(p[i]) { i += 1 }
        guard i - start <= 256 else { throw error("Keyword is too long.") }
        var h: UInt64 = 0xcbf29ce484222325
        for k in start..<i { h = (h ^ UInt64(upper(p[k]))) &* 0x100000001b3 }
        let upperBytes = (start..<i).map { upper(p[$0]) }
        if let bucket = typeCache[h] {
            for s in bucket where s.utf8.elementsEqual(upperBytes) { return s }
        }
        let s = String(decoding: upperBytes, as: UTF8.self)
        typeCache[h, default: []].append(s)
        return s
    }

    @inline(__always) func upper(_ c: UInt8) -> UInt8 { (c >= 0x61 && c <= 0x7A) ? c - 32 : c }

    mutating func integerDigits(max: Int) throws -> Int {
        let start = i
        var v = 0
        while i < n, p[i] >= 0x30, p[i] <= 0x39 {
            let (m, o1) = v.multipliedReportingOverflow(by: 10)
            let (a, o2) = m.addingReportingOverflow(Int(p[i] - 0x30))
            guard !o1, !o2, a <= max else { throw error("Number is out of range.") }
            v = a
            i += 1
        }
        guard i > start else { throw error("Expected digits.") }
        return v
    }

    mutating func parseFile(progress: (Double) -> Void, isCancelled: () -> Bool) throws -> STEPFile {
        // Optional UTF-8 byte order mark.
        if n >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF { i = 3 }
        let magic = try keyword()
        guard magic == "ISO-10303-21" else { throw error("Not a STEP physical file (missing ISO-10303-21 header).") }
        try expect(0x3B, "';'")
        guard try keyword() == "HEADER" else { throw error("Missing HEADER section.") }
        try expect(0x3B, "';'")
        var header = STEPHeader()
        while true {
            let k = try keyword()
            if k == "ENDSEC" { try expect(0x3B, "';'"); break }
            try expect(0x28, "'('")
            let args = try list(depth: 1)
            try expect(0x3B, "';'")
            switch k {
            case "FILE_DESCRIPTION":
                header.description = args.first?.listValue?.compactMap(\.stringValue) ?? []
                header.implementationLevel = args.count > 1 ? args[1].stringValue ?? "" : ""
            case "FILE_NAME":
                func s(_ j: Int) -> String { j < args.count ? args[j].stringValue ?? "" : "" }
                func l(_ j: Int) -> [String] { j < args.count ? args[j].listValue?.compactMap(\.stringValue) ?? [] : [] }
                header.name = s(0); header.timeStamp = s(1); header.author = l(2); header.organization = l(3)
                header.preprocessorVersion = s(4); header.originatingSystem = s(5); header.authorization = s(6)
            case "FILE_SCHEMA":
                header.schemas = args.first?.listValue?.compactMap(\.stringValue) ?? []
            default:
                break
            }
        }
        var file = STEPFile(header: header)
        var sawData = false
        while true {
            let k = try keyword()
            if k == "END-ISO-10303-21" {
                try expect(0x3B, "';'")
                break
            }
            guard k == "DATA" else { throw error("Expected DATA section but found \(k).") }
            sawData = true
            if try peek() == 0x28 { i += 1; _ = try list(depth: 1) }
            try expect(0x3B, "';'")
            var counter = 0
            while true {
                let c = try peek()
                if c != 0x23 {
                    let end = try keyword()
                    guard end == "ENDSEC" else { throw error("Expected an entity instance or ENDSEC but found \(end).") }
                    try expect(0x3B, "';'")
                    break
                }
                let entity = try instance()
                guard file.count < limits.maxEntities else {
                    throw error("The file has more than \(limits.maxEntities) entities (limit).")
                }
                guard file.add(entity) else { throw IFCError("Duplicate entity id #\(entity.id).", line: entity.line) }
                counter += 1
                if counter & 0xFFFF == 0 {
                    if isCancelled() { throw IFCError.cancelled }
                    progress(Double(i) / Double(max(n, 1)))
                }
            }
        }
        guard sawData else { throw error("The file has no DATA section.") }
        progress(1)
        return file
    }

    mutating func instance() throws -> STEPEntity {
        let startLine = line
        i += 1 // '#'
        let id = try integerDigits(max: 1 << 53)
        try expect(0x3D, "'='")
        let c = try peek()
        let type: String
        let args: [STEPValue]
        if c == 0x28 {
            // Complex (external mapping) instance: (A(...) B(...)). Keep the first partial record.
            i += 1
            var first: (String, [STEPValue])?
            while try peek() != 0x29 {
                let k = try keyword()
                try expect(0x28, "'('")
                let a = try list(depth: 1)
                if first == nil { first = (k, a) }
            }
            i += 1
            guard let f = first else { throw error("Empty complex entity instance #\(id).") }
            type = f.0; args = f.1
        } else {
            type = try keyword()
            try expect(0x28, "'('")
            args = try list(depth: 1)
        }
        try expect(0x3B, "';' after entity #\(id)")
        return STEPEntity(id: id, type: type, args: args, line: startLine)
    }

    /// Parses list items after the opening parenthesis up to and including the closing one.
    mutating func list(depth: Int) throws -> [STEPValue] {
        guard depth <= limits.maxNesting else { throw error("Lists are nested more than \(limits.maxNesting) levels deep.") }
        var out: [STEPValue] = []
        if try peek() == 0x29 { i += 1; return out }
        while true {
            out.append(try value(depth: depth))
            let c = try peek()
            if c == 0x2C { i += 1; continue }
            if c == 0x29 { i += 1; return out }
            throw error("Expected ',' or ')' but found '\(printable(c))'.")
        }
    }

    mutating func value(depth: Int) throws -> STEPValue {
        let c = try peek()
        switch c {
        case 0x24: i += 1; return .null
        case 0x2A: i += 1; return .derived
        case 0x23:
            i += 1
            return .ref(try integerDigits(max: 1 << 53))
        case 0x27:
            return .string(try string())
        case 0x2E:
            i += 1
            let start = i
            while i < n && p[i] != 0x2E {
                guard Reader.isKeywordChar(p[i]) else { throw error("Invalid enumeration value.") }
                i += 1
            }
            guard i < n else { throw error("Unterminated enumeration value.") }
            let e = String(decoding: (start..<i).map { upper(p[$0]) }, as: UTF8.self)
            i += 1
            return .enumeration(e)
        case 0x22:
            i += 1
            let start = i
            while i < n && p[i] != 0x22 {
                guard (p[i] >= 0x30 && p[i] <= 0x39) || (p[i] >= 0x41 && p[i] <= 0x46) else { throw error("Invalid binary literal.") }
                i += 1
            }
            guard i < n else { throw error("Unterminated binary literal.") }
            let s = String(decoding: p[start..<i], as: UTF8.self)
            i += 1
            return .binary(s)
        case 0x28:
            i += 1
            return .list(try list(depth: depth + 1))
        case 0x2B, 0x2D, 0x30...0x39:
            return try number()
        default:
            if (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F {
                let k = try keyword()
                try expect(0x28, "'(' after \(k)")
                return .typed(k, try list(depth: depth + 1))
            }
            throw error("Unexpected character '\(printable(c))'.")
        }
    }

    mutating func number() throws -> STEPValue {
        let start = i
        var isReal = false
        if p[i] == 0x2B || p[i] == 0x2D { i += 1 }
        var digits = 0
        while i < n, p[i] >= 0x30, p[i] <= 0x39 { i += 1; digits += 1 }
        guard digits > 0 else { throw error("Invalid number.") }
        if i < n && p[i] == 0x2E {
            isReal = true
            i += 1
            while i < n, p[i] >= 0x30, p[i] <= 0x39 { i += 1 }
        }
        if i < n && (p[i] == 0x45 || p[i] == 0x65) {
            isReal = true
            i += 1
            if i < n && (p[i] == 0x2B || p[i] == 0x2D) { i += 1 }
            var ed = 0
            while i < n, p[i] >= 0x30, p[i] <= 0x39 { i += 1; ed += 1 }
            guard ed > 0 else { throw error("Invalid exponent in number.") }
        }
        guard i - start <= 60 else { throw error("Number literal is too long.") }
        if !isReal {
            var v = 0
            var neg = false
            var k = start
            if p[k] == 0x2D { neg = true; k += 1 } else if p[k] == 0x2B { k += 1 }
            var overflow = false
            while k < i {
                let (m, o1) = v.multipliedReportingOverflow(by: 10)
                let (a, o2) = m.addingReportingOverflow(Int(p[k] - 0x30))
                if o1 || o2 { overflow = true; break }
                v = a
                k += 1
            }
            if !overflow { return .integer(neg ? -v : v) }
        }
        numBuf.removeAll(keepingCapacity: true)
        for k in start..<i { numBuf.append(CChar(bitPattern: p[k])) }
        numBuf.append(0)
        let d = numBuf.withUnsafeBufferPointer { strtod($0.baseAddress!, nil) }
        return .real(d)
    }

    mutating func string() throws -> String {
        let startLine = line
        i += 1 // opening quote
        strBuf.removeAll(keepingCapacity: true)
        while true {
            guard i < n else { throw IFCError("Unterminated string literal.", line: startLine) }
            let c = p[i]
            if c == 0x27 {
                if i + 1 < n && p[i + 1] == 0x27 { strBuf.append(0x27); i += 2; continue }
                i += 1
                break
            }
            if c == 0x0A { line += 1; i += 1; continue }  // line breaks inside strings are not part of the value
            if c == 0x0D { i += 1; continue }
            strBuf.append(c)
            i += 1
            if strBuf.count > limits.maxStringBytes { throw IFCError("String literal exceeds \(limits.maxStringBytes) bytes.", line: startLine) }
        }
        return try STEPParser.decodeString(strBuf, line: startLine)
    }
}
