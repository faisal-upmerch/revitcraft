import Foundation

/// Geometric constructions used by object snapping.
public enum SnapMath {
    /// Foot of the perpendicular from `p` onto the curve, if it lies on the bounded curve.
    /// For arcs, the nearer of the two radial feet that lies on the arc is returned.
    public static func perpendicularFoot(from p: Vec2, to c: Curve2) -> Vec2? {
        switch c {
        case .line(let s):
            guard !s.isDegenerate else { return nil }
            let t = s.parameter(of: p)
            let e = Tolerance.length / s.length
            guard t >= -e, t <= 1 + e else { return nil }
            return s.point(at: min(1, max(0, t)))
        case .arc(let a):
            let d = p - a.center
            guard d.length > Tolerance.length, a.radius > Tolerance.length else { return nil }
            let u = d.normalized
            let near = a.center + u * a.radius, far = a.center - u * a.radius
            for q in [near, far] where a.containsAngleTolerant((q - a.center).angle) { return q }
            return nil
        }
    }

    /// Points on the arc where a line through `p` is tangent to it, ordered along the arc.
    /// Empty when `p` is inside the circle; `[p]` when `p` lies on the arc itself.
    public static func tangentPoints(from p: Vec2, to arc: Arc2) -> [Vec2] {
        let d = p - arc.center
        let dist = d.length
        let r = arc.radius
        guard r > Tolerance.length else { return [] }
        if abs(dist - r) <= Tolerance.length {
            return arc.containsAngleTolerant(d.angle) ? [p] : []
        }
        guard dist > r else { return [] }
        let alpha = acos(r / dist)
        let base = d.angle
        let pts = [base - alpha, base + alpha]
            .filter { arc.containsAngleTolerant($0) }
            .map { (arc.parameter(ofAngle: $0), arc.point(atAngle: $0)) }
            .sorted { $0.0 < $1.0 }
        return pts.map(\.1)
    }

    /// Quadrant points (angles 0, π/2, π, 3π/2) lying on the arc, ordered along the arc.
    public static func quadrantPoints(of arc: Arc2) -> [Vec2] {
        (0..<4).map { Double($0) * .pi / 2 }
            .filter { arc.containsAngleTolerant($0) }
            .map { (arc.parameter(ofAngle: $0), arc.point(atAngle: $0)) }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// Nearest point on the bounded curve.
    public static func nearest(on c: Curve2, to p: Vec2) -> Vec2 { c.closestPoint(to: p) }
}
