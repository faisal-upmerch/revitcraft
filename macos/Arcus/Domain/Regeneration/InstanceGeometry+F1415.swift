import Foundation
import ArcusGeometry

// F1415: family model lines and flip controls on placed instances (RevitCraft `grips.rs`: "Flip controls of families that
// have them, at their places in the family").

extension FamilyInstanceGeometry {
    /// Plan symbols of a family's model lines (reference lines never show in projects), projected to plan.
    static func f1415ModelLineSymbols(_ ev: EvaluatedFamily, transform t: Transform2) -> [PlanSymbol] {
        ev.modelLines.compactMap { l in
            guard !l.isReference else { return nil }
            let s = Segment2(l.start.xy, l.end.xy)
            guard !s.isDegenerate else { return nil }
            return PlanSymbol(curve: Curve2.line(s).transformed(t), subcategory: l.subcategory, visibleAt: l.visibleAt)
        }
    }

    /// The flip controls of a placed component in world plan coordinates: where each sits, whether it flips the hand
    /// (horizontal controls) or the facing, and the axis its arrows point along.
    public static func controls(_ e: Element, _ model: BIMModel) -> [(position: Vec2, flipsHand: Bool, direction: Vec2, kind: FamilyControlKind)] {
        guard e.component != nil, let p = ComponentGeometry.placement(e, model), let ev = evaluate(e, model), !ev.controls.isEmpty else { return [] }
        let x = p.plan.applyVector(.unitX).normalized, y = p.plan.applyVector(Vec2(0, 1)).normalized
        return ev.controls.map { c in (p.plan.apply(c.position), c.kind.isHorizontal, c.kind.isHorizontal ? x : y, c.kind) }
    }
}
