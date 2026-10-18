import Foundation

/// A parameter value of an ISO 10303-21 (STEP physical file) instance.
public enum STEPValue: Sendable, Hashable, CustomStringConvertible {
    /// `$` — unset optional attribute.
    case null
    /// `*` — attribute derived in a subtype.
    case derived
    case integer(Int)
    case real(Double)
    case string(String)
    /// `.NAME.` — enumeration or boolean/logical (`.T.`, `.F.`, `.U.`). Stored without the dots.
    case enumeration(String)
    /// `"0FF"` — binary literal, stored as its hex text.
    case binary(String)
    /// `#123` — entity instance reference.
    case ref(Int)
    case list([STEPValue])
    /// `IFCLABEL('x')` — a typed (select) value.
    case typed(String, [STEPValue])

    public var refValue: Int? { if case .ref(let r) = self { return r }; return nil }
    public var listValue: [STEPValue]? {
        switch self {
        case .list(let l): return l
        case .typed(_, let v) where v.count == 1: return v[0].listValue
        default: return nil
        }
    }
    /// String contents (unwrapping typed values such as IFCLABEL('x')).
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .typed(_, let v) where v.count == 1: return v[0].stringValue
        default: return nil
        }
    }
    /// Numeric value (integers, reals, and typed measures such as IFCLENGTHMEASURE(3.)).
    public var doubleValue: Double? {
        switch self {
        case .real(let d): return d
        case .integer(let i): return Double(i)
        case .typed(_, let v) where v.count == 1: return v[0].doubleValue
        default: return nil
        }
    }
    public var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .real(let d) where d.isFinite && abs(d) < 9e15: return Int(d.rounded())
        case .typed(_, let v) where v.count == 1: return v[0].intValue
        default: return nil
        }
    }
    public var enumValue: String? {
        switch self {
        case .enumeration(let e): return e
        case .typed(_, let v) where v.count == 1: return v[0].enumValue
        default: return nil
        }
    }
    /// `.T.` / `.F.` (and IFCBOOLEAN(.T.)). `.U.` (unknown) is nil.
    public var boolValue: Bool? {
        switch enumValue {
        case "T": return true
        case "F": return false
        default: return nil
        }
    }
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// Type name of a typed value (e.g. "IFCLABEL").
    public var typeName: String? { if case .typed(let t, _) = self { return t }; return nil }

    /// Human-readable value for property export ("Pset.Prop" = value).
    public var displayString: String {
        switch self {
        case .null: return ""
        case .derived: return "*"
        case .integer(let i): return String(i)
        case .real(let d): return STEPFormat.shortReal(d)
        case .string(let s): return s
        case .enumeration(let e):
            switch e {
            case "T": return "TRUE"
            case "F": return "FALSE"
            case "U": return "UNKNOWN"
            default: return e
            }
        case .binary(let b): return b
        case .ref(let r): return "#\(r)"
        case .list(let l): return l.map(\.displayString).joined(separator: ", ")
        case .typed(_, let v): return v.map(\.displayString).joined(separator: ", ")
        }
    }

    /// Part 21 encoding of the value.
    public var description: String {
        var s = ""
        STEPFormat.write(self, into: &s)
        return s
    }
}

/// One `#id=TYPE(...)` instance.
public struct STEPEntity: Sendable {
    public let id: Int
    /// Upper-case entity type name, e.g. "IFCWALL". Complex instances use the first partial type.
    public let type: String
    public let args: [STEPValue]
    /// 1-based line on which the instance starts.
    public let line: Int
    public init(id: Int, type: String, args: [STEPValue], line: Int) { self.id = id; self.type = type; self.args = args; self.line = line }

    /// Argument by position; `.null` when out of range (tolerates schema variants with fewer attributes).
    public subscript(_ i: Int) -> STEPValue { i >= 0 && i < args.count ? args[i] : .null }
}

/// HEADER section contents.
public struct STEPHeader: Sendable {
    public var description: [String] = []
    public var implementationLevel = ""
    public var name = ""
    public var timeStamp = ""
    public var author: [String] = []
    public var organization: [String] = []
    public var preprocessorVersion = ""
    public var originatingSystem = ""
    public var authorization = ""
    public var schemas: [String] = []
    public init() {}
}

/// A parsed STEP physical file.
public struct STEPFile: Sendable {
    public var header: STEPHeader
    public private(set) var entities: [Int: STEPEntity] = [:]
    /// Entity ids in file order.
    public private(set) var order: [Int] = []
    /// Entity ids per upper-case type, in file order.
    public private(set) var byType: [String: [Int]] = [:]

    public init(header: STEPHeader = STEPHeader()) { self.header = header }

    public var count: Int { order.count }
    public subscript(_ id: Int) -> STEPEntity? { entities[id] }
    public subscript(_ v: STEPValue) -> STEPEntity? { v.refValue.flatMap { entities[$0] } }
    public func all(_ type: String) -> [STEPEntity] { (byType[type] ?? []).compactMap { entities[$0] } }

    /// Adds an instance; returns false if the id already exists.
    mutating func add(_ e: STEPEntity) -> Bool {
        guard entities[e.id] == nil else { return false }
        entities[e.id] = e
        order.append(e.id)
        byType[e.type, default: []].append(e.id)
        return true
    }
}

/// Shared Part 21 formatting helpers (writer side).
enum STEPFormat {
    /// Deterministic real formatting: always contains a decimal point, at most 9 decimals, trailing zeros trimmed.
    static func real(_ v: Double) -> String {
        guard v.isFinite else { return "0." }
        if abs(v) < 1e-10 { return "0." }
        let a = abs(v)
        if a >= 1e12 || a < 1e-6 {
            // Exponent form: mantissa with a decimal point, e.g. 1.5E-07.
            var s = String(format: "%.9E", v)
            if let eIdx = s.firstIndex(of: "E") {
                var mant = String(s[s.startIndex..<eIdx])
                let exp = String(s[eIdx...])
                while mant.hasSuffix("0") { mant.removeLast() }
                s = mant + exp
            }
            return s
        }
        var s = String(format: "%.9f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s == "-0." { return "0." }
        return s
    }

    /// Short display of a real for property values.
    static func shortReal(_ v: Double) -> String {
        let r = real(v)
        return r.hasSuffix(".") ? String(r.dropLast()) : r
    }

    /// Encodes a string literal: printable ASCII kept, `'` doubled, `\` doubled, everything else as \X2\…\X0\ (\X4\ beyond the BMP).
    static func string(_ s: String) -> String {
        var out = "'"
        var pending: [Unicode.Scalar] = []
        func flush() {
            guard !pending.isEmpty else { return }
            if pending.allSatisfy({ $0.value <= 0xFFFF }) {
                out += "\\X2\\"
                for p in pending { out += String(format: "%04X", p.value) }
                out += "\\X0\\"
            } else {
                out += "\\X4\\"
                for p in pending { out += String(format: "%08X", p.value) }
                out += "\\X0\\"
            }
            pending.removeAll()
        }
        for u in s.unicodeScalars {
            if u.value >= 0x20 && u.value <= 0x7E {
                flush()
                switch u {
                case "'": out += "''"
                case "\\": out += "\\\\"
                default: out.unicodeScalars.append(u)
                }
            } else {
                // Keep runs homogeneous: BMP runs in \X2\, others in \X4\.
                if let last = pending.last, (last.value > 0xFFFF) != (u.value > 0xFFFF) { flush() }
                pending.append(u)
            }
        }
        flush()
        out += "'"
        return out
    }

    static func write(_ v: STEPValue, into s: inout String) {
        switch v {
        case .null: s += "$"
        case .derived: s += "*"
        case .integer(let i): s += String(i)
        case .real(let d): s += real(d)
        case .string(let str): s += string(str)
        case .enumeration(let e): s += "."; s += e; s += "."
        case .binary(let b): s += "\""; s += b; s += "\""
        case .ref(let r): s += "#"; s += String(r)
        case .list(let l):
            s += "("
            for (i, x) in l.enumerated() {
                if i > 0 { s += "," }
                write(x, into: &s)
            }
            s += ")"
        case .typed(let t, let args):
            s += t
            s += "("
            for (i, x) in args.enumerated() {
                if i > 0 { s += "," }
                write(x, into: &s)
            }
            s += ")"
        }
    }
}
