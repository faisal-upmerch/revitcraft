import Foundation
import ArcusDomain

// HOME: the furniture pieces Home ▸ Furniture offers as starting points (Docs/FurnitureMode.md §3 Library, §4).

/// The furniture library on disk: bundled pieces in `Resources/Furniture Library/<Room>/<Name>.arcusfurniture`, and
/// the user's own furniture templates in `~/Library/Application Support/Arcus/Furniture Templates/` (loose files go
/// under "My Templates"; sub-folders are rooms, as in the bundle). Pure file scanning, so tests can point it at any
/// folder.
public enum FurnitureLibraryCatalog {
    /// The file extension of Furniture documents.
    public static let fileExtension = "arcusfurniture"
    /// Room name for user templates saved straight into the templates folder.
    public static let myTemplatesRoom = "My Templates"

    /// One library piece, as listed under one room (FM9: a bundled piece listed under several rooms is one Item per
    /// room, all with the same file).
    public struct Item: Identifiable, Hashable, Sendable {
        public var url: URL
        /// Display name (the file name without its extension).
        public var name: String
        /// Room it is listed under ("Living Room", "Kitchen", "My Templates").
        public var room: String
        /// True for the user's own templates (Application Support), false for bundled pieces.
        public var isUser: Bool
        /// FM9: from the library's index.json: every room the piece is listed under, search words, its types' names
        /// and sizes, category ("Furniture"/"Casework"), detail ("high"/"simple") and description.
        public var rooms: [String] = []
        public var keywords: [String] = []
        public var types: [FurnitureLibraryIndex.TypeSize] = []
        public var category: String?
        public var detail: String?
        public var summary: String = ""
        /// The room and the file (a piece listed under two rooms is two items).
        public var id: String { room + "|" + url.path }
        public init(url: URL, name: String, room: String, isUser: Bool) {
            self.url = url; self.name = name; self.room = room; self.isUser = isUser
        }

        /// "3 types" (empty when the count isn't known).
        public var typeCountText: String { types.isEmpty ? "" : "\(types.count) type\(types.count == 1 ? "" : "s")" }

        /// True when the name, a room or a keyword contains `q` (case- and diacritic-insensitive).
        public func matches(_ q: String) -> Bool {
            func has(_ s: String) -> Bool { s.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return has(name) || has(room) || rooms.contains(where: has) || keywords.contains(where: has) || (category.map(has) ?? false)
        }
    }

    /// A room and its pieces, by name.
    public struct Room: Identifiable, Hashable, Sendable {
        public var name: String
        public var items: [Item]
        public var id: String { name }
    }

    /// `Furniture Library` inside the app's resources, or nil outside an app bundle.
    public static var bundledRoot: URL? {
        Bundle.main.resourceURL?.appending(path: "Furniture Library", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/Arcus/Furniture Templates`.
    public static var userRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Arcus/Furniture Templates", directoryHint: .isDirectory)
    }

    /// Every piece in the bundled library and the user's templates. Missing folders give no pieces.
    public static func all() -> [Item] { scan(bundled: bundledRoot, user: userRoot) }

    /// Pieces under `bundled` (room folders only) and `user` (room folders, plus loose files as My Templates).
    public static func scan(bundled: URL?, user: URL?) -> [Item] {
        var items: [Item] = []
        if let bundled { items += scanRoot(bundled, isUser: false, looseRoom: nil) }
        if let user { items += scanRoot(user, isUser: true, looseRoom: myTemplatesRoom) }
        return items.sorted { a, b in
            a.room == b.room ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.room.localizedStandardCompare(b.room) == .orderedAscending
        }
    }

    /// The pieces whose name, room or keywords contain `query` (case- and diacritic-insensitive), grouped by room. User rooms
    /// come after the bundled ones, and My Templates last.
    public static func rooms(_ items: [Item], matching query: String = "") -> [Room] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = q.isEmpty ? items : items.filter { $0.matches(q) } // FM9: names, rooms and keywords
        var order: [String] = []
        var byRoom: [String: [Item]] = [:]
        for item in matched {
            if byRoom[item.room] == nil { order.append(item.room) }
            byRoom[item.room, default: []].append(item)
        }
        func rank(_ room: String) -> Int {
            if room == myTemplatesRoom { return 2 }
            return byRoom[room]?.allSatisfy(\.isUser) == true ? 1 : 0
        }
        return order.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.localizedStandardCompare(b) == .orderedAscending
        }.map { Room(name: $0, items: byRoom[$0] ?? []) }
    }

    private static func scanRoot(_ root: URL, isUser: Bool, looseRoom: String?) -> [Item] {
        let fm = FileManager.default
        // FM9: a library with an index lists each piece under every room it names; the file lives once.
        if let index = FurnitureLibraryIndex.read(in: root) { return indexedItems(index, root: root, isUser: isUser) }
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var items: [Item] = []
        for entry in entries {
            if entry.pathExtension.lowercased() == fileExtension {
                if let looseRoom { items.append(item(entry, room: looseRoom, isUser: isUser)) }
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let room = entry.lastPathComponent
                let files = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                items += files.filter { $0.pathExtension.lowercased() == fileExtension }.map { item($0, room: room, isUser: isUser) }
            }
        }
        return items
    }

    /// The pieces of an indexed library, one item per piece and room (files that aren't there are skipped).
    static func indexedItems(_ index: FurnitureLibraryIndex, root: URL, isUser: Bool) -> [Item] {
        var out: [Item] = []
        for p in index.pieces {
            let url = root.appending(path: p.file, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            for room in p.rooms.isEmpty ? [url.deletingLastPathComponent().lastPathComponent] : p.rooms {
                var item = Item(url: url, name: p.name, room: room, isUser: isUser)
                item.rooms = p.rooms
                item.keywords = p.keywords
                item.types = p.types
                item.category = p.category
                item.detail = p.detail
                item.summary = p.description
                out.append(item)
            }
        }
        return out
    }

    private static func item(_ url: URL, room: String, isUser: Bool) -> Item {
        Item(url: url, name: url.deletingPathExtension().lastPathComponent, room: room, isUser: isUser)
    }
}

/// What a recent file on Home is, from its extension: badges and the Recent filter use it.
public enum HomeDocumentKind: String, CaseIterable, Sendable {
    case project = "Project"
    case furniture = "Furniture"
    case family = "Family"

    /// `.arcus` → project, `.arcusfurniture` → furniture, `.arcusfamily` → family; nil for anything else (DWG, IFC…).
    public init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "arcus": self = .project
        case FurnitureLibraryCatalog.fileExtension: self = .furniture
        case "arcusfamily": self = .family
        default: return nil
        }
    }

    /// The Recent filter's title for this kind ("Projects", "Furniture", "Families").
    public var filterTitle: String {
        switch self {
        case .project: "Projects"
        case .furniture: "Furniture"
        case .family: "Families"
        }
    }

    /// The recent files of `kind` (all when nil), in their original order.
    public static func filter(_ urls: [URL], _ kind: HomeDocumentKind?) -> [URL] {
        guard let kind else { return urls }
        return urls.filter { HomeDocumentKind(url: $0) == kind }
    }
}
