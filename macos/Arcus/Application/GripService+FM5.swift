import Foundation
import ArcusGeometry
import ArcusDomain

// FM5: grips and controls of bays, separators and fronts. Bay Separators have end grips in the view they're seen in
// (the Front/Back elevation, or plan), as room separators. A single door shows the flip arrows under it in the Front
// elevation and in front of it in plan, as a door's hand control: clicking them flips the hinge side.

extension GripService {
    /// Separator end grips; [] for bays and fronts (they follow their parts and bays), nil for other elements.
    static func fm5Grips(_ e: Element, _ model: BIMModel, viewID: ElementID?) -> [Grip]? {
        switch e.data {
        case .furnitureBaySeparator(let s):
            // FMG3: in the views looking at the separator's face.
            guard let map = FurnitureFaceMap.of(model[viewID]?.view), map.face == s.face, s.face == .top || map.frame == BayFrame(angle: s.facing ?? 0) else { return [] }
            return [Grip(elementID: e.id, kind: .start, position: map.toView(s.start), viewID: viewID), Grip(elementID: e.id, kind: .end, position: map.toView(s.end), viewID: viewID)]
        case .furnitureBay, .furnitureFront: return []
        default: return nil
        }
    }

    /// Applies a separator grip drag (kept square to the piece); false for other elements.
    static func fm5Apply(_ g: Grip, to p: Vec2, in tx: TransactionContext) -> Bool {
        guard let e = tx.model[g.elementID], var s = e.furnitureBaySeparator else { return false }
        guard let map = FurnitureFaceMap.of(tx.model[g.viewID]?.view) else { return true } // FMG3
        let q = map.toLocal(p)
        let fixed = g.kind == .start ? s.end : s.start
        let moved = s.isVertical ? Vec2(fixed.x, q.y) : Vec2(q.x, fixed.y)
        if g.kind == .start { s.start = moved } else { s.end = moved }
        guard s.start.distance(to: s.end) > Tolerance.shortCurve else { return true }
        tx.update(g.elementID) { $0.furnitureBaySeparator = s }
        return true
    }

    /// The hinge flip arrows of a single door; nil for elements that aren't fronts.
    static func fm5Controls(_ e: Element, _ model: BIMModel, view: Element?, pixel: Double) -> [Grip]? {
        guard let f = e.furnitureFront else { return nil }
        guard f.kind == .door, let g = FurnitureFronts.geometry(e, model), g.face == .front, g.leaves.count == 1, let leaf = g.leaves.first,
              let map = FurnitureFaceMap.of(view?.view) else { return [] }
        let gap = 16 * pixel
        let toward = leaf.hinge == .left ? -1.0 : 1.0
        // FMG3: under the door in the views looking at its face, in front of it in plan (turned with the face).
        switch map.face {
        case .front:
            guard map.frame == g.frame else { return [] }
            let a = map.toView(Vec2(leaf.rect.center.x, leaf.v.0.value))
            let dir = (map.toView(Vec2(leaf.rect.center.x + toward, leaf.v.0.value)) - a).normalized
            return [Grip(elementID: e.id, kind: .flipHand, position: a - Vec2(0, gap), direction: dir)]
        case .top:
            let c = g.frame.world(Vec2(leaf.rect.center.x, g.outerFace))
            return [Grip(elementID: e.id, kind: .flipHand, position: c + g.frame.outward * gap, direction: g.frame.world(Vec2(toward, 0)))]
        }
    }
}
