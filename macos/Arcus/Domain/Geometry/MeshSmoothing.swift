import Foundation

// VIS: smooth shading for tessellated curves. Builders write flat faces (one normal per face); for display, faces that
// meet at less than the crease angle share averaged normals, so cylinders, round-overs and turned legs shade round,
// while real edges (box corners, cylinder rims) stay sharp. The seams between smoothed faces become silhouette
// candidates: the viewport draws one only where the surface turns away from the eye, as a hand drawing would.

/// A mesh prepared for smooth shading: welded vertices with smooth normals, the original feature edges, and the
/// silhouette candidates (seams inside smooth regions with the normals of the two faces that meet there).
public struct ShadedMesh: Sendable {
    public var mesh: Mesh
    /// Pairs of vertex indices into `mesh.positions`.
    public var silhouetteEdges: [UInt32]
    /// Two face normals per silhouette edge (the faces on either side).
    public var silhouetteNormals: [Vec3]

    public init(mesh: Mesh, silhouetteEdges: [UInt32] = [], silhouetteNormals: [Vec3] = []) {
        self.mesh = mesh; self.silhouetteEdges = silhouetteEdges; self.silhouetteNormals = silhouetteNormals
    }

    public var silhouetteCount: Int { silhouetteEdges.count / 2 }

    /// Moved by `offset` (normals unchanged).
    public func translated(_ offset: Vec3) -> ShadedMesh {
        var m = self
        m.mesh.positions = mesh.positions.map { $0 + offset }
        return m
    }
}

public enum MeshSmoothing {
    /// Faces meeting at less than this angle shade as one smooth surface (a 12-sided cylinder still reads round; a box
    /// corner or a 45° chamfer stays crisp).
    public static let creaseAngle = 35 * Double.pi / 180
    /// Quantization of positions when finding shared corners (m).
    static let weldTolerance = 5e-6

    /// The mesh with smooth normals across faces that meet at less than `creaseAngle`.
    public static func shade(_ m: Mesh, creaseAngle: Double = creaseAngle) -> ShadedMesh {
        let triCount = m.indices.count / 3
        let vCount = m.positions.count
        guard triCount > 0, vCount > 0 else { return ShadedMesh(mesh: m) }
        // Face normals and corner angles (weights).
        var faceN = [Vec3](repeating: .zero, count: triCount)
        var weights = [Double](repeating: 0, count: triCount * 3)
        for t in 0..<triCount {
            let ia = Int(m.indices[3 * t]), ib = Int(m.indices[3 * t + 1]), ic = Int(m.indices[3 * t + 2])
            guard ia < vCount, ib < vCount, ic < vCount else { continue }
            let a = m.positions[ia], b = m.positions[ib], c = m.positions[ic]
            let n = (b - a).cross(c - a)
            let l = n.length
            guard l > 1e-14 else { continue }
            faceN[t] = n / l
            weights[3 * t] = cornerAngle(a, b, c)
            weights[3 * t + 1] = cornerAngle(b, c, a)
            weights[3 * t + 2] = cornerAngle(c, a, b)
        }
        // Fast path: a mesh whose few face directions all meet at the crease or more (boxes, walls, slabs) can't smooth.
        let cosCreaseFast = cos(creaseAngle)
        var dirs: [Vec3] = []
        var fewDirections = true
        for n in faceN where n.lengthSquared > 0 {
            if dirs.contains(where: { $0.dot(n) > 0.999999 }) { continue }
            if dirs.count >= 24 || dirs.contains(where: { $0.dot(n) >= cosCreaseFast }) { fewDirections = false; break }
            dirs.append(n)
        }
        if fewDirections { return ShadedMesh(mesh: m) }
        // Position groups (corners at the same place).
        var groupOf = [Int32](repeating: -1, count: vCount)
        var keyToGroup: [SIMD3<Int64>: Int32] = [:]
        keyToGroup.reserveCapacity(vCount)
        let q = 1 / weldTolerance
        var groupCount = 0
        for v in 0..<vCount {
            let p = m.positions[v]
            let s = SIMD3<Double>(p.x * q, p.y * q, p.z * q)
            let key = SIMD3<Int64>(Int64(s.x.rounded()), Int64(s.y.rounded()), Int64(s.z.rounded()))
            if let g = keyToGroup[key] { groupOf[v] = g; continue }
            // Near a rounding boundary the same point can land in the next cell: look there too.
            var found: Int32?
            let f = s - SIMD3<Double>(Double(key.x), Double(key.y), Double(key.z))
            let near = SIMD3<Int64>(abs(f.x) > 0.45 ? (f.x > 0 ? 1 : -1) : 0, abs(f.y) > 0.45 ? (f.y > 0 ? 1 : -1) : 0, abs(f.z) > 0.45 ? (f.z > 0 ? 1 : -1) : 0)
            if near != .zero {
                for dx in [0, near.x] { for dy in [0, near.y] { for dz in [0, near.z] where found == nil && !(dx == 0 && dy == 0 && dz == 0) {
                    found = keyToGroup[key &+ SIMD3(dx, dy, dz)]
                } } }
            }
            let g = found ?? Int32(groupCount)
            if found == nil { groupCount += 1 }
            keyToGroup[key] = g
            groupOf[v] = g
        }
        // Corners per group (CSR).
        var start = [Int](repeating: 0, count: groupCount + 1)
        for c in 0..<(triCount * 3) where faceN[c / 3].lengthSquared > 0 {
            let v = Int(m.indices[c])
            if v < vCount { start[Int(groupOf[v]) + 1] += 1 }
        }
        for g in 0..<groupCount { start[g + 1] += start[g] }
        var fill = start
        var corners = [Int](repeating: 0, count: start[groupCount])
        for c in 0..<(triCount * 3) where faceN[c / 3].lengthSquared > 0 {
            let v = Int(m.indices[c])
            guard v < vCount else { continue }
            let g = Int(groupOf[v])
            corners[fill[g]] = c
            fill[g] += 1
        }
        let cosCrease = cos(creaseAngle)
        var out = Mesh()
        out.positions.reserveCapacity(vCount)
        out.normals.reserveCapacity(vCount)
        var outOfCorner = [UInt32](repeating: 0, count: triCount * 3)
        var outOfVertex = [Int32](repeating: -1, count: vCount)
        var anySmooth = false
        // Per group: cluster corners by face normal, smooth each cluster over its neighbours within the crease.
        var clusterN: [Vec3] = [], clusterSum: [Vec3] = [], clusterOut: [UInt32] = []
        var cornerCluster: [Int] = []
        for g in 0..<groupCount {
            let lo = start[g], hi = start[g + 1]
            guard hi > lo else { continue }
            clusterN.removeAll(keepingCapacity: true); clusterSum.removeAll(keepingCapacity: true)
            cornerCluster.removeAll(keepingCapacity: true)
            for k in lo..<hi {
                let c = corners[k]
                let n = faceN[c / 3]
                var found = -1
                for (j, cn) in clusterN.enumerated() where cn.dot(n) > 0.999999 { found = j; break }
                if found < 0 { found = clusterN.count; clusterN.append(n); clusterSum.append(.zero) }
                clusterSum[found] = clusterSum[found] + n * weights[c]
                cornerCluster.append(found)
            }
            clusterOut.removeAll(keepingCapacity: true)
            var groupNormals: [(Vec3, UInt32)] = []
            let pos = m.positions[Int(m.indices[corners[lo]])]
            for j in 0..<clusterN.count {
                var s = Vec3.zero
                var merged = 0
                for k in 0..<clusterN.count where clusterN[j].dot(clusterN[k]) >= cosCrease { s = s + clusterSum[k]; merged += 1 }
                if merged > 1 { anySmooth = true }
                let n = s.lengthSquared > 1e-24 ? s.normalized : clusterN[j]
                if let hit = groupNormals.first(where: { $0.0.dot(n) > 0.99999 }) {
                    clusterOut.append(hit.1)
                } else {
                    let idx = UInt32(out.positions.count)
                    out.positions.append(pos); out.normals.append(n)
                    groupNormals.append((n, idx))
                    clusterOut.append(idx)
                }
            }
            for (k, ci) in zip(lo..<hi, cornerCluster) {
                let c = corners[k]
                let o = clusterOut[ci]
                outOfCorner[c] = o
                let v = Int(m.indices[c])
                if outOfVertex[v] < 0 { outOfVertex[v] = Int32(o) }
            }
        }
        // A mesh with no smooth seams keeps its own vertices (no rewrite, no silhouettes).
        guard anySmooth else { return ShadedMesh(mesh: m) }
        out.indices.reserveCapacity(m.indices.count)
        for t in 0..<triCount where faceN[t].lengthSquared > 0 {
            out.indices.append(contentsOf: [outOfCorner[3 * t], outOfCorner[3 * t + 1], outOfCorner[3 * t + 2]])
        }
        // Vertices only edges use (lines with no faces) are kept as they are.
        func mapped(_ v: UInt32) -> UInt32 {
            let i = Int(v)
            guard i < vCount else { return 0 }
            if outOfVertex[i] >= 0 { return UInt32(outOfVertex[i]) }
            let idx = UInt32(out.positions.count)
            out.positions.append(m.positions[i])
            out.normals.append(i < m.normals.count ? m.normals[i] : .unitZ)
            outOfVertex[i] = Int32(idx)
            return idx
        }
        var featureKeys = Set<UInt64>(), featureOut = Set<UInt64>()
        out.featureEdges.reserveCapacity(m.featureEdges.count)
        for e in stride(from: 0, to: m.featureEdges.count - 1, by: 2) {
            let a = mapped(m.featureEdges[e]), b = mapped(m.featureEdges[e + 1])
            out.featureEdges.append(contentsOf: [a, b])
            featureKeys.insert(edgeKey(groupOf[Int(m.featureEdges[e])], groupOf[Int(m.featureEdges[e + 1])]))
            featureOut.insert(edgeKey(Int32(bitPattern: a), Int32(bitPattern: b)))
        }
        // Silhouette candidates: edges shared by two smoothed faces that are not coplanar.
        var open: [UInt64: Int] = [:]
        open.reserveCapacity(out.indices.count)
        var silE: [UInt32] = [], silN: [Vec3] = []
        var t2 = 0
        var outTri: [Int] = []
        outTri.reserveCapacity(triCount)
        for t in 0..<triCount where faceN[t].lengthSquared > 0 {
            outTri.append(t)
            for k in 0..<3 {
                let a = out.indices[3 * t2 + k], b = out.indices[3 * t2 + (k + 1) % 3]
                let key = edgeKey(Int32(bitPattern: a), Int32(bitPattern: b))
                if let other = open.removeValue(forKey: key) {
                    let n0 = faceN[other], n1 = faceN[t]
                    let d = n0.dot(n1)
                    guard d < 0.9999999, d >= cosCrease else { continue }
                    let ga = groupOf[Int(m.indices[3 * t + k])], gb = groupOf[Int(m.indices[3 * t + (k + 1) % 3])]
                    if featureKeys.contains(edgeKey(ga, gb)) { continue }
                    silE.append(contentsOf: [a, b]); silN.append(contentsOf: [n0, n1])
                } else {
                    open[key] = t
                }
            }
            t2 += 1
        }
        if !open.isEmpty { unpairedSilhouettes(out, outTri, faceN, open, featureOut, cosCrease, &silE, &silN) }
        return ShadedMesh(mesh: out, silhouetteEdges: silE, silhouetteNormals: silN)
    }

    /// Silhouette candidates for edges with no face across them in the topology (T-junctions and slivers that Boolean
    /// cuts leave): the face across is found by position, as the face touching the edge's midpoint from the other side.
    static func unpairedSilhouettes(_ out: Mesh, _ outTri: [Int], _ faceN: [Vec3], _ open: [UInt64: Int], _ featureOut: Set<UInt64>,
                                    _ cosCrease: Double, _ silE: inout [UInt32], _ silN: inout [Vec3]) {
        let b = out.bounds
        let diag = (b.max - b.min).length
        guard diag > 0 else { return }
        let h = max(diag / 32, 1e-4)
        func cell(_ p: Vec3) -> SIMD3<Int32> {
            SIMD3(Int32(((p.x - b.min.x) / h).rounded(.down)), Int32(((p.y - b.min.y) / h).rounded(.down)), Int32(((p.z - b.min.z) / h).rounded(.down)))
        }
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        var big: [Int32] = []
        func corners(_ i: Int) -> (Vec3, Vec3, Vec3) {
            (out.positions[Int(out.indices[3 * i])], out.positions[Int(out.indices[3 * i + 1])], out.positions[Int(out.indices[3 * i + 2])])
        }
        for i in 0..<outTri.count {
            let (p0, p1, p2) = corners(i)
            let lo = cell(Vec3(min(p0.x, p1.x, p2.x), min(p0.y, p1.y, p2.y), min(p0.z, p1.z, p2.z)))
            let hi = cell(Vec3(max(p0.x, p1.x, p2.x), max(p0.y, p1.y, p2.y), max(p0.z, p1.z, p2.z)))
            if Int(hi.x - lo.x + 1) * Int(hi.y - lo.y + 1) * Int(hi.z - lo.z + 1) > 512 { big.append(Int32(i)); continue }
            for x in lo.x...hi.x { for y in lo.y...hi.y { for z in lo.z...hi.z { grid[SIMD3(x, y, z), default: []].append(Int32(i)) } } }
        }
        var outIndexOf: [Int: Int] = [:]
        for (i, t) in outTri.enumerated() { outIndexOf[t] = i }
        let tol = 1e-5
        for (key, t) in open where !featureOut.contains(key) {
            let a = UInt32(truncatingIfNeeded: key >> 32), bb = UInt32(truncatingIfNeeded: key)
            let pa = out.positions[Int(a)], pb = out.positions[Int(bb)]
            let mid = (pa + pb) * 0.5
            let n0 = faceN[t]
            let own = outIndexOf[t] ?? -1
            var best: Vec3?
            for i in (grid[cell(mid)] ?? []) + big where Int(i) != own {
                let n1 = faceN[outTri[Int(i)]]
                let d = n0.dot(n1)
                guard d < 0.9999999, d >= cosCrease, d > (best.map { n0.dot($0) } ?? -2) else { continue }
                let (p0, p1, p2) = corners(Int(i))
                guard abs((mid - p0).dot(n1)) <= tol else { continue }
                func side(_ u: Vec3, _ v: Vec3) -> Bool {
                    let e = v - u
                    let l = e.length
                    return l <= 0 || e.cross(mid - u).dot(n1) / l >= -tol
                }
                if side(p0, p1), side(p1, p2), side(p2, p0) { best = n1 }
            }
            if let n1 = best { silE.append(contentsOf: [a, bb]); silN.append(contentsOf: [n0, n1]) }
        }
    }

    /// The mesh without feature edges that lie inside a smooth or flat surface: an edge is kept only where the faces
    /// touching its midpoint meet at `creaseAngle` or more (or it bounds a single face). Boolean results need this: the
    /// BSP leaves slivers and T-junctions along cut curves, so their edges can't find their neighbours by topology.
    public static func droppingSmoothEdges(_ m: Mesh, creaseAngle: Double = .pi / 8) -> Mesh {
        guard !m.featureEdges.isEmpty, !m.indices.isEmpty else { return m }
        let b = m.bounds
        let diag = (b.max - b.min).length
        guard diag > 0 else { return m }
        let h = max(diag / 48, 1e-4)
        func cell(_ p: Vec3) -> SIMD3<Int32> {
            SIMD3(Int32(((p.x - b.min.x) / h).rounded(.down)), Int32(((p.y - b.min.y) / h).rounded(.down)), Int32(((p.z - b.min.z) / h).rounded(.down)))
        }
        let triCount = m.indices.count / 3
        var normals = [Vec3](repeating: .zero, count: triCount)
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        var big: [Int32] = []
        for t in 0..<triCount {
            let a = m.positions[Int(m.indices[3 * t])], bb = m.positions[Int(m.indices[3 * t + 1])], c = m.positions[Int(m.indices[3 * t + 2])]
            let n = (bb - a).cross(c - a)
            guard n.length > 1e-16 else { continue }
            normals[t] = n.normalized
            let lo = cell(Vec3(min(a.x, bb.x, c.x), min(a.y, bb.y, c.y), min(a.z, bb.z, c.z)))
            let hi = cell(Vec3(max(a.x, bb.x, c.x), max(a.y, bb.y, c.y), max(a.z, bb.z, c.z)))
            let span = Int(hi.x - lo.x + 1) * Int(hi.y - lo.y + 1) * Int(hi.z - lo.z + 1)
            if span > 512 { big.append(Int32(t)); continue }
            for x in lo.x...hi.x { for y in lo.y...hi.y { for z in lo.z...hi.z { grid[SIMD3(x, y, z), default: []].append(Int32(t)) } } }
        }
        let cosCrease = cos(creaseAngle)
        let tol = 1e-6
        var out = m
        out.featureEdges = []
        out.featureEdges.reserveCapacity(m.featureEdges.count)
        var touching: [Vec3] = []
        for e in stride(from: 0, to: m.featureEdges.count - 1, by: 2) {
            let pa = m.positions[Int(m.featureEdges[e])], pb = m.positions[Int(m.featureEdges[e + 1])]
            let mid = (pa + pb) * 0.5
            touching.removeAll(keepingCapacity: true)
            for t in (grid[cell(mid)] ?? []) + big {
                let n = normals[Int(t)]
                guard n.lengthSquared > 0 else { continue }
                let a = m.positions[Int(m.indices[3 * Int(t)])], bb = m.positions[Int(m.indices[3 * Int(t) + 1])], c = m.positions[Int(m.indices[3 * Int(t) + 2])]
                guard abs((mid - a).dot(n)) <= tol else { continue }
                // Inside or on the boundary (within tol of each edge's line).
                func side(_ u: Vec3, _ v: Vec3) -> Bool {
                    let d = v - u
                    let l = d.length
                    return l <= 0 || d.cross(mid - u).dot(n) / l >= -tol
                }
                guard side(a, bb), side(bb, c), side(c, a) else { continue }
                touching.append(n)
            }
            var keep = touching.count < 2
            if !keep {
                outer: for i in 0..<touching.count {
                    for j in (i + 1)..<touching.count where touching[i].dot(touching[j]) < cosCrease { keep = true; break outer }
                }
            }
            if keep { out.featureEdges.append(contentsOf: [m.featureEdges[e], m.featureEdges[e + 1]]) }
        }
        return out
    }

    /// The mesh with its T-junctions closed: a triangle with another triangle's corner lying on one of its edges is
    /// split (a fan from its centre through every such corner), so neighbours share vertices and smooth shading and
    /// silhouettes run across Boolean cuts. Positions keep their indices (feature edges stay valid); new ones are added.
    public static func fixingTJunctions(_ m: Mesh, tolerance tol: Double = 1e-5) -> Mesh {
        let triCount = m.indices.count / 3
        guard triCount > 0 else { return m }
        let b = m.bounds
        let diag = (b.max - b.min).length
        guard diag > 0 else { return m }
        let h = max(diag / 32, 1e-4)
        func cell(_ p: Vec3) -> SIMD3<Int32> {
            SIMD3(Int32(((p.x - b.min.x) / h).rounded(.down)), Int32(((p.y - b.min.y) / h).rounded(.down)), Int32(((p.z - b.min.z) / h).rounded(.down)))
        }
        // Distinct corner positions in a grid.
        var grid: [SIMD3<Int32>: [Int]] = [:]
        var seen = Set<SIMD3<Int64>>()
        let q = 1 / max(tol, 1e-9)
        for v in Set(m.indices.map { Int($0) }) where v < m.positions.count {
            let p = m.positions[v]
            guard seen.insert(SIMD3(Int64((p.x * q).rounded()), Int64((p.y * q).rounded()), Int64((p.z * q).rounded()))).inserted else { continue }
            grid[cell(p), default: []].append(v)
        }
        /// Corners strictly inside segment a–b (within `tol` of it), ordered from a.
        func onEdge(_ a: Vec3, _ bb: Vec3) -> [Vec3] {
            let d = bb - a
            let len = d.length
            guard len > 4 * tol else { return [] }
            let u = d / len
            let lo = cell(Vec3(min(a.x, bb.x) - tol, min(a.y, bb.y) - tol, min(a.z, bb.z) - tol))
            let hi = cell(Vec3(max(a.x, bb.x) + tol, max(a.y, bb.y) + tol, max(a.z, bb.z) + tol))
            var hits: [(Double, Vec3)] = []
            var visited = 0
            for x in lo.x...hi.x { for y in lo.y...hi.y { for z in lo.z...hi.z {
                visited += 1
                guard visited <= 4096 else { continue }
                // Only cells the segment passes near.
                let cc = Vec3(b.min.x + (Double(x) + 0.5) * h, b.min.y + (Double(y) + 0.5) * h, b.min.z + (Double(z) + 0.5) * h)
                let t0 = max(0, min(len, (cc - a).dot(u)))
                guard (a + u * t0 - cc).length <= h * 0.9 else { continue }
                for v in grid[SIMD3(x, y, z)] ?? [] {
                    let p = m.positions[v]
                    let t = (p - a).dot(u)
                    guard t > 2 * tol, t < len - 2 * tol else { continue }
                    if (a + u * t - p).length <= tol { hits.append((t, p)) }
                }
            } } }
            return hits.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // Only edges with no twin (by position) can carry a T-junction: find those first.
        func key(_ v: UInt32) -> SIMD3<Int64> {
            let p = m.positions[Int(v)]
            return SIMD3(Int64((p.x * q).rounded()), Int64((p.y * q).rounded()), Int64((p.z * q).rounded()))
        }
        var ids: [SIMD3<Int64>: Int32] = [:]
        let vid = m.indices.map { v -> Int32 in
            let k = key(v)
            if let i = ids[k] { return i }
            let i = Int32(ids.count); ids[k] = i; return i
        }
        var edgeCount: [UInt64: Int] = [:]
        for t in 0..<triCount { for k in 0..<3 { edgeCount[edgeKey(vid[3 * t + k], vid[3 * t + (k + 1) % 3]), default: 0] += 1 } }
        func open(_ t: Int, _ k: Int) -> Bool { edgeCount[edgeKey(vid[3 * t + k], vid[3 * t + (k + 1) % 3])] == 1 }
        var out = m
        out.indices = []
        out.indices.reserveCapacity(m.indices.count)
        var changed = false
        for t in 0..<triCount {
            let ia = m.indices[3 * t], ib = m.indices[3 * t + 1], ic = m.indices[3 * t + 2]
            let a = m.positions[Int(ia)], bb = m.positions[Int(ib)], c = m.positions[Int(ic)]
            let e0 = open(t, 0) ? onEdge(a, bb) : [], e1 = open(t, 1) ? onEdge(bb, c) : [], e2 = open(t, 2) ? onEdge(c, a) : []
            if e0.isEmpty && e1.isEmpty && e2.isEmpty { out.indices.append(contentsOf: [ia, ib, ic]); continue }
            changed = true
            let n = Int(ia) < m.normals.count ? m.normals[Int(ia)] : (bb - a).cross(c - a).normalized
            var ring: [UInt32] = []
            func add(_ p: Vec3) -> UInt32 {
                out.positions.append(p)
                if !out.normals.isEmpty || !m.normals.isEmpty { out.normals.append(n) }
                return UInt32(out.positions.count - 1)
            }
            ring.append(ia); ring += e0.map(add)
            ring.append(ib); ring += e1.map(add)
            ring.append(ic); ring += e2.map(add)
            let centre = add((a + bb + c) / 3)
            for k in 0..<ring.count { out.indices.append(contentsOf: [centre, ring[k], ring[(k + 1) % ring.count]]) }
        }
        return changed ? out : m
    }

    static func edgeKey(_ a: Int32, _ b: Int32) -> UInt64 {
        let lo = UInt32(bitPattern: min(a, b)), hi = UInt32(bitPattern: max(a, b))
        return UInt64(lo) << 32 | UInt64(hi)
    }

    /// Interior angle at `a` of triangle (a, b, c).
    static func cornerAngle(_ a: Vec3, _ b: Vec3, _ c: Vec3) -> Double {
        let u = b - a, v = c - a
        let lu = u.length, lv = v.length
        guard lu > 0, lv > 0 else { return 0 }
        return acos(max(-1, min(1, u.dot(v) / (lu * lv))))
    }
}

extension Mesh {
    /// VIS: this mesh prepared for smooth shading (see `MeshSmoothing`).
    public func smoothShaded(creaseAngle: Double = MeshSmoothing.creaseAngle) -> ShadedMesh {
        MeshSmoothing.shade(self, creaseAngle: creaseAngle)
    }
}
