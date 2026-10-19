import Foundation

// FM8: File ▸ Save as Furniture Template… puts a piece in the user's Furniture Templates folder, under a room, where
// Home ▸ Furniture and Insert ▸ Load Furniture find it (FurnitureLibraryCatalog.scan).

extension FurnitureLibraryCatalog {
    /// Where a template named `name` in `room` is saved under `root` (My Templates: loose in the root). Characters a
    /// file name can't hold become dashes.
    public static func templateURL(name: String, room: String, root: URL) -> URL {
        func clean(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            return t.hasPrefix(".") ? "-" + t.dropFirst() : t
        }
        let n = clean(name).isEmpty ? "Furniture" : clean(name)
        let r = clean(room)
        let folder = r.isEmpty || r == myTemplatesRoom ? root : root.appending(path: r, directoryHint: .isDirectory)
        return folder.appending(path: n + "." + fileExtension, directoryHint: .notDirectory)
    }

    /// The rooms a template can go in: the bundled library's rooms and the user's own, then My Templates.
    public static func templateRooms(_ items: [Item]) -> [String] {
        var rooms = Array(Set(items.map(\.room)).subtracting([myTemplatesRoom])).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for r in ["Living Room", "Dining Room", "Bedroom", "Kitchen", "Office", "Bathroom", "Entryway", "Outdoor"] where !rooms.contains(r) { rooms.append(r) }
        return rooms.sorted { $0.localizedStandardCompare($1) == .orderedAscending } + [myTemplatesRoom]
    }
}
