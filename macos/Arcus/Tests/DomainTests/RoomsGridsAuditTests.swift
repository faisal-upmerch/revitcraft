import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-SCHED (ARCUS-089 retest): rooms and areas (placement, tags, colour fill) and grids (numbering, bubbles, 2D/3D
/// extents, dimensions to grids).
@Suite("Rooms, areas and grids audit (BL-SCHED)")
@MainActor
struct RoomsGridsAuditTests {
    func texts(_ g: ViewGraphics, _ category: ArcusDomain.Category) -> [String] {
        g.items.filter { $0.category == category }.flatMap(\.primitives).compactMap { if case .text(let t) = $0 { return t.string } else { return nil } }
    }

    func session(_ build: (TransactionContext, ProjectTemplates.Ids) -> Void = { _, _ in }) -> (DocumentSession, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        s.undoManager.beginUndoGrouping()
        s.perform("Setup") { tx in build(tx, ids) }
        return (s, ids)
    }

    // MARK: Rooms

    @Test func roomToolPlacesNumbersInSequenceAndTagsShowNameAndNumber() {
        let (s, ids) = session { tx, ids in
            _ = Fx.boxWalls(tx, ids)
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(5, 0), Vec2(5, 8))))), levelID: ids.levels[0])
        }
        let plan = ids.planViews[ids.levels[0]]!
        let ctx = ToolContext(session: s, viewID: plan)
        let tool = RoomTool(ctx: ctx)
        let first = tool.nextNumber
        tool.pointerDown(ToolInput(point: Vec2(2, 4), rawPoint: Vec2(2, 4)))
        tool.pointerDown(ToolInput(point: Vec2(8, 4), rawPoint: Vec2(8, 4)))
        let rooms = s.model.elements(.rooms)
        #expect(rooms.map { $0.room!.number } == [String(first), String(first + 1)])
        #expect(rooms.allSatisfy { RoomGeometry.boundary($0, s.model).state == .bounded })
        #expect(rooms.allSatisfy { s.model.tags(of: $0.id).count == 1 }, "Tag on Placement")
        // Renaming a room updates its tag in the plan.
        s.setParameter(ParameterID("name"), value: .text("Kitchen"), on: [rooms[0].id], name: "Name")
        let g = ViewGraphicsBuilder(model: s.model, view: s.model[plan]!).build()
        let tagTexts = texts(g, .tags)
        #expect(tagTexts.contains("Kitchen") && tagTexts.contains(String(first)), "room tag texts: \(tagTexts)")
    }

    @Test func roomOutsideAnEnclosureIsPlacedButReportedUnbounded() {
        let (s, ids) = session { tx, ids in _ = Fx.boxWalls(tx, ids) }
        let tool = RoomTool(ctx: ToolContext(session: s, viewID: ids.planViews[ids.levels[0]]!))
        tool.pointerDown(ToolInput(point: Vec2(20, 20), rawPoint: Vec2(20, 20)))
        let r = s.model.elements(.rooms).last!
        #expect(RoomGeometry.boundary(r, s.model).state != .bounded)
    }

    // Colour fill schemes, legends and section fills are covered by RoomAreaAnnotationTests (verified, not repeated).

    // MARK: Grids

    @Test func gridNamesContinueTheSequence() {
        #expect(GridNaming.next(after: []) == "1")
        #expect(GridNaming.next(after: ["1", "2", "3"]) == "4")
        #expect(GridNaming.next(after: ["A", "B"]) == "C")
        #expect(GridNaming.next(after: ["H"]) == "J", "I is skipped")
        #expect(GridNaming.next(after: ["N"]) == "P", "O is skipped")
        #expect(GridNaming.next(after: ["Y", "Z"]) == "AA")
        #expect(GridNaming.next(after: ["AZ"]) == "BA")
        #expect(GridNaming.next(after: ["A1"]) == "A2")
        #expect(GridNaming.next(after: ["G-09"]) == "G-10")
        #expect(GridNaming.next(after: ["1", "2", "3", "1A"]) == "1B")
        // Never a duplicate: "3" after "2" is taken, so "4".
        #expect(GridNaming.next(after: ["3", "1", "2"]) == "4")
        #expect(LineTool.nextName(after: ["A", "Z"]) == "AA")
    }

    @Test func gridToolNamesEachNewGrid() {
        let (s, ids) = session()
        let tool = LineTool(ctx: ToolContext(session: s, viewID: ids.planViews[ids.levels[0]]!), kind: .grid, commandID: .grid)
        let existing = Set(s.model.elements(.grids).map(\.name))
        for x in [0.0, 6] {
            tool.pointerDown(ToolInput(point: Vec2(x, -2), rawPoint: Vec2(x, -2)))
            tool.pointerDown(ToolInput(point: Vec2(x, 10), rawPoint: Vec2(x, 10)))
        }
        let names = s.model.elements(.grids).map(\.name).filter { !existing.contains($0) }
        #expect(names.count == 2 && Set(names).count == 2)
    }

    @Test func gridBubblesFollowTheirFlags() {
        var grid: ElementID!
        let (s, ids) = session { tx, _ in grid = tx.create(.grids, name: "7", data: .grid(GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(0, 10)))))) }
        let plan = s.model[ids.planViews[ids.levels[0]]]!
        func labels() -> Int { ViewGraphicsBuilder(model: s.model, view: s.model[plan.id]!).build().items.filter { $0.elementID == grid }.flatMap(\.primitives).filter { if case .text(let t) = $0 { return t.string == "7" }; return false }.count }
        #expect(labels() == 1, "bubble at the start only by default")
        s.setParameter(ParameterID("grid.bubbleEnd"), value: .bool(true), on: [grid], name: "Bubble at End")
        #expect(labels() == 2)
        s.setParameter(ParameterID("grid.bubbleStart"), value: .bool(false), on: [grid], name: "Bubble at Start")
        s.setParameter(ParameterID("grid.bubbleEnd"), value: .bool(false), on: [grid], name: "Bubble at End")
        #expect(labels() == 0)
    }

    @Test func gridVerticalExtentsLimitItInSections() throws {
        var grid: ElementID!, section: ElementID!
        let (s, _) = session { tx, _ in
            grid = tx.create(.grids, name: "1", data: .grid(GridData(curve: .line(Segment2(Vec2(5, -5), Vec2(5, 5))))))
            var sv = ViewData(kind: .section, scale: 50)
            sv.planeOrigin = Vec3(0, 0, 0)
            sv.viewDirection = Vec2(0, 1)
            sv.farClip = 10
            section = tx.create(.views, name: "Section A", data: .view(sv))
        }
        func span() -> (Double, Double)? {
            let g = ViewGraphicsBuilder(model: s.model, view: s.model[section]!).build()
            guard let item = g.items.first(where: { $0.elementID == grid }) else { return nil }
            for p in item.primitives { if case .polyline(let pts, _, _) = p, pts.count == 2 { return (min(pts[0].y, pts[1].y), max(pts[0].y, pts[1].y)) } }
            return nil
        }
        let full = try #require(span(), "the section crosses the grid")
        s.perform("Extents") { tx in tx.update(grid) { $0.grid?.bottomElevation = 1; $0.grid?.topElevation = 2.5 } }
        let limited = try #require(span())
        #expect(Fx.approx(limited.0, 1) && Fx.approx(limited.1, 2.5), "limited to its 3D extents: \(limited), full \(full)")
        s.perform("Above") { tx in tx.update(grid) { $0.grid?.bottomElevation = 500; $0.grid?.topElevation = 501 } }
        #expect(span() == nil || span()!.1 <= full.1, "a grid entirely outside the view's height isn't drawn past it")
    }

    @Test func dimensionBetweenGridsFollowsAMovedGrid() throws {
        var g1: ElementID!, g2: ElementID!, dim: ElementID!
        let (s, ids) = session { tx, ids in
            g1 = tx.create(.grids, name: "A", data: .grid(GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(0, 10))))))
            g2 = tx.create(.grids, name: "B", data: .grid(GridData(curve: .line(Segment2(Vec2(6, 0), Vec2(6, 10))))))
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [GeometryReference(g1, .location), GeometryReference(g2, .location)],
                                                                        linePoint: Vec2(3, 11))),
                            typeID: ids.systemTypes["Dimension"], ownerViewID: ids.planViews[ids.levels[0]])
        }
        #expect(DimensionQueries.measure(s.model[dim]!, s.model).map { ($0 * 1000).rounded() } == [6000])
        s.perform("Move") { tx in tx.update(g2) { $0.grid?.curve = .line(Segment2(Vec2(7.5, 0), Vec2(7.5, 10))) } }
        #expect(DimensionQueries.measure(s.model[dim]!, s.model).map { ($0 * 1000).rounded() } == [7500])
    }
}
