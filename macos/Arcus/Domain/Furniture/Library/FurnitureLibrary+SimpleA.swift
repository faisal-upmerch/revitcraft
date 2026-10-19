import Foundation

// FM9B: this batch's library pieces (see FurnitureLibrary.swift): 83 simple pieces for the living room, bedroom, dining
// room, kitchen, home office and bathroom, written with the FM9B kit (FurnitureLibrary+SimpleAKit*.swift), one file
// per room.

extension FurnitureLibrary {
    static var simpleA: [FurnitureLibraryPiece] { simpleASpecs.map(\.libraryPiece) }

    /// The pieces as specs (tests build them with `build()`, which reports a failing step).
    static var simpleASpecs: [SA.Piece] { simpleALiving + simpleABedroom + simpleADining + simpleAKitchen + simpleAOffice + simpleABathroom }
}
