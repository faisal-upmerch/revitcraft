import Foundation
import ArcusGeometry
import ArcusDomain

// S3D: object snapping to model geometry in 3D views, as in Revit.
//
// A 3D view's scene (the meshes it draws, with their feature edges) is indexed per element. A query projects the
// candidates near the pointer with the current camera and keeps those within the snap distance on screen:
// vertices (endpoints), edge midpoints, real 3D crossings of edges, edges piercing the work plane, the foot of the
// perpendicular from the start point, the nearest point on an edge, points of point clouds and, for face-hosted
// tools, the face under the pointer. Candidates hidden behind opaque geometry are dropped (a CPU ray cast toward the
// viewer), so only what the user sees snaps. Linked models, imports and point clouds are part of the scene and snap too.
//
// Work-plane tools take the snapped point's projection onto the work plane, so a wall drawn on Level 1 can start
// under the top corner of a wall on Level 2. The plan's own snaps (location lines, grid crossings, alignment and
// extension tracking, parallel/perpendicular) keep working on the plane and compete in Revit's priority order.

/// What a 3D snap lies on.
public enum Snap3DFeature: String, Sendable, Hashable {
    /// A mesh corner (endpoint of a feature edge).
    case vertex
    case edgeMidpoint
    /// Two edges crossing in space (not at a shared corner).
    case edgeIntersection
    /// An edge piercing the work plane.
    case workPlaneIntersection
    /// Foot of the perpendicular from the start point, on the plan projection of an edge.
    case perpendicular
    /// Nearest point on an edge.
    case edge
    /// A point of a point cloud.
    case point
    /// The face under the pointer (face-hosted placement).
    case face
}

/// A snappable point found in a 3D view.
public struct Snap3DCandidate: Sendable, Hashable {
    public var point: Vec3
    public var kind: SnapKind
    public var feature: Snap3DFeature
    public var elementIDs: [ElementID]
    /// Where it shows on screen (view points) and how far that is from the pointer.
    public var screen: Vec2
    public var screenDistance: Double
    public var depth: Double
    /// The edge it lies on, when it lies on one.
    public var edge: Segment3?

    /// Rank in Revit's order: the snap kind's priority, then the distance from the pointer, then nearer the viewer.
    public func ranks(before o: Snap3DCandidate) -> Bool {
        (kind.priority, screenDistance, depth) < (o.kind.priority, o.screenDistance, o.depth)
    }
}

/// One element's geometry for the 3D snap index.
public struct Snap3DSource: Sendable {
    public var id: ElementID
    public var category: Category
    public var meshes: [Mesh]
    /// Per mesh: opaque surfaces hide what is behind them (glass, masses and ghosted parts do not).
    public var opaque: [Bool]
    public var bounds: Box3
    public init(id: ElementID, category: Category, meshes: [Mesh], opaque: [Bool]? = nil, bounds: Box3? = nil) {
        self.id = id; self.category = category; self.meshes = meshes
        self.opaque = opaque ?? Array(repeating: true, count: meshes.count)
        self.bounds = bounds ?? meshes.reduce(Box3.empty) { $0.union($1.bounds) }
    }
}

/// The parameters of one snap query.
public struct Snap3DQuery: Sendable {
    /// The pointer in view points (origin bottom-left).
    public var pointer: Vec2
    public var camera: ScreenProjection3D
    /// Snap distance in points.
    public var radius: Double = 10
    public var enabled: Set<SnapKind> = Set(SnapKind.allCases)
    /// Elements being moved or edited: they neither snap nor hide anything.
    public var exclude: Set<ElementID> = []
    /// The section box: only geometry inside it snaps and hides.
    public var clip: Box3? = nil
    /// Start point of what is being drawn (perpendicular snaps).
    public var from: Vec3? = nil
    /// Elevation of the work plane (edges piercing it snap as intersections).
    public var workPlaneZ: Double? = nil
    /// Wireframe and transparent styles show everything: nothing hides a snap.
    public var occlusion = true
    /// Most candidates returned (distinct points, best first).
    public var limit = 16
    public init(pointer: Vec2, camera: ScreenProjection3D) { self.pointer = pointer; self.camera = camera }
}

/// Snappable geometry of a 3D view, built from its scene. Construction only records element bounds; edges, corners
/// and triangles of an element are extracted (and split into a box tree when large) the first time a query reaches
/// it, so a 20k-element model indexes instantly and queries touch only what is near the pointer.
public final class Snap3DIndex {
    struct Entry {
        var id: ElementID
        var category: Category
        var bounds: Box3
        var center: Vec3
        var radius: Double
    }

    /// Extracted geometry of one element.
    final class Features {
        var edges: [Segment3] = []
        var edgeTree = BoxTree()
        /// Triangle corners, three per triangle, with whether each triangle hides what is behind it.
        var tris: [Vec3] = []
        var triOpaque: [Bool] = []
        var triTree = BoxTree()
        var points: [Vec3] = []
        var pointTree = BoxTree()
    }

    let sources: [Snap3DSource]
    let entries: [Entry]
    /// Elements touched by queries (cleared when it grows past `featureCacheLimit`).
    private var features: [Int: Features] = [:]
    static let featureCacheLimit = 4000
    /// Identifies what the index was built from (a scene revision), for cache checks by the host.
    public let revision: UInt64

    public init(sources: [Snap3DSource], revision: UInt64 = 0) {
        self.sources = sources
        self.revision = revision
        entries = sources.map { s in
            let b = s.bounds
            return Entry(id: s.id, category: s.category, bounds: b, center: b.isEmpty ? .zero : b.center, radius: b.isEmpty ? 0 : b.diagonal / 2)
        }
    }

    /// An index of model elements' 3D geometry (tests, and hosts without a built scene).
    public convenience init(model: BIMModel, elements: [ElementID]? = nil, detail: DetailLevel = .medium) {
        let ids = elements ?? model.allElements.filter { $0.category.isModel && !$0.isType && $0.ownerViewID == nil && ElementMeshes.hasModelGeometry($0) }.map(\.id)
        let sources = ids.compactMap { id -> Snap3DSource? in
            guard let e = model[id] else { return nil }
            let parts = GeometryCache.shared.parts(e, model, detail: detail).filter { !$0.mesh.isEmpty && $0.isVisibleIn3D }
            guard !parts.isEmpty else { return nil }
            func alpha(_ p: MeshPart) -> Double {
                p.color?.a ?? model[p.materialID]?.material.map { 1 - $0.transparency } ?? ElementMeshes.defaultColor(e.category).a
            }
            return Snap3DSource(id: id, category: e.category, meshes: parts.map(\.mesh), opaque: parts.map { alpha($0) > 0.98 })
        }
        self.init(sources: sources, revision: model.revision)
    }

    public var count: Int { entries.count }

    // MARK: Feature extraction

    func features(_ i: Int) -> Features {
        if let f = features[i] { return f }
        if features.count >= Self.featureCacheLimit { features.removeAll(keepingCapacity: true) }
        let f = Self.extract(sources[i])
        features[i] = f
        return f
    }

    static func extract(_ s: Snap3DSource) -> Features {
        let f = Features()
        if s.category == .pointClouds {
            // Point markers are small tetrahedra: their centres are the points.
            for m in s.meshes where m.positions.count % 4 == 0 {
                for k in stride(from: 0, to: m.positions.count, by: 4) {
                    f.points.append((m.positions[k] + m.positions[k + 1] + m.positions[k + 2] + m.positions[k + 3]) / 4)
                }
            }
            f.pointTree = BoxTree(boxes: f.points.map { Box3(min: $0, max: $0) })
            return f
        }
        var seen = Set<EdgeKey>()
        for (mi, m) in s.meshes.enumerated() {
            let n = m.positions.count
            var pairs = m.featureEdges
            if pairs.isEmpty && !m.indices.isEmpty { pairs = derivedFeatureEdges(m) }
            var k = 0
            while k + 1 < pairs.count {
                let a = Int(pairs[k]), b = Int(pairs[k + 1])
                k += 2
                guard a < n, b < n else { continue }
                let pa = m.positions[a], pb = m.positions[b]
                guard pa.distance(to: pb) > Tolerance.length, seen.insert(EdgeKey(pa, pb)).inserted else { continue }
                f.edges.append(Segment3(pa, pb))
            }
            let opaque = mi < s.opaque.count ? s.opaque[mi] : true
            var t = 0
            while t + 2 < m.indices.count {
                let a = Int(m.indices[t]), b = Int(m.indices[t + 1]), c = Int(m.indices[t + 2])
                t += 3
                guard a < n, b < n, c < n else { continue }
                f.tris += [m.positions[a], m.positions[b], m.positions[c]]
                f.triOpaque.append(opaque)
            }
        }
        f.edgeTree = BoxTree(boxes: f.edges.map { Box3(points: [$0.a, $0.b]) })
        f.triTree = BoxTree(boxes: stride(from: 0, to: f.tris.count, by: 3).map { Box3(points: [f.tris[$0], f.tris[$0 + 1], f.tris[$0 + 2]]) })
        return f
    }

    /// Edges of a mesh that has none recorded (some imported meshes): boundary edges and creases sharper than 25°.
    static func derivedFeatureEdges(_ m: Mesh) -> [UInt32] {
        var normals: [EdgeKey: (a: UInt32, b: UInt32, n: [Vec3])] = [:]
        var t = 0
        let n = m.positions.count
        while t + 2 < m.indices.count {
            let ids = [m.indices[t], m.indices[t + 1], m.indices[t + 2]]
            t += 3
            guard ids.allSatisfy({ Int($0) < n }) else { continue }
            let p = ids.map { m.positions[Int($0)] }
            let normal = (p[1] - p[0]).cross(p[2] - p[0]).normalized
            for e in 0..<3 {
                let a = ids[e], b = ids[(e + 1) % 3]
                let key = EdgeKey(m.positions[Int(a)], m.positions[Int(b)])
                normals[key, default: (a, b, [])].n.append(normal)
            }
        }
        let crease = cos(25 * Double.pi / 180)
        var out: [UInt32] = []
        for (_, v) in normals where v.n.count == 1 || v.n.count == 2 && v.n[0].dot(v.n[1]) < crease || v.n.count > 2 {
            out += [v.a, v.b]
        }
        return out
    }

    // MARK: Queries

    /// Elements whose bounds may show within the snap distance of the pointer, not excluded.
    func nearElements(_ q: Snap3DQuery) -> [Int] {
        var out: [Int] = []
        for (i, e) in entries.enumerated() where !e.bounds.isEmpty && !q.exclude.contains(e.id) {
            if let c = q.clip, !c.intersects(e.bounds) { continue }
            if q.camera.sphereMayCover(center: e.center, radius: e.radius, pointer: q.pointer, within: q.radius) { out.append(i) }
        }
        // Very dense views: the nearest elements are the ones that can be seen.
        if out.count > 600 {
            out.sort { q.camera.depth(of: entries[$0].center) - entries[$0].radius < q.camera.depth(of: entries[$1].center) - entries[$1].radius }
            out = Array(out.prefix(600))
        }
        return out
    }

    /// Visible snaps within the snap distance of the pointer, best first (Revit's order), one per distinct point.
    public func candidates(_ q: Snap3DQuery) -> [Snap3DCandidate] {
        guard !entries.isEmpty, q.radius > 0 else { return [] }
        let cam = q.camera, ptr = q.pointer, r = q.radius
        let ray = cam.ray(at: ptr)
        let near = nearElements(q)
        var raw: [Snap3DCandidate] = []
        var lines: [(seg: Segment3, id: ElementID, d: Double)] = []
        var budget = 200_000

        func consider(_ p: Vec3, _ kind: SnapKind, _ feature: Snap3DFeature, _ ids: [ElementID], edge: Segment3? = nil) {
            guard q.enabled.contains(kind) else { return }
            if let c = q.clip, !c.expanded(by: Tolerance.length * 10).contains(p) { return }
            guard let s = cam.project(p) else { return }
            let d = s.distance(to: ptr)
            guard d <= r else { return }
            raw.append(Snap3DCandidate(point: p, kind: kind, feature: feature, elementIDs: ids, screen: s, screenDistance: d, depth: cam.depth(of: p), edge: edge))
        }
        func nodeNear(_ b: Box3) -> Bool { cam.sphereMayCover(center: b.center, radius: b.diagonal / 2, pointer: ptr, within: r) }

        for i in near {
            let e = entries[i]
            let f = features(i)
            f.edgeTree.visit(nodeNear) { k in
                budget -= 1
                guard budget > 0 else { return }
                let s = f.edges[k]
                guard let (ca, cb) = cam.clippedToNear(s.a, s.b), let pa = cam.project(ca), let pb = cam.project(cb) else { return }
                let ds = Segment2(pa, pb).distance(to: ptr)
                guard ds <= r else { return }
                lines.append((s, e.id, ds))
                consider(s.a, .endpoint, .vertex, [e.id], edge: s)
                consider(s.b, .endpoint, .vertex, [e.id], edge: s)
                consider(s.midpoint, .midpoint, .edgeMidpoint, [e.id], edge: s)
                let t = Intersect3D.segmentParameter(closestToLine: ray.origin, ray.direction, s.a, s.b)
                consider(s.a.lerp(to: s.b, t: t), .nearest, .edge, [e.id], edge: s)
                if let from = q.from {
                    // Perpendicular on plan: the edge's plan projection seen from the start point.
                    let u = s.b.xy - s.a.xy
                    if u.lengthSquared > 1e-10 {
                        let tp = (from.xy - s.a.xy).dot(u) / u.lengthSquared
                        if tp > 1e-6, tp < 1 - 1e-6 { consider(s.a.lerp(to: s.b, t: tp), .perpendicular, .perpendicular, [e.id], edge: s) }
                    }
                }
                if let z = q.workPlaneZ, (s.a.z - z) * (s.b.z - z) < 0, abs(s.a.z - z) > Tolerance.length, abs(s.b.z - z) > Tolerance.length {
                    let tz = (z - s.a.z) / (s.b.z - s.a.z)
                    consider(s.a.lerp(to: s.b, t: tz), .intersection, .workPlaneIntersection, [e.id], edge: s)
                }
            }
            if !f.points.isEmpty {
                // A cloud: the front-most points under the pointer, the closest few.
                let before = raw.count
                f.pointTree.visit(nodeNear) { k in
                    budget -= 1
                    guard budget > 0 else { return }
                    consider(f.points[k], .endpoint, .point, [e.id])
                }
                let pts = Array(raw[before...])
                raw.removeSubrange(before...)
                if let front = pts.map(\.depth).min() {
                    let window = max(0.25, cam.worldPerPoint(atDepth: front) * r * 2)
                    raw += pts.filter { $0.depth <= front + window }.sorted { $0.screenDistance < $1.screenDistance }.prefix(3)
                }
            }
        }

        // Edges crossing in space, away from shared corners.
        let local = lines.sorted { $0.d < $1.d }.prefix(60)
        let la = Array(local)
        if q.enabled.contains(.intersection) {
            for i in 0..<la.count {
                for j in (i + 1)..<la.count {
                    let a = la[i].seg, b = la[j].seg
                    let c = Intersect3D.closestPoints(a.a, a.b, b.a, b.b)
                    let tol = max(1e-4, cam.worldPerPoint(at: a.a.lerp(to: a.b, t: c.s)) * 0.05)
                    guard c.gap <= tol else { continue }
                    let p = a.a.lerp(to: a.b, t: c.s)
                    let atCornerOfA = c.s < 1e-6 || c.s > 1 - 1e-6, atCornerOfB = c.t < 1e-6 || c.t > 1 - 1e-6
                    if atCornerOfA && atCornerOfB { continue }
                    // Collinear overlaps have no single crossing.
                    let da = (a.b - a.a).normalized, db = (b.b - b.a).normalized
                    if da.cross(db).length < 1e-6 { continue }
                    var ids = [la[i].id]
                    if la[j].id != la[i].id { ids.append(la[j].id) }
                    consider(p, .intersection, .edgeIntersection, ids, edge: a)
                }
            }
        }

        // Best first; one per point; only what is not hidden.
        raw.sort { $0.ranks(before: $1) }
        var out: [Snap3DCandidate] = []
        var rejected: [Vec3] = []
        for c in raw {
            guard out.count < q.limit else { break }
            if out.contains(where: { $0.point.distance(to: c.point) <= 1e-4 }) || rejected.contains(where: { $0.distance(to: c.point) <= 1e-4 }) { continue }
            if q.occlusion, isHidden(c.point, q, near: near) { rejected.append(c.point); continue }
            out.append(c)
        }
        return out
    }

    /// The best visible snap under the pointer.
    public func snap(_ q: Snap3DQuery) -> Snap3DCandidate? {
        var q1 = q
        q1.limit = 1
        return candidates(q1).first
    }

    /// True when opaque geometry lies between `p` and the viewer.
    func isHidden(_ p: Vec3, _ q: Snap3DQuery, near: [Int]) -> Bool {
        let (dir, dist) = q.camera.towardViewer(from: p)
        let eps = max(1e-4, q.camera.worldPerPoint(at: p) * 0.5)
        let o = p + dir * eps
        let tMax = dist.isFinite ? max(0, dist - eps) : 1e7
        guard tMax > 0 else { return false }
        for i in near {
            let f = features(i)
            if !Intersect3D.ray(o, dir, hits: entries[i].bounds.expanded(by: Tolerance.length), tMax: tMax) { continue }
            var hidden = false
            f.triTree.visit({ Intersect3D.ray(o, dir, hits: $0.expanded(by: Tolerance.length), tMax: tMax) }) { k in
                guard !hidden, f.triOpaque[k] else { return }
                let b = k * 3
                guard let t = Intersect3D.ray(o, dir, triangle: f.tris[b], f.tris[b + 1], f.tris[b + 2]), t > 0, t < tMax else { return }
                if let c = q.clip, !c.contains(o + dir * t) { return }
                hidden = true
            }
            if hidden { return true }
        }
        return false
    }

    /// The face under the pointer: the nearest surface the pointer ray meets (inside the section box).
    public func faceHit(_ q: Snap3DQuery) -> Snap3DCandidate? {
        let ray = q.camera.ray(at: q.pointer)
        var tight = q
        tight.radius = 1
        var best: (t: Double, id: ElementID)?
        for i in nearElements(tight) {
            let f = features(i)
            let tMax = best?.t ?? 1e7
            guard Intersect3D.ray(ray.origin, ray.direction, hits: entries[i].bounds.expanded(by: Tolerance.length), tMax: tMax) else { continue }
            f.triTree.visit({ Intersect3D.ray(ray.origin, ray.direction, hits: $0.expanded(by: Tolerance.length), tMax: best?.t ?? 1e7) }) { k in
                let b = k * 3
                guard let t = Intersect3D.ray(ray.origin, ray.direction, triangle: f.tris[b], f.tris[b + 1], f.tris[b + 2]), t > 0, t < (best?.t ?? .infinity) else { return }
                let p = ray.origin + ray.direction * t
                if q.camera.isPerspective, q.camera.depth(of: p) < q.camera.near { return }
                if let c = q.clip, !c.contains(p) { return }
                best = (t, entries[i].id)
            }
        }
        guard let best else { return nil }
        let p = ray.origin + ray.direction * best.t
        return Snap3DCandidate(point: p, kind: .nearest, feature: .face, elementIDs: [best.id], screen: q.pointer, screenDistance: 0,
                               depth: q.camera.depth(of: p), edge: nil)
    }
}

/// Order-independent key of an edge by its quantized end points (0.01 mm), for removing duplicate edges.
struct EdgeKey: Hashable {
    var a: SIMD3<Int64>, b: SIMD3<Int64>
    init(_ p: Vec3, _ q: Vec3) {
        func k(_ v: Vec3) -> SIMD3<Int64> { SIMD3(Int64((v.x * 1e5).rounded()), Int64((v.y * 1e5).rounded()), Int64((v.z * 1e5).rounded())) }
        let x = k(p), y = k(q)
        if (x.x, x.y, x.z) <= (y.x, y.y, y.z) { a = x; b = y } else { a = y; b = x }
    }
}

/// A bounding-box tree over items (leaves of up to 12), for culling the edges, points and triangles of large meshes.
struct BoxTree {
    struct Node { var box: Box3; var lo: Int; var hi: Int; var left = -1; var right = -1 }
    private(set) var nodes: [Node] = []
    private(set) var order: [Int] = []

    init() {}

    init(boxes: [Box3], leafSize: Int = 12) {
        guard !boxes.isEmpty else { return }
        order = Array(boxes.indices)
        let centers = boxes.map(\.center)
        nodes.reserveCapacity(boxes.count / max(leafSize / 2, 1) + 1)
        func build(_ lo: Int, _ hi: Int) -> Int {
            var box = Box3.empty
            var cb = Box3.empty
            for k in lo..<hi { box.include(boxes[order[k]]); cb.include(centers[order[k]]) }
            let me = nodes.count
            nodes.append(Node(box: box, lo: lo, hi: hi))
            guard hi - lo > leafSize else { return me }
            let s = cb.size
            let axis = s.x >= s.y && s.x >= s.z ? 0 : s.y >= s.z ? 1 : 2
            func key(_ i: Int) -> Double { axis == 0 ? centers[i].x : axis == 1 ? centers[i].y : centers[i].z }
            order[lo..<hi].sort { key($0) < key($1) }
            let mid = (lo + hi) / 2
            let l = build(lo, mid)
            let r = build(mid, hi)
            nodes[me].left = l
            nodes[me].right = r
            return me
        }
        _ = build(0, boxes.count)
    }

    /// Calls `leaf` with every item in a node `accept` passes (depth first).
    func visit(_ accept: (Box3) -> Bool, _ leaf: (Int) -> Void) {
        guard !nodes.isEmpty else { return }
        var stack = [0]
        while let n = stack.popLast() {
            let node = nodes[n]
            guard accept(node.box) else { continue }
            if node.left < 0 {
                for k in node.lo..<node.hi { leaf(order[k]) }
            } else {
                stack.append(node.right)
                stack.append(node.left)
            }
        }
    }
}
