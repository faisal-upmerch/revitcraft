import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F5 (RevitCraft port, Analyze and Massing): spaces, space separators and space tags; Show Mass and In-Place Mass;
/// Model by Face (walls, curtain systems, floors, roofs); Model In-place.
@MainActor
@Suite("F5 Analyze and Massing")
struct F5Tests {
    func context(level: Int = 0) -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[level]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }

    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        if let hit { i.hitCandidates = [hit] }
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    /// A 10 × 8 box of walls on Level 1.
    func boxWalls(_ ctx: ToolContext, _ ids: ProjectTemplates.Ids) {
        ctx.session.perform("Walls") { tx in _ = Fx.boxWalls(tx, ids) }
    }

    func separator(_ ctx: ToolContext, _ ids: ProjectTemplates.Ids, _ c: ArcusDomain.Category, x: Double) {
        ctx.session.perform("Line") { tx in
            tx.create(c, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(x, 0), Vec2(x, 8))))), levelID: ids.levels[0])
        }
    }

    // MARK: Spaces

    @Test func spacesAreBoundedBySpaceSeparatorsNotRoomSeparators() throws {
        let (ctx, ids) = context()
        boxWalls(ctx, ids)
        separator(ctx, ids, .spaceSeparationLines, x: 4)
        separator(ctx, ids, .roomSeparationLines, x: 7)
        let level = ids.levels[0]
        var a: ElementID!, b: ElementID!, room: ElementID!
        ctx.session.perform("Place") { tx in
            a = try SpacePlacement.place(at: Vec2(2, 4), level: level, in: tx)
            b = try SpacePlacement.place(at: Vec2(8, 4), level: level, in: tx)
            room = tx.create(.rooms, name: "Room", data: .room(RoomData(point: Vec2(2, 4), number: "101")), levelID: level)
        }
        #expect(ctx.session.lastError == nil)
        let m = ctx.model
        #expect(m[a]?.category == .spaces && m[a]?.room?.number == "1" && m[b]?.room?.number == "2")
        let ba = RoomGeometry.boundary(m[a]!, m), bb = RoomGeometry.boundary(m[b]!, m)
        #expect(ba.state == .bounded && bb.state == .bounded)
        let inner = 0.1 // the generic wall's half thickness
        #expect(Fx.approx(ba.area, (4 - inner) * (8 - 2 * inner), 1e-6), "the space separator at x = 4 divides spaces")
        #expect(Fx.approx(bb.area, (6 - inner) * (8 - 2 * inner), 1e-6), "the room separator at x = 7 does not")
        // The room in the same region as space A is not affected by it (rooms and spaces share regions).
        let br = RoomGeometry.boundary(m[room]!, m)
        #expect(br.state == .bounded && Fx.approx(br.area, (7 - inner) * (8 - 2 * inner), 1e-6))
        // Space quantities and parameters come from the room data.
        #expect(Fx.approx(Parameters.value(ParameterID("q.area"), of: m[a]!, m)?.doubleValue ?? 0, ba.area))
    }

    @Test func spacePlacementRefusesUnenclosedAndRedundantRegions() {
        let (ctx, ids) = context()
        boxWalls(ctx, ids)
        let level = ids.levels[0]
        ctx.session.perform("Outside") { tx in _ = try SpacePlacement.place(at: Vec2(30, 30), level: level, in: tx) }
        #expect(ctx.session.lastError?.message.contains("not in a properly enclosed region") == true)
        ctx.session.perform("First") { tx in _ = try SpacePlacement.place(at: Vec2(2, 2), level: level, in: tx) }
        #expect(ctx.session.lastError == nil)
        ctx.session.perform("Second") { tx in _ = try SpacePlacement.place(at: Vec2(6, 6), level: level, in: tx) }
        #expect(ctx.session.lastError?.message == "There is already a space in this region.")
        #expect(ctx.model.elements(.spaces).count == 1)
    }

    @Test func spaceToolPlacesAndTagsSpaces() throws {
        let (ctx, ids) = context()
        boxWalls(ctx, ids)
        let tool = SpaceTool(ctx: ctx)
        #expect(tool.prompt == "Click to place space 1.")
        click(tool, Vec2(5, 4))
        let space = try #require(ctx.model.elements(.spaces).first)
        let tag = try #require(ctx.model.tags(of: space.id).first)
        #expect(tag.ownerViewID == ctx.viewID)
        #expect(ctx.model[ctx.model[tag.typeID]?.typeData?.familyID]?.name == SpaceTags.familyName)
        // Plans draw the space as a selectable region and the tag with the space's name and number.
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.view!).build()
        let item = try #require(g.items.first { $0.elementID == space.id })
        #expect(item.category == .spaces && !item.hitPolygons.isEmpty)
        let texts = g.items.filter { $0.elementID == tag.id }.flatMap(\.primitives).compactMap { p -> String? in if case .text(let t) = p { return t.string }; return nil }
        #expect(texts.contains("Space") && texts.contains("1"))
        // Space Tag tags the space under the pointer.
        ctx.session.perform("Untag") { tx in tx.delete(tag.id) }
        let tagTool = TagTool(ctx: ctx, commandID: .spaceTag, categories: [.spaces])
        #expect(tagTool.title == "Space Tag")
        click(tagTool, Vec2(5, 4), hit: space.id)
        #expect(ctx.model.tags(of: space.id).count == 1)
    }

    @Test func spaceSeparatorToolDrawsSpaceSeparationLines() {
        let (ctx, _) = context()
        let tool = LineTool(ctx: ctx, kind: .spaceSeparation, commandID: .spaceSeparator)
        #expect(tool.title == "Space Separator")
        click(tool, Vec2(0, 0))
        click(tool, Vec2(5, 0))
        let lines = ctx.model.elements(.spaceSeparationLines)
        #expect(lines.count == 1 && lines[0].ownerViewID == nil && lines[0].levelID == ctx.levelID)
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.view!).build()
        #expect(g.items.contains { $0.elementID == lines[0].id })
        #expect(CreateSimilar.command(for: lines[0], ctx.model) == .spaceSeparator)
    }

    @Test func spacesAreScheduled() throws {
        let (ctx, ids) = context()
        boxWalls(ctx, ids)
        separator(ctx, ids, .spaceSeparationLines, x: 4)
        var sched: ElementID!
        ctx.session.perform("Spaces") { tx in
            try SpacePlacement.place(at: Vec2(2, 4), level: ids.levels[0], in: tx)
            try SpacePlacement.place(at: Vec2(8, 4), level: ids.levels[0], in: tx)
            let def = ScheduleDefinition(kind: .category, categories: [.spaces], fields: [ScheduleTemplates.field("room.number", "Number"), ScheduleTemplates.field("q.area", "Area")])
            sched = tx.create(.schedules, name: "Space Schedule", data: .schedule(def))
        }
        #expect(Category.schedulable.contains(.spaces) && Category.taggable.contains(.spaces))
        let t = ScheduleEngine.compute(ctx.model[sched]!, ctx.model)
        let rows = t.rows.filter { $0.kind == .data }
        #expect(rows.map { $0.cells[0].text }.sorted() == ["1", "2"])
    }

    // MARK: Masses

    func massSketch(_ ctx: ToolContext, _ r: Rect2, inset: Double = 0, height: Double? = nil) -> SketchTool {
        let t = SketchTool(ctx: ctx, target: .f5(.mass), commandID: .inPlaceMass)
        t.massOptions = MassSketchOptions(height: height, topInset: inset)
        t.drawMode = .rectangle
        click(t, r.min)
        click(t, r.max)
        return t
    }

    @Test func inPlaceMassExtrudesTheSketchedFootprint() throws {
        let (ctx, ids) = context()
        let t = massSketch(ctx, Rect2(min: .zero, max: Vec2(10, 8)))
        #expect(t.title == "Mass Footprint")
        #expect(t.finish())
        let mass = try #require(ctx.model.elements(.mass).first)
        #expect(mass.name == "Mass 1" && mass.levelID == ids.levels[0])
        #expect(ctx.session.selection.ids == [mass.id])
        let d = try #require(mass.mass)
        #expect(Fx.approx(d.height, 10), "RevitCraft's default mass height")
        let m = ctx.model
        let solid = ElementMeshes.parts(mass, m).reduce(Mesh()) { var x = $0; x.append($1.mesh); return x }
        #expect(Fx.approx(abs(solid.signedVolume), 800, 1e-6))
        #expect(Fx.approx(Parameters.value(ParameterID("mass.grossVolume"), of: mass, m)?.doubleValue ?? 0, 800, 1e-6))
        #expect(Fx.approx(Parameters.value(ParameterID("mass.grossSurfaceArea"), of: mass, m)?.doubleValue ?? 0, 2 * 80 + 36 * 10, 1e-6))
        // Gross Floor Area: the footprint at every level from the base up to (not including) the top.
        let cutting = m.levels.filter { ($0.level?.elevation ?? 0) >= -0.001 && ($0.level?.elevation ?? 0) < 9.999 }.count
        #expect(Fx.approx(Parameters.value(ParameterID("mass.grossFloorArea"), of: mass, m)?.doubleValue ?? 0, 80 * Double(cutting), 1e-6))
        // The plan cuts the mass: its outline is drawn on the cut layer and selects it.
        let g = ViewGraphicsBuilder(model: m, view: ctx.view!).build()
        let item = try #require(g.items.first { $0.elementID == mass.id })
        #expect(item.layer == .cut && item.hitPolygons.first.map { Fx.approx($0.area, 80) } == true)
        // Height is editable; a blend inset that leaves no top is refused.
        try ctx.session.performThrowing("Height") { tx in try Parameters.set(ParameterID("mass.height"), to: .double(6), on: mass.id, in: tx) }
        #expect(ctx.model[mass.id]?.mass?.height == 6)
        ctx.session.perform("Inset") { tx in try Parameters.set(ParameterID("mass.topInset"), to: .double(5), on: mass.id, in: tx) }
        #expect(ctx.session.lastError != nil && ctx.model[mass.id]?.mass?.isBlend == false)
    }

    @Test func blendMassTapersToItsTopInset() throws {
        let (ctx, _) = context()
        #expect(massSketch(ctx, Rect2(min: .zero, max: Vec2(10, 8)), inset: 1, height: 4).finish())
        let mass = try #require(ctx.model.elements(.mass).first)
        let d = try #require(mass.mass)
        #expect(d.isBlend && d.formName == "Blend")
        let top = try #require(MassGeometry.topLoop(d))
        #expect(Fx.approx(top.area, 8 * 6, 1e-6))
        // A frustum of rectangles: h/3 (A1 + A2 + √(A1·A2)) does not hold for non-similar rectangles; integrate instead.
        let volume = (0..<400).reduce(0.0) { acc, k in
            let t = (Double(k) + 0.5) / 400
            return acc + (10 - 2 * t) * (8 - 2 * t) * 4 / 400
        }
        let solid = ElementMeshes.parts(mass, ctx.model).reduce(Mesh()) { var x = $0; x.append($1.mesh); return x }
        #expect(Fx.approx(abs(solid.signedVolume), volume, 1e-3))
        #expect(Fx.approx(MassGeometry.section(mass, ctx.model, atZ: 2)?.area ?? 0, 9 * 7, 1e-6))
    }

    @Test func showMassHidesMassesInEveryView() throws {
        let (ctx, _) = context()
        #expect(massSketch(ctx, Rect2(min: .zero, max: Vec2(10, 8))).finish())
        let mass = try #require(ctx.model.elements(.mass).first)
        let view = ctx.view!
        #expect(ctx.session.showMass)
        #expect(ViewGraphicsBuilder(model: ctx.model, view: view, temporary: ctx.session.temporaryVisibility(for: view.id)).build().items.contains { $0.elementID == mass.id })
        ctx.session.showMass = false
        let temp = ctx.session.temporaryVisibility(for: view.id)
        #expect(temp.hideMass && !temp.isActive, "Show Mass is not a temporary hide/isolate")
        #expect(!ViewGraphicsBuilder(model: ctx.model, view: view, temporary: temp).build().items.contains { $0.elementID == mass.id })
        #expect(VisibilityResolver(model: ctx.model, view: view, temporary: temp).resolve(mass) == nil)
    }

    @Test func massMovesWithItsFootprint() throws {
        var (m, ids) = Fx.template()
        var id: ElementID!
        try Fx.commit(&m) { tx in id = try MassGeometry.create(boundary: Polygon2.rectangle(Rect2(min: .zero, max: Vec2(4, 4))).points, height: 3, level: ids.levels[0], in: tx) }
        var e = m[id]!
        ElementTransform.apply(.translation(Vec2(10, 0)), to: &e)
        #expect(e.mass?.boundary.map(\.x).min() == 10)
        #expect(Polygon2(e.mass!.boundary).isCounterClockwise)
        // Older documents (no top inset) decode.
        let json = #"{"boundary":[{"x":0,"y":0},{"x":1,"y":0},{"x":1,"y":1}],"height":2,"baseOffset":0}"#
        let decoded = try JSONDecoder().decode(MassData.self, from: Data(json.utf8))
        #expect(decoded.topInset == nil && !decoded.isBlend)
        let round = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(m[id]!))
        #expect(round.mass == m[id]!.mass && round.category == .mass)
    }

    // MARK: Model by Face

    func massModel(inset: Double = 0, height: Double = 10) throws -> (DocumentSession, ProjectTemplates.Ids, ElementID) {
        let (m, ids) = Fx.template()
        let s = DocumentSession(model: m)
        var id: ElementID!
        try s.performThrowing("Mass") { tx in
            id = try MassGeometry.create(boundary: Polygon2.rectangle(Rect2(min: .zero, max: Vec2(10, 8))).points, height: height, topInset: inset, level: ids.levels[0], in: tx)
        }
        return (s, ids, id)
    }

    @Test func wallsByFacePutTheirExteriorFaceOnTheMass() throws {
        let (s, ids, mass) = try massModel()
        let type = ids.wallTypes[Fx.generic]
        var walls: [ElementID] = []
        try s.performThrowing("Wall by Face") { tx in walls = try ModelByFace.create(.wall, mass: mass, typeID: type, in: tx) }
        #expect(walls.count == 4)
        let m = s.model
        for id in walls {
            let w = try #require(m[id]), f = try #require(WallGeometry.frame(w, m))
            #expect(w.wall?.locationLine == .finishFaceExterior && w.levelID == ids.levels[0])
            #expect(Fx.approx(f.height, 10))
            // The exterior face lies on the mass outline, the wall inside it.
            let ext = f.exteriorFace.midpoint, int = f.interiorFace.midpoint
            #expect(MassGeometry.footprint(m[mass]!.mass!).edges.contains { $0.distance(to: ext) < 1e-6 })
            #expect(Polygon2.rectangle(Rect2(min: .zero, max: Vec2(10, 8))).contains(int, onBoundary: false))
        }
        // Doing it again finds the faces taken.
        s.perform("Again") { tx in _ = try ModelByFace.create(.wall, mass: mass, typeID: type, in: tx) }
        #expect(s.lastError?.message == "These faces already have walls.")
    }

    @Test func blendWallsLeanWithTheFaces() throws {
        let (s, ids, mass) = try massModel(inset: 1, height: 4)
        var walls: [ElementID] = []
        try s.performThrowing("Wall by Face") { tx in walls = try ModelByFace.create(.wall, mass: mass, typeID: ids.wallTypes[Fx.generic], in: tx) }
        #expect(walls.count == 4)
        let slant = try #require(s.model[walls[0]]?.wall?.slantAngle)
        #expect(Fx.approx(slant, -atan(1.0 / 4)), "leaning inward to the top loop")
        // Curtain systems need vertical faces.
        s.perform("Curtain") { tx in _ = try ModelByFace.create(.curtainSystem, mass: mass, typeID: nil, in: tx) }
        #expect(s.lastError?.message.contains("vertical faces") == true)
    }

    @Test func curtainSystemFloorsAndRoofByFace() throws {
        let (s, ids, mass) = try massModel()
        try s.performThrowing("Curtain Types") { tx in CurtainWallDefaults.populate(tx) }
        let curtainType = try #require(s.model.types(for: .walls).first { $0.typeData?.curtain != nil }?.id)
        var curtains: [ElementID] = [], floors: [ElementID] = [], roofs: [ElementID] = []
        try s.performThrowing("By Face") { tx in
            curtains = try ModelByFace.create(.curtainSystem, mass: mass, typeID: curtainType, in: tx)
            floors = try ModelByFace.create(.floor, mass: mass, typeID: ids.floorTypes["Concrete Slab 200mm"], in: tx)
            roofs = try ModelByFace.create(.roof, mass: mass, typeID: ids.roofTypes["Flat Roof - Concrete"], in: tx)
        }
        let m = s.model
        #expect(curtains.count == 4 && curtains.allSatisfy { CurtainWallGeometry.isCurtain(m[$0]!, m) })
        // Mass floors: a floor on every level from the base up to below the top, with the footprint.
        let expected = MassGeometry.floorLevels(m[mass]!, m).map(\.id)
        #expect(!expected.isEmpty && floors.compactMap { m[$0]?.levelID } == expected)
        #expect(floors.allSatisfy { Fx.approx(QuantityEngine.quantities(for: m[$0]!, in: m).area ?? 0, 80, 1e-6) })
        // The roof sits on the top face (10 m up), on the level nearest it.
        let roof = try #require(roofs.first.flatMap { m[$0] })
        #expect(Fx.approx(m.baseElevation(of: roof), 10, 1e-9))
        #expect(roof.roof?.edgeSlopes.allSatisfy { $0 == nil } == true)
    }

    @Test func modelByFaceToolPicksOneFaceInPlan() throws {
        let (s, ids, mass) = try massModel()
        let ctx = ToolContext(session: s, viewID: ids.planViews[ids.levels[0]]!)
        let tool = ModelByFaceTool(ctx: ctx, kind: .wall, typeID: ids.wallTypes[Fx.generic])
        #expect(tool.commandID == .wallByFace && tool.title == "Wall by Face")
        click(tool, Vec2(5, 0.4), hit: mass) // near the south face
        let walls = s.model.elements(.walls)
        #expect(walls.count == 1)
        let seg = try #require(walls.first?.wall?.location.asSegment)
        #expect(Fx.approx(seg.start, Vec2(10, 0)) && Fx.approx(seg.end, Vec2(0, 0)), "clockwise: the exterior faces out")
        // In 3D, the face clicked: the top face makes a roof.
        let roofTool = ModelByFaceTool(ctx: ctx, kind: .roof, typeID: ids.roofTypes["Flat Roof - Concrete"])
        var i = ToolInput(point: Vec2(5, 4), rawPoint: Vec2(5, 4))
        i.hit = mass; i.hitCandidates = [mass]; i.surfacePoint = Vec3(5, 4, 10)
        roofTool.pointerDown(i)
        #expect(s.model.elements(.roofs).count == 1)
    }

    // MARK: Model In-place

    @Test func modelInPlacePlacesItsSingleInstanceAtTheOrigin() throws {
        var (m, ids) = Fx.template()
        let name = InPlaceFamilies.defaultName(m)
        #expect(name.hasPrefix("Family"))
        var def = InPlaceFamilies.definition(name: name, template: .furniture)
        #expect(def.solids.isEmpty && def.types.map(\.name) == [name])
        def.solids = StarterLibrary.genericBox().solids
        var fid: ElementID!, inst: ElementID!
        try Fx.commit(&m) { tx in
            fid = FamilyProjectLoader.load(def, replacing: nil, in: tx)
            inst = try InPlaceFamilies.place(familyID: fid, level: ids.levels[0], in: tx)
        }
        let e = try #require(m[inst])
        #expect(e.category == .furniture && e.component?.location == .zero && e.levelID == ids.levels[0])
        #expect(InPlaceFamilies.isInPlace(m[fid]))
        // Placing again keeps the one instance; reloading the family keeps the in-place mark.
        try Fx.commit(&m) { tx in
            let again = try InPlaceFamilies.place(familyID: fid, level: ids.levels[0], in: tx)
            #expect(again == inst)
            FamilyProjectLoader.load(def, replacing: fid, in: tx)
        }
        #expect(InPlaceFamilies.instances(of: fid, m).count == 1 && InPlaceFamilies.isInPlace(m[fid]))
        #expect(InPlaceFamilies.uniqueName(name, m) != name)
    }

    @Test func f5CommandsAreInTheCatalog() {
        for id: CommandID in [.space, .spaceSeparator, .spaceTag, .showMass, .inPlaceMass, .curtainSystemByFace, .roofByFace, .wallByFace, .floorByFace, .modelInPlace] {
            #expect(CommandCatalog.all.filter { $0.id == id }.count == 1, "\(id)")
        }
        #expect(CommandCatalog.info(.modelInPlace).title == "Model In-place")
        #expect(CommandCatalog.info(.spaceTag).title == "Space Tag")
    }
}
