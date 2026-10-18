import Foundation
import ArcusGeometry

// BL-SITE: toposolid geometry — the clipped top surface, one closed solid per structure layer, sub-divisions that
// follow their host, surface simplification and earthwork sampling.

public enum ToposolidGeometry {
    /// Sub-divisions sit this far above their host's surface so the two tops never fight in 3D.
    public static let subdivisionLift = 0.003

    // MARK: Outline and surface

    /// Convex hull (counter-clockwise, no collinear points) of plan points.
    public static func convexHull(_ pts: [Vec2]) -> [Vec2] {
        let p = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count >= 3 else { return p }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in p {
            while lower.count >= 2 && (lower[lower.count - 1] - lower[lower.count - 2]).cross(q - lower[lower.count - 2]) <= 1e-12 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2 && (upper[upper.count - 1] - upper[upper.count - 2]).cross(q - upper[upper.count - 2]) <= 1e-12 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Plan outline of a toposolid: its sketched/split outline, else the convex hull of its points.
    public static func outline(_ e: Element) -> Polygon2 {
        guard let t = e.topography else { return Polygon2([]) }
        if let o = t.solid?.outline, o.count >= 3 { return Polygon2(o).counterClockwise }
        return Polygon2(convexHull(t.points.map(\.xy)))
    }

    /// Inserts points along each edge of a closed loop so no edge piece is longer than `spacing`.
    public static func densify(_ loop: [Vec2], spacing: Double) -> [Vec2] {
        guard loop.count >= 2, spacing > 0 else { return loop }
        var out: [Vec2] = []
        for i in loop.indices {
            let a = loop[i], b = loop[(i + 1) % loop.count]
            let n = max(1, Int((a.distance(to: b) / spacing).rounded(.up)))
            for k in 0..<n { out.append(a.lerp(to: b, t: Double(k) / Double(n))) }
        }
        return out
    }

    /// Edge spacing used when outlines are densified: fine enough that the triangulation follows the outline.
    public static func densifySpacing(for outline: Polygon2) -> Double {
        let b = outline.bounds
        return min(2.0, max(0.25, max(b.width, b.height) / 40))
    }

    /// Survey points for a flat toposolid with the given outline at elevation `z` (the outline densified).
    public static func flatPoints(outline: Polygon2, z: Double) -> [Vec3] {
        SiteEditing.dedupe(densify(outline.counterClockwise.points, spacing: densifySpacing(for: outline)).map { Vec3($0, z: z) })
    }

    /// Top surface of a toposolid, a sub-division or any topography element: points and counter-clockwise triangles
    /// clipped to the outline (toposolids) or to the boundary and the host's outline (sub-divisions, sub-regions).
    public static func topSurface(_ e: Element, _ model: BIMModel?) -> (points: [Vec3], triangles: [Int]) {
        guard let t = e.topography else { return ([], []) }
        if t.solid != nil, let b = t.boundary, b.count >= 3, let model, let host = model[e.hostID], host.isToposolid {
            // Sub-division: re-derived from the host every time, so it follows the host's shape edits.
            let hs = topSurface(host, nil)
            let poly = Polygon2(b).counterClockwise
            let spacing = densifySpacing(for: poly)
            let edge = densify(poly.points, spacing: spacing).map { Vec3($0, z: SiteEditing.elevation(hs.points, at: $0, triangles: hs.triangles)) }
            let inside = hs.points.filter { poly.contains($0.xy, onBoundary: false) }
            let pts = SiteEditing.dedupe(edge + inside)
            var tri = TopographyGeometry.triangulate(pts)
            tri = SiteEditing.clip(triangles: tri, points: pts, to: poly)
            tri = SiteEditing.clip(triangles: tri, points: pts, to: outline(host))
            return compact(pts, tri)
        }
        let pts = t.points
        guard pts.count >= 3 else { return (pts, []) }
        var tri = TopographyGeometry.triangulate(pts)
        if let b = t.boundary, b.count >= 3 { tri = SiteEditing.clip(triangles: tri, points: pts, to: Polygon2(b)) }
        else if let o = t.solid?.outline, o.count >= 3 { tri = SiteEditing.clip(triangles: tri, points: pts, to: Polygon2(o)) }
        return compact(pts, tri)
    }

    /// Drops points no triangle uses (outside the outline) and renumbers the triangles.
    static func compact(_ pts: [Vec3], _ tri: [Int]) -> (points: [Vec3], triangles: [Int]) {
        var map = [Int](repeating: -1, count: pts.count)
        var out: [Vec3] = []
        for i in tri where map[i] < 0 { map[i] = out.count; out.append(pts[i]) }
        return (out, tri.map { map[$0] })
    }

    /// Directed boundary edges of a triangle set (interior on the left), in no particular order.
    static func boundaryEdges(_ tri: [Int]) -> [(Int, Int)] {
        var count: [UInt64: Int] = [:]
        func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            for (a, b) in [(tri[i], tri[i + 1]), (tri[i + 1], tri[i + 2]), (tri[i + 2], tri[i])] { count[key(a, b), default: 0] += 1 }
        }
        var out: [(Int, Int)] = []
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            for (a, b) in [(tri[i], tri[i + 1]), (tri[i + 1], tri[i + 2]), (tri[i + 2], tri[i])] where count[key(a, b)] == 1 { out.append((a, b)) }
        }
        return out
    }

    // MARK: Layers

    /// One structure layer between two surfaces over the top surface's triangulation.
    public struct LayerBand: Sendable {
        public var layerIndex: Int
        public var materialID: ElementID?
        /// Elevations of the band's top and bottom at each surface point.
        public var top: [Double]
        public var bottom: [Double]
    }

    /// The structure layers of a toposolid or sub-division as bands over `surface`.
    ///
    /// Toposolids: layers above the first variable layer keep their thickness and follow the terrain; the variable
    /// layer reaches down to a flat base (its own thickness below the lowest point of its top); layers below it are
    /// flat. Without a variable layer every layer follows the terrain. Sub-divisions: the type's layers are scaled to
    /// `|subdivisionHeight|` (default: the type's thickness) and sit on (positive) or in (negative) the host surface.
    public static func bands(_ e: Element, _ model: BIMModel, surface: (points: [Vec3], triangles: [Int])) -> [LayerBand] {
        guard let t = e.topography, let solid = t.solid else { return [] }
        let a = ToposolidTypes.assembly(of: e, model)
        let top = surface.points.map(\.z)
        let used = Set(surface.triangles)
        var out: [LayerBand] = []
        if t.boundary != nil {
            let total = a.totalThickness
            let h = solid.subdivisionHeight ?? total
            let span = max(abs(h), 0.001)
            let scale = total > Tolerance.length ? span / total : 1
            var depth = 0.0
            let lift = max(h, 0) + subdivisionLift
            for (i, l) in a.layers.enumerated() where l.thickness > Tolerance.length {
                let d0 = depth, d1 = depth + l.thickness * scale
                depth = d1
                out.append(LayerBand(layerIndex: i, materialID: i == 0 ? (t.materialID ?? l.materialID) : l.materialID,
                                     top: top.map { $0 + lift - d0 }, bottom: top.map { $0 + lift - d1 }))
            }
            return out
        }
        let minTop = used.map { top[$0] }.min() ?? (top.min() ?? 0)
        let variable = a.layers.firstIndex { $0.isVariable && $0.thickness > Tolerance.length }
        var depth = 0.0
        var flatZ: Double?
        for (i, l) in a.layers.enumerated() where l.thickness > Tolerance.length {
            if let fz = flatZ {
                out.append(LayerBand(layerIndex: i, materialID: l.materialID, top: top.map { _ in fz }, bottom: top.map { _ in fz - l.thickness }))
                flatZ = fz - l.thickness
            } else if i == variable {
                let base = minTop - depth - l.thickness
                out.append(LayerBand(layerIndex: i, materialID: l.materialID, top: top.map { $0 - depth }, bottom: top.map { _ in base }))
                flatZ = base
            } else {
                let d0 = depth
                depth += l.thickness
                out.append(LayerBand(layerIndex: i, materialID: l.materialID, top: top.map { $0 - d0 }, bottom: top.map { $0 - d0 - l.thickness }))
            }
        }
        return out
    }

    /// A closed solid between two surfaces over a triangulation: top and bottom faces plus vertical sides along the
    /// boundary. Feature edges: the top and bottom outlines and the vertical edges at outline corners.
    public static func bandMesh(points: [Vec3], triangles tri: [Int], top: [Double], bottom: [Double]) -> Mesh {
        guard tri.count >= 3 else { return .empty }
        var m = Mesh()
        let n = points.count
        // Top (smooth normals) and bottom (flat base or smooth, facing down).
        var topN = [Vec3](repeating: .zero, count: n), botN = [Vec3](repeating: .zero, count: n)
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            let (a, b, c) = (tri[i], tri[i + 1], tri[i + 2])
            let ta = Vec3(points[a].xy, z: top[a]), tb = Vec3(points[b].xy, z: top[b]), tc = Vec3(points[c].xy, z: top[c])
            let nt = (tb - ta).cross(tc - ta)
            topN[a] += nt; topN[b] += nt; topN[c] += nt
            let ba = Vec3(points[a].xy, z: bottom[a]), bb = Vec3(points[b].xy, z: bottom[b]), bc = Vec3(points[c].xy, z: bottom[c])
            let nb = (bc - ba).cross(bb - ba)
            botN[a] += nb; botN[b] += nb; botN[c] += nb
        }
        m.positions = points.indices.map { Vec3(points[$0].xy, z: top[$0]) } + points.indices.map { Vec3(points[$0].xy, z: bottom[$0]) }
        m.normals = topN.map { $0.lengthSquared > 0 ? $0.normalized : .unitZ } + botN.map { $0.lengthSquared > 0 ? $0.normalized : -.unitZ }
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            m.indices += [UInt32(tri[i]), UInt32(tri[i + 1]), UInt32(tri[i + 2])]
            m.indices += [UInt32(n + tri[i]), UInt32(n + tri[i + 2]), UInt32(n + tri[i + 1])]
        }
        // Sides: for boundary edge a→b (interior on the left) the outward normal points to the right.
        let edges = boundaryEdges(tri)
        var next: [Int: Int] = [:], prev: [Int: Int] = [:]
        for (a, b) in edges { next[a] = b; prev[b] = a }
        for (a, b) in edges {
            let pa = points[a].xy, pb = points[b].xy
            let d = pb - pa
            guard d.lengthSquared > 1e-18 else { continue }
            let out = Vec3(d.y, -d.x, 0).normalized
            let base = UInt32(m.positions.count)
            m.positions += [Vec3(pa, z: bottom[a]), Vec3(pb, z: bottom[b]), Vec3(pb, z: top[b]), Vec3(pa, z: top[a])]
            m.normals += [out, out, out, out]
            m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            m.featureEdges += [UInt32(a), UInt32(b), UInt32(n + a), UInt32(n + b)]
            // Vertical edge at a corner of the outline (direction changes by more than ~15°).
            if let p = prev[a] {
                let d0 = (pa - points[p].xy).normalized, d1 = d.normalized
                if d0.dot(d1) < 0.966 { m.featureEdges += [UInt32(a), UInt32(n + a)] }
            }
        }
        return m
    }

    /// 3D representation: one closed solid per structure layer, each with its layer's material.
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        let s = topSurface(e, model)
        guard s.triangles.count >= 3 else { return [] }
        return bands(e, model, surface: s).compactMap { b in
            let m = bandMesh(points: s.points, triangles: s.triangles, top: b.top, bottom: b.bottom)
            return m.isEmpty ? nil : MeshPart(mesh: m, materialID: b.materialID)
        }
    }

    /// Solid volume of all layers (m³).
    public static func volume(_ e: Element, _ model: BIMModel) -> Double {
        meshParts(e, model).reduce(0) { $0 + abs($1.mesh.signedVolume) }
    }

    /// Nominal thickness: the type's total (toposolids) or `|subdivisionHeight|` (sub-divisions).
    public static func thickness(_ e: Element, _ model: BIMModel) -> Double {
        if e.isToposolidSubdivision, let h = e.topography?.solid?.subdivisionHeight { return abs(h) }
        return ToposolidTypes.assembly(of: e, model).totalThickness
    }

    // MARK: Simplify

    /// Removes survey points that the surface doesn't need: the result keeps the outline (hull corners, or every point
    /// on a sketched outline) and every point whose removal would change the surface by more than `tolerance`
    /// vertically. Greedy insertion: start from the outline, then repeatedly add the worst-fitting point of each triangle.
    public static func simplify(_ pts: [Vec3], outline: Polygon2?, tolerance: Double) -> [Vec3] {
        guard pts.count > 3, tolerance > 0 else { return pts }
        let hull = outline.map { $0.counterClockwise } ?? Polygon2(convexHull(pts.map(\.xy)))
        var keep = Set<Int>()
        // A sketched outline keeps every point on it (its notches must stay covered); a hull only needs its corners.
        if outline != nil { for (i, p) in pts.enumerated() where hull.distanceToBoundary(p.xy) < 1e-6 { keep.insert(i) } }
        // Outline corners that aren't survey points still need their nearest points.
        for c in hull.points {
            if let i = pts.indices.min(by: { pts[$0].xy.distanceSquared(to: c) < pts[$1].xy.distanceSquared(to: c) }) { keep.insert(i) }
        }
        for _ in 0..<64 {
            let order = keep.sorted()
            let kp = order.map { pts[$0] }
            let tri = TopographyGeometry.triangulate(kp)
            let index = TriangleIndex(points: kp, triangles: tri)
            var worst: [Int: (Int, Double)] = [:]
            for i in pts.indices where !keep.contains(i) {
                guard let (t, z) = index.locate(pts[i].xy) else { worst[-1 - i] = (i, .infinity); continue }
                let err = abs(z - pts[i].z)
                if err > tolerance, err > (worst[t]?.1 ?? -1) { worst[t] = (i, err) }
            }
            if worst.isEmpty { break }
            for (_, v) in worst { keep.insert(v.0) }
        }
        return keep.sorted().map { pts[$0] }
    }

    /// Point location in a triangulation through a uniform grid of triangle boxes.
    struct TriangleIndex {
        let points: [Vec3]
        let triangles: [Int]
        let origin: Vec2
        let cell: Double
        let cols: Int, rows: Int
        var buckets: [[Int]]

        init(points: [Vec3], triangles: [Int]) {
            self.points = points; self.triangles = triangles
            let b = Rect2(points: points.map(\.xy))
            let nt = max(1, triangles.count / 3)
            let side = max(1, Int(Double(nt).squareRoot()))
            origin = b.min
            cell = max(max(b.width, b.height) / Double(side), 1e-6)
            cols = max(1, Int((b.width / cell).rounded(.up)) + 1)
            rows = max(1, Int((b.height / cell).rounded(.up)) + 1)
            buckets = Array(repeating: [], count: cols * rows)
            for t in 0..<(triangles.count / 3) {
                let r = Rect2(points: [points[triangles[3 * t]].xy, points[triangles[3 * t + 1]].xy, points[triangles[3 * t + 2]].xy])
                let c0 = max(0, Int((r.min.x - origin.x) / cell)), c1 = min(cols - 1, Int((r.max.x - origin.x) / cell))
                let r0 = max(0, Int((r.min.y - origin.y) / cell)), r1 = min(rows - 1, Int((r.max.y - origin.y) / cell))
                guard c0 <= c1, r0 <= r1 else { continue }
                for y in r0...r1 { for x in c0...c1 { buckets[y * cols + x].append(t) } }
            }
        }

        /// Triangle containing `p` and the interpolated elevation there.
        func locate(_ p: Vec2) -> (Int, Double)? {
            let x = Int((p.x - origin.x) / cell), y = Int((p.y - origin.y) / cell)
            guard x >= 0, y >= 0, x < cols, y < rows else { return nil }
            for t in buckets[y * cols + x] {
                let a = points[triangles[3 * t]], b = points[triangles[3 * t + 1]], c = points[triangles[3 * t + 2]]
                let d = (b.xy - a.xy).cross(c.xy - a.xy)
                guard abs(d) > 1e-15 else { continue }
                let u = (p - a.xy).cross(c.xy - a.xy) / d, v = (b.xy - a.xy).cross(p - a.xy) / d
                if u >= -1e-9, v >= -1e-9, u + v <= 1 + 1e-9 { return (t, a.z + u * (b.z - a.z) + v * (c.z - a.z)) }
            }
            return nil
        }
    }

    // MARK: Earthwork

    /// Cut (ground above `z`) and fill (ground below `z`) volumes between a surface and a flat level over a region,
    /// sampled on a grid of about `samples` cells per side.
    public static func cutFill(surface: (points: [Vec3], triangles: [Int]), region: Polygon2, level z: Double, samples: Int = 80) -> (cut: Double, fill: Double) {
        let b = region.bounds
        guard b.width > 0, b.height > 0, surface.triangles.count >= 3 else { return (0, 0) }
        let n = max(4, samples)
        let dx = b.width / Double(n), dy = b.height / Double(n)
        let index = TriangleIndex(points: surface.points, triangles: surface.triangles)
        var cut = 0.0, fill = 0.0
        for i in 0..<n {
            for j in 0..<n {
                let p = Vec2(b.min.x + (Double(i) + 0.5) * dx, b.min.y + (Double(j) + 0.5) * dy)
                guard region.contains(p), let (_, g) = index.locate(p) else { continue }
                let d = g - z
                if d > 0 { cut += d * dx * dy } else { fill -= d * dx * dy }
            }
        }
        return (cut, fill)
    }
}
