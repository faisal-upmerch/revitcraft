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
    /// The centre of a curved edge (a tessellated arc or circle).
    case curveCenter
    /// The face under the pointer (face-hosted placement).
    case face
    /// S3D2: a quadrant point of a circle, arc or ellipse (its ends of axes).
    case curveQuadrant
    /// S3D2: where a line from the start point touches a curved edge.
    case curveTangent
    /// S3D2: two edges that cross only on screen, resolved onto the work plane (or the nearer edge).
    case apparentIntersection
}

/// S3D2: a line a query snaps to besides the scene's (datum traces on the work plane).
public struct Snap3DExtraLine: Sendable, Hashable {
    public var segment: Segment3
    public var id: ElementID
    public var category: Category
    public init(segment: Segment3, id: ElementID, category: Category) { self.segment = segment; self.id = id; self.category = category }
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
    /// S3D2: points that must be visible for the snap to count (an apparent intersection: where it is on both edges);
    /// nil: the point itself.
    public var visibilityPoints: [Vec3]? = nil

    /// Revit's order (SnapKind.priority), an apparent intersection just after true ones.
    public var rankPriority: Double { Double(kind.priority) + (feature == .apparentIntersection ? 0.5 : 0) }

    /// Rank in Revit's order: the snap kind's priority, then the distance from the pointer, then nearer the viewer.
    public func ranks(before o: Snap3DCandidate) -> Bool {
        (rankPriority, screenDistance, depth) < (o.rankPriority, o.screenDistance, o.depth)
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
    /// The work plane (edges piercing it snap as intersections; apparent intersections resolve onto it).
    public var workPlane: WorkPlaneFrame? = nil
    /// Elevation of a level work plane (sets `workPlane`).
    public var workPlaneZ: Double? {
        get { workPlane.flatMap { $0.isHorizontal ? $0.origin.z : nil } }
        set { workPlane = newValue.map { WorkPlaneFrame(origin: Vec3(0, 0, $0), u: .unitX, v: .unitY) } }
    }
    /// S3D2: apparent intersections resolve onto the work plane (drawing tools) or onto the nearer edge (face-hosted).
    public var apparentOntoNearerEdge = false
    /// S3D2: lines besides the scene's (traces of datums on the work plane).
    public var extraLines: [Snap3DExtraLine] = []
    /// S3D2: whether line elements (datums, model lines, 2D CAD) snap: false when the view doesn't draw them.
    public var includeLineElements = true
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
        /// S3D2: a line element (datum, model line, 2D CAD): edges only.
        var linesOnly = false
    }

    /// S3D2: a curved edge chain (arc, circle, ellipse or spline) in its plane.
    struct Curve3 {
        var points: [Vec3]
        var closed: Bool
        var normal: Vec3
        /// Centre and radius when it is a circle or circular arc.
        var circle: (center: Vec3, radius: Double, e1: Vec3, e2: Vec3)?
        var edge: Int
        var bounds: Box3
    }

    /// Extracted geometry of one element.
    final class Features {
        var edges: [Segment3] = []
        /// Per edge: whether each end is a corner. Facet points along a tessellated curve (two nearly collinear
        /// edges meeting) are not, so a curved wall's top edge offers nearest points, not dozens of endpoints.
        var corners: [(a: Bool, b: Bool)] = []
        /// Midpoints of edges made of several pieces (a straight edge split at a join, an arc by its length) and
        /// centres of curved edges, with the edge piece they lie on.
        var extras: [(p: Vec3, kind: SnapKind, feature: Snap3DFeature, edge: Int)] = []
        var extraTree = BoxTree()
        /// S3D2: curved chains, for tangents.
        var curves: [Curve3] = []
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
            return Entry(id: s.id, category: s.category, bounds: b, center: b.isEmpty ? .zero : b.center, radius: b.isEmpty ? 0 : b.diagonal / 2,
                         linesOnly: s.category != .pointClouds && s.meshes.allSatisfy { $0.indices.isEmpty })
        }
    }

    /// An index of model elements' 3D geometry (tests, and hosts without a built scene).
    /// With `view`, also the lines that 3D view draws (datums, model lines, 2D CAD; Lines3D) as it shows them.
    public convenience init(model: BIMModel, elements: [ElementID]? = nil, detail: DetailLevel = .medium, view: Element? = nil) {
        let ids = elements ?? model.allElements.filter { $0.category.isModel && !$0.isType && $0.ownerViewID == nil && ElementMeshes.hasModelGeometry($0) }.map(\.id)
        var sources = ids.compactMap { id -> Snap3DSource? in
            guard let e = model[id] else { return nil }
            let parts = GeometryCache.shared.parts(e, model, detail: detail).filter { !$0.mesh.isEmpty && $0.isVisibleIn3D }
            guard !parts.isEmpty else { return nil }
            func alpha(_ p: MeshPart) -> Double {
                p.color?.a ?? model[p.materialID]?.material.map { 1 - $0.transparency } ?? ElementMeshes.defaultColor(e.category).a
            }
            return Snap3DSource(id: id, category: e.category, meshes: parts.map(\.mesh), opaque: parts.map { alpha($0) > 0.98 })
        }
        if let view { // S3D2
            sources += Lines3D.items(model: model, view: view, resolver: VisibilityResolver(model: model, view: view)).map {
                Snap3DSource(id: $0.id, category: $0.category, meshes: [$0.mesh])
            }
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
        f.corners = cornerFlags(f.edges)
        (f.extras, f.curves) = chainPoints(f.edges, corners: f.corners)
        f.extraTree = BoxTree(boxes: f.extras.map { Box3(min: $0.p, max: $0.p) })
        f.edgeTree = BoxTree(boxes: f.edges.map { Box3(points: [$0.a, $0.b]) })
        f.triTree = BoxTree(boxes: stride(from: 0, to: f.tris.count, by: 3).map { Box3(points: [f.tris[$0], f.tris[$0 + 1], f.tris[$0 + 2]]) })
        return f
    }

    /// Which edge ends are corners: anything but a point where exactly two edges continue within 25° of straight.
    static func cornerFlags(_ edges: [Segment3]) -> [(a: Bool, b: Bool)] {
        var incident: [SIMD3<Int64>: [Vec3]] = [:]
        func key(_ v: Vec3) -> SIMD3<Int64> { SIMD3(Int64((v.x * 1e5).rounded()), Int64((v.y * 1e5).rounded()), Int64((v.z * 1e5).rounded())) }
        for e in edges {
            incident[key(e.a), default: []].append((e.b - e.a).normalized)
            incident[key(e.b), default: []].append((e.a - e.b).normalized)
        }
        let straight = -cos(25 * Double.pi / 180)
        func corner(_ v: Vec3) -> Bool {
            guard let d = incident[key(v)], d.count == 2 else { return true }
            return d[0].dot(d[1]) > straight
        }
        return edges.map { (corner($0.a), corner($0.b)) }
    }

    typealias Extra = (p: Vec3, kind: SnapKind, feature: Snap3DFeature, edge: Int)

    /// Chains of edges between corners: the midpoint of each chain of two or more pieces (by length), and for curved
    /// chains their centre and quadrant points (circles and arcs through their ends and middle; closed loops such as
    /// ellipses by their centroid and the ends of their axes), with the curves kept for tangent snaps.
    static func chainPoints(_ edges: [Segment3], corners: [(a: Bool, b: Bool)]) -> ([Extra], [Curve3]) {
        func key(_ v: Vec3) -> SIMD3<Int64> { SIMD3(Int64((v.x * 1e5).rounded()), Int64((v.y * 1e5).rounded()), Int64((v.z * 1e5).rounded())) }
        var at: [SIMD3<Int64>: [Int]] = [:]
        for (i, e) in edges.enumerated() { at[key(e.a), default: []].append(i); at[key(e.b), default: []].append(i) }
        var used = [Bool](repeating: false, count: edges.count)
        var out: [Extra] = []
        var curves: [Curve3] = []
        /// Walks from `start` along edge `first` through non-corner points; returns the points and edges passed.
        func walk(_ first: Int, from start: Vec3) -> (pts: [Vec3], ids: [Int]) {
            var pts = [start], ids: [Int] = []
            var cur = first, here = start
            while true {
                used[cur] = true
                ids.append(cur)
                let e = edges[cur]
                let atA = key(e.a) == key(here)
                let next = atA ? e.b : e.a
                pts.append(next)
                let nextIsCorner = atA ? corners[cur].b : corners[cur].a
                if nextIsCorner || key(next) == key(start) { break }
                guard let n = at[key(next)]?.first(where: { !used[$0] }) else { break }
                cur = n; here = next
                if ids.count > 4096 { break }
            }
            return (pts, ids)
        }
        func emit(_ pts: [Vec3], _ ids: [Int], closed: Bool) {
            guard ids.count >= 2 else { return }
            var lens: [Double] = [0]
            for k in 1..<pts.count { lens.append(lens[k - 1] + pts[k].distance(to: pts[k - 1])) }
            let total = lens.last ?? 0
            guard total > Tolerance.length else { return }
            let chord = pts.last!.distance(to: pts[0])
            let straight = !closed && chord >= total * (1 - 1e-6)
            var mid = pts[0], midEdge = ids[0]
            for k in 1..<pts.count where lens[k] >= total / 2 {
                let t = (total / 2 - lens[k - 1]) / max(lens[k] - lens[k - 1], 1e-12)
                mid = pts[k - 1].lerp(to: pts[k], t: t); midEdge = ids[k - 1]
                break
            }
            if !closed { out.append((mid, .midpoint, .edgeMidpoint, midEdge)) }
            guard !straight, pts.count >= 4 else { return }
            let ring = closed ? Array(pts.dropLast()) : pts
            // The chain's plane (Newell's normal); twisted chains (3D splines) get no centre, quadrants or tangents.
            var n = Vec3.zero
            for k in ring.indices {
                let a = ring[k], b = ring[(k + 1) % ring.count]
                n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
            }
            guard n.length > 1e-12 else { return }
            n = n.normalized
            let planeTol = max(1e-3, total * 1e-3)
            guard ring.allSatisfy({ abs(($0 - ring[0]).dot(n)) <= planeTol }) else { return }
            // Axes for quadrants: plan X and Y for flat curves; horizontal and up the plane otherwise.
            var e1 = abs(n.z) > 0.9 ? (Vec3.unitX - n * n.x) : n.cross(.unitZ)
            e1 = e1.normalized
            var e2 = n.cross(e1).normalized
            if abs(n.z) <= 0.9, e2.z < 0 { e2 = -e2 }
            if abs(n.z) > 0.9, e2.dot(.unitY) < 0 { e2 = -e2 }
            let bounds = Box3(points: pts)
            /// Distance from `q` to the chain.
            func offChain(_ q: Vec3) -> Double {
                var d = Double.infinity
                for k in 1..<pts.count {
                    let t = Intersect3D.segmentParameter(closestToLine: q, n, pts[k - 1], pts[k])
                    d = min(d, pts[k - 1].lerp(to: pts[k], t: t).distance(to: q))
                }
                return d
            }
            if closed {
                let c = ring.reduce(Vec3.zero, +) / Double(ring.count)
                let r = ring.map { $0.distance(to: c) }
                guard let lo = r.min(), let hi = r.max(), lo > Tolerance.length else { return }
                out.append((c, .center, .curveCenter, ids[0]))
                if hi - lo <= 0.05 * hi {
                    let rr = r.reduce(0, +) / Double(r.count)
                    for d in [e1, -e1, e2, -e2] { out.append((c + d * rr, .quadrant, .curveQuadrant, ids[0])) }
                    curves.append(Curve3(points: pts, closed: true, normal: n, circle: (c, rr, e1, e2), edge: ids[0], bounds: bounds))
                } else {
                    // An ellipse: the ends of its axes, from the spread of its points in the plane.
                    var sxx = 0.0, syy = 0.0, sxy = 0.0
                    for p in ring { let d = p - c; let x = d.dot(e1), y = d.dot(e2); sxx += x * x; syy += y * y; sxy += x * y }
                    let ang = 0.5 * atan2(2 * sxy, sxx - syy)
                    let a1 = e1 * cos(ang) + e2 * sin(ang), a2 = n.cross(a1)
                    for d in [a1, -a1, a2, -a2] {
                        if let best = ring.max(by: { ($0 - c).dot(d) < ($1 - c).dot(d) }) { out.append((best, .quadrant, .curveQuadrant, ids[0])) }
                    }
                    curves.append(Curve3(points: pts, closed: true, normal: n, circle: nil, edge: ids[0], bounds: bounds))
                }
            } else if let c = circumcenter(pts[0], mid, pts.last!) {
                let rr = pts[0].distance(to: c)
                let fits = pts.allSatisfy { abs($0.distance(to: c) - rr) <= max(0.02 * rr, 0.003) }
                if fits {
                    out.append((c, .center, .curveCenter, midEdge))
                    let tol = max(0.01 * rr, 0.002)
                    for d in [e1, -e1, e2, -e2] where offChain(c + d * rr) <= tol { out.append((c + d * rr, .quadrant, .curveQuadrant, midEdge)) }
                }
                curves.append(Curve3(points: pts, closed: false, normal: n, circle: fits ? (c, rr, e1, e2) : nil, edge: midEdge, bounds: bounds))
            } else {
                curves.append(Curve3(points: pts, closed: false, normal: n, circle: nil, edge: midEdge, bounds: bounds))
            }
        }
        for i in edges.indices where !used[i] && (corners[i].a || corners[i].b) {
            let (pts, ids) = walk(i, from: corners[i].a ? edges[i].a : edges[i].b)
            emit(pts, ids, closed: false)
        }
        for i in edges.indices where !used[i] {
            let (pts, ids) = walk(i, from: edges[i].a)
            emit(pts, ids, closed: key(pts.last!) == key(pts[0]))
        }
        return (out, curves)
    }

    /// S3D2: where lines from `from` touch a curve (in the curve's plane): exact for circles and arcs, else where the
    /// direction from the start point runs along the flattened curve.
    static func tangentPoints(from f: Vec3, to c: Curve3) -> [Vec3] {
        let n = c.normal
        let fp = f - n * (f - c.points[0]).dot(n)
        if let k = c.circle {
            let d = fp - k.center
            let x = d.dot(k.e1), y = d.dot(k.e2)
            let dist = (x * x + y * y).squareRoot()
            guard dist > k.radius * (1 + 1e-9) else { return [] }
            let base = atan2(y, x), a = acos(k.radius / dist)
            var pts = [base + a, base - a].map { k.center + k.e1 * (k.radius * cos($0)) + k.e2 * (k.radius * sin($0)) }
            if !c.closed {
                let tol = max(0.01 * k.radius, 0.002)
                pts = pts.filter { q in
                    (1..<c.points.count).contains { i in
                        let t = Intersect3D.segmentParameter(closestToLine: q, n, c.points[i - 1], c.points[i])
                        return c.points[i - 1].lerp(to: c.points[i], t: t).distance(to: q) <= tol
                    }
                }
            }
            return pts
        }
        // Flattened curve: the sign of (p − f′) × tangent changes where a line from f′ touches it.
        let p = c.points
        guard p.count >= 3 else { return [] }
        func tangent(_ i: Int) -> Vec3 {
            let a = i > 0 ? p[i - 1] : (c.closed ? p[p.count - 2] : p[i])
            let b = i < p.count - 1 ? p[i + 1] : (c.closed ? p[1] : p[i])
            return (b - a).normalized
        }
        func g(_ i: Int) -> Double { (p[i] - fp).cross(tangent(i)).dot(n) }
        var out: [Vec3] = []
        for i in 0..<(p.count - 1) {
            let a = g(i), b = g(i + 1)
            guard a * b < 0 else { continue }
            out.append(p[i].lerp(to: p[i + 1], t: a / (a - b)))
        }
        return out
    }

    /// Centre of the circle through three points; nil when they are (nearly) collinear.
    static func circumcenter(_ a: Vec3, _ b: Vec3, _ c: Vec3) -> Vec3? {
        let ab = b - a, ac = c - a
        let n = ab.cross(ac)
        let n2 = n.dot(n)
        guard n2 > 1e-14 * ab.lengthSquared * ac.lengthSquared else { return nil }
        return a + (n.cross(ab) * ac.lengthSquared + ac.cross(n) * ab.lengthSquared) / (2 * n2)
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
        guard !entries.isEmpty || !q.extraLines.isEmpty, q.radius > 0 else { return [] }
        let cam = q.camera, ptr = q.pointer, r = q.radius
        let ray = cam.ray(at: ptr)
        let near = nearElements(q)
        var raw: [Snap3DCandidate] = []
        var lines: [(seg: Segment3, id: ElementID, category: Category, d: Double, sa: Vec2, sb: Vec2)] = []
        var budget = 200_000

        func consider(_ p: Vec3, _ kind: SnapKind, _ feature: Snap3DFeature, _ ids: [ElementID], edge: Segment3? = nil, check: [Vec3]? = nil) {
            guard q.enabled.contains(kind) else { return }
            if let c = q.clip, !c.expanded(by: Tolerance.length * 10).contains(p) { return }
            guard let s = cam.project(p) else { return }
            let d = s.distance(to: ptr)
            guard d <= r else { return }
            raw.append(Snap3DCandidate(point: p, kind: kind, feature: feature, elementIDs: ids, screen: s, screenDistance: d, depth: cam.depth(of: p),
                                       edge: edge, visibilityPoints: check))
        }
        func nodeNear(_ b: Box3) -> Bool { cam.sphereMayCover(center: b.center, radius: b.diagonal / 2, pointer: ptr, within: r) }
        /// One edge: its corners, midpoint, nearest point, perpendicular foot and work-plane piercing.
        func visit(_ s: Segment3, corners c: (a: Bool, b: Bool), _ id: ElementID, _ category: Category) {
            guard let (ca, cb) = cam.clippedToNear(s.a, s.b), let pa = cam.project(ca), let pb = cam.project(cb) else { return }
            let ds = Segment2(pa, pb).distance(to: ptr)
            guard ds <= r else { return }
            lines.append((s, id, category, ds, pa, pb))
            if c.a { consider(s.a, .endpoint, .vertex, [id], edge: s) }
            if c.b { consider(s.b, .endpoint, .vertex, [id], edge: s) }
            if c.a && c.b { consider(s.midpoint, .midpoint, .edgeMidpoint, [id], edge: s) }
            let t = Intersect3D.segmentParameter(closestToLine: ray.origin, ray.direction, s.a, s.b)
            consider(s.a.lerp(to: s.b, t: t), .nearest, .edge, [id], edge: s)
            if let from = q.from {
                // Perpendicular in the work plane: the foot on the edge as the plane sees it (plan for levels).
                let f = q.workPlane ?? WorkPlaneFrame(origin: .zero, u: .unitX, v: .unitY)
                func local(_ p: Vec3) -> Vec2 { let d = p - f.origin; return Vec2(d.dot(f.u), d.dot(f.v)) }
                let a2 = local(s.a), u = local(s.b) - a2
                if u.lengthSquared > 1e-10 {
                    let tp = (local(from) - a2).dot(u) / u.lengthSquared
                    if tp > 1e-6, tp < 1 - 1e-6 { consider(s.a.lerp(to: s.b, t: tp), .perpendicular, .perpendicular, [id], edge: s) }
                }
            }
            if let f = q.workPlane {
                let n = f.normal
                let da = (s.a - f.origin).dot(n), db = (s.b - f.origin).dot(n)
                if da * db < 0, abs(da) > Tolerance.length, abs(db) > Tolerance.length {
                    consider(s.a.lerp(to: s.b, t: da / (da - db)), .intersection, .workPlaneIntersection, [id], edge: s)
                }
            }
        }

        for i in near {
            let e = entries[i]
            if e.linesOnly && !q.includeLineElements { continue }
            let f = features(i)
            f.edgeTree.visit(nodeNear) { k in
                budget -= 1
                guard budget > 0 else { return }
                visit(f.edges[k], corners: f.corners[k], e.id, e.category)
            }
            f.extraTree.visit(nodeNear) { k in
                let x = f.extras[k]
                consider(x.p, x.kind, x.feature, [e.id], edge: f.edges[x.edge])
            }
            if let from = q.from, q.enabled.contains(.tangent) {
                for c in f.curves where nodeNear(c.bounds) {
                    for p in Self.tangentPoints(from: from, to: c) { consider(p, .tangent, .curveTangent, [e.id], edge: f.edges[c.edge]) }
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
        for x in q.extraLines where !q.exclude.contains(x.id) { visit(x.segment, corners: (true, true), x.id, x.category) }

        // Edges crossing in space, away from shared corners; edges crossing only on screen (apparent intersections).
        let la = Array(lines.sorted { $0.d < $1.d }.prefix(60))
        if q.enabled.contains(.intersection) || q.enabled.contains(.gridIntersection) {
            for i in 0..<la.count {
                for j in (i + 1)..<la.count {
                    let a = la[i].seg, b = la[j].seg
                    let da = (a.b - a.a).normalized, db = (b.b - b.a).normalized
                    if da.cross(db).length < 1e-6 { continue } // collinear overlaps have no single crossing
                    var ids = [la[i].id]
                    if la[j].id != la[i].id { ids.append(la[j].id) }
                    let c = Intersect3D.closestPoints(a.a, a.b, b.a, b.b)
                    let tol = max(1e-4, cam.worldPerPoint(at: a.a.lerp(to: a.b, t: c.s)) * 0.05)
                    if c.gap <= tol {
                        let atCornerOfA = c.s < 1e-6 || c.s > 1 - 1e-6, atCornerOfB = c.t < 1e-6 || c.t > 1 - 1e-6
                        if atCornerOfA && atCornerOfB { continue }
                        let grids = la[i].category == .grids && la[j].category == .grids
                        consider(a.a.lerp(to: a.b, t: c.s), grids ? .gridIntersection : .intersection, .edgeIntersection, ids, edge: a)
                        continue
                    }
                    guard q.enabled.contains(.intersection), let x = Segment2(la[i].sa, la[i].sb).intersection(Segment2(la[j].sa, la[j].sb)),
                          x.distance(to: ptr) <= r else { continue }
                    // Apparent: where each edge shows at the crossing; the snap goes onto the work plane under it, or
                    // onto the nearer edge.
                    let sray = cam.ray(at: x)
                    let pa = a.a.lerp(to: a.b, t: Intersect3D.segmentParameter(closestToLine: sray.origin, sray.direction, a.a, a.b))
                    let pb = b.a.lerp(to: b.b, t: Intersect3D.segmentParameter(closestToLine: sray.origin, sray.direction, b.a, b.b))
                    let nearer = cam.depth(of: pa) <= cam.depth(of: pb) ? pa : pb
                    var p = nearer
                    if !q.apparentOntoNearerEdge, let f = q.workPlane {
                        let den = sray.direction.dot(f.normal)
                        if abs(den) > 1e-9 {
                            let t = (f.origin - sray.origin).dot(f.normal) / den
                            if t > 0 { p = sray.origin + sray.direction * t }
                        }
                    }
                    consider(p, .intersection, .apparentIntersection, ids, edge: cam.depth(of: pa) <= cam.depth(of: pb) ? a : b, check: [pa, pb])
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
            if q.occlusion, (c.visibilityPoints ?? [c.point]).contains(where: { isHidden($0, q, near: near) }) { rejected.append(c.point); continue }
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
