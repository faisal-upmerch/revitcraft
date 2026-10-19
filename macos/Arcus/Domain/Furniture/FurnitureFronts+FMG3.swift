import Foundation
import ArcusGeometry
import ArcusCalc

// FMG3: lids (doors and flaps on top-access bays). A lid hinges on its back edge (concealed hinges, or a piano hinge
// along the whole edge), is held open by a lid stay on the side (two on lids wider than 24"), can be Slab, Shaker or
// Glass Panel, and shows its swing in the side elevations: the lid open upright and the arc its front edge sweeps.

extension FurnitureFronts {
    /// The stay a lid uses: its type's when that is a lid (drop-down) stay, else the standard lid stay.
    static func lidStayType(_ tv: FurnitureFrontTypes.Values, _ m: BIMModel) -> ElementID? {
        if let st = tv.stayType, FurnitureHardware.Values(m[st]?.typeData).kind == .stay,
           m[st]?.typeData?.params[Parameters.familyParamID("Drop Down")]?.boolValue == true { return st }
        return FurnitureHardware.type(FurnitureHardware.flapStay, "Drop-Down Stay", m)
    }

    /// Lid stays: on the left side's inside face under the lid's back, and on the right side too when the lid is wider
    /// than 24" (in the bay's frame, as the other hardware).
    static func lidStays(_ e: Element, _ g: FrontGeometry, _ tv: FurnitureFrontTypes.Values, _ m: BIMModel) -> [HardwarePlacement] {
        guard g.face == .top, let st = lidStayType(tv, m) else { return [] }
        let o = g.opening
        let arm = FurnitureHardware.Values(m[st]?.typeData).d("Arm Length", 0.25)
        let depth = o.y1 - o.y0
        // The stay's arm runs forward from the bracket at the back, under the lid.
        let back = min(depth - 0.02, arm + 0.04)
        let y = o.value("y1").shifted(-back), z = o.value("z1").shifted(-0.03)
        var out = [HardwarePlacement(slot: "stay.0", typeID: st, at: (o.value("x0"), y, z), mirrored: false, values: [:], carcassPartID: o.left)]
        if o.width > 24 * inch {
            out.append(HardwarePlacement(slot: "stay.1", typeID: st, at: (o.value("x1"), y, z), mirrored: true, values: [:], carcassPartID: o.right))
        }
        return out
    }
}

extension FurnitureSwings {
    /// A lid's swing seen from the side: the lid open upright on its back hinge and the quarter arc its front edge sweeps,
    /// as model polylines at the lid's middle (x).
    public static func lidElevation(_ front: Element, _ m: BIMModel) -> [[Vec3]] {
        guard let g = FurnitureFronts.geometry(front, m), g.face == .top else { return [] }
        var out: [[Vec3]] = []
        for leaf in g.leaves where leaf.hinge == .back {
            let x = (leaf.u.0.value + leaf.u.1.value) / 2
            let yb = leaf.v.1.value, yf = leaf.v.0.value, z = leaf.w.1.value
            let r = yb - yf
            guard r > Tolerance.length else { continue }
            out.append([Vec3(x, yb, z), Vec3(x, yb, z + r)])
            let n = 12
            out.append((0...n).map { k in
                let a = Double(k) / Double(n) * .pi / 2
                return Vec3(x, yb - r * cos(a), z + r * sin(a))
            })
        }
        return out
    }
}

// MARK: - Leaf Count

extension FurnitureFronts {
    /// A door's Leaf Count (1 or 2): its family parameter's value in the current type when it has one, else its own,
    /// else its type's.
    public static func leafCount(_ e: Element, _ m: BIMModel) -> Int {
        guard let f = e.furnitureFront, f.kind == .door else { return 1 }
        if let p = f.leafCountParameter, let n = leafCount(of: FurnitureParameters.value(p, m)) { return n }
        if let n = f.leafCount { return n >= 2 ? 2 : 1 }
        return FurnitureFrontTypes.values(of: e, m).leafCount
    }

    /// A family parameter's value as a Leaf Count (an integer: 2 or more is a pair; yes/no: yes is a pair).
    public static func leafCount(of v: FormulaValue?) -> Int? {
        switch v {
        case .quantity(let x, _)?: x >= 1.5 ? 2 : 1
        case .bool(let b)?: b ? 2 : 1
        default: nil
        }
    }

    /// The family parameters a door's Leaf Count can follow: integer and yes/no parameters of the document.
    public static func leafCountParameters(_ m: BIMModel) -> [String] {
        m.furnitureSetup?.family.parameters.filter { $0.type == .integer || $0.type == .bool }.map(\.name) ?? []
    }

    /// Associates a door's Leaf Count with a family parameter (nil removes the association).
    public static func associateLeafCount(_ ids: [ElementID], with parameter: String?, in tx: TransactionContext) throws(TransactionError) {
        if let parameter {
            guard leafCountParameters(tx.model).contains(parameter) else {
                throw TransactionError("“\(parameter)” isn't an Integer or Yes/No family parameter.", resolution: "Add it in Family Types, then associate it.")
            }
        }
        for id in ids where tx.model[id]?.furnitureFront?.kind == .door { tx.update(id) { $0.furnitureFront?.leafCountParameter = parameter } }
    }
}
