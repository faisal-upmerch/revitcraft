import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct RobustnessTests {
    @Test func hlrEdgePiercingInclinedSlab() {
        let slab = MeshBuilder.slab(Profile2(outer: rect(0, 0, 4, 4)), bottom: PlaneZ(a: 0, b: 1, c: 0), top: PlaneZ(a: 0, b: 1, c: 0.1))
        let pole = Mesh.box(Box3(min: Vec3(1.9, 1.9, -1), max: Vec3(2.1, 2.1, 5)))
        let view = ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: Vec3(0, -10, 0), near: 0, far: 100)
        let edges = HiddenLineRenderer.render([HLRInput(tag: 1, mesh: slab), HLRInput(tag: 2, mesh: pole)], projection: view)
        let poleEdges = edges.filter { $0.tag == 2 }
        // The pole emerges from the slab's top surface at height 2.0 (z = y + 0.1 at y = 1.9),
        // less the depth tolerance times the surface's depth gradient (1 m per m).
        let emerge = 2.0 - HiddenLineRenderer.depthTolerance
        #expect(approx(poleEdges.reduce(0) { $0 + $1.segment.length }, 0.4 + 2 * (1 + 5 - emerge), 1e-9))
        let emerging = poleEdges.filter { abs($0.segment.start.x - 1.9) < 1e-9 && $0.segment.length > 2 }
        #expect(emerging.count == 1)
        #expect(approx(min(emerging[0].segment.start.y, emerging[0].segment.end.y), emerge, 1e-9))
    }

    @Test func emptyInputsEverywhere() {
        #expect(PlanarArrangement(segments: []).faces.isEmpty)
        #expect(PlanarArrangement(segments: [Segment2(.zero, .zero)]).faces.isEmpty)
        #expect(BoundaryCleanup.unionBoundary(of: []).isEmpty)
        #expect(BoundaryCleanup.clipSegments([], outside: [rect(0, 0, 1, 1)]).isEmpty)
        #expect(BoundaryCleanup.clipSegments([Segment2(.zero, Vec2(1, 0))], outside: []).count == 1)
        #expect(PolygonBoolean.union([]).isEmpty)
        #expect(PolygonBoolean.intersection([], [Profile2(outer: rect(0, 0, 1, 1))]).isEmpty)
        #expect(approx(PolygonBoolean.difference([Profile2(outer: rect(0, 0, 1, 1))], []).first?.area ?? 0, 1))
        #expect(HiddenLineRenderer.render([], projection: .topDown(z: 0, depth: 1)).isEmpty)
        #expect(MeshSection.section(.empty, plane: .horizontal(z: 0)).isEmpty)
        #expect(Polygon2([]).offset(by: 1).isEmpty)
    }

    @Test func booleanDeterminism() {
        let shapes = (0..<8).map { i -> Profile2 in
            let a = Double(i) * 0.7
            let c = Vec2(cos(a) * 3, sin(a) * 3)
            return Profile2(outer: Polygon2((0..<6).map { c + Vec2.fromAngle(Double($0) * .pi / 3 + a, length: 2) }))
        }
        let u1 = PolygonBoolean.union(shapes)
        let u2 = PolygonBoolean.union(shapes)
        #expect(u1 == u2)
        #expect(u1.count == 1)
        // Union area never exceeds the sum and is at least the largest piece.
        let sum = shapes.reduce(0) { $0 + $1.area }
        #expect(u1[0].area < sum && u1[0].area > shapes[0].area)
        // Inclusion–exclusion for two shapes.
        let i01 = PolygonBoolean.intersection([shapes[0]], [shapes[1]]).reduce(0) { $0 + $1.area }
        let u01 = PolygonBoolean.union([shapes[0], shapes[1]]).reduce(0) { $0 + $1.area }
        #expect(approx(u01, shapes[0].area + shapes[1].area - i01, 1e-9))
        let d01 = PolygonBoolean.difference([shapes[0]], [shapes[1]]).reduce(0) { $0 + $1.area }
        #expect(approx(d01, shapes[0].area - i01, 1e-9))
    }

    @Test func nearToleranceArrangement() {
        // A room whose walls miss each other by 3 µm and overshoot by 6 µm.
        let e = 3e-6
        let segs = [
            Segment2(Vec2(0, 0), Vec2(4 + 2 * e, 0)), Segment2(Vec2(4, -e), Vec2(4, 3)),
            Segment2(Vec2(4 + e, 3), Vec2(0, 3)), Segment2(Vec2(0, 3 + e), Vec2(0, e)),
        ]
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 1)
        #expect(approx(arr.faces[0].area, 12, 1e-4))
    }

    @Test func offsetAtLargeCoordinatesAndHoles() {
        let p = rect(10_000, 10_000, 10_004, 10_004)
        let g = p.offset(by: 0.5)
        #expect(g.count == 1 && approx(g[0].area, 25, 1e-6))
        // Growing a U until its arms close creates an enclosed hole loop.
        let u = Polygon2([Vec2(0, 0), Vec2(5, 0), Vec2(5, 5), Vec2(4, 5), Vec2(4, 1), Vec2(1, 1), Vec2(1, 5), Vec2(0, 5)])
        let closed = u.offset(by: 0.3)
        #expect(closed.count == 1) // arms 3 m apart do not touch yet
        let wide = Polygon2([Vec2(0, 0), Vec2(5, 0), Vec2(5, 5), Vec2(3, 5), Vec2(3, 1), Vec2(2, 1), Vec2(2, 5), Vec2(0, 5)])
        let fused = wide.offset(by: 0.6)
        #expect(fused.count == 1) // the 1 m slot closes from the top, no hole
        #expect(fused[0].isCounterClockwise)
    }

    @Test func curveOpsDeterministicOrder() {
        let circle = Curve2.arc(Arc2(center: .zero, radius: 2, startAngle: 0, sweep: 2 * .pi))
        let chord = Curve2.line(Segment2(Vec2(-3, 1), Vec2(3, 1)))
        #expect(chord.intersections(with: circle) == chord.intersections(with: circle))
        let pts = chord.intersections(with: circle)
        #expect(pts[0].x < pts[1].x)
        let rev = chord.reversed.intersections(with: circle)
        #expect(rev[0].x > rev[1].x)
    }
}
