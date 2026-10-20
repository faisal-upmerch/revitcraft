import Foundation
import ArcusGeometry

// FMG3: placed families' model lines in elevations and sections, as Revit-style casework draws them: a loaded
// cabinet's door swings (Elevation Swing, dashed) and its other model lines, at the detail levels they show at, where
// the family's own solids don't hide them (the swings on the doors you look at, not the ones round the back).

extension VerticalGraphics {
    /// Adds the lines to each instance's own drawing (a new item when it has none).
    func fmg3FamilyModelLines(_ fr: Frame, _ visible: [(Element, GraphicOverride)], occluders: [HLRInput] = [], into items: inout [GItem]) {
        // FMG4: walls and every other element in front of a line hide it, as hidden-line views do (not only the
        // family's own solids); a line half behind a wall is drawn where it shows.
        var scene: Occluders?
        for (e, o) in visible where e.component != nil {
            if builder.isCancelled() { return }
            guard let ev = FamilyInstanceGeometry.evaluate(e, model), !ev.modelLines.isEmpty, let p = ComponentGeometry.placement(e, model) else { continue }
            let level = builder.detailLevel(e.category)
            let lines = ev.modelLines.filter { !$0.isReference && $0.visibleAt.contains(level) }
            guard !lines.isEmpty else { continue }
            if scene == nil {
                let own = occluders.isEmpty ? [GeometryCache.shared.parts(e, model, detail: level).reduce(into: Mesh()) { $0.append($1.mesh) }] : occluders.map(\.mesh)
                scene = Occluders(own.flatMap { Self.viewTriangles($0, fr) }, section: data.kind != .elevation)
            }
            let tris = scene!
            var prims: [GPrimitive] = []
            for l in lines {
                let a = p.world.apply(l.start), b = p.world.apply(l.end)
                let da = (a.xy - fr.origin.xy).dot(fr.forward), db = (b.xy - fr.origin.xy).dot(fr.forward)
                guard max(da, db) >= -0.001, min(da, db) <= data.farClip else { continue }
                let ua = fr.uv(a), ub = fr.uv(b)
                guard ua.distance(to: ub) > Tolerance.shortCurve else { continue } // seen edge-on
                var st = builder.stroke(e.category, cut: false, o)
                if l.subcategory == .elevationSwing || l.subcategory == .swing { st.weight = 1; st.pattern = .dash }
                for run in tris.visibleRuns(a, b, fr) { prims.append(.polyline([fr.uv(run.0), fr.uv(run.1)], closed: false, st)) }
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
}

/// FMG4: the triangles of everything a vertical view shows, in view coordinates with their depths, binned in a grid
/// so a point is tested only against the triangles round it, to hide the parts of model lines behind them.
struct Occluders {
    let tris: [(Vec2, Vec2, Vec2, Double, Double, Double)]
    /// In a section, what lies in front of the cut plane hides nothing.
    let section: Bool
    private let origin: Vec2
    private let cell: Double
    private let columns: Int, rows: Int
    private let bins: [[Int32]]

    init(_ tris: [(Vec2, Vec2, Vec2, Double, Double, Double)], section: Bool) {
        self.section = section
        // Triangles seen edge-on (and degenerate ones) hide nothing.
        let kept = tris.filter { abs(($0.1 - $0.0).cross($0.2 - $0.0)) > 1e-12 }
        self.tris = kept
        var ext = Rect2.empty
        for t in kept { ext.include(t.0); ext.include(t.1); ext.include(t.2) }
        if ext.isEmpty { ext = Rect2(min: .zero, max: Vec2(1, 1)) }
        let n = 96
        let size = max(ext.width, ext.height, 1e-6) / Double(n)
        origin = ext.min
        cell = size
        columns = max(1, Int((ext.width / size).rounded(.up)) + 1)
        rows = max(1, Int((ext.height / size).rounded(.up)) + 1)
        var b = [[Int32]](repeating: [], count: columns * rows)
        for (k, t) in kept.enumerated() {
            let lo = Vec2(min(t.0.x, t.1.x, t.2.x), min(t.0.y, t.1.y, t.2.y)), hi = Vec2(max(t.0.x, t.1.x, t.2.x), max(t.0.y, t.1.y, t.2.y))
            let c0 = max(0, Int((lo.x - ext.min.x) / size)), c1 = min(columns - 1, Int((hi.x - ext.min.x) / size))
            let r0 = max(0, Int((lo.y - ext.min.y) / size)), r1 = min(rows - 1, Int((hi.y - ext.min.y) / size))
            guard c0 <= c1, r0 <= r1 else { continue }
            for r in r0...r1 { for c in c0...c1 { b[r * columns + c].append(Int32(k)) } }
        }
        bins = b
    }

    /// True when something lies in front of the point (by more than 2 mm) where it covers it.
    func hides(_ p: Vec2, depth: Double) -> Bool {
        let c = Int((p.x - origin.x) / cell), r = Int((p.y - origin.y) / cell)
        guard c >= 0, r >= 0, c < columns, r < rows else { return false }
        for k in bins[r * columns + c] {
            let t = tris[Int(k)]
            let v0 = t.1 - t.0, v1 = t.2 - t.0, v2 = p - t.0
            let den = v0.cross(v1)
            let s = v2.cross(v1) / den, q = v0.cross(v2) / den
            guard s >= -1e-9, q >= -1e-9, s + q <= 1 + 1e-9 else { continue }
            let z = t.3 + (t.4 - t.3) * s + (t.5 - t.3) * q
            if section, z < 0 { continue }
            if z < depth - 0.002 { return true }
        }
        return false
    }

    /// The pieces of the model segment a–b that show (sampled every centimetre or so).
    func visibleRuns(_ a: Vec3, _ b: Vec3, _ fr: VerticalGraphics.Frame) -> [(Vec3, Vec3)] {
        let n = max(4, min(64, Int((fr.uv(a).distance(to: fr.uv(b)) / 0.01).rounded(.up))))
        func point(_ t: Double) -> Vec3 { a + (b - a) * t }
        var runs: [(Vec3, Vec3)] = []
        var start: Double?
        for k in 0..<n {
            let t0 = Double(k) / Double(n), t1 = Double(k + 1) / Double(n)
            let mid = point((t0 + t1) / 2)
            let shows = !hides(fr.uv(mid), depth: (mid.xy - fr.origin.xy).dot(fr.forward))
            if shows, start == nil { start = t0 }
            if !shows, let s = start { runs.append((point(s), point(t0))); start = nil }
        }
        if let s = start { runs.append((point(s), b)) }
        return runs
    }
}
