import Foundation

/// A bounded 3D segment.
public struct Segment3: Hashable, Codable, Sendable {
    public var a: Vec3
    public var b: Vec3
    public init(_ a: Vec3, _ b: Vec3) { self.a = a; self.b = b }
    public var length: Double { a.distance(to: b) }
    public var midpoint: Vec3 { a.lerp(to: b, t: 0.5) }
}

/// The top surface of a roof.
public struct RoofSurface: Sendable {
    /// Planar faces, CCW seen from above.
    public var faces: [[Vec3]]
    /// Holes of each face (parallel to `faces`, CW seen from above; usually empty).
    public var faceHoles: [[[Vec3]]]
    /// Interior break lines between faces: ridges, hips and valleys.
    public var ridgeLines: [Segment3]
    /// True when the surface is the exact straight-skeleton roof.
    public var isExact: Bool
    public var warnings: [String]

    public init(faces: [[Vec3]] = [], faceHoles: [[[Vec3]]] = [], ridgeLines: [Segment3] = [], isExact: Bool = true, warnings: [String] = []) {
        self.faces = faces
        self.faceHoles = faceHoles.count == faces.count ? faceHoles : Array(repeating: [], count: faces.count)
        self.ridgeLines = ridgeLines
        self.isExact = isExact
        self.warnings = warnings
    }
}

/// Roof generation from a footprint with per-edge slopes (straight-skeleton semantics).
///
/// Every slope-defining edge spawns a plane rising inward from the edge line at
/// `baseZ` with the edge's slope angle; gable edges (nil) rise vertically and cap no
/// plane. Convex footprints are solved exactly: the roof is the lower envelope of the
/// planes, and each face is the footprint clipped by the half-planes where its plane
/// is lowest.
///
/// Non-convex footprints use a deterministic approximation (`isExact == false`): each
/// edge's plane only competes inside the edge's wedge — the convex region on the
/// inner side of the edge bounded by the plane-intersection bisectors at its two
/// endpoints — and the roof is the lowest competing plane. Faces are computed exactly
/// for that rule with polygon booleans, so they tile the footprint without gaps or
/// overlaps; valleys form at reflex corners. This reproduces the straight skeleton
/// for L, T and U shapes of uniform width but can differ where the skeleton's split
/// events matter.
public enum RoofSolver {
    /// z = height(p) = cu·x + cv·y + c0 (local coordinates, relative to baseZ).
    struct EdgePlane {
        var cu: Double, cv: Double, c0: Double
        func height(_ p: Vec2) -> Double { cu * p.x + cv * p.y + c0 }
    }

    /// a·x + b·y + c ≥ 0.
    struct HalfPlane {
        var a: Double, b: Double, c: Double
        func value(_ p: Vec2) -> Double { a * p.x + b * p.y + c }
    }

    struct Edge {
        var a: Vec2
        var b: Vec2
        var slope: Double?
        var dir: Vec2 { (b - a).normalized }
        var mid: Vec2 { a.midpoint(b) }
        /// Signed distance to the left (inside for CCW footprints) as a half-plane function.
        var inside: HalfPlane {
            let d = dir
            return HalfPlane(a: -d.y, b: d.x, c: d.y * a.x - d.x * a.y)
        }
        var plane: EdgePlane? {
            guard let s = slope else { return nil }
            let k = tan(s)
            let h = inside
            return EdgePlane(cu: k * h.a, cv: k * h.b, c0: k * h.c)
        }
    }

    public static func solve(footprint: Polygon2, slopes: [Double?], baseZ: Double) -> RoofSurface {
        var warnings: [String] = []
        let n0 = footprint.count
        guard n0 >= 3, !footprint.isDegenerate else {
            return RoofSurface(isExact: false, warnings: ["Footprint is degenerate; no roof generated."])
        }
        var sl = slopes
        if sl.count != n0 {
            warnings.append("Expected \(n0) slopes, got \(sl.count); missing edges are treated as gables.")
            sl = (0..<n0).map { $0 < slopes.count ? slopes[$0] : nil }
        }
        // Normalize to CCW; edge k of the reversed loop is original edge n-2-k reversed.
        var pts = footprint.points
        if !footprint.isCounterClockwise {
            pts.reverse()
            sl = (0..<n0).map { sl[((n0 - 2 - $0) % n0 + n0) % n0] }
        }
        // Normalize slopes.
        var clamped = false
        sl = sl.map { s in
            guard let s, s.isFinite else { return nil }
            if s >= .pi / 2 - Tolerance.angle { return nil }
            if s < 0 { clamped = true; return 0 }
            return s
        }
        if clamped { warnings.append("Negative slopes were clamped to flat.") }
        let origin = footprint.bounds.min
        let local = pts.map { $0 - origin }
        let edges = cleanEdges(local, sl)
        guard edges.count >= 3 else {
            return RoofSurface(isExact: false, warnings: warnings + ["Footprint is degenerate; no roof generated."])
        }
        let poly = Polygon2(edges.map(\.a))
        func lift(_ p: Vec2, _ h: Double) -> Vec3 { Vec3(p.x + origin.x, p.y + origin.y, baseZ + h) }

        let slopeIdx = edges.indices.filter { edges[$0].slope != nil }
        if slopeIdx.isEmpty {
            warnings.append("No slope-defining edges; generated a flat roof at the base height.")
            return RoofSurface(faces: [poly.points.map { lift($0, 0) }], isExact: true, warnings: warnings)
        }

        var faces2D: [(profile: Profile2, plane: EdgePlane)] = []
        let isExact: Bool
        let heightAt: (Vec2) -> Double
        if poly.isConvex {
            isExact = true
            let planes = slopeIdx.map { edges[$0].plane! }
            heightAt = { p in planes.map { $0.height(p) }.min() ?? 0 }
            for ii in slopeIdx.indices {
                let pi = planes[ii]
                var region = poly.points
                var empty = false
                for (jj, _) in slopeIdx.enumerated() where jj != ii {
                    let pj = planes[jj]
                    let hp = HalfPlane(a: pj.cu - pi.cu, b: pj.cv - pi.cv, c: pj.c0 - pi.c0) // h_j - h_i ≥ 0
                    if identical(hp, scale: poly.bounds) {
                        if jj < ii { empty = true; break }
                        continue
                    }
                    region = clip(region, hp)
                    if region.count < 3 { empty = true; break }
                }
                guard !empty else { continue }
                let f = Polygon2(region).simplified()
                if f.count >= 3 && !f.isDegenerate { faces2D.append((Profile2(outer: f), pi)) }
            }
        } else {
            isExact = false
            warnings.append("Non-convex footprint: roof uses the wedge-restricted plane envelope approximation of the straight skeleton.")
            let wedges = edges.indices.map { wedge(edges, $0) }
            let box = poly.bounds.expanded(by: max(poly.bounds.width, poly.bounds.height) * 2 + 1)
            let boxPts = Polygon2.rectangle(box).points
            heightAt = { p in
                var best = Double.infinity
                for i in slopeIdx where wedges[i].allSatisfy({ $0.value(p) >= -Tolerance.length }) {
                    best = min(best, edges[i].plane!.height(p))
                }
                return best.isFinite ? best : 0
            }
            let footprintProfile = [Profile2(outer: poly)]
            for i in slopeIdx {
                let pi = edges[i].plane!
                let wi = convexRegion(boxPts, wedges[i])
                guard wi.count >= 3 else { continue }
                var base = PolygonBoolean.intersection(footprintProfile, [Profile2(outer: Polygon2(wi))])
                guard !base.isEmpty else { continue }
                var bounds = Rect2.empty
                for b in base { bounds.include(b.bounds) }
                var subtract: [Profile2] = []
                for j in slopeIdx where j != i {
                    let pj = edges[j].plane!
                    let lower = HalfPlane(a: pi.cu - pj.cu, b: pi.cv - pj.cv, c: pi.c0 - pj.c0) // h_i - h_j ≥ 0
                    var hps = wedges[j]
                    if identical(lower, scale: poly.bounds) {
                        if j > i { continue }
                    } else {
                        hps.append(lower)
                    }
                    let r = convexRegion(boxPts, hps)
                    guard r.count >= 3 else { continue }
                    let rp = Polygon2(r)
                    guard !rp.isDegenerate, rp.bounds.intersects(bounds) else { continue }
                    subtract.append(Profile2(outer: rp))
                }
                if !subtract.isEmpty { base = PolygonBoolean.difference(base, subtract) }
                for b in base where b.area > Tolerance.area { faces2D.append((b, pi)) }
            }
        }

        // Validate tiling.
        let covered = faces2D.reduce(0) { $0 + $1.profile.area }
        // Allowed discrepancy: a Tolerance.length band along the boundary.
        if abs(covered - poly.area) > max(Tolerance.area, poly.perimeter * Tolerance.length) {
            warnings.append("Roof faces cover \(covered) m² of a \(poly.area) m² footprint.")
        }
        // Lift faces.
        var faces: [[Vec3]] = []
        var holes: [[[Vec3]]] = []
        for f in faces2D {
            faces.append(f.profile.outer.points.map { lift($0, f.plane.height($0)) })
            holes.append(f.profile.holes.map { h in h.points.map { lift($0, f.plane.height($0)) } })
        }
        // Break lines: face edges not on the footprint boundary, merged.
        var interior: [Segment2] = []
        for f in faces2D {
            for loop in f.profile.loops {
                for e in loop.edges where !e.isDegenerate && poly.distanceToBoundary(e.midpoint) > Tolerance.length * 10 {
                    interior.append(e)
                }
            }
        }
        let ridges = mergeCollinear(PlanarArrangement(segments: interior)).map {
            Segment3(lift($0.start, heightAt($0.start)), lift($0.end, heightAt($0.end)))
        }
        return RoofSurface(faces: faces, faceHoles: holes, ridgeLines: ridges, isExact: isExact, warnings: warnings)
    }

    /// Removes zero-length edges and merges consecutive collinear edges of equal slope.
    static func cleanEdges(_ pts: [Vec2], _ slopes: [Double?]) -> [Edge] {
        var edges: [Edge] = []
        let n = pts.count
        for i in 0..<n {
            let e = Edge(a: pts[i], b: pts[(i + 1) % n], slope: slopes[i])
            if e.a.distance(to: e.b) > Tolerance.length { edges.append(e) }
        }
        func sameSlope(_ x: Double?, _ y: Double?) -> Bool {
            switch (x, y) {
            case (nil, nil): return true
            case let (x?, y?): return abs(x - y) <= Tolerance.angle
            default: return false
            }
        }
        var changed = true
        while changed && edges.count > 3 {
            changed = false
            for i in 0..<edges.count {
                let j = (i + 1) % edges.count
                let a = edges[i], b = edges[j]
                if abs(a.dir.cross(b.dir)) <= Tolerance.angle && a.dir.dot(b.dir) > 0 && sameSlope(a.slope, b.slope) {
                    edges[i] = Edge(a: a.a, b: b.b, slope: a.slope)
                    edges.remove(at: j)
                    changed = true
                    break
                }
            }
        }
        // Reconnect endpoints after removing zero-length edges.
        for i in 0..<edges.count { edges[i].b = edges[(i + 1) % edges.count].a }
        return edges
    }

    /// True if the half-plane function is identically zero (identical planes).
    static func identical(_ h: HalfPlane, scale r: Rect2) -> Bool {
        let s = max(r.width, r.height, 1)
        return abs(h.a) * s <= Tolerance.length && abs(h.b) * s <= Tolerance.length && abs(h.c) <= Tolerance.length
    }

    /// Wedge half-planes of edge i: inner side plus the bisector constraints at both ends.
    static func wedge(_ edges: [Edge], _ i: Int) -> [HalfPlane] {
        let n = edges.count
        var hps = [edges[i].inside]
        for (other, atEnd) in [((i + n - 1) % n, false), ((i + 1) % n, true)] {
            let e = edges[i], o = edges[other]
            let v = atEnd ? e.b : e.a
            let f: HalfPlane
            if abs(e.dir.cross(o.dir)) <= Tolerance.angle && e.dir.dot(o.dir) > 0 {
                // Collinear neighbours with different slopes: split perpendicular at the vertex.
                let d = e.dir
                f = HalfPlane(a: d.x, b: d.y, c: -(d.x * v.x + d.y * v.y))
            } else if let pe = e.plane, let po = o.plane {
                f = HalfPlane(a: pe.cu - po.cu, b: pe.cv - po.cv, c: pe.c0 - po.c0)
            } else if o.slope == nil {
                f = o.inside
            } else {
                f = e.inside // e is a gable: its own wedge is irrelevant
            }
            let sv = f.value(e.mid)
            guard abs(sv) > Tolerance.lengthSquared else { continue }
            hps.append(sv > 0 ? f : HalfPlane(a: -f.a, b: -f.b, c: -f.c))
        }
        return hps
    }

    /// Sutherland–Hodgman clip of a convex polygon, keeping value ≥ 0.
    static func clip(_ poly: [Vec2], _ h: HalfPlane) -> [Vec2] {
        guard !poly.isEmpty else { return [] }
        var out: [Vec2] = []
        var prev = poly[poly.count - 1]
        var pv = h.value(prev)
        for cur in poly {
            let cv = h.value(cur)
            if (cv >= 0) != (pv >= 0) {
                out.append(prev.lerp(to: cur, t: pv / (pv - cv)))
            }
            if cv >= 0 { out.append(cur) }
            prev = cur
            pv = cv
        }
        return out
    }

    static func convexRegion(_ start: [Vec2], _ hps: [HalfPlane]) -> [Vec2] {
        var r = start
        for h in hps {
            r = clip(r, h)
            if r.count < 3 { return [] }
        }
        return r
    }

    /// Arrangement edges merged through vertices where exactly two collinear edges meet.
    static func mergeCollinear(_ arr: PlanarArrangement) -> [Segment2] {
        let verts = arr.vertices
        let ev = arr.edgeVertices
        var incident: [[Int]] = Array(repeating: [], count: verts.count)
        for (i, e) in ev.enumerated() { incident[e.a].append(i); incident[e.b].append(i) }
        func other(_ e: Int, _ v: Int) -> Int { ev[e].a == v ? ev[e].b : ev[e].a }
        func passThrough(_ v: Int, from e: Int) -> Int? {
            guard incident[v].count == 2 else { return nil }
            let f = incident[v][0] == e ? incident[v][1] : incident[v][0]
            let d0 = (verts[v] - verts[other(e, v)]).normalized, d1 = (verts[other(f, v)] - verts[v]).normalized
            return abs(d0.cross(d1)) <= Tolerance.angle && d0.dot(d1) > 0 ? f : nil
        }
        var used = Array(repeating: false, count: ev.count)
        var out: [Segment2] = []
        for e in ev.indices where !used[e] {
            used[e] = true
            var a = ev[e].a, b = ev[e].b
            var cur = e
            while let f = passThrough(b, from: cur), !used[f] { used[f] = true; b = other(f, b); cur = f }
            cur = e
            while let f = passThrough(a, from: cur), !used[f] { used[f] = true; a = other(f, a); cur = f }
            out.append(Segment2(verts[a], verts[b]))
        }
        return out
    }

    /// Closed roof slab: the top surface, a copy offset vertically down by `thickness`,
    /// and vertical fascia faces along the footprint boundary. Feature edges cover the
    /// top face outlines (including ridges, hips and valleys), the bottom boundary and
    /// the vertical corners. The surface carries absolute heights, so `baseZ` is only
    /// part of the signature for symmetry with `solve`.
    public static func roofSolid(surface: RoofSurface, footprint: Polygon2, baseZ _: Double, thickness: Double) -> Mesh {
        guard thickness > Tolerance.length, !surface.faces.isEmpty else { return .empty }
        let fp = footprint.counterClockwise
        var w = MeshWriter()
        let down = Vec3(0, 0, -thickness)
        var drawn: [Segment3] = []
        for (fi, face) in surface.faces.enumerated() {
            guard face.count >= 3 else { continue }
            let normal = newellNormal(face)
            guard normal.z > Tolerance.angle else { continue }
            let holes = fi < surface.faceHoles.count ? surface.faceHoles[fi] : []
            let o = face[0]
            func zAt(_ p: Vec2) -> Double { o.z - (normal.x * (p.x - o.x) + normal.y * (p.y - o.y)) / normal.z }
            let prof = Profile2(outer: Polygon2(face.map(\.xy)), holes: holes.map { Polygon2($0.map(\.xy)) })
            let tri = Triangulator.triangulate(prof)
            let top = tri.points.map { $0.at(z: zAt($0)) }
            let tb = w.addVertices(top, normal: normal)
            let bb = w.addVertices(top.map { $0 + down }, normal: -normal)
            for t in stride(from: 0, to: tri.triangles.count, by: 3) {
                let a = UInt32(tri.triangles[t]), b = UInt32(tri.triangles[t + 1]), c = UInt32(tri.triangles[t + 2])
                w.addTriangle(tb + a, tb + b, tb + c)
                w.addTriangle(bb + a, bb + c, bb + b)
            }
            for loop in prof.loops {
                let pts = loop.points
                for i in 0..<pts.count {
                    let p = pts[i], q = pts[(i + 1) % pts.count]
                    let pt = p.at(z: zAt(p)), qt = q.at(z: zAt(q))
                    let onBoundary = fp.distanceToBoundary(p.midpoint(q)) <= Tolerance.length * 10
                    if !onBoundary {
                        // Interior break line: draw it once, on the top surface vertices.
                        let seen = drawn.contains { ($0.a.isAlmostEqual(pt) && $0.b.isAlmostEqual(qt)) || ($0.a.isAlmostEqual(qt) && $0.b.isAlmostEqual(pt)) }
                        if !seen, let ip = tri.points.firstIndex(where: { $0.isAlmostEqual(p) }),
                           let iq = tri.points.firstIndex(where: { $0.isAlmostEqual(q) }) {
                            drawn.append(Segment3(pt, qt))
                            w.addEdge(tb + UInt32(ip), tb + UInt32(iq))
                        }
                        continue
                    }
                    let d = (q - p).normalized
                    let base = w.addVertices([pt + down, qt + down, qt, pt], normal: Vec3(d.y, -d.x, 0))
                    w.addTriangle(base, base + 1, base + 2)
                    w.addTriangle(base, base + 2, base + 3)
                    w.addEdge(base, base + 1)
                    w.addEdge(base + 3, base + 2)
                    if fp.points.contains(where: { $0.isAlmostEqual(p, tolerance: Tolerance.length * 10) }) {
                        w.addEdge(base, base + 3)
                    }
                }
            }
        }
        return w.mesh
    }
}
