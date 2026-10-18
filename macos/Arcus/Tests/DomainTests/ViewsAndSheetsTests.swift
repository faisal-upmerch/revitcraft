import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// MARK: - Scope boxes (V2)

@Suite("Scope boxes")
struct ScopeBoxTests {
    /// A box model with a scope box east of the building and grid A inside it, grid B unassigned.
    func setup() throws -> (Fx.Box, scope: ElementID, gridA: ElementID, gridB: ElementID) {
        var box = try Fx.box()
        var scope: ElementID!, a: ElementID!, b: ElementID!
        try Fx.commit(&box.model) { tx in
            scope = tx.create(.scopeBoxes, name: "East Wing",
                              data: .scopeBox(ScopeBoxData(rect: Rect2(min: Vec2(20, 0), max: Vec2(30, 10)), bottomElevation: -1, topElevation: 10)))
            var ga = GridData(curve: .line(Segment2(Vec2(25, -5), Vec2(25, 15))))
            ga.scopeBoxID = scope
            a = tx.create(.grids, name: "A", data: .grid(ga))
            b = tx.create(.grids, name: "B", data: .grid(GridData(curve: .line(Segment2(Vec2(5, -5), Vec2(5, 15))))))
        }
        return (box, scope, a, b)
    }

    func items(_ g: ViewGraphics, _ id: ElementID) -> [GItem] { g.items.filter { $0.elementID == id } }

    @Test func gridOutsideTheScopeBoxIsNotDrawnWhereTheCropLiesElsewhere() throws {
        var (box, _, a, b) = try setup()
        let plan = box.ids.planViews[box.l1]!
        try Fx.commit(&box.model) { tx in
            tx.update(plan) { $0.view?.cropActive = true; $0.view?.cropRegion = Rect2(min: Vec2(-1, -1), max: Vec2(11, 9)) }
        }
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[plan]!).build()
        #expect(items(g, a).isEmpty, "grid A belongs to a scope box the crop doesn't reach")
        #expect(!items(g, b).isEmpty, "grid B has no scope box")
    }

    @Test func gridInAScopeBoxIsTrimmedToIt() throws {
        let (box, _, a, _) = try setup()
        let g = ViewGraphicsBuilder(model: box.model, view: box.plan).build()
        let item = try #require(items(g, a).first)
        let pts = item.primitives.compactMap { p -> [Vec2]? in if case .polyline(let pts, _, _) = p { return pts } else { return nil } }.flatMap { $0 }
        #expect(!pts.isEmpty)
        #expect(pts.allSatisfy { $0.y >= -1e-6 && $0.y <= 10 + 1e-6 }, "the line stays inside the box (0…10)")
    }

    @Test func scopeBoxIsDrawnOnlyInPlansItsHeightReaches() throws {
        var (box, scope, _, _) = try setup()
        #expect(!items(ViewGraphicsBuilder(model: box.model, view: box.plan).build(), scope).isEmpty)
        try Fx.commit(&box.model) { tx in tx.update(scope) { $0.scopeBox?.topElevation = 0.5 } }
        #expect(items(ViewGraphicsBuilder(model: box.model, view: box.plan).build(), scope).isEmpty, "Level 1's cut plane (1.2 m) is above the box")
    }

    @Test func planViewAssignedToAScopeBoxCropsToIt() throws {
        var (box, scope, _, _) = try setup()
        let plan = box.ids.planViews[box.l1]!
        try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("view.scopeBox"), to: .ref(scope), on: plan, in: tx) }
        #expect(box.model[plan]?.view?.scopeBoxID == scope)
        try Fx.commit(&box.model) { tx in tx.update(scope) { $0.scopeBox?.center = Vec2(40, 5) } }
        let r = VisibilityResolver(model: box.model, view: box.model[plan]!)
        #expect(r.data.cropActive)
        #expect(r.data.cropRegion == Rect2(min: Vec2(35, 0), max: Vec2(45, 10)), "the crop follows the moved box")
    }

    @Test func datumScopeBoxParameterValidatesTheReference() throws {
        var (box, scope, _, b) = try setup()
        try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("datum.scopeBox"), to: .ref(scope), on: b, in: tx) }
        #expect(box.model[b]?.grid?.scopeBoxID == scope)
        #expect(Parameters.value(ParameterID("datum.scopeBox"), of: box.model[b]!, box.model) == .ref(scope))
        #expect(throws: (any Error).self) {
            let level = box.l1
            try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("datum.scopeBox"), to: .ref(level), on: b, in: tx) }
        }
    }

    @Test func deletingAScopeBoxReleasesItsDatumsAndViews() throws {
        var (box, scope, a, _) = try setup()
        let plan = box.ids.planViews[box.l1]!
        try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("view.scopeBox"), to: .ref(scope), on: plan, in: tx) }
        try Fx.commit(&box.model) { tx in tx.delete(scope) }
        #expect(box.model[a]?.grid?.scopeBoxID == nil)
        #expect(box.model[plan]?.view?.scopeBoxID == nil)
        #expect(box.model[plan]?.view?.cropRegion == Rect2(min: Vec2(20, 0), max: Vec2(30, 10)), "the view keeps the box's extent as its crop")
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[box.ids.planViews[box.l2]!]!).build()
        #expect(g.items.contains { $0.elementID == a }, "grid A now shows everywhere")
    }

    @Test func rotatedBoxClipsAndIntersects() {
        let sb = ScopeBoxData(center: .zero, halfSize: Vec2(2, 1), rotation: .pi / 4, bottomElevation: 0, topElevation: 3)
        #expect(sb.contains(Vec2(1, 1)))
        #expect(!sb.contains(Vec2(2, -2)))
        let c = sb.clip(Segment2(Vec2(-10, -10), Vec2(10, 10)))
        #expect(c.map { Fx.approx($0.length, 4, 1e-9) } == true, "the diagonal runs along the 4 m local x axis")
        #expect(sb.clip(Segment2(Vec2(5, -5), Vec2(6, -4))) == nil)
        #expect(sb.intersects(Rect2(min: Vec2(0.5, 0.5), max: Vec2(3, 3))))
        #expect(!sb.intersects(Rect2(min: Vec2(1.6, -3), max: Vec2(3, -1.6))), "inside the bounds but outside the rotated box")
    }

    @Test func moveAndRotateAScopeBox() throws {
        var e = Element(id: ElementID(1), category: .scopeBoxes, data: .scopeBox(ScopeBoxData(center: Vec2(1, 0), halfSize: Vec2(1, 1), bottomElevation: 0, topElevation: 1)))
        #expect(ElementTransform.isTransformable(e))
        ElementTransform.apply(.rotation(.pi / 2), to: &e)
        #expect(Fx.approx(e.scopeBox!.center, Vec2(0, 1), 1e-9))
        #expect(Fx.approx(e.scopeBox!.rotation, .pi / 2, 1e-9))
    }

    @Test func levelInAScopeBoxIsHiddenInAnElevationThatDoesNotSeeIt() throws {
        var (box, scope, _, _) = try setup()
        let l2 = box.l2
        try Fx.commit(&box.model) { tx in tx.update(l2) { $0.level?.scopeBoxID = scope } }
        // The template's elevations look at the building; find one whose depth range misses the east-wing box.
        let elevations = box.model.views.filter { $0.view?.kind == .elevation }
        #expect(!elevations.isEmpty)
        var hiddenSomewhere = false
        for v in elevations {
            let g = ViewGraphicsBuilder(model: box.model, view: v).build()
            if items(g, box.l2).isEmpty { hiddenSomewhere = true }
            #expect(!items(g, box.l1).isEmpty, "Level 1 has no scope box and shows everywhere")
        }
        #expect(hiddenSomewhere)
    }
}

// MARK: - Sheets (S1)

@Suite("Placing views on sheets")
struct SheetPlacementTests {
    @Test func droppingAViewCreatesAViewportThenTheOneSheetRuleRefuses() throws {
        var box = try Fx.box()
        let sheet = box.model.sheets[0].id
        let plan = box.ids.planViews[box.l1]!
        var second: ElementID!
        try Fx.commit(&box.model) { tx in second = tx.create(.sheets, name: "Sections", data: .sheet(SheetData(number: "A102"))) }
        var vp: ElementID!
        try Fx.commit(&box.model) { tx in vp = try SheetPlacement.place(plan, onSheet: sheet, at: Vec2(0.3, 0.25), in: tx) }
        let data = try #require(box.model[vp]?.viewport)
        #expect(data.viewID == plan && data.center == Vec2(0.3, 0.25) && data.detailNumber == "1")
        #expect(box.model[vp]?.ownerViewID == sheet)
        // Dropping it again, here or on another sheet, raises the one-sheet error.
        for target in [sheet, second!] {
            #expect(SheetPlacement.refusal(plan, onSheet: target, box.model)?.contains("one sheet") == true)
            #expect(throws: TransactionError.self) { try Fx.commit(&box.model) { tx in try SheetPlacement.place(plan, onSheet: target, at: .zero, in: tx) } }
        }
        #expect(box.model.viewports(showing: plan).count == 1)
    }

    @Test func schedulesAndLegendsGoOnManySheets() throws {
        var box = try Fx.box()
        let sheet = box.model.sheets[0].id
        var second: ElementID!, legend: ElementID!
        try Fx.commit(&box.model) { tx in
            second = tx.create(.sheets, name: "Two", data: .sheet(SheetData(number: "A102")))
            legend = tx.create(.views, name: "Legend 1", data: .view(ViewData(kind: .legend, scale: 50)))
        }
        let schedule = try #require(box.model.schedules.first?.id)
        try Fx.commit(&box.model) { tx in
            for s in [sheet, second!] {
                try SheetPlacement.place(schedule, onSheet: s, in: tx)
                try SheetPlacement.place(legend, onSheet: s, in: tx)
            }
        }
        #expect(box.model.viewports(showing: schedule).count == 2)
        #expect(box.model.viewports(showing: legend).count == 2)
        #expect(SheetPlacement.refusal(sheet, onSheet: second, box.model) != nil, "a sheet can't be placed on a sheet")
    }

    @Test func placementMatchesTheSheetLayout() throws {
        var box = try Fx.box()
        let sheet = box.model.sheets[0].id
        let plan = box.ids.planViews[box.l1]!
        try Fx.commit(&box.model) { tx in try SheetPlacement.place(plan, onSheet: sheet, at: Vec2(0.4, 0.3), in: tx) }
        let b = SheetGraphicsBuilder(model: box.model, sheet: box.model[sheet]!)
        let (layout, g) = try #require(b.layouts().first)
        let region = SheetGraphicsBuilder.viewRegion(try #require(g))
        let (box2, t) = SheetGraphicsBuilder.placement(center: Vec2(0.4, 0.3), region: region, scale: layout.scale)
        #expect(box2 == layout.box && t == layout.transform)
        #expect(Fx.approx(t.apply(region.center), Vec2(0.4, 0.3), 1e-12))
    }
}

// MARK: - Selection Box (V3), element overrides (V4), level renames (V6)

@Suite("View tools")
struct ViewToolTests {
    @Test func selectionBoxFitsTheSelectedElements() throws {
        let box = try Fx.box()
        let walls = [box.walls[0], box.walls[1]]
        let b = try #require(SelectionBox.box(for: walls, box.model, margin: 0.3))
        let union = walls.reduce(Box3.empty) { $0.union(ElementMeshes.bounds(box.model[$1]!, box.model)) }
        #expect(Fx.approx(b.min.x, union.min.x - 0.3) && Fx.approx(b.max.y, union.max.y + 0.3) && Fx.approx(b.max.z, union.max.z + 0.3))
        var v = ViewData(kind: .threeD)
        v.camera = .defaultIsometric
        SelectionBox.apply(b, to: &v)
        #expect(v.sectionBoxActive && v.sectionBox == b)
        #expect(Fx.approx(v.camera!.target.xy, b.center.xy) && Fx.approx(v.camera!.target.z, b.center.z))
        let oldDir = (Camera3D.defaultIsometric.target - Camera3D.defaultIsometric.eye).normalized
        #expect(((v.camera!.target - v.camera!.eye).normalized - oldDir).length < 1e-9, "the view direction is kept")
        #expect(SelectionBox.box(for: [box.l1, box.ids.planViews[box.l1]!], box.model) == nil, "datums and views have no 3D extent")
    }

    @Test func elementOverrideChangesOnlyThatElementInThatView() throws {
        var box = try Fx.box()
        let plan = box.ids.planViews[box.l1]!
        var o = GraphicOverride()
        o.cutLineColor = RGBColor(1, 0, 0)
        o.cutLineWeight = 9
        o.halftone = true
        let wall = box.walls[0]
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.visibility.setElementOverride(o, for: [wall]) } }
        func strokes(_ g: ViewGraphics, _ id: ElementID) -> [GStroke] {
            g.items.filter { $0.elementID == id }.flatMap(\.primitives).compactMap { if case .polyline(_, _, let s) = $0 { return s } else { return nil } }
        }
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[plan]!).build()
        #expect(strokes(g, box.walls[0]).contains { $0.color == RGBColor(1, 0, 0) && $0.weight == 9 && $0.halftone })
        #expect(!strokes(g, box.walls[1]).contains { $0.color == RGBColor(1, 0, 0) })
        let other = ViewGraphicsBuilder(model: box.model, view: box.model[box.ids.ceilingViews[box.l1]!]!).build()
        #expect(!strokes(other, box.walls[0]).contains { $0.color == RGBColor(1, 0, 0) }, "other views are unaffected")
        #expect(box.model[plan]?.view?.visibility.commonElementOverride([box.walls[0]]) == o)
        // Reset clears the entry.
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.visibility.setElementOverride(GraphicOverride(), for: [wall]) } }
        #expect(box.model[plan]?.view?.visibility.elementOverrides.isEmpty == true)
    }

    @Test func renamingALevelFindsItsPlanViews() throws {
        var box = try Fx.box()
        let oldName = box.model[box.l1]!.name
        let l1 = box.l1
        let (record, _) = try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("name"), to: .text("Ground Floor"), on: l1, in: tx) }
        let renames = LevelRename.renamedLevels(in: record)
        #expect(renames == [LevelRename.Rename(levelID: box.l1, oldName: oldName, newName: "Ground Floor")])
        let views = LevelRename.correspondingViews(renames[0], box.model)
        let plan = box.ids.planViews[box.l1]!
        #expect(views.contains { $0.viewID == plan && $0.newName == "Ground Floor" })
        if let rcp = box.ids.ceilingViews[box.l1], box.model[rcp]?.name.hasPrefix(oldName) == true {
            #expect(views.contains { $0.viewID == rcp })
        }
        #expect(views.allSatisfy { box.model[$0.viewID]?.levelID == box.l1 })
        #expect(!views.contains { $0.viewID == box.ids.planViews[box.l2]! })
        // Applying the renames passes the unique-name rules.
        try Fx.commit(&box.model) { tx in for v in views { tx.update(v.viewID) { $0.name = v.newName } } }
        #expect(box.model[plan]?.name == "Ground Floor")
    }

    @Test func renameSuffixedViewsAndSkipTakenNames() {
        let (m0, ids) = Fx.template()
        var m = m0
        let l1 = ids.levels[0]
        let old = m[l1]!.name
        var extra: ElementID!
        try? Fx.commit(&m) { tx in
            extra = tx.create(.views, name: "\(old) (Structural Plan)", data: .view(ViewData(kind: .structuralPlan)), levelID: l1)
            tx.create(.views, name: "New", data: .view(ViewData(kind: .floorPlan)), levelID: ids.levels[1])
        }
        let views = LevelRename.correspondingViews(LevelRename.Rename(levelID: l1, oldName: old, newName: "New"), m)
        #expect(views.contains { $0.viewID == extra && $0.newName == "New (Structural Plan)" })
        #expect(!views.contains { $0.viewID == ids.planViews[l1] }, "a floor plan named “New” already exists")
    }
}

// MARK: - Site markers (G1) and persistence

@Suite("Base point, survey point and cameras")
struct SiteMarkerTests {
    @Test func basePointAndSurveyPointAreOptIn() throws {
        var box = try Fx.box()
        let plan = box.ids.planViews[box.l1]!
        func cats(_ m: BIMModel) -> Set<ArcusDomain.Category> { Set(ViewGraphicsBuilder(model: m, view: m[plan]!).build().items.map(\.category)) }
        #expect(!cats(box.model).contains(.projectBasePoint) && !cats(box.model).contains(.surveyPoint))
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.visibility.setCategoryVisible(.projectBasePoint, true) } }
        #expect(cats(box.model).contains(.projectBasePoint) && !cats(box.model).contains(.surveyPoint))
        #expect(box.model[plan]!.view!.visibility.isCategoryVisible(.projectBasePoint))
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.visibility.setCategoryVisible(.projectBasePoint, false) } }
        #expect(!cats(box.model).contains(.projectBasePoint))
        #expect(box.model[plan]!.view!.visibility.shownOptInCategories == nil)
    }

    @Test func newFieldsRoundTripAndOlderDataDecodes() throws {
        var g = GridData(curve: .line(Segment2(.zero, .unitX)))
        g.scopeBoxID = ElementID(42)
        let e = Element(id: ElementID(7), category: .grids, name: "A", data: .grid(g))
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(e))
        #expect(back.grid?.scopeBoxID == ElementID(42))
        let sb = Element(id: ElementID(8), category: .scopeBoxes, name: "S", data: .scopeBox(ScopeBoxData(center: Vec2(1, 2), halfSize: Vec2(3, 4), rotation: 0.5, bottomElevation: -1, topElevation: 9)))
        #expect(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(sb)) == sb)
        // Data written before these fields existed has no keys for them.
        let old = try JSONEncoder().encode(GridData(curve: .line(Segment2(.zero, .unitX))))
        #expect(!String(decoding: old, as: UTF8.self).contains("scopeBoxID"))
        #expect(try JSONDecoder().decode(GridData.self, from: old).scopeBoxID == nil)
        let vg = try JSONDecoder().decode(VisibilityGraphics.self, from: JSONEncoder().encode(VisibilityGraphics()))
        #expect(vg.shownOptInCategories == nil)
    }
}

// MARK: - Tools (V1 camera, V7 grid Pick Lines, scope box tool)

@MainActor
@Suite("View placement tools")
struct ViewPlacementToolTests {
    func context() throws -> (ToolContext, Fx.Box) {
        let box = try Fx.box()
        let session = DocumentSession(model: box.model)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: box.ids.planViews[box.l1]!)
        ctx.pixel = 0.01
        return (ctx, box)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2) {
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
    }

    @Test func cameraToolCreatesAPerspectiveView() throws {
        let (ctx, box) = try context()
        let tool = CameraTool(ctx: ctx)
        var opened: ElementID?
        tool.onCreated = { opened = $0 }
        tool.setOption("eyeHeight", .double(1.6))
        click(tool, Vec2(-5, 4))
        #expect(opened == nil)
        click(tool, Vec2(5, 4))
        let v = try #require(opened.flatMap { ctx.model[$0] })
        let cam = try #require(v.view?.camera)
        let z = ctx.model.elevation(ofLevel: box.l1)
        #expect(v.view?.kind == .threeD && cam.isPerspective)
        #expect(cam.eye == Vec3(-5, 4, z + 1.6) && cam.target == Vec3(5, 4, z + CameraViews.defaultTargetHeight))
        #expect(v.levelID == box.l1 && v.name.hasPrefix("3D View"))
        // The camera shows in the plan of its level, selects its view and opens it on double-click.
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.model[box.ids.planViews[box.l1]!]!).build()
        let glyph = try #require(g.items.first { $0.category == .cameras })
        #expect(glyph.elementID == v.id && glyph.targetViewID == v.id)
        #expect(!ViewGraphicsBuilder(model: ctx.model, view: ctx.model[box.ids.planViews[box.l2]!]!).build().items.contains { $0.category == .cameras })
        // Eye height is a view parameter.
        ctx.session.perform("Eye") { tx in try Parameters.set(ParameterID("view.eyeHeight"), to: .double(2.5), on: v.id, in: tx) }
        #expect(Fx.approx(ctx.model[v.id]!.view!.camera!.eye.z, z + 2.5))
    }

    @Test func gridPickLinesCreatesAGridOnAWallLine() throws {
        let (ctx, box) = try context()
        let g = ViewGraphicsBuilder(model: ctx.model, view: box.plan).build()
        ctx.snapIndex = SnapIndex(graphics: g, model: ctx.model, view: box.plan)
        let tool = LineTool(ctx: ctx, kind: .grid, commandID: .gridPickLines)
        tool.pickLines = true
        #expect(tool.options.contains { $0.id == "mode" && $0.value == .text("Pick Lines") })
        click(tool, Vec2(4, 0.02))
        let grids = ctx.model.elements(.grids)
        #expect(grids.count == 1)
        let seg = try #require(grids.first?.grid?.curve.asSegment)
        #expect(abs(seg.start.y) < 1e-6 && abs(seg.end.y) < 1e-6 && seg.length > 9, "the grid runs along the south wall's location line")
        click(tool, Vec2(4, 3))   // nothing to pick in the middle of the room
        #expect(ctx.model.elements(.grids).count == 1)
        tool.setOption("mode", .text("Line"))
        #expect(!tool.pickLines)
    }

    @Test func scopeBoxToolDrawsARectangle() throws {
        let (ctx, _) = try context()
        let tool = ScopeBoxTool(ctx: ctx)
        click(tool, Vec2(0, 0))
        click(tool, Vec2(12, -6))
        let sb = try #require(ctx.model.elements(.scopeBoxes).first)
        #expect(sb.name == "Scope Box 1")
        #expect(sb.scopeBox?.bounds == Rect2(min: Vec2(0, -6), max: Vec2(12, 0)))
        #expect(tool.name == "Scope Box 2")
    }
}
