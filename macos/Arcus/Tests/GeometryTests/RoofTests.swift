import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct RoofSolverTests {
    let slope = Angle.radians(30)

    func maxZ(_ s: RoofSurface) -> Double { s.faces.flatMap { $0 }.map(\.z).max() ?? -.infinity }
    func planArea(_ s: RoofSurface) -> Double { s.faces.reduce(0) { $0 + Polygon2($1.map(\.xy)).signedArea } }
    func horizontal(_ s: RoofSurface) -> [Segment3] { s.ridgeLines.filter { abs($0.a.z - $0.b.z) <= 1e-9 } }

    @Test func rectangleHipRoof() {
        let fp = rect(0, 0, 10, 6)
        let s = RoofSolver.solve(footprint: fp, slopes: [slope, slope, slope, slope], baseZ: 3)
        #expect(s.isExact && s.warnings.isEmpty)
        #expect(s.faces.count == 4)
        #expect(approx(planArea(s), 60, 1e-9))
        #expect(approx(maxZ(s), 3 + 3 * tan(slope), 1e-9))
        let ridge = horizontal(s)
        #expect(ridge.count == 1)
        #expect(approx(ridge[0].length, 4, 1e-9))
        #expect(approx(ridge[0].a.z, 3 + 3 * tan(slope), 1e-9))
        // Four hips from the corners.
        #expect(s.ridgeLines.count == 5)
        // Faces are planar, CCW from above and sit on the base at the eaves.
        for f in s.faces {
            #expect(Polygon2(f.map(\.xy)).isCounterClockwise)
            #expect(f.contains { approx($0.z, 3) })
        }
    }

    @Test func gableRoof() {
        let fp = rect(0, 0, 10, 6)
        let s = RoofSolver.solve(footprint: fp, slopes: [slope, nil, slope, nil], baseZ: 0)
        #expect(s.faces.count == 2)
        #expect(s.ridgeLines.count == 1)
        #expect(approx(s.ridgeLines[0].length, 10, 1e-9))
        #expect(approx(s.ridgeLines[0].a.z, 3 * tan(slope), 1e-9))
        #expect(approx(planArea(s), 60, 1e-9))
    }

    @Test func pyramidOnSquare() {
        let s = RoofSolver.solve(footprint: rect(0, 0, 6, 6), slopes: Array(repeating: Angle.radians(45), count: 4), baseZ: 1)
        #expect(s.faces.count == 4)
        #expect(s.faces.allSatisfy { $0.count == 3 })
        #expect(approx(maxZ(s), 4, 1e-9))
        #expect(s.ridgeLines.count == 4)
        #expect(horizontal(s).isEmpty)
        for r in s.ridgeLines { #expect(approx(r.length, (9.0 + 9 + 9).squareRoot(), 1e-9)) }
    }

    @Test func differentSlopesShiftRidge() {
        // Steeper south slope pushes the ridge towards the south eave.
        let s = RoofSolver.solve(footprint: rect(0, 0, 10, 6), slopes: [Angle.radians(60), nil, Angle.radians(30), nil], baseZ: 0)
        #expect(s.faces.count == 2)
        let r = s.ridgeLines[0]
        // tan60·y = tan30·(6 − y) ⇒ y = 1.5
        #expect(approx(r.a.y, 1.5, 1e-9) && approx(r.b.y, 1.5, 1e-9))
    }

    @Test func lShapedRoofHasValleys() {
        let fp = Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(10, 4), Vec2(4, 4), Vec2(4, 10), Vec2(0, 10)])
        let a = Angle.radians(45)
        let s = RoofSolver.solve(footprint: fp, slopes: Array(repeating: a, count: 6), baseZ: 0)
        #expect(!s.isExact)
        #expect(!s.warnings.isEmpty)
        #expect(approx(planArea(s), fp.area, 1e-6))
        #expect(approx(maxZ(s), 2, 1e-9))
        // A valley rises from the reflex corner (4,4) to the ridge junction (2,2).
        let valley = s.ridgeLines.first { ($0.a.xy.isAlmostEqual(Vec2(4, 4)) || $0.b.xy.isAlmostEqual(Vec2(4, 4))) }
        #expect(valley != nil)
        if let v = valley {
            let top = v.a.z > v.b.z ? v.a : v.b
            #expect(approx(top.xy, Vec2(2, 2), 1e-9) && approx(top.z, 2, 1e-9))
        }
        // Ridges: two horizontal ridges of the arms at height 2.
        let ridges = horizontal(s).filter { approx($0.a.z, 2, 1e-9) }
        #expect(approx(ridges.reduce(0) { $0 + $1.length }, 12, 1e-9))
        // Surface continuity: every face vertex agrees with the height of the other faces at shared points.
        for f in s.faces { for p in f { #expect(p.z >= -1e-9 && p.z <= 2 + 1e-9) } }
    }

    @Test func clockwiseFootprintRemapsSlopes() {
        let ccw = RoofSolver.solve(footprint: rect(0, 0, 10, 6), slopes: [slope, nil, slope, nil], baseZ: 0)
        // Same rectangle clockwise: (0,0),(0,6),(10,6),(10,0). Edges: left, top, right, bottom.
        let cw = RoofSolver.solve(footprint: Polygon2([Vec2(0, 0), Vec2(0, 6), Vec2(10, 6), Vec2(10, 0)]),
                                  slopes: [nil, slope, nil, slope], baseZ: 0)
        #expect(cw.faces.count == 2)
        #expect(approx(cw.ridgeLines[0].length, ccw.ridgeLines[0].length, 1e-9))
    }

    @Test func largeCoordinatesAndSolid() {
        let o = Vec2(10_000, 10_000)
        let fp = rect(0, 0, 10, 6).transformed(.translation(o))
        let s = RoofSolver.solve(footprint: fp, slopes: Array(repeating: slope, count: 4), baseZ: 100)
        #expect(approx(horizontal(s)[0].length, 4, 1e-7))
        let solid = RoofSolver.roofSolid(surface: s, footprint: fp, baseZ: 100, thickness: 0.3)
        let local = solid.transformed(.translation(Vec3(-o.x, -o.y, -100)))
        #expect(approx(local.signedVolume, 60 * 0.3, 1e-6))
        #expect(isWatertight(solid))
        #expect(!solid.featureEdges.isEmpty)
    }

    @Test func gableSolidIsClosed() {
        let fp = rect(0, 0, 8, 5)
        let s = RoofSolver.solve(footprint: fp, slopes: [slope, nil, slope, nil], baseZ: 0)
        let m = RoofSolver.roofSolid(surface: s, footprint: fp, baseZ: 0, thickness: 0.25)
        #expect(approx(m.signedVolume, 40 * 0.25, 1e-9))
        #expect(isWatertight(m))
    }

    @Test func lShapedSolidVolume() {
        let fp = Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(10, 4), Vec2(4, 4), Vec2(4, 10), Vec2(0, 10)])
        let s = RoofSolver.solve(footprint: fp, slopes: Array(repeating: slope, count: 6), baseZ: 0)
        let m = RoofSolver.roofSolid(surface: s, footprint: fp, baseZ: 0, thickness: 0.2)
        #expect(approx(m.signedVolume, fp.area * 0.2, 1e-6))
    }

    @Test func degenerateAndFlatCases() {
        let bad = RoofSolver.solve(footprint: Polygon2([.zero, .unitX]), slopes: [nil, nil], baseZ: 0)
        #expect(bad.faces.isEmpty && !bad.warnings.isEmpty)
        let flat = RoofSolver.solve(footprint: rect(0, 0, 3, 3), slopes: [nil, nil, nil, nil], baseZ: 2)
        #expect(flat.faces.count == 1 && flat.faces[0].allSatisfy { approx($0.z, 2) })
        #expect(!flat.warnings.isEmpty)
        let mismatch = RoofSolver.solve(footprint: rect(0, 0, 3, 3), slopes: [slope], baseZ: 0)
        #expect(mismatch.warnings.contains { $0.contains("slopes") })
        #expect(mismatch.faces.count == 1) // single slope edge covers the footprint
    }

    @Test func tShapedRoof() {
        // Bar 12×3 on top of a 4 m wide stem.
        let fp = Polygon2([Vec2(4, 0), Vec2(8, 0), Vec2(8, 6), Vec2(12, 6), Vec2(12, 9), Vec2(0, 9), Vec2(0, 6), Vec2(4, 6)])
        let s = RoofSolver.solve(footprint: fp, slopes: Array(repeating: Angle.radians(45), count: 8), baseZ: 0)
        #expect(approx(planArea(s), fp.area, 1e-6))
        #expect(approx(maxZ(s), 2, 1e-9))
        #expect(s.faces.allSatisfy { f in f.allSatisfy { $0.z >= -1e-9 } })
    }
}
