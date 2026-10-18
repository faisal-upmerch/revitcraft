import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// I4: RevitCraft's datum grips: grid 3D/2D extents, Add Elbow, alignment locks, and section depth and flip.
@Suite("Datum grips")
struct DatumGripsTests {
    struct Env { var model: BIMModel; var plan: ElementID; var grids: [ElementID] }

    /// Three parallel vertical grids from y = 0 to 10 at x = 0, 5 and 10.
    func env() throws -> Env {
        var (m, ids) = Fx.template()
        var grids: [ElementID] = []
        try Fx.commit(&m) { tx in
            grids = [0.0, 5, 10].enumerated().map { k, x in
                tx.create(.grids, name: "\(k + 1)", data: .grid(GridData(curve: .line(Segment2(Vec2(x, 0), Vec2(x, 10))), bubbleAtStart: true, bubbleAtEnd: true)))
            }
        }
        return Env(model: m, plan: ids.planViews[ids.levels[0]]!, grids: grids)
    }

    func run(_ m: inout BIMModel, _ body: (TransactionContext) -> Void) throws { try Fx.commit(&m) { tx in body(tx) } }
    func control(_ e: Env, _ id: ElementID, _ kind: Grip.Kind) -> Grip? {
        GripService.controls(for: e.model[id]!, e.model, view: e.model[e.plan], pixel: 0.01).first { $0.kind == kind }
    }

    @Test func olderGridsDecodeWithoutExtentsOrLocks() throws {
        let json = #"{"curve":{"line":{"_0":{"start":{"x":0,"y":0},"end":{"x":0,"y":10}}}},"bubbleAtStart":true,"bubbleAtEnd":false}"#
        let g = try? JSONDecoder().decode(GridData.self, from: Data(json.utf8))
        let fresh = GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(0, 10))))
        let round = try JSONDecoder().decode(GridData.self, from: JSONEncoder().encode(fresh))
        #expect(round == fresh && round.viewExtents == nil && round.lockStart == nil)
        if let g { #expect(g.viewExtents == nil && !g.isLocked(atEnd: true)) }
    }

    @Test func switchingAnEndTo2DLetsItMoveInThisViewOnly() throws {
        var e = try env()
        let id = e.grids[0]
        let ends = GripService.grips(for: e.model[id]!, e.model, viewKind: .floorPlan, viewID: e.plan)
        #expect(ends.filter { $0.kind == .start || $0.kind == .end }.allSatisfy { !$0.isOn }, "hollow: model (3D) extents")
        let switch3D = try #require(control(e, id, .gridExtents(atEnd: true)))
        try run(&e.model) { GripService.toggle(switch3D, in: $0) }
        let end = try #require(GripService.grips(for: e.model[id]!, e.model, viewKind: .floorPlan, viewID: e.plan).first { $0.kind == .end })
        #expect(end.isOn, "filled: 2D in this view")
        try run(&e.model) { GripService.apply(end, to: Vec2(0, 7), in: $0) }
        let g = try #require(e.model[id]?.grid)
        #expect(Fx.approx(g.curve(in: e.plan).end, Vec2(0, 7)), "the view shows the 2D end")
        #expect(Fx.approx(g.curve.end, Vec2(0, 10)), "the model end stays")
        // Back to 3D: the view follows the model again.
        let back = try #require(control(e, id, .gridExtents(atEnd: true)))
        #expect(back.isOn)
        try run(&e.model) { GripService.toggle(back, in: $0) }
        #expect(Fx.approx(e.model[id]!.grid!.curve(in: e.plan).end, Vec2(0, 10)) && e.model[id]!.grid!.viewExtents == nil)
    }

    @Test func lockedEndsMoveWithTheEndTheyAlignWith() throws {
        var e = try env()
        let id = e.grids[0]
        let lock = try #require(control(e, id, .gridLock(atEnd: true)), "aligned ends get a padlock")
        #expect(!lock.isOn)
        try run(&e.model) { GripService.toggle(lock, in: $0) }
        #expect(e.model[id]!.grid!.isLocked(atEnd: true))
        let end = try #require(GripService.grips(for: e.model[id]!, e.model, viewKind: .floorPlan, viewID: e.plan).first { $0.kind == .end })
        try run(&e.model) { GripService.apply(end, to: Vec2(0, 12), in: $0) }
        for g in e.grids { #expect(Fx.approx(e.model[g]!.grid!.curve.end.y, 12)) }
        // Unlocked, an end moves alone.
        let unlock = try #require(control(e, id, .gridLock(atEnd: true)))
        try run(&e.model) { GripService.toggle(unlock, in: $0) }
        let end2 = try #require(GripService.grips(for: e.model[id]!, e.model, viewKind: .floorPlan, viewID: e.plan).first { $0.kind == .end })
        try run(&e.model) { GripService.apply(end2, to: Vec2(0, 13), in: $0) }
        #expect(Fx.approx(e.model[id]!.grid!.curve.end.y, 13) && Fx.approx(e.model[e.grids[1]]!.grid!.curve.end.y, 12))
    }

    @Test func addElbowJogsTheBubbleAsideAndDrags() throws {
        var e = try env()
        let id = e.grids[1]
        let add = try #require(control(e, id, .addElbow(atEnd: false)))
        try run(&e.model) { GripService.toggle(add, in: $0) }
        let o = try #require(e.model[id]!.grid!.extent(in: e.plan)?.elbowStart)
        #expect(Fx.approx(abs(o.x), 0.008 * Double(e.model[e.plan]!.view!.scale)) && Fx.approx(o.y, 0), "across the grid by 8 mm on paper")
        #expect(control(e, id, .addElbow(atEnd: false)) == nil, "the control gives way to the elbow's grip")
        let grip = try #require(GripService.grips(for: e.model[id]!, e.model, viewKind: .floorPlan, viewID: e.plan).first { $0.kind == .gridElbow(atEnd: false) })
        try run(&e.model) { GripService.apply(grip, to: Vec2(7, -3), in: $0) }
        #expect(Fx.approx(e.model[id]!.grid!.extent(in: e.plan)!.elbowStart!, Vec2(2, 0)), "only the offset across the grid counts")
        // The plan draws the jog: more than the single grid line.
        let g = ViewGraphicsBuilder(model: e.model, view: e.model[e.plan]!).build()
        let item = try #require(g.items.first { $0.elementID == id })
        #expect(item.primitives.filter { if case .polyline = $0 { return true }; return false }.count >= 2)
    }

    @Test func sectionGripsSetDepthAndFlipKeepsTheLine() throws {
        var (m, ids) = Fx.template()
        var sec: ElementID!
        try Fx.commit(&m) { tx in
            var s = ViewData(kind: .section); s.planeOrigin = Vec3(0, 0, 0); s.viewDirection = Vec2(0, 1)
            s.cropRegion = Rect2(min: Vec2(-4, 0), max: Vec2(6, 10)); s.farClip = 5
            sec = tx.create(.views, name: "Section 1", data: .view(s))
        }
        let plan = ids.planViews[ids.levels[0]]!
        let grips = GripService.grips(for: m[sec]!, m, viewKind: .floorPlan, viewID: plan)
        let depth = try #require(grips.first { $0.kind == .sectionDepth })
        #expect(Fx.approx(depth.position.distance(to: Vec2(1, 0)), 5))
        try Fx.commit(&m) { tx in GripService.apply(depth, to: depth.position + depth.direction * 3, in: tx) }
        #expect(Fx.approx(m[sec]!.view!.farClip, 8))
        let before = try #require(GripService.sectionLine(m[sec]!.view!))
        let flip = try #require(GripService.controls(for: m[sec]!, m, view: m[plan], pixel: 0.01).first { $0.kind == .flipSection })
        try Fx.commit(&m) { tx in GripService.toggle(flip, in: tx) }
        let after = try #require(GripService.sectionLine(m[sec]!.view!))
        #expect(Fx.approx(after.forward, -before.forward), "looks the other way")
        #expect(Set([after.a, after.b].map { "\(($0.x * 1000).rounded()),\(($0.y * 1000).rounded())" }) == Set([before.a, before.b].map { "\(($0.x * 1000).rounded()),\(($0.y * 1000).rounded())" }), "the line stays put")
    }
}
