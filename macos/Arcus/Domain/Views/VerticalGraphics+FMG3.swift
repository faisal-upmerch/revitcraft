import Foundation
import ArcusGeometry

// FMG3: placed families' model lines in elevations and sections, as Revit-style casework draws them: a loaded
// cabinet's door swings (Elevation Swing, dashed) and its other model lines, at the detail levels they show at, where
// the family's own solids don't hide them (the swings on the doors you look at, not the ones round the back).

extension VerticalGraphics {
    /// Adds the lines to each instance's own drawing (a new item when it has none).
    func fmg3FamilyModelLines(_ fr: Frame, _ visible: [(Element, GraphicOverride)], into items: inout [GItem]) {
        for (e, o) in visible where e.component != nil {
            if builder.isCancelled() { return }
            guard let ev = FamilyInstanceGeometry.evaluate(e, model), !ev.modelLines.isEmpty, let p = ComponentGeometry.placement(e, model) else { continue }
            let level = builder.detailLevel(e.category)
            let lines = ev.modelLines.filter { !$0.isReference && $0.visibleAt.contains(level) }
            guard !lines.isEmpty else { continue }
            let mesh = GeometryCache.shared.parts(e, model, detail: level).reduce(into: Mesh()) { $0.append($1.mesh) }
            let tris = Self.viewTriangles(mesh, fr)
            var prims: [GPrimitive] = []
            for l in lines {
                let a = p.world.apply(l.start), b = p.world.apply(l.end)
                let da = (a.xy - fr.origin.xy).dot(fr.forward), db = (b.xy - fr.origin.xy).dot(fr.forward)
                guard max(da, db) >= -0.001, min(da, db) <= data.farClip else { continue }
                let ua = fr.uv(a), ub = fr.uv(b)
                guard ua.distance(to: ub) > Tolerance.shortCurve else { continue } // seen edge-on
                let mid = (a + b) * 0.5
                guard !Self.hidden(fr.uv(mid), depth: (mid.xy - fr.origin.xy).dot(fr.forward), tris) else { continue }
                var st = builder.stroke(e.category, cut: false, o)
                if l.subcategory == .elevationSwing || l.subcategory == .swing { st.weight = 1; st.pattern = .dash }
                prims.append(.polyline([ua, ub], closed: false, st))
            }
            guard !prims.isEmpty else { continue }
            if let k = items.firstIndex(where: { $0.elementID == e.id && $0.layer == .model }) { items[k].primitives += prims }
            else { items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [])) }
        }
    }

    /// A mesh's triangles in view coordinates (u, v) with each corner's depth.
    static func viewTriangles(_ mesh: Mesh, _ fr: Frame) -> [(Vec2, Vec2, Vec2, Double, Double, Double)] {
        var out: [(Vec2, Vec2, Vec2, Double, Double, Double)] = []
        let pts = mesh.positions
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = pts[Int(mesh.indices[i])], b = pts[Int(mesh.indices[i + 1])], c = pts[Int(mesh.indices[i + 2])]
            func d(_ p: Vec3) -> Double { (p.xy - fr.origin.xy).dot(fr.forward) }
            out.append((fr.uv(a), fr.uv(b), fr.uv(c), d(a), d(b), d(c)))
            i += 3
        }
        return out
    }

    /// True when a triangle lies in front of the point (by more than 2 mm) where it covers it.
    static func hidden(_ p: Vec2, depth: Double, _ tris: [(Vec2, Vec2, Vec2, Double, Double, Double)]) -> Bool {
        for t in tris {
            let v0 = t.1 - t.0, v1 = t.2 - t.0, v2 = p - t.0
            let den = v0.cross(v1)
            guard abs(den) > 1e-12 else { continue }
            let s = v2.cross(v1) / den, r = v0.cross(v2) / den
            guard s >= -1e-9, r >= -1e-9, s + r <= 1 + 1e-9 else { continue }
            let z = t.3 + (t.4 - t.3) * s + (t.5 - t.3) * r
            if z < depth - 0.002 { return true }
        }
        return false
    }
}
