import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F810: View tab features: Show/Remove Hidden Lines, Cut Profile, Framing Elevation, sketched callouts, walkthroughs,
/// matchlines, Duplicate Sheet, guide grids, renderings and the commands' catalog entries.
@MainActor
@Suite("F810 view, sheets and presentation")
struct F810Tests {
    /// A session on `m` with a plan tool context.
    func context(_ m: BIMModel, view: ElementID) -> ToolContext {
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: view)
        ctx.pixel = 0.01
        return ctx
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }
    func graphics(_ m: BIMModel, _ view: ElementID) -> ViewGraphics { ViewGraphicsBuilder(model: m, view: m[view]!).build() }
    func points(_ p: GPrimitive) -> [Vec2] {
        switch p {
        case .polyline(let q, _, _): q
        case .fill(let ps, _): ps.flatMap(\.points)
        case .arc(let a, _): [a.point(at: 0), a.point(at: 1)]
        case .text(let t): [t.position]
        }
    }
    func dashedLines(_ g: ViewGraphics, _ id: ElementID) -> [[Vec2]] {
        g.items.filter { $0.elementID == id }.flatMap(\.primitives).compactMap { p -> [Vec2]? in
            if case .polyline(let q, _, let st) = p, st.pattern == .hidden { return q }
            return nil
        }
    }

    // MARK: Show / Remove Hidden Lines

    @Test func hiddenLinesDashAFloorUnderTheWallsInPlan() throws {
        var b = try Fx.box()
        var floor = ElementID(0)
        let (ids, l1) = (b.ids, b.l1)
        try Fx.commit(&b.model) { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes.values.first, levelID: l1)
        }
        let plan = b.plan.id
        #expect(dashedLines(graphics(b.model, plan), floor).isEmpty)
        let ctx = context(b.model, view: plan)
        let show = HiddenLinesTool(ctx: ctx, show: true)
        click(show, Vec2(10, 4), hit: b.walls[1])
        #expect(show.obscuring == b.walls[1] && show.prompt == "Select element whose lines are hidden.")
        // The wall lies on top: the second pick looks past it to the floor below.
        var second = ToolInput(point: Vec2(10, 4), rawPoint: Vec2(10, 4))
        second.hit = b.walls[1]
        second.hitCandidates = [b.walls[1], floor]
        show.pointerMoved(second)
        show.pointerDown(second)
        #expect(ctx.model[plan]?.view?.hiddenLines == [HiddenLinePair(obscuring: b.walls[1], hidden: floor)])
        // The floor's east edge runs along the east wall's centreline: dashed, on top of the wall's poché.
        let dashed = dashedLines(graphics(ctx.model, plan), floor)
        #expect(!dashed.isEmpty)
        #expect(dashed.flatMap { $0 }.allSatisfy { Fx.approx($0.x, 10, 0.11) })
        // Only in this view: the Level 2 plan is unchanged.
        #expect(ctx.model[b.ids.planViews[b.l2]!]?.view?.hiddenLines == nil)
        // Remove Hidden Lines takes the same two picks.
        let remove = HiddenLinesTool(ctx: ctx, show: false)
        click(remove, Vec2(10, 4), hit: b.walls[1])
        click(remove, Vec2(10, 4), hit: floor)
        #expect(ctx.model[plan]?.view?.hiddenLines == nil)
        #expect(dashedLines(graphics(ctx.model, plan), floor).isEmpty)
        // Removing again says why.
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        click(remove, Vec2(10, 4), hit: b.walls[1])
        click(remove, Vec2(10, 4), hit: floor)
        #expect(messages.last == "These elements have no hidden lines shown.")
    }

    @Test func hiddenLinesDashAWallBehindAnotherInElevation() throws {
        var (m, ids) = Fx.template()
        var front = ElementID(0), back = ElementID(0), elev = ElementID(0)
        try Fx.commit(&m) { tx in
            front = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0))
            back = Fx.wall(tx, ids, Vec2(3, 3), Vec2(7, 3))
            var v = ViewData(kind: .elevation)
            v.planeOrigin = Vec3(5, -5, 0)
            v.viewDirection = Vec2(0, 1)
            v.farClip = 40
            v.cropRegion = Rect2(min: Vec2(-8, -1), max: Vec2(8, 8))
            v.cropActive = true
            elev = tx.create(.views, name: "F810 South", data: .view(v))
        }
        #expect(dashedLines(graphics(m, elev), back).isEmpty)
        try Fx.commit(&m) { tx in try HiddenLines.show(back, behind: front, in: elev, tx) }
        let dashed = dashedLines(graphics(m, elev), back)
        // The back wall's outline (4 m wide) is hidden by the front wall: its edges come back dashed.
        #expect(dashed.count >= 4)
        let us = dashed.flatMap { $0 }.map(\.x)
        #expect(Fx.approx((us.max() ?? 0) - (us.min() ?? 0), 4, 0.05))
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try HiddenLines.show(back, behind: back, in: elev, tx) } }
    }

    // MARK: Cut Profile

    @Test func cutProfilesReshapeAWallInOneViewOnly() throws {
        var (m, ids) = Fx.template()
        var wall = ElementID(0), other = ElementID(0)
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(4, 0))
            var copy = tx.model[plan]!.view!
            copy.hiddenLines = nil
            other = tx.create(.views, name: "Level 1 Copy", data: .view(copy), levelID: ids.levels[0])
        }
        func maxY(_ m: BIMModel, _ v: ElementID) -> Double {
            graphics(m, v).items.filter { $0.elementID == wall && $0.layer == .cut }.flatMap(\.primitives).flatMap(points).map(\.y).max() ?? -1
        }
        #expect(Fx.approx(maxY(m, plan), 0.1, 1e-6))
        // Pick the wall, then sketch a bump on its north face: it joins the wall in this view.
        let ctx = context(m, view: plan)
        let pick = CutProfileTool(ctx: ctx)
        var picked: ElementID?
        pick.onPicked = { picked = $0 }
        click(pick, Vec2(1.5, 0), hit: wall)
        #expect(picked == wall)
        let sketch = SketchTool(ctx: ctx, target: .f810(.cutProfile(wall: wall)), commandID: .cutProfile)
        sketch.setOption("mode", .text("Rectangle"))
        click(sketch, Vec2(1, 0)); click(sketch, Vec2(2, 0.8))
        #expect(sketch.finish())
        let cp = try #require(ctx.model.elements(.cutProfiles).first)
        #expect(cp.cutProfile?.adds == true && cp.hostID == wall && cp.ownerViewID == plan)
        #expect(Fx.approx(maxY(ctx.model, plan), 0.8, 1e-6))
        #expect(Fx.approx(maxY(ctx.model, other), 0.1, 1e-6))
        // A region mostly inside the wall cuts it away.
        var m2 = ctx.model
        try Fx.commit(&m2) { tx in try CutProfiles.create(region: [Vec2(3, -0.2), Vec2(3.5, -0.2), Vec2(3.5, 0.05), Vec2(3, 0.05)], wall: wall, view: plan, tx) }
        let cut = try #require(m2.elements(.cutProfiles).first { $0.cutProfile?.adds == false })
        #expect(cut.cutProfile?.region.count == 4)
        // A region away from the wall is refused.
        #expect(throws: TransactionError.self) { try Fx.commit(&m2) { tx in try CutProfiles.create(region: [Vec2(0, 3), Vec2(1, 3), Vec2(1, 4)], wall: wall, view: plan, tx) } }
        // Moving the wall moves its cut profiles.
        let before = try #require(m2.elements(.cutProfiles).first { $0.cutProfile?.adds == true }?.cutProfile?.region.first)
        try Fx.commit(&m2) { tx in try ElementOperations.transform([wall], by: .translation(Vec2(0, 1)), in: tx, viewID: plan) }
        let after = try #require(m2.elements(.cutProfiles).first { $0.cutProfile?.adds == true }?.cutProfile?.region.first)
        #expect(Fx.approx(after, before + Vec2(0, 1)))
        // Deleting the wall deletes its cut profiles.
        try Fx.commit(&m2) { tx in tx.delete(wall) }
        #expect(m2.elements(.cutProfiles).isEmpty)
    }

    // MARK: Framing Elevation

    @Test func framingElevationLooksAtItsGrid() throws {
        var (m, ids) = Fx.template()
        var grid = ElementID(0), across = ElementID(0)
        try Fx.commit(&m) { tx in
            grid = tx.create(.grids, name: "1", data: .grid(GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(0, 6))))))
            across = tx.create(.grids, name: "A", data: .grid(GridData(curve: .line(Segment2(Vec2(-3, 2), Vec2(3, 2))))))
        }
        let ctx = context(m, view: ids.planViews[ids.levels[0]]!)
        let tool = FramingElevationTool(ctx: ctx)
        // Clicked east of a north-south grid: the view looks west at it, cropped to its length.
        click(tool, Vec2(2, 3), hit: grid)
        let v = try #require(ctx.model.views.first { $0.name.hasPrefix("Elevation") && $0.name.hasSuffix("- a") })
        let vd = try #require(v.view)
        #expect(vd.kind == .elevation && vd.cropActive && vd.cropVisible)
        #expect(Fx.approx(Vec2(vd.planeOrigin!.x, vd.planeOrigin!.y), Vec2(1.5, 3)) && Fx.approx(vd.viewDirection!, Vec2(-1, 0)))
        #expect(Fx.approx(vd.cropRegion!.width, 6))
        let zs = ctx.model.levels.compactMap { $0.level?.elevation }
        #expect(Fx.approx(vd.cropRegion!.min.y, zs.min()! - 1) && Fx.approx(vd.cropRegion!.max.y, zs.max()! + 3))
        // Grids running into the view show in it, inside the crop.
        let g = graphics(ctx.model, v.id)
        #expect(g.items.contains { $0.elementID == across })
    }

    // MARK: Callout ▸ Sketch

    @Test func sketchedCalloutsClipToTheirBoundary() throws {
        let b = try Fx.box()
        let plan = b.plan.id
        let ctx = context(b.model, view: plan)
        let tool = SketchTool(ctx: ctx, target: .callout, commandID: .calloutSketch)
        tool.drawMode = .line
        let tri = [Vec2(-1, -1), Vec2(6, -1), Vec2(-1, 5)]
        for p in tri + [tri[0]] { click(tool, p) }
        #expect(tool.finish())
        let callout = try #require(ctx.model.views.first { $0.view?.parentViewID == plan })
        let vd = try #require(callout.view)
        #expect(vd.cropShape?.count == 3 && vd.cropActive && vd.scale == 50)
        let shape = Polygon2(tri)
        let g = graphics(ctx.model, callout.id)
        let model = g.items.filter { $0.layer != .annotation && $0.layer != .overlay && $0.elementID != nil }
        #expect(!model.isEmpty)
        #expect(model.flatMap(\.primitives).flatMap(points).allSatisfy { shape.contains($0) || shape.distanceToBoundary($0) < 1e-6 })
        // The west wall reaches beyond the boundary in the parent but is cut to it in the callout.
        let west = model.filter { $0.elementID == b.walls[3] }.flatMap(\.primitives).flatMap(points).map(\.y).max() ?? 0
        #expect(west < 5)
        // The crop outline and the parent's callout marker follow the sketch.
        #expect(g.items.contains { $0.layer == .overlay && $0.primitives.contains { if case .polyline(let q, true, _) = $0 { return q.count == 3 }; return false } })
        let marker = try #require(graphics(ctx.model, plan).items.first { $0.elementID == callout.id })
        #expect(marker.primitives.contains { if case .polyline(let q, true, _) = $0 { return q.count == 3 }; return false })
        // An open sketch is refused.
        let open = SketchTool(ctx: ctx, target: .callout, commandID: .calloutSketch)
        open.drawMode = .line
        click(open, Vec2(0, 0)); click(open, Vec2(2, 0)); click(open, Vec2(2, 2))
        #expect(!open.finish())
    }

    @Test func clippingToAPolygonKeepsTheInsideParts() {
        let tri = Polygon2([Vec2(0, 0), Vec2(4, 0), Vec2(0, 4)])
        let line = GPrimitive.polyline([Vec2(-1, 1), Vec2(5, 1)], closed: false, .thin)
        let out = ViewGraphicsBuilder.clipPrimitive(line, to: tri)
        #expect(out.count == 1)
        if case .polyline(let q, _, _) = out[0] { #expect(Fx.approx(q.first!, Vec2(0, 1)) && Fx.approx(q.last!, Vec2(3, 1))) }
        let fill = GPrimitive.fill([.rectangle(Rect2(min: Vec2(-1, -1), max: Vec2(1, 1)))], GFill(pattern: .solid))
        if case .fill(let ps, _) = ViewGraphicsBuilder.clipPrimitive(fill, to: tri).first { #expect(Fx.approx(ps.reduce(0) { $0 + $1.area }, 1, 1e-6)) }
        else { Issue.record("The fill was dropped.") }
        #expect(ViewGraphicsBuilder.clipPrimitive(.text(GText(position: Vec2(3, 3), height: 0.003, string: "x")), to: tri).isEmpty)
        let split = PresentationGeometry.split([Vec2(-1, 1), Vec2(5, 1)], closed: false, by: [tri])
        #expect(split.inside.count == 1 && split.outside.count == 2)
    }

    // MARK: Walkthrough

    @Test func walkthroughsMoveTheirCameraAlongThePath() throws {
        let (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        let ctx = context(m, view: plan)
        let tool = WalkthroughTool(ctx: ctx)
        var opened: ElementID?
        tool.onCreated = { opened = $0 }
        click(tool, Vec2(0, 0))
        #expect(!tool.finish())
        click(tool, Vec2(10, 0)); click(tool, Vec2(10, 10))
        #expect(tool.finish())
        let v = try #require(opened.flatMap { ctx.model[$0] })
        #expect(v.name == "Walkthrough 1" && v.isCameraView)
        let w = try #require(v.view?.walkthrough)
        #expect(w.frames == 300 && w.frame == 1 && w.path.count == 3)
        let z = ctx.model.elevation(ofLevel: ids.levels[0]) + 1.75
        #expect(v.view?.camera?.eye.isAlmostEqual(Vec3(0, 0, z)) == true && v.view?.camera?.isPerspective == true)
        // Frame 150 of 300 is near the corner, looking along the path.
        _ = ctx.session.perform("Frame") { tx in try Walkthroughs.setFrame(150, of: v.id, tx) }
        let c = try #require(ctx.model[v.id]?.view?.camera)
        #expect(abs(c.eye.x - 10) < 0.2 && abs(c.eye.y) < 0.2 && c.target.distance(to: c.eye) > 0.9)
        #expect(ctx.model[v.id]?.view?.walkthrough?.frame == 150)
        _ = ctx.session.perform("Frame") { tx in try Walkthroughs.setFrame(999, of: v.id, tx) }
        #expect(ctx.model[v.id]?.view?.camera?.eye.isAlmostEqual(Vec3(10, 10, z)) == true)
        #expect(ctx.model[v.id]?.view?.walkthrough?.frame == 300)
        // The path shows in the plan of its level.
        let g = graphics(ctx.model, plan)
        #expect(g.items.contains { $0.elementID == v.id && $0.targetViewID == v.id })
        // Properties: Total Frames and Frame, which moves the camera.
        var mm = ctx.model
        #expect(Parameters.value(ParameterID("walkthrough.frames"), of: mm[v.id]!, mm) == .int(300))
        try Fx.commit(&mm) { tx in
            try Parameters.set(ParameterID("walkthrough.frames"), to: .int(3), on: v.id, in: tx)
            try Parameters.set(ParameterID("walkthrough.frame"), to: .int(2), on: v.id, in: tx)
        }
        #expect(mm[v.id]?.view?.walkthrough?.frames == 3 && mm[v.id]?.view?.camera?.eye.isAlmostEqual(Vec3(10, 0, z)) == true)
    }

    // MARK: Matchline

    @Test func matchlinesShowInEveryPlan() throws {
        let (m, ids) = Fx.template()
        let ctx = context(m, view: ids.planViews[ids.levels[0]]!)
        let tool = MatchlineTool(ctx: ctx)
        click(tool, Vec2(2, -3))
        #expect(tool.prompt == "Click the end of the matchline.")
        click(tool, Vec2(2, 3))
        let ml = try #require(ctx.model.elements(.matchlines).first)
        #expect(ml.matchline == MatchlineData(start: Vec2(2, -3), end: Vec2(2, 3)) && ml.ownerViewID == nil)
        var moved = ctx.model
        try Fx.commit(&moved) { tx in try ElementOperations.transform([ml.id], by: .translation(Vec2(1, 0)), in: tx, viewID: nil) }
        #expect(moved[ml.id]?.matchline?.start == Vec2(3, -3))
        for l in ids.levels {
            let item = graphics(ctx.model, ids.planViews[l]!).items.first { $0.elementID == ml.id }
            #expect(item?.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.pattern == .dashDot }; return false } == true)
        }
        #expect(throws: TransactionError.self) { var mm = ctx.model; try Fx.commit(&mm) { tx in try Matchlines.create(from: .zero, to: .zero, tx) } }
    }

    // MARK: Sheets

    @Test func duplicateSheetCopiesTheSheetButNotItsViewports() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        var sheet = ElementID(0)
        try Fx.commit(&m) { tx in
            sheet = tx.create(.sheets, name: "Plans", data: .sheet(SheetData(number: "A201", paper: .a1, titleBlockTypeID: ids.titleBlocks["A1 Title Block"])))
            tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.4, 0.3), detailNumber: "1")), ownerViewID: sheet)
            tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(0.1, 0.1), text: "General notes")), ownerViewID: sheet)
        }
        var plain = ElementID(0), detailed = ElementID(0)
        try Fx.commit(&m) { tx in
            plain = try SheetDuplication.duplicate(sheet, withDetailing: false, in: tx)
            detailed = try SheetDuplication.duplicate(sheet, withDetailing: true, in: tx)
        }
        let a = try #require(m[plain]), b2 = try #require(m[detailed])
        #expect(a.sheet?.number == "A202" && a.name == "Plans Copy" && a.sheet?.titleBlockTypeID == ids.titleBlocks["A1 Title Block"])
        #expect(b2.sheet?.number == "A203" && b2.name == "Plans Copy 2")
        #expect(m.owned(byView: plain).isEmpty)
        let owned = m.owned(byView: detailed)
        #expect(owned.count == 1 && owned[0].textNote?.text == "General notes")
        #expect(SheetDuplication.nextNumber(after: "S", in: m) == "S101")
    }

    @Test func viewportsSnapToTheGuideGrid() throws {
        let boxes = [Rect2(min: Vec2(0.101, 0.2), max: Vec2(0.301, 0.4))]
        // Moved 0.0485 right: the left edge lands at 0.1495, 0.5 mm from the 150 mm line.
        let v = GuideGrids.snap(Vec2(0.0485, 0.0), boxes: boxes, spacing: 0.025, tolerance: 0.002)
        #expect(Fx.approx(boxes[0].min.x + v.x, 0.15, 1e-9) || Fx.approx(boxes[0].max.x + v.x, 0.35, 1e-9))
        // Too far from a line: unchanged.
        #expect(Fx.approx(GuideGrids.snap(Vec2(0.0125, 0), boxes: [Rect2(min: Vec2(0.0001, 0), max: Vec2(0.0001, 0))], spacing: 0.025, tolerance: 0.001), Vec2(0.0125, 0)))
        // A cropped view's viewport box is its crop at the view scale.
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        var vp = ElementID(0)
        try Fx.commit(&m) { tx in
            tx.update(plan) { $0.view?.cropActive = true; $0.view?.cropRegion = Rect2(min: .zero, max: Vec2(10, 5)) }
            let s = tx.create(.sheets, name: "S", data: .sheet(SheetData(number: "A1")))
            vp = tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.4, 0.3), detailNumber: "1")), ownerViewID: s)
        }
        let vpe = try #require(m[vp])
        let box = try #require(GuideGrids.viewportBox(vpe, m))
        let scale = Double(m[plan]!.view!.scale)
        #expect(Fx.approx(box.width, 10 / scale) && Fx.approx(box.center, Vec2(0.4, 0.3)))
    }

    // MARK: Renderings

    @Test func renderingsAreSavedInTheProject() throws {
        var (m, _) = Fx.template()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try Fx.commit(&m) { tx in
            let r = RenderingData(png: png, width: 640, height: 400, viewID: nil, quality: "Medium", sunLighting: true, skyBackground: true)
            try Renderings.save(r, name: Renderings.nextName(for: "{3D}", tx.model), tx)
            try Renderings.save(r, name: Renderings.nextName(for: "{3D}", tx.model), tx)
        }
        #expect(Set(Renderings.all(m).map(\.name)) == ["{3D}_1", "{3D}_2"])
        #expect(Renderings.all(m).first?.rendering?.png == png)
        // Saved renderings round-trip through the element encoding.
        let e = try #require(Renderings.all(m).first)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(e))
        #expect(back.rendering == e.rendering)
        #expect(throws: TransactionError.self) {
            try Fx.commit(&m) { tx in try Renderings.save(RenderingData(png: Data(), width: 0, height: 0, viewID: nil, quality: "Draft", sunLighting: false, skyBackground: false), name: "x", tx) }
        }
    }

    @Test func viewDataFromOlderFilesHasNoNewFields() throws {
        // A view written before F810 (no crop shape, hidden lines or walkthrough) decodes with them absent.
        var v = ViewData(kind: .floorPlan)
        v.cropShape = [Vec2(0, 0), Vec2(1, 0), Vec2(0, 1)]
        v.walkthrough = WalkthroughData(path: [.zero, Vec3(1, 0, 0)])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(v))
        var json = try #require(obj as? [String: Any])
        #expect(json["cropShape"] != nil && json["walkthrough"] != nil)
        json.removeValue(forKey: "cropShape"); json.removeValue(forKey: "walkthrough"); json.removeValue(forKey: "hiddenLines")
        let old = try JSONDecoder().decode(ViewData.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.cropShape == nil && old.walkthrough == nil && old.hiddenLines == nil && old.kind == .floorPlan)
    }

    // MARK: Commands

    @Test func commandsHaveRevitCraftNamesAndAliases() {
        let ids: [CommandID] = [.showHiddenLines, .removeHiddenLines, .cutProfile, .framingElevation, .calloutSketch, .walkthrough, .finishWalkthrough,
                                .walkthroughPreviousFrame, .walkthroughNextFrame, .walkthroughPlay, .walkthroughExport, .titleBlock, .guideGrid, .matchline,
                                .switchWindows, .tabViews, .tileViews, .canvasTheme, .navigationWheel, .render, .renderGallery, .exportOBJ]
        for id in ids { #expect(CommandCatalog.all.filter { $0.id == id }.count == 1, "\(id)") }
        #expect(CommandCatalog.info(.tabViews).aliases == ["TW"] && CommandCatalog.info(.tileViews).aliases == ["WT"] && CommandCatalog.info(.render).aliases == ["RR"])
        #expect(CommandCatalog.info(.exportOBJ).title == "Export OBJ")
        // No third-party product names.
        #expect(!CommandCatalog.f810Commands.contains { $0.title.contains("Twinmotion") || $0.help.contains("Twinmotion") })
        let aliases = CommandCatalog.all.flatMap(\.aliases)
        for a in ["TW", "WT", "RR"] { #expect(aliases.filter { $0 == a }.count == 1, "\(a)") }
    }
}
