import Foundation

// FM9C: this batch's library pieces (see FurnitureLibrary.swift): the simple pieces of part B, by room, in
// FurnitureLibrary+SimpleB+<Room>.swift, built with the helpers in FurnitureLibrary+SimpleBKit.swift.

extension FurnitureLibrary {
    static var simpleB: [FurnitureLibraryPiece] {
        SimpleB.pieces.map { p in
            FurnitureLibraryPiece(p.name, rooms: p.rooms, category: p.category, detail: .simple, keywords: SimpleB.keywords(p)) { SimpleB.model(p) }
        }
    }
}

/// The part B simple pieces.
enum SimpleB {
    /// One piece: its name, rooms (the first is its folder), category and builder.
    struct Piece: Sendable {
        var name: String
        var rooms: [String]
        var category: FamilyTemplate
        var make: @Sendable () throws -> BIMModel
        init(_ name: String, _ rooms: [String], _ category: FamilyTemplate, _ make: @escaping @Sendable () throws -> BIMModel) {
            self.name = name; self.rooms = rooms; self.category = category; self.make = make
        }
        init(_ name: String, _ rooms: [String], _ make: @escaping @Sendable () throws -> BIMModel) { self.init(name, rooms, .furniture, make) }
    }

    static var pieces: [Piece] { entryway + kids + outdoor + storage + multipurpose + decorative }

    /// The piece's document; if it can't be built (the FM9C tests rule that out), a blank one of its category with the
    /// failure recorded, as LibraryKit records it, so the library generator reports it.
    static func model(_ p: Piece) -> BIMModel {
        do { return try p.make() } catch { return LibraryKit.failed(FurnitureTemplates.blank(category: p.category, name: p.name), error) }
    }

    /// Search words for a piece by its rooms (Load Furniture and Home ▸ Furniture search them with the name).
    static func keywords(_ p: Piece) -> [String] {
        var out: [String] = []
        if p.rooms.contains(outdoorRoom) { out += ["outdoor", "patio", "garden", "teak", "cedar"] }
        if p.rooms.contains(kidsRoom) { out += ["kids", "children", "nursery", "baby"] }
        if p.rooms.contains(entry) { out += ["entry", "hallway", "foyer", "mudroom"] }
        if p.rooms.contains(storageRoom) { out += ["storage", "utility", "closet", "organizer"] }
        if p.rooms.contains(multi) { out += ["space-saving", "convertible", "small space"] }
        if p.rooms.contains(decor) { out += ["decorative", "accent", "display"] }
        if p.category == .casework { out.append("casework") }
        return out
    }

    /// Pieces with parts that keep their size when the piece flexes, and why (Flex still passes: nothing breaks).
    static let partialFlex: [String: String] = [
        "Sun Lounger": "the back's raked struts",
        "Hammock": "the raked uprights, ropes and the bed's curve",
        "Hanging Chair": "the revolved basket and base",
        "Picnic Table": "the A-frame legs",
        "Folding Chair": "the raked legs",
        "Swing Bench": "the A-frame legs",
        "Adirondack Chair": "the raked stringers and back slats",
        "Folding Screen": "the leaves, drawn at an angle in plan",
        "Ladder Shelf": "the raked side rails",
    ]

    static let entry = "Entryway & Hallway", kidsRoom = "Kids' Room & Nursery", outdoorRoom = "Outdoor & Balcony"
    static let storageRoom = "Storage & Utility", multi = "Multipurpose & Space-Saving", decor = "Decorative & Accent"
}
