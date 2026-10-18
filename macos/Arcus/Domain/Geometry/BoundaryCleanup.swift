import Foundation

/// A piece of a union outline, attributed to the polygon it came from.
public struct BoundaryPiece: Sendable, Hashable {
    public var polygonIndex: Int
    public var segment: Segment2

    public init(polygonIndex: Int, segment: Segment2) {
        self.polygonIndex = polygonIndex
        self.segment = segment
    }
}

/// Outline cleanup for overlapping plan polygons (wall joins, hidden pieces).
public enum BoundaryCleanup {
    /// Distance at which the two sides of an edge are probed. Twenty times the
    /// coincidence tolerance keeps probes clear of `Polygon2.contains`'s boundary band
    /// while staying far below any buildable thickness (0.2 mm).
    static let sideProbe: Double = Tolerance.length * 20

    /// Accelerated "is this point inside any polygon" query.
    struct PolygonSet {
        let polygons: [Polygon2]
        let grid: SpatialGrid<Int>

        init(_ polygons: [Polygon2]) {
            self.polygons = polygons
            var extent = Rect2.empty
            var size = 0.0
            for p in polygons { let b = p.bounds; extent.include(b); size += max(b.width, b.height) }
            var g = SpatialGrid<Int>(cellSize: SpatialGrid<Int>.suggestedCellSize(
                extent: extent, count: max(1, polygons.count), meanItemSize: size / Double(max(1, polygons.count))))
            for (i, p) in polygons.enumerated() where p.count >= 3 { g.insert(i, bounds: p.bounds) }
            grid = g
        }

        func insideAny(_ q: Vec2, onBoundary: Bool) -> Bool {
            grid.query(point: q, radius: 0).contains { polygons[$0].contains(q, onBoundary: onBoundary) }
        }

        /// Parameters along `s` where it crosses or touches edges of the candidate polygons.
        func splitParameters(of s: Segment2, excluding skip: Int?) -> [Double] {
            var ts: [Double] = [0, 1]
            let len = s.length
            guard len > Tolerance.length else { return ts }
            for pi in grid.query(s.bounds.expanded(by: Tolerance.length)) where pi != skip {
                for e in polygons[pi].edges where !e.isDegenerate && e.bounds.expanded(by: Tolerance.length).intersects(s.bounds) {
                    let parallel = abs(s.direction.cross(e.direction)) <= Tolerance.angle
                    if parallel {
                        guard abs(s.signedDistance(to: e.start)) <= Tolerance.length else { continue }
                        for p in [e.start, e.end] {
                            let t = s.parameter(of: p)
                            if t > 0 && t < 1 { ts.append(t) }
                        }
                    } else if let hit = s.lineIntersection(e) {
                        let eu = Tolerance.length / e.length
                        let et = Tolerance.length / len
                        if hit.u >= -eu && hit.u <= 1 + eu && hit.t > et && hit.t < 1 - et { ts.append(hit.t) }
                    }
                }
            }
            ts.sort()
            var out: [Double] = []
            for t in ts where out.last.map({ (t - $0) * len > Tolerance.length }) ?? true { out.append(t) }
            if let l = out.last, l < 1 { out[out.count - 1] = 1 }
            return out
        }
    }

    /// The outline of the union of `polygons`, as pieces of their original edges.
    ///
    /// Every edge is split where it meets other polygons' edges; a piece is kept when
    /// exactly one of its two sides (probed at the midpoint ± normal·`sideProbe`) is
    /// inside the union. Interior join lines therefore vanish, and coincident edges
    /// shared by several polygons are emitted once (by the lowest polygon index).
    /// Pieces are oriented with the union's interior on their left and are ordered by
    /// polygon index, edge order, then position along the edge.
    public static func unionBoundary(of polygons: [Polygon2]) -> [BoundaryPiece] {
        let set = PolygonSet(polygons)
        var out: [BoundaryPiece] = []
        var keptGrid = SpatialGrid<Int>(cellSize: set.grid.cellSize)
        for (pi, poly) in polygons.enumerated() where poly.count >= 3 && !poly.isDegenerate {
            for e in poly.edges where !e.isDegenerate {
                let ts = set.splitParameters(of: e, excluding: nil)
                for k in 1..<ts.count {
                    let piece = Segment2(e.point(at: ts[k - 1]), e.point(at: ts[k]))
                    let len = piece.length
                    guard len > Tolerance.length else { continue }
                    let m = piece.midpoint
                    let off = min(sideProbe, len * 0.25)
                    let n = piece.normal * off
                    let left = set.insideAny(m + n, onBoundary: false)
                    let right = set.insideAny(m - n, onBoundary: false)
                    guard left != right else { continue }
                    let oriented = left ? piece : piece.reversed
                    let dup = keptGrid.query(point: m, radius: Tolerance.length).contains { idx in
                        let s = out[idx].segment
                        return (s.start.isAlmostEqual(oriented.start) && s.end.isAlmostEqual(oriented.end))
                            || (s.start.isAlmostEqual(oriented.end) && s.end.isAlmostEqual(oriented.start))
                    }
                    if dup { continue }
                    keptGrid.insert(out.count, bounds: Rect2(points: [m]))
                    out.append(BoundaryPiece(polygonIndex: pi, segment: oriented))
                }
            }
        }
        return out
    }

    /// The parts of `segments` not strictly inside any polygon. Pieces lying on a
    /// polygon boundary are kept. Contiguous kept pieces of one segment are merged;
    /// output keeps input order and each piece keeps its segment's direction.
    public static func clipSegments(_ segments: [Segment2], outside polygons: [Polygon2]) -> [Segment2] {
        let set = PolygonSet(polygons)
        var out: [Segment2] = []
        for s in segments where !s.isDegenerate {
            let ts = set.splitParameters(of: s, excluding: nil)
            var runStart: Double? = nil
            var runEnd = 0.0
            for k in 1..<ts.count {
                let m = s.point(at: (ts[k - 1] + ts[k]) * 0.5)
                let hidden = set.insideAny(m, onBoundary: false)
                if hidden {
                    if let r = runStart { out.append(Segment2(s.point(at: r), s.point(at: runEnd))) }
                    runStart = nil
                } else {
                    if runStart == nil { runStart = ts[k - 1] }
                    runEnd = ts[k]
                }
            }
            if let r = runStart { out.append(Segment2(s.point(at: r), s.point(at: runEnd))) }
        }
        return out.filter { $0.length > Tolerance.length }
    }
}
