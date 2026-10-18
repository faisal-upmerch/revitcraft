import Foundation

/// Plane sections of triangle meshes.
///
/// Sign convention: a vertex whose signed distance to the plane is within
/// `Tolerance.length` is snapped onto the plane and then treated as lying on the
/// positive side. Every triangle is therefore classified consistently, a face lying in
/// the plane produces nothing, and each crossing edge yields exactly one point shared
/// by both adjacent triangles (vertices are welded by position first).
public enum MeshSection {
    /// Endpoint identity: an on-plane vertex or a crossing edge (welded vertex ids).
    private enum Key: Hashable {
        case vertex(Int)
        case edge(Int, Int)
    }

    private struct RawSegment {
        var a: Key
        var b: Key
        var pa: Vec3
        var pb: Vec3
    }

    private static func rawSegments(_ mesh: Mesh, plane: Plane3) -> [RawSegment] {
        var welder = PointWelder3(tolerance: Tolerance.length)
        let ids = mesh.positions.map { welder.id(for: $0) }
        let wp = welder.points
        let dist: [Double] = wp.map {
            let d = plane.signedDistance($0)
            return abs(d) <= Tolerance.length ? 0 : d
        }
        var out: [RawSegment] = []
        for t in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let v = [ids[Int(mesh.indices[t])], ids[Int(mesh.indices[t + 1])], ids[Int(mesh.indices[t + 2])]]
            if v[0] == v[1] || v[1] == v[2] || v[0] == v[2] { continue }
            let pos = v.map { dist[$0] >= 0 }
            if pos[0] == pos[1] && pos[1] == pos[2] { continue }
            var pts: [(Key, Vec3)] = []
            for i in 0..<3 {
                let a = v[i], b = v[(i + 1) % 3]
                guard pos[(i)] != pos[(i + 1) % 3] else { continue }
                let (lo, hi) = a < b ? (a, b) : (b, a)
                if dist[lo] == 0 { pts.append((.vertex(lo), wp[lo])); continue }
                if dist[hi] == 0 { pts.append((.vertex(hi), wp[hi])); continue }
                let s = dist[lo] / (dist[lo] - dist[hi])
                pts.append((.edge(lo, hi), wp[lo].lerp(to: wp[hi], t: s)))
            }
            guard pts.count == 2, pts[0].0 != pts[1].0 else { continue }
            // Orient so that the solid (behind the triangle) lies to the left in plane coordinates.
            let n = (wp[v[1]] - wp[v[0]]).cross(wp[v[2]] - wp[v[0]])
            let dir = plane.normal.cross(n)
            if (pts[1].1 - pts[0].1).dot(dir) >= 0 {
                out.append(RawSegment(a: pts[0].0, b: pts[1].0, pa: pts[0].1, pb: pts[1].1))
            } else {
                out.append(RawSegment(a: pts[1].0, b: pts[0].0, pa: pts[1].1, pb: pts[0].1))
            }
        }
        return out
    }

    /// All section segments in plane coordinates (works on open / non-manifold meshes).
    /// For closed meshes, segments are oriented so the material lies on their left.
    public static func sectionSegments(_ mesh: Mesh, plane: Plane3) -> [Segment2] {
        rawSegments(mesh, plane: plane).map { Segment2(plane.toPlane($0.pa), plane.toPlane($0.pb)) }
    }

    /// Closed section loops in plane coordinates (`plane.toPlane`). For closed meshes,
    /// outer loops are CCW and holes CW. Collinear points are merged and loops with
    /// area below `Tolerance.area` are dropped. Open chains are discarded.
    public static func section(_ mesh: Mesh, plane: Plane3) -> [Polygon2] {
        let segs = rawSegments(mesh, plane: plane)
        var outgoing: [Key: [Int]] = [:]
        for (i, s) in segs.enumerated() { outgoing[s.a, default: []].append(i) }
        var used = Array(repeating: false, count: segs.count)
        var loops: [Polygon2] = []
        for start in segs.indices where !used[start] {
            var chain: [Int] = []
            var cur = start
            var closed = false
            while true {
                used[cur] = true
                chain.append(cur)
                let endKey = segs[cur].b
                if endKey == segs[start].a { closed = true; break }
                guard let next = outgoing[endKey]?.first(where: { !used[$0] }) else { break }
                cur = next
            }
            guard closed else { continue }
            let pts = chain.map { plane.toPlane(segs[$0].pa) }
            let poly = Polygon2(pts).simplified()
            if poly.count >= 3 && !poly.isDegenerate { loops.append(poly) }
        }
        return loops
    }
}

/// Half-space clipping of meshes.
public enum MeshClip {
    /// Keeps the part of the mesh on or below the plane (signed distance ≤ 0), splitting
    /// straddling triangles and feature edges. The cut is not capped.
    public static func clip(_ mesh: Mesh, keepingBelow plane: Plane3) -> Mesh {
        let d: [Double] = mesh.positions.map {
            let s = plane.signedDistance($0)
            return abs(s) <= Tolerance.length ? 0 : s
        }
        let hasNormals = mesh.normals.count == mesh.positions.count
        var out = Mesh()
        var remap = Array(repeating: -1, count: mesh.positions.count)
        var cutVerts: [SIMD2<Int>: UInt32] = [:]

        func keep(_ i: Int) -> UInt32 {
            if remap[i] < 0 {
                remap[i] = out.positions.count
                out.positions.append(mesh.positions[i])
                if hasNormals { out.normals.append(mesh.normals[i]) }
            }
            return UInt32(remap[i])
        }
        func cut(_ i: Int, _ j: Int) -> UInt32 {
            let key = SIMD2(min(i, j), max(i, j))
            if let v = cutVerts[key] { return v }
            let (a, b) = (key.x, key.y)
            let t = d[a] / (d[a] - d[b])
            let v = UInt32(out.positions.count)
            out.positions.append(mesh.positions[a].lerp(to: mesh.positions[b], t: t))
            if hasNormals { out.normals.append(mesh.normals[a].lerp(to: mesh.normals[b], t: t).normalized) }
            cutVerts[key] = v
            return v
        }

        for t in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let v = [Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2])]
            let inside = v.map { d[$0] <= 0 }
            if inside.allSatisfy({ $0 }) {
                out.indices.append(contentsOf: v.map(keep))
                continue
            }
            if !inside.contains(true) { continue }
            var poly: [UInt32] = []
            for k in 0..<3 {
                let a = v[k], b = v[(k + 1) % 3]
                if inside[k] { poly.append(keep(a)) }
                if inside[k] != inside[(k + 1) % 3] && d[a] != 0 && d[b] != 0 { poly.append(cut(a, b)) }
            }
            guard poly.count >= 3 else { continue }
            for k in 1..<(poly.count - 1) { out.indices.append(contentsOf: [poly[0], poly[k], poly[k + 1]]) }
        }
        for e in stride(from: 0, to: mesh.featureEdges.count - 1, by: 2) {
            let a = Int(mesh.featureEdges[e]), b = Int(mesh.featureEdges[e + 1])
            switch (d[a] <= 0, d[b] <= 0) {
            case (true, true): out.featureEdges.append(contentsOf: [keep(a), keep(b)])
            case (true, false): if d[a] != 0 { out.featureEdges.append(contentsOf: [keep(a), cut(a, b)]) }
            case (false, true): if d[b] != 0 { out.featureEdges.append(contentsOf: [cut(a, b), keep(b)]) }
            case (false, false): break
            }
        }
        return out
    }
}
