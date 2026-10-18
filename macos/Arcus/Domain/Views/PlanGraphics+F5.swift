import Foundation
import ArcusGeometry

// F5: plan graphics of spaces, space separation lines and conceptual masses (RevitCraft plan.rs).
extension PlanGraphics {
    func f5Items(_ byCategory: [Category: [(Element, GraphicOverride)]]) -> [GItem] {
        var items: [GItem] = []
        if data.kind != .areaPlan {
            items += spaces()
            items += spaceSeparators()
        }
        items += masses(byCategory[.mass] ?? [])
        return items
    }

    /// Spaces draw as rooms do: their region (a fill only when overridden) is the selection target; an unbounded space
    /// shows a cross at its placement point.
    func spaces() -> [GItem] {
        guard let level = levelID else { return [] }
        var items: [GItem] = []
        let bounds = RoomBoundaryCache.shared.boundaries(level: level, model)
        for r in model.elements(.spaces) where r.levelID == level {
            guard let o = builder.resolver.resolve(r) else { continue }
            guard let b = bounds[r.id], let prof = b.profile, b.state == .bounded else {
                if let p = r.room?.point {
                    let s = builder.paper(0.002)
                    let st = GStroke(weight: 1, color: RGBColor(0.8, 0.3, 0.2), halftone: o.halftone ?? false)
                    items.append(GItem(elementID: r.id, category: .spaces, layer: .annotation,
                                       primitives: [.polyline([p - Vec2(s, s), p + Vec2(s, s)], closed: false, st), .polyline([p - Vec2(s, -s), p + Vec2(s, -s)], closed: false, st)],
                                       hitPolygons: [.rectangle(Rect2(center: p, halfSize: Vec2(s, s)))]))
                }
                continue
            }
            var prims: [GPrimitive] = []
            if let sf = builder.surfaceFill(o) { prims.append(.fill(prof.loops, sf)) }
            items.append(GItem(elementID: r.id, category: .spaces, layer: .fills, primitives: prims, hitPolygons: prof.loops))
        }
        return items
    }

    func spaceSeparators() -> [GItem] {
        var items: [GItem] = []
        for l in model.elements(.spaceSeparationLines) where l.levelID == levelID {
            guard let o = builder.resolver.resolve(l), let ml = l.modelLine else { continue }
            let st = builder.stroke(.spaceSeparationLines, cut: false, o)
            items.append(GItem(elementID: l.id, category: .spaceSeparationLines, layer: .model,
                               primitives: [ml.freeform.map { .polyline($0.points, closed: false, st) } ?? curvePrim(ml.curve, st)]))
        }
        return items
    }

    /// Masses: the section at the cut plane where the plane passes through, else the footprint (and a blend's top
    /// loop) seen from above when the mass lies below the cut plane and reaches the view depth.
    func masses(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let m = e.mass else { continue }
            let z0 = MassGeometry.baseZ(e, model), z1 = MassGeometry.topZ(e, model)
            let foot = MassGeometry.footprint(m)
            guard foot.count >= 3 else { continue }
            if z0 <= cutZ + Tolerance.length, z1 > cutZ, let cut = MassGeometry.section(e, model, atZ: cutZ) {
                let st = builder.stroke(.mass, cut: true, o)
                var prims: [GPrimitive] = [.polyline(cut.points, closed: true, st)]
                if m.isBlend, z0 >= depthZ - Tolerance.length { prims.append(.polyline(foot.points, closed: true, builder.stroke(.mass, cut: false, o))) }
                items.append(GItem(elementID: e.id, category: .mass, layer: .cut, primitives: prims, hitPolygons: [foot]))
            } else if z1 <= cutZ + Tolerance.length, z1 >= depthZ - Tolerance.length {
                let st = builder.stroke(.mass, cut: false, o)
                var prims: [GPrimitive] = [.polyline(foot.points, closed: true, st)]
                if m.isBlend, let top = MassGeometry.topLoop(m) {
                    prims.append(.polyline(top.points, closed: true, st))
                    // The blend's corner edges, footprint to top.
                    let t = MassGeometry.aligned(top, to: foot)
                    if t.count == foot.count { for (a, b) in zip(foot.points, t.points) { prims.append(.polyline([a, b], closed: false, st)) } }
                }
                items.append(GItem(elementID: e.id, category: .mass, layer: .model, primitives: prims, hitPolygons: [foot]))
            }
        }
        return items
    }
}
