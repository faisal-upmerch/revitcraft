import Foundation
import Testing
import AppKit
@testable import ArcusDomain
@testable import ArcusApplication
@testable import ArcusUI

/// FMG4: Home ▸ Furniture names the new piece after the piece picked last (the owner picked Entryway Bench, then
/// Kitchen Cart, and got a cart called Entryway Bench); a name typed by the user stays; the category follows.
@Suite("FMG4 Home furniture picking") @MainActor
struct FMG4HomeTests {
    static func item(_ name: String, _ category: String) -> FurnitureLibraryCatalog.Item {
        var i = FurnitureLibraryCatalog.Item(url: URL(fileURLWithPath: "/tmp/\(name).arcusfurniture"), name: name, room: "Kitchen", isUser: false)
        i.category = category
        return i
    }

    @Test func theNameFollowsThePickedPieceUntilTheUserTypesOne() {
        let home = HomeModel(tab: .furniture, readsDisk: false)
        home.pickFurnitureTemplate(Self.item("Entryway Bench", "Furniture"))
        #expect(home.furnitureName == "Entryway Bench")
        home.pickFurnitureTemplate(Self.item("Kitchen Cabinet", "Casework"))
        #expect(home.furnitureName == "Kitchen Cabinet")
        #expect(home.furnitureCategory == .casework)
        #expect(home.furnitureTemplate?.lastPathComponent == "Kitchen Cabinet.arcusfurniture")
        home.pickFurnitureTemplate(nil)
        #expect(home.furnitureName == "Untitled Furniture" && home.furnitureTemplate == nil)
        home.furnitureName = "Mudroom Bench"
        home.pickFurnitureTemplate(Self.item("Kitchen Cart", "Furniture"))
        #expect(home.furnitureName == "Mudroom Bench")
        #expect(home.furnitureCategory == .furniture)
    }
}
