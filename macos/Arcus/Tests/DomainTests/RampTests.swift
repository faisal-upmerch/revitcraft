import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Ramps")
struct RampTests {
    /// Level 1 (0) to Level 2 (4 m) in the architectural template; a 0.5 m unconnected ramp keeps numbers small.
    func ramp(_ path: [Vec2], height: Double = 0.5, width: Double = 1.2, configure: ((inout TypeData) -> Void)? = nil) throws -> (BIMModel, ElementID, [ModelWarning]) {
        var (m, ids) = Fx.template()
        var rid: ElementID!
        let r = try Fx.commit(&m) { tx in
            var td = RampGeometry.defaultType(material: nil)
            configure?(&td)
            let type = tx.create(.elementTypes, name: "Test Ramp", data: .type(td))
            var rd = RampData(path: path, width: width)
            rd.unconnectedHeight = height
            rid = tx.create(.ramps, data: .ramp(rd), typeID: type, levelID: ids.levels[0])
            for left in [true, false] {
                var rail = RailingData(path: [])
                rail.followsHost = true; rail.hostSideLeft = left
                tx.create(.railings, data: .railing(rail), typeID: ids.systemTypes["Railing"], levelID: ids.levels[0], hostID: rid)
            }
        }
        return (m, rid, r.warnings)
    }

    @Test func straightRampAtMaximumSlope() throws {
        let (m, id, warnings) = try ramp([Vec2(0, 0), Vec2(6, 0)])
        let l = try #require(RampGeometry.layout(m[id]!, m))
        #expect(warnings.isEmpty)
        #expect(l.pieces.count == 1 && !l.pieces[0].isLanding)
        #expect(Fx.approx(l.slopedLength, 6) && Fx.approx(l.requiredLength, 6))
        #expect(Fx.approx(l.slope, 1.0 / 12))
        #expect(!l.isTooSteep)
        // Solid ramp: a wedge 6 × 1.2 × 0.5 / 2.
        let q = QuantityEngine.quantities(for: m[id]!, in: m)
        #expect(abs(q.volume! - 6 * 1.2 * 0.5 / 2) < 1e-9)
        #expect(Fx.approx(q.height!, 0.5) && Fx.approx(q.width!, 1.2) && Fx.approx(q.length!, 6))
        #expect(Fx.approx(q.area!, 7.2))
    }

    @Test func lengthMismatchWarnsInModelHealthAndStillCommits() throws {
        let (m, id, warnings) = try ramp([Vec2(0, 0), Vec2(4, 0)])
        #expect(m[id] != nil, "the ramp is committed")
        #expect(warnings.contains { $0.code == "ramp.length" && $0.elements == [id] })
        let health = ModelHealth.check(m)
        let w = try #require(health.first { $0.code == "ramp.length" })
        #expect(w.elements == [id])
        #expect(w.message.contains("6.00 m") && w.message.contains("4.00 m"))
        let l = try #require(RampGeometry.layout(m[id]!, m))
        #expect(l.isTooSteep && Fx.approx(l.slope, 0.125))
    }

    @Test func turnsBecomeLandingsAndLongRunsGetIntermediateLandings() throws {
        // L-shaped: 5 m then 5 m with a 1.2 m square landing at the corner.
        let (m, id, _) = try ramp([Vec2(0, 0), Vec2(5, 0), Vec2(5, 5)])
        let l = try #require(RampGeometry.layout(m[id]!, m))
        #expect(l.pieces.map(\.isLanding) == [false, true, false])
        #expect(Fx.approx(l.slopedLength, 10 - 1.2))
        #expect(Fx.approx(l.pieces[1].polygon.area, 1.2 * 1.2))
        #expect(Fx.approx(l.pieces[1].z0, 0.25) && Fx.approx(l.pieces[2].z1, 0.5))
        // A 20 m run with a 9 m maximum incline length: two 1.5 m landings, three runs of 17/3 m.
        let (m2, id2, _) = try ramp([Vec2(0, 0), Vec2(20, 0)], height: 1.2)
        let l2 = try #require(RampGeometry.layout(m2[id2]!, m2))
        #expect(l2.pieces.map(\.isLanding) == [false, true, false, true, false])
        #expect(Fx.approx(l2.slopedLength, 17))
        #expect(l2.pieces.filter { !$0.isLanding }.allSatisfy { Fx.approx($0.length, 17.0 / 3) })
    }

    @Test func railingsFollowTheRampSurface() throws {
        let (m, id, _) = try ramp([Vec2(0, 0), Vec2(5, 0), Vec2(5, 5)])
        let rails = m.hosted(by: id).filter { $0.category == .railings }
        #expect(rails.count == 2)
        for r in rails {
            let p = RailingGeometry.path(r, m)
            #expect(p.count >= 4)
            #expect(Fx.approx(p.first!.z, 0) && Fx.approx(p.last!.z, 0.5))
            #expect(zip(p, p.dropFirst()).allSatisfy { $0.z <= $1.z + 1e-9 }, "rails climb monotonically")
        }
        // The outer (right-hand, for a left turn) rail goes round the landing corner.
        let right = rails.first { $0.railing?.hostSideLeft == false }!
        #expect(RailingGeometry.path(right, m).contains { Fx.approx($0.xy, Vec2(5.55, -0.55)) })
    }

    @Test func thinRampIsASlopedSlab() throws {
        let (m, id, _) = try ramp([Vec2(0, 0), Vec2(6, 0)]) { $0.params[RampGeometry.shapeParam] = .text(RampShape.thin.rawValue) }
        let q = QuantityEngine.quantities(for: m[id]!, in: m)
        #expect(abs(q.volume! - 6 * 1.2 * RampGeometry.defaultThickness) < 1e-9)
    }

    @Test func planGraphicsCutAndBreak() throws {
        let (m, id, _) = try ramp([Vec2(0, 0), Vec2(12, 0)], height: 2)
        let lines = RampGeometry.planLines(m[id]!, m, cutZ: 1.2)
        #expect(lines.breakLine != nil)
        #expect(!lines.below.isEmpty && !lines.above.isEmpty)
        #expect(lines.walk.first == Vec2(0, 0) && lines.walk.last == Vec2(12, 0))
    }

    @Test func invalidRampsAreRejected() throws {
        var (m, ids) = Fx.template()
        let tx = TransactionContext(model: m, name: "Ramp")
        tx.create(.ramps, data: .ramp(RampData(path: [Vec2(0, 0)])), levelID: ids.levels[0])
        #expect(throws: TransactionError.self) { try tx.commit() }
        let tx2 = TransactionContext(model: m, name: "Ramp")
        tx2.create(.ramps, data: .ramp(RampData(path: [Vec2(0, 0), Vec2(5, 0)], width: 0.4)), levelID: ids.levels[0])
        #expect(throws: TransactionError.self) { try tx2.commit() }
        try Fx.commit(&m) { tx in tx.create(.ramps, data: .ramp(RampData(path: [Vec2(0, 0), Vec2(9, 0)], topLevelID: ids.levels[1])), levelID: ids.levels[0]) }
        #expect(m.elements(.ramps).count == 1)
    }

    @Test func rampParametersAndTransform() throws {
        var (m, id, _) = try ramp([Vec2(0, 0), Vec2(6, 0)])
        let entries = Parameters.instanceEntries(m[id]!, m)
        #expect(entries.contains { $0.id == ParameterID("ramp.width") })
        #expect(entries.contains { $0.id == ParameterID("ramp.requiredLength") })
        try Fx.commit(&m) { tx in tx.update(id) { ElementTransform.apply(.translation(Vec2(1, 2)), to: &$0) } }
        #expect(m[id]!.ramp!.path == [Vec2(1, 2), Vec2(7, 2)])
    }
}
