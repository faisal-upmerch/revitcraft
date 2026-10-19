import Foundation
import ArcusGeometry
import ArcusDomain

// FM4: grips of furniture parts. Panels and rails have end grips where their line is seen (in plan when drawn in plan,
// in the elevation they were drawn in); in an elevation a plan-drawn panel or a leg shows shape-handle arrows at its top
// and base (drag to set them; they then follow the plane they're dropped on). Legs have a point grip in plan. The
// arrows reuse the `.sectionDepth` triangle glyph; `isOn` tells the top arrow from the base arrow.

extension GripService {
    /// The furniture part grips in a view, or nil for elements that aren't parts.
    static func fm4Grips(_ e: Element, _ model: BIMModel, viewID: ElementID?) -> [Grip]? {
        guard e.category.isFurniturePart else { return nil }
        guard let view = model[viewID]?.view, let map = FurnitureSketchMap.of(view) else { return [] }
        var out: [Grip] = []
        func ends(_ plane: FamilySketchPlane, _ s: Vec2, _ en: Vec2) {
            guard plane == map.plane else { return }
            out.append(Grip(elementID: e.id, kind: .start, position: map.toView(s), viewID: viewID))
            out.append(Grip(elementID: e.id, kind: .end, position: map.toView(en), viewID: viewID))
        }
        func arrows(_ b: Box3) {
            guard map.plane != .xy else { return }
            let u = (map.project(b.min).x + map.project(b.max).x) / 2
            out.append(Grip(elementID: e.id, kind: .sectionDepth, position: Vec2(u, b.max.z), direction: Vec2(0, 1), isOn: true, viewID: viewID))
            out.append(Grip(elementID: e.id, kind: .sectionDepth, position: Vec2(u, b.min.z), direction: Vec2(0, -1), isOn: false, viewID: viewID))
        }
        switch e.data {
        case .furniturePanel(let p):
            ends(p.plane, p.start, p.end)
            if p.plane == .xy, let b = FurniturePartSolids.partBox(e, model)?.box { arrows(b) }
        case .furnitureRail(let r): ends(r.plane, r.start, r.end)
        case .furnitureLeg(let l):
            if map.plane == .xy { out.append(Grip(elementID: e.id, kind: .point, position: l.location, viewID: viewID)) }
            else if let b = FurniturePartSolids.partBox(e, model)?.box ?? FurniturePartMeshes.meshParts(e, model, detail: .coarse).first?.mesh.bounds { arrows(b) }
        default: break
        }
        return out
    }

    /// Applies a part grip drag; false for other elements.
    static func fm4Apply(_ g: Grip, to p: Vec2, in tx: TransactionContext) -> Bool {
        guard let e = tx.model[g.elementID], e.category.isFurniturePart else { return false }
        guard let map = FurnitureSketchMap.of(tx.model[g.viewID]?.view) else { return true }
        let s = map.toSketch(p)
        tx.update(g.elementID) { e in
            switch (e.data, g.kind) {
            case (.furniturePanel(var d), .start): d.start = s; e.data = .furniturePanel(d)
            case (.furniturePanel(var d), .end): d.end = s; e.data = .furniturePanel(d)
            case (.furnitureRail(var d), .start): d.start = s; e.data = .furnitureRail(d)
            case (.furnitureRail(var d), .end): d.end = s; e.data = .furnitureRail(d)
            case (.furnitureLeg(var d), .point): d.location = p; e.data = .furnitureLeg(d)
            case (.furniturePanel(var d), .sectionDepth):
                if g.isOn { if p.y - d.base > Tolerance.length { d.top = p.y; d.attachedTopID = nil } }
                else if d.top - p.y > Tolerance.length { d.base = p.y; d.attachedBaseID = nil }
                e.data = .furniturePanel(d)
            case (.furnitureLeg(var d), .sectionDepth):
                if g.isOn { if p.y - d.base > Tolerance.length { d.top = p.y; d.attachedTopID = nil } }
                else if d.top - p.y > Tolerance.length { d.base = p.y }
                e.data = .furnitureLeg(d)
            default: break
            }
        }
        return true
    }

    /// The flip arrows of a panel drawn in plan, outside its outside face (as a wall's).
    static func fm4Controls(_ e: Element, _ model: BIMModel, view: Element?, pixel: Double) -> [Grip]? {
        guard let p = e.furniturePanel else { return e.category.isFurniturePart ? [] : nil }
        guard let map = FurnitureSketchMap.of(view?.view), map.plane == p.plane, p.length > Tolerance.length else { return [] }
        let t = FurniturePartTypes.values(of: e, model).thickness
        let (fo, _) = FurniturePartSolids.faceOffsets(p, thickness: t)
        let d = (p.end - p.start).normalized, n = d.perpendicular
        // The outside is the side of the outside face from the line (the left of the line, or the right when flipped).
        let side: Double = p.flipped ? -1 : 1
        let mid = p.start.midpoint(p.end) + n * fo
        let a = map.toView(mid), b = map.toView(mid + n * side)
        let dir = (b - a).normalized
        return [Grip(elementID: e.id, kind: .flipWall, position: a + dir * 16 * pixel, direction: dir)]
    }
}
