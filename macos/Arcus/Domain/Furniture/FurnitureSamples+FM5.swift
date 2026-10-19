import Foundation
import ArcusGeometry

// FM5: a sample base cabinet built with the operations the tools call: a 54" x 24" x 34 1/2" carcass (sides, raised
// bottom, top, back, toe kick) split by two EQ dividers into three bays; a door hinged left, a stack of three drawers
// (Bay Divide, EQ) and a door hinged right. Tests, QA captures and render checks use it.

extension FurnitureSamples {
    /// The carcass of the base cabinet (commit it before `baseCabinetFronts`, which picks the bays from it).
    @discardableResult
    public static func baseCabinet(in tx: TransactionContext, width: Double = 54, depth: Double = 24, height: Double = 34.5) throws(TransactionError) -> [String: ElementID] {
        try FurnitureParameters.setValue("Width", .double(width * inch), in: tx)
        try FurnitureParameters.setValue("Depth", .double(depth * inch), in: tx)
        try FurnitureParameters.setValue("Height", .double(height * inch), in: tx)
        let l = -width * inch / 2, r = width * inch / 2, f = -depth * inch / 2, b = depth * inch / 2
        let t = 0.75 * inch, kick = 4 * inch
        var ids: [String: ElementID] = [:]
        let ply = type(tx.model, .furniturePanels, "3/4\" Plywood")
        ids["left"] = try FurniturePartOperations.createPanel(start: Vec2(l, f), end: Vec2(l, b), extent: PartExtent(), typeID: ply, in: tx)
        ids["right"] = try FurniturePartOperations.createPanel(start: Vec2(r, b), end: Vec2(r, f), extent: PartExtent(), typeID: ply, in: tx)
        let inside = [Vec2(l + t, f), Vec2(r - t, f), Vec2(r - t, b), Vec2(l + t, b)]
        ids["top"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Top", offset: 0, role: .top, typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Top"), in: tx)
        ids["bottom"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: kick + t, role: .bottom,
                                                                typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Shelf"), in: tx)
        return ids
    }

    /// The back, toe kick and two EQ dividers, picked from the committed carcass.
    public static func baseCabinetInterior(in tx: TransactionContext, _ ids: [String: ElementID]) throws(TransactionError) {
        guard let bottom = ids["bottom"] else { return }
        _ = try FurniturePartOperations.createPlinth(under: bottom, setback: 3 * inch, in: tx)
        let back = type(tx.model, .furniturePanels, "1/4\" Back Panel (Hardboard)")
        let mid = Vec2(0, 20 * inch)
        _ = try FurniturePartOperations.createBack(atFront: mid, fit: .inside, typeID: back, in: tx)
        _ = try FurniturePartOperations.createDividers(atFront: mid, vertical: true, count: 2, typeID: type(tx.model, .furniturePanels, "3/4\" Plywood"), in: tx)
    }

    /// Bays in the three openings, a door hinged left, three drawers and a door hinged right. Returns the bays and
    /// fronts by name ("leftBay", "drawerBay", "rightBay", "leftDoor", "rightDoor", "drawers").
    public static func baseCabinetFronts(in tx: TransactionContext) throws(TransactionError) -> [String: [ElementID]] {
        let w = (FurniturePlanes.positionsByName(tx.model)["Right"] ?? 0) * 2
        let z = 20 * inch
        var out: [String: [ElementID]] = [:]
        let left = try FurnitureBays.createBay(face: .front, at: Vec2(-w / 3, z), in: tx)
        let middle = try FurnitureBays.createBay(face: .front, at: Vec2(0, z), in: tx)
        let right = try FurnitureBays.createBay(face: .front, at: Vec2(w / 3, z), in: tx)
        out["leftBay"] = [left]; out["drawerBay"] = [middle]; out["rightBay"] = [right]
        out["leftDoor"] = try FurnitureFronts.createFront(.door, in: left, in: tx)
        out["rightDoor"] = try FurnitureFronts.createFront(.door, in: right, hingeFlipped: true, in: tx)
        out["drawers"] = try FurnitureFronts.createDrawers(in: middle, count: 3, in: tx)
        return out
    }

    /// A Furniture document with the base cabinet, its bays, fronts and hardware.
    public static func baseCabinetModel() -> BIMModel? {
        var m = FurnitureTemplates.blank(category: .casework, name: "Base Cabinet")
        let tx = TransactionContext(model: m, name: "Base Cabinet")
        guard let ids = try? baseCabinet(in: tx), let c = try? tx.commit() else { return nil }
        m = c.model
        let tx2 = TransactionContext(model: m, name: "Back, Kick and Dividers")
        guard (try? baseCabinetInterior(in: tx2, ids)) != nil, let c2 = try? tx2.commit() else { return nil }
        m = c2.model
        let tx3 = TransactionContext(model: m, name: "Doors and Drawers")
        guard (try? baseCabinetFronts(in: tx3)) != nil, let c3 = try? tx3.commit() else { return nil }
        return c3.model
    }
}
