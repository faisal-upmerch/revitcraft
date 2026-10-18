import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// W2-DWG: the Massing & Site tools driven with pointer input.
@MainActor
@Suite("Site tools (interactive)")
struct SiteToolInteractionTests {
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
    func addSlope(_ ctx: ToolContext) -> ElementID {
        var id: ElementID?
        ctx.session.perform("Topo") { tx in id = try SiteOperations.createToposurface(SiteToolsTests.slope, in: tx).0 }
        return id!
    }

    @Test func parkingLayoutByRectangleCreatesGroupedStripes() throws {
        let (ctx, _) = context()
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = ParkingLayoutTool(ctx: ctx)
        tool.setOption("stops", .bool(true))
        click(tool, Vec2(0, 0))
        tool.pointerMoved(ToolInput(point: Vec2(60, 30), rawPoint: Vec2(60, 30)))
        #expect(tool.preview.primitives.count > 70, "the preview shows the stripes before the second click")
        click(tool, Vec2(60, 30))
        let m = ctx.model
        let group = try #require(m.elements(.modelGroups).first { $0.name.hasPrefix("Parking Layout") })
        #expect(group.comments == "72 stalls")
        let members = group.group!.members.compactMap { m[$0] }
        let stripeStyle = try #require(m.lineStyle(named: "Parking Stripes")).id
        #expect(members.filter { $0.modelLine?.styleID == stripeStyle }.count == 75)
        #expect(members.filter { $0.modelLine?.styleID == m.lineStyle(named: "Parking Wheel Stops")?.id }.count == 72)
        #expect(members.allSatisfy { $0.category == .detailLines && $0.ownerViewID == nil && $0.groupID == group.id })
        #expect(messages.last?.contains("72 stalls") == true)
        // Angle changes pick the recommended aisle.
        tool.setOption("angle", .text("45°"))
        #expect(tool.params.angle == 45 && tool.params.aisleWidth == 4.0)
    }

    @Test func parkingLayoutPicksAFloorBoundary() throws {
        let (ctx, ids) = context()
        ctx.session.perform("Pad") { tx in
            tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(100, 0), max: Vec2(130, 20))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        let tool = ParkingLayoutTool(ctx: ctx)
        tool.setOption("mode", .text("Pick Boundary"))
        click(tool, Vec2(115, 10))
        #expect((ctx.model.elements(.modelGroups).first?.group?.members.count ?? 0) > 0)
    }

    @Test func subregionSplitLabelAndEdit() throws {
        let (ctx, _) = context()
        let topo = addSlope(ctx)
        // Sub-region: pick the surface with the first click.
        let sub = SubregionTool(ctx: ctx, hostID: nil)
        for p in [Vec2(1, 1), Vec2(3, 1), Vec2(3, 3), Vec2(1, 3)] { click(sub, p) }
        #expect(sub.finish())
        #expect(ctx.model.elements(.topography).contains { $0.hostID == topo && $0.topography?.boundary?.count == 4 })

        // Label contours across the slope (0.5 m interval by default: 0.5 at x = 5).
        let label = LabelContoursTool(ctx: ctx)
        click(label, Vec2(0.5, 8)); click(label, Vec2(9.5, 8))
        let notes = ctx.model.allElements.compactMap(\.textNote)
        #expect(notes.count == 1 && Fx.approx(notes[0].position, Vec2(5, 8)))

        // Edit, then split.
        let edit = try #require(EditSurfaceTool(ctx: ctx, surfaceID: topo))
        let before = ctx.model[topo]!.topography!.points.count
        edit.setOption("elevation", .double(3))
        click(edit, Vec2(4.2, 2.2))
        edit.setOption("mode", .text("Delete Point"))
        click(edit, Vec2(0, 0))
        #expect(edit.finish())
        let pts = ctx.model[topo]!.topography!.points
        #expect(pts.count == before)
        #expect(pts.contains(Vec3(4.2, 2.2, 3)) && !pts.contains { $0.xy == Vec2(0, 0) })

        let split = SplitSurfaceTool(ctx: ctx, hostID: topo)
        click(split, Vec2(0, 5.5)); click(split, Vec2(10, 5.5))
        #expect(split.finish())
        #expect(ctx.model.elements(.topography).filter { $0.topography?.boundary == nil }.count == 2)
    }
}
