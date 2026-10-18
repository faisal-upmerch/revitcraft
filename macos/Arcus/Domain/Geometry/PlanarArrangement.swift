import Foundation

/// A bounded face of a planar arrangement.
public struct ArrangementFace: Sendable {
    /// Outer boundary, counter-clockwise.
    public var outer: Polygon2
    /// Islands lying inside the face, clockwise.
    public var holes: [Polygon2]
    /// Net area (outer minus holes).
    public var area: Double
    /// The face as a profile (outer CCW, holes CW).
    public var profile: Profile2

    public init(outer: Polygon2, holes: [Polygon2]) {
        self.outer = outer
        self.holes = holes
        self.area = outer.area - holes.reduce(0) { $0 + $1.area }
        self.profile = Profile2(outer: outer, holes: holes)
    }
}

/// Planar subdivision induced by a set of segments.
///
/// Construction:
/// 1. Endpoints are welded within `snapTolerance` (first occurrence wins).
/// 2. Pairwise intersections (found through a uniform grid) become vertices too.
/// 3. Every vertex lying within `snapTolerance` of a segment splits it, which also
///    handles T-junctions and collinear overlaps; identical pieces are merged.
/// 4. A half-edge structure is traced with faces on the left. Dead-end chains
///    (degree-1 vertices) and bridges (edges with the same face on both sides) are
///    pruned so they never appear in face boundaries.
/// 5. Counter-clockwise cycles are bounded faces; each connected component's outer
///    (clockwise) cycle becomes a hole of the smallest face that contains it.
///
/// All ordering is derived from input order, so results are deterministic.
public struct PlanarArrangement: Sendable {
    public let snapTolerance: Double
    /// Welded vertices.
    public private(set) var vertices: [Vec2] = []
    /// All unique split edges (including pruned dead ends), as vertex index pairs.
    public private(set) var edgeVertices: [EdgeIndex] = []
    /// Bounded faces.
    public private(set) var faces: [ArrangementFace] = []
    /// Face index for each half-edge (`2e`: first→second vertex, `2e+1`: reverse), -1 for
    /// the unbounded region and -2 for pruned (dangling or bridge) edges.
    private(set) var halfEdgeFace: [Int] = []
    private var faceGrid = SpatialGrid<Int>(cellSize: 1)

    /// A pair of vertex indices.
    public struct EdgeIndex: Hashable, Sendable {
        public var a: Int
        public var b: Int
    }

    /// Edges as segments.
    public var edges: [Segment2] { edgeVertices.map { Segment2(vertices[$0.a], vertices[$0.b]) } }

    public init(segments: [Segment2], snapTolerance: Double = Tolerance.length) {
        let tol = max(snapTolerance, Tolerance.length)
        self.snapTolerance = tol
        let segs = segments.filter {
            $0.start.x.isFinite && $0.start.y.isFinite && $0.end.x.isFinite && $0.end.y.isFinite && $0.length > tol
        }
        guard !segs.isEmpty else { return }
        buildEdges(segs, tol: tol)
        buildFaces()
    }

    // MARK: Edges

    private mutating func buildEdges(_ segs: [Segment2], tol: Double) {
        var extent = Rect2.empty
        var total = 0.0
        for s in segs { extent.include(s.bounds); total += s.length }
        let cell = SpatialGrid<Int>.suggestedCellSize(extent: extent, count: segs.count, meanItemSize: total / Double(segs.count))
        var grid = SpatialGrid<Int>(cellSize: cell)
        for (i, s) in segs.enumerated() { grid.insert(i, bounds: s.bounds.expanded(by: tol)) }

        var welder = PointWelder2(tolerance: tol)
        for s in segs {
            _ = welder.id(for: s.start)
            _ = welder.id(for: s.end)
        }
        for i in segs.indices {
            let a = segs[i]
            for j in grid.query(a.bounds.expanded(by: tol)) where j > i {
                let b = segs[j]
                let parallel = abs(a.direction.cross(b.direction)) <= Tolerance.angle
                if parallel && abs(a.signedDistance(to: b.start)) <= tol && abs(a.signedDistance(to: b.end)) <= tol {
                    continue // collinear: endpoints split each other in the vertex pass
                }
                guard let hit = a.lineIntersection(b) else { continue }
                let et = tol / a.length, eu = tol / b.length
                guard hit.t >= -et, hit.t <= 1 + et, hit.u >= -eu, hit.u <= 1 + eu else { continue }
                _ = welder.id(for: a.point(at: min(1, max(0, hit.t))))
            }
        }
        vertices = welder.points

        var splits: [[Int]] = Array(repeating: [], count: segs.count)
        for (vid, p) in vertices.enumerated() {
            for si in grid.query(point: p, radius: 0) where segs[si].distance(to: p) <= tol {
                splits[si].append(vid)
            }
        }
        var seen: Set<EdgeIndex> = []
        for (si, s) in segs.enumerated() {
            let ordered = splits[si].map { (s.parameter(of: vertices[$0]), $0) }.sorted {
                $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1
            }
            var prevID = -1
            for (_, v) in ordered {
                if prevID >= 0 && v != prevID {
                    let key = EdgeIndex(a: min(prevID, v), b: max(prevID, v))
                    if seen.insert(key).inserted { edgeVertices.append(EdgeIndex(a: prevID, b: v)) }
                }
                prevID = v
            }
        }
    }

    // MARK: Faces

    private mutating func buildFaces() {
        let eCount = edgeVertices.count
        let vCount = vertices.count
        guard eCount > 0 else { return }
        var alive = Array(repeating: true, count: eCount)
        var cycles: [[Int]] = []
        var cycleOf = Array(repeating: -1, count: eCount * 2)

        func origin(_ h: Int) -> Int { h & 1 == 0 ? edgeVertices[h >> 1].a : edgeVertices[h >> 1].b }
        func dest(_ h: Int) -> Int { h & 1 == 0 ? edgeVertices[h >> 1].b : edgeVertices[h >> 1].a }

        while true {
            // Prune dead ends.
            var degree = Array(repeating: 0, count: vCount)
            var incident: [[Int]] = Array(repeating: [], count: vCount)
            for e in 0..<eCount where alive[e] {
                degree[edgeVertices[e].a] += 1; degree[edgeVertices[e].b] += 1
                incident[edgeVertices[e].a].append(e); incident[edgeVertices[e].b].append(e)
            }
            var stack = (0..<vCount).filter { degree[$0] == 1 }
            while let v = stack.popLast() {
                guard degree[v] == 1, let e = incident[v].first(where: { alive[$0] }) else { continue }
                alive[e] = false
                let o = edgeVertices[e].a == v ? edgeVertices[e].b : edgeVertices[e].a
                degree[v] = 0
                degree[o] -= 1
                if degree[o] == 1 { stack.append(o) }
            }
            // Angular order of outgoing half-edges.
            var outgoing: [[Int]] = Array(repeating: [], count: vCount)
            for e in 0..<eCount where alive[e] {
                outgoing[edgeVertices[e].a].append(2 * e)
                outgoing[edgeVertices[e].b].append(2 * e + 1)
            }
            var position = Array(repeating: 0, count: eCount * 2)
            for v in 0..<vCount where !outgoing[v].isEmpty {
                let p = vertices[v]
                outgoing[v] = outgoing[v].map { h in ((vertices[dest(h)] - p).angle, h) }
                    .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
                    .map(\.1)
                for (i, h) in outgoing[v].enumerated() { position[h] = i }
            }
            // Trace cycles: next(h) is the outgoing edge at dest(h) immediately clockwise from twin(h).
            cycles = []
            cycleOf = Array(repeating: -1, count: eCount * 2)
            for start in 0..<(eCount * 2) where alive[start >> 1] && cycleOf[start] < 0 {
                var cycle: [Int] = []
                var h = start
                let cid = cycles.count
                while cycleOf[h] < 0 {
                    cycleOf[h] = cid
                    cycle.append(h)
                    let v = dest(h)
                    let list = outgoing[v]
                    let twin = h ^ 1
                    h = list[(position[twin] - 1 + list.count) % list.count]
                }
                cycles.append(cycle)
            }
            // Remove bridges (same cycle on both sides) and retry.
            var removed = false
            for e in 0..<eCount where alive[e] && cycleOf[2 * e] == cycleOf[2 * e + 1] {
                alive[e] = false
                removed = true
            }
            if !removed { break }
        }

        // Classify cycles.
        var bounded: [Int] = []       // cycle ids
        var boundaries: [Int] = []    // clockwise component boundaries
        var cyclePolys: [Polygon2] = []
        for (cid, c) in cycles.enumerated() {
            let poly = Polygon2(c.map { vertices[origin($0)] })
            cyclePolys.append(poly)
            let a = poly.signedArea
            if a > Tolerance.area { bounded.append(cid) } else if a < -Tolerance.area { boundaries.append(cid) }
        }
        // Connected components.
        var parent = Array(0..<vCount)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var y = x
            while parent[y] != r { let n = parent[y]; parent[y] = r; y = n }
            return r
        }
        for e in 0..<eCount where alive[e] {
            let ra = find(edgeVertices[e].a), rb = find(edgeVertices[e].b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        var faceOfCycle = Array(repeating: -1, count: cycles.count)
        var outers: [Polygon2] = []
        var faceComponent: [Int] = []
        var grid = SpatialGrid<Int>(cellSize: 1)
        if !bounded.isEmpty {
            var extent = Rect2.empty
            for cid in bounded { extent.include(cyclePolys[cid].bounds) }
            grid = SpatialGrid<Int>(cellSize: SpatialGrid<Int>.suggestedCellSize(
                extent: extent, count: bounded.count, meanItemSize: max(extent.width, extent.height) / max(1, Double(bounded.count).squareRoot())))
        }
        for cid in bounded {
            let fi = outers.count
            faceOfCycle[cid] = fi
            outers.append(cyclePolys[cid])
            faceComponent.append(find(origin(cycles[cid][0])))
            grid.insert(fi, bounds: cyclePolys[cid].bounds)
        }
        var holes: [[Polygon2]] = Array(repeating: [], count: outers.count)
        for cid in boundaries {
            let comp = find(origin(cycles[cid][0]))
            let probe = vertices[origin(cycles[cid][0])]
            var best = -1
            var bestArea = Double.infinity
            for fi in grid.query(point: probe, radius: 0) where faceComponent[fi] != comp {
                let a = outers[fi].area
                if a < bestArea && outers[fi].contains(probe, onBoundary: false) { best = fi; bestArea = a }
            }
            if best >= 0 {
                faceOfCycle[cid] = best
                holes[best].append(cyclePolys[cid])
            }
        }
        faces = outers.indices.map { ArrangementFace(outer: outers[$0], holes: holes[$0]) }
        faceGrid = grid
        halfEdgeFace = (0..<(eCount * 2)).map { h in
            guard alive[h >> 1] else { return -2 }
            let c = cycleOf[h]
            return c >= 0 ? faceOfCycle[c] : -1
        }
    }

    /// Smallest bounded face strictly containing `p`; nil in the unbounded region or on an edge.
    public func face(containing p: Vec2) -> ArrangementFace? {
        faceIndex(containing: p).map { faces[$0] }
    }

    /// Index into `faces` of the face strictly containing `p`.
    public func faceIndex(containing p: Vec2) -> Int? {
        var best: Int? = nil
        var bestArea = Double.infinity
        for fi in faceGrid.query(point: p, radius: 0) {
            let f = faces[fi]
            guard f.area < bestArea, f.outer.contains(p, onBoundary: false),
                  !f.holes.contains(where: { $0.contains(p, onBoundary: true) }) else { continue }
            best = fi
            bestArea = f.area
        }
        return best
    }
}

extension ArrangementFace {
    /// A point strictly inside the face (centroid of its largest triangle).
    func interiorPoint() -> Vec2? {
        let tri = Triangulator.triangulate(profile)
        var best: Vec2? = nil
        var bestArea = 0.0
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            let a = tri.points[tri.triangles[t]], b = tri.points[tri.triangles[t + 1]], c = tri.points[tri.triangles[t + 2]]
            let ar = (b - a).cross(c - a) * 0.5
            if ar > bestArea { bestArea = ar; best = (a + b + c) / 3 }
        }
        return best
    }
}
