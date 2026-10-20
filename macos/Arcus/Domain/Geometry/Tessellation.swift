import Foundation

// VIS: how finely curved geometry is cut into straight pieces for display. One quality per view detail level: Coarse is
// simple, Medium smooth, Fine very smooth. The segment count follows the size (a chord tolerance) with a floor per full
// circle so small round parts (legs, knobs, wheels) still read as round, and a cap so huge arcs stay light.

/// Chord-tolerance tessellation settings for arcs, circles and revolves.
public struct TessellationQuality: Hashable, Sendable {
    /// Largest distance between a chord and the curve it replaces (m).
    public var chordTolerance: Double
    /// Fewest segments for a full circle (radii from `smallRadius` up).
    public var minSegments: Int
    /// Most segments for a full circle.
    public var maxSegments: Int

    public init(chordTolerance: Double, minSegments: Int, maxSegments: Int) {
        self.chordTolerance = chordTolerance; self.minSegments = minSegments; self.maxSegments = maxSegments
    }

    /// Coarse views: 24 segments a circle at least (15° each), 2 mm chord.
    public static let coarse = TessellationQuality(chordTolerance: 0.002, minSegments: 24, maxSegments: 64)
    /// Medium views: 36 a circle at least (10° each), 0.5 mm chord.
    public static let medium = TessellationQuality(chordTolerance: 0.0005, minSegments: 36, maxSegments: 128)
    /// Fine views: 72 a circle at least (5° each), 0.2 mm chord.
    public static let fine = TessellationQuality(chordTolerance: 0.0002, minSegments: 72, maxSegments: 256)

    /// Below this radius (1/2": dowels, pins, holes, screws, axles) the floor shrinks with the radius, down to 18
    /// segments: small round parts are too small to show more, and Boolean cuts of machining stay quick.
    public static let smallRadius = 0.0127

    /// Segments for a full circle of radius `r`.
    public func fullCircleSegments(radius r: Double) -> Int {
        guard r > Tolerance.length else { return 4 }
        let floor = r < Self.smallRadius ? max(18, Int((Double(minSegments) * r / Self.smallRadius).rounded(.up))) : minSegments
        var byChord = floor
        if r > chordTolerance {
            let step = 2 * acos(max(-1, min(1, 1 - chordTolerance / r)))
            if step > 1e-9 { byChord = Int((Angle.twoPi / step).rounded(.up)) }
        }
        return max(floor, min(maxSegments, byChord))
    }

    /// Segments for an arc of radius `r` sweeping `sweep` radians (at least 1).
    public func segments(radius r: Double, sweep: Double = Angle.twoPi) -> Int {
        let full = Double(fullCircleSegments(radius: r))
        return max(1, Int((full * min(abs(sweep), Angle.twoPi) / Angle.twoPi - 1e-9).rounded(.up)))
    }

    /// Largest angle one segment may turn through on a circle of radius `r`.
    public func stepAngle(radius r: Double) -> Double { Angle.twoPi / Double(fullCircleSegments(radius: r)) }
}

extension Arc2 {
    /// VIS: the arc as a polyline at a view quality (both ends exact).
    public func tessellate(quality: TessellationQuality) -> [Vec2] {
        let n = quality.segments(radius: radius, sweep: sweep)
        return (0...n).map { point(at: Double($0) / Double(n)) }
    }
}

/// VIS: finer polylines for curves that were stored as points (sketched or generated arcs, rounded corners, turned
/// profiles). Runs of short, equal, gently turning segments are curve samples; each of their segments is split along
/// the circle through it and its neighbours until no piece turns more than the quality allows. Corners, straight edges
/// and the points themselves are kept exactly, so the shape only gets rounder, never different.
public enum CurveRefinement {
    /// Largest turn at a vertex that still counts as a sample of a smooth curve (a 15-sided circle turns 24°).
    public static let smoothTurn = 24.5 * Double.pi / 180
    /// Adjacent segments of a curve sample differ in length by at most this ratio.
    static let lengthRatio = 2.0
    /// Upper bound on the points a refined polyline may have.
    static let maxPoints = 8192

    /// The polyline with its curve runs refined for `quality`; `closed` loops wrap around.
    public static func refine(_ pts: [Vec2], closed: Bool, quality: TessellationQuality) -> [Vec2] {
        let n = pts.count
        guard n >= 3 else { return pts }
        func at(_ i: Int) -> Vec2? {
            if closed { return pts[((i % n) + n) % n] }
            return i >= 0 && i < n ? pts[i] : nil
        }
        // Vertices that sit on a smooth curve.
        var smooth = [Bool](repeating: false, count: n)
        var any = false
        for i in 0..<n {
            guard let a = at(i - 1), let c = at(i + 1) else { continue }
            let b = pts[i]
            let l0 = a.distance(to: b), l1 = b.distance(to: c)
            guard l0 > Tolerance.length, l1 > Tolerance.length, max(l0, l1) <= lengthRatio * min(l0, l1) else { continue }
            let d0 = (b - a) / l0, d1 = (c - b) / l1
            let turn = acos(max(-1, min(1, d0.dot(d1))))
            if turn > 1e-4 && turn <= smoothTurn { smooth[i] = true; any = true }
        }
        guard any else { return pts }
        func smoothAt(_ i: Int) -> Bool { closed ? smooth[((i % n) + n) % n] : (i >= 0 && i < n && smooth[i]) }
        func length(_ i: Int) -> Double? {
            guard let a = at(i), let b = at(i + 1) else { return nil }
            return a.distance(to: b)
        }
        var out: [Vec2] = []
        out.reserveCapacity(n * 2)
        let last = closed ? n : n - 1
        for i in 0..<last {
            let p = pts[i]
            out.append(p)
            guard let q = at(i + 1), out.count < maxPoints else { continue }
            let len = p.distance(to: q)
            guard len > Tolerance.length else { continue }
            let sA = smoothAt(i), sB = smoothAt(i + 1)
            // A segment between two curve samples, or the first/last chord of a curve (as long as its neighbour chord).
            let curved = (sA && sB) || (sA && (length(i - 1).map { len <= 1.5 * $0 } ?? false))
                || (sB && (length(i + 1).map { len <= 1.5 * $0 } ?? false))
            guard curved else { continue }
            let ca = sA ? at(i - 1).flatMap { circle($0, p, q) } : nil
            let cb = sB ? at(i + 2).flatMap { circle(p, q, $0) } : nil
            guard ca != nil || cb != nil else { continue }
            let r = [ca?.r, cb?.r].compactMap { $0 }.reduce(0, +) / Double([ca, cb].compactMap { $0 }.count)
            guard r > Tolerance.length, len < 2 * r else { continue }
            let theta = 2 * asin(min(1, len / (2 * r)))
            let k = min(64, Int((theta / quality.stepAngle(radius: r) - 1e-6).rounded(.up)))
            guard k > 1 else { continue }
            for j in 1..<k {
                let t = Double(j) / Double(k)
                let pa = ca.map { arcPoint($0, p, q, t) }, pb = cb.map { arcPoint($0, p, q, t) }
                switch (pa, pb) {
                case let (x?, y?): out.append(x.lerp(to: y, t: t))
                case let (x?, nil): out.append(x)
                case let (nil, y?): out.append(y)
                default: break
                }
            }
        }
        if !closed { out.append(pts[n - 1]) }
        return out
    }

    /// The circle through three points (nil when they are almost in line).
    static func circle(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> (c: Vec2, r: Double)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let scale = max(a.distance(to: b), b.distance(to: c))
        guard abs(d) > 1e-9 * scale * scale else { return nil }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        let ctr = Vec2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                       (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        return (ctr, ctr.distance(to: a))
    }

    /// The point a fraction `t` of the way from p to q along the shorter arc of circle `c` through them.
    static func arcPoint(_ c: (c: Vec2, r: Double), _ p: Vec2, _ q: Vec2, _ t: Double) -> Vec2 {
        let a0 = (p - c.c).angle
        let da = Angle.normalizeSigned((q - c.c).angle - a0)
        let rp = p.distance(to: c.c), rq = q.distance(to: c.c)
        return c.c + Vec2.fromAngle(a0 + da * t, length: rp + (rq - rp) * t)
    }
}
