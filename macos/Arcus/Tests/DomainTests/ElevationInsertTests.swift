import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-CANVAS: doors and windows placed in elevations (ARCUS-036); level heads sized as annotation (ARCUS-093).
@MainActor
@Suite("Elevation placement and level heads (BL-CANVAS)")
struct ElevationInsertTests {
    func elevation() throws -> (ToolContext, ProjectTemplates.Ids, [ElementID]) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        var walls: [ElementID] = []
        session.perform("Walls") { tx in walls = Fx.boxWalls(tx, ids, w: 10, h: 8) }
        let south = try #require(session.model.views.first { $0.name == "South" })
        let ctx = ToolContext(session: session, viewID: south.id)
        ctx.pixel = 0.01
        return (ctx, ids, walls)
    }
    /// View point (u, z) of a plan point at an elevation.
    func viewPoint(_ ctx: ToolContext, _ p: Vec2, z: Double) throws -> Vec2 {
        let fr = try #require(InsertTool.verticalFrame(ctx.viewData))
        return Vec2((p - fr.origin).dot(fr.right), z)
    }

    @Test func doorPlacedInAnElevationHostsTheFrontWallWithItsSillAtTheLevel() throws {
        let (ctx, ids, walls) = try elevation()
        let tool = InsertTool(ctx: ctx, category: .doors)
        #expect(tool.prompt.contains("Move over a wall"))
        let q = try viewPoint(ctx, Vec2(4, 0), z: 1)
        tool.pointerMoved(ToolInput(point: q, rawPoint: q))
        #expect(tool.preview.highlight == [walls[0]], "the south wall (nearest the viewer) is highlighted, not the north wall behind it")
        #expect(tool.preview.tempDims.count == 2, "distances to the wall ends")
        let width = try #require(ctx.type(for: .doors).flatMap { t in InsertGeometry.openingSize(Element(id: ElementID(1), category: .doors, data: .insert(InsertData(location: .zero)), typeID: t), ctx.model)?.width })
        #expect(tool.preview.tempDims.first?.text == ctx.format(4 - width / 2), "wall end to the near jamb of a door centred at 4 m")
        tool.pointerDown(ToolInput(point: q, rawPoint: q))
        let door = try #require(ctx.model.elements(.doors).first)
        #expect(door.hostID == walls[0])
        #expect(door.levelID == ids.levels[0])
        #expect(Fx.approx(door.insert!.location, Vec2(4, 0)))
        #expect(door.insert?.sillHeight == 0)
        #expect(door.mark == "1")
        // The South elevation looks north: the door faces the viewer (−y).
        let place = try #require(InsertGeometry.placement(door, ctx.model))
        #expect(place.plan.apply(Vec2(0, 1)).y < place.plan.apply(.zero).y)
    }

    @Test func windowKeepsItsSillAndShowsItsHeight() throws {
        let (ctx, _, walls) = try elevation()
        let tool = InsertTool(ctx: ctx, category: .windows)
        tool.setOption("sill", .double(0.9))
        let q = try viewPoint(ctx, Vec2(6, 0), z: 1.5)
        tool.pointerMoved(ToolInput(point: q, rawPoint: q))
        #expect(tool.preview.tempDims.contains { $0.text == ctx.format(0.9) }, "sill height to the host's base")
        tool.pointerDown(ToolInput(point: q, rawPoint: q))
        let w = try #require(ctx.model.elements(.windows).first)
        #expect(w.hostID == walls[0] && w.insert?.sillHeight == 0.9)
    }

    @Test func noHostAboveTheWallsOrBesideThem() throws {
        let (ctx, _, _) = try elevation()
        let tool = InsertTool(ctx: ctx, category: .doors)
        for q in [try viewPoint(ctx, Vec2(5, 0), z: 40), try viewPoint(ctx, Vec2(-6, 0), z: 1)] {
            tool.pointerMoved(ToolInput(point: q, rawPoint: q))
            #expect(tool.preview.highlight.isEmpty && tool.preview.cursor == .notAllowed)
        }
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        tool.pointerDown(ToolInput(point: .zero, rawPoint: .zero))
        #expect(ctx.model.elements(.doors).isEmpty && !messages.isEmpty)
    }

    @Test func wallsSeenEndOnAreNotHosts() throws {
        let (ctx, _, walls) = try elevation()
        let model = ctx.model
        // At the west wall's station only the south wall's end is hit; the west wall runs along the line of sight.
        let q = try viewPoint(ctx, Vec2(0, 0), z: 1)
        let hit = InsertTool.verticalHost(at: q, view: ctx.viewData, model: model, width: 0.9)
        #expect(hit?.wallID == walls[0])
        #expect(hit.map { Fx.approx($0.location, Vec2(0.45, 0)) } == true, "clamped so the opening stays in the wall")
    }

    // MARK: Level heads

    @Test func levelHeadTextIsAnnotationSizedAtTheViewScale() throws {
        let (m, ids) = Fx.template()
        let south = try #require(m.views.first { $0.name == "South" })
        var mm = m
        try Fx.commit(&mm) { tx in tx.update(south.id) { $0.view?.scale = 50 } }
        let g = ViewGraphicsBuilder(model: mm, view: mm[south.id]!).build()
        let level = try #require(g.items.first { $0.elementID == ids.levels[0] })
        let texts = level.primitives.compactMap { p -> GText? in if case .text(let t) = p { return t }; return nil }
        #expect(texts.contains { $0.height == 0.0025 }, "2.5 mm name text on paper")
        let arcs = level.primitives.compactMap { p -> Arc2? in if case .arc(let a, _) = p { return a }; return nil }
        #expect(arcs.contains { Fx.approx($0.radius, 0.0025 * 50) }, "head symbol sized on paper, scaled to the view")
    }
}
