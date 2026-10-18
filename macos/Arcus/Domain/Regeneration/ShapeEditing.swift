import Foundation
import ArcusGeometry

/// Top surface of a shape-edited floor or flat roof: a triangulated height field over the plan profile whose vertices
/// are the boundary vertices plus interior shape points, each lifted by its elevation offset. The bottom stays planar,
/// so lowering points (drainage falls) reduces the volume while the plan area is unchanged.
public struct ShapedSurface: Sendable {
    public var points: [Vec2]
    /// Elevation offset of each point from the unedited top plane.
    public var offsets: [Double]
    /// Counter-clockwise triangles (index triples into `points`).
    public var triangles: [Int]

    /// Offset at a plan point (barycentric interpolation), nil outside the surface.
    public func offset(at p: Vec2) -> Double? {
        for t in stride(from: 0, to: triangles.count, by: 3) {
            let (i, j, k) = (triangles[t], triangles[t + 1], triangles[t + 2])
            guard let (u, v, w) = ShapeEditing.barycentric(p, points[i], points[j], points[k]), u >= -1e-9, v >= -1e-9, w >= -1e-9 else { continue }
            return u * offsets[i] + v * offsets[j] + w * offsets[k]
        }
        return nil
    }
}

public enum ShapeEditing {
    /// Points closer than this to a vertex edit that vertex.
    public static let snapTolerance = 0.01

    /// Whether an element can be shape edited: floors, building pads and flat footprint roofs.
    public static func canEdit(_ e: Element) -> Bool {
        switch e.data {
        case .slab: return e.category == .floors || e.category == .buildingPads
        case .roof(let r): return r.extrusion == nil && !r.edgeSlopes.isEmpty && r.edgeSlopes.allSatisfy { $0 == nil }
        default: return false
        }
    }

    public static func points(of e: Element) -> [ShapePoint] {
        switch e.data {
        case .slab(let s): return s.shapePoints ?? []
        case .roof(let r): return r.shapePoints ?? []
        default: return []
        }
    }

    public static func setPoints(_ pts: [ShapePoint], on e: inout Element) {
        let value = pts.isEmpty ? nil : pts
        switch e.data {
        case .slab: e.slab?.shapePoints = value
        case .roof: e.roof?.shapePoints = value
        default: break
        }
    }

    /// Plan profile being shape edited (floor boundary, or roof footprint with openings).
    public static func profile(of e: Element) -> Profile2? {
        switch e.data {
        case .slab: return SlabGeometry.profile(e)
        case .roof:
            guard let fp = RoofGeometry.footprint(e) else { return nil }
            return Profile2(outer: fp.polygon, holes: RoofGeometry.openings(e))
        default: return nil
        }
    }

    /// Profile normalized as the mesh builders expect: simplified loops, outer counter-clockwise, holes clockwise.
    static func prepared(_ profile: Profile2) -> Profile2? {
        let outer = profile.outer.simplified().counterClockwise
        guard outer.count >= 3, !outer.isDegenerate else { return nil }
        let holes = profile.holes.map { $0.simplified().clockwise }.filter { $0.count >= 3 && !$0.isDegenerate }
        return Profile2(outer: outer, holes: holes)
    }

    static func barycentric(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> (Double, Double, Double)? {
        let d = (b - a).cross(c - a)
        guard abs(d) > 1e-15 else { return nil }
        let u = (b - p).cross(c - p) / d, v = (c - p).cross(a - p) / d
        return (u, v, 1 - u - v)
    }

    /// Where a shape point may go: inside the profile and not on (or within tolerance of) a boundary edge unless it
    /// is on a vertex.
    public static func isPlaceable(_ p: Vec2, in profile: Profile2) -> Bool {
        let verts = profile.loops.flatMap(\.points)
        if verts.contains(where: { $0.distance(to: p) <= snapTolerance }) { return true }
        guard profile.contains(p) else { return false }
        return !profile.loops.flatMap(\.edges).contains { $0.distance(to: p) <= snapTolerance }
    }

    /// Builds the shaped top surface: the profile's constrained triangulation with interior points inserted and
    /// Delaunay edge flips.
    public static func surface(_ profile: Profile2, points shape: [ShapePoint]) -> ShapedSurface? {
        guard let prof = prepared(profile) else { return nil }
        let tri = Triangulator.triangulate(prof)
        guard !tri.triangles.isEmpty else { return nil }
        var pts = tri.points
        var offs = pts.map { p in shape.first { $0.position.distance(to: p) <= snapTolerance }?.offset ?? 0 }
        var tris = tri.triangles
        for sp in shape where !pts.contains(where: { $0.distance(to: sp.position) <= snapTolerance }) {
            guard isPlaceable(sp.position, in: prof) else { continue }
            // Find the containing triangle and split it (points on an interior edge split both neighbors).
            var host: Int?
            for t in stride(from: 0, to: tris.count, by: 3) {
                guard let (u, v, w) = barycentric(sp.position, pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]]) else { continue }
                if u >= -1e-9, v >= -1e-9, w >= -1e-9 { host = t; break }
            }
            guard let t = host else { continue }
            let n = pts.count
            pts.append(sp.position); offs.append(sp.offset)
            let (a, b, c) = (tris[t], tris[t + 1], tris[t + 2])
            tris.replaceSubrange(t..<(t + 3), with: [a, b, n])
            tris += [b, c, n, c, a, n]
        }
        removeDegenerate(&tris, pts)
        flipToDelaunay(&tris, pts)
        return ShapedSurface(points: pts, offsets: offs, triangles: tris)
    }

    /// Drops zero-area triangles left by points inserted exactly on an interior edge; the neighbour split covers
    /// the same area.
    static func removeDegenerate(_ tris: inout [Int], _ pts: [Vec2]) {
        var out: [Int] = []
        for t in stride(from: 0, to: tris.count, by: 3) {
            let a = pts[tris[t]], b = pts[tris[t + 1]], c = pts[tris[t + 2]]
            if (b - a).cross(c - a) > 1e-12 { out += [tris[t], tris[t + 1], tris[t + 2]] }
        }
        // A point on a shared edge leaves the neighbour unsplit (its edge now has a hanging vertex): split it too.
        var changed = true
        while changed {
            changed = false
            for t in stride(from: 0, to: out.count, by: 3) {
                for e in 0..<3 {
                    let i = out[t + e], j = out[t + (e + 1) % 3], k = out[t + (e + 2) % 3]
                    let a = pts[i], b = pts[j]
                    let seg = Segment2(a, b)
                    guard let m = pts.indices.first(where: { $0 != i && $0 != j && seg.distance(to: pts[$0]) < 1e-9 && seg.parameter(of: pts[$0]) > 1e-9 && seg.parameter(of: pts[$0]) < 1 - 1e-9 }) else { continue }
                    out.replaceSubrange(t..<(t + 3), with: [i, m, k])
                    out += [m, j, k]
                    changed = true
                    break
                }
                if changed { break }
            }
        }
        tris = out
    }

    /// Lawson flips on shared edges until every edge is locally Delaunay (boundary edges are never shared).
    static func flipToDelaunay(_ tris: inout [Int], _ pts: [Vec2]) {
        func inCircle(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Bool {
            let ax = a.x - d.x, ay = a.y - d.y, bx = b.x - d.x, by = b.y - d.y, cx = c.x - d.x, cy = c.y - d.y
            let det = (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay)
            return det > 1e-12
        }
        for _ in 0..<(tris.count * 4) {
            var edgeOwner: [UInt64: (tri: Int, opposite: Int)] = [:]
            var flipped = false
            outer: for t in stride(from: 0, to: tris.count, by: 3) {
                for e in 0..<3 {
                    let i = tris[t + e], j = tris[t + (e + 1) % 3], k = tris[t + (e + 2) % 3]
                    let key = UInt64(min(i, j)) << 32 | UInt64(max(i, j))
                    if let other = edgeOwner[key] {
                        let l = other.opposite
                        // Triangles (i, j, k) and (j, i, l): flip to (k, l, j) and (l, k, i) when l lies inside the circumcircle.
                        guard inCircle(pts[i], pts[j], pts[k], pts[l]) else { continue }
                        // Both new triangles counter-clockwise ⇔ the quad (i, l, j, k) is convex.
                        let n1 = [k, l, j], n2 = [l, k, i]
                        guard area(n1, pts) > 1e-12, area(n2, pts) > 1e-12 else { continue }
                        tris.replaceSubrange(t..<(t + 3), with: n1)
                        tris.replaceSubrange(other.tri..<(other.tri + 3), with: n2)
                        flipped = true
                        break outer
                    }
                    edgeOwner[key] = (t, k)
                }
            }
            if !flipped { return }
        }
    }

    static func area(_ t: [Int], _ pts: [Vec2]) -> Double { (pts[t[1]] - pts[t[0]]).cross(pts[t[2]] - pts[t[0]]) / 2 }

    /// Closed solid under a shaped top: planar bottom, triangulated top, vertical sides along every loop.
    public static func mesh(_ profile: Profile2, bottom: PlaneZ, top: PlaneZ, points shape: [ShapePoint]) -> Mesh {
        guard let prof = prepared(profile), let s = surface(prof, points: shape) else { return .empty }
        func topZ(_ i: Int) -> Double { top.z(at: s.points[i]) + s.offsets[i] }
        func topAt(_ p: Vec2) -> Double { top.z(at: p) + (s.points.indices.first { s.points[$0].distance(to: p) <= snapTolerance }.map { s.offsets[$0] } ?? 0) }
        var m = Mesh()
        var normals: [Int: Vec3] = [:]
        for t in stride(from: 0, to: s.triangles.count, by: 3) {
            let ids = [s.triangles[t], s.triangles[t + 1], s.triangles[t + 2]]
            let v = ids.map { s.points[$0].at(z: topZ($0)) }
            let n = (v[1] - v[0]).cross(v[2] - v[0]).normalized
            normals[t] = n
            m.addConvexFace(v, normal: n, edges: false)
            let bv = ids.reversed().map { s.points[$0].at(z: bottom.z(at: s.points[$0])) }
            m.addConvexFace(bv, normal: -bottom.upNormal, edges: false)
        }
        // Creases between top triangles whose normals differ (ridges and valleys of the falls).
        var owner: [UInt64: Int] = [:]
        for t in stride(from: 0, to: s.triangles.count, by: 3) {
            for e in 0..<3 {
                let i = s.triangles[t + e], j = s.triangles[t + (e + 1) % 3]
                let key = UInt64(min(i, j)) << 32 | UInt64(max(i, j))
                if let o = owner[key], let n1 = normals[o], let n2 = normals[t], n1.dot(n2) < cos(0.5 * .pi / 180) {
                    let base = UInt32(m.positions.count)
                    m.positions += [s.points[i].at(z: topZ(i)), s.points[j].at(z: topZ(j))]
                    m.normals += [n2, n2]
                    m.featureEdges += [base, base + 1]
                } else {
                    owner[key] = t
                }
            }
        }
        for loop in prof.loops {
            let pts = loop.points, n = pts.count
            for i in 0..<n {
                let p = pts[i], q = pts[(i + 1) % n]
                let d = (q - p).normalized
                let side = [p.at(z: bottom.z(at: p)), q.at(z: bottom.z(at: q)), q.at(z: topAt(q)), p.at(z: topAt(p))]
                let base = UInt32(m.positions.count)
                m.addConvexFace(side, normal: Vec3(d.y, -d.x, 0), edges: false)
                m.featureEdges += [base, base + 1, base + 3, base + 2]
                let prev = pts[(i + n - 1) % n]
                let turn = acos(max(-1, min(1, (p - prev).normalized.dot(d))))
                if turn > .pi / 8 { m.featureEdges += [base, base + 3] }
            }
        }
        return m
    }
}
