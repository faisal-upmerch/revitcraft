import Foundation

// MCP: a small JSON value for the protocol and tool arguments (no third-party JSON code). Numbers keep integers exact
// so JSON-RPC ids round-trip.

public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Accessors

    public subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): b
        case .string(let s): ["true", "yes", "1"].contains(s.lowercased()) ? true : ["false", "no", "0"].contains(s.lowercased()) ? false : nil
        default: nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }
    public var intValue: Int? {
        switch self {
        case .int(let i): i
        case .double(let d) where d == d.rounded() && abs(d) < 9e15: Int(d)
        case .string(let s): Int(s)
        default: nil
        }
    }
    public var isNull: Bool { if case .null = self { return true }; return false }

    // MARK: Encoding

    /// Compact JSON text on one line (MCP stdio forbids embedded newlines).
    public var jsonText: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if !d.isFinite { out += "null" } else if d == d.rounded(), abs(d) < 1e15 { out += String(Int(d)) } else {
                // Short, exact enough for geometry: 6 significant decimals after rounding noise.
                var s = String(format: "%.6f", d)
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
                out += s
            }
        case .string(let s): JSONValue.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (k, v) in a.enumerated() {
                if k > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            // Stable key order keeps results readable and tests deterministic.
            for (k, key) in o.keys.sorted().enumerated() {
                if k > 0 { out += "," }
                JSONValue.quote(key, into: &out)
                out += ":"
                o[key]!.write(to: &out)
            }
            out += "}"
        }
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    // MARK: Decoding

    public struct ParseError: Error, Sendable, CustomStringConvertible {
        public var description: String
    }

    /// Parses JSON text. Uses Foundation's parser, then maps to `JSONValue` keeping integers as `.int`.
    public static func parse(_ text: String) throws(ParseError) -> JSONValue {
        guard let data = text.data(using: .utf8) else { throw ParseError(description: "Not UTF-8.") }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws(ParseError) -> JSONValue {
        let obj: Any
        do { obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) } catch {
            throw ParseError(description: "Invalid JSON: \(error.localizedDescription)")
        }
        return from(obj)
    }

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let d = n.doubleValue
            if CFNumberIsFloatType(n) { return .double(d) }
            return .int(n.intValue)
        case let s as String: return .string(s)
        case let a as [Any]: return .array(a.map(from))
        case let o as [String: Any]: return .object(o.mapValues(from))
        default: return .null
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .int(v) }
    public init(floatLiteral v: Double) { self = .double(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b })) }
    public init(nilLiteral: ()) { self = .null }
}
