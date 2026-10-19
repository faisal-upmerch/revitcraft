import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// STAIR: Revit-style stairs: riser math and calculation rules, Create Stair runs and landings, winders and spirals,
/// plan cut marks and UP/DN on both levels, railings continuous round landings, multistory stairs, migration of older
/// stairs, and the stair parameters, types, Flip, Edit Path and Shaft ▸ Pick Stair.
@MainActor
@Suite("STAIR stairs")
struct STAIRTests {
    static let tread = 0.28

    func context(level: Int = 0) -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[level]]!)
        ctx.pixel = 0.01
        return (ctx, ids)
    }

    func click(_ tool: some InteractiveTool, _ p: Vec2) {
        let i = ToolInput(point: p, rawPoint: p)
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    func plan(_ m: BIMModel, _ ids: ProjectTemplates.Ids, level: Int) -> ViewGraphics {
        ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[level]]!]!).build()
    }

    func texts(_ g: ViewGraphics, _ id: ElementID) -> [String] {
        g.items.filter { $0.elementID == id }.flatMap(\.primitives).compactMap { if case .text(let t) = $0 { return t.string }; return nil }
    }

    /// A stair drawn with Create Stair (the monolithic template type unless `type` names another).
    @discardableResult
    func drawStair(_ ctx: ToolContext, type: String? = nil, _ draw: (StairTool) throws -> Void) throws -> Element {
        if let type { ctx.currentTypes[.stairs] = ctx.model.types(for: .stairs).first { $0.name == type }?.id }
        else { ctx.currentTypes[.stairs] = ctx.model.types(for: .stairs).first { $0.name == "Monolithic - 175 max riser" }?.id }
        let before = Set(ctx.model.elements(.stairs).map(\.id))
        let t = StairTool(ctx: ctx)
        try draw(t)
        #expect(t.finish())
        return try #require(ctx.model.elements(.stairs).first { !before.contains($0.id) })
    }

    // MARK: Riser math and calculation rules

    @Test func riserMathFollowsLevelsTypeAndProperties() throws {
        let (ctx, ids) = context()
        let e = try drawStair(ctx) { t in click(t, Vec2(0, 0)); click(t, Vec2(0, 22 * Self.tread)) }
        let l = try #require(StairGeometry.layout(e, ctx.model))
        // Level 1 to Level 2 is 4 m; the type's Maximum Riser Height is 175 mm: 23 risers of 173.9 mm, 280 mm treads.
        #expect(l.desiredRiserCount == 23 && l.riserCount == 23)
        #expect(Fx.approx(l.riserHeight, 4.0 / 23) && Fx.approx(l.treadDepth, 0.28))
        #expect(l.runs[0].treads.count == 22 && l.runs[0].riserLines.count == 23)
        #expect(Fx.approx(l.runs[0].topZ, 4.0))
        #expect(l.warnings.isEmpty, "\(l.warnings)")
        // Properties: Actual Tread Depth and Desired Number of Risers.
        try ctx.session.performThrowing("Tread") { tx in try Parameters.set(ParameterID("stair.actualTreadDepth"), to: .double(0.3), on: e.id, in: tx) }
        let l2 = try #require(StairGeometry.layout(ctx.model[e.id]!, ctx.model))
        #expect(Fx.approx(l2.treadDepth, 0.3) && Fx.approx(l2.runs[0].walkLength, 22 * 0.3), "the run lengthens with the tread")
        #expect(Parameters.value(ParameterID("stair.actualRisers"), of: ctx.model[e.id]!, ctx.model) == .int(23))
        // Begin with Riser off: the run starts with a tread (one more tread, same risers).
        try ctx.session.performThrowing("Begin") { tx in try Parameters.set(ParameterID("stair.beginWithRiser"), to: .bool(false), on: e.id, in: tx) }
        let l3 = try #require(StairGeometry.layout(ctx.model[e.id]!, ctx.model))
        #expect(l3.runs[0].treads.count == 23 && l3.riserCount == 23)
        #expect(Fx.approx(l3.runs[0].treads[0].z, 0), "the first tread is at the base")
    }

    @Test func calculationRulesWarn() throws {
        let (ctx, ids) = context()
        let e = try drawStair(ctx) { t in click(t, Vec2(0, 0)); click(t, Vec2(0, 10 * Self.tread)) }
        var l = try #require(StairGeometry.layout(e, ctx.model))
        #expect(l.riserCount == 11 && l.remainingRisers == 12)
        #expect(l.warnings.contains { $0.contains("needs 23") && $0.contains("12 remaining") })
        // Too few desired risers: riser height above the maximum and 2R + T outside the type's range.
        try ctx.session.performThrowing("Risers") { tx in try Parameters.set(ParameterID("stair.desiredRisers"), to: .int(18), on: e.id, in: tx) }
        l = try #require(StairGeometry.layout(ctx.model[e.id]!, ctx.model))
        #expect(l.warnings.contains { $0.contains("exceeds the type's Maximum Riser Height") })
        #expect(l.warnings.contains { $0.contains("Stair calculation rule not met") })
        // Tread below the minimum, run narrower than the minimum.
        try ctx.session.performThrowing("Tread") { tx in
            try Parameters.set(ParameterID("stair.actualTreadDepth"), to: .double(0.2), on: e.id, in: tx)
            try Parameters.set(ParameterID("stair.width"), to: .double(0.7), on: e.id, in: tx)
        }
        l = try #require(StairGeometry.layout(ctx.model[e.id]!, ctx.model))
        #expect(l.warnings.contains { $0.contains("less than the type's Minimum Tread Depth") })
        #expect(l.warnings.contains { $0.contains("Minimum Run Width") })
        // They reach Model Health and the transaction warnings with code stair.rule.
        #expect(ModelHealth.check(ctx.model).contains { $0.code == "stair.rule" && $0.elements.contains(e.id) })
        _ = ids
    }

    // MARK: Create Stair: runs, readout, Location Line, landings

    @Test func straightRunReadoutLocationLineAndFinish() throws {
        let (ctx, _) = context()
        let t = StairTool(ctx: ctx)
        #expect(t.isSketchMode && t.commandID == .stair)
        click(t, Vec2(0, 0))
        t.pointerMoved(ToolInput(point: Vec2(0, 2.3), rawPoint: Vec2(0, 2.3)))
        let readout = t.preview.primitives.compactMap { if case .text(let g) = $0 { return g.string }; return nil }
        #expect(readout.contains("9 RISERS CREATED, 14 REMAINING"))
        // Run: Left: the clicked path is the run's left edge (the run lies to its right).
        t.setOption("locationLine", .text(StairLocationLine.runLeft.rawValue))
        click(t, Vec2(0, 2.3))
        let r = try #require(t.draft.runs?.first)
        #expect(r.risers == 9)
        #expect(Fx.approx(r.start, Vec2(t.width / 2, 0)), "centre line half a width to the right of the path")
        #expect(t.remaining == 14)
        #expect(t.finish())
        let e = try #require(ctx.model.elements(.stairs).first)
        #expect(e.stair?.isComponentStair == true)
        #expect(ctx.model.hosted(by: e.id).filter { $0.railing != nil }.count == 2, "a railing each side")
        #expect(ctx.session.undoManager.undoActionName == "Create Stair")
    }

    @Test func automaticLandingAtATurnAndPickTwoRuns() throws {
        let (ctx, _) = context()
        let e = try drawStair(ctx) { t in
            click(t, Vec2(0, 0)); click(t, Vec2(0, 11 * Self.tread))
            let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(-1, 0), tolerance: 1e-6) })
            click(t, c.point); click(t, c.point + Vec2(-10 * Self.tread, 0))
        }
        let l = try #require(StairGeometry.layout(e, ctx.model))
        #expect(l.runs.count == 2 && l.riserCount == 23)
        #expect(l.landings.count == 1 && l.landings[0].isAutomatic)
        #expect(Fx.approx(l.landings[0].polygon.area, 1.1 * 1.1, 1e-6), "an L landing is one run width square")
        #expect(Fx.approx(l.landings[0].z, 12 * l.riserHeight))
        // Automatic Landing off: no landing until Pick Two Runs adds it.
        let (ctx2, _) = context()
        let t = StairTool(ctx: ctx2)
        t.setOption("automaticLanding", .bool(false))
        click(t, Vec2(0, 0)); click(t, Vec2(0, 11 * Self.tread))
        let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(-1, 0), tolerance: 1e-6) })
        click(t, c.point); click(t, c.point + Vec2(-10 * Self.tread, 0))
        #expect(t.layout()?.landings.isEmpty == true)
        t.choose(StairTool.LandingMode.pickTwoRuns)
        click(t, Vec2(0, 1)); click(t, c.point + Vec2(-1, 0))
        #expect(t.layout()?.landings.count == 1)
        // A sketched landing replaces it.
        t.choose(StairTool.LandingMode.sketch)
        let o = Vec2(-0.55, 11 * Self.tread)
        for p in [o, o + Vec2(1.1, 0), o + Vec2(1.1, 1.4), o + Vec2(0, 1.4), o] { click(t, p) }
        let land = try #require(t.layout()?.landings.first)
        #expect(!land.isAutomatic && land.afterRun == 0 && Fx.approx(land.polygon.area, 1.1 * 1.4, 1e-6))
    }

    @Test func uStairFromTwoRunsHasAWellAndOneLanding() throws {
        let (ctx, _) = context()
        let e = try drawStair(ctx, type: "Assembled - 175 max riser") { t in
            click(t, Vec2(0, 0)); click(t, Vec2(0, 11 * Self.tread))
            let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(0, -1), tolerance: 1e-6) && $0.point.x < 0 })
            click(t, c.point); click(t, c.point + Vec2(0, -10 * Self.tread))
        }
        let l = try #require(StairGeometry.layout(e, ctx.model))
        #expect(l.runs.count == 2 && l.landings.count == 1)
        let gap = abs(l.runs[0].left[0].point.x - l.runs[1].left[0].point.x)
        #expect(Fx.approx(gap, 0.2, 1e-6), "the well clears both runs' stringers by 100 mm")
        #expect(l.supports.count == 2 && l.supports.allSatisfy { $0.kind == .stringerClosed }, "the assembled type has stringers both sides")
    }

    // MARK: Winders, spirals, sketched runs

    @Test func windersAndSpiralsGeometry() throws {
        let (ctx, _) = context()
        let lw = try drawStair(ctx) { t in t.choose(StairTool.RunMode.lWinder); click(t, Vec2(0, 0)) }
        let l1 = try #require(StairGeometry.layout(lw, ctx.model))
        let r1 = l1.runs[0]
        #expect(r1.shape == .lWinder && r1.risers == 23 && r1.treads.count == 22)
        #expect(r1.treads.filter(\.isWinder).count == 3)
        #expect(abs(r1.direction.dot(r1.endDirection)) < 1e-9, "an L winder turns 90°")
        #expect(Fx.approx(r1.topZ, 4.0))
        let uw = try drawStair(ctx) { t in t.choose(StairTool.RunMode.uWinder); click(t, Vec2(10, 0)) }
        let r2 = try #require(StairGeometry.layout(uw, ctx.model)?.runs.first)
        #expect(r2.treads.filter(\.isWinder).count == 6)
        #expect(Fx.approx(r2.direction.dot(r2.endDirection), -1), "a U winder turns back")
        let sp = try drawStair(ctx) { t in t.choose(StairTool.RunMode.fullStepSpiral); click(t, Vec2(20, 3)); click(t, Vec2(21.6, 3)) }
        let r3 = try #require(StairGeometry.layout(sp, ctx.model)?.runs.first)
        #expect(r3.shape == .spiral && r3.risers == 23)
        #expect(r3.treads.allSatisfy { abs($0.walkPoint.distance(to: Vec2(20, 3)) - 1.6) < 0.01 }, "the walk line is the centre arc")
        // Center-Ends: centre, start, end a quarter turn on.
        let ce = try drawStair(ctx) { t in
            t.choose(StairTool.RunMode.centerEndsSpiral)
            click(t, Vec2(30, 0)); click(t, Vec2(32, 0))
            for a in stride(from: 0.1, through: Double.pi / 2, by: 0.1) { t.pointerMoved(ToolInput(point: Vec2(30, 0) + Vec2.fromAngle(a, length: 2), rawPoint: Vec2(30, 0) + Vec2.fromAngle(a, length: 2))) }
            click(t, Vec2(30, 2))
        }
        let r4 = try #require(StairGeometry.layout(ce, ctx.model)?.runs.first)
        #expect(r4.risers == Int((Double.pi / 2 * 2 / Self.tread).rounded()) + 1)
    }

    @Test func sketchedRunFromBoundaryRiserAndPathLines() throws {
        let (ctx, _) = context()
        let e = try drawStair(ctx) { t in
            t.choose(StairTool.RunMode.sketch)
            #expect(t.runSketch != nil)
            t.choose(StairTool.SketchLine.boundary)
            click(t, Vec2(-0.6, 0)); click(t, Vec2(-0.6, 5)); _ = t.escape()
            click(t, Vec2(0.6, 0)); click(t, Vec2(0.6, 5)); _ = t.escape()
            t.choose(StairTool.SketchLine.riser)
            for k in 0..<10 { let y = Double(k) * 0.3; click(t, Vec2(-1, y)); click(t, Vec2(1, y)) }
            t.choose(StairTool.SketchLine.path)
            click(t, Vec2(0, 0)); click(t, Vec2(0, 4)); _ = t.escape()
            #expect(t.finish(), "Finish ends the run sketch")
            #expect(t.runSketch == nil && t.draft.runs?.first?.shape == .sketch)
        }
        let r = try #require(StairGeometry.layout(e, ctx.model)?.runs.first)
        #expect(r.risers == 10 && r.treads.count == 9)
        #expect(Fx.approx(r.startEdge.length, 1.2, 1e-6), "risers trimmed to the boundaries")
    }

    // MARK: Plan: cut mark, UP and DN on both levels

    @Test func planCutMarkAndUpDownOnBothLevels() throws {
        let (ctx, ids) = context()
        let e = try drawStair(ctx) { t in click(t, Vec2(0, 0)); click(t, Vec2(0, 22 * Self.tread)) }
        let m = ctx.model
        let g1 = plan(m, ids, level: 0), g2 = plan(m, ids, level: 1)
        #expect(texts(g1, e.id).contains("UP") && !texts(g1, e.id).contains("DN"))
        #expect(texts(g2, e.id).contains("DN") && !texts(g2, e.id).contains("UP"), "the arrival plan reads DN")
        let item1 = try #require(g1.items.first { $0.elementID == e.id && $0.category == .stairs })
        let dashed = item1.primitives.filter { if case .polyline(_, _, let st) = $0 { return st.pattern == .hidden }; return false }
        let solid = item1.primitives.filter { if case .polyline(_, _, let st) = $0 { return st.pattern == .solid }; return false }
        #expect(!dashed.isEmpty && !solid.isEmpty, "solid below the cut plane, dashed above it")
        // Double zigzag: two cut lines of six points each across the run.
        let zigzags = item1.primitives.filter { if case .polyline(let p, _, _) = $0 { return p.count == 6 }; return false }
        #expect(zigzags.count == 2)
        // The cut sits where the nosing line reaches the cut plane (1200 mm above Level 1).
        let cut = try #require(StairPlanView(StairGeometry.layout(e, m)!, levelZ: 0, cutZ: 1.2, depthZ: 0, paper: { $0 * 100 })?.cut)
        #expect(Fx.approx(cut.station, (1.2 - 4.0 / 23) / (4.0 / 23) * 0.28, 1e-6))
        // Up Text in Properties.
        try ctx.session.performThrowing("Text") { tx in try Parameters.set(ParameterID("stair.upText"), to: .text("UP 23R"), on: e.id, in: tx) }
        #expect(texts(plan(ctx.model, ids, level: 0), e.id).contains("UP 23R"))
        // Single zigzag type.
        let type = try #require(ctx.model[e.typeID]?.id)
        try ctx.session.performThrowing("Cut") { tx in try Parameters.set(ParameterID("stair.cutMarkType"), to: .text("Single Zigzag"), on: type, in: tx) }
        let item = try #require(plan(ctx.model, ids, level: 0).items.first { $0.elementID == e.id && $0.category == .stairs })
        #expect(item.primitives.filter { if case .polyline(let p, _, _) = $0 { return p.count == 6 }; return false }.count == 1)
    }

    // MARK: Railings

    @Test func railingsGoRoundLandingsWithoutDiagonals() throws {
        let (ctx, ids) = context()
        var sid: ElementID!
        ctx.session.perform("Older U stair") { tx in
            sid = tx.create(.stairs, data: .stair(StairData(shape: .uShaped, origin: .zero, direction: .pi / 2, width: 1.1, topLevelID: ids.levels[1])),
                            typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
            for left in [true, false] {
                var r = RailingData(path: []); r.followsHost = true; r.hostSideLeft = left
                tx.create(.railings, data: .railing(r), typeID: ids.systemTypes["Railing"], levelID: ids.levels[0], hostID: sid)
            }
        }
        let m = ctx.model
        let l = try #require(StairGeometry.layout(m[sid]!, m))
        let landing = try #require(l.landings.first).polygon
        for rail in m.hosted(by: sid) {
            let lay = try #require(StairRailings.layout(rail, stair: m[sid]!, m))
            let pts = lay.base.map(\.xy)
            // Every segment that lies on the landing runs along one of its edges (inset), never across it.
            for (a, b) in zip(pts, pts.dropFirst()) where a.distance(to: b) > 1e-6 {
                let mid = a.midpoint(b)
                guard landing.contains(mid), landing.distanceToBoundary(mid) > 0.2 else { continue }
                Issue.record("rail segment \(a) → \(b) crosses the landing")
            }
            #expect(lay.top.count > lay.base.count, "the top rail extends at the bottom and top")
            #expect(lay.balusters.count >= 2 * l.runs.reduce(0) { $0 + $1.treads.count } - 2, "balusters on every tread")
            // Continuous: the base line never jumps in plan.
            #expect(zip(pts, pts.dropFirst()).allSatisfy { $0.distance(to: $1) < 7 })
        }
        // The outer rail turns both landing corners; the inner one crosses only the well.
        let outer = try #require(m.hosted(by: sid).first { $0.railing?.hostSideLeft == false })
        let o = try #require(StairRailings.layout(outer, stair: m[sid]!, m)).base.map(\.xy)
        #expect(o.filter { landing.contains($0) }.count >= 2)
        // On Level 1 the rail is split at the cut mark like the stair.
        let g = plan(m, ids, level: 0)
        let rail = try #require(g.items.first { $0.elementID == outer.id })
        #expect(rail.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.pattern == .hidden }; return false })
    }

    @Test func railingPositionEditPathAndReset() throws {
        let (ctx, ids) = context()
        let e = try drawStair(ctx, type: "Assembled - 175 max riser") { t in click(t, Vec2(0, 0)); click(t, Vec2(0, 22 * Self.tread)) }
        let rail = try #require(ctx.model.hosted(by: e.id).first { $0.railing?.hostSideLeft == true })
        let onTreads = try #require(StairRailings.layout(rail, stair: e, ctx.model))
        try ctx.session.performThrowing("Position") { tx in try Parameters.set(ParameterID("railing.stairPosition"), to: .text("Stringer"), on: rail.id, in: tx) }
        let onStringer = try #require(StairRailings.layout(ctx.model[rail.id]!, stair: e, ctx.model))
        #expect(onStringer.base[0].x < onTreads.base[0].x - 0.05, "on the stringer, outside the run")
        #expect(onStringer.base[0].z > onTreads.base[0].z, "on top of the stringer")
        // Edit Path: a sketched path still rises with the stair.
        let tool = try #require(StairRailingPathTool(ctx: ctx, railingID: rail.id))
        click(tool, Vec2(-0.3, 1)); click(tool, Vec2(-0.3, 5))
        #expect(tool.finish())
        let edited = try #require(StairRailings.layout(ctx.model[rail.id]!, stair: e, ctx.model))
        #expect(Fx.approx(edited.base.first!.xy.x, -0.3) && edited.base.last!.z > edited.base.first!.z + 2)
        ctx.session.perform("Reset") { tx in tx.update(rail.id) { $0.railing?.editedHostPath = nil } }
        #expect(ctx.model[rail.id]!.railing?.editedHostPath == nil)
        _ = ids
    }

    // MARK: Multistory, migration, transforms

    @Test func multistoryStairsRepeatAndAdaptToStoreyHeight() throws {
        let (ctx, ids) = context()
        let e = try drawStair(ctx) { t in
            t.multistoryTopLevelID = ids.levels[2]
            click(t, Vec2(0, 0)); click(t, Vec2(0, 22 * Self.tread))
        }
        let storeys = try #require(MultistoryStairs.storeys(of: e, ctx.model))
        #expect(storeys.count == 2 && storeys.allSatisfy { StairGeometry.layout($0, ctx.model)?.riserCount == 23 })
        // Level 2 shows the upper storey going UP and the lower one coming up to it (DN).
        let t2 = texts(plan(ctx.model, ids, level: 1), e.id)
        #expect(t2.contains("UP") && t2.contains("DN"))
        // A taller upper storey gets its own risers.
        ctx.session.perform("Roof") { tx in tx.update(ids.levels[2]) { $0.level?.elevation = 8.7 } }
        let st2 = try #require(MultistoryStairs.storeys(of: ctx.model[e.id]!, ctx.model))
        let upper = try #require(StairGeometry.layout(st2[1], ctx.model))
        #expect(upper.riserCount == 27 && upper.desiredRiserCount == 27 && upper.warnings.isEmpty, "\(upper.warnings)")
    }

    @Test func olderStairsDecodeAndReadAsTheirRuns() throws {
        // A stair as a schema-3 file stores it (no component fields).
        let json = #"{"shape":"U-Shaped","origin":{"x":0,"y":0},"direction":0,"width":1.2,"baseOffset":0,"topOffset":0,"unconnectedHeight":3,"turnsLeft":false}"#
        let s = try JSONDecoder().decode(StairData.self, from: Data(json.utf8))
        #expect(!s.isComponentStair && s.runs == nil && s.treadDepth == nil)
        let (m0, ids) = Fx.template()
        var m = m0
        var d = s; d.topLevelID = ids.levels[1]
        var sid: ElementID!
        try Fx.commit(&m) { tx in sid = tx.create(.stairs, data: .stair(d), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0]) }
        let l = try #require(StairGeometry.layout(m[sid]!, m))
        // The old U: n/2 risers each way, the second flight 100 mm beside the first, one full-width landing.
        #expect(l.runs.count == 2 && l.runs[0].risers == 11 && l.runs[1].risers == 12)
        #expect(Fx.approx(l.runs[1].start, Vec2(10 * 0.28, -1.3)))
        #expect(Fx.approx(l.landings[0].polygon.area, 1.2 * (2 * 1.2 + 0.1)))
        // Round trip with components.
        var c = d
        c.runs = l.runs.map { StairRun(start: $0.start, direction: $0.direction.angle, risers: $0.risers, width: $0.width) }
        let back = try JSONDecoder().decode(StairData.self, from: JSONEncoder().encode(c))
        #expect(back == c && back.isComponentStair)
    }

    @Test func mirrorAndFlip() throws {
        let (ctx, _) = context()
        let e = try drawStair(ctx) { t in t.choose(StairTool.RunMode.lWinder); click(t, Vec2(0, 0)) }
        var mirrored = e
        #expect(ElementTransform.apply(.mirror(through: .zero, direction: Vec2(0, 1)), to: &mirrored))
        #expect(mirrored.stair?.runs?.first?.turnsLeft == false)
        #expect(Fx.approx(mirrored.stair!.runs!.first!.start.x, -e.stair!.runs!.first!.start.x))
        // Flip: the top becomes the bottom.
        let t = try #require(StairTool(ctx: ctx, editing: e.id))
        let before = try #require(t.layout())
        t.flip()
        let after = try #require(t.layout())
        #expect(after.runs[0].startEdge.midpoint.isAlmostEqual(before.runs[0].endEdge.midpoint, tolerance: 1e-6))
        #expect(after.riserCount == before.riserCount)
    }

    // MARK: Types, parameters, shaft

    @Test func templateHasRevitStairFamiliesAndComponentTypes() throws {
        let (m, _) = Fx.template()
        let families = Set(m.types(for: .stairs).compactMap { $0.typeData?.familyName })
        #expect(families == ["Assembled Stair", "Cast-In-Place Stair", "Precast Stair"])
        #expect(m.types(for: .stairRuns).count == 2 && m.types(for: .stairLandings).count == 2 && m.types(for: .stairSupports).count == 2)
        let assembled = try #require(m.types(for: .stairs).first { $0.typeData?.familyName == "Assembled Stair" })
        let info = StairTypeInfo.of(type: assembled.typeData, m)
        #expect(!info.run.monolithic && info.run.nosingLength > 0 && info.right.kind == .stringerClosed && info.left.kind == .stringerClosed)
        let names = Set(Parameters.typeEntries(assembled, m).map(\.name))
        for n in ["Maximum Riser Height", "Minimum Tread Depth", "Minimum Run Width", "Run Type", "Landing Type", "Right Support", "Left Support",
                  "Middle Support", "Cut Mark Type", "Function"] { #expect(names.contains(n), "\(n)") }
        let inst = Element(id: ElementID(1), category: .stairs, data: .stair(StairData(origin: .zero, direction: 0)), typeID: assembled.id, levelID: m.levels.first?.id)
        let iNames = Set(Parameters.allEntries(inst, m).map(\.name))
        for n in ["Base Level", "Base Offset", "Top Level", "Top Offset", "Desired Stair Height", "Multistory Top Level", "Up Text", "Down Text",
                  "Desired Number of Risers", "Actual Number of Risers", "Actual Riser Height", "Actual Tread Depth", "Begin with Riser",
                  "End with Riser", "Tread/Riser Start Number"] { #expect(iNames.contains(n), "\(n)") }
        // Imperial projects get imperial names.
        let (mi, _) = ProjectTemplates.make(.architectural, units: .imperial)
        #expect(mi.types(for: .stairs).contains { $0.name == "Assembled - 7\" max riser 11\" tread" })
    }

    @Test func shaftPicksTheStairOutline() throws {
        let (ctx, _) = context()
        let e = try drawStair(ctx) { t in
            click(t, Vec2(0, 0)); click(t, Vec2(0, 11 * Self.tread))
            let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(-1, 0), tolerance: 1e-6) })
            click(t, c.point); click(t, c.point + Vec2(-10 * Self.tread, 0))
        }
        let shaft = ShaftOpeningTool(ctx: ctx)
        shaft.pickingStair = true
        var i = ToolInput(point: Vec2(0, 1), rawPoint: Vec2(0, 1)); i.hit = e.id
        shaft.pointerDown(i)
        #expect(shaft.loops.count == 1)
        let area = Polygon2(shaft.loops[0].map(\.start)).area
        let l = try #require(StairGeometry.layout(e, ctx.model))
        #expect(Fx.approx(area, l.runs.reduce(0) { $0 + $1.outline.area } + l.landings.reduce(0) { $0 + $1.polygon.area }, 1e-6))
        #expect(shaft.finish())
        #expect(ctx.model.elements(.shaftOpenings).count == 1)
    }

    @Test func commandsAndAliasesAreCatalogued() {
        for id: CommandID in [.stair, .stairComponentRun, .stairComponentLanding, .stairComponentSupport, .stairRunStraight, .stairRunFullStepSpiral,
                              .stairRunCenterEndsSpiral, .stairRunLWinder, .stairRunUWinder, .stairRunSketch, .stairLandingPickRuns, .stairLandingSketch,
                              .stairSupportPickEdges, .stairSketchBoundary, .stairSketchRiser, .stairSketchPath, .stairRailingSettings, .stairFlip,
                              .stairRailingEditPath, .stairRailingReset, .shaftPickStair] {
            #expect(CommandCatalog.byID[id] != nil, "\(id)")
            #expect(!CommandCatalog.info(id).help.isEmpty)
        }
        #expect(CommandCatalog.search("stair", aliases: CommandCatalog.defaultAliases, recent: [], available: { _ in true }).first?.id == .stair)
    }
}
