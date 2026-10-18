import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Sketches, floors, roofs and ceilings")
struct SlabRoofTests {
    static func l(_ a: Vec2, _ b: Vec2) -> Curve2 { .line(Segment2(a, b)) }
    static func loop(_ pts: [Vec2]) -> [Curve2] { (0..<pts.count).map { l(pts[$0], pts[($0 + 1) % pts.count]) } }
    static let square = loop([Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)])

    enum BadSketch: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case empty, open, degenerate, bowTie, holeOutside, nested, crossingLoops
        var testDescription: String { rawValue }
        var sketch: Sketch {
            switch self {
            case .empty: return Sketch(loops: [])
            case .open: return Sketch(loops: [Array(SlabRoofTests.square.dropLast())])
            case .degenerate: return Sketch(loops: [SlabRoofTests.loop([Vec2(0, 0), Vec2(5, 0), Vec2(10, 0)])])
            case .bowTie: return Sketch(loops: [SlabRoofTests.loop([Vec2(0, 0), Vec2(10, 10), Vec2(10, 0), Vec2(2, 8)])])
            case .holeOutside: return Sketch(loops: [SlabRoofTests.square, SlabRoofTests.loop([Vec2(20, 0), Vec2(22, 0), Vec2(22, 2), Vec2(20, 2)])])
            case .nested: return Sketch(loops: [SlabRoofTests.square, SlabRoofTests.loop([Vec2(1, 1), Vec2(9, 1), Vec2(9, 9), Vec2(1, 9)]),
                                                SlabRoofTests.loop([Vec2(2, 2), Vec2(8, 2), Vec2(8, 8), Vec2(2, 8)])])
            case .crossingLoops: return Sketch(loops: [SlabRoofTests.square, SlabRoofTests.loop([Vec2(8, 4), Vec2(12, 4), Vec2(12, 6), Vec2(8, 6)])])
            }
        }
        var expected: SketchError {
            switch self {
            case .empty: .empty
            case .open: .openLoop(0)
            case .degenerate: .degenerateLoop(0)
            case .bowTie: .selfIntersecting(0)
            case .holeOutside: .loopOutsideBoundary
            case .nested: .nestedLoops
            case .crossingLoops: .loopsIntersect
            }
        }
    }

    @Test(arguments: BadSketch.allCases)
    func invalidSketchesReportTheirError(_ bad: BadSketch) {
        guard case .failure(let e) = bad.sketch.profile() else { Issue.record("expected \(bad.expected)"); return }
        #expect(e == bad.expected)
        #expect(!e.description.isEmpty)
    }

    @Test(arguments: [BadSketch.open, .bowTie, .holeOutside])
    func invalidFloorSketchRejectsCommit(_ bad: BadSketch) {
        let (m, ids) = Fx.template()
        let tx = TransactionContext(model: m, name: "Floor")
        tx.create(.floors, data: .slab(SlabData(boundary: bad.sketch)), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        #expect(throws: TransactionError.self) { try tx.commit() }
    }

    @Test func unorderedAndReversedCurvesFormALoop() throws {
        let s = Self.square
        let shuffled = [s[2], s[0].reversed, s[3], s[1].reversed]
        let p = try Sketch(loops: [shuffled]).profile().get()
        #expect(Fx.approx(p.area, 100))
        #expect(Sketch.orderLoop([s[0], s[2]]) == nil)
    }

    @Test func sketchWithHoleAndArcs() throws {
        let hole = Self.loop([Vec2(4, 4), Vec2(6, 4), Vec2(6, 6), Vec2(4, 6)])
        let p = try Sketch(loops: [Self.square, hole]).profile().get()
        #expect(p.holes.count == 1)
        #expect(Fx.approx(p.area, 96))
        // Semicircular end: 10 × 10 square with a half-disc on the east side.
        let arc = Curve2.arc(Arc2(center: Vec2(10, 5), radius: 5, startAngle: -.pi / 2, sweep: .pi))
        let d = try Sketch(loops: [[Self.l(Vec2(0, 0), Vec2(10, 0)), arc, Self.l(Vec2(10, 10), Vec2(0, 10)), Self.l(Vec2(0, 10), Vec2(0, 0))]]).profile().get()
        #expect(abs(d.area - (100 + .pi * 12.5)) < 0.05)
    }

    // MARK: Floors

    @Test(arguments: [("Concrete Slab 200mm", 0.2), ("Screed on Concrete 250mm", 0.25), ("Timber Floor 300mm", 0.3)])
    func floorQuantities(_ type: String, _ t: Double) throws {
        var (m, ids) = Fx.template()
        var f: ElementID!
        let hole = Self.loop([Vec2(4, 4), Vec2(6, 4), Vec2(6, 6), Vec2(4, 6)])
        try Fx.commit(&m) { tx in
            f = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [Self.square, hole]), offset: -0.05)), typeID: ids.floorTypes[type], levelID: ids.levels[1])
        }
        let q = QuantityEngine.quantities(for: m[f]!, in: m)
        #expect(Fx.approx(q.area!, 96))
        #expect(Fx.approx(q.perimeter!, 48))
        #expect(Fx.approx(q.thickness!, t, 1e-12))
        #expect(Fx.approx(q.volume!, 96 * t, 1e-9))
        #expect(Fx.approx(q.elevationTop!, 3.95) && Fx.approx(q.elevationBottom!, 3.95 - t))
        #expect(Fx.approx(abs(SlabGeometry.mesh(m[f]!, m).signedVolume), 96 * t, 1e-6))
        #expect(Fx.approx(q.materials.reduce(0) { $0 + $1.volume }, 96 * t, 1e-9))
    }

    @Test func slopeArrowTiltsTheTopSurface() throws {
        var (m, ids) = Fx.template()
        var f: ElementID!
        try Fx.commit(&m) { tx in
            var s = SlabData(boundary: Sketch(loops: [Self.square]))
            s.slopeArrow = SlopeArrow(tail: Vec2(0, 5), head: Vec2(10, 5), slope: 0.02)
            f = tx.create(.floors, data: .slab(s), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        #expect(Fx.approx(SlabGeometry.topZ(m[f]!, at: Vec2(0, 3), m)!, 0))
        #expect(Fx.approx(SlabGeometry.topZ(m[f]!, at: Vec2(10, 3), m)!, 0.2))
        #expect(Fx.approx(Parameters.value(ParameterID("slab.slope"), of: m[f]!, m)!.doubleValue!, 0.02))
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("slab.slope"), to: .double(0.05), on: f, in: tx) }
        #expect(Fx.approx(SlabGeometry.topZ(m[f]!, at: Vec2(10, 3), m)!, 0.5))
    }

    @Test func ceilingSitsAtItsOffset() throws {
        var (m, ids) = Fx.template()
        var c: ElementID!
        try Fx.commit(&m) { tx in
            c = tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(loops: [Self.square]), offset: 2.7)), typeID: ids.ceilingTypes["Plasterboard Ceiling"], levelID: ids.levels[0])
        }
        let q = QuantityEngine.quantities(for: m[c]!, in: m)
        #expect(Fx.approx(q.elevationBottom!, 2.7), "a ceiling's offset is its underside")
        #expect(Fx.approx(q.thickness!, 0.0125))
    }

    // MARK: Roofs

    @Test(arguments: [15.0, 30.0, 45.0])
    func hipRoofRidgeAndArea(_ degrees: Double) throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        let a = degrees * .pi / 180
        try Fx.commit(&m) { tx in
            r = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [a, a, a, a])),
                          typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
        }
        #expect(Fx.approx(RoofGeometry.ridgeHeight(m[r]!, m)!, 4.0 + 4 * tan(a), 1e-6))
        let q = QuantityEngine.quantities(for: m[r]!, in: m)
        #expect(Fx.approx(q.area!, 80 / cos(a), 1e-6))
        #expect(Fx.approx(q.thickness!, 0.3, 1e-12))
        #expect(Fx.approx(q.perimeter!, 36))
        #expect(Fx.approx(RoofGeometry.topZ(m[r]!, at: Vec2(5, 4), m)!, 4.0 + 4 * tan(a), 1e-6))
        #expect(Fx.approx(RoofGeometry.topZ(m[r]!, at: Vec2(1, 4), m)!, 4.0 + tan(a), 1e-6))
        #expect(Fx.approx(Parameters.value(ParameterID("roof.slope"), of: m[r]!, m)!.doubleValue!, tan(a), 1e-9))
    }

    @Test func gableRoofHasFullLengthRidge() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        let a = atan(0.5)
        try Fx.commit(&m) { tx in
            r = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [a, nil, a, nil])),
                          typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
        }
        #expect(Fx.approx(RoofGeometry.ridgeHeight(m[r]!, m)!, 4.0 + 2.0, 1e-6))
        // At the gable ends the roof still reaches the ridge.
        #expect(Fx.approx(RoofGeometry.topZ(m[r]!, at: Vec2(0.01, 4), m)!, 6.0, 1e-6))
        #expect(Fx.approx(RoofGeometry.topZ(m[r]!, at: Vec2(9.99, 2), m)!, 5.0, 1e-6))
        let q = QuantityEngine.quantities(for: m[r]!, in: m)
        #expect(Fx.approx(q.area!, 80 / cos(a), 1e-6))
        // Changing the slope keeps gable edges unsloped.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("roof.slope"), to: .double(1), on: r, in: tx) }
        #expect(m[r]!.roof!.edgeSlopes.map { $0 == nil } == [false, true, false, true])
        #expect(Fx.approx(RoofGeometry.ridgeHeight(m[r]!, m)!, 8.0, 1e-6))
        let tx = TransactionContext(model: m, name: "Flat")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("roof.slope"), to: .double(0), on: r, in: tx) }
    }

    @Test func roofOpeningReducesArea() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        let a = 30 * Double.pi / 180
        try Fx.commit(&m) { tx in
            let fp = Sketch(loops: [Self.loop([Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]), Self.loop([Vec2(1, 1), Vec2(2, 1), Vec2(2, 2), Vec2(1, 2)])])
            r = tx.create(.roofs, data: .roof(RoofData(footprint: fp, edgeSlopes: [a, a, a, a])), typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
        }
        #expect(RoofGeometry.openings(m[r]!).count == 1)
        #expect(Fx.approx(QuantityEngine.quantities(for: m[r]!, in: m).volume!, (80 - 1) * 0.3, 1e-9))
    }

    @Test func wallTopAttachesToFloorUnderside() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!, f: ElementID!
        try Fx.commit(&m) { tx in
            f = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(-1, -1), max: Vec2(9, 3))))),
                          typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[1])
            w = Fx.wall(tx, ids, .zero, Vec2(8, 0), top: nil) { $0.unconnectedHeight = 6 }
        }
        #expect(Fx.approx(QuantityEngine.quantities(for: m[w]!, in: m).area!, 48))
        try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.attachedTopIDs = [f] } }
        #expect(Parameters.value(ParameterID("wall.topAttached"), of: m[w]!, m) == .bool(true))
        #expect(Fx.approx(AttachmentQueries.undersideZ(m[f]!, at: Vec2(4, 0), m)!, 3.8))
        #expect(Fx.approx(QuantityEngine.quantities(for: m[w]!, in: m).area!, 8 * 3.8, 1e-6))
        #expect(Fx.approx(abs(WallGeometry.solid(m[w]!, m).signedVolume), 8 * 3.8 * 0.2, 1e-6))
    }

    @Test func wallTopAttachesToHipRoof() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!, r: ElementID!
        let a = 30 * Double.pi / 180
        try Fx.commit(&m) { tx in
            r = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: Vec2(-1, -1), max: Vec2(11, 9))), edgeSlopes: [a, a, a, a])),
                          typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
            w = Fx.wall(tx, ids, Vec2(0, 4), Vec2(10, 4), top: nil) { $0.unconnectedHeight = 10; $0.attachedTopIDs = [] }
        }
        try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.attachedTopIDs = [r] } }
        let top = WallGeometry.topProfile(m[w]!, WallGeometry.frame(m[w]!, m)!, m)
        let maxZ = top.points.map(\.y).max()!
        // The ridge along y = 4 is 5 m in from the eaves; the wall stops under the roof thickness.
        #expect(maxZ <= 4.0 + 5 * tan(a) - 0.3 + 1e-6)
        #expect(maxZ > 4.0)
        #expect(QuantityEngine.quantities(for: m[w]!, in: m).area! < 10 * 10)
    }
}
