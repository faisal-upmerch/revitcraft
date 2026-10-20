import Foundation

// F1415: constructive solid geometry on closed triangle meshes with BSP trees, after Evan Wallace's csg.js and RevitCraft's
// `crates/rc-core/src/csg.rs`. Family voids of every form (extrusion, blend, revolve, sweep, swept blend) cut solids with it.
// The trees are built and walked with explicit stacks, so deep trees never exhaust a secondary thread's stack.

/// A solid as a soup of convex planar polygons, with Boolean operations.
public struct MeshCSG: Sendable {
    /// Split tolerance in metres (RevitCraft: 1e-3 mm).
    static let epsilon = 1e-6

    struct Plane: Sendable {
        var normal: Vec3
        var w: Double
        init?(_ a: Vec3, _ b: Vec3, _ c: Vec3) {
            let n = (b - a).cross(c - a)
            let len = n.length
            guard len > 1e-12 else { return nil }
            normal = n / len
            w = normal.dot(a)
        }
        mutating func flip() { normal = -normal; w = -w }
        func distance(_ p: Vec3) -> Double { normal.dot(p) - w }
    }

    public struct Polygon: Sendable {
        public var vertices: [Vec3]
        var plane: Plane
        init?(_ vertices: [Vec3]) {
            guard vertices.count >= 3 else { return nil }
            for i in 0..<(vertices.count - 2) {
                if let p = Plane(vertices[0], vertices[i + 1], vertices[i + 2]) { self.vertices = vertices; plane = p; return }
            }
            return nil
        }
        mutating func flip() { vertices.reverse(); plane.flip() }
        public var normal: Vec3 { plane.normal }
    }

    public var polygons: [Polygon]

    public init(polygons: [Polygon] = []) { self.polygons = polygons }

    /// The triangles of a closed mesh as a solid.
    public init(mesh: Mesh) {
        var out: [Polygon] = []
        out.reserveCapacity(mesh.indices.count / 3)
        for i in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])], c = mesh.positions[Int(mesh.indices[i + 2])]
            if let p = Polygon([a, b, c]) { out.append(p) }
        }
        polygons = out
    }

    public var isEmpty: Bool { polygons.isEmpty }

    /// Enclosed volume (positive for outward-facing solids).
    public var volume: Double {
        var v = 0.0
        for p in polygons {
            for i in 1..<(p.vertices.count - 1) { v += p.vertices[0].dot(p.vertices[i].cross(p.vertices[i + 1])) }
        }
        return v / 6
    }

    public var bounds: Box3 { Box3(points: polygons.lazy.flatMap(\.vertices)) }

    // MARK: Booleans

    /// This solid with `other` removed.
    public func subtracting(_ other: MeshCSG) -> MeshCSG {
        guard !polygons.isEmpty, !other.polygons.isEmpty else { return self }
        guard bounds.intersects(other.bounds) else { return self }
        let a = Node(polygons), b = Node(other.polygons)
        a.invert()
        a.clip(to: b)
        b.clip(to: a)
        b.invert()
        b.clip(to: a)
        b.invert()
        a.build(b.allPolygons())
        a.invert()
        return MeshCSG(polygons: a.allPolygons())
    }

    public func union(_ other: MeshCSG) -> MeshCSG {
        guard !polygons.isEmpty else { return other }
        guard !other.polygons.isEmpty else { return self }
        let a = Node(polygons), b = Node(other.polygons)
        a.clip(to: b)
        b.clip(to: a)
        b.invert()
        b.clip(to: a)
        b.invert()
        a.build(b.allPolygons())
        return MeshCSG(polygons: a.allPolygons())
    }

    public func intersecting(_ other: MeshCSG) -> MeshCSG {
        guard !polygons.isEmpty, !other.polygons.isEmpty, bounds.intersects(other.bounds) else { return MeshCSG() }
        let a = Node(polygons), b = Node(other.polygons)
        a.invert()
        b.clip(to: a)
        b.invert()
        a.clip(to: b)
        b.clip(to: a)
        a.build(b.allPolygons())
        a.invert()
        return MeshCSG(polygons: a.allPolygons())
    }

    // MARK: Splitting

    /// Sorts `poly` against `plane` into the four lists (coplanar polygons by facing), splitting spanning polygons.
    static func split(_ poly: Polygon, by plane: Plane, coFront: inout [Polygon], coBack: inout [Polygon], front: inout [Polygon], back: inout [Polygon]) {
        let eps = epsilon
        var kinds = [UInt8](repeating: 0, count: poly.vertices.count)
        var all: UInt8 = 0
        for (i, v) in poly.vertices.enumerated() {
            let t = plane.distance(v)
            let k: UInt8 = t < -eps ? 2 : t > eps ? 1 : 0
            kinds[i] = k
            all |= k
        }
        switch all {
        case 0: if plane.normal.dot(poly.plane.normal) > 0 { coFront.append(poly) } else { coBack.append(poly) }
        case 1: front.append(poly)
        case 2: back.append(poly)
        default:
            var f: [Vec3] = [], b: [Vec3] = []
            let n = poly.vertices.count
            for i in 0..<n {
                let j = (i + 1) % n
                let ti = kinds[i], tj = kinds[j]
                let vi = poly.vertices[i], vj = poly.vertices[j]
                if ti != 2 { f.append(vi) }
                if ti != 1 { b.append(vi) }
                if (ti | tj) == 3 {
                    let t = (plane.w - plane.normal.dot(vi)) / plane.normal.dot(vj - vi)
                    let v = vi.lerp(to: vj, t: t)
                    f.append(v); b.append(v)
                }
            }
            if var p = Polygon(f) { p.plane = poly.plane; front.append(p) }
            if var p = Polygon(b) { p.plane = poly.plane; back.append(p) }
        }
    }

    /// A BSP tree node. A reference type so the iterative walks can rewire children in place.
    final class Node {
        var plane: Plane?
        var front: Node?
        var back: Node?
        var polygons: [Polygon] = []

        init(_ polys: [Polygon] = []) { build(polys) }

        /// Every node of the tree (pre-order).
        func nodes() -> [Node] {
            var out: [Node] = [], stack: [Node] = [self]
            while let n = stack.popLast() {
                out.append(n)
                if let f = n.front { stack.append(f) }
                if let b = n.back { stack.append(b) }
            }
            return out
        }

        func invert() {
            for n in nodes() {
                for i in n.polygons.indices { n.polygons[i].flip() }
                n.plane?.flip()
                swap(&n.front, &n.back)
            }
        }

        /// The parts of `polys` outside this tree's solid.
        func clipPolygons(_ polys: [Polygon]) -> [Polygon] {
            var out: [Polygon] = []
            var stack: [(Node, [Polygon])] = [(self, polys)]
            while let (n, ps) = stack.popLast() {
                guard let plane = n.plane else { out += ps; continue }
                var f: [Polygon] = [], b: [Polygon] = [], cf: [Polygon] = [], cb: [Polygon] = []
                for p in ps { MeshCSG.split(p, by: plane, coFront: &cf, coBack: &cb, front: &f, back: &b) }
                f += cf; b += cb
                if !f.isEmpty { if let nf = n.front { stack.append((nf, f)) } else { out += f } }
                if !b.isEmpty, let nb = n.back { stack.append((nb, b)) }
            }
            return out
        }

        /// Removes the parts of this tree's polygons inside `other`.
        func clip(to other: Node) {
            for n in nodes() { n.polygons = other.clipPolygons(n.polygons) }
        }

        func allPolygons() -> [Polygon] { nodes().flatMap(\.polygons) }

        func build(_ polys: [Polygon]) {
            var stack: [(Node, [Polygon])] = [(self, polys)]
            while let (n, ps) = stack.popLast() {
                guard let first = ps.first else { continue }
                if n.plane == nil { n.plane = first.plane }
                let plane = n.plane!
                var f: [Polygon] = [], b: [Polygon] = [], cf: [Polygon] = [], cb: [Polygon] = []
                for p in ps { MeshCSG.split(p, by: plane, coFront: &cf, coBack: &cb, front: &f, back: &b) }
                n.polygons += cf + cb
                if !f.isEmpty {
                    if n.front == nil { n.front = Node() }
                    stack.append((n.front!, f))
                }
                if !b.isEmpty {
                    if n.back == nil { n.back = Node() }
                    stack.append((n.back!, b))
                }
            }
        }
    }

    // MARK: Back to a mesh

    /// A renderable mesh: flat normals per face, and feature edges where faces meet at more than `creaseAngle` (edges between
    /// coplanar fragments of one face, which the BSP splits leave behind, are not drawn).
    public func mesh(creaseAngle: Double = .pi / 8) -> Mesh {
        var m = Mesh()
        guard !polygons.isEmpty else { return m }
        // Coplanar groups.
        struct Key: Hashable { var nx: Int, ny: Int, nz: Int, w: Int }
        func key(_ p: Plane) -> Key {
            Key(nx: Int((p.normal.x * 1e4).rounded()), ny: Int((p.normal.y * 1e4).rounded()), nz: Int((p.normal.z * 1e4).rounded()), w: Int((p.w * 1e5).rounded()))
        }
        var groupOf: [Int] = []
        var groups: [[Int]] = []
        var groupPlane: [Plane] = []
        var index: [Key: Int] = [:]
        for (i, p) in polygons.enumerated() {
            let k = key(p.plane)
            if let g = index[k] { groupOf.append(g); groups[g].append(i) } else {
                index[k] = groups.count; groupOf.append(groups.count); groups.append([i]); groupPlane.append(p.plane)
            }
        }
        let boxes = polygons.map { Box3(points: $0.vertices) }
        let eps = 1e-6, probe = 2e-5
        func contains(_ p: Polygon, _ q: Vec3) -> Bool {
            guard abs(p.plane.distance(q)) <= eps * 10 else { return false }
            let n = p.vertices.count
            for i in 0..<n {
                let a = p.vertices[i], b = p.vertices[(i + 1) % n]
                // VIS: a point on the edge itself is inside (within 0.1 µm), so neighbours across a shared edge are found
                // however the BSP rounded their vertices.
                if (b - a).cross(q - a).dot(p.plane.normal) < -1e-7 * max((b - a).length, 1e-9) { return false }
            }
            return true
        }
        func near(_ box: Box3, _ q: Vec3) -> Bool {
            q.x >= box.min.x - 1e-5 && q.x <= box.max.x + 1e-5 && q.y >= box.min.y - 1e-5 && q.y <= box.max.y + 1e-5
                && q.z >= box.min.z - 1e-5 && q.z <= box.max.z + 1e-5
        }
        let cosCrease = cos(creaseAngle)
        for (pi, p) in polygons.enumerated() {
            let base = UInt32(m.positions.count)
            m.positions += p.vertices
            m.normals += Array(repeating: p.plane.normal, count: p.vertices.count)
            for i in 1..<(p.vertices.count - 1) { m.indices += [base, base + UInt32(i), base + UInt32(i + 1)] }
            let g = groupOf[pi]
            let n = p.vertices.count
            for i in 0..<n {
                let a = p.vertices[i], b = p.vertices[(i + 1) % n]
                let e = b - a
                guard e.length > eps else { continue }
                let mid = (a + b) * 0.5
                // Outward in the face's plane, away from its interior.
                let out = e.cross(p.plane.normal).normalized
                let q = mid + out * probe
                // Interior to the face: a coplanar fragment lies across the edge.
                if groups[g].contains(where: { $0 != pi && near(boxes[$0], q) && contains(polygons[$0], q) }) { continue }
                // The face across the edge: a polygon of another plane through both ends that touches the midpoint.
                var neighbour: Int?
                for (gi, plane) in groupPlane.enumerated() where gi != g && abs(plane.distance(a)) <= eps * 10 && abs(plane.distance(b)) <= eps * 10 {
                    if let k = groups[gi].first(where: { near(boxes[$0], mid) && contains(polygons[$0], mid) }) { neighbour = k; break }
                }
                if let k = neighbour {
                    // Emitted once per edge, by the side with the lower group index.
                    guard g < groupOf[k] else { continue }
                    if p.plane.normal.dot(polygons[k].plane.normal) > cosCrease { continue }
                }
                m.featureEdges += [base + UInt32(i), base + UInt32((i + 1) % n)]
            }
        }
        return m
    }
}
