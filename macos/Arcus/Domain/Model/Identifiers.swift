import Foundation

/// Stable, typed identity of a model element within one project.
///
/// IDs are allocated monotonically by the model and never reused inside a
/// document, so undo/redo, persistence and cross-references stay unambiguous.
public struct ElementID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public static func < (a: ElementID, b: ElementID) -> Bool { a.raw < b.raw }
    public var description: String { "#\(raw)" }

    public init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(UInt64.self)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// IFC GlobalId: 22 characters, the 128-bit UUID in IFC's base-64 alphabet.
public struct IFCGUID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    public init?(_ value: String) {
        guard value.count == 22, value.allSatisfy({ IFCGUID.alphabet.contains($0) }) else { return nil }
        self.value = value
    }
    private init(unchecked: String) { value = unchecked }

    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$")

    public static func random() -> IFCGUID { IFCGUID(uuid: UUID()) }

    /// Deterministic GUID derived from a namespace string (used for reproducible fixtures).
    public static func deterministic(_ seed: String) -> IFCGUID {
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x84222325cbf29ce4
        for b in seed.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(b)) &* 0x1000193 &+ 0x9e3779b97f4a7c15
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((h1 >> (8 * UInt64(i))) & 0xff); bytes[8 + i] = UInt8((h2 >> (8 * UInt64(i))) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return IFCGUID(bytes: bytes)
    }

    public init(uuid: UUID) {
        let u = uuid.uuid
        self.init(bytes: [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
    }

    init(bytes: [UInt8]) {
        // IFC compression: first char encodes 2 bits, then 21 chars of 6 bits each (128 bits total).
        var chars: [Character] = []
        chars.reserveCapacity(22)
        var num = [UInt32](repeating: 0, count: 6)
        num[0] = UInt32(bytes[0])
        for i in 0..<5 {
            let o = 1 + i * 3
            num[i + 1] = (UInt32(bytes[o]) << 16) | (UInt32(bytes[o + 1]) << 8) | UInt32(bytes[o + 2])
        }
        func encode(_ n: UInt32, digits: Int) {
            var v = n
            var tmp = [Character](repeating: "0", count: digits)
            for j in stride(from: digits - 1, through: 0, by: -1) {
                tmp[j] = IFCGUID.alphabet[Int(v % 64)]
                v /= 64
            }
            chars.append(contentsOf: tmp)
        }
        encode(num[0], digits: 2)
        for i in 1..<6 { encode(num[i], digits: 4) }
        self.init(unchecked: String(chars))
    }

    /// Decodes back to the 16 UUID bytes.
    public var bytes: [UInt8] {
        let map = Dictionary(uniqueKeysWithValues: IFCGUID.alphabet.enumerated().map { ($1, UInt32($0)) })
        let c = Array(value)
        func decode(_ range: Range<Int>) -> UInt32 { range.reduce(0) { $0 * 64 + (map[c[$1]] ?? 0) } }
        var out = [UInt8(decode(0..<2) & 0xff)]
        for i in 0..<5 {
            let n = decode((2 + i * 4)..<(6 + i * 4))
            out.append(UInt8((n >> 16) & 0xff)); out.append(UInt8((n >> 8) & 0xff)); out.append(UInt8(n & 0xff))
        }
        return out
    }
    public var description: String { value }

    private enum CodingKeys: String, CodingKey { case value }

    /// Decodes the stored `{"value": "…"}` form (and a bare string) without rejecting malformed ids: a damaged
    /// GlobalId must not make the whole element unreadable. Loaders check `isValid` and report or repair it
    /// (`ArcusPackage.read` rejects, `verify` reports, `saveRecoveryCopy` assigns a fresh id).
    public init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self), let v = try? keyed.decode(String.self, forKey: .value) {
            self.init(unchecked: v)
        } else {
            self.init(unchecked: try decoder.singleValueContainer().decode(String.self))
        }
    }
    /// Whether the value is a well-formed 22-character IFC GlobalId.
    public var isValid: Bool { IFCGUID(value) != nil }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
    }
}
