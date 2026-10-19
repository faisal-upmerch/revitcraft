import Foundation

/// An orthographic view: screen axes `right` and `up`, view direction `forward`.
///
/// `forward = up × right`, so for a viewer looking along `forward` the triple
/// (right, up, forward) is a left-handed screen frame (x right, y up, depth into the
/// screen). Depth grows away from the viewer; `near`…`far` bound the visible slab,
/// and `near` acts as the section cut plane: everything with depth < near is removed.
public struct ViewProjection: Hashable, Sendable {
    public var origin: Vec3
    public var right: Vec3
    public var up: Vec3
    /// View direction (into the screen).
    public var forward: Vec3
    public var near: Double
    public var far: Double

    /// `right` is normalized; `up` is orthogonalized against it.
    public init(origin: Vec3, right: Vec3, up: Vec3, near: Double, far: Double) {
        let r = right.normalized
        let u = (up - r * up.dot(r)).normalized
        self.origin = origin
        self.right = r
        self.up = u
        self.forward = u.cross(r)
        self.near = near
        self.far = far
    }

    /// Screen coordinates (along right, up) and depth (along forward) of a point.
    public func project(_ p: Vec3) -> (uv: Vec2, depth: Double) {
        let d = p - origin
        return (Vec2(d.dot(right), d.dot(up)), d.dot(forward))
    }

    /// Elevation / section looking horizontally along `direction` with Z up.
    public static func elevation(lookingAt direction: Vec2, origin: Vec3, near: Double, far: Double) -> ViewProjection {
        let f = Vec3(direction.x, direction.y, 0).normalized
        return ViewProjection(origin: origin, right: f.cross(.unitZ), up: .unitZ, near: near, far: far)
    }

    /// Plan projection looking down from height `z`, showing `depth` meters below it.
    /// Screen coordinates equal plan (x, y).
    public static func topDown(z: Double, depth: Double) -> ViewProjection {
        ViewProjection(origin: Vec3(0, 0, z), right: .unitX, up: .unitY, near: 0, far: depth)
    }
}

/// A mesh to render, tagged with a caller-defined id (e.g. element index).
public struct HLRInput: Sendable {
    public var tag: Int
    public var mesh: Mesh
    public init(tag: Int, mesh: Mesh) { self.tag = tag; self.mesh = mesh }
}

/// A visible edge piece in screen coordinates.
public struct HLREdge: Sendable, Hashable {
    public var tag: Int
    public var segment: Segment2
    /// Average depth of the piece.
    public var depth: Double
    /// True for silhouette edges (between a front- and a back-facing triangle) that are not
    /// also feature edges; false for feature and open-boundary edges.
    public var isSilhouette: Bool

    public init(tag: Int, segment: Segment2, depth: Double, isSilhouette: Bool) {
        self.tag = tag; self.segment = segment; self.depth = depth; self.isSilhouette = isSilhouette
    }
}

/// Exact-interval hidden-line removal for orthographic views.
///
/// Candidate edges are mesh feature edges, silhouette edges (shared by a front-facing
/// and a back-facing or edge-on triangle, on welded positions) and open boundary edges. Triangles and
/// edges are clipped to the depth slab [near, far]. For every edge, occluding
/// triangles are gathered from a uniform grid along the edge; each triangle hides an
/// exact parameter interval (inside its projection, inclusive by `Tolerance.length`,
/// and in front by more than `depthTolerance`). The complement of the merged
/// intervals gives the visible pieces; pieces shorter than `Tolerance.shortCurve`
/// are dropped. Triangles containing the edge itself are never occluders.
public enum HiddenLineRenderer {
    /// Depth margin before a surface counts as in front of an edge. 1 mm (100×
    /// `Tolerance.length`) so coplanar faces of abutting elements never hide each other.
    public static let depthTolerance: Double = Tolerance.length * 100

    private struct Occluder {
        var u0: Double, v0: Double, u1: Double, v1: Double, u2: Double, v2: Double
        /// depth = du·u + dv·v + dc
        var du: Double, dv: Double, dc: Double
        var minDepth: Double
        var source: Int
    }

    private struct Candidate {
        var tag: Int
        var a: Vec3   // view space (u, v, depth)
        var b: Vec3
        var silhouette: Bool
        var excluded: [Int]
    }

    /// Renders visible edges. Returns [] if `isCancelled` becomes true.
    public static func render(_ inputs: [HLRInput], projection: ViewProjection, clip: Rect2? = nil,
                              isCancelled: @Sendable () -> Bool = { false }) -> [HLREdge] {
        let near = min(projection.near, projection.far), far = max(projection.near, projection.far)
        var occluders: [Occluder] = []
        var candidates: [Candidate] = []
        var sourceBase = 0
        let viewDir = projection.forward

        for input in inputs {
            if isCancelled() { return [] }
            let m = input.mesh
            let view = m.positions.map { p -> Vec3 in
                let pr = projection.project(p)
                return Vec3(pr.uv.x, pr.uv.y, pr.depth)
            }
            var welder = PointWelder3(tolerance: Tolerance.length)
            let wid = m.positions.map { welder.id(for: $0) }
            let triCount = m.indices.count / 3
            // Facing and edge adjacency on welded ids.
            var front = Array(repeating: false, count: triCount)
            var edgeTris: [SIMD2<Int>: [Int]] = [:]
            var edgeOrder: [SIMD2<Int>] = []
            for t in 0..<triCount {
                if t & 1023 == 0 && isCancelled() { return [] }
                let ia = Int(m.indices[3 * t]), ib = Int(m.indices[3 * t + 1]), ic = Int(m.indices[3 * t + 2])
                let pa = m.positions[ia], pb = m.positions[ib], pc = m.positions[ic]
                let n = (pb - pa).cross(pc - pa)
                let nl = n.length
                front[t] = nl > 0 && -n.dot(viewDir) > Tolerance.angle * nl
                let w = [wid[ia], wid[ib], wid[ic]]
                if w[0] != w[1] && w[1] != w[2] && w[0] != w[2] {
                    for k in 0..<3 {
                        let key = SIMD2(min(w[k], w[(k + 1) % 3]), max(w[k], w[(k + 1) % 3]))
                        if edgeTris[key] == nil { edgeOrder.append(key) }
                        edgeTris[key, default: []].append(t)
                    }
                }
                // Occluders: clip to the depth slab, fan-triangulate.
                let tri = [view[ia], view[ib], view[ic]]
                if tri.allSatisfy({ $0.z < near }) || tri.allSatisfy({ $0.z > far }) { continue }
                let poly = clipSlab(tri, near: near, far: far)
                guard poly.count >= 3 else { continue }
                for k in 1..<(poly.count - 1) {
                    if let o = makeOccluder(poly[0], poly[k], poly[k + 1], source: sourceBase + t) { occluders.append(o) }
                }
            }
            // Candidate edges: features first, then silhouettes and open boundaries.
            var index: [SIMD2<Int>: Int] = [:]
            var local: [Candidate] = []
            func add(_ key: SIMD2<Int>, _ ia: Int, _ ib: Int, silhouette: Bool) {
                guard index[key] == nil else { return } // feature edges take precedence
                let excluded = (edgeTris[key] ?? []).map { $0 + sourceBase }
                index[key] = local.count
                local.append(Candidate(tag: input.tag, a: view[ia], b: view[ib], silhouette: silhouette, excluded: excluded))
            }
            for e in stride(from: 0, to: m.featureEdges.count - 1, by: 2) {
                let ia = Int(m.featureEdges[e]), ib = Int(m.featureEdges[e + 1])
                guard wid[ia] != wid[ib] else { continue }
                add(SIMD2(min(wid[ia], wid[ib]), max(wid[ia], wid[ib])), ia, ib, silhouette: false)
            }
            var firstVertex: [Int: Int] = [:]
            for (i, w) in wid.enumerated() where firstVertex[w] == nil { firstVertex[w] = i }
            var boundary: [(key: SIMD2<Int>, ia: Int, ib: Int, tri: Int)] = []
            for key in edgeOrder {
                let tris = edgeTris[key] ?? []
                let ia = firstVertex[key.x] ?? 0, ib = firstVertex[key.y] ?? 0
                if tris.count == 1 {
                    boundary.append((key, ia, ib, tris[0]))
                } else if tris.contains(where: { front[$0] }) && tris.contains(where: { !front[$0] }) {
                    add(key, ia, ib, silhouette: true)
                }
            }
            // HOUSE: T-junctions inside a flat face (a long edge on one side, collinear shorter edges on the other, as
            // when two wall openings share a sill line) leave "boundary" edges that are not edges of the shape. The
            // parts of a boundary edge covered by coplanar boundary edges of the same face are dropped.
            func unitNormal(_ t: Int) -> Vec3 {
                let pa = m.positions[Int(m.indices[3 * t])], pb = m.positions[Int(m.indices[3 * t + 1])], pc = m.positions[Int(m.indices[3 * t + 2])]
                return (pb - pa).cross(pc - pa).normalized
            }
            func lineKey(_ a: Vec3, _ b: Vec3) -> SIMD4<Int>? {
                var d = (b - a).normalized
                guard d.length > 0.5 else { return nil }
                if d.x < -1e-9 || (abs(d.x) <= 1e-9 && (d.y < -1e-9 || (abs(d.y) <= 1e-9 && d.z < 0))) { d = d * -1 }
                let p0 = a - d * a.dot(d)
                let q = 1e4
                return SIMD4(Int((d.x * 1e3).rounded()) &* 4_000 &+ Int((d.y * 1e3).rounded()), Int((p0.x * q).rounded()), Int((p0.y * q).rounded()), Int((p0.z * q).rounded()))
            }
            var byLine: [SIMD4<Int>: [Int]] = [:]
            for (i, e) in boundary.enumerated() {
                if let k = lineKey(m.positions[e.ia], m.positions[e.ib]) { byLine[k, default: []].append(i) }
            }
            for (i, e) in boundary.enumerated() {
                let a = m.positions[e.ia], b = m.positions[e.ib]
                let len = a.distance(to: b)
                var covered: [(Double, Double)] = []
                if len > Tolerance.length, let k = lineKey(a, b), let group = byLine[k], group.count > 1 {
                    let n = unitNormal(e.tri), d = (b - a) / len
                    for j in group where j != i {
                        let f = boundary[j]
                        let fa = m.positions[f.ia], fb = m.positions[f.ib]
                        guard unitNormal(f.tri).dot(n) > 1 - 1e-9, abs((fa - a).dot(n)) <= Tolerance.length else { continue }
                        // Both ends on this edge's line.
                        guard (fa - a - d * (fa - a).dot(d)).length <= Tolerance.length, (fb - a - d * (fb - a).dot(d)).length <= Tolerance.length else { continue }
                        let t0 = max(0, min((fa - a).dot(d), (fb - a).dot(d))), t1 = min(len, max((fa - a).dot(d), (fb - a).dot(d)))
                        if t1 - t0 > Tolerance.length { covered.append((t0, t1)) }
                    }
                }
                guard !covered.isEmpty else { add(e.key, e.ia, e.ib, silhouette: false); continue }
                covered.sort { $0.0 < $1.0 }
                var pieces: [(Double, Double)] = [], at = 0.0
                for (t0, t1) in covered {
                    if t0 - at > Tolerance.length { pieces.append((at, t0)) }
                    at = max(at, t1)
                }
                if len - at > Tolerance.length { pieces.append((at, len)) }
                let excluded = (edgeTris[e.key] ?? []).map { $0 + sourceBase }
                let va = view[e.ia], vb = view[e.ib]
                for (t0, t1) in pieces {
                    local.append(Candidate(tag: input.tag, a: va + (vb - va) * (t0 / len), b: va + (vb - va) * (t1 / len), silhouette: false, excluded: excluded))
                }
            }
            candidates.append(contentsOf: local)
            sourceBase += triCount
        }
        if isCancelled() { return [] }

        // Uniform grid over occluder bounds.
        var extent = Rect2.empty
        for o in occluders {
            extent.include(Vec2(min(o.u0, o.u1, o.u2), min(o.v0, o.v1, o.v2)))
            extent.include(Vec2(max(o.u0, o.u1, o.u2), max(o.v0, o.v1, o.v2)))
        }
        if let c = clip { extent = extent.intersection(c) }
        let grid = OccluderGrid(occluders: occluders, extent: extent)

        // Visibility per edge, in parallel over interleaved chunks. Each chunk writes its own
        // slot and chunks are concatenated in order, so output is deterministic.
        let ctx = EdgeContext(occluders: occluders, candidates: candidates, grid: grid, near: near, far: far, clip: clip)
        let chunkSize = 128
        let chunkCount = (candidates.count + chunkSize - 1) / chunkSize
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, chunkCount))
        var chunks = Array(repeating: [HLREdge](), count: chunkCount)
        chunks.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                var scratch = EdgeScratch(occluderCount: ctx.occluders.count)
                var chunk = w
                while chunk < chunkCount {
                    if isCancelled() { return }
                    var local: [HLREdge] = []
                    for ei in (chunk * chunkSize)..<min(ctx.candidates.count, (chunk + 1) * chunkSize) {
                        ctx.visiblePieces(ei, &scratch, into: &local)
                    }
                    out[chunk] = local
                    chunk += workers
                }
            }
        }
        if isCancelled() { return [] }
        return chunks.flatMap { $0 }
    }

    private struct EdgeScratch {
        var stamp: [Int]
        var intervals: [(Double, Double)] = []
        init(occluderCount: Int) { stamp = Array(repeating: -1, count: occluderCount) }
    }

    private struct EdgeContext: Sendable {
        let occluders: [Occluder]
        let candidates: [Candidate]
        let grid: OccluderGrid
        let near: Double
        let far: Double
        let clip: Rect2?

        func visiblePieces(_ ei: Int, _ scratch: inout EdgeScratch, into result: inout [HLREdge]) {
            let c = candidates[ei]
            let minPiece = Tolerance.shortCurve
            // Depth slab parameter range.
            var s0 = 0.0, s1 = 1.0
            let da = c.a.z, db = c.b.z
            if !clipRange(&s0, &s1, fa: da - near, fb: db - near) { return }
            if !clipRange(&s0, &s1, fa: far - da, fb: far - db) { return }
            let a2 = Vec2(c.a.x, c.a.y), b2 = Vec2(c.b.x, c.b.y)
            let seg = Segment2(a2, b2)
            if let r = clip {
                guard let cr = parametricClip(seg, r) else { return }
                s0 = max(s0, cr.0); s1 = min(s1, cr.1)
            }
            let len2D = seg.length
            guard s1 > s0, (s1 - s0) * len2D >= minPiece else { return }
            let pa = seg.point(at: s0), pb = seg.point(at: s1)
            scratch.intervals.removeAll(keepingCapacity: true)
            let maxDepth = max(da + (db - da) * s0, da + (db - da) * s1)
            let dir = b2 - a2
            let dirLen = dir.length
            // Parameter span below which a remaining gap cannot become a visible piece.
            let negligible = minPiece / len2D
            var hidden = false
            grid.visit(from: pa, to: pb) { oi in
                guard scratch.stamp[oi] != ei else { return true }
                scratch.stamp[oi] = ei
                let o = occluders[oi]
                guard o.minDepth < maxDepth - depthTolerance, !c.excluded.contains(o.source) else { return true }
                var lo = s0, hi = s1
                // Inside the triangle (CCW after makeOccluder). Crossings are exact; an edge
                // running parallel to a triangle side counts as inside within Tolerance.length,
                // so edges along an occluder's outline (or its internal diagonals) are hidden.
                if !insideRange(&lo, &hi, o.u0, o.v0, o.u1, o.v1, a2, dir, dirLen) { return true }
                if !insideRange(&lo, &hi, o.u1, o.v1, o.u2, o.v2, a2, dir, dirLen) { return true }
                if !insideRange(&lo, &hi, o.u2, o.v2, o.u0, o.v0, a2, dir, dirLen) { return true }
                // Hidden where edgeDepth(s) - triDepth(P(s)) > depthTolerance.
                let g0 = da - (o.du * a2.x + o.dv * a2.y + o.dc) - depthTolerance
                let g1 = db - (o.du * b2.x + o.dv * b2.y + o.dc) - depthTolerance
                let gl = g0 + (g1 - g0) * lo, gh = g0 + (g1 - g0) * hi
                if !clipRange(&lo, &hi, fa: gl, fb: gh, strict: true) { return true }
                guard hi > lo else { return true }
                scratch.intervals.append((lo, hi))
                // Early out once the whole edge is covered.
                if lo <= s0 + negligible && hi >= s1 - negligible { hidden = true; return false }
                if scratch.intervals.count & 7 == 0 && Self.covers(&scratch.intervals, s0, s1, negligible) {
                    hidden = true
                    return false
                }
                return true
            }
            if hidden { return }
            scratch.intervals.sort { $0.0 < $1.0 }
            var cursor = s0
            func emit(_ t0: Double, _ t1: Double) {
                guard (t1 - t0) * len2D >= minPiece else { return }
                let p0 = seg.point(at: t0), p1 = seg.point(at: t1)
                let depth = da + (db - da) * (t0 + t1) * 0.5
                result.append(HLREdge(tag: c.tag, segment: Segment2(p0, p1), depth: depth, isSilhouette: c.silhouette))
            }
            for (lo, hi) in scratch.intervals {
                if lo > cursor { emit(cursor, lo) }
                cursor = max(cursor, hi)
                if cursor >= s1 { break }
            }
            if cursor < s1 { emit(cursor, s1) }
        }

        /// Sorts and merges intervals in place; true if they leave no gap worth drawing.
        static func covers(_ iv: inout [(Double, Double)], _ s0: Double, _ s1: Double, _ negligible: Double) -> Bool {
            iv.sort { $0.0 < $1.0 }
            var merged: [(Double, Double)] = []
            merged.reserveCapacity(iv.count)
            for x in iv {
                if let last = merged.last, x.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, x.1) } else { merged.append(x) }
            }
            iv = merged
            var cursor = s0
            for (lo, hi) in merged {
                if lo - cursor >= negligible { return false }
                cursor = max(cursor, hi)
            }
            return s1 - cursor < negligible
        }
    }

    /// Restricts [lo, hi] to the parameters of a + s·dir left of the triangle side t0→t1.
    @inline(__always)
    private static func insideRange(_ lo: inout Double, _ hi: inout Double, _ t0u: Double, _ t0v: Double,
                                    _ t1u: Double, _ t1v: Double, _ a: Vec2, _ dir: Vec2, _ dirLen: Double) -> Bool {
        let ex = t1u - t0u, ey = t1v - t0v
        let el = (ex * ex + ey * ey).squareRoot()
        let beta = ex * dir.y - ey * dir.x
        let parallel = abs(beta) <= Tolerance.angle * el * dirLen
        let alpha = ex * (a.y - t0v) - ey * (a.x - t0u) + (parallel ? Tolerance.length * el : 0)
        return clipRange(&lo, &hi, fa: alpha + beta * lo, fb: alpha + beta * hi)
    }

    /// Restricts [lo, hi] to where the linear function with values fa at lo and fb at hi
    /// is ≥ 0 (> 0 when `strict`). Returns false if the result is empty.
    private static func clipRange(_ lo: inout Double, _ hi: inout Double, fa: Double, fb: Double, strict: Bool = false) -> Bool {
        let aIn = strict ? fa > 0 : fa >= 0
        let bIn = strict ? fb > 0 : fb >= 0
        if aIn && bIn { return hi >= lo }
        if !aIn && !bIn { return false }
        let t = lo + (hi - lo) * (fa / (fa - fb))
        if aIn { hi = t } else { lo = t }
        return hi >= lo
    }

    private static func parametricClip(_ s: Segment2, _ r: Rect2) -> (Double, Double)? {
        let d = s.vector
        var t0 = 0.0, t1 = 1.0
        for (p, q) in [(-d.x, s.start.x - r.min.x), (d.x, r.max.x - s.start.x), (-d.y, s.start.y - r.min.y), (d.y, r.max.y - s.start.y)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return nil }
            }
        }
        return (t0, t1)
    }

    /// Sutherland–Hodgman clip of a view-space triangle against near ≤ depth ≤ far.
    private static func clipSlab(_ tri: [Vec3], near: Double, far: Double) -> [Vec3] {
        var poly = tri
        for (bound, keepAbove) in [(near, true), (far, false)] {
            guard !poly.isEmpty else { return [] }
            var out: [Vec3] = []
            var prev = poly[poly.count - 1]
            for cur in poly {
                let ci = keepAbove ? cur.z >= bound : cur.z <= bound
                let pi = keepAbove ? prev.z >= bound : prev.z <= bound
                if ci != pi {
                    let t = (bound - prev.z) / (cur.z - prev.z)
                    var q = prev.lerp(to: cur, t: t)
                    q.z = bound
                    out.append(q)
                }
                if ci { out.append(cur) }
                prev = cur
            }
            poly = out
        }
        return poly
    }

    private static func makeOccluder(_ a: Vec3, _ b: Vec3, _ c: Vec3, source: Int) -> Occluder? {
        var p0 = a, p1 = b, p2 = c
        var area2 = (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
        // Edge-on triangles (projected area ~0) never occlude.
        let scale = max((p1 - p0).lengthSquared, (p2 - p0).lengthSquared, (p2 - p1).lengthSquared)
        guard abs(area2) > Tolerance.angle * scale, abs(area2) > Tolerance.lengthSquared else { return nil }
        if area2 < 0 { swap(&p1, &p2); area2 = -area2 }
        // Solve depth = du·u + dv·v + dc.
        let e1 = p1 - p0, e2 = p2 - p0
        let du = (e1.z * e2.y - e2.z * e1.y) / area2
        let dv = (e2.z * e1.x - e1.z * e2.x) / area2
        let dc = p0.z - du * p0.x - dv * p0.y
        return Occluder(u0: p0.x, v0: p0.y, u1: p1.x, v1: p1.y, u2: p2.x, v2: p2.y,
                        du: du, dv: dv, dc: dc, minDepth: min(p0.z, p1.z, p2.z), source: source)
    }

    /// CSR uniform grid of occluder indices.
    private struct OccluderGrid {
        var origin = Vec2.zero
        var cell = 1.0
        var nx = 0, ny = 0
        var start: [Int] = []
        var items: [Int] = []

        init(occluders: [Occluder], extent: Rect2) {
            guard !occluders.isEmpty, !extent.isEmpty else { return }
            let w = max(extent.width, Tolerance.length), h = max(extent.height, Tolerance.length)
            let target = max(1.0, Double(occluders.count))
            var c = (w * h / target).squareRoot()
            c = max(c, max(w, h) / 1024, Tolerance.length * 10)
            cell = c
            origin = extent.min
            nx = min(1024, max(1, Int((w / c).rounded(.up)))); ny = min(1024, max(1, Int((h / c).rounded(.up))))
            var counts = Array(repeating: 0, count: nx * ny + 1)
            func range(_ o: Occluder) -> (Int, Int, Int, Int)? {
                let x0 = (min(o.u0, o.u1, o.u2) - origin.x) / c, x1 = (max(o.u0, o.u1, o.u2) - origin.x) / c
                let y0 = (min(o.v0, o.v1, o.v2) - origin.y) / c, y1 = (max(o.v0, o.v1, o.v2) - origin.y) / c
                guard x1 >= -1, y1 >= -1, x0 <= Double(nx) + 1, y0 <= Double(ny) + 1 else { return nil }
                return (max(0, min(nx - 1, Int(x0.rounded(.down)))), max(0, min(nx - 1, Int(x1.rounded(.down)))),
                        max(0, min(ny - 1, Int(y0.rounded(.down)))), max(0, min(ny - 1, Int(y1.rounded(.down)))))
            }
            let ranges = occluders.map(range)
            for r in ranges {
                guard let r else { continue }
                for y in r.2...r.3 { for x in r.0...r.1 { counts[y * nx + x + 1] += 1 } }
            }
            for i in 1..<counts.count { counts[i] += counts[i - 1] }
            start = counts
            items = Array(repeating: 0, count: counts[counts.count - 1])
            var fill = counts
            for (i, r) in ranges.enumerated() {
                guard let r else { continue }
                for y in r.2...r.3 {
                    for x in r.0...r.1 {
                        items[fill[y * nx + x]] = i
                        fill[y * nx + x] += 1
                    }
                }
            }
        }

        /// Visits every occluder in cells touched by the segment (conservative supercover).
        func visit(from a: Vec2, to b: Vec2, _ body: (Int) -> Bool) {
            guard nx > 0 else { return }
            let ax = (a.x - origin.x) / cell, ay = (a.y - origin.y) / cell
            let bx = (b.x - origin.x) / cell, by = (b.y - origin.y) / cell
            let cx0 = max(0, Int(min(ax, bx).rounded(.down))), cx1 = min(nx - 1, Int(max(ax, bx).rounded(.down)))
            guard cx0 <= cx1 else { return }
            let dx = bx - ax
            for cx in cx0...cx1 {
                // y-range of the segment within this column (padded by one cell for safety).
                var ylo: Double, yhi: Double
                if dx == 0 {
                    ylo = min(ay, by); yhi = max(ay, by)
                } else {
                    let t0 = max(0, min(1, (Double(cx) - ax) / dx)), t1 = max(0, min(1, (Double(cx + 1) - ax) / dx))
                    let y0 = ay + (by - ay) * t0, y1 = ay + (by - ay) * t1
                    ylo = min(y0, y1); yhi = max(y0, y1)
                }
                let cy0 = max(0, Int(ylo.rounded(.down)) - 1), cy1 = min(ny - 1, Int(yhi.rounded(.down)) + 1)
                guard cy0 <= cy1 else { continue }
                for cy in cy0...cy1 {
                    let k = cy * nx + cx
                    for i in start[k]..<start[k + 1] where !body(items[i]) { return }
                }
            }
        }
    }
}
