import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct TriangulatorTests {
    @Test func squareWithHole() {
        let p = Profile2(outer: rect(0, 0, 10, 10), holes: [rect(3, 3, 6, 7)])
        let r = Triangulator.triangulate(p)
        #expect(r.triangles.count % 3 == 0)
        #expect(approx(triangleArea(r.points, r.triangles), p.area, 1e-9))
        for t in stride(from: 0, to: r.triangles.count, by: 3) {
            let a = r.points[r.triangles[t]], b = r.points[r.triangles[t + 1]], c = r.points[r.triangles[t + 2]]
            #expect((b - a).cross(c - a) >= 0)
        }
    }

    @Test func clockwiseInputAndCollinearDuplicates() {
        let pts = [Vec2(0, 0), Vec2(0, 4), Vec2(0, 4), Vec2(2, 4), Vec2(4, 4), Vec2(4, 2), Vec2(4, 0), Vec2(2, 0), Vec2(0, 0)]
        let r = Triangulator.triangulate(Polygon2(pts))
        #expect(approx(triangleArea(r.points, r.triangles), 16, 1e-9))
    }

    @Test func concaveComb() {
        var pts: [Vec2] = [Vec2(0, 0)]
        for i in 0..<10 {
            let x = Double(i)
            pts += [Vec2(x + 0.25, 5), Vec2(x + 0.75, 5), Vec2(x + 1, 0.5)]
        }
        pts[pts.count - 1] = Vec2(10, 0)
        let poly = Polygon2(pts)
        let r = Triangulator.triangulate(poly)
        #expect(approx(triangleArea(r.points, r.triangles), poly.area, 1e-9))
    }

    @Test func multipleHolesAndLargeCoordinates() {
        let o = Vec2(10_000, 10_000)
        let t = Transform2.translation(o)
        let outer = rect(0, 0, 20, 10).transformed(t)
        let holes = (0..<5).map { rect(Double($0) * 4 + 1, 2, Double($0) * 4 + 3, 8).transformed(t) }
        let p = Profile2(outer: outer, holes: holes)
        let r = Triangulator.triangulate(p)
        #expect(approx(triangleArea(r.points, r.triangles), p.area, 1e-6))
        #expect(r.triangles.count / 3 <= (4 + 20) + 2 * 5 - 2)
    }

    @Test func holeTouchingOuterVertex() {
        let outer = rect(0, 0, 10, 10)
        let hole = Polygon2([Vec2(0, 5), Vec2(3, 3), Vec2(3, 7)]) // touches the left edge
        let p = Profile2(outer: outer, holes: [hole])
        let r = Triangulator.triangulate(p)
        #expect(approx(triangleArea(r.points, r.triangles), p.area, 1e-9))
    }

    @Test func thousandVertexStarIsFast() {
        let n = 1000
        let pts = (0..<n).map { i -> Vec2 in
            let a = Double(i) / Double(n) * 2 * .pi
            let r = i % 2 == 0 ? 10.0 : 6.0 + 3.0 * sin(Double(i) * 0.37)
            return Vec2(cos(a) * r, sin(a) * r)
        }
        let poly = Polygon2(pts)
        let clock = ContinuousClock()
        let t0 = clock.now
        let r = Triangulator.triangulate(poly)
        let dt = clock.now - t0
        #expect(r.triangles.count / 3 == n - 2)
        #expect(approx(triangleArea(r.points, r.triangles), poly.area, 1e-7))
        #expect(dt < .milliseconds(500))
    }

    @Test func degenerateInput() {
        #expect(Triangulator.triangulate(Polygon2([Vec2(0, 0), Vec2(1, 1)])).triangles.isEmpty)
        let flat = Triangulator.triangulate(Polygon2([Vec2(0, 0), Vec2(1, 0), Vec2(2, 0)]))
        #expect(approx(triangleArea(flat.points, flat.triangles), 0))
    }
}

@Suite struct PolygonBooleanTests {
    let a = Profile2(outer: rect(0, 0, 4, 4))
    let b = Profile2(outer: rect(2, 2, 6, 6))

    @Test func unionOfOverlappingSquares() {
        let u = PolygonBoolean.union([a, b])
        #expect(u.count == 1)
        #expect(approx(u[0].area, 28))
        #expect(u[0].outer.count == 8)
    }

    @Test func intersectionAndDifference() {
        let i = PolygonBoolean.intersection([a], [b])
        #expect(i.count == 1 && approx(i[0].area, 4))
        let d = PolygonBoolean.difference([a], [b])
        #expect(d.count == 1 && approx(d[0].area, 12))
        #expect(PolygonBoolean.intersection([a], [Profile2(outer: rect(10, 10, 11, 11))]).isEmpty)
    }

    @Test func differenceCreatesHole() {
        let big = Profile2(outer: rect(0, 0, 10, 10))
        let d = PolygonBoolean.difference([big], [Profile2(outer: rect(4, 4, 6, 6))])
        #expect(d.count == 1)
        #expect(d[0].holes.count == 1)
        #expect(approx(d[0].area, 96))
    }

    @Test func unionWithHolesAndIslands() {
        let ring = Profile2(outer: rect(0, 0, 10, 10), holes: [rect(2, 2, 8, 8)])
        let island = Profile2(outer: rect(4, 4, 6, 6))
        let u = PolygonBoolean.union([ring, island])
        #expect(u.count == 2)
        #expect(approx(u.reduce(0) { $0 + $1.area }, 64 + 4))
        // Filling the hole merges everything.
        let filled = PolygonBoolean.union([ring, Profile2(outer: rect(1, 1, 9, 9))])
        #expect(filled.count == 1 && filled[0].holes.isEmpty && approx(filled[0].area, 100))
    }

    @Test func sharedEdgesMerge() {
        let u = PolygonBoolean.union([Profile2(outer: rect(0, 0, 1, 1)), Profile2(outer: rect(1, 0, 2, 1)), Profile2(outer: rect(0, 1, 2, 2))])
        #expect(u.count == 1 && approx(u[0].area, 4) && u[0].outer.count == 4)
    }

    @Test func differenceSplitsIntoPieces() {
        let bar = Profile2(outer: rect(0, 0, 10, 1))
        let d = PolygonBoolean.difference([bar], [Profile2(outer: rect(4, -1, 6, 2))])
        #expect(d.count == 2)
        #expect(d.allSatisfy { approx($0.area, 4) })
    }

    @Test func booleanAtLargeCoordinates() {
        let t = Transform2.translation(Vec2(-10_000, 10_000))
        let u = PolygonBoolean.union([a.transformed(t), b.transformed(t)])
        #expect(u.count == 1 && approx(u[0].area, 28, 1e-6))
    }
}

@Suite struct OffsetAndClipTests {
    @Test func growSquare() {
        let r = rect(0, 0, 4, 4).offset(by: 1)
        #expect(r.count == 1)
        #expect(approx(r[0].area, 36))
        #expect(r[0].isCounterClockwise)
    }

    @Test func shrinkSquareAndCollapse() {
        let r = rect(0, 0, 4, 4).offset(by: -1)
        #expect(r.count == 1 && approx(r[0].area, 4))
        #expect(rect(0, 0, 4, 4).offset(by: -2.5).isEmpty)
        // Clockwise input behaves the same.
        #expect(approx(rect(0, 0, 4, 4).reversed.offset(by: -1)[0].area, 4))
    }

    @Test func shrinkSplitsDumbbell() {
        // Two 4×4 squares joined by a 1 m wide neck.
        let pts = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 1.5), Vec2(8, 1.5), Vec2(8, 0), Vec2(12, 0),
                   Vec2(12, 4), Vec2(8, 4), Vec2(8, 2.5), Vec2(4, 2.5), Vec2(4, 4), Vec2(0, 4)]
        let r = Polygon2(pts).offset(by: -0.75)
        #expect(r.count == 2)
        #expect(r.allSatisfy { approx($0.area, 2.5 * 2.5, 1e-6) })
    }

    @Test func growLShapeMiter() {
        let l = Polygon2([Vec2(0, 0), Vec2(4, 0), Vec2(4, 1), Vec2(1, 1), Vec2(1, 4), Vec2(0, 4)])
        let r = l.offset(by: 0.5)
        #expect(r.count == 1)
        // Mitered growth of an orthogonal polygon: exact rectilinear offset.
        let expected = Polygon2([Vec2(-0.5, -0.5), Vec2(4.5, -0.5), Vec2(4.5, 1.5), Vec2(1.5, 1.5), Vec2(1.5, 4.5), Vec2(-0.5, 4.5)])
        #expect(approx(r[0].area, expected.area, 1e-9))
    }

    @Test func sharpCornerIsBeveled() {
        let spike = Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(0, 1)])
        let r = spike.offset(by: 0.1)
        #expect(r.count == 1)
        // The tip at (10,0) has a miter ~2 m long; the bevel keeps it within 4×d.
        let far = r[0].points.map { $0.distance(to: Vec2(10, 0)) }.min()!
        #expect(far <= 0.4 + 1e-9)
        #expect(r[0].bounds.max.x < 10.5)
    }

    @Test func polylineOffset() {
        let pts = [Vec2(0, 0), Vec2(5, 0), Vec2(5, 5)]
        let o = PolylineOffset.offset(pts, by: 1)
        #expect(o.count == 3)
        #expect(approx(o[0], Vec2(0, 1)) && approx(o[1], Vec2(4, 1)) && approx(o[2], Vec2(4, 5)))
        let r = PolylineOffset.offset(pts, by: -1)
        #expect(approx(r[1], Vec2(6, -1)))
        #expect(PolylineOffset.offset([Vec2(1, 1), Vec2(1, 1)], by: 1).isEmpty)
    }

    @Test func sutherlandHodgman() {
        let tri = Polygon2([Vec2(-2, -2), Vec2(6, -2), Vec2(2, 6)])
        let c = tri.clipped(to: Rect2(min: .zero, max: Vec2(4, 4)))
        #expect(c != nil)
        #expect(c!.bounds.min.x >= -1e-12 && c!.bounds.max.x <= 4 + 1e-12)
        let inside = rect(1, 1, 2, 2).clipped(to: Rect2(min: .zero, max: Vec2(4, 4)))
        #expect(approx(inside!.area, 1))
        #expect(rect(10, 10, 11, 11).clipped(to: Rect2(min: .zero, max: Vec2(4, 4))) == nil)
    }

    @Test func liangBarsky() {
        let r = Rect2(min: .zero, max: Vec2(10, 10))
        let s = Segment2(Vec2(-5, 5), Vec2(15, 5)).clipped(to: r)!
        #expect(approx(s.start, Vec2(0, 5)) && approx(s.end, Vec2(10, 5)))
        #expect(Segment2(Vec2(-5, -5), Vec2(-1, 20)).clipped(to: r) == nil)
        let d = Segment2(Vec2(-5, -5), Vec2(15, 15)).clipped(to: r)!
        #expect(approx(d.start, .zero) && approx(d.end, Vec2(10, 10)))
    }
}

@Suite struct SpatialGridTests {
    @Test func insertQueryRemove() {
        var g = SpatialGrid<Int>(cellSize: 1)
        for i in 0..<100 {
            let x = Double(i % 10) * 2, y = Double(i / 10) * 2
            g.insert(i, bounds: Rect2(min: Vec2(x, y), max: Vec2(x + 0.5, y + 0.5)))
        }
        #expect(g.count == 100)
        #expect(g.query(Rect2(min: Vec2(-0.1, -0.1), max: Vec2(2.1, 0.1))) == [0, 1])
        #expect(g.query(point: Vec2(3, 3), radius: 0.8) == [11])
        #expect(g.query(point: Vec2(3, 3), radius: 0.6).isEmpty)
        g.remove(11)
        #expect(g.query(point: Vec2(3, 3), radius: 0.8).isEmpty)
        #expect(g.count == 99)
    }

    @Test func hugeItemsGoToOverflowAndDeduplicate() {
        var g = SpatialGrid<String>(cellSize: 0.01)
        g.insert("site", bounds: Rect2(min: Vec2(-1e6, -1e6), max: Vec2(1e6, 1e6)))
        g.insert("door", bounds: Rect2(min: Vec2(0, 0), max: Vec2(0.05, 0.05)))
        #expect(g.query(Rect2(min: Vec2(0.01, 0.01), max: Vec2(0.02, 0.02))) == ["site", "door"])
        g.remove("site")
        #expect(g.query(Rect2(min: Vec2(0.01, 0.01), max: Vec2(0.02, 0.02))) == ["door"])
        // Re-insert moves the item.
        g.insert("door", bounds: Rect2(min: Vec2(5, 5), max: Vec2(6, 6)))
        #expect(g.query(Rect2(min: .zero, max: Vec2(1, 1))).isEmpty)
        #expect(g.count == 1)
    }

    @Test func twentyThousandItems() {
        var g = SpatialGrid<Int>(cellSize: 2)
        var state: UInt64 = 42
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        var boxes: [Rect2] = []
        for i in 0..<20_000 {
            let p = Vec2(rnd() * 500, rnd() * 500)
            let b = Rect2(min: p, max: p + Vec2(rnd() * 3, rnd() * 3))
            boxes.append(b)
            g.insert(i, bounds: b)
        }
        let q = Rect2(min: Vec2(100, 100), max: Vec2(120, 130))
        let brute = boxes.indices.filter { boxes[$0].intersects(q) }
        #expect(g.query(q) == brute)
    }
}
