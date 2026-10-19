import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Snap engine: guides, extensions, increments")
struct SnapEngineTests {
    /// A context over a drafting index of lines, 0.01 m per point (6 pt guide tolerance = 0.06 m).
    func context(_ lines: [(ElementID, [Vec2])]) -> ToolContext {
        let ctx = ToolContext(session: DocumentSession(model: BIMModel()), viewID: ElementID(99))
        ctx.pixel = 0.01
        ctx.snapIndex = SnapTests().index(lines.map { ($0.0, $0.1, .detailLines) })
        return ctx
    }

    @Test func extensionOfALineBeyondItsEnd() throws {
        let ctx = context([(ElementID(1), [Vec2(0, 0), Vec2(5, 0)])])
        let (p, s) = ctx.snap(Vec2(8, 0.03))
        let r = try #require(s)
        #expect(r.kind == .extension && p == Vec2(8, 0))
        #expect(r.description.hasPrefix("EXTENSION of ["))
        #expect(!r.guides.isEmpty, "a dashed guide from the line's end")
    }

    @Test func crossingOfTwoExtensions() throws {
        let ctx = context([(ElementID(1), [Vec2(0, 0), Vec2(5, 0)]), (ElementID(2), [Vec2(10, -10), Vec2(10, -5)])])
        let (p, s) = ctx.snap(Vec2(10.03, 0.02))
        let r = try #require(s)
        #expect(r.kind == .intersection && p.distance(to: Vec2(10, 0)) < 1e-9)
        #expect(r.description.hasPrefix("INTERSECTION of EXTENSION of") && r.description.contains(" AND EXTENSION of"))
        #expect(r.guides.count == 2)
    }

    @Test func horizontalFromTheStartMeetsAnExtension() throws {
        let ctx = context([(ElementID(2), [Vec2(10, -1), Vec2(10, 2)])])
        let (p, s) = ctx.snap(Vec2(10.03, 5.02), from: Vec2(0, 5))
        let r = try #require(s)
        #expect(p.distance(to: Vec2(10, 5)) < 1e-9)
        #expect(r.description.contains("HORIZONTAL") && r.description.contains("EXTENSION of"))
    }

    @Test func lengthRoundsToAnIncrementForTheZoom() throws {
        let ctx = context([])
        #expect(abs(ctx.lengthIncrement - 0.1) < 1e-12, "8 pt at 0.01 m/pt → 0.1 m")
        let (p, s) = ctx.snap(Vec2(3.456, 0.01), from: .zero)
        #expect(s?.description == "HORIZONTAL")
        #expect(p.distance(to: Vec2(3.5, 0)) < 1e-9)
        // Free direction: only the length is rounded.
        let (q, s2) = ctx.snap(Vec2(2.0, 1.5), from: .zero)
        #expect(s2 == nil && abs(q.length - 2.5) < 1e-9)
        ctx.pixel = 0.0005
        #expect(abs(ctx.lengthIncrement - 0.005) < 1e-12, "zoomed in → 5 mm")
    }

    @Test func aLineDrawnBesideAParallelOneStopsLevelWithItsEnd() throws {
        // Drawing up from (3, 0) beside a line from (0, 0) to (0, 5): the end snaps level with (0, 5).
        let ctx = context([(ElementID(1), [Vec2(0, 0), Vec2(0, 5)])])
        let (p, s) = ctx.snap(Vec2(3.02, 5.03), from: Vec2(3, 0))
        let r = try #require(s)
        #expect(p.distance(to: Vec2(3, 5)) < 1e-9, "\(p)")
        #expect(r.description.contains("VERTICAL") && r.description.contains("ALIGNMENT with END of"), "\(r.description)")
        #expect(r.shortLabel == "Vertical and Extension" && r.guides.count == 2, "\(r.shortLabel ?? "") \(r.guides.count)")
        // Away from the end there is no alignment.
        let (_, s2) = ctx.snap(Vec2(3.01, 4.2), from: Vec2(3, 0))
        #expect(s2?.description == "VERTICAL")
    }

    @Test func aPlacementLinesUpWithANeighboursEdgesAndCentre() throws {
        // A 1 m square footprint at the origin: placing 5 m to the right, just off its top edge, lands level with it
        // (its edge's extension and the alignment through its corner coincide; one guide is drawn).
        let ctx = context([(ElementID(1), [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1), Vec2(0, 0)])])
        let (p, s) = ctx.snap(Vec2(5, 1.03))
        let r = try #require(s)
        #expect(abs(p.y - 1) < 1e-9 && abs(p.x - 5) < 1e-9, "\(p)")
        #expect(r.description.hasPrefix("EXTENSION of") || r.description.hasPrefix("ALIGNMENT"), "\(r.description)")
        #expect(r.guides.count == 1, "one guide, not one per coincident rule: \(r.guides.count)")
        // A tiny footprint (a 6x6 post is ~10 pt here, too short for an extension guide) still offers alignment.
        let small = context([(ElementID(2), [Vec2(0, 0), Vec2(0.1, 0), Vec2(0.1, 0.1), Vec2(0, 0.1), Vec2(0, 0)])])
        let (q, s2) = small.snap(Vec2(3, 0.12))
        #expect(abs(q.y - 0.1) < 1e-9 && s2?.description.hasPrefix("ALIGNMENT with END of") == true && s2?.shortLabel == "Alignment", "\(q) \(s2?.description ?? "")")
        let (c, s3) = ctx.snap(Vec2(1.02, 1.03))
        #expect(s3?.kind == .endpoint && c == Vec2(1, 1), "the corner itself is a point snap")
    }

    @Test func endpointAlsoNamesTheHorizontal() throws {
        let ctx = context([(ElementID(1), [Vec2(4, 0), Vec2(4, 3)])])
        let (p, s) = ctx.snap(Vec2(4.02, 0.01), from: .zero)
        let r = try #require(s)
        #expect(r.kind == .endpoint && p == Vec2(4, 0))
        #expect(r.description.hasPrefix("ENDPOINT of [") && r.description.hasSuffix("AND HORIZONTAL"))
    }

    @Test func pointSnapsBeatGuides() throws {
        // The pointer is on a line's extension but also close to another line's end: the endpoint wins.
        let ctx = context([(ElementID(1), [Vec2(0, 0), Vec2(5, 0)]), (ElementID(2), [Vec2(8, 0.05), Vec2(8, 3)])])
        let (p, s) = ctx.snap(Vec2(8.02, 0.02))
        #expect(s?.kind == .endpoint && p == Vec2(8, 0.05))
    }
}

@MainActor
@Suite("Placing and dragging like BIM tools")
struct PlaceAndDragTests {
    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        ctx.pixel = 0.01
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    @Test func doorShowsDistancesToTheNearestWallsAndATypedValuePlacesIt() throws {
        let (ctx, _) = context()
        let wt = WallTool(ctx: ctx)
        click(wt, Vec2(0, 0)); click(wt, Vec2(10, 0)); _ = wt.escape()
        let host = try #require(ctx.model.elements(.walls).first)
        let wt2 = WallTool(ctx: ctx)
        click(wt2, Vec2(3, 0)); click(wt2, Vec2(3, 4)); _ = wt2.escape()          // a partition teeing into the host
        let door = InsertTool(ctx: ctx, category: .doors)
        var i = ToolInput(point: Vec2(5, 0), rawPoint: Vec2(5, 0.02))
        i.hit = host.id
        door.pointerMoved(i)
        let T = WallGeometry.assembly(for: host, ctx.model).totalThickness
        let W = try #require(door.probe.flatMap { InsertGeometry.openingSize($0, ctx.model)?.width })
        let values = door.spacing.map(\.value).sorted()
        #expect(values.count == 2)
        // Opening edges to the partition's face (x = 3 + T/2) and to the host's far end (x = 10); the door steps so the
        // nearer one is a round value for the zoom (0.1 m at 0.01 m/pt).
        let loc = try #require(door.location)
        #expect(abs(values[0] - (loc.x - W / 2 - (3 + T / 2))) < 1e-6, "gap to the partition face: \(values)")
        #expect(abs(values[1] - (10 - (loc.x + W / 2))) < 1e-6, "gap to the host's far end: \(values)")
        #expect(abs(values[0] / 0.1 - (values[0] / 0.1).rounded()) < 1e-6 && abs(loc.x - 5) <= 0.05 + 1e-9, "rounded near the pointer: \(values)")
        // The preview dimensions stand off the wall on the cursor's side (the pointer is just above the wall).
        #expect(door.preview.tempDims.allSatisfy { abs($0.from.y - T / 2) < 1e-9 && abs($0.to.y - T / 2) < 1e-9 && ($0.to - $0.from).perpendicular.y > 0 },
                "\(door.preview.tempDims.map { ($0.from, $0.to) })")
        #expect(door.numericLabel == "Distance")
        #expect(door.numericInput("1200"))          // project units are millimetres
        let placed = try #require(ctx.model.elements(.doors).first?.insert?.location)
        #expect(abs(placed.x - (3 + T / 2 + 1.2 + W / 2)) < 1e-6 && abs(placed.y) < 1e-6, "a 1.2 m gap from the partition face: \(placed)")
    }

    @Test func chainedLinesMeasureTheirAngleFromThePreviousSegment() throws {
        let (ctx, _) = context()
        let tool = LineTool(ctx: ctx, kind: .model, commandID: .modelLine)
        click(tool, Vec2(0, 0))
        tool.pointerMoved(ToolInput(point: Vec2(4, 0), rawPoint: Vec2(4, 0)))
        #expect(tool.preview.tempDims.first { $0.isAngleArc }?.angleReference == nil, "the first segment measures from the horizontal")
        tool.pointerDown(ToolInput(point: Vec2(4, 0), rawPoint: Vec2(4, 0)))
        tool.pointerMoved(ToolInput(point: Vec2(4, 3), rawPoint: Vec2(4, 3)))
        let arc = try #require(tool.preview.tempDims.first { $0.isAngleArc })
        #expect(arc.angleReference == Vec2(1, 0) && arc.from == Vec2(4, 0), "the next one from the segment before it")
    }

    @Test func doorPullsToTheMiddleBetweenWalls() throws {
        let (ctx, _) = context()
        let wt = WallTool(ctx: ctx)
        click(wt, Vec2(0, 0)); click(wt, Vec2(10, 0)); _ = wt.escape()
        let host = try #require(ctx.model.elements(.walls).first)
        let door = InsertTool(ctx: ctx, category: .doors)
        var i = ToolInput(point: Vec2(5.04, 0), rawPoint: Vec2(5.04, 0.02))
        i.hit = host.id
        door.pointerMoved(i)
        let loc = try #require(door.location)
        #expect(abs(loc.x - 5) < 1e-9, "within 6 pt of the middle: pulled to it (\(loc))")
    }

    @Test func draggingAWallMovesItPerpendicularAndShowsLiveDimensions() throws {
        let (ctx, _) = context()
        let wt = WallTool(ctx: ctx)
        for p in [Vec2(0, 0), Vec2(6, 0), Vec2(6, 4), Vec2(0, 4), Vec2(0, 0)] { click(wt, p) }
        _ = wt.escape()
        let east = try #require(ctx.model.elements(.walls).first { $0.wall?.location.midpoint.x ?? 0 > 5 })
        ctx.session.selection.select([east.id])
        let tool = SelectTool(ctx: ctx)
        _ = tool.beginDrag(at: Vec2(6, 2), grip: nil)
        tool.dragged(to: Vec2(7.5, 3.1))                            // diagonal pointer motion
        #expect(tool.moveVector(Vec2(7.5, 3.1), from: Vec2(6, 2)) == Vec2(1.5, 0), "walls move perpendicular to themselves")
        let guide = try #require(tool.preview.guides.first, "a dashed guide through the grab point")
        #expect(abs(guide.start.y - 2) < 1e-9 && abs(guide.end.y - 2) < 1e-9 && guide.start.x < 6 && guide.end.x > 7.5, "\(guide)")
        let dims = tool.preview.tempDims.filter { !$0.isAngle }
        let T = WallGeometry.assembly(for: east, ctx.model).totalThickness
        #expect(dims.contains { $0.text == ctx.format(7.5 - T) }, "live gap to the west wall's face: \(dims.map(\.text))")
        // Typing while dragging sets that gap.
        #expect(tool.numericInput("5000"))
        let typed = try #require(ctx.model[east.id]?.wall?.location.midpoint)
        #expect(abs(typed.x - (5 + T)) < 1e-9, "a 5 m gap between the faces: \(typed)")
        // A plain drag then moves it by the (perpendicular) pointer motion.
        _ = tool.beginDrag(at: Vec2(5 + T, 2), grip: nil)
        tool.dragged(to: Vec2(6.5 + T, 3.1))
        tool.endDrag(at: Vec2(6.5 + T, 3.1))
        let moved = try #require(ctx.model[east.id]?.wall?.location.midpoint)
        #expect(abs(moved.x - (6.5 + T)) < 1e-9 && abs(moved.y - 2) < 1e-9)
    }
}
