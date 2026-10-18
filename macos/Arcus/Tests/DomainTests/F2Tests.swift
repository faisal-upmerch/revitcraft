import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F2 (RevitCraft port, Architecture B): stacked walls, multi-segment grids, work planes, multistory stairs, roof slope
/// arrows and eave tools, slanted columns, columns at grids and at columns.
@MainActor
@Suite("F2 Architecture B")
struct F2Tests {
    func context(level: Int = 0) -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[level]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }

    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil, candidates: [ElementID] = []) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        i.hitCandidates = candidates.isEmpty ? (hit.map { [$0] } ?? []) : candidates
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    func plan(_ m: BIMModel, _ ids: ProjectTemplates.Ids, level: Int = 0) -> ViewGraphics {
        ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[level]]!]!).build()
    }

    // MARK: Stacked walls

    /// The starter stacked type and a 10 m stacked wall on Level 1, 3 m high (unconnected).
    func stackedWall(_ ctx: ToolContext, _ ids: ProjectTemplates.Ids) throws -> (wall: ElementID, type: ElementID) {
        var type: ElementID?
        ctx.session.perform("Stacked type") { tx in type = StackedWallDefaults.populate(tx) }
        let t = try #require(type)
        var w: ElementID!
        ctx.session.perform("Wall") { tx in
            var d = WallData(location: .line(Segment2(.zero, Vec2(10, 0))), unconnectedHeight: 3)
            d.topLevelID = nil
            w = tx.create(.walls, data: .wall(d), typeID: t, levelID: ids.levels[0])
        }
        return (w, t)
    }

    @Test func starterStackedTypeStacksBasicTypes() throws {
        let (ctx, ids) = context()
        let (_, t) = try stackedWall(ctx, ids)
        let td = try #require(ctx.model[t]?.typeData)
        #expect(td.systemFamily == .stackedWall && td.familyName == "Stacked Wall")
        let parts = try #require(td.stack?.parts)
        #expect(parts.count == 2)
        #expect(ctx.model[parts[0].typeID]?.name.contains("Concrete") == true && Fx.approx(parts[0].height, 0.9))
        #expect(parts[1].typeID == ids.wallTypes[Fx.brick] && parts[1].isVariable)
        // Running it again reuses the type.
        var again: ElementID?
        ctx.session.perform("Again") { tx in again = StackedWallDefaults.populate(tx) }
        #expect(again == t)
    }

    @Test func stackedWallBuildsAsItsParts() throws {
        let (ctx, ids) = context()
        let (w, _) = try stackedWall(ctx, ids)
        let m = ctx.model
        let wall = try #require(m[w])
        let parts = try #require(StackedWalls.parts(of: wall, m))
        #expect(parts.count == 2)
        let f0 = try #require(WallGeometry.frame(parts[0], m)), f1 = try #require(WallGeometry.frame(parts[1], m))
        #expect(Fx.approx(f0.baseZ, 0) && Fx.approx(f0.topZ, 0.9))
        #expect(Fx.approx(f1.baseZ, 0.9) && Fx.approx(f1.topZ, 3), "\(f1.baseZ) \(f1.topZ) \(String(describing: wall.wall))")
        #expect(Fx.approx(f0.thickness, 0.3) && Fx.approx(f1.thickness, 0.38))
        // The wall as a whole reports its thickest part.
        #expect(Fx.approx(try #require(WallGeometry.frame(wall, m)).thickness, 0.38))
        // 3D: one solid per part, each in its own material, with the parts' volumes.
        let meshes = ElementMeshes.parts(wall, m)
        #expect(meshes.count == 2)
        #expect(meshes[0].materialID != meshes[1].materialID)
        let v = meshes.reduce(0) { $0 + abs($1.mesh.signedVolume) }
        #expect(Fx.approx(v, 10 * 0.9 * 0.3 + 10 * 2.1 * 0.38, 1e-4))
    }

    @Test func stackedWallPlanShowsThePartAtTheCutPlane() throws {
        let (ctx, ids) = context()
        let (w, _) = try stackedWall(ctx, ids)
        let g = plan(ctx.model, ids)
        let cut = try #require(g.items.first { $0.elementID == w && $0.layer == .cut })
        let area = cut.hitPolygons.reduce(0) { $0 + $1.area }
        #expect(Fx.approx(area, 10 * 0.38, 1e-4), "the 1.2 m cut passes through the brick part")
        // A cut through the base course shows the concrete part.
        let base = StackedWalls.part(of: ctx.model[w]!, atZ: 0.5, ctx.model)
        #expect(Fx.approx(WallGeometry.planCut(base, atZ: 0.5, ctx.model).reduce(0) { $0 + $1.area }, 10 * 0.3, 1e-4))
    }

    @Test func stackedWallFollowsItsTypeAndKeepsTheVariablePart() throws {
        let (ctx, ids) = context()
        let (w, t) = try stackedWall(ctx, ids)
        // Edit the type in Type Properties: a 1.2 m generic course on top, the brick part stays variable.
        let editor = TypePropertiesEditor(session: ctx.session, typeID: t)
        var spec = try #require(ctx.model[t]?.typeData?.stack)
        spec.parts.append(StackedWallPart(typeID: ids.wallTypes[Fx.generic], height: 1.2))
        try editor.stage(stack: spec)
        #expect(ctx.model[t]?.typeData?.stack?.parts.count == 2, "staged, not committed")
        #expect(editor.apply())
        let m = ctx.model
        let parts = try #require(StackedWalls.parts(of: m[w]!, m))
        #expect(parts.count == 3)
        let tops = parts.compactMap { WallGeometry.frame($0, m)?.topZ }
        #expect(Fx.approx(tops[0], 0.9) && Fx.approx(tops[1], 1.8) && Fx.approx(tops[2], 3))
        // Two variable parts are refused.
        spec.parts[2].height = 0
        #expect(throws: ParameterError.self) { try editor.stage(stack: spec) }
        // Editing a part's basic type updates the stacked wall's 3D.
        #expect(DependencyGraph.inputs(of: m[w]!, m).contains(ids.wallTypes[Fx.brick]!))
    }

    @Test func stackedTypePersistsAndOlderTypesDecode() throws {
        var td = TypeData(instanceCategory: .walls, systemFamily: .stackedWall, familyName: "Stacked Wall")
        td.stack = StackedWallSpec(parts: [StackedWallPart(typeID: ElementID(7), height: 0.9, offset: 0.05, flipped: true), StackedWallPart(typeID: ElementID(8), height: 0)])
        let back = try JSONDecoder().decode(TypeData.self, from: JSONEncoder().encode(td))
        #expect(back == td)
        var plain = td; plain.stack = nil; plain.systemFamily = .basicWall
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        json.removeValue(forKey: "stack")
        let old = try JSONDecoder().decode(TypeData.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.stack == nil)
    }

    // MARK: Multi-segment grids

    @Test func multiSegmentGridSketchCreatesOneGridThroughItsBends() throws {
        let (ctx, ids) = context()
        let tool = GridSketchTool(ctx: ctx)
        #expect(tool.isSketchMode)
        let name = tool.name
        for p in [Vec2(0, 0), Vec2(0, 5), Vec2(3, 8)] { click(tool, p) }
        #expect(tool.numericInput("4"), "a typed length adds the next point along the rubber band")
        var done = false
        ctx.toolFinished = { done = true }
        #expect(tool.finish() && done)
        let g = try #require(ctx.model.elements(.grids).first { $0.name == name })
        let gd = try #require(g.grid)
        #expect(gd.isMultiSegment && gd.vertices?.count == 2)
        #expect(gd.polyline.first == Vec2(0, 0) && gd.segments.count == 3)
        // Plan: one line through the bends and the bubble beyond the start along the first segment.
        let item = try #require(plan(ctx.model, ids).items.first { $0.elementID == g.id })
        let lines = item.primitives.compactMap { p -> [Vec2]? in if case .polyline(let pts, _, _) = p { return pts }; return nil }
        #expect(lines.contains { $0.count == 4 })
        let bubble = item.primitives.compactMap { p -> Arc2? in if case .arc(let a, _) = p { return a }; return nil }.first
        #expect(try #require(bubble).center.y < 0, "the start bubble hangs below the first (vertical) segment")
        // I4's per-view ends, elbows and locks don't apply to bent grids.
        #expect(GripService.gridControls(g, gd, ctx.model, view: ctx.view, pixel: 0.01, bubbleRadius: 0.4).isEmpty)
        #expect(ElementOperations.curveOf(g) == nil, "not trimmed, split or offset")
    }

    @Test func multiSegmentGridEditsMovesAndShowsInSections() throws {
        let (ctx, ids) = context()
        var id: ElementID!
        ctx.session.perform("Grid") { tx in id = tx.create(.grids, name: "X", data: .grid(GridData(path: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)])!)) }
        #expect(GridData(path: [Vec2(0, 0), Vec2(5, 0), Vec2(10, 0)])?.isMultiSegment == false, "collinear bends are dropped")
        // Edit Sketch: the path is loaded and can be redrawn.
        let edit = GridSketchTool(ctx: ctx, editing: id)
        #expect(edit.points.count == 3)
        click(edit, Vec2(0, 10))
        #expect(edit.finish())
        #expect(ctx.model[id]?.grid?.vertices?.count == 2)
        // Move carries the bends.
        ctx.session.perform("Move") { tx in tx.update(id) { ElementTransform.apply(.translation(Vec2(1, 2)), to: &$0) } }
        #expect(ctx.model[id]?.grid?.vertices?.first == Vec2(11, 2))
        // A section across the second segment shows the grid there.
        var v = ViewData(kind: .section)
        v.planeOrigin = Vec3(5, 7, 0); v.viewDirection = Vec2(0, 1); v.farClip = 5
        v.cropRegion = Rect2(min: Vec2(-20, -1), max: Vec2(20, 12))
        let sec = Element(id: ElementID(UInt64.max - 50), category: .views, name: "S", data: .view(v))
        let g = ViewGraphicsBuilder(model: ctx.model, view: sec).build()
        #expect(g.items.contains { $0.elementID == id })
        _ = ids
    }

    // MARK: Work planes

    @Test func workPlaneSetShowAndViewer() throws {
        let (ctx, ids) = context()
        let planID = ids.planViews[ids.levels[0]]!
        var rp: ElementID!
        ctx.session.perform("Ref") { tx in rp = tx.create(.referencePlanes, name: "Center", data: .referencePlane(ReferencePlaneData(line: Segment2(Vec2(0, -5), Vec2(0, 5))))) }
        let m = ctx.model
        let names = WorkPlanes.candidates(m).map { WorkPlanes.name($0, m) }
        #expect(names.contains("Level : Level 1") && names.contains("Reference Plane : Center"))
        // A plan's work plane is its level until set.
        #expect(WorkPlanes.current(m[planID]!, m) == .level(ids.levels[0]))
        WorkPlanes.set(.level(ids.levels[1]), on: planID, in: ctx.session)
        #expect(WorkPlanes.current(ctx.model[planID]!, ctx.model) == .level(ids.levels[1]))
        // Show: a translucent plane with dashed grid lines under the drawing; toggling again hides it.
        WorkPlanes.toggleShown(planID, in: ctx.session)
        let shown = plan(ctx.model, ids).items.filter { $0.elementID == nil && $0.layer == .underlay && !$0.selectable }
        let item = try #require(shown.first)
        #expect(item.primitives.contains { if case .fill(_, let f) = $0 { return f.transparency > 0.5 }; return false })
        #expect(item.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.pattern == .dash }; return false })
        WorkPlanes.toggleShown(planID, in: ctx.session)
        #expect(!plan(ctx.model, ids).items.contains { $0.elementID == nil && $0.layer == .underlay && !$0.selectable && $0.category == .views })
        // Pick a plane: clicking the reference plane makes it the work plane.
        let pick = WorkPlanePickTool(ctx: ctx)
        click(pick, Vec2(0, 0), hit: rp)
        #expect(ctx.model[planID]?.view?.workPlane == .referencePlane(rp))
        // Viewer: a level shows its floor plan; a reference plane a view looking straight at it.
        #expect(WorkPlanes.viewerView(.level(ids.levels[0]), ctx.model)?.id == planID)
        let face = try #require(WorkPlanes.viewerView(.referencePlane(rp), ctx.model))
        let d = try #require(face.view?.viewDirection)
        #expect(abs(d.x) > 0.999 && abs(d.y) < 1e-6, "looks along the plane's normal")
        // The frame of a reference plane is vertical through its line.
        let f = try #require(WorkPlanes.frame(.referencePlane(rp), ctx.model))
        #expect(!f.isHorizontal && Fx.approx(abs(f.normal.x), 1))
    }

    // MARK: Multistory stairs

    @Test func connectLevelsRepeatsTheStairOnEveryStorey() throws {
        let (ctx, ids) = context()
        let tool = StairTool(ctx: ctx, shape: .straight)
        tool.multistoryTopLevelID = ids.levels[2]
        click(tool, Vec2(0, 0)); click(tool, Vec2(0, 5))
        let stair = try #require(ctx.model.elements(.stairs).first)
        #expect(stair.stair?.multistoryTopLevelID == ids.levels[2])
        let m = ctx.model
        let storeys = try #require(MultistoryStairs.storeys(of: stair, m))
        #expect(storeys.count == 2)
        #expect(storeys[1].levelID == ids.levels[1] && storeys[1].stair?.topLevelID == ids.levels[2])
        // 3D: twice the single stair.
        var single = stair; single.stair?.multistoryTopLevelID = nil
        let v1 = StairGeometry.meshParts(single, m).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        let v2 = ElementMeshes.parts(stair, m).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        #expect(Fx.approx(v2, 2 * v1, 1e-4))
        // Level 2's plan shows the repeated storey as the stair.
        #expect(plan(m, ids, level: 1).items.contains { $0.elementID == stair.id && $0.category == .stairs })
        // Its railings repeat too.
        let rail = try #require(m.hosted(by: stair.id).first { $0.railing != nil })
        #expect(MultistoryStairs.railingPaths(rail, m)?.count == 2)
        // Multistory Top Level in Properties: None makes it single again; a level below the top is refused.
        try ctx.session.performThrowing("None") { tx in try Parameters.set(ParameterID("stair.multistoryTop"), to: .ref(nil), on: stair.id, in: tx) }
        #expect(MultistoryStairs.storeys(of: ctx.model[stair.id]!, ctx.model) == nil)
        #expect(throws: (any Error).self) {
            try ctx.session.performThrowing("Below") { tx in try Parameters.set(ParameterID("stair.multistoryTop"), to: .ref(ids.levels[0]), on: stair.id, in: tx) }
        }
    }

    // MARK: Roofs

    func roofSketch(_ ctx: ToolContext) -> SketchTool {
        let t = SketchTool(ctx: ctx, target: .roof, commandID: .roofFootprint)
        t.drawMode = .rectangle
        return t
    }

    @Test func roofSlopeArrowMakesAShed() throws {
        let (ctx, ids) = context(level: 1)
        let t = roofSketch(ctx)
        t.definesSlope = false
        click(t, Vec2(0, 0)); click(t, Vec2(10, 8))
        t.drawSlopeArrow()
        #expect(t.isDrawingSlopeArrow)
        click(t, Vec2(5, 0)); click(t, Vec2(5, 8))
        #expect(t.roofSlopeArrows.count == 1 && !t.isDrawingSlopeArrow)
        // A click on an arrow in Slope Arrow mode removes it; draw it again.
        ctx.pixel = 0.01
        t.drawSlopeArrow(); click(t, Vec2(5, 4))
        #expect(t.roofSlopeArrows.isEmpty)
        t.drawSlopeArrow(); click(t, Vec2(5, 0)); click(t, Vec2(5, 8))
        #expect(t.finish())
        let roof = try #require(ctx.model.elements(.roofs).first)
        #expect(roof.roof?.slopeArrows?.count == 1)
        // The south edge rises toward the head at the sketch's slope (1:2): 4 m over 8 m.
        let base = RoofGeometry.baseZ(roof, ctx.model)
        #expect(Fx.approx(try #require(RoofGeometry.ridgeHeight(roof, ctx.model)) - base, 4, 1e-6))
        #expect(Fx.approx(try #require(RoofGeometry.topZ(roof, at: Vec2(5, 2), ctx.model)) - base, 1, 1e-6))
        _ = ids
    }

    @Test func alignEavesAdjustsHeightOrOverhang() throws {
        let (ctx, ids) = context(level: 1)
        // A 10 × 8 hip roof at 30° whose south eave sits 0.5 m up.
        var id: ElementID!
        let s30 = Angle.radians(30)
        ctx.session.perform("Roof") { tx in
            var r = RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [s30, s30, s30, s30])
            r.edgeOffsets = [0.5, 0, 0, 0]
            id = tx.create(.roofs, data: .roof(r), typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
        }
        let base = RoofGeometry.baseZ(ctx.model[id]!, ctx.model)
        #expect(Fx.approx(try #require(RoofGeometry.topZ(ctx.model[id]!, at: Vec2(5, 0.001), ctx.model)) - base, 0.5, 1e-3), "the raised eave")
        // Adjust Overhang: the south eave moves out until it is level with the others; the roof plane stays.
        let t = SketchTool(ctx: ctx, target: .roof, commandID: .editBoundary, editing: id)
        t.alignEaves()
        #expect(t.isAligningEaves)
        t.setEaveAdjustment(.overhang)
        ctx.pixel = 0.01
        click(t, Vec2(10, 4)) // reference: the east eave (at the base)
        click(t, Vec2(5, 0))  // align the south eave
        let south = try #require(t.curves.first { $0.asSegment.map { abs($0.start.y - $0.end.y) < 1e-9 && $0.start.y < 1 } ?? false })
        let d = 0.5 / tan(s30)
        #expect(Fx.approx(south.start.y, -d, 1e-6) && t.eaveOffset(of: south) == 0)
        #expect(t.finish())
        let r = try #require(ctx.model[id]?.roof)
        #expect(r.edgeOffsets == nil, "every eave is at the base now")
        #expect(Fx.approx(try #require(RoofGeometry.footprint(ctx.model[id]!)).polygon.bounds.min.y, -d, 1e-6))
        // Adjust Height on a fresh copy: the eave stays put and drops to the reference height.
        ctx.session.perform("Raise") { tx in tx.update(id) { $0.roof?.edgeOffsets = [0, 0.4, 0, 0] } }
        let t2 = SketchTool(ctx: ctx, target: .roof, commandID: .editBoundary, editing: id)
        t2.alignEaves()
        let east = try #require(t2.curves.first { t2.eaveOffset(of: $0) > 0 })
        click(t2, Vec2(5, -d)) // reference: the south eave (base)
        click(t2, east.midpoint)
        #expect(t2.eaveOffset(of: east) == 0 && t2.curves.contains(east))
    }

    // MARK: Columns

    @Test func slantedColumnLeansFromItsBaseToItsTop() throws {
        let (ctx, ids) = context()
        let tool = StructuralColumnTool(ctx: ctx)
        tool.placeSlanted()
        #expect(tool.options.contains { $0.label == "2nd Click" })
        click(tool, Vec2(0, 0)); click(tool, Vec2(2, 0))
        let col = try #require(ctx.model.elements(.structuralColumns).first)
        #expect(col.column?.topLocation == Vec2(2, 0) && col.column?.topLevelID == ids.levels[1])
        let m = ctx.model
        let b = ElementMeshes.parts(col, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        let w = (b.max.y - b.min.y) / 2
        #expect(Fx.approx(b.max.x, 2 + w, 1e-6) && Fx.approx(b.min.x, -w, 1e-6))
        // The plan cut at 1.2 m (of a 4 m storey) is the section moved 0.6 m along the axis.
        let cut = try #require(plan(m, ids).items.first { $0.elementID == col.id && $0.layer == .cut })
        let cx = cut.hitPolygons[0].points.reduce(0) { $0 + $1.x } / Double(cut.hitPolygons[0].points.count)
        let cutZ = m[ids.planViews[ids.levels[0]]!]!.view!.viewRange.cutOffset
        #expect(Fx.approx(cx, 2 * cutZ / 4, 1e-6))
        #expect(Parameters.value(ParameterID("column.style"), of: col, m)?.textValue == "Slanted - End Point Driven")
    }

    @Test func columnsAtGridsAndAtColumns() throws {
        let (ctx, ids) = context()
        var grids: [ElementID] = []
        var arch: ElementID!
        ctx.session.perform("Grids") { tx in
            for (a, b) in [(Vec2(0, -1), Vec2(0, 9)), (Vec2(6, -1), Vec2(6, 9)), (Vec2(-1, 0), Vec2(7, 0)), (Vec2(-1, 8), Vec2(7, 8))] {
                grids.append(tx.create(.grids, name: "G\(grids.count)", data: .grid(GridData(curve: .line(Segment2(a, b))))))
            }
            arch = tx.create(.columns, data: .column(ColumnData(location: Vec2(20, 20), rotation: 0.3)), typeID: ctx.type(for: .columns), levelID: ids.levels[0])
        }
        let tool = StructuralColumnTool(ctx: ctx)
        tool.pickMultiple(.atGrids)
        #expect(tool.finish() && ctx.model.elements(.structuralColumns).isEmpty, "Finish with nothing picked explains why and places nothing")
        for g in grids { click(tool, .zero, hit: g) }
        #expect(StructuralColumnTool.points(.atGrids, tool.picked, ctx.model).count == 4)
        #expect(tool.finish())
        #expect(ctx.model.elements(.structuralColumns).count == 4 && tool.multiple == nil)
        tool.pickMultiple(.atColumns)
        click(tool, Vec2(20, 20), hit: arch)
        #expect(tool.finish())
        let placed = try #require(ctx.model.elements(.structuralColumns).first { $0.column?.location == Vec2(20, 20) })
        #expect(Fx.approx(placed.column?.rotation ?? 0, 0.3))
    }
}
