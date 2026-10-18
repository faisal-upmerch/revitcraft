import Foundation
import ArcusGeometry

// F1: Spline, Ellipse and Partial Ellipse draw modes (RevitCraft `DrawMode::Spline/Ellipse/PartialEllipse`,
// `crates/rc-app/src/tools.rs` `spline_segs` and `ellipse_points`). Arcus curves are lines and arcs, so these shapes are
// kept as tessellated polylines: one model or detail line holds a whole spline or half ellipse (a full ellipse is two
// halves, as in the reference app), and sketches take their segments as boundary lines.

/// A free-form line: its tessellated points, first to last.
public struct FreeformCurve: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case spline = "Spline", ellipse = "Ellipse", partialEllipse = "Partial Ellipse" }
    public var kind: Kind
    /// At least two points.
    public var points: [Vec2]

    public init(kind: Kind, points: [Vec2]) { self.kind = kind; self.points = points }

    public var segments: [Segment2] {
        guard points.count >= 2 else { return [] }
        return (0..<(points.count - 1)).map { Segment2(points[$0], points[$0 + 1]) }.filter { $0.length > Tolerance.length }
    }
    public var length: Double { segments.reduce(0) { $0 + $1.length } }
    public var bounds: Rect2 { Rect2(points: points) }
    /// The straight line from the first point to the last.
    public var chord: Curve2? {
        guard let a = points.first, let b = points.last, a.distance(to: b) > Tolerance.shortCurve else { return nil }
        return .line(Segment2(a, b))
    }
    public func transformed(_ t: Transform2) -> FreeformCurve { FreeformCurve(kind: kind, points: points.map(t.apply)) }

    /// The curve turned and scaled about its ends so they land on `start` and `end` (dragging an end grip).
    public func stretched(start: Vec2, end: Vec2) -> FreeformCurve {
        guard let a = points.first, let b = points.last else { return self }
        let d = b - a, e = end - start
        let l2 = d.lengthSquared
        guard l2 > 1e-18 else { return self }
        // Complex ratio e / d: a rotation with a uniform scale.
        let re = (e.x * d.x + e.y * d.y) / l2, im = (e.y * d.x - e.x * d.y) / l2
        return FreeformCurve(kind: kind, points: points.map { q in
            let v = q - a
            return start + Vec2(v.x * re - v.y * im, v.x * im + v.y * re)
        })
    }

    /// A Catmull-Rom spline through the points, 10 steps per span (RevitCraft `spline_segs`).
    public static func spline(through pts: [Vec2]) -> [Vec2] {
        guard pts.count >= 2 else { return pts }
        let n = pts.count
        func at(_ i: Int) -> Vec2 { pts[min(max(i, 0), n - 1)] }
        var out = [pts[0]]
        for i in 0..<(n - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            for k in 1...10 {
                let t = Double(k) / 10, t2 = t * t, t3 = t2 * t
                let a = p1 * 2, b = (p2 - p0) * t, c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2, d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                let q = (a + b + c + d) * 0.5
                if let last = out.last, q.distance(to: last) > 1e-9 { out.append(q) }
            }
        }
        return out
    }

    /// An ellipse about `center` with one axis end at `axisEnd`; the other radius is the distance of `through` from that
    /// axis. 48 points, returned as its two halves (each from one axis end to the other). Nil when degenerate.
    public static func ellipse(center: Vec2, axisEnd: Vec2, through: Vec2) -> [[Vec2]]? {
        let axis = axisEnd - center
        guard axis.length > Tolerance.shortCurve else { return nil }
        let n = axis.normalized.perpendicular
        let minor = (through - center).dot(n)
        guard abs(minor) > Tolerance.shortCurve else { return nil }
        func pt(_ t: Double) -> Vec2 { center + axis * cos(t) + n * (minor * sin(t)) }
        let first = (0...24).map { pt(Double.pi * Double($0) / 24) }
        let second = (24...48).map { pt(Double.pi * Double($0) / 24) }
        return [first, second]
    }

    /// Half an ellipse on the axis from `a` to `b`, bulging to the side of `through` by its distance from the axis
    /// (RevitCraft: from a through the side of c to b). 25 points. Nil when degenerate.
    public static func halfEllipse(from a: Vec2, to b: Vec2, through: Vec2) -> [Vec2]? {
        let center = (a + b) * 0.5, axis = (b - a) * 0.5
        guard axis.length > Tolerance.shortCurve else { return nil }
        let n = axis.normalized.perpendicular
        let minor = (through - center).dot(n)
        guard abs(minor) > Tolerance.shortCurve else { return nil }
        return (0...24).map { k in
            let t = Double.pi * (1 - Double(k) / 24)
            return center + axis * cos(t) + n * (minor * sin(t))
        }
    }
}

extension ModelLineData {
    /// The line as drawn: a free-form line's segments, else its line or arc.
    public var curves: [Curve2] { freeform.map { $0.segments.map { .line($0) } } ?? [curve] }
    /// Length as drawn.
    public var drawnLength: Double { freeform?.length ?? curve.length }
    /// Plan bounds as drawn.
    public var drawnBounds: Rect2 { freeform?.bounds ?? curve.bounds }
}
