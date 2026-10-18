import Foundation
import ArcusGeometry

// F2: multi-segment grids (RevitCraft `Grid::vertices`, `add_grid_path`): a grid through several connected straight
// segments, its bubbles at the two ends along the end segments.

extension GridData {
    /// A grid of several connected segments (it has bend points).
    public var isMultiSegment: Bool { !(vertices ?? []).isEmpty }

    /// A multi-segment grid through `points` (at least two, consecutive duplicates dropped).
    public init?(path points: [Vec2], bubbleAtStart: Bool = true, bubbleAtEnd: Bool = false) {
        var v: [Vec2] = []
        for p in points where v.last.map({ $0.distance(to: p) > Tolerance.shortCurve }) ?? true { v.append(p) }
        // Bends that don't turn are dropped, so a straight chain is an ordinary straight grid.
        var k = 1
        while k < v.count - 1 {
            if abs((v[k] - v[k - 1]).normalized.cross((v[k + 1] - v[k]).normalized)) < 1e-9, (v[k] - v[k - 1]).dot(v[k + 1] - v[k]) > 0 { v.remove(at: k) } else { k += 1 }
        }
        guard v.count >= 2 else { return nil }
        self.init(curve: .line(Segment2(v[0], v[v.count - 1])), bubbleAtStart: bubbleAtStart, bubbleAtEnd: bubbleAtEnd)
        vertices = v.count > 2 ? Array(v[1..<(v.count - 1)]) : nil
    }

    /// The grid line as drawn: arcs tessellated, multi-segment grids through their bends.
    public var polyline: [Vec2] {
        guard isMultiSegment else { return curve.tessellate(chordTolerance: 0.01) }
        return [curve.start] + (vertices ?? []) + [curve.end]
    }

    /// The straight segments of a straight or multi-segment grid (empty for arcs).
    public var segments: [Segment2] {
        guard curve.asSegment != nil else { return [] }
        let p = polyline
        return (0..<(p.count - 1)).map { Segment2(p[$0], p[$0 + 1]) }.filter { $0.length > Tolerance.shortCurve }
    }

    /// Outward directions at the start and the end, where the bubbles sit.
    public var endDirections: (start: Vec2, end: Vec2) {
        if case .arc(let a) = curve { return (-a.tangent(at: 0), a.tangent(at: 1)) }
        let p = polyline, n = p.count
        return ((p[0] - p[1]).normalized, (p[n - 1] - p[n - 2]).normalized)
    }

    /// Total length along the segments.
    public var pathLength: Double { isMultiSegment ? segments.reduce(0) { $0 + $1.length } : curve.length }

    /// The segment an elevation or section through `planeLine` shows: the one the plane crosses, else (elevations) the
    /// longest one that isn't parallel to it. As RevitCraft: a multi-segment grid shows where one of its segments does.
    public func segment(seenBy planeLine: Segment2) -> Segment2? {
        guard isMultiSegment else { return curve.asSegment }
        let segs = segments.filter { !$0.isParallel(to: planeLine) }
        return segs.first { s in s.lineIntersection(planeLine).map { $0.t >= -1e-6 && $0.t <= 1 + 1e-6 } ?? false }
            ?? segs.max { $0.length < $1.length }
    }
}
