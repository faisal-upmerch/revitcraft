import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct CurveIntersectionTests {
    @Test func lineLineCrossing() {
        let a = Curve2.line(Segment2(Vec2(0, 0), Vec2(10, 0)))
        let b = Curve2.line(Segment2(Vec2(3, -2), Vec2(3, 2)))
        let pts = a.intersections(with: b)
        #expect(pts.count == 1)
        #expect(approx(pts[0], Vec2(3, 0)))
    }

    @Test func lineLineDisjointAndTouching() {
        let a = Curve2.line(Segment2(Vec2(0, 0), Vec2(10, 0)))
        #expect(a.intersections(with: .line(Segment2(Vec2(11, -1), Vec2(11, 1)))).isEmpty)
        // Touching at the end within tolerance.
        let t = a.intersections(with: .line(Segment2(Vec2(10 + 5e-6, 0), Vec2(10, 5))))
        #expect(t.count == 1)
    }

    @Test func collinearOverlapReportsOverlapEnds() {
        let a = Curve2.line(Segment2(Vec2(0, 0), Vec2(10, 0)))
        let b = Curve2.line(Segment2(Vec2(12, 0), Vec2(4, 0)))
        let pts = a.intersections(with: b)
        #expect(pts.count == 2)
        #expect(approx(pts[0], Vec2(4, 0)) && approx(pts[1], Vec2(10, 0)))
    }

    @Test func lineArcTwoPointsOrderedAlongSelf() {
        let arc = Curve2.arc(Arc2(center: .zero, radius: 5, startAngle: 0, sweep: 2 * .pi))
        let line = Curve2.line(Segment2(Vec2(10, 3), Vec2(-10, 3)))
        let pts = line.intersections(with: arc)
        #expect(pts.count == 2)
        #expect(approx(pts[0], Vec2(4, 3)) && approx(pts[1], Vec2(-4, 3)))
        // From the arc's perspective the order follows the arc (CCW from angle 0).
        let back = arc.intersections(with: line)
        #expect(approx(back[0], Vec2(4, 3)))
    }

    @Test func lineArcRespectsSweepAndTangent() {
        let upper = Curve2.arc(Arc2(center: .zero, radius: 5, startAngle: 0, sweep: .pi))
        let low = Curve2.line(Segment2(Vec2(-10, -3), Vec2(10, -3)))
        #expect(upper.intersections(with: low).isEmpty)
        let tangent = Curve2.line(Segment2(Vec2(-10, 5), Vec2(10, 5)))
        let t = upper.intersections(with: tangent)
        #expect(t.count == 1 && approx(t[0], Vec2(0, 5)))
    }

    @Test func arcArcIntersections() {
        let a = Curve2.arc(Arc2(center: .zero, radius: 5, startAngle: 0, sweep: 2 * .pi))
        let b = Curve2.arc(Arc2(center: Vec2(8, 0), radius: 5, startAngle: 0, sweep: 2 * .pi))
        let pts = a.intersections(with: b)
        #expect(pts.count == 2)
        #expect(pts.allSatisfy { approx($0.x, 4) && approx(abs($0.y), 3) })
        // Concentric, different radius.
        let c = Curve2.arc(Arc2(center: .zero, radius: 3, startAngle: 0, sweep: 1))
        #expect(a.intersections(with: c).isEmpty)
        // Co-circular overlap.
        let d = Curve2.arc(Arc2(center: .zero, radius: 5, startAngle: 1, sweep: 1))
        let q = Curve2.arc(Arc2(center: .zero, radius: 5, startAngle: 1.5, sweep: 1))
        let ov = d.intersections(with: q)
        #expect(ov.count == 2)
    }

    @Test func largeCoordinatesIntersection() {
        let o = Vec2(10_000, 10_000)
        let a = Curve2.line(Segment2(o, o + Vec2(10, 0)))
        let b = Curve2.line(Segment2(o + Vec2(2.5, -1), o + Vec2(2.5, 1)))
        let pts = a.intersections(with: b)
        #expect(pts.count == 1 && approx(pts[0], o + Vec2(2.5, 0), 1e-9))
    }
}

@Suite struct CurveEditingTests {
    @Test func parameterOfPoints() {
        let l = Curve2.line(Segment2(Vec2(0, 0), Vec2(4, 0)))
        #expect(approx(l.parameter(of: Vec2(1, 3)), 0.25))
        let arc = Curve2.arc(Arc2(center: .zero, radius: 1, startAngle: 0, sweep: .pi))
        #expect(approx(arc.parameter(of: Vec2(0, 1)), 0.5))
        let cw = Curve2.arc(Arc2(center: .zero, radius: 1, startAngle: .pi, sweep: -.pi))
        #expect(approx(cw.parameter(of: Vec2(0, 1)), 0.5))
        #expect(approx(cw.parameter(of: Vec2(1, 0)), 1))
    }

    @Test func splitAndShortPieces() {
        let l = Curve2.line(Segment2(Vec2(0, 0), Vec2(10, 0)))
        let parts = l.split(at: 0.3)
        #expect(parts != nil)
        #expect(approx(parts!.0.end, Vec2(3, 0)) && approx(parts!.1.start, Vec2(3, 0)))
        #expect(l.split(at: 0.00005) == nil) // 0.5 mm piece < short curve limit
        #expect(l.split(at: 1) == nil)
        let arc = Curve2.arc(Arc2(center: .zero, radius: 2, startAngle: 0, sweep: .pi))
        let ap = arc.split(at: 0.5)!
        #expect(approx(ap.0.length + ap.1.length, arc.length))
        #expect(approx(ap.0.end, Vec2(0, 2)))
    }

    @Test func subcurve() {
        let arc = Curve2.arc(Arc2(center: .zero, radius: 1, startAngle: 0, sweep: .pi))
        let s = arc.subcurve(from: 0.25, to: 0.75)
        #expect(approx(s.start, Vec2(cos(.pi / 4), sin(.pi / 4))))
        #expect(approx(s.length, .pi / 2))
    }

    @Test func extendLineToMeetLine() {
        let a = Curve2.line(Segment2(Vec2(0, 0), Vec2(4, 0)))
        let wall = Curve2.line(Segment2(Vec2(10, -1), Vec2(10, 1)))
        let ext = a.trimmedOrExtended(toMeet: wall, atEnd: true)
        #expect(ext != nil && approx(ext!.end, Vec2(10, 0)) && approx(ext!.start, .zero))
        // Trim the start.
        let cut = Curve2.line(Segment2(Vec2(1, -1), Vec2(1, 1)))
        let tr = a.trimmedOrExtended(toMeet: cut, atEnd: false)
        #expect(tr != nil && approx(tr!.start, Vec2(1, 0)))
        // Parallel: nil.
        #expect(a.trimmedOrExtended(toMeet: .line(Segment2(Vec2(0, 1), Vec2(5, 1))), atEnd: true) == nil)
        // Would reverse the segment: nil.
        let behind = Curve2.line(Segment2(Vec2(-3, -1), Vec2(-3, 1)))
        #expect(a.trimmedOrExtended(toMeet: behind, atEnd: true) == nil)
    }

    @Test func extendArcToMeetLine() {
        let arc = Curve2.arc(Arc2(center: .zero, radius: 1, startAngle: 0, sweep: .pi / 4))
        let line = Curve2.line(Segment2(Vec2(0, -5), Vec2(0, 5)))
        let ext = arc.trimmedOrExtended(toMeet: line, atEnd: true)
        #expect(ext != nil)
        #expect(approx(ext!.end, Vec2(0, 1)))
        #expect(approx(ext!.asArc!.sweep, .pi / 2))
    }

    @Test func filletRightAngle() {
        let a = Segment2(Vec2(0, 0), Vec2(10, 0))
        let b = Segment2(Vec2(10, 0), Vec2(10, 10))
        let f = Fillet.lines(a, b, radius: 2)
        #expect(f != nil)
        guard let f else { return }
        #expect(approx(f.a.end, Vec2(8, 0)))
        #expect(approx(f.b.start, Vec2(10, 2)))
        #expect(approx(f.arc.center, Vec2(8, 2)))
        #expect(approx(f.arc.start, Vec2(8, 0)) && approx(f.arc.end, Vec2(10, 2)))
        #expect(approx(abs(f.arc.sweep), .pi / 2))
        #expect(Fillet.lines(a, b, radius: 20) == nil)
        #expect(Fillet.lines(a, Segment2(Vec2(0, 1), Vec2(5, 1)), radius: 1) == nil)
    }

    @Test func filletNonTouchingLinesExtends() {
        let a = Segment2(Vec2(0, 0), Vec2(5, 0))
        let b = Segment2(Vec2(10, 10), Vec2(10, 3))
        let f = Fillet.lines(a, b, radius: 1)!
        #expect(approx(f.a.start, Vec2(0, 0)) && approx(f.a.end, Vec2(9, 0)))
        #expect(approx(f.b.start, Vec2(10, 10)) && approx(f.b.end, Vec2(10, 1)))
    }
}

@Suite struct FreeformCurveTests {
    @Test func ellipseBasics() {
        let e = Ellipse2(center: Vec2(1, 2), majorAxis: Vec2(4, 0), ratio: 0.5)
        #expect(approx(e.point(atParam: .pi / 2), Vec2(1, 4)))
        let b = e.bounds
        #expect(approx(b.min, Vec2(-3, 0)) && approx(b.max, Vec2(5, 4)))
        let pts = e.tessellate(chordTolerance: 0.001)
        #expect(pts.count > 20)
        let area = Polygon2(pts).area
        #expect(abs(area - .pi * 4 * 2) < 0.05)
        for p in pts {
            let q = p - Vec2(1, 2)
            #expect(approx(q.x * q.x / 16 + q.y * q.y / 4, 1, 1e-9))
        }
    }

    @Test func ellipseRotatedBoundsAndTransform() {
        let e = Ellipse2(center: .zero, majorAxis: Vec2(3, 3), ratio: 0.5, startParam: 0, endParam: .pi)
        let pts = e.tessellate(chordTolerance: 0.0005)
        let tb = Rect2(points: pts)
        #expect(approx(e.bounds.max.y, tb.max.y, 1e-3))
        let t = Transform2.rotation(0.7, around: Vec2(1, 1)) * .scale(2, 2)
        let et = e.transformed(t)
        for s in stride(from: 0.0, through: Double.pi, by: 0.3) {
            let p = t.apply(e.point(atParam: s))
            // Every transformed point must lie on the transformed ellipse's arc.
            let samples = et.tessellate(chordTolerance: 1e-5)
            let d = Polyline.distance(samples, p)
            #expect(d < 1e-3)
        }
        #expect(approx(et.start, t.apply(e.start), 1e-9))
        #expect(approx(et.end, t.apply(e.end), 1e-9))
        // Mirror keeps the same point set and swaps nothing visible.
        let m = Transform2.mirror(through: .zero, direction: .unitX)
        let em = e.transformed(m)
        #expect(approx(Rect2(points: em.tessellate()).min.y, -Rect2(points: pts).max.y, 1e-3))
    }

    @Test func ellipseNonUniformTransform() {
        let circle = Ellipse2(center: .zero, majorAxis: Vec2(1, 0), ratio: 1)
        let t = Transform2.rotation(0.3) * Transform2.scale(3, 1)
        let e = circle.transformed(t)
        #expect(approx(e.majorAxis.length, 3, 1e-9))
        #expect(approx(e.ratio, 1.0 / 3, 1e-9))
    }

    @Test func bezierMatchesBernstein() {
        let p0 = Vec2(0, 0), p1 = Vec2(1, 2), p2 = Vec2(3, 2), p3 = Vec2(4, 0)
        let b = BSpline2.cubicBezier(p0, p1, p2, p3)
        #expect(b.isValid)
        for t in [0.0, 0.2, 0.5, 0.9, 1.0] {
            let u = 1 - t
            let expected = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
            #expect(approx(b.point(at: t), expected, 1e-12))
        }
        let pts = b.tessellate(chordTolerance: 0.001)
        #expect(approx(pts.first!, p0) && approx(pts.last!, p3))
        // Chord error: every mid-chord point is close to the curve.
        for i in 1..<pts.count {
            let mid = pts[i - 1].midpoint(pts[i])
            var best = Double.infinity
            for k in 0...2000 { best = min(best, b.point(at: Double(k) / 2000).distance(to: mid)) }
            #expect(best < 0.0015)
        }
    }

    @Test func rationalQuarterCircle() {
        let w = 1 / 2.0.squareRoot()
        let s = BSpline2(degree: 2, controlPoints: [Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)],
                         knots: [0, 0, 0, 1, 1, 1], weights: [1, w, 1])
        for p in s.tessellate(chordTolerance: 1e-4) { #expect(approx(p.length, 1, 1e-12)) }
        #expect(!BSpline2(degree: 3, controlPoints: [.zero, .unitX], knots: [0, 1]).isValid)
        #expect(BSpline2(degree: 3, controlPoints: [.zero, .unitX], knots: [0, 1]).tessellate().isEmpty)
    }

    @Test func clampedUniformSpline() {
        let cps = [Vec2(0, 0), Vec2(1, 1), Vec2(2, -1), Vec2(3, 1), Vec2(4, 0)]
        let s = BSpline2(degree: 3, controlPoints: cps, knots: BSpline2.clampedUniformKnots(count: 5, degree: 3))
        #expect(s.isValid)
        let pts = s.tessellate()
        #expect(approx(pts.first!, cps.first!) && approx(pts.last!, cps.last!))
        #expect(s.controlBounds.contains(Rect2(points: pts)))
    }
}

@Suite struct SnapMathTests {
    @Test func perpendicularFeet() {
        let l = Curve2.line(Segment2(Vec2(0, 0), Vec2(10, 0)))
        #expect(approx(SnapMath.perpendicularFoot(from: Vec2(3, 5), to: l)!, Vec2(3, 0)))
        #expect(SnapMath.perpendicularFoot(from: Vec2(12, 5), to: l) == nil)
        let arc = Curve2.arc(Arc2(center: .zero, radius: 2, startAngle: 0, sweep: .pi))
        #expect(approx(SnapMath.perpendicularFoot(from: Vec2(0, 5), to: arc)!, Vec2(0, 2)))
        // Point below: the near foot is off the arc, the far one is on it.
        #expect(approx(SnapMath.perpendicularFoot(from: Vec2(0, -5), to: arc)!, Vec2(0, 2)))
    }

    @Test func tangentsAndQuadrants() {
        let circle = Arc2(center: .zero, radius: 1, startAngle: 0, sweep: 2 * .pi)
        let t = SnapMath.tangentPoints(from: Vec2(2, 0), to: circle)
        #expect(t.count == 2)
        for p in t {
            #expect(approx((p - Vec2(2, 0)).dot(p), 0, 1e-9))
        }
        #expect(SnapMath.tangentPoints(from: Vec2(0.5, 0), to: circle).isEmpty)
        let half = Arc2(center: .zero, radius: 1, startAngle: 0, sweep: .pi)
        #expect(SnapMath.tangentPoints(from: Vec2(2, 0), to: half).count == 1)
        let q = SnapMath.quadrantPoints(of: Arc2(center: .zero, radius: 1, startAngle: -0.1, sweep: .pi))
        #expect(q.count == 2 && approx(q[0], Vec2(1, 0)) && approx(q[1], Vec2(0, 1)))
        #expect(approx(SnapMath.nearest(on: .arc(half), to: Vec2(0, -3)), Vec2(1, 0)) || approx(SnapMath.nearest(on: .arc(half), to: Vec2(0, -3)), Vec2(-1, 0)))
    }
}

/// Test-only polyline helpers.
enum Polyline {
    static func distance(_ pts: [Vec2], _ p: Vec2) -> Double {
        var best = Double.infinity
        for i in 1..<pts.count { best = min(best, Segment2(pts[i - 1], pts[i]).distance(to: p)) }
        return best
    }
}
