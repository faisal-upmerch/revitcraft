import Foundation
import ArcusGeometry

extension VerticalGraphics {
    /// Wall openings are voids in their host's mesh; these items make them selectable in elevations and sections.
    func wallOpeningItems(_ fr: Frame) -> [GItem] {
        var items: [GItem] = []
        for e in model.elements(.wallOpenings) {
            guard let o = builder.resolver.resolve(e), let x = WallOpeningGeometry.extents(e, model) else { continue }
            let L = x.host.length
            guard L > 0 else { continue }
            let p0 = x.host.location.point(at: x.s0 / L), p1 = x.host.location.point(at: x.s1 / L)
            let d0 = (p0 - fr.origin.xy).dot(fr.forward), d1 = (p1 - fr.origin.xy).dot(fr.forward)
            guard max(d0, d1) >= -0.001, min(d0, d1) <= data.farClip else { continue }
            let u0 = fr.u(p0), u1 = fr.u(p1)
            guard abs(u1 - u0) > 1e-3 else { continue } // seen edge-on
            if let crop = data.cropRegion, max(u0, u1) < crop.min.x || min(u0, u1) > crop.max.x { continue }
            let rect = Polygon2([Vec2(u0, x.z0), Vec2(u1, x.z0), Vec2(u1, x.z1), Vec2(u0, x.z1)]).counterClockwise
            let st = builder.stroke(.wallOpenings, cut: false, o)
            items.append(GItem(elementID: e.id, category: .wallOpenings, layer: .model,
                               primitives: [.polyline(rect.points, closed: true, GStroke(weight: 1, color: st.color, pattern: .solid, halftone: st.halftone))],
                               hitPolygons: [rect]))
        }
        return items
    }
}
