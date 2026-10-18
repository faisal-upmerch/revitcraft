import Foundation

/// A bounded straight segment.
public struct Segment2: Hashable, Codable, Sendable {
    public var start: Vec2
    public var end: Vec2

    public init(_ start: Vec2, _ end: Vec2) { self.start = start; self.end = end }

    public var vector: Vec2 { end - start }
    public var length: Double { vector.length }
    public var direction: Vec2 { vector.normalized }
    /// Left-hand unit normal (CCW perpendicular of direction).
    public var normal: Vec2 { direction.perpendicular }
    public var midpoint: Vec2 { start.midpoint(end) }
    public var reversed: Segment2 { Segment2(end, start) }
    public var bounds: Rect2 { Rect2(points: [start, end]) }
    public var isDegenerate: Bool { vector.lengthSquared <= Tolerance.lengthSquared }

    public func point(at t: Double) -> Vec2 { start.lerp(to: end, t: t) }
    /// Parameter of the orthogonal projection of p onto the infinite line (0 at start, 1 at end).
    public func parameter(of p: Vec2) -> Double {
        let v = vector
        let l2 = v.lengthSquared
        return l2 > 0 ? (p - start).dot(v) / l2 : 0
    }
    public func closestPoint(to p: Vec2) -> Vec2 { point(at: min(1, max(0, parameter(of: p)))) }
    public func distance(to p: Vec2) -> Double { closestPoint(to: p).distance(to: p) }
    /// Signed perpendicular distance from the infinite line (positive on the left).
    public func signedDistance(to p: Vec2) -> Double { direction.cross(p - start) }
    public func offset(by d: Double) -> Segment2 { let n = normal * d; return Segment2(start + n, end + n) }
    public func transformed(_ t: Transform2) -> Segment2 { Segment2(t.apply(start), t.apply(end)) }
    public func isParallel(to o: Segment2) -> Bool { abs(direction.cross(o.direction)) <= Tolerance.angle }
    public func isCollinear(with o: Segment2) -> Bool {
        isParallel(to: o) && abs(signedDistance(to: o.start)) <= Tolerance.length
    }

    /// Intersection of the infinite lines; returns parameters on self and other.
    public func lineIntersection(_ o: Segment2) -> (point: Vec2, t: Double, u: Double)? {
        let r = vector, s = o.vector
        let denom = r.cross(s)
        guard abs(denom) > 1e-14 * max(1, r.length * s.length) else { return nil }
        let qp = o.start - start
        let t = qp.cross(s) / denom
        let u = qp.cross(r) / denom
        return (point(at: t), t, u)
    }
    /// Proper or touching intersection of the bounded segments (within tolerance).
    public func intersection(_ o: Segment2) -> Vec2? {
        guard let hit = lineIntersection(o) else { return nil }
        let et = Tolerance.length / max(length, Tolerance.length)
        let eu = Tolerance.length / max(o.length, Tolerance.length)
        guard hit.t >= -et, hit.t <= 1 + et, hit.u >= -eu, hit.u <= 1 + eu else { return nil }
        return hit.point
    }
}

/// A circular arc, counter-clockwise from startAngle sweeping `sweep` radians (sweep may be negative for CW).
public struct Arc2: Hashable, Codable, Sendable {
    public var center: Vec2
    public var radius: Double
    public var startAngle: Double
    public var sweep: Double

    public init(center: Vec2, radius: Double, startAngle: Double, sweep: Double) {
        self.center = center; self.radius = radius; self.startAngle = startAngle; self.sweep = sweep
    }

    /// Arc through three points (start, a point on the arc, end). Nil if collinear.
    public init?(through a: Vec2, _ b: Vec2, _ c: Vec2) {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-12 else { return nil }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        let ctr = Vec2(ux, uy)
        let sa = (a - ctr).angle, ma = (b - ctr).angle, ea = (c - ctr).angle
        var sw = Angle.normalize(ea - sa)
        // Choose direction so that the middle point lies on the arc.
        if Angle.normalize(ma - sa) > sw { sw -= Angle.twoPi }
        self.init(center: ctr, radius: (a - ctr).length, startAngle: sa, sweep: sw)
    }

    public var endAngle: Double { startAngle + sweep }
    public var start: Vec2 { point(atAngle: startAngle) }
    public var end: Vec2 { point(atAngle: endAngle) }
    public var mid: Vec2 { point(atAngle: startAngle + sweep / 2) }
    public var length: Double { abs(sweep) * radius }
    public var isFullCircle: Bool { abs(abs(sweep) - Angle.twoPi) <= Tolerance.angle }
    public func point(atAngle a: Double) -> Vec2 { center + Vec2(cos(a), sin(a)) * radius }
    public func point(at t: Double) -> Vec2 { point(atAngle: startAngle + sweep * t) }
    public func tangent(at t: Double) -> Vec2 {
        let a = startAngle + sweep * t
        let v = Vec2(-sin(a), cos(a))
        return sweep >= 0 ? v : -v
    }
    /// True if the angle lies within the swept range.
    public func containsAngle(_ a: Double) -> Bool {
        if isFullCircle { return true }
        let rel = sweep >= 0 ? Angle.normalize(a - startAngle) : Angle.normalize(startAngle - a)
        return rel <= abs(sweep) + Tolerance.angle
    }
    public var reversed: Arc2 { Arc2(center: center, radius: radius, startAngle: endAngle, sweep: -sweep) }
    public var bounds: Rect2 {
        var r = Rect2(points: [start, end])
        for q in 0..<4 {
            let a = Double(q) * .pi / 2
            if containsAngle(a) { r.include(point(atAngle: a)) }
        }
        return r
    }
    /// Polyline approximation with chord error below `chordTolerance`.
    public func tessellate(chordTolerance: Double = 0.002, maxSegments: Int = 256) -> [Vec2] {
        let n: Int
        if radius <= chordTolerance {
            n = 2
        } else {
            let step = 2 * acos(max(-1, min(1, 1 - chordTolerance / radius)))
            n = max(2, min(maxSegments, Int(ceil(abs(sweep) / max(step, 1e-6)))))
        }
        return (0...n).map { point(at: Double($0) / Double(n)) }
    }
    public func closestPoint(to p: Vec2) -> Vec2 {
        let a = (p - center).angle
        if containsAngle(a) { return point(atAngle: a) }
        return p.distance(to: start) < p.distance(to: end) ? start : end
    }
    public func transformed(_ t: Transform2) -> Arc2 {
        let c = t.apply(center)
        let s = t.apply(start)
        let r = radius * t.uniformScale
        let sa = (s - c).angle
        return Arc2(center: c, radius: r, startAngle: sa, sweep: t.isMirroring ? -sweep : sweep)
    }
}

/// A planar curve used by sketches, walls, grids and drafting.
public enum Curve2: Hashable, Codable, Sendable {
    case line(Segment2)
    case arc(Arc2)

    public var start: Vec2 {
        switch self { case .line(let s): s.start; case .arc(let a): a.start }
    }
    public var end: Vec2 {
        switch self { case .line(let s): s.end; case .arc(let a): a.end }
    }
    public var midpoint: Vec2 {
        switch self { case .line(let s): s.midpoint; case .arc(let a): a.mid }
    }
    public var length: Double {
        switch self { case .line(let s): s.length; case .arc(let a): a.length }
    }
    public var bounds: Rect2 {
        switch self { case .line(let s): s.bounds; case .arc(let a): a.bounds }
    }
    public var reversed: Curve2 {
        switch self { case .line(let s): .line(s.reversed); case .arc(let a): .arc(a.reversed) }
    }
    public func point(at t: Double) -> Vec2 {
        switch self { case .line(let s): s.point(at: t); case .arc(let a): a.point(at: t) }
    }
    public func tangent(at t: Double) -> Vec2 {
        switch self { case .line(let s): s.direction; case .arc(let a): a.tangent(at: t) }
    }
    /// Left normal at parameter t.
    public func normal(at t: Double) -> Vec2 { tangent(at: t).perpendicular }
    public func closestPoint(to p: Vec2) -> Vec2 {
        switch self { case .line(let s): s.closestPoint(to: p); case .arc(let a): a.closestPoint(to: p) }
    }
    public func distance(to p: Vec2) -> Double { closestPoint(to: p).distance(to: p) }
    public func transformed(_ t: Transform2) -> Curve2 {
        switch self { case .line(let s): .line(s.transformed(t)); case .arc(let a): .arc(a.transformed(t)) }
    }
    public func tessellate(chordTolerance: Double = 0.002) -> [Vec2] {
        switch self {
        case .line(let s): [s.start, s.end]
        case .arc(let a): a.tessellate(chordTolerance: chordTolerance)
        }
    }
    /// Offset to the left by d (for arcs: radius change respecting direction).
    public func offset(by d: Double) -> Curve2 {
        switch self {
        case .line(let s): return .line(s.offset(by: d))
        case .arc(let a):
            let r = a.sweep >= 0 ? a.radius - d : a.radius + d
            return .arc(Arc2(center: a.center, radius: max(r, Tolerance.length), startAngle: a.startAngle, sweep: a.sweep))
        }
    }
    public var asSegment: Segment2? { if case .line(let s) = self { return s }; return nil }
    public var asArc: Arc2? { if case .arc(let a) = self { return a }; return nil }
}
