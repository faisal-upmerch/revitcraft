import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-CANVAS: sketch draw tools, Offset, selection after Finish and sketch errors (ARCUS-048/049/050), wall
/// Center-ends Arc (ARCUS-042) and Scale by a factor (ARCUS-054).
@MainActor
@Suite("Sketch mode (BL-CANVAS)")
struct SketchModeBLTests {
    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2) {
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
    }
    func floorTool(_ ctx: ToolContext, _ mode: String) -> SketchTool {
        let t = SketchTool(ctx: ctx, target: .floor, commandID: .floor)
        t.setOption("mode", .text(mode))
        return t
    }

    // MARK: Draw tools

    @Test func floorDrawPanelHasTheFullToolSet() {
        let (ctx, _) = context()
        let t = SketchTool(ctx: ctx, target: .floor, commandID: .floor)
        guard case .choice(let modes)? = t.options.first(where: { $0.id == "mode" })?.kind else { Issue.record("no draw modes"); return }
        #expect(modes == ["Line", "Rectangle", "Inscribed Polygon", "Circumscribed Polygon", "Circle", "Start-End-Radius Arc", "Center-ends Arc",
                          "Tangent End Arc", "Fillet Arc", "Pick Lines", "Pick Walls"])
        #expect(t.options.contains { $0.id == "offset" })
        #expect(t.ribbonTitle(ctx.model) == "Modify | Create Floor Boundary")
        let roof = SketchTool(ctx: ctx, target: .roof, commandID: .roofFootprint)
        #expect(roof.ribbonTitle(ctx.model) == "Modify | Create Roof Footprint")
        t.setOption("mode", .text("Arc"))
        #expect(t.drawMode == .arc, "the old name still selects Start-End-Radius Arc")
    }

    @Test func circleFloorFinishesAndStaysSelected() throws {
        let (ctx, _) = context()
        let t = floorTool(ctx, "Circle")
        click(t, Vec2(5, 5))
        #expect(t.numericLabel == "Radius")
        click(t, Vec2(8, 5))
        #expect(t.curves.count == 2 && t.curves.allSatisfy { $0.asArc != nil })
        #expect(t.finish())
        let floor = try #require(ctx.model.elements(.floors).first)
        #expect(ctx.session.selection.ids == [floor.id], "the new floor stays selected after Finish")
        let slab = try #require(floor.slab)
        if case .success(let p) = slab.boundary.profile() { #expect(abs(p.area - Double.pi * 9) < 0.1) } else { Issue.record("circle profile failed") }
    }

    @Test func polygonsWithSidesAndTypedRadius() throws {
        let (ctx, _) = context()
        let t = floorTool(ctx, "Inscribed Polygon")
        t.setOption("sides", .int(5))
        click(t, Vec2(0, 0))
        t.pointerMoved(ToolInput(point: Vec2(1, 0), rawPoint: Vec2(1, 0)))
        #expect(t.numericInput("3000"))
        #expect(t.curves.count == 5)
        #expect(t.curves.allSatisfy { Fx.approx($0.start.length, 3, 1e-6) }, "corners on the 3 m circle")
        let c = floorTool(ctx, "Circumscribed Polygon")
        click(c, Vec2(0, 0))
        click(c, Vec2(2, 0))
        #expect(c.curves.count == 6)
        #expect(c.curves.allSatisfy { Fx.approx($0.midpoint.length, 2, 1e-6) }, "sides touch the 2 m circle")
        #expect(c.finish())
    }

    @Test func centerEndsTangentAndFilletArcs() throws {
        let (ctx, _) = context()
        let t = floorTool(ctx, "Center-ends Arc")
        click(t, Vec2(0, 0)); click(t, Vec2(2, 0)); click(t, Vec2(0, 5))
        let arc = try #require(t.curves.last?.asArc)
        #expect(Fx.approx(arc.radius, 2) && Fx.approx(arc.sweep, Double.pi / 2) && Fx.approx(arc.end, Vec2(0, 2)))

        let l = floorTool(ctx, "Line")
        click(l, Vec2(0, 0)); click(l, Vec2(4, 0))
        l.setOption("mode", .text("Tangent End Arc"))
        click(l, Vec2(6, 2))
        let tan = try #require(l.curves.last?.asArc)
        #expect(Fx.approx(tan.start, Vec2(4, 0)) && Fx.approx(tan.end, Vec2(6, 2)))
        #expect(abs(tan.tangent(at: 0).normalized.dot(Vec2(1, 0)) - 1) < 1e-9, "leaves the line along its direction")

        let f = floorTool(ctx, "Line")
        click(f, Vec2(0, 0)); click(f, Vec2(4, 0)); click(f, Vec2(4, 4))
        f.setOption("mode", .text("Fillet Arc"))
        click(f, Vec2(2, 0)); click(f, Vec2(4, 2))
        #expect(f.numericLabel == "Radius")
        #expect(f.numericInput("1000"))
        #expect(f.curves.count == 3)
        let fa = try #require(f.curves.last?.asArc)
        #expect(Fx.approx(fa.radius, 1) && Fx.approx(fa.center, Vec2(3, 1)))
        #expect(Fx.approx(f.curves[0].end, Vec2(3, 0)) && Fx.approx(f.curves[1].start, Vec2(4, 1)), "the lines are trimmed to the arc")
    }

    @Test func offsetAppliesToDrawnAndPickedLines() throws {
        let (ctx, ids) = context()
        ctx.session.perform("Walls") { tx in _ = Fx.boxWalls(tx, ids, w: 10, h: 8) }
        // Pick Walls: the interior face (200 mm wall on its centerline) without Offset.
        let plain = floorTool(ctx, "Pick Walls")
        click(plain, Vec2(5, 0.15))
        #expect(Fx.approx(plain.curves[0].start.y, 0.1) && Fx.approx(plain.curves[0].end.y, 0.1))
        // Offset 100 moves the boundary into the wall.
        let off = floorTool(ctx, "Pick Walls")
        off.setOption("offset", .double(0.1))
        click(off, Vec2(5, 0.15))
        #expect(Fx.approx(off.curves[0].start.y, 0) && Fx.approx(off.curves[0].end.y, 0))
        #expect(off.options.contains { $0.id == "extend" && $0.label == "Extend into Wall (to Core)" })
        // Line and rectangle honour Offset too.
        let rect = floorTool(ctx, "Rectangle")
        rect.setOption("offset", .double(0.5))
        click(rect, Vec2(0, 0)); click(rect, Vec2(4, 2))
        let b = rect.curves.reduce(Rect2.empty) { $0.union($1.bounds) }
        #expect(Fx.approx(b.min, Vec2(-0.5, -0.5)) && Fx.approx(b.max, Vec2(4.5, 2.5)))
    }

    // MARK: Errors

    @Test func openLoopErrorNamesTheLinesAndContinueKeepsTheSketch() throws {
        let (ctx, _) = context()
        var shown: [(String, [String])] = []
        var answer = 0
        var finished = false
        ctx.toolFinished = { finished = true }
        ctx.presentError = { message, _, actions, done in shown.append((message, actions)); done(answer) }
        let t = floorTool(ctx, "Line")
        click(t, Vec2(0, 0)); click(t, Vec2(4, 0)); click(t, Vec2(4, 3))
        #expect(!t.finish())
        #expect(shown.count == 1 && shown[0].1 == ["Continue", "Quit Sketch"])
        #expect(shown[0].0.contains("closed loops"))
        #expect(t.errorCurves == [0, 1], "both open lines are highlighted")
        #expect(t.preview.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.color == SketchTool.alertColor }; return false })
        #expect(!finished && t.curves.count == 2 && ctx.model.elements(.floors).isEmpty, "Continue returns to the sketch")
        answer = 1
        #expect(!t.finish())
        #expect(finished, "Quit Sketch leaves sketch mode")
    }

    @Test func validationFindsCrossingAndOverlappingLines() {
        let bow: [Curve2] = [Vec2(0, 0), Vec2(4, 4), Vec2(4, 0), Vec2(0, 4)].indices.map { i in
            let p = [Vec2(0, 0), Vec2(4, 4), Vec2(4, 0), Vec2(0, 4)]
            return .line(Segment2(p[i], p[(i + 1) % 4]))
        }
        let issues = SketchValidation.issues(bow)
        #expect(issues.map(\.kind) == [.intersecting])
        #expect(issues.first?.curves == [0, 2])
        let square = Polygon2.rectangle(Rect2(min: .zero, max: Vec2(3, 3))).edges.map { Curve2.line($0) }
        #expect(SketchValidation.issues(square).isEmpty)
        #expect(SketchValidation.issues(square + [square[0]]).first?.kind == .overlapping)
        #expect(SketchValidation.issues([]).first?.kind == .empty)
        // A branch (three lines meeting at a point) is not a closed loop.
        let branch = square + [.line(Segment2(Vec2(3, 3), Vec2(5, 5)))]
        #expect(SketchValidation.issues(branch).first { $0.kind == .openLoop }?.curves.contains(4) == true)
    }

    // MARK: Walls and Scale

    @Test func wallCenterEndsArc() throws {
        let (ctx, _) = context()
        let t = WallTool(ctx: ctx)
        t.setOption("mode", .text("Center-ends Arc"))
        #expect(t.mode == .centerArc)
        click(t, Vec2(0, 0)); click(t, Vec2(5, 0)); click(t, Vec2(0, 7))
        let w = try #require(ctx.model.elements(.walls).first)
        let a = try #require(w.wall?.location.asArc)
        #expect(Fx.approx(a.center, .zero) && Fx.approx(a.radius, 5) && Fx.approx(abs(a.sweep), Double.pi / 2))
        #expect(WallTool.Mode.arc.rawValue == "Start-End-Radius Arc")
        t.setOption("mode", .text("Arc"))
        #expect(t.mode == .arc)
    }

    @Test func scaleThreeLinesByTwo() throws {
        let (ctx, ids) = context()
        var lines: [ElementID] = []
        ctx.session.perform("Lines") { tx in
            for k in 0..<3 {
                lines.append(tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(1, Double(k)), Vec2(3, Double(k)))))), ownerViewID: ids.planViews[ids.levels[0]]!))
            }
        }
        let tool = ScaleTool(ctx: ctx, ids: lines)
        tool.setOption("scaleMethod", .text("Numerical"))
        #expect(tool.options.contains { $0.id == "scaleFactor" })
        tool.setOption("scaleFactor", .text("2"))
        click(tool, Vec2(0, 0))
        for (k, id) in lines.enumerated() {
            let s = try #require(ctx.model[id]?.modelLine?.curve.asSegment)
            #expect(Fx.approx(s.start, Vec2(2, 2 * Double(k))) && Fx.approx(s.end, Vec2(6, 2 * Double(k))))
        }
    }
}
