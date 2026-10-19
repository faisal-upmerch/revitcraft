import Foundation
import ArcusGeometry

// FM4: two sample pieces built with the part operations the tools use: a bookcase (casework: sides, top, raised bottom,
// plinth, adjustable shelves, a back) and a dining table (a butcher-block top, tapered legs At Corners and aprons).
// QA captures and render checks use them; the furniture library (FM9) builds its pieces the same way.

public enum FurnitureSamples {
    static let inch = 0.0254

    static func plane(_ m: BIMModel, _ n: String) -> Double { FurniturePlanes.positionsByName(m)[n] ?? 0 }
    static func type(_ m: BIMModel, _ cat: Category, _ name: String) -> ElementID? { m.types(for: cat).first { $0.name == name }?.id }

    /// A 36" x 12" x 72" bookcase in `tx` (a Furniture document): 3/4" plywood sides, top and raised bottom, a recessed
    /// plinth, four adjustable shelves and a 1/4" back. Returns the parts by role.
    @discardableResult
    public static func bookcase(in tx: TransactionContext, width: Double = 36, depth: Double = 12, height: Double = 72) throws(TransactionError) -> [String: ElementID] {
        try FurnitureParameters.setValue("Width", .double(width * inch), in: tx)
        try FurnitureParameters.setValue("Depth", .double(depth * inch), in: tx)
        try FurnitureParameters.setValue("Height", .double(height * inch), in: tx)
        // The planes move at commit; work with their values here.
        let l = -width * inch / 2, r = width * inch / 2, f = -depth * inch / 2, b = depth * inch / 2
        let t = 0.75 * inch
        var ids: [String: ElementID] = [:]
        let ply = type(tx.model, .furniturePanels, "3/4\" Plywood")
        ids["left"] = try FurniturePartOperations.createPanel(start: Vec2(l, f), end: Vec2(l, b), extent: PartExtent(), typeID: ply, in: tx)
        ids["right"] = try FurniturePartOperations.createPanel(start: Vec2(r, b), end: Vec2(r, f), extent: PartExtent(), typeID: ply, in: tx)
        let inside = [Vec2(l + t, f), Vec2(r - t, f), Vec2(r - t, b), Vec2(l + t, b)]
        let shelfType = type(tx.model, .furnitureShelves, "3/4\" Plywood Shelf")
        ids["top"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Top", offset: 0, role: .top, typeID: type(tx.model, .furnitureShelves, "3/4\" Plywood Top"), in: tx)
        ids["bottom"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: 3.5 * inch + t, role: .bottom, typeID: shelfType, in: tx)
        for (k, z) in [17.0, 31, 45, 59].enumerated() {
            ids["shelf\(k + 1)"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: z * inch, adjustable: true, frontSetback: 0.25 * inch, typeID: shelfType, in: tx)
        }
        return ids
    }

    /// Adds the plinth and the back once the carcass is committed (they're picked from it, as the tools pick).
    public static func bookcaseFinish(in tx: TransactionContext, _ ids: [String: ElementID]) throws(TransactionError) {
        guard let bottom = ids["bottom"] else { return }
        _ = try FurniturePartOperations.createPlinth(under: bottom, setback: 0.5 * inch, in: tx)
        let back = type(tx.model, .furniturePanels, "1/4\" Back Panel (Hardboard)")
        let mid = Vec2(0, 30 * inch)
        _ = try FurniturePartOperations.createBack(atFront: mid, fit: .inside, typeID: back, in: tx)
    }

    /// A 60" x 36" x 30" dining table in `tx`: a 1 1/2" butcher-block top with round-over edges, tapered legs At Corners
    /// and 3/4" x 3" aprons between them.
    @discardableResult
    public static func table(in tx: TransactionContext, width: Double = 60, depth: Double = 36, height: Double = 30) throws(TransactionError) -> [String: ElementID] {
        try FurnitureParameters.setValue("Width", .double(width * inch), in: tx)
        try FurnitureParameters.setValue("Depth", .double(depth * inch), in: tx)
        try FurnitureParameters.setValue("Height", .double(height * inch), in: tx)
        let l = -width * inch / 2, r = width * inch / 2, f = -depth * inch / 2, b = depth * inch / 2
        var ids: [String: ElementID] = [:]
        ids["top"] = try FurniturePartOperations.createShelf(boundary: [Vec2(l, f), Vec2(r, f), Vec2(r, b), Vec2(l, b)], plane: "Top", offset: 0, role: .top,
                                                             typeID: type(tx.model, .furnitureShelves, "1 1/2\" Butcher Block"), in: tx)
        return ids
    }

    /// The table's legs and aprons, picked from its committed top.
    public static func tableFinish(in tx: TransactionContext, _ ids: [String: ElementID]) throws(TransactionError) {
        guard let top = ids["top"], let tb = FurniturePartSolids.partBox(tx.model[top]!, tx.model)?.box else { return }
        let inset = 2 * inch
        let legType = type(tx.model, .furnitureLegs, "Square Tapered 1 3/4\"")
        _ = try FurniturePartOperations.legsAtCorners(of: top, inset: inset, typeID: legType, in: tx)
        let lw = FurniturePartTypes.Values(tx.model[legType]?.typeData).width
        let apron = type(tx.model, .furnitureRails, "3/4\" x 3\" Apron")
        let x0 = tb.min.x + inset + lw, x1 = tb.max.x - inset - lw, y0 = tb.min.y + inset + lw, y1 = tb.max.y - inset - lw
        let yf = tb.min.y + inset + lw / 2, yb = tb.max.y - inset - lw / 2, xl = tb.min.x + inset + lw / 2, xr = tb.max.x - inset - lw / 2
        let under = tb.min.z - (FurniturePlanes.positionsByName(tx.model)["Top"] ?? tb.max.z)
        for (s, e) in [(Vec2(x0, yf), Vec2(x1, yf)), (Vec2(x1, yb), Vec2(x0, yb)), (Vec2(xl, y1), Vec2(xl, y0)), (Vec2(xr, y0), Vec2(xr, y1))] {
            _ = try FurniturePartOperations.createRail(start: s, end: e, w: under, wPlane: "Top", justification: .top, typeID: apron, in: tx)
        }
    }

    /// A Furniture document with the bookcase.
    public static func bookcaseModel() -> BIMModel? {
        var m = FurnitureTemplates.blank(category: .casework, name: "Bookcase")
        let tx = TransactionContext(model: m, name: "Bookcase")
        guard let ids = try? bookcase(in: tx), let c = try? tx.commit() else { return nil }
        m = c.model
        let tx2 = TransactionContext(model: m, name: "Plinth and Back")
        guard (try? bookcaseFinish(in: tx2, ids)) != nil, let c2 = try? tx2.commit() else { return nil }
        return c2.model
    }

    /// A Furniture document with the dining table.
    public static func tableModel() -> BIMModel? {
        var m = FurnitureTemplates.blank(category: .furniture, name: "Dining Table")
        let tx = TransactionContext(model: m, name: "Table")
        guard let ids = try? table(in: tx), let c = try? tx.commit() else { return nil }
        m = c.model
        let tx2 = TransactionContext(model: m, name: "Legs and Aprons")
        guard (try? tableFinish(in: tx2, ids)) != nil, let c2 = try? tx2.commit() else { return nil }
        return c2.model
    }
}
