import Foundation

/// Miter limit for offsets, as a multiple of the offset distance.
let offsetMiterLimit: Double = 4

extension Polygon2 {
    /// Offsets the region enclosed by the polygon by `distance`: positive grows it
    /// (outward for a CCW polygon), negative shrinks it, regardless of the input winding.
    ///
    /// Corners are mitered; a miter reaching farther than 4×|distance| from its vertex is
    /// beveled. The raw offset loop is cleaned through a planar arrangement keeping faces
    /// of positive winding number, so shrinking past narrow parts splits or removes loops.
    /// Returns outer loops (CCW) followed by any hole loops (CW) that the growth encloses;
    /// empty when nothing remains.
    public func offset(by distance: Double) -> [Polygon2] {
        let base = simplified().counterClockwise
        guard base.count >= 3, !base.isDegenerate else { return [] }
        if abs(distance) <= Tolerance.length { return [base] }
        let raw = Self.rawOffsetLoop(base.points, distance: distance)
        guard raw.count >= 3 else { return [] }
        let segs = (0..<raw.count).map { Segment2(raw[$0], raw[($0 + 1) % raw.count]) }.filter { !$0.isDegenerate }
        // Positive winding keeps the grown band and drops inverted pieces. A shrunk square's
        // raw loop is point-reflected (still CCW), so shrink results must additionally lie at
        // least |distance| from the original boundary; the slack only absorbs rounding.
        let slack = Tolerance.length * 10
        let profiles = PolygonBoolean.resolve(segments: segs) { p in
            guard windingNumber(raw, p) > 0 else { return false }
            if distance > 0 { return true }
            return base.contains(p, onBoundary: false) && base.distanceToBoundary(p) >= -distance - slack
        }
        var outers: [Polygon2] = [], holes: [Polygon2] = []
        for p in profiles {
            outers.append(p.outer)
            holes.append(contentsOf: p.holes)
        }
        return outers + holes
    }

    /// Raw (possibly self-intersecting) mitered offset of a CCW loop.
    static func rawOffsetLoop(_ pts: [Vec2], distance d: Double) -> [Vec2] {
        let n = pts.count
        var out: [Vec2] = []
        out.reserveCapacity(n * 2)
        for i in 0..<n {
            let p0 = pts[(i + n - 1) % n], p1 = pts[i], p2 = pts[(i + 1) % n]
            let e0 = (p1 - p0).normalized, e1 = (p2 - p1).normalized
            // Outward (right-hand) normals of the CCW loop.
            let n0 = Vec2(e0.y, -e0.x), n1 = Vec2(e1.y, -e1.x)
            let a = p1 + n0 * d, b = p1 + n1 * d
            let cross = e0.cross(e1)
            if abs(cross) <= Tolerance.angle && e0.dot(e1) > 0 {
                out.append(a) // collinear
                continue
            }
            let l0 = Segment2(p0 + n0 * d, a), l1 = Segment2(b, p2 + n1 * d)
            let convexForOffset = d > 0 ? cross > 0 : cross < 0
            if let hit = l0.lineIntersection(l1), hit.point.distance(to: p1) <= offsetMiterLimit * abs(d) {
                out.append(hit.point)
            } else if convexForOffset {
                out.append(a); out.append(b) // bevel
            } else {
                // Concave side with an extreme miter: the raw points form a small loop
                // that the winding cleanup removes.
                out.append(a); out.append(p1); out.append(b)
            }
        }
        var clean: [Vec2] = []
        for p in out where clean.last.map({ !$0.isAlmostEqual(p) }) ?? true { clean.append(p) }
        while clean.count > 1, clean[0].isAlmostEqual(clean[clean.count - 1]) { clean.removeLast() }
        return clean
    }
}

/// Winding number of a closed loop around `p` (CCW loops give +1 inside).
func windingNumber(_ loop: [Vec2], _ p: Vec2) -> Int {
    var w = 0
    let n = loop.count
    for i in 0..<n {
        let a = loop[i], b = loop[(i + 1) % n]
        if a.y <= p.y {
            if b.y > p.y && (b - a).cross(p - a) > 0 { w += 1 }
        } else if b.y <= p.y && (b - a).cross(p - a) < 0 {
            w -= 1
        }
    }
    return w
}

/// Offsets of open polylines.
public enum PolylineOffset {
    /// Offsets an open polyline by `d` (positive to the left of travel) with mitered
    /// joints; miters longer than 4×|d| are beveled. Consecutive duplicate points are
    /// ignored. Returns [] for fewer than two distinct points.
    public static func offset(_ pts: [Vec2], by d: Double) -> [Vec2] {
        var p: [Vec2] = []
        for q in pts where p.last.map({ !$0.isAlmostEqual(q) }) ?? true { p.append(q) }
        guard p.count >= 2 else { return [] }
        var out: [Vec2] = []
        func leftNormal(_ a: Vec2, _ b: Vec2) -> Vec2 { (b - a).normalized.perpendicular }
        out.append(p[0] + leftNormal(p[0], p[1]) * d)
        if p.count > 2 {
            for i in 1..<(p.count - 1) {
                let n0 = leftNormal(p[i - 1], p[i]), n1 = leftNormal(p[i], p[i + 1])
                let a = p[i] + n0 * d, b = p[i] + n1 * d
                let e0 = (p[i] - p[i - 1]).normalized, e1 = (p[i + 1] - p[i]).normalized
                if abs(e0.cross(e1)) <= Tolerance.angle {
                    if e0.dot(e1) > 0 { out.append(a) } else { out.append(a); out.append(b) }
                    continue
                }
                let l0 = Segment2(p[i - 1] + n0 * d, a), l1 = Segment2(b, p[i + 1] + n1 * d)
                if let hit = l0.lineIntersection(l1), hit.point.distance(to: p[i]) <= offsetMiterLimit * abs(d) {
                    out.append(hit.point)
                } else {
                    out.append(a); out.append(b)
                }
            }
        }
        out.append(p[p.count - 1] + leftNormal(p[p.count - 2], p[p.count - 1]) * d)
        var clean: [Vec2] = []
        for q in out where clean.last.map({ !$0.isAlmostEqual(q) }) ?? true { clean.append(q) }
        return clean
    }
}
