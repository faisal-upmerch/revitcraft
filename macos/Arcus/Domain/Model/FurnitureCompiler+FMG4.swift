import Foundation
import ArcusGeometry

// FMG4: elevation swings that flex. Each leaf's swing (the dashed lines from its far corners to the middle of its
// hinge edge) is a small nested family drawn in the leaf's own size (Leaf Width, Leaf Height), placed at the leaf's
// lower near corner on its face and turned with the face: its size and place follow the planes, on the front, back and
// side faces and between a canted face's corners, and it shows by the variant's yes/no parameter (Leaf Count by type,
// Visible associated with a family parameter).

extension FurnitureCompiler {
    /// The swing families by hinge edge.
    static func swingFamily(_ hinge: HingeEdge) -> FamilyDefinition {
        var f = FamilyDefinition(name: "Elevation Swing \(hinge.rawValue)", template: .genericModel)
        f.parameters = [FamilyParameter(name: "Leaf Width", type: .length), FamilyParameter(name: "Leaf Height", type: .length)]
        f.types = [FamilyTypeDefinition(name: "Swing", values: ["Leaf Width": .double(0.4), "Leaf Height": .double(0.6)])]
        let (w, h, w2, h2) = ("Leaf Width", "Leaf Height", "Leaf Width / 2", "Leaf Height / 2")
        let pts: [(String, String, String, String)] = switch hinge {
        case .left: [(w, h, "0", h2), ("0", h2, w, "0")]
        case .right: [("0", h, w, h2), (w, h2, "0", "0")]
        case .top: [("0", "0", w2, h), (w2, h, w, "0")]
        case .bottom: [("0", h, w2, "0"), (w2, "0", w, h)]
        case .back: [] // lids (FurnitureCompiler+FMG3 draws theirs)
        }
        f.modelLines = pts.map { a in
            var l = FamilyModelLine(plane: .xz, offset: .expr("0"), start: FamilyPoint(a.0, a.1), end: FamilyPoint(a.2, a.3))
            l.subcategory = .elevationSwing
            l.visibleAt = [.medium, .fine]
            return l
        }
        return f
    }

    /// A coordinate as a length formula of the family being compiled (sums of planes included).
    static func formula(_ v: PartValue, _ ctx: PartSolidContext) -> String {
        guard let p = v.plane, let pf = ctx.planeFormula else { return "\(FurnitureFormLocks.num(v.value)) m" }
        if PlaneTerms.isSum(p) { return PlaneTerms.expression(p, offset: v.offset, pf) ?? "\(FurnitureFormLocks.num(v.value)) m" }
        guard let o = pf(p)?.trimmingCharacters(in: .whitespaces) else { return "\(FurnitureFormLocks.num(v.value)) m" }
        let base = Double(o).map { "\(FurnitureFormLocks.num($0)) m" } ?? "(\(o))"
        return abs(v.offset) < 1e-12 ? base : "\(base) \(lengthTerm(v.offset))"
    }

    /// Adds a front's leaf swings (doors and flaps on the front, back, side and canted faces) as placed swing families.
    /// Returns false when the front has none to add this way (lids, drawers).
    @discardableResult
    static func addLeafSwings(_ front: Element, _ m: BIMModel, _ ctx: PartSolidContext, to f: inout FamilyDefinition, visibility: String?) -> Bool {
        guard let g = FurnitureFronts.geometry(front, m), g.face == .front, front.furnitureFront?.kind != .drawer else { return false }
        let anchors = CantAnchors(g.opening, g.frame)
        let n = PartSolidContext.number
        for leaf in g.leaves {
            guard let hinge = leaf.hinge, hinge != .back else { continue }
            let fam = swingFamily(hinge)
            if f.nestedFamily(named: fam.name) == nil { f.nestedFamilies.append(fam) }
            let (u0, u1) = leaf.u.0.value <= leaf.u.1.value ? leaf.u : (leaf.u.1, leaf.u.0)
            let (z0, z1) = leaf.v.0.value <= leaf.v.1.value ? leaf.v : (leaf.v.1, leaf.v.0)
            let outer = (leaf.w.0.value <= leaf.w.1.value ? leaf.w.0 : leaf.w.1).shifted(-0.0005) // a hair in front of the leaf
            var inst: NestedFamilyInstance
            if g.frame.isIdentity {
                inst = NestedFamilyInstance(familyName: fam.name, typeName: "Swing", x: ctx.bound(u0), y: ctx.bound(outer), z: ctx.bound(z0), rotation: "0", mirrored: false)
                inst.bindings["Leaf Width"] = "(\(formula(u1, ctx))) - (\(formula(u0, ctx)))"
            } else if g.frame.isSquare {
                let p = g.frame.world((u0, outer, z0))
                inst = NestedFamilyInstance(familyName: fam.name, typeName: "Swing", x: ctx.bound(p.x), y: ctx.bound(p.y), z: ctx.bound(p.z),
                                            rotation: n(g.frame.angle * 180 / .pi), mirrored: false)
                inst.bindings["Leaf Width"] = "\(n(u1.value - u0.value)) m"
                if u0.plane != nil || u1.plane != nil { inst.bindings["Leaf Width"] = "(\(formula(u1, ctx))) - (\(formula(u0, ctx)))" }
            } else if let a = anchors, ctx.symbolic, let xy = a.point(u0.value, outer.value, ctx), let rot = a.rotationFormula(g.frame.angle * 180 / .pi, ctx),
                      let span = a.span(u0.value, u1.value, ctx) {
                inst = NestedFamilyInstance(familyName: fam.name, typeName: "Swing", x: xy.0, y: xy.1, z: ctx.bound(z0), rotation: rot, mirrored: false)
                inst.bindings["Leaf Width"] = span
            } else {
                let p = g.frame.world(Vec2(u0.value, outer.value))
                inst = NestedFamilyInstance(familyName: fam.name, typeName: "Swing", x: .expr(n(p.x)), y: .expr(n(p.y)), z: ctx.bound(z0),
                                            rotation: n(g.frame.angle * 180 / .pi), mirrored: false)
                inst.bindings["Leaf Width"] = "\(n(u1.value - u0.value)) m"
            }
            inst.bindings["Leaf Height"] = "(\(formula(z1, ctx))) - (\(formula(z0, ctx)))"
            inst.visibleAt = [.medium, .fine]
            inst.visibilityParameter = visibility
            f.nestedInstances.append(inst)
        }
        return true
    }
}

// MARK: - Lid swings in plan

extension FurnitureSwings {
    /// FMG4: a lid's swing seen from above, as casework drawings show a lid: the dashed lines from its front corners to
    /// the middle of its hinged (back) edge, pointing at the hinge. Leaf coordinates (u along x, v along y).
    public static func lidPlanPoints(_ front: Element, _ m: BIMModel) -> [[(x: PartValue, y: PartValue)]] {
        guard let g = FurnitureFronts.geometry(front, m), g.face == .top else { return [] }
        var out: [[(x: PartValue, y: PartValue)]] = []
        for leaf in g.leaves where leaf.hinge == .back {
            let (u0, u1) = leaf.u.0.value <= leaf.u.1.value ? leaf.u : (leaf.u.1, leaf.u.0)
            let (v0, v1) = leaf.v.0.value <= leaf.v.1.value ? leaf.v : (leaf.v.1, leaf.v.0)
            let mid = PartValue.sum(u0, u1).scaled(0.5)
            out.append([(u0, v0), (mid, v1), (u1, v0)])
        }
        return out
    }

    /// The lid plan swing as plan segments (model x, y).
    public static func lidPlan(_ front: Element, _ m: BIMModel) -> [Segment2] {
        lidPlanPoints(front, m).flatMap { pts in
            zip(pts, pts.dropFirst()).map { Segment2(Vec2($0.0.x.value, $0.0.y.value), Vec2($0.1.x.value, $0.1.y.value)) }
        }
    }
}

extension FurnitureCompiler {
    /// FMG4: a lid's plan swing as symbolic lines on the lid's planes (they flex with it), dashed (Elevation Swing).
    static func lidPlanLines(_ front: Element, _ m: BIMModel, _ ctx: PartSolidContext, visibility: String?) -> [FamilyLine] {
        FurnitureSwings.lidPlanPoints(front, m).flatMap { pts in
            zip(pts, pts.dropFirst()).map { a, b in
                var l = FamilyLine(shape: .line(FamilyPoint(ctx.bound(a.x), ctx.bound(a.y)), FamilyPoint(ctx.bound(b.x), ctx.bound(b.y))), subcategory: .elevationSwing)
                l.visibleAt = [.medium, .fine]
                l.visibilityParameter = visibility
                return l
            }
        }
    }
}
