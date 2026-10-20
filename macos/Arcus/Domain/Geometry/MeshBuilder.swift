import Foundation

/// A non-vertical plane written as a height field: z = a·x + b·y + c.
public struct PlaneZ: Hashable, Codable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double

    public init(a: Double, b: Double, c: Double) { self.a = a; self.b = b; self.c = c }

    /// Height of the plane above plan point p.
    public func z(at p: Vec2) -> Double { a * p.x + b * p.y + c }
    /// Horizontal plane at height z.
    public static func flat(_ z: Double) -> PlaneZ { PlaneZ(a: 0, b: 0, c: z) }
    /// Plane through three points; nil if they are collinear in plan.
    public static func through(_ p0: Vec3, _ p1: Vec3, _ p2: Vec3) -> PlaneZ? {
        let n = (p1 - p0).cross(p2 - p0)
        guard abs(n.z) > Tolerance.lengthSquared else { return nil }
        let a = -n.x / n.z, b = -n.y / n.z
        return PlaneZ(a: a, b: b, c: p0.z - a * p0.x - b * p0.y)
    }
    /// Unit normal pointing up.
    public var upNormal: Vec3 { Vec3(-a, -b, 1).normalized }
}

/// Mesh accumulation with per-face (flat) vertices.
struct MeshWriter {
    var mesh = Mesh()

    var count: UInt32 { UInt32(mesh.positions.count) }

    /// Adds vertices with a shared normal and returns the base index.
    @discardableResult
    mutating func addVertices(_ pts: [Vec3], normal: Vec3) -> UInt32 {
        let base = count
        mesh.positions.append(contentsOf: pts)
        mesh.normals.append(contentsOf: repeatElement(normal, count: pts.count))
        return base
    }

    mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        mesh.indices.append(contentsOf: [a, b, c])
    }

    mutating func addEdge(_ a: UInt32, _ b: UInt32) {
        mesh.featureEdges.append(contentsOf: [a, b])
    }

    /// Adds a planar polygon face (CCW seen from outside) with duplicated vertices,
    /// triangulating it in its own plane. Returns the index of its first vertex, or nil
    /// if degenerate. Vertices keep the input order.
    @discardableResult
    mutating func addFace(_ pts: [Vec3], normal: Vec3? = nil) -> UInt32? {
        guard pts.count >= 3 else { return nil }
        let n = normal ?? newellNormal(pts)
        guard n.lengthSquared > 0 else { return nil }
        let base = addVertices(pts, normal: n)
        if pts.count == 3 {
            addTriangle(base, base + 1, base + 2)
            return base
        }
        // Project to the face plane and triangulate (handles concave faces).
        let x = n.anyPerpendicular, y = n.cross(x)
        let o = pts[0]
        let flat = pts.map { Vec2(($0 - o).dot(x), ($0 - o).dot(y)) }
        if Polygon2(flat).isConvex {
            for i in 1..<(pts.count - 1) { addTriangle(base, base + UInt32(i), base + UInt32(i + 1)) }
            return base
        }
        let tri = Triangulator.triangulate(Polygon2(flat))
        // Map triangulator points back to input indices (duplicates collapse to the first).
        var lookup: [Int] = []
        for p in tri.points { lookup.append(flat.firstIndex { $0.isAlmostEqual(p) } ?? 0) }
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            addTriangle(base + UInt32(lookup[tri.triangles[t]]), base + UInt32(lookup[tri.triangles[t + 1]]),
                        base + UInt32(lookup[tri.triangles[t + 2]]))
        }
        return base
    }
}

/// Newell's robust polygon normal (unit length, zero for degenerate polygons).
func newellNormal(_ pts: [Vec3]) -> Vec3 {
    var n = Vec3.zero
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    }
    return n.length > Tolerance.lengthSquared ? n.normalized : .zero
}

/// Builders for closed, flat-shaded solids.
///
/// All meshes use per-face vertices (flat normals), counter-clockwise winding seen
/// from outside, and carry feature edges for line drawing: cap outlines, plus
/// longitudinal edges only where the profile turns by more than `creaseAngle`, so
/// tessellated curves do not show every facet edge.
public enum MeshBuilder {
    /// Cleans a profile: simplified loops, outer CCW, holes CW, degenerate loops dropped.
    static func prepare(_ profile: Profile2) -> Profile2? {
        let outer = profile.outer.simplified()
        guard outer.count >= 3, !outer.isDegenerate else { return nil }
        let holes = profile.holes.map { $0.simplified() }.filter { $0.count >= 3 && !$0.isDegenerate }
        return Profile2(outer: outer, holes: holes)
    }

    /// Turn angle (0…π) at vertex i of a loop.
    static func turnAngle(_ loop: [Vec2], _ i: Int) -> Double {
        let n = loop.count
        let d0 = (loop[i] - loop[(i + n - 1) % n]).normalized, d1 = (loop[(i + 1) % n] - loop[i]).normalized
        return acos(max(-1, min(1, d0.dot(d1))))
    }

    /// Vertical prism between two height fields over a profile.
    static func prism(_ profile: Profile2, bottom: (Vec2) -> Double, top: (Vec2) -> Double,
                      bottomNormal: Vec3, topNormal: Vec3, creaseAngle: Double) -> Mesh {
        guard let prof = prepare(profile) else { return .empty }
        var w = MeshWriter()
        let tri = Triangulator.triangulate(prof)
        guard !tri.triangles.isEmpty else { return .empty }
        let topBase = w.addVertices(tri.points.map { $0.at(z: top($0)) }, normal: topNormal)
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            w.addTriangle(topBase + UInt32(tri.triangles[t]), topBase + UInt32(tri.triangles[t + 1]), topBase + UInt32(tri.triangles[t + 2]))
        }
        let botBase = w.addVertices(tri.points.map { $0.at(z: bottom($0)) }, normal: bottomNormal)
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            w.addTriangle(botBase + UInt32(tri.triangles[t]), botBase + UInt32(tri.triangles[t + 2]), botBase + UInt32(tri.triangles[t + 1]))
        }
        for loop in prof.loops {
            let pts = loop.points
            let n = pts.count
            for i in 0..<n {
                let p = pts[i], q = pts[(i + 1) % n]
                let d = (q - p).normalized
                let normal = Vec3(d.y, -d.x, 0)
                let base = w.addVertices([p.at(z: bottom(p)), q.at(z: bottom(q)), q.at(z: top(q)), p.at(z: top(p))], normal: normal)
                w.addTriangle(base, base + 1, base + 2)
                w.addTriangle(base, base + 2, base + 3)
                w.addEdge(base, base + 1)
                w.addEdge(base + 3, base + 2)
                if turnAngle(pts, i) > creaseAngle { w.addEdge(base, base + 3) }
            }
        }
        return w.mesh
    }

    /// Closed vertical extrusion of a profile between z0 and z1 (order-independent).
    public static func extrude(_ profile: Profile2, bottom z0: Double, top z1: Double, creaseAngle: Double = .pi / 8) -> Mesh {
        let lo = min(z0, z1), hi = max(z0, z1)
        guard hi - lo > Tolerance.length else { return .empty }
        return prism(profile, bottom: { _ in lo }, top: { _ in hi }, bottomNormal: -.unitZ, topNormal: .unitZ, creaseAngle: creaseAngle)
    }

    /// Extrusion of a profile given in the frame's local XY plane along local +Z by
    /// `depth` (negative extrudes along -Z).
    public static func extrude(_ profile: Profile2, frame: Transform3, depth: Double, creaseAngle: Double = .pi / 8) -> Mesh {
        extrude(profile, bottom: min(0, depth), top: max(0, depth), creaseAngle: creaseAngle).transformed(frame)
    }

    /// Slab between two (possibly sloped) planes over a profile. The top must lie above
    /// the bottom everywhere over the profile.
    public static func slab(_ profile: Profile2, bottom: PlaneZ, top: PlaneZ) -> Mesh {
        prism(profile, bottom: bottom.z(at:), top: top.z(at:), bottomNormal: -bottom.upNormal, topNormal: top.upNormal,
              creaseAngle: .pi / 8)
    }

    /// Vertical cylinder approximated by a regular polygon with `segments` sides.
    public static func cylinder(center: Vec2, radius: Double, z0: Double, z1: Double, segments: Int = 24) -> Mesh {
        let n = max(3, segments)
        guard radius > Tolerance.length else { return .empty }
        let pts = (0..<n).map { center + Vec2.fromAngle(Double($0) / Double(n) * Angle.twoPi, length: radius) }
        return extrude(Profile2(outer: Polygon2(pts)), bottom: z0, top: z1)
    }

    /// Sweeps a closed profile along a polyline path with mitered joints and capped ends.
    ///
    /// The profile is given in local (u, v) coordinates where u points to the left of
    /// the path direction (`up × direction`) and v is perpendicular to both (close to
    /// `up`). Joints lie in the bisecting plane of adjacent segments.
    public static func sweep(profile: Polygon2, along path: [Vec3], up: Vec3 = .unitZ) -> Mesh {
        var pts: [Vec3] = []
        for p in path where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        let prof = profile.simplified().counterClockwise
        guard pts.count >= 2, prof.count >= 3, !prof.isDegenerate else { return .empty }
        let m = pts.count
        let dirs = (0..<(m - 1)).map { (pts[$0 + 1] - pts[$0]).normalized }
        var us: [Vec3] = [], vs: [Vec3] = []
        let upN = up.normalized.lengthSquared > 0 ? up.normalized : .unitZ
        for (s, d) in dirs.enumerated() {
            var u = upN.cross(d)
            if u.length <= Tolerance.angle { u = s > 0 ? us[s - 1] : d.anyPerpendicular }
            u = (u - d * u.dot(d)).normalized
            us.append(u)
            vs.append(d.cross(u))
        }
        /// Profile point q at joint j (on the joint's miter plane, using the incoming frame).
        func ringPoint(_ j: Int, _ q: Vec2) -> Vec3 {
            let s = j == 0 ? 0 : j - 1
            let base = pts[j] + us[s] * q.x + vs[s] * q.y
            guard j > 0, j < m - 1 else { return base }
            let nm = dirs[j - 1] + dirs[j]
            guard nm.length > Tolerance.angle else { return base }
            let n = nm.normalized
            let lambda = -(base - pts[j]).dot(n) / dirs[j - 1].dot(n)
            return base + dirs[j - 1] * lambda
        }
        let qn = prof.count
        let rings: [[Vec3]] = (0..<m).map { j in prof.points.map { ringPoint(j, $0) } }
        var w = MeshWriter()
        let crease = Double.pi / 8
        for s in 0..<(m - 1) {
            for k in 0..<qn {
                let k1 = (k + 1) % qn
                let e = prof.points[k1] - prof.points[k]
                let out2 = Vec2(e.y, -e.x).normalized
                let expected = us[s] * out2.x + vs[s] * out2.y
                var quad = [rings[s][k], rings[s][k1], rings[s + 1][k1], rings[s + 1][k]]
                let flipped = newellNormal(quad).dot(expected) < 0
                if flipped { quad = [quad[0], quad[3], quad[2], quad[1]] }
                guard let base = w.addFace(quad) else { continue }
                // Slots of the canonical corners (start ring k, k+1; end ring k, k+1).
                let iS0 = base, iS1 = flipped ? base + 3 : base + 1
                let iE0 = flipped ? base + 1 : base + 3, iE1 = base + 2
                if s == 0 { w.addEdge(iS0, iS1) }
                if s == m - 2 { w.addEdge(iE0, iE1) }
                if MeshBuilder.turnAngle(prof.points, k) > crease { w.addEdge(iS0, iE0) }
                if s > 0 && acos(max(-1, min(1, dirs[s - 1].dot(dirs[s])))) > crease { w.addEdge(iS0, iS1) }
            }
        }
        // End caps.
        let tri = Triangulator.triangulate(prof)
        let startPts = tri.points.map { ringPoint(0, $0) }
        let endPts = tri.points.map { ringPoint(m - 1, $0) }
        let sb = w.addVertices(startPts, normal: -dirs[0])
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            w.addTriangle(sb + UInt32(tri.triangles[t]), sb + UInt32(tri.triangles[t + 2]), sb + UInt32(tri.triangles[t + 1]))
        }
        let eb = w.addVertices(endPts, normal: dirs[m - 2])
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            w.addTriangle(eb + UInt32(tri.triangles[t]), eb + UInt32(tri.triangles[t + 1]), eb + UInt32(tri.triangles[t + 2]))
        }
        return w.mesh
    }

    /// Revolves a closed (r, z) profile about the vertical axis through `axisOrigin`.
    /// A partial `angle` gets planar end caps. The profile should stay at r ≥ 0.
    public static func revolve(profile: [Vec2], around axisOrigin: Vec3, segments: Int, angle: Double = 2 * .pi) -> Mesh {
        let prof = Polygon2(profile).simplified().counterClockwise
        guard prof.count >= 3, !prof.isDegenerate, abs(angle) > Tolerance.angle else { return .empty }
        let full = abs(angle) >= Angle.twoPi - Tolerance.angle
        let sweepAngle = full ? Angle.twoPi : angle
        let n = full ? max(3, segments) : max(1, segments)
        let phis = (0...n).map { sweepAngle * Double($0) / Double(n) }
        func pos(_ q: Vec2, _ k: Int) -> Vec3 {
            let phi = phis[k]
            return axisOrigin + Vec3(q.x * cos(phi), q.x * sin(phi), q.y)
        }
        var w = MeshWriter()
        let crease = Double.pi / 8
        let pp = prof.points
        let qn = pp.count
        // VIS: angles' cosines and sines once, and a direct path for quads off the axis (the common case).
        let cs = phis.map { (cos($0), sin($0)) }
        func at(_ q: Vec2, _ k: Int) -> Vec3 { axisOrigin + Vec3(q.x * cs[k].0, q.x * cs[k].1, q.y) }
        for i in 0..<qn {
            let p = pp[i], q = pp[(i + 1) % qn]
            let ringEdge = turnAngle(pp, i) > crease && p.x > Tolerance.length
            let offAxis = p.x > Tolerance.length && q.x > Tolerance.length
            for k in 0..<n {
                if offAxis && full {
                    let a = at(p, k), b = at(p, k + 1), c = at(q, k + 1), d = at(q, k)
                    let fn = (b - a).cross(c - a) + (c - a).cross(d - a)
                    let len = fn.length
                    guard len > 1e-20 else { continue }
                    let base = w.addVertices([a, b, c, d], normal: fn / len)
                    w.addTriangle(base, base + 1, base + 2)
                    w.addTriangle(base, base + 2, base + 3)
                    if ringEdge { w.addEdge(base, base + 1) }
                    continue
                }
                // Outward for a CCW profile and positive sweep; negative sweeps are fixed
                // globally by the volume check below.
                let poly = [pos(p, k), pos(p, k + 1), pos(q, k + 1), pos(q, k)]
                // Collapse vertices on the axis.
                var clean: [Vec3] = []
                var slots: [Int] = []
                for (vi, v) in poly.enumerated() where !(clean.last.map { $0.isAlmostEqual(v) } ?? false) {
                    clean.append(v); slots.append(vi)
                }
                if clean.count > 1 && clean[0].isAlmostEqual(clean[clean.count - 1]) { clean.removeLast(); slots.removeLast() }
                guard clean.count >= 3 else { continue }
                // VIS: revolve quads are planar trapezoids (and triangles at the axis): add them directly, no triangulation.
                let fn = newellNormal(clean)
                guard fn.lengthSquared > 0 else { continue }
                let base = w.addVertices(clean, normal: fn)
                w.addTriangle(base, base + 1, base + 2)
                if clean.count == 4 { w.addTriangle(base, base + 2, base + 3) }
                // Ring edge at profile vertex p (edge between slots 0 and 1) where the profile creases.
                if ringEdge, let a = slots.firstIndex(of: 0), let b = slots.firstIndex(of: 1) {
                    w.addEdge(base + UInt32(a), base + UInt32(b))
                }
                if !full {
                    // Cap outlines: profile edge at the first and last angle.
                    if k == 0, let a = slots.firstIndex(of: 0), let b = slots.firstIndex(of: 3) {
                        w.addEdge(base + UInt32(a), base + UInt32(b))
                    }
                    if k == n - 1, let a = slots.firstIndex(of: 1), let b = slots.firstIndex(of: 2) {
                        w.addEdge(base + UInt32(a), base + UInt32(b))
                    }
                }
            }
        }
        if !full {
            let tri = Triangulator.triangulate(prof)
            for (k, outwardSign) in [(0, -1.0), (n, 1.0)] {
                let phi = phis[k]
                let tangent = Vec3(-sin(phi), cos(phi), 0)
                let normal = tangent * outwardSign
                let pts3 = tri.points.map { pos($0, k) }
                let base = w.addVertices(pts3, normal: normal)
                for t in stride(from: 0, to: tri.triangles.count, by: 3) {
                    let a = tri.triangles[t], b = tri.triangles[t + 1], c = tri.triangles[t + 2]
                    let tn = (pts3[b] - pts3[a]).cross(pts3[c] - pts3[a])
                    if tn.dot(normal) >= 0 { w.addTriangle(base + UInt32(a), base + UInt32(b), base + UInt32(c)) }
                    else { w.addTriangle(base + UInt32(a), base + UInt32(c), base + UInt32(b)) }
                }
            }
        }
        var mesh = w.mesh
        if mesh.signedVolume < 0 {
            for i in stride(from: 0, to: mesh.indices.count, by: 3) { mesh.indices.swapAt(i + 1, i + 2) }
            mesh.normals = mesh.normals.map { -$0 }
        }
        return mesh
    }
}
