import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-SITE (ARCUS-070): the Toposolid and Sub-Divide sketch tools and the Split Line shape-editing mode, driven with
/// pointer input.
@MainActor
@Suite("Toposolid tools (interactive)")
struct ToposolidToolTests {
    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2) {
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
    }

    @Test func rectangleSketchCreatesAToposolidAtTheHeightOffset() throws {
        let (ctx, ids) = context()
        var finished = false
        ctx.toolFinished = { finished = true }
        let tool = ToposolidSketchTool(ctx: ctx)
        tool.setOption("mode", .text("Rectangle"))
        tool.setOption("offset", .double(-0.5))
        click(tool, Vec2(0, 0))
        click(tool, Vec2(12, 8))
        let e = try #require(ctx.model.elements(.topography).first { $0.isToposolid })
        #expect(finished && e.levelID == ids.levels[0])
        let b = ElementMeshes.bounds(e, ctx.model)
        #expect(Fx.approx(b.max.z, ctx.levelElevation - 0.5) && Fx.approx(b.max.x, 12) && Fx.approx(b.max.y, 8))
        #expect(ctx.session.canUndo)
    }

    @Test func lineSketchClosesOnTheFirstPointAndSubDivideFollows() throws {
        let (ctx, _) = context()
        let tool = ToposolidSketchTool(ctx: ctx)
        for p in [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10), Vec2(0, 0)] { click(tool, p) }
        let solid = try #require(ctx.model.elements(.topography).first { $0.isToposolid })
        #expect(Fx.approx(ToposolidGeometry.outline(solid).area, 100))
        let sub = ToposolidSketchTool(ctx: ctx, subdivide: solid.id)
        #expect(sub.commandID == .subdivideToposolid)
        sub.setOption("height", .double(0.2))
        sub.setOption("mode", .text("Rectangle"))
        click(sub, Vec2(2, 2))
        click(sub, Vec2(4, 5))
        let s = try #require(ctx.model.hosted(by: solid.id).first { $0.isToposolidSubdivision })
        #expect(s.topography?.solid?.subdivisionHeight == 0.2)
        #expect(Fx.approx(ElementMeshes.parts(s, ctx.model).reduce(0) { $0 + $1.mesh.signedVolume }, 6 * 0.2, 1e-6))
    }

    @Test func tooFewCornersReportAndEscapeStepsBack() {
        let (ctx, _) = context()
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = ToposolidSketchTool(ctx: ctx)
        click(tool, Vec2(0, 0)); click(tool, Vec2(5, 0))
        #expect(!tool.finish() && messages.last?.contains("three corners") == true)
        #expect(tool.escape() == .stayInTool)
        #expect(ctx.model.elements(.topography).isEmpty)
    }

    @Test func editSurfaceSplitLineAddsPoints() throws {
        let (ctx, _) = context()
        var id: ElementID!
        ctx.session.perform("Solid") { tx in id = try ToposolidOperations.create(points: ToposolidTests.slope, in: tx).0 }
        let tool = try #require(EditSurfaceTool(ctx: ctx, surfaceID: id, commandID: .editSurface))
        tool.setOption("mode", .text("Split Line"))
        click(tool, Vec2(0.5, 0.5))
        #expect(tool.escape() == .stayInTool, "Esc cancels the half-drawn line")
        click(tool, Vec2(0.5, 0.5))
        click(tool, Vec2(9.5, 9.2))
        #expect(tool.finish())
        let pts = try #require(ctx.model[id]?.topography?.points)
        #expect(pts.count > 121 && pts.allSatisfy { Fx.approx($0.z, 0.1 * $0.x, 1e-9) })
    }
}
