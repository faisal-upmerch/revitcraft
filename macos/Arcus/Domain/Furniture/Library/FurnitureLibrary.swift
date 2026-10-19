import Foundation

// FM9: the Furniture Library (Docs/FurnitureMode.md §3 "Library"). Every piece is built with the same Furniture mode
// operations the tools call, then saved as a .arcusfurniture template by `arcus-bench --furniture-library <dir>` and
// bundled in Contents/Resources/Furniture Library/<Room>/<Name>.arcusfurniture. Each batch registers its pieces in
// its own file: FurnitureLibrary+Essentials.swift (FM9, the 25 essentials at high detail), +SimpleA.swift (FM9B) and
// +SimpleB.swift (FM9C).

/// One library piece.
public struct FurnitureLibraryPiece: Sendable {
    public enum Detail: String, Sendable { case high, simple }
    /// The piece's name, as on the owner's list ("Bedside Table").
    public var name: String
    /// Rooms it is listed under; the first is the folder it is saved in.
    public var rooms: [String]
    /// Furniture or Casework.
    public var category: FamilyTemplate
    public var detail: Detail
    /// Builds the Furniture document (Imperial, parametric, with its types).
    public var build: @Sendable () -> BIMModel

    public init(_ name: String, rooms: [String], category: FamilyTemplate = .furniture, detail: Detail, build: @escaping @Sendable () -> BIMModel) {
        self.name = name; self.rooms = rooms; self.category = category; self.detail = detail; self.build = build
    }
}

public enum FurnitureLibrary {
    /// Every library piece, essentials first.
    public static var all: [FurnitureLibraryPiece] { essentials + simpleA + simpleB }
}
