import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Wall, curtain and opening tools")
struct WallCurtainToolTests {
    func context(view: String? = nil, level: Int = 0) -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let viewID = view.map { name in m.views.first { $0.name == name }!.id } ?? ids.planViews[ids.levels[level]]!
        let ctx = ToolContext(session: session, viewID: viewID)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }
    var walls: (ToolContext) -> [Element] { { $0.model.elements(.walls) } }

    // MARK: Wall tool

    @Test func wallEndOnAnotherWallsCornerJoinsIt() throws {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        click(tool, Vec2(0, 0)); click(tool, Vec2(6, 0))
        _ = tool.escape()
        let first = try #require(walls(ctx).first)
        let half = WallGeometry.assembly(for: first, ctx.model).totalThickness / 2
        // Start the next wall on the visible outer corner at the east end (a face corner, not the location end).
        let t2 = WallTool(ctx: ctx)
        click(t2, Vec2(6 + half, -half)); click(t2, Vec2(6 + half, 4))
        _ = t2.escape()
        let second = try #require(walls(ctx).first { $0.id != first.id })
        guard case .line(let s)? = second.wall?.location else { Issue.record("not a line"); return }
        #expect(s.start.distance(to: Vec2(6, 0)) < 1e-9, "the end moved onto the other wall's location end")
        #expect(WallGeometry.endJoin(second, atEnd: false, ctx.model).kind == .corner)
        // Ends in the middle of a wall are tee joins and stay where they were put.
        #expect(WallGeometry.joinEndpoint(near: Vec2(3, half), levelID: first.levelID, ctx.model) == nil)
        // Just beyond the corner square (not on the wall): stays where it was put, however close it looks when zoomed in.
        #expect(WallGeometry.joinEndpoint(near: Vec2(6 + half * 2.2, 0), levelID: first.levelID, ctx.model) == nil)
        // Far from any wall end: unchanged.
        #expect(WallGeometry.joinEndpoint(near: Vec2(6 + 4 * half, 0), levelID: first.levelID, ctx.model) == nil)
    }

    @Test func optionsBarOffersTheWallFields() {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        let ids = tool.options.map(\.id)
        for id in ["mode", "extent", "top", "location", "chain", "offset", "useRadius", "join"] { #expect(ids.contains(id), "\(id)") }
        tool.setOption("useRadius", .bool(true))
        #expect(tool.options.contains { $0.id == "radius" })
        tool.setOption("mode", .text("Inscribed Polygon"))
        #expect(tool.options.contains { $0.id == "sides" })
        tool.setOption("extent", .text("Depth"))
        #expect(tool.options.contains { $0.id == "depthLevel" })
    }

    @Test func depthJoinStatusAndSpaceFlip() {
        let (ctx, ids) = context()
        let tool = WallTool(ctx: ctx)
        tool.setOption("extent", .text("Depth"))
        tool.setOption("height", .double(1.5))
        tool.setOption("join", .text("Disallow"))
        click(tool, .zero)
        tool.spaceBar()
        #expect(tool.flipSide)
        click(tool, Vec2(4, 0))
        let w = walls(ctx)[0]
        #expect(w.levelID == ids.levels[0] && w.wall?.topLevelID == ids.levels[0])
        #expect(w.wall?.baseOffset == -1.5)
        #expect(w.wall?.flipped == true)
        #expect(w.wall?.allowJoinAtStart == false && w.wall?.allowJoinAtEnd == false)
        let f = WallGeometry.frame(w, ctx.model)!
        #expect(Fx.approx(f.baseZ, -1.5) && Fx.approx(f.topZ, 0))
    }

    @Test func depthDownToALevel() {
        let (ctx, ids) = context(level: 1)
        let tool = WallTool(ctx: ctx)
        tool.setOption("extent", .text("Depth"))
        tool.setOption("depthLevel", .text(ctx.model[ids.levels[0]]!.name))
        click(tool, .zero); click(tool, Vec2(0, 5))
        let w = walls(ctx)[0]
        #expect(w.levelID == ids.levels[0] && w.wall?.topLevelID == ids.levels[1] && w.wall?.baseOffset == 0)
    }

    @Test func circleAndPolygonModes() {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        tool.setOption("mode", .text("Circle"))
        click(tool, Vec2(10, 10)); click(tool, Vec2(13, 10))
        var ws = walls(ctx)
        #expect(ws.count == 2)
        #expect(ws.allSatisfy { ($0.wall?.location.asArc?.sweep ?? 0) < 0 && Fx.approx($0.wall?.location.asArc?.radius ?? 0, 3) }, "clockwise halves, exterior out")
        tool.setOption("mode", .text("Inscribed Polygon"))
        tool.setOption("sides", .int(6))
        click(tool, .zero); click(tool, Vec2(2, 0))
        ws = walls(ctx)
        #expect(ws.count == 8)
        let hex = ws.suffix(6).compactMap { $0.wall?.location.asSegment }
        #expect(hex.allSatisfy { Fx.approx($0.start.length, 2, 1e-9) && Fx.approx($0.length, 2, 1e-9) })
        tool.setOption("mode", .text("Circumscribed Polygon"))
        tool.setOption("sides", .int(4))
        click(tool, Vec2(30, 0)); click(tool, Vec2(32, 0))
        let sq = walls(ctx).suffix(4).compactMap { $0.wall?.location.asSegment }
        #expect(sq.count == 4 && sq.allSatisfy { Fx.approx($0.length, 4, 1e-9) }, "sides touch the 2 m circle")
        // Radius option: one click places a circle.
        tool.setOption("mode", .text("Circle"))
        tool.setOption("useRadius", .bool(true))
        tool.setOption("radius", .double(1))
        click(tool, Vec2(50, 50))
        #expect(walls(ctx).count == 14)
    }

    @Test func tangentArcContinuesTheChain() throws {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        click(tool, .zero); click(tool, Vec2(4, 0))
        tool.setOption("mode", .text("Tangent Arc"))
        // Switching modes mid-chain continues from the end of the last wall.
        click(tool, Vec2(6, 2))
        let arc = try #require(walls(ctx).last?.wall?.location.asArc)
        #expect(Fx.approx(arc.start, Vec2(4, 0), 1e-9) && Fx.approx(arc.end, Vec2(6, 2), 1e-9))
        #expect(Fx.approx(arc.tangent(at: 0), Vec2(1, 0), 1e-9))
        #expect(WallGeometry.endJoin(walls(ctx)[0], atEnd: true, ctx.model).kind == .corner)
        // Without a chain, the first click picks the end of an existing wall.
        tool.setOption("mode", .text("Line"))
        #expect(tool.escape() == .stayInTool)
        tool.setOption("mode", .text("Tangent Arc"))
        click(tool, Vec2(4, 0))
        click(tool, Vec2(6, -2))
        #expect(walls(ctx).count == 3)
        #expect(Fx.approx(walls(ctx).last!.wall!.location.tangent(at: 0), Vec2(1, 0), 1e-9))
    }

    @Test func radiusFilletsLineChainCorners() throws {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        tool.setOption("useRadius", .bool(true))
        tool.setOption("radius", .double(1))
        click(tool, .zero); click(tool, Vec2(5, 0)); click(tool, Vec2(5, 5))
        let ws = walls(ctx)
        #expect(ws.count == 3)
        let first = try #require(ws[0].wall?.location.asSegment)
        #expect(Fx.approx(first.start, .zero) && Fx.approx(first.end, Vec2(4, 0), 1e-9), "trimmed back to the fillet")
        let arc = try #require(ws[1].wall?.location.asArc)
        #expect(Fx.approx(arc.radius, 1, 1e-9) && Fx.approx(arc.center, Vec2(4, 1), 1e-9))
        let last = try #require(ws[2].wall?.location.asSegment)
        #expect(Fx.approx(last.start, Vec2(5, 1), 1e-9) && Fx.approx(last.end, Vec2(5, 5), 1e-9))
    }

    @Test func filletArcTrimsTwoWalls() throws {
        let (ctx, ids) = context()
        var a: ElementID!, b: ElementID!
        ctx.session.perform("Walls") { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(6, 0))
            b = Fx.wall(tx, ids, Vec2(6, 0), Vec2(6, 6))
        }
        let tool = WallTool(ctx: ctx)
        tool.setOption("mode", .text("Fillet Arc"))
        click(tool, Vec2(3, 0.05)); click(tool, Vec2(6.05, 3))
        #expect(tool.numericLabel == "Radius")
        #expect(tool.numericInput("2000"))
        let sa = try #require(ctx.model[a]?.wall?.location.asSegment), sb = try #require(ctx.model[b]?.wall?.location.asSegment)
        #expect(Fx.approx(sa.start, .zero) && Fx.approx(sa.end, Vec2(4, 0), 1e-9))
        #expect(Fx.approx(sb.start, Vec2(6, 2), 1e-9) && Fx.approx(sb.end, Vec2(6, 6), 1e-9))
        let arc = try #require(walls(ctx).first { $0.wall?.location.asArc != nil }?.wall?.location.asArc)
        #expect(Fx.approx(arc.start, Vec2(4, 0), 1e-9) && Fx.approx(arc.end, Vec2(6, 2), 1e-9) && Fx.approx(arc.radius, 2, 1e-9))
    }

    @Test func curtainWallsDrawWithTheWallTool() throws {
        let (ctx, ids) = context()
        ctx.currentTypes[.walls] = ids.systemTypes["Curtain Wall: Storefront"]
        let tool = WallTool(ctx: ctx, mode: .line, commandID: .curtainWall)
        #expect(tool.commandID == .curtainWall)
        click(tool, .zero); click(tool, Vec2(7.2, 0))
        let w = try #require(walls(ctx).first)
        #expect(w.wall?.curtain != nil)
        let l = try #require(CurtainWallGeometry.layout(w, ctx.model))
        #expect(l.panels.count == 4 * 2, "max spacing 1.8 over 7.2 m, fixed 2.4 m rows up to 4 m")
    }

    // MARK: Curtain tools

    /// A Storefront wall along the x axis (seen by the South elevation with u = x).
    func curtainScene(view: String = "South") -> (ToolContext, ProjectTemplates.Ids, ElementID) {
        let (ctx, ids) = context(view: view)
        var w: ElementID!
        ctx.session.perform("CW") { tx in
            w = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(6, 0))), topLevelID: ids.levels[1])),
                          typeID: ids.systemTypes["Curtain Wall: Exterior Glazing"], levelID: ids.levels[0])
        }
        return (ctx, ids, w)
    }

    @Test func curtainGridAddsAndRemovesGridLinesInElevation() throws {
        let (ctx, _, w) = curtainScene()
        let tool = CurtainGridTool(ctx: ctx)
        #expect(CurtainWallGeometry.layout(ctx.model[w]!, ctx.model)?.stations.count == 5)
        // Near the bottom edge: a vertical grid line at the cursor's station.
        click(tool, Vec2(0.5, 0.2), hit: w)
        #expect(ctx.model[w]?.wall?.curtain?.verticalGrids.map { ($0 * 1000).rounded() / 1000 } == [0.5])
        // Near the end: a horizontal grid line.
        click(tool, Vec2(5.95, 1.1), hit: w)
        #expect(ctx.model[w]?.wall?.curtain?.horizontalGrids.map { ($0 * 1000).rounded() / 1000 } == [1.1])
        #expect(CurtainWallGeometry.layout(ctx.model[w]!, ctx.model)?.panels.count == 5 * 3)
        // Clicking a grid line added by hand removes it.
        click(tool, Vec2(0.52, 0.3), hit: w)
        #expect(ctx.model[w]?.wall?.curtain?.verticalGrids.isEmpty == true)
        // Typed distance from the previous grid line.
        tool.orientation = .vertical
        tool.pointerMoved(ToolInput(point: Vec2(3.7, 2), rawPoint: Vec2(3.7, 2)))
        #expect(tool.numericInput("500"))
        #expect(ctx.model[w]?.wall?.curtain?.verticalGrids.map { ($0 * 1000).rounded() / 1000 } == [3.5])
    }

    @Test func mullionToolTogglesSegmentsAndFillsAllGridLines() throws {
        let (ctx, _, w) = curtainScene()
        let tool = MullionTool(ctx: ctx)
        func layout() -> CurtainLayout { CurtainWallGeometry.layout(ctx.model[w]!, ctx.model)! }
        #expect(layout().mullions.isEmpty)
        click(tool, Vec2(1.51, 1), hit: w)
        #expect(layout().mullions.count == 1)
        #expect(layout().mullions[0].isVertical && Fx.approx(layout().mullions[0].position, 1.5))
        click(tool, Vec2(1.5, 1), hit: w)
        #expect(layout().mullions.isEmpty, "clicking an existing mullion removes it")
        tool.placement = .all
        click(tool, Vec2(2, 2), hit: w)
        let l = layout()
        // 5 vertical lines × 2 rows + 3 horizontal lines × 4 columns.
        #expect(l.mullions.count == 5 * 2 + 3 * 4)
        #expect(ctx.model[w]?.wall?.curtain?.mullions.count == 5 + 3)
    }

    @Test func curtainPanelToolSwapsToTheSelectedType() throws {
        let (ctx, _, w) = curtainScene()
        ctx.currentTypes[.curtainPanels] = ctx.model.type(category: .curtainPanels, name: "Empty")?.id
        let tool = CurtainPanelTool(ctx: ctx)
        click(tool, Vec2(0.5, 1), hit: w)
        var l = CurtainWallGeometry.layout(ctx.model[w]!, ctx.model)!
        #expect(l.panels.filter { $0.kind == .empty }.count == 1)
        #expect(l.panel(atStation: 0.5, z: 1)?.kind == .empty)
        // Swapping the same panel again replaces its override instead of stacking another.
        ctx.currentTypes[.curtainPanels] = ctx.model.type(category: .curtainPanels, name: "Solid")?.id
        tool.scope = .row
        click(tool, Vec2(0.5, 1), hit: w)
        l = CurtainWallGeometry.layout(ctx.model[w]!, ctx.model)!
        #expect(l.panels.filter { $0.row == 0 }.allSatisfy { $0.kind == .solid })
        #expect(ctx.model[w]?.wall?.curtain?.panels.count == 4)
        // Plans: panels are picked at the cut plane.
        let (pctx, _, pw) = curtainScene(view: "Level 1")
        pctx.currentTypes[.curtainPanels] = pctx.model.type(category: .curtainPanels, name: "Empty")?.id
        let ptool = CurtainPanelTool(ctx: pctx)
        click(ptool, Vec2(4, 0.02))
        let pl = CurtainWallGeometry.layout(pctx.model[pw]!, pctx.model)!
        #expect(pl.panel(atStation: 4, z: 1.2)?.kind == .empty)
    }

    // MARK: Openings

    @Test func wallOpeningToolCutsARectangleFromAnElevation() throws {
        let (ctx, ids) = context(view: "South")
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(8, 0)) }
        let tool = WallOpeningTool(ctx: ctx)
        click(tool, Vec2(3, 2), hit: w)
        click(tool, Vec2(2, 1))
        click(tool, Vec2(3.5, 2.5))
        let op = try #require(ctx.model.elements(.wallOpenings).first)
        #expect(op.hostID == w && op.levelID == ids.levels[0])
        let d = try #require(op.opening?.wallOpening)
        #expect(Fx.approx(d.start, 2) && Fx.approx(d.end, 3.5) && Fx.approx(d.bottom, 1) && Fx.approx(d.top, 2.5))
        #expect(Fx.approx(QuantityEngine.quantities(for: ctx.model[w]!, in: ctx.model).area ?? 0, 32 - 1.5 * 1.5, 1e-9))
        // In a plan the tool refuses.
        let (pctx, _) = context()
        var messages: [String] = []
        pctx.showMessage = { messages.append($0) }
        click(WallOpeningTool(ctx: pctx), .zero)
        #expect(!messages.isEmpty)
    }

    @Test func shaftToolSketchesAndFinishes() throws {
        let (ctx, ids) = context()
        var floor: ElementID!
        ctx.session.perform("Floor") { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[1])
        }
        let tool = ShaftOpeningTool(ctx: ctx)
        #expect(tool.isSketchMode)
        #expect(!tool.finish(), "an empty sketch can't finish")
        tool.setOption("mode", .text("Line"))
        click(tool, Vec2(1, 1)); click(tool, Vec2(3, 1)); click(tool, Vec2(3, 3)); click(tool, Vec2(1, 3))
        click(tool, Vec2(1, 1)) // closes the loop
        var done = false
        ctx.toolFinished = { done = true }
        #expect(tool.finish())
        #expect(done)
        let shaft = try #require(ctx.model.elements(.shaftOpenings).first)
        #expect(shaft.levelID == ids.levels[0] && shaft.opening?.shaft?.topLevelID == ids.levels[1])
        #expect(Fx.approx(QuantityEngine.quantities(for: ctx.model[floor]!, in: ctx.model).area ?? 0, 80 - 4, 1e-9))
    }
}
