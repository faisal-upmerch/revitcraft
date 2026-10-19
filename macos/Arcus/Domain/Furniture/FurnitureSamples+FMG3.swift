import Foundation
import ArcusGeometry

// FMG3: samples for fronts on other faces, built with the operations the tools call: a kitchen island carcass open at
// the front and the back (two EQ dividers, no back panel) with doors on its back, and a 36" chest with a lid. QA
// captures and render checks use them.

extension FurnitureSamples {
    /// The base cabinet's carcass with two EQ dividers and no back, doors on its back face (seen from behind) and
    /// drawers in its middle bay at the front.
    public static func islandModel() -> BIMModel? {
        let s = TransactionContext(model: FurnitureTemplates.blank(category: .casework, name: "Island"), name: "Island")
        guard (try? baseCabinet(in: s)) != nil, var m = try? s.commit().model else { return nil }
        let t2 = TransactionContext(model: m, name: "Dividers")
        guard (try? FurniturePartOperations.createDividers(atFront: Vec2(0, 20 * inch), vertical: true, count: 2,
                                                           typeID: type(t2.model, .furniturePanels, "3/4\" Plywood"), in: t2)) != nil,
              let c2 = try? t2.commit() else { return nil }
        m = c2.model
        let t3 = TransactionContext(model: m, name: "Fronts")
        do {
            let back = BayFrame(angle: .pi)
            let l = try FurnitureBays.createBay(face: .front, at: Vec2(-18 * inch, 20 * inch), frame: back, in: t3)
            let r = try FurnitureBays.createBay(face: .front, at: Vec2(18 * inch, 20 * inch), frame: back, in: t3)
            _ = try FurnitureFronts.createFront(.door, in: l, in: t3)
            _ = try FurnitureFronts.createFront(.door, in: r, hingeFlipped: true, in: t3)
            let middle = try FurnitureBays.createBay(face: .front, at: Vec2(0, 20 * inch), in: t3)
            _ = try FurnitureFronts.createDrawers(in: middle, count: 3, in: t3)
        } catch { return nil }
        return try? t3.commit().model
    }

    /// A 36" x 18" x 18" chest (sides, front, back, a raised bottom) with a lid of `lidType` on its top opening.
    public static func chestModel(lidType: String = "Lid - Shaker Piano Hinge") -> BIMModel? {
        let tx = TransactionContext(model: FurnitureTemplates.blank(category: .furniture, name: "Chest"), name: "Chest")
        do {
            try FurnitureParameters.setValue("Width", .double(36 * inch), in: tx)
            try FurnitureParameters.setValue("Depth", .double(18 * inch), in: tx)
            try FurnitureParameters.setValue("Height", .double(18 * inch), in: tx)
            let l = -18 * inch, r = 18 * inch, f = -9 * inch, b = 9 * inch, t = 0.75 * inch
            let ply = type(tx.model, .furniturePanels, "3/4\" Plywood")
            _ = try FurniturePartOperations.createPanel(start: Vec2(l, f), end: Vec2(l, b), extent: PartExtent(), typeID: ply, in: tx)
            _ = try FurniturePartOperations.createPanel(start: Vec2(r, b), end: Vec2(r, f), extent: PartExtent(), typeID: ply, in: tx)
            _ = try FurniturePartOperations.createPanel(start: Vec2(r - t, f), end: Vec2(l + t, f), extent: PartExtent(), typeID: ply, in: tx)
            _ = try FurniturePartOperations.createPanel(start: Vec2(l + t, b), end: Vec2(r - t, b), extent: PartExtent(), typeID: ply, in: tx)
            _ = try FurniturePartOperations.createShelf(boundary: [Vec2(l + t, f + t), Vec2(r - t, f + t), Vec2(r - t, b - t), Vec2(l + t, b - t)], plane: "Bottom",
                                                        offset: 2 * inch, role: .bottom, typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Shelf"), in: tx)
        } catch { return nil }
        guard let m = try? tx.commit().model else { return nil }
        let t2 = TransactionContext(model: m, name: "Lid")
        do {
            let bay = try FurnitureBays.createBay(face: .top, at: .zero, in: t2)
            let lt = t2.model.types(for: .furnitureFronts).first { $0.typeData?.familyName == FrontKind.flap.rawValue && $0.name == lidType }?.id
            _ = try FurnitureFronts.createFront(.flap, in: bay, typeID: lt, in: t2)
        } catch { return nil }
        return try? t2.commit().model
    }
}
