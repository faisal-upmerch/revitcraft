import Foundation
import ArcusGeometry

// FM8: what a loaded piece costs, for the project's Cost type parameter (Identity Data) and so Furniture Schedules can
// total it. A simple estimate from the Furniture document: each part's cut size priced by its material's cost and
// unit, door and drawer fronts by their area, and the hardware's type cost. Labour, finishing, edge banding and offcuts
// are left out. FM7's Material Takeoff and Part List are the detailed takeoff.

public enum FurnitureCostEstimate {
    static let squareFoot = 0.09290304 // m²
    static let boardFoot = 0.0023597372 // m³ (144 in³)
    static let foot = 0.3048
    /// A stock sheet, 4' x 8'.
    static let sheet = 32 * squareFoot

    /// The price of `amount` of material `id`: area (m²), volume (m³) or length (m) as its cost unit needs.
    static func price(_ id: ElementID?, area: Double, volume: Double, length: Double, _ m: BIMModel) -> Double {
        guard let mat = m[id]?.material, mat.cost > 0 else { return 0 }
        switch mat.costUnit {
        case .sheet?: return mat.cost * area / sheet
        case .squareFoot?: return mat.cost * area / squareFoot
        case .boardFoot?: return mat.cost * volume / boardFoot
        case .linearFoot?: return mat.cost * length / foot
        case .each?: return mat.cost
        case nil: return mat.cost * area / squareFoot
        }
    }

    /// The estimated cost of the piece as it is (its current type), in the document's currency.
    public static func cost(of m: BIMModel) -> Double {
        guard m.isFurniture else { return 0 }
        var total = 0.0
        for e in Category.furnitureParts.flatMap({ m.elements($0) }) {
            guard e.furnitureForm?.isVoid != true, e.furnitureEdgeProfile == nil, let (l, w, t) = FurnitureJoints.cutSize(of: e.id, in: m) else { continue }
            let material = FurniturePartTypes.values(of: e, m).material
            total += price(material, area: l * w, volume: l * w * t, length: l, m)
        }
        for e in m.elements(.furnitureFronts) {
            guard let g = FurnitureFronts.geometry(e, m) else { continue }
            let material = FurnitureFrontTypes.values(of: e, m).material
            for leaf in g.leaves { total += price(material, area: leaf.width * leaf.height, volume: leaf.width * leaf.height * g.thickness, length: max(leaf.width, leaf.height), m) }
        }
        for h in m.elements(.furnitureHardware) { total += FurnitureHardware.values(of: h, m).cost }
        return (total * 100).rounded() / 100
    }

    /// The estimated cost of each of the piece's types (the document regenerated at each type's values).
    public static func costs(byType m: BIMModel) -> [String: Double] {
        guard let setup = m.furnitureSetup else { return [:] }
        var out: [String: Double] = [:]
        for t in setup.family.types {
            if t.name == setup.currentType { out[t.name] = cost(of: m); continue }
            let tx = TransactionContext(model: m, name: "Cost")
            guard (try? FurnitureParameters.setCurrentType(t.name, in: tx)) != nil, let c = try? tx.commit() else { continue }
            out[t.name] = cost(of: c.model)
        }
        return out
    }
}
