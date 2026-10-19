import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Floor, roof, stair and ramp tools")
struct FloorsRoofsStairsToolTests {
    func context(view: ((BIMModel, ProjectTemplates.Ids) -> ElementID)? = nil) -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let v = view?(m, ids) ?? ids.planViews[ids.levels[0]]!
        let ctx = ToolContext(session: session, viewID: v)
        ctx.pixel = 0.01
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, count: Int = 1) {
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        var i = ToolInput(point: p, rawPoint: p)
        i.clickCount = count
        tool.pointerDown(i)
    }

    // MARK: Ramp

    @Test func rampToolDrawsARampWithRailingsAndWarnsWhenShort() {
        let (ctx, ids) = context()
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = RampTool(ctx: ctx)
        #expect(tool.topLevelID == ids.levels[1])
        tool.setOption("top", .text("Unconnected"))
        tool.setOption("width", .double(1.5))
        #expect(tool.isSketchMode)
        click(tool, Vec2(0, 0))
        click(tool, Vec2(10, 0))
        tool.pointerMoved(ToolInput(point: Vec2(10, 8), rawPoint: Vec2(10, 8)))
        #expect(tool.preview.tempDims.first?.text.contains("run") == true)
        #expect(tool.finish())
        let ramps = ctx.model.elements(.ramps)
        #expect(ramps.count == 1)
        let r = ramps[0]
        #expect(r.ramp?.path == [Vec2(0, 0), Vec2(10, 0)] && r.ramp?.width == 1.5)
        #expect(ctx.model[r.typeID]?.typeData?.instanceCategory == .ramps)
        #expect(ctx.model.hosted(by: r.id).filter { $0.railing?.followsHost == true }.count == 2)
        // Unconnected 1 m rise over 10 m at 1:12 needs 12 m: committed, and reported.
        #expect(ctx.session.lastWarnings.contains { $0.code == "ramp.length" })
        #expect(messages.contains { $0.contains("steeper") })
    }

    @Test func rampToolCreatesATypeWhenTheDocumentHasNone() throws {
        let (ctx, _) = context()
        #expect(ctx.model.types(for: .ramps).isEmpty)
        let tool = RampTool(ctx: ctx)
        click(tool, Vec2(0, 0))
        click(tool, Vec2(6, 0))
        click(tool, Vec2(6, 6))
        click(tool, Vec2(6, 6), count: 2)   // the second click of a double-click finishes
        #expect(ctx.model.elements(.ramps).count == 1)
        let type = try #require(ctx.model.types(for: .ramps).first)
        #expect(type.name == RampGeometry.defaultTypeName)
        #expect(type.typeData?.params[RampGeometry.maxSlopeParam]?.doubleValue == RampGeometry.defaultMaxSlope)
        #expect(ctx.model.elements(.ramps)[0].ramp?.path.count == 3)
        // The next ramp reuses it.
        let again = RampTool(ctx: ctx)
        click(again, Vec2(0, 10))
        click(again, Vec2(8, 10))
        #expect(again.finish())
        #expect(ctx.model.types(for: .ramps).count == 1)
    }

    @Test func rampToolTypedLengthAndEscape() {
        let (ctx, _) = context()
        let tool = RampTool(ctx: ctx)
        #expect(tool.numericLabel == nil)
        click(tool, Vec2(1, 1))
        tool.pointerMoved(ToolInput(point: Vec2(1, 9), rawPoint: Vec2(1, 9)))
        #expect(tool.numericInput("4000"))
        #expect(tool.points.last == Vec2(1, 5))
        #expect(tool.escape() == .stayInTool)
        #expect(tool.points.count == 1)
        #expect(tool.escape() == .stayInTool)
        #expect(tool.escape() == .exitTool)
        #expect(!tool.finish())
    }

    // MARK: Roof by extrusion

    func elevationContext() -> (ToolContext, ProjectTemplates.Ids) {
        context { m, _ in m.views.first { $0.name == "South" }!.id }
    }

    @Test func extrusionRejectsAClosedProfile() {
        let (ctx, _) = elevationContext()
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = SketchTool(ctx: ctx, target: .roofExtrusion, commandID: .roofExtrusion)
        tool.drawMode = .line
        for p in [Vec2(0, 4), Vec2(5, 7), Vec2(10, 4), Vec2(0, 4)] { click(tool, p) }
        #expect(!tool.finish())
        #expect(messages.last?.contains("needs an open profile") == true)
        #expect(ctx.model.elements(.roofs).isEmpty)
    }

    @Test func extrusionFromAnElevationSpansTheWallsBelow() throws {
        let (ctx, ids) = elevationContext()
        ctx.session.perform("Walls") { tx in _ = Fx.boxWalls(tx, ids, w: 10, h: 8) }
        let tool = SketchTool(ctx: ctx, target: .roofExtrusion, commandID: .roofExtrusion)
        tool.drawMode = .line
        tool.setOption("overhang", .double(0.5))
        // The South elevation looks north (+y); its right vector is +x, so u = x.
        for p in [Vec2(-0.5, 4), Vec2(5, 6.5)] { click(tool, p) }
        click(tool, Vec2(10.5, 4))
        #expect(tool.finish())
        let roof = try #require(ctx.model.elements(.roofs).first)
        let x = try #require(roof.roof?.extrusion)
        #expect(roof.levelID == ids.levels[1], "the highest level at or below the profile")
        #expect(x.profile.count == 2)
        #expect(Fx.approx(x.profile[0].start, Vec2(-0.5, 0)) && Fx.approx(x.profile[1].end, Vec2(10.5, 0)))
        // Depth runs along the view direction and covers the walls (y −0.1…8.1) plus the overhang.
        let fp = try #require(RoofExtrusionGeometry.footprint(roof)).bounds
        #expect(fp.min.y < -0.5 && fp.max.y > 8.5)
        #expect(Fx.approx(RoofGeometry.ridgeHeight(roof, ctx.model)!, 6.5))
        // Editing the profile in the same view round-trips it.
        let edit = SketchTool(ctx: ctx, target: .roofExtrusion, commandID: .editBoundary, editing: roof.id)
        #expect(edit.curves.count == 2)
        #expect(Fx.approx(edit.curves[0].end, Vec2(5, 6.5)))
    }

    // MARK: Edit Stair

    /// STAIR: Edit Stairs reads an older L stair as its runs; dragging run 1's end arrow adds whole treads and run 2's
    /// start arrow takes them back (risers moved between the flights); a side arrow widens the run from that side.
    @Test func editStairMovesRisersBetweenFlightsAndWidens() throws {
        let (ctx, ids) = context()
        var sid: ElementID!
        ctx.session.perform("Stair") { tx in
            sid = tx.create(.stairs, data: .stair(StairData(shape: .lShaped, origin: Vec2(0, 0), direction: 0, width: 1.1, topLevelID: ids.levels[1])),
                            typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
        }
        let before = try #require(StairGeometry.layout(ctx.model[sid]!, ctx.model))
        let tool = try #require(StairTool(ctx: ctx, editing: sid))
        #expect(tool.modifying && tool.draft.runs?.count == 2)
        func drag(_ from: Vec2, _ to: Vec2) {
            tool.pointerDown(ToolInput(point: from, rawPoint: from))
            tool.pointerDragged(ToolInput(point: to, rawPoint: to))
            tool.pointerUp(ToolInput(point: to, rawPoint: to))
        }
        // Select run 1 and drag its end two treads on.
        click(tool, before.runs[0].walkPoint(1))
        #expect(tool.selection == .run(0))
        let end = try #require(tool.grips().first { $0.1 == .end }?.0)
        drag(end, end + Vec2(2 * before.treadDepth, 0))
        #expect(tool.draft.runs?[0].risers == before.runs[0].risers + 2)
        // Run 2's start arrow two treads back along it.
        click(tool, before.runs[1].walkPoint(1))
        #expect(tool.selection == .run(1))
        let start = try #require(tool.grips().first { $0.1 == .start }?.0)
        drag(start, start + before.runs[1].direction * (2 * before.treadDepth))
        #expect(tool.draft.runs?[1].risers == before.runs[1].risers - 2)
        // Widen run 2 from its left by 0.2 m.
        let wl = try #require(tool.grips().first { $0.1 == .widthLeft }?.0)
        drag(wl, wl + before.runs[1].direction.perpendicular * 0.2)
        #expect(Fx.approx(tool.draft.runs?[1].width ?? 0, 1.3))
        #expect(ctx.model[sid]!.stair!.runs == nil, "nothing changes before Finish")
        #expect(tool.finish())
        let after = try #require(StairGeometry.layout(ctx.model[sid]!, ctx.model))
        #expect(after.runs[0].risers == before.runs[0].risers + 2)
        #expect(after.riserCount == before.riserCount)
        #expect(Fx.approx(after.runs[1].width, 1.3))
        #expect(ctx.session.undoManager.undoActionName == "Edit Stairs")
    }

    /// STAIR: the Options Bar edits the selected run; Cancel Edit Mode leaves the stair as it was.
    @Test func editStairOptionsAndCancel() throws {
        let (ctx, ids) = context()
        var sid: ElementID!
        ctx.session.perform("Stair") { tx in
            sid = tx.create(.stairs, data: .stair(StairData(origin: .zero, direction: 0, topLevelID: ids.levels[1])), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
        }
        let tool = try #require(StairTool(ctx: ctx, editing: sid))
        #expect(!tool.options.contains { $0.id == "selRisers" })
        click(tool, Vec2(1, 0))
        #expect(tool.options.contains { $0.id == "selRisers" })
        tool.setOption("selRisers", .int(24))
        #expect(tool.draft.runs?[0].risers == 24)
        tool.cancelSketch()
        #expect(ctx.model[sid]!.stair!.runs == nil)
        let t2 = try #require(StairTool(ctx: ctx, editing: sid))
        click(t2, Vec2(1, 0))
        t2.setOption("selRisers", .int(24))
        #expect(t2.finish())
        #expect(StairGeometry.layout(ctx.model[sid]!, ctx.model)?.riserCount == 24)
    }

    // MARK: Shape editing

    @Test func shapeEditToolAddsPointsAndTypesOffsets() throws {
        let (ctx, ids) = context()
        var fid: ElementID!
        ctx.session.perform("Floor") { tx in
            fid = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [ShapeEditingTests.square]))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        let add = try #require(ShapeEditTool(ctx: ctx, elementID: fid, mode: .addPoint))
        add.setOption("elevation", .double(-0.02))
        click(add, Vec2(5, 5))
        #expect(ctx.model[fid]!.slab!.shapePoints == [ShapePoint(position: Vec2(5, 5), offset: -0.02)])
        click(add, Vec2(5, 0.001))   // on an edge: refused
        #expect(ctx.model[fid]!.slab!.shapePoints?.count == 1)
        let modify = try #require(ShapeEditTool(ctx: ctx, elementID: fid, mode: .modify))
        click(modify, Vec2(10, 10))
        #expect(modify.selected == Vec2(10, 10))
        #expect(modify.numericInput("15"))
        #expect(ctx.model[fid]!.slab!.shapePoints?.contains(ShapePoint(position: Vec2(10, 10), offset: 0.015)) == true)
        #expect(Fx.approx(SlabGeometry.topZ(ctx.model[fid]!, at: Vec2(10, 10), ctx.model)!, 0.015))
        // Drag the interior point.
        let from = Vec2(5, 5), to = Vec2(4, 6)
        modify.pointerDown(ToolInput(point: from, rawPoint: from))
        modify.pointerDragged(ToolInput(point: to, rawPoint: to))
        modify.pointerUp(ToolInput(point: to, rawPoint: to))
        #expect(ctx.model[fid]!.slab!.shapePoints?.contains { $0.position == to && $0.offset == -0.02 } == true)
        #expect(ShapeEditTool(ctx: ctx, elementID: ids.levels[0], mode: .modify) == nil)
    }

    // MARK: Commands

    @Test func wp4CommandsAreCatalogued() {
        for id: CommandID in [.ramp, .roofExtrusion, .editStair, .modifySubElements, .addShapePoint, .resetShape, .attachWallsToHost, .joinSolids, .unjoinSolids] {
            let info = CommandCatalog.info(id)
            #expect(CommandCatalog.byID[id] != nil, "\(id)")
            #expect(!info.help.isEmpty && info.symbol != "questionmark")
        }
        #expect(CommandCatalog.search("ramp", aliases: CommandCatalog.defaultAliases, recent: [], available: { _ in true }).first?.id == .ramp)
    }
}
