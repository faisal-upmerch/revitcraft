import ArcusGeometry

/// Triangulates the polygons of a `.fill` primitive once, at scene build time.
///
/// GraphicsRenderer fills all polygons of a primitive as one even-odd path. Here polygons are classified by nesting
/// depth (even depth = solid, odd depth = hole of its immediate container), grouped into `Profile2`s and triangulated
/// with ArcusGeometry's `Triangulator` (earcut with hole bridging). That reproduces even-odd exactly for nested,
/// non-crossing loops — the case the display-list builders produce. Crossing loops (a polygon partly overlapping
/// another of the same fill) render as their union instead of the XOR.
///
/// Each triangle records which of its edges lie on the region boundary; only those are anti-aliased (and pushed out by
/// one pixel) in the shader, so interior diagonals never show seams. Boundary edges shared by two polygons of the
/// same fill (adjacent pieces) are treated as interior too, matching the single-path CoreGraphics fill.
nonisolated enum FillTessellator {
    struct Triangle: Sendable {
        var a: Vec2
        var b: Vec2
        var c: Vec2
        /// Bit 0: edge ab is a boundary edge, bit 1: bc, bit 2: ca.
        var boundary: UInt32
    }

    static func triangulate(_ polygons: [Polygon2]) -> [Triangle] {
        var valid = polygons.filter { $0.points.count >= 3 }
        if valid.isEmpty { return [] }
        // Work relative to a local origin: area and orientation tests on absolute coordinates far from the view
        // origin (survey coordinates, deep zoom) cancel catastrophically for small polygons.
        var box = Rect2.empty
        for p in valid { box.include(p.bounds) }
        guard !box.isEmpty, box.min.x.isFinite, box.min.y.isFinite, box.max.x.isFinite, box.max.y.isFinite else { return [] }
        let o = box.min
        if o.x != 0 || o.y != 0 { valid = valid.map { Polygon2($0.points.map { $0 - o }) } }
        let profiles = valid.count == 1 ? [Profile2(outer: valid[0])] : nest(valid)
        var out: [Triangle] = []
        for p in profiles { appendTriangles(Triangulator.triangulate(p), into: &out) }
        if profiles.count > 1 { clearSharedBoundaries(&out) }
        if o.x != 0 || o.y != 0 {
            for i in out.indices { out[i].a += o; out[i].b += o; out[i].c += o }
        }
        return out
    }

    private static func appendTriangles(_ t: (points: [Vec2], triangles: [Int]), into out: inout [Triangle]) {
        let tris = t.triangles
        guard tris.count >= 3 else { return }
        // Undirected edge use counts: boundary edges belong to exactly one triangle (hole bridges appear twice).
        @inline(__always) func key(_ i: Int, _ j: Int) -> UInt64 { UInt64(min(i, j)) << 32 | UInt64(max(i, j)) }
        var counts: [UInt64: UInt8] = [:]
        counts.reserveCapacity(tris.count)
        for k in stride(from: 0, to: tris.count, by: 3) {
            counts[key(tris[k], tris[k + 1]), default: 0] &+= 1
            counts[key(tris[k + 1], tris[k + 2]), default: 0] &+= 1
            counts[key(tris[k + 2], tris[k]), default: 0] &+= 1
        }
        out.reserveCapacity(out.count + tris.count / 3)
        for k in stride(from: 0, to: tris.count, by: 3) {
            let i = tris[k], j = tris[k + 1], l = tris[k + 2]
            var flags: UInt32 = 0
            if counts[key(i, j)] == 1 { flags |= 1 }
            if counts[key(j, l)] == 1 { flags |= 2 }
            if counts[key(l, i)] == 1 { flags |= 4 }
            out.append(Triangle(a: t.points[i], b: t.points[j], c: t.points[l], boundary: flags))
        }
    }

    private struct EdgeKey: Hashable {
        var x0, y0, x1, y1: Double
        init(_ a: Vec2, _ b: Vec2) {
            if (a.x, a.y) < (b.x, b.y) { x0 = a.x; y0 = a.y; x1 = b.x; y1 = b.y } else { x0 = b.x; y0 = b.y; x1 = a.x; y1 = a.y }
        }
    }

    private static func clearSharedBoundaries(_ tris: inout [Triangle]) {
        var counts: [EdgeKey: Int] = [:]
        for t in tris {
            if t.boundary & 1 != 0 { counts[EdgeKey(t.a, t.b), default: 0] += 1 }
            if t.boundary & 2 != 0 { counts[EdgeKey(t.b, t.c), default: 0] += 1 }
            if t.boundary & 4 != 0 { counts[EdgeKey(t.c, t.a), default: 0] += 1 }
        }
        guard counts.values.contains(where: { $0 > 1 }) else { return }
        for i in tris.indices {
            var t = tris[i]
            if t.boundary & 1 != 0, counts[EdgeKey(t.a, t.b), default: 0] > 1 { t.boundary &= ~1 }
            if t.boundary & 2 != 0, counts[EdgeKey(t.b, t.c), default: 0] > 1 { t.boundary &= ~2 }
            if t.boundary & 4 != 0, counts[EdgeKey(t.c, t.a), default: 0] > 1 { t.boundary &= ~4 }
            tris[i] = t
        }
    }

    /// Groups loops into profiles by containment depth (even-odd semantics for nested loops).
    static func nest(_ polys: [Polygon2]) -> [Profile2] {
        let n = polys.count
        let bounds = polys.map(\.bounds)
        // A representative point per loop that does not lie on another loop's boundary.
        var reps: [Vec2] = []
        reps.reserveCapacity(n)
        for i in 0..<n {
            var chosen = polys[i].points[0]
            for p in polys[i].points.prefix(8) {
                var onOther = false
                for j in 0..<n where j != i && bounds[j].contains(p, tolerance: 1e-9) {
                    if polys[j].distanceToBoundary(p) <= 1e-9 { onOther = true; break }
                }
                if !onOther { chosen = p; break }
            }
            reps.append(chosen)
        }
        var depth = [Int](repeating: 0, count: n)
        var containers = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            for j in 0..<n where j != i && bounds[j].contains(reps[i]) && polys[j].contains(reps[i], onBoundary: false) {
                depth[i] += 1
                containers[i].append(j)
            }
        }
        var holes = [[Polygon2]](repeating: [], count: n)
        for i in 0..<n where depth[i] % 2 == 1 {
            // Immediate container: the one with depth exactly one less.
            if let parent = containers[i].first(where: { depth[$0] == depth[i] - 1 }) { holes[parent].append(polys[i]) }
        }
        var out: [Profile2] = []
        for i in 0..<n where depth[i] % 2 == 0 { out.append(Profile2(outer: polys[i], holes: holes[i])) }
        return out
    }
}
