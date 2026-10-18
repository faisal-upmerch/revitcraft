import Foundation

// MARK: - Circle helpers

extension Arc2 {
    /// Angular tolerance equivalent to `Tolerance.length` measured along this arc.
    var angularTolerance: Double { max(Tolerance.angle, Tolerance.length / max(radius, Tolerance.length)) }

    /// Sweep-relative parameter of an angle in 0…1 when inside the sweep; outside
    /// the sweep it extends below 0 or above 1 towards the nearer end.
    func parameter(ofAngle a: Double) -> Double {
        let span = abs(sweep)
        guard span > 0 else { return 0 }
        let rel = sweep >= 0 ? Angle.normalize(a - startAngle) : Angle.normalize(startAngle - a)
        if isFullCircle || rel <= span { return rel / span }
        let past = rel - span
        let before = Angle.twoPi - rel
        return before < past ? -before / span : rel / span
    }

    /// True if the angle is within the sweep, with a length-based tolerance at the ends.
    func containsAngleTolerant(_ a: Double) -> Bool {
        if isFullCircle { return true }
        let t = parameter(ofAngle: a)
        let e = angularTolerance / max(abs(sweep), Tolerance.angle)
        return t >= -e && t <= 1 + e
    }
}

/// Intersections of the infinite line through `s` with the circle (center, r).
/// Returns 0, 1 (tangent within tolerance) or 2 points ordered along the line.
func lineCircleIntersections(_ s: Segment2, center: Vec2, radius r: Double) -> [Vec2] {
    let d = s.direction
    guard d.lengthSquared > 0 else { return [] }
    let foot = s.start + d * (center - s.start).dot(d)
    let h = foot.distance(to: center)
    if h > r + Tolerance.length { return [] }
    if abs(h - r) <= Tolerance.length {
        // Tangent (or within tolerance of tangent): the foot is the single contact.
        return [h > 0 ? center + (foot - center) * (r / h) : foot]
    }
    let k = (max(0, r * r - h * h)).squareRoot()
    return [foot - d * k, foot + d * k]
}

/// Intersections of two full circles. Returns [] for concentric circles.
func circleCircleIntersections(_ c0: Vec2, _ r0: Double, _ c1: Vec2, _ r1: Double) -> [Vec2] {
    let dv = c1 - c0
    let d = dv.length
    guard d > Tolerance.length else { return [] }
    if d > r0 + r1 + Tolerance.length || d < abs(r0 - r1) - Tolerance.length { return [] }
    let a = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    let h2 = r0 * r0 - a * a
    let u = dv / d
    let base = c0 + u * a
    // Tangent within tolerance: the two roots collapse (compare the gap between roots, 2h).
    if h2 <= 0 || 2 * h2.squareRoot() <= Tolerance.length { return [base] }
    let h = h2.squareRoot()
    let n = u.perpendicular
    return [base - n * h, base + n * h]
}

// MARK: - Curve2 operations

extension Curve2 {
    /// Bounded intersection points with another curve, ordered by parameter along `self`.
    ///
    /// Collinear overlapping lines (and co-circular overlapping arcs) report the
    /// endpoints of the shared portion. Points closer than `Tolerance.length` are merged.
    public func intersections(with other: Curve2) -> [Vec2] {
        var pts: [Vec2] = []
        switch (self, other) {
        case (.line(let a), .line(let b)):
            pts = Self.lineLine(a, b)
        case (.line(let a), .arc(let b)):
            pts = Self.lineArc(a, b)
        case (.arc(let a), .line(let b)):
            pts = Self.lineArc(b, a)
        case (.arc(let a), .arc(let b)):
            pts = Self.arcArc(a, b)
        }
        return orderedUnique(pts)
    }

    /// Sorts points by parameter along self and merges near-duplicates.
    func orderedUnique(_ pts: [Vec2]) -> [Vec2] {
        let sorted = pts.map { (parameter(of: $0), $0) }.sorted { $0.0 < $1.0 }
        var out: [Vec2] = []
        for (_, p) in sorted where !out.contains(where: { $0.isAlmostEqual(p) }) { out.append(p) }
        return out
    }

    private static func onSegment(_ s: Segment2, _ p: Vec2) -> Bool {
        let e = Tolerance.length / max(s.length, Tolerance.length)
        let t = s.parameter(of: p)
        return t >= -e && t <= 1 + e && s.distance(to: p) <= Tolerance.length
    }

    private static func lineLine(_ a: Segment2, _ b: Segment2) -> [Vec2] {
        if a.isDegenerate || b.isDegenerate {
            if a.isDegenerate && b.isDegenerate { return a.start.isAlmostEqual(b.start) ? [a.start] : [] }
            return a.isDegenerate ? (onSegment(b, a.start) ? [a.start] : []) : (onSegment(a, b.start) ? [b.start] : [])
        }
        let parallel = abs(a.direction.cross(b.direction)) <= Tolerance.angle
        if parallel {
            guard abs(a.signedDistance(to: b.start)) <= Tolerance.length,
                  abs(a.signedDistance(to: b.end)) <= Tolerance.length else { return [] }
            var r: [Vec2] = []
            for p in [a.start, a.end] where onSegment(b, p) { r.append(p) }
            for p in [b.start, b.end] where onSegment(a, p) { r.append(p) }
            return r
        }
        return a.intersection(b).map { [$0] } ?? []
    }

    private static func lineArc(_ s: Segment2, _ arc: Arc2) -> [Vec2] {
        if s.isDegenerate {
            let p = s.start
            return abs(p.distance(to: arc.center) - arc.radius) <= Tolerance.length
                && arc.containsAngleTolerant((p - arc.center).angle) ? [p] : []
        }
        return lineCircleIntersections(s, center: arc.center, radius: arc.radius).filter {
            onSegmentParam(s, $0) && arc.containsAngleTolerant(($0 - arc.center).angle)
        }
    }

    private static func onSegmentParam(_ s: Segment2, _ p: Vec2) -> Bool {
        let e = Tolerance.length / max(s.length, Tolerance.length)
        let t = s.parameter(of: p)
        return t >= -e && t <= 1 + e
    }

    private static func arcArc(_ a: Arc2, _ b: Arc2) -> [Vec2] {
        if a.center.isAlmostEqual(b.center) {
            guard abs(a.radius - b.radius) <= Tolerance.length else { return [] }
            // Co-circular: report overlap endpoints.
            var r: [Vec2] = []
            for p in [a.start, a.end] where b.containsAngleTolerant((p - b.center).angle) { r.append(p) }
            for p in [b.start, b.end] where a.containsAngleTolerant((p - a.center).angle) { r.append(p) }
            return r
        }
        return circleCircleIntersections(a.center, a.radius, b.center, b.radius).filter {
            a.containsAngleTolerant(($0 - a.center).angle) && b.containsAngleTolerant(($0 - b.center).angle)
        }
    }

    /// Parameter (0…1 along the curve) of a point on the curve. Lines use the orthogonal
    /// projection; arcs use the angle of the point around the center. Points beyond the
    /// ends yield values outside 0…1.
    public func parameter(of p: Vec2) -> Double {
        switch self {
        case .line(let s): return s.parameter(of: p)
        case .arc(let a): return a.parameter(ofAngle: (p - a.center).angle)
        }
    }

    /// Portion of the curve between parameters t0 and t1 (t1 < t0 yields a reversed piece).
    public func subcurve(from t0: Double, to t1: Double) -> Curve2 {
        switch self {
        case .line(let s):
            return .line(Segment2(s.point(at: t0), s.point(at: t1)))
        case .arc(let a):
            return .arc(Arc2(center: a.center, radius: a.radius,
                             startAngle: a.startAngle + a.sweep * t0, sweep: a.sweep * (t1 - t0)))
        }
    }

    /// Splits at parameter t. Returns nil if either piece would be shorter than
    /// `Tolerance.shortCurve`.
    public func split(at t: Double) -> (Curve2, Curve2)? {
        let len = length
        guard t.isFinite, t * len > Tolerance.shortCurve, (1 - t) * len > Tolerance.shortCurve else { return nil }
        return (subcurve(from: 0, to: t), subcurve(from: t, to: 1))
    }

    /// Moves the start (or end, if `atEnd`) of the curve to the nearest intersection of
    /// its extension (infinite line or full circle) with the extension of `other`.
    ///
    /// Line results that would reverse the curve's direction are rejected, and any
    /// result shorter than `Tolerance.shortCurve` returns nil.
    public func trimmedOrExtended(toMeet other: Curve2, atEnd: Bool) -> Curve2? {
        let candidates = Self.extensionIntersections(self, other)
        let moving = atEnd ? end : start
        let ordered = candidates.sorted {
            let da = $0.distanceSquared(to: moving), db = $1.distanceSquared(to: moving)
            return da != db ? da < db : ($0.x != $1.x ? $0.x < $1.x : $0.y < $1.y)
        }
        for p in ordered {
            if let c = movingEnd(to: p, atEnd: atEnd), c.length > Tolerance.shortCurve { return c }
        }
        return nil
    }

    private func movingEnd(to p: Vec2, atEnd: Bool) -> Curve2? {
        switch self {
        case .line(let s):
            let n = atEnd ? Segment2(s.start, p) : Segment2(p, s.end)
            guard n.vector.dot(s.vector) > 0 else { return nil }
            return .line(n)
        case .arc(let a):
            let ang = (p - a.center).angle
            if atEnd {
                let span = a.sweep >= 0 ? Angle.normalize(ang - a.startAngle) : Angle.normalize(a.startAngle - ang)
                guard span > a.angularTolerance else { return nil }
                return .arc(Arc2(center: a.center, radius: a.radius, startAngle: a.startAngle,
                                 sweep: a.sweep >= 0 ? span : -span))
            } else {
                let end = a.endAngle
                let span = a.sweep >= 0 ? Angle.normalize(end - ang) : Angle.normalize(ang - end)
                guard span > a.angularTolerance else { return nil }
                let sw = a.sweep >= 0 ? span : -span
                return .arc(Arc2(center: a.center, radius: a.radius, startAngle: end - sw, sweep: sw))
            }
        }
    }

    /// Intersections of the unbounded extensions (lines → infinite lines, arcs → full circles).
    static func extensionIntersections(_ a: Curve2, _ b: Curve2) -> [Vec2] {
        switch (a, b) {
        case (.line(let s), .line(let t)):
            guard !s.isDegenerate, !t.isDegenerate, !s.isParallel(to: t), let hit = s.lineIntersection(t) else { return [] }
            return [hit.point]
        case (.line(let s), .arc(let c)), (.arc(let c), .line(let s)):
            return lineCircleIntersections(s, center: c.center, radius: c.radius)
        case (.arc(let c0), .arc(let c1)):
            return circleCircleIntersections(c0.center, c0.radius, c1.center, c1.radius)
        }
    }
}

// MARK: - Fillet

/// Fillet construction between curves.
public enum Fillet {
    /// Tangent arc of `radius` between two line segments that meet (or would meet
    /// when extended) at a corner. The segment ends nearest the corner are trimmed
    /// to the tangent points; each segment keeps its orientation. The arc runs from
    /// the tangent point on `a` to the tangent point on `b`.
    ///
    /// Returns nil for parallel lines, non-positive radius, or when the radius is too
    /// large for the available segment lengths.
    public static func lines(_ a: Segment2, _ b: Segment2, radius: Double) -> (a: Segment2, arc: Arc2, b: Segment2)? {
        guard radius > Tolerance.length, !a.isDegenerate, !b.isDegenerate, !a.isParallel(to: b),
              let hit = a.lineIntersection(b) else { return nil }
        let corner = hit.point
        let aStartFar = a.start.distanceSquared(to: corner) >= a.end.distanceSquared(to: corner)
        let bStartFar = b.start.distanceSquared(to: corner) >= b.end.distanceSquared(to: corner)
        let farA = aStartFar ? a.start : a.end
        let farB = bStartFar ? b.start : b.end
        let da = (farA - corner).normalized, db = (farB - corner).normalized
        let cosT = max(-1, min(1, da.dot(db)))
        let theta = acos(cosT)
        guard theta > Tolerance.angle, Double.pi - theta > Tolerance.angle else { return nil }
        let tangentDist = radius / tan(theta / 2)
        guard tangentDist <= farA.distance(to: corner) + Tolerance.length,
              tangentDist <= farB.distance(to: corner) + Tolerance.length else { return nil }
        let ta = corner + da * tangentDist, tb = corner + db * tangentDist
        let bis = (da + db).normalized
        let center = corner + bis * (radius / sin(theta / 2))
        let sa = (ta - center).angle
        let sweep = Angle.normalizeSigned((tb - center).angle - sa)
        let arc = Arc2(center: center, radius: radius, startAngle: sa, sweep: sweep)
        let na = aStartFar ? Segment2(a.start, ta) : Segment2(ta, a.end)
        let nb = bStartFar ? Segment2(b.start, tb) : Segment2(tb, b.end)
        return (na, arc, nb)
    }
}

// MARK: - Adaptive tessellation

/// Adaptive polyline sampling of a parametric curve on [t0, t1]: intervals are
/// bisected until the curve midpoint lies within `tolerance` of the chord.
func adaptiveSample(_ f: (Double) -> Vec2, from t0: Double, to t1: Double, tolerance: Double,
                    initialSegments: Int, maxDepth: Int = 16) -> [Vec2] {
    let tol = max(tolerance, Tolerance.length)
    let n = max(1, initialSegments)
    var out: [Vec2] = [f(t0)]
    func recurse(_ a: Double, _ pa: Vec2, _ b: Double, _ pb: Vec2, _ depth: Int) {
        let m = (a + b) * 0.5
        let pm = f(m)
        // Check two interior samples so inflections are not missed.
        let q1 = f(a + (b - a) * 0.25), q3 = f(a + (b - a) * 0.75)
        let chord = Segment2(pa, pb)
        let err = max(chord.distance(to: pm), chord.distance(to: q1), chord.distance(to: q3))
        if depth >= maxDepth || err <= tol {
            out.append(pb)
            return
        }
        recurse(a, pa, m, pm, depth + 1)
        recurse(m, pm, b, pb, depth + 1)
    }
    var prevT = t0
    var prevP = out[0]
    for i in 1...n {
        let t = t0 + (t1 - t0) * Double(i) / Double(n)
        let p = f(t)
        recurse(prevT, prevP, t, p, 0)
        prevT = t; prevP = p
    }
    return out
}

// MARK: - Ellipse

/// An elliptical arc: `point(atParam: t) = center + majorAxis·cos t + minorAxis·sin t`,
/// where `minorAxis = majorAxis.perpendicular · ratio`. The arc runs counter-clockwise
/// in parameter from `startParam` to `endParam` (end is taken modulo 2π after start;
/// equal values describe a full ellipse), matching the DXF convention.
public struct Ellipse2: Hashable, Codable, Sendable {
    public var center: Vec2
    /// Semi-major axis vector (its length is the semi-major radius).
    public var majorAxis: Vec2
    /// Minor / major radius ratio, in (0, 1].
    public var ratio: Double
    public var startParam: Double
    public var endParam: Double

    public init(center: Vec2, majorAxis: Vec2, ratio: Double, startParam: Double = 0, endParam: Double = 2 * .pi) {
        self.center = center; self.majorAxis = majorAxis; self.ratio = ratio
        self.startParam = startParam; self.endParam = endParam
    }

    public var minorAxis: Vec2 { majorAxis.perpendicular * ratio }
    /// Parametric span in (0, 2π].
    public var paramSpan: Double {
        let s = endParam - startParam
        if abs(s) >= Angle.twoPi - Tolerance.parameter { return Angle.twoPi }
        let n = Angle.normalize(s)
        return n <= Tolerance.parameter ? Angle.twoPi : n
    }
    public var isFull: Bool { paramSpan >= Angle.twoPi - Tolerance.parameter }

    public func point(atParam t: Double) -> Vec2 { center + majorAxis * cos(t) + minorAxis * sin(t) }
    public var start: Vec2 { point(atParam: startParam) }
    public var end: Vec2 { point(atParam: startParam + paramSpan) }

    /// True if parameter t lies within the arc's parametric range.
    func containsParam(_ t: Double) -> Bool {
        isFull || Angle.normalize(t - startParam) <= paramSpan + Tolerance.parameter
    }

    /// Axis-aligned bounds (exact: extreme parameters are computed analytically).
    public var bounds: Rect2 {
        var r = Rect2(points: [start, end])
        let m = majorAxis, n = minorAxis
        for base in [atan2(n.x, m.x), atan2(n.y, m.y)] {
            for t in [base, base + .pi] where containsParam(t) { r.include(point(atParam: t)) }
        }
        return r
    }

    /// Polyline approximation whose chord error is below `chordTolerance`.
    public func tessellate(chordTolerance: Double = 0.002) -> [Vec2] {
        let span = paramSpan
        let initial = max(4, Int((span / (Double.pi / 4)).rounded(.up)))
        return adaptiveSample({ self.point(atParam: self.startParam + $0) }, from: 0, to: span,
                              tolerance: chordTolerance, initialSegments: initial)
    }

    /// Image under an affine transform (exact for any non-singular affine map; the
    /// conjugate diameters are re-diagonalised into principal axes).
    public func transformed(_ t: Transform2) -> Ellipse2 {
        let c = t.apply(center)
        let u = t.applyVector(majorAxis), v = t.applyVector(minorAxis)
        // p(s) = c + u cos s + v sin s. Rotate the parameter to the principal axes.
        let t0 = 0.5 * atan2(2 * u.dot(v), u.dot(u) - v.dot(v))
        var a = u * cos(t0) + v * sin(t0)
        var b = u * (-sin(t0)) + v * cos(t0)
        var shift = t0 // original parameter s = s' + shift
        if b.lengthSquared > a.lengthSquared {
            // Swap so that `a` is the major axis: s = s'' + π/2 + shift.
            let na = b, nb = -a
            a = na; b = nb
            shift += .pi / 2
        }
        let la = a.length
        guard la > 0 else { return Ellipse2(center: c, majorAxis: .zero, ratio: 1, startParam: startParam, endParam: endParam) }
        let r = b.length / la
        let span = paramSpan
        if a.cross(b) >= 0 {
            let s0 = startParam - shift
            return Ellipse2(center: c, majorAxis: a, ratio: r, startParam: s0, endParam: s0 + span)
        } else {
            // Mirrored: p = c + a cos s' - |b|-perp sin s'  ⇒ negate the parameter to keep CCW order.
            let e0 = -(startParam - shift) - span
            return Ellipse2(center: c, majorAxis: a, ratio: r, startParam: e0, endParam: e0 + span)
        }
    }
}

// MARK: - B-spline / NURBS

/// A (possibly rational) B-spline curve evaluated with de Boor's algorithm.
///
/// Valid when `knots.count == controlPoints.count + degree + 1`, knots are
/// non-decreasing and (if present) `weights.count == controlPoints.count` with
/// positive weights. The curve's domain is `knots[degree]…knots[controlPoints.count]`.
public struct BSpline2: Hashable, Codable, Sendable {
    public var degree: Int
    public var controlPoints: [Vec2]
    public var knots: [Double]
    public var weights: [Double]?

    public init(degree: Int, controlPoints: [Vec2], knots: [Double], weights: [Double]? = nil) {
        self.degree = degree; self.controlPoints = controlPoints; self.knots = knots; self.weights = weights
    }

    /// Cubic Bézier segment as a clamped cubic B-spline.
    public static func cubicBezier(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2) -> BSpline2 {
        BSpline2(degree: 3, controlPoints: [p0, p1, p2, p3], knots: [0, 0, 0, 0, 1, 1, 1, 1])
    }

    /// Clamped uniform B-spline through-the-ends knot vector for `count` control points.
    public static func clampedUniformKnots(count: Int, degree: Int) -> [Double] {
        guard count > degree else { return [] }
        let inner = count - degree - 1
        var k = Array(repeating: 0.0, count: degree + 1)
        if inner > 0 { for i in 1...inner { k.append(Double(i) / Double(inner + 1)) } }
        k.append(contentsOf: Array(repeating: 1.0, count: degree + 1))
        return k
    }

    public var isValid: Bool {
        guard degree >= 1, controlPoints.count > degree, knots.count == controlPoints.count + degree + 1 else { return false }
        for i in 1..<knots.count where knots[i] < knots[i - 1] { return false }
        guard knots[controlPoints.count] > knots[degree] else { return false }
        if let w = weights { return w.count == controlPoints.count && w.allSatisfy { $0 > 0 && $0.isFinite } }
        return true
    }

    public var domain: ClosedRange<Double> { knots[degree]...knots[controlPoints.count] }

    /// Point at curve parameter u (clamped to the domain). Requires `isValid`.
    public func point(at u: Double) -> Vec2 {
        let p = degree, n = controlPoints.count
        let uu = min(max(u, knots[p]), knots[n])
        // Knot span k with knots[k] <= u < knots[k+1], restricted to [p, n-1].
        var k = p
        if uu >= knots[n] {
            k = n - 1
            while k > p && knots[k] >= knots[n] { k -= 1 }
        } else {
            var lo = p, hi = n
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if knots[mid] <= uu { lo = mid } else { hi = mid }
            }
            k = lo
        }
        // Homogeneous de Boor.
        var d: [(Double, Double, Double)] = (0...p).map { j in
            let i = j + k - p
            let w = weights?[i] ?? 1
            return (controlPoints[i].x * w, controlPoints[i].y * w, w)
        }
        if p >= 1 {
            for r in 1...p {
                for j in stride(from: p, through: r, by: -1) {
                    let i = j + k - p
                    let denom = knots[i + p - r + 1] - knots[i]
                    let alpha = denom > 0 ? (uu - knots[i]) / denom : 0
                    d[j] = ((1 - alpha) * d[j - 1].0 + alpha * d[j].0,
                            (1 - alpha) * d[j - 1].1 + alpha * d[j].1,
                            (1 - alpha) * d[j - 1].2 + alpha * d[j].2)
                }
            }
        }
        let w = d[p].2
        return w != 0 ? Vec2(d[p].0 / w, d[p].1 / w) : Vec2(d[p].0, d[p].1)
    }

    /// Polyline approximation with chord error below `chordTolerance`, sampling each
    /// non-empty knot span adaptively. Returns [] for an invalid spline.
    public func tessellate(chordTolerance: Double = 0.002) -> [Vec2] {
        guard isValid else { return [] }
        var out: [Vec2] = []
        let n = controlPoints.count
        for k in degree..<n where knots[k + 1] > knots[k] {
            let piece = adaptiveSample({ self.point(at: $0) }, from: knots[k], to: knots[k + 1],
                                       tolerance: chordTolerance, initialSegments: max(2, degree * 2))
            if out.isEmpty { out = piece } else { out.append(contentsOf: piece.dropFirst()) }
        }
        return out
    }

    /// Bounds of the control polygon (contains the curve by the convex hull property).
    public var controlBounds: Rect2 { Rect2(points: controlPoints) }

    /// Image under an affine transform (B-splines are affinely invariant).
    public func transformed(_ t: Transform2) -> BSpline2 {
        BSpline2(degree: degree, controlPoints: controlPoints.map(t.apply), knots: knots, weights: weights)
    }
}
