import Foundation

// FM9: `index.json` next to the bundled Furniture Library's room folders. `arcus-bench --furniture-library <dir>` writes
// it with the pieces; Home ▸ Furniture, Load Furniture and the Component Library read it (FurnitureLibraryCatalog) to
// list each piece under every room it belongs to, while its file lives once, in its first room's folder.

/// The bundled Furniture Library's index.
public struct FurnitureLibraryIndex: Codable, Hashable, Sendable {
    /// One size type of a piece, in inches.
    public struct TypeSize: Codable, Hashable, Sendable {
        public var name: String
        public var width: Double
        public var depth: Double
        public var height: Double
        public init(name: String, width: Double, depth: Double, height: Double) { self.name = name; self.width = width; self.depth = depth; self.height = height }
    }

    /// One piece: its file (relative to the library folder) and what the galleries show and search.
    public struct Piece: Codable, Hashable, Sendable {
        public var name: String
        public var file: String
        public var rooms: [String]
        /// "Furniture" or "Casework".
        public var category: String
        /// "high" or "simple".
        public var detail: String
        public var keywords: [String]
        public var description: String
        public var types: [TypeSize]
        public init(name: String, file: String, rooms: [String], category: String, detail: String, keywords: [String], description: String, types: [TypeSize]) {
            self.name = name; self.file = file; self.rooms = rooms; self.category = category; self.detail = detail; self.keywords = keywords
            self.description = description; self.types = types
        }
    }

    public static let fileName = "index.json"
    public static let currentVersion = 1

    public var version: Int
    public var pieces: [Piece]
    public init(version: Int = currentVersion, pieces: [Piece]) { self.version = version; self.pieces = pieces }

    /// The index in `folder`, or nil when there is none (or it can't be read).
    public static func read(in folder: URL) -> FurnitureLibraryIndex? {
        guard let data = try? Data(contentsOf: folder.appending(path: fileName, directoryHint: .notDirectory)) else { return nil }
        return try? JSONDecoder().decode(FurnitureLibraryIndex.self, from: data)
    }

    /// Pretty, key-sorted JSON (stable between builds).
    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }

    /// The index entry of a built piece: its type sizes (formulas evaluated) and its file under its first room.
    public static func entry(_ p: FurnitureLibraryPiece, _ m: BIMModel) -> Piece {
        var types: [TypeSize] = []
        if let s = m.furnitureSetup {
            for t in s.family.types {
                let v = FamilyEvaluator.parameterValues(s.family, typeName: t.name, units: m.units).values
                func inches(_ n: String) -> Double {
                    if case .quantity(let q, _)? = v[n] { return (q / 0.0254 * 1000).rounded() / 1000 }
                    return 0
                }
                types.append(TypeSize(name: t.name, width: inches("Width"), depth: inches("Depth"), height: inches("Height")))
            }
        }
        return Piece(name: p.name, file: relativePath(p), rooms: p.rooms, category: p.category == .casework ? "Casework" : "Furniture",
                     detail: p.detail.rawValue, keywords: p.keywords, description: m.furnitureSetup?.family.description ?? "", types: types)
    }

    /// `<Room>/<Name>.arcusfurniture` (characters a file name can't hold become dashes).
    public static func relativePath(_ p: FurnitureLibraryPiece) -> String {
        func clean(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            return t.hasPrefix(".") ? "-" + t.dropFirst() : t
        }
        return "\(clean(p.rooms.first ?? "Other"))/\(clean(p.name)).arcusfurniture"
    }
}

extension FurnitureLibrary {
    /// The piece with every generated identifier made deterministic from `seed` (IFC GUIDs, the UUIDs of family solids,
    /// lines and schedule fields, revision stamps), so rebuilding the library writes the same files.
    public static func stabilized(_ m: BIMModel, seed: String) -> BIMModel {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let dec = JSONDecoder()
        guard let uuid = try? NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}") else { return m }
        var map: [String: String] = [:]
        func stable(_ old: String) -> String {
            if let hit = map[old] { return hit }
            let new = deterministicUUID("\(seed)#\(map.count)")
            map[old] = new
            return new
        }
        var out = m
        for e in m.allElements {
            var x = e
            x.ifcGUID = .deterministic("\(seed)/\(e.id.raw)")
            x.revision = e.id.raw // below Element.legacyRevisionLimit: re-stamped when the file is opened
            guard let data = try? enc.encode(x), let text = String(data: data, encoding: .utf8) else { out.put(x); continue }
            let ns = text as NSString
            var result = ""
            var last = 0
            for match in uuid.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                result += stable(ns.substring(with: match.range))
                last = match.range.location + match.range.length
            }
            result += ns.substring(from: last)
            if let y = try? dec.decode(Element.self, from: Data(result.utf8)) { out.put(y) } else { out.put(x) }
        }
        return out
    }

    /// A UUID string from a hash of `seed` (FNV-1a, 128 bits).
    public static func deterministicUUID(_ seed: String) -> String {
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x6c62272e07bb0142
        for b in seed.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(b)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
        }
        let hex = String(format: "%016llX%016llX", h1, h2)
        let c = Array(hex)
        return "\(String(c[0..<8]))-\(String(c[8..<12]))-4\(String(c[13..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))"
    }
}
