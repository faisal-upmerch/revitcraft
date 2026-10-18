import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// Tools and selection drags driven from a 3D view on a level work plane (W2-3D): ray/plane mapping, work-plane
/// levels, snapping and hit candidates for 3D pointer samples, and drags of floors, ceilings, roofs and components.
@MainActor
@Suite("3D work plane")
struct WorkPlane3DTests {
    /// A session whose tool context is the floor plan of `level`, with that plan's snap index.
    func context(_ m: BIMModel, _ ids: ProjectTemplates.Ids, level: Int = 0, session: DocumentSession? = nil) -> (ToolContext, ViewGraphics) {
        let s = session ?? {
            let s = DocumentSession(model: m)
            s.undoManager.groupsByEvent = false
            s.undoManager.beginUndoGrouping()
            return s
        }()
        let plan = WorkPlane3D.planView(forLevel: ids.levels[level], in: s.model)!
        let ctx = ToolContext(session: s, viewID: plan)
        ctx.pixel = 0.01
        let g = ViewGraphicsBuilder(model: s.model, view: s.model[plan]!).build()
        ctx.snapIndex = SnapIndex(graphics: g, model: s.model, view: s.model[plan]!)
        return (ctx, g)
    }

    /// A pointer sample from an oblique camera south of and above `target`, aimed at it.
    func sample(at target: Vec3, picked: ElementID? = nil, surface: Vec3? = nil) -> WorkPlane3D.PointerSample {
        let eye = target + Vec3(-6, -14, 11)
        return WorkPlane3D.PointerSample(origin: eye, direction: (target - eye).normalized, pickedID: picked, pickedPoint: surface)
    }

    // MARK: Ray and plane

    @Test func rayMeetsHorizontalPlanes() throws {
        let p = try #require(WorkPlane3D.intersect(origin: Vec3(1, 2, 10), direction: Vec3(0.3, 0.4, -1).normalized, planeZ: 4))
        #expect(Fx.approx(p.z, 4) && Fx.approx(p.xy, Vec2(1 + 0.3 * 6, 2 + 0.4 * 6), 1e-9))
        #expect(WorkPlane3D.intersect(origin: Vec3(0, 0, 10), direction: Vec3(1, 0, 0), planeZ: 0) == nil, "parallel")
        #expect(WorkPlane3D.intersect(origin: Vec3(0, 0, 10), direction: Vec3(0, 0, 1), planeZ: 0) == nil, "pointing away")
        // Looking up at a plane above the camera works too.
        #expect(WorkPlane3D.intersect(origin: Vec3(0, 0, 1), direction: Vec3(0, 0.6, 0.8), planeZ: 3)?.xy == Vec2(0, 1.5))
    }

    @Test func surfaceToolsFollowThePickedFaceAndMissesFallBackToIt() throws {
        let s = sample(at: Vec3(3, 0, 0), picked: ElementID(7), surface: Vec3(3, -0.1, 1.2))
        #expect(Fx.approx(try #require(WorkPlane3D.planPoint(s, planeZ: 0)).xy, Vec2(3, 0), 1e-9), "free points: the plane")
        #expect(try #require(WorkPlane3D.planPoint(s, planeZ: 0, preferSurface: true)) == Vec3(3, -0.1, 0), "hosts: the face under the pointer")
        let level = WorkPlane3D.PointerSample(origin: Vec3(0, -10, 1), direction: Vec3(0, 1, 0), pickedID: ElementID(7), pickedPoint: Vec3(0, 0, 1))
        #expect(WorkPlane3D.planPoint(level, planeZ: 0) == Vec3(0, 0, 0), "a level view misses the plane: use the picked point")
    }

    // MARK: Work-plane levels

    @Test func workPlaneDefaultsToTheLastPlanElseTheLowestLevel() throws {
        let (m, ids) = Fx.template()
        let l1 = ids.levels[0], l2 = ids.levels[1]
        #expect(WorkPlane3D.planView(forLevel: l1, in: m) == ids.planViews[l1], "the floor plan, not the ceiling plan")
        #expect(WorkPlane3D.defaultLevel(in: m, recentViews: []) == l1)
        let south = m.views.first { $0.view?.kind == .elevation }!.id
        #expect(WorkPlane3D.defaultLevel(in: m, recentViews: [ids.planViews[l2]!, south]) == l2, "elevations don't count")
        #expect(WorkPlane3D.defaultLevel(in: m, recentViews: [ids.planViews[l2]!, ids.planViews[l1]!]) == l1, "the most recent plan wins")
        #expect(WorkPlane3D.levels(in: m).map(\.id).prefix(2) == [l1, l2])
    }

    @Test func aSelectionMovesOnTheLevelOfTheGrabbedElement() throws {
        var (m, ids) = Fx.template()
        var floor: ElementID!, roof: ElementID!
        try Fx.commit(&m) { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))), edgeSlopes: [nil, nil, nil, nil])),
                             typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
        }
        #expect(WorkPlane3D.level(of: [floor, roof], in: m) == ids.levels[0])
        #expect(WorkPlane3D.level(of: [floor, roof], preferred: roof, in: m) == ids.levels[1])
    }

    // MARK: Tools through 3D samples

    @Test func pointerNearACornerSnapsOnTheWorkPlane() throws {
        var (m, ids) = Fx.template()
        var wall: ElementID!
        try Fx.commit(&m) { tx in wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0)) }
        let (ctx, g) = context(m, ids)
        let i = try #require(WorkPlane3D.toolInput(sample(at: Vec3(10.03, 0.02, 0)), planeZ: 0, ctx: ctx, graphics: g, snapFrom: nil))
        #expect(Fx.approx(i.rawPoint, Vec2(10.03, 0.02), 1e-9))
        // The wall's end: a face corner (visible) or its location line's end.
        let half = WallGeometry.assembly(for: m[wall]!, m).totalThickness / 2
        #expect(i.snap?.kind == .endpoint && Fx.approx(i.point.x, 10) && [0, half].contains { Fx.approx(abs(i.point.y), $0) },
                "snapped to the wall end: \(i.point) \(String(describing: i.snap?.kind))")
        #expect(i.hitCandidates.contains(wall), "the wall is a hit candidate at its end")
        // The GPU-picked element leads the candidates.
        let picked = try #require(WorkPlane3D.toolInput(sample(at: Vec3(5, 0.05, 0), picked: wall, surface: Vec3(5, -0.1, 1)), planeZ: 0, ctx: ctx, graphics: g, snapFrom: nil))
        #expect(picked.hit == wall)
    }

    @Test func threeDSnapsIgnoreViewMarkersAndAnnotations() throws {
        // QA regression: a wall started at (20, 0) in 3D began at the East elevation marker's quadrant, which exists
        // only in the plan.
        let box = try Fx.box()
        let g = ViewGraphicsBuilder(model: box.model, view: box.plan).build()
        let marker = try #require(g.items.first { $0.targetViewID != nil && $0.category == .elevationMarks }, "the plan shows elevation markers")
        let full = SnapIndex(graphics: g, model: box.model, view: box.plan)
        let mg = WorkPlane3D.modelGraphics(g, model: box.model)
        #expect(!mg.items.contains { $0.targetViewID != nil || $0.category.isAnnotation && box.model[$0.elementID]?.modelLine == nil })
        #expect(mg.items.contains { $0.elementID == box.walls[0] })
        let model = SnapIndex(graphics: mg, model: box.model, view: box.plan)
        let p = marker.bounds.center
        let radius = max(marker.bounds.width, marker.bounds.height)
        // Elevation markers are annotation: no view snaps to them (SnapIndex.nonSnappable), plans included.
        let planHit = full.snap(p, radius: radius, from: nil, settings: SnapSettings())
        #expect(planHit.map { !$0.elementIDs.contains { box.model[$0]?.category == .elevationMarks } } ?? true,
                "the plan snapped to its marker: \(String(describing: planHit))")
        let hit = model.snap(p, radius: radius, from: nil, settings: SnapSettings())
        #expect(hit.map { !$0.elementIDs.contains { box.model[$0]?.category == .elevationMarks || box.model[$0]?.view != nil } } ?? true,
                "3D snapping never picks the marker: \(String(describing: hit))")
    }

    @Test func wallToolDrawsOnTheLevel2WorkPlane() throws {
        let (m, ids) = Fx.template()
        let (ctx, g) = context(m, ids, level: 1)
        let z = ctx.levelElevation
        #expect(z > 0)
        let tool = WallTool(ctx: ctx, mode: .line)
        for p in [Vec2(0, 0), Vec2(6, 0)] {
            let i = try #require(WorkPlane3D.toolInput(sample(at: Vec3(p, z: z)), planeZ: z, ctx: ctx, graphics: g, snapFrom: tool.snapFrom))
            tool.pointerMoved(i)
            tool.pointerDown(i)
        }
        _ = tool.escape()
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 1)
        let w = try #require(walls.first)
        #expect(w.levelID == ids.levels[1])
        let seg = try #require(w.wall?.location.asSegment)
        #expect(Fx.approx(seg.start, Vec2(0, 0), 1e-6) && Fx.approx(seg.end, Vec2(6, 0), 1e-6))
    }

    @Test func doorAttachesToTheWallFaceUnderThePointer() throws {
        var (m, ids) = Fx.template()
        var wall: ElementID!
        try Fx.commit(&m) { tx in wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0)) }
        let (ctx, g) = context(m, ids)
        ctx.currentTypes[.doors] = ids.familyTypes[Fx.doorType]
        let tool = InsertTool(ctx: ctx, category: .doors)
        // Pointing at the south face 1.2 m up: the floor behind the wall is far from it on plan.
        let s = sample(at: Vec3(4, -0.1, 1.2), picked: wall, surface: Vec3(4, -0.1, 1.2))
        let onFloor = try #require(WorkPlane3D.planPoint(s, planeZ: 0))
        #expect(onFloor.xy.distance(to: Vec2(4, -0.1)) > 0.5)
        let i = try #require(WorkPlane3D.toolInput(s, planeZ: 0, ctx: ctx, graphics: g, snapFrom: nil, preferSurface: true))
        tool.pointerMoved(i)
        tool.pointerDown(i)
        let door = try #require(ctx.model.elements(.doors).first)
        #expect(door.hostID == wall)
        #expect(abs(try #require(door.insert?.location).y) < 1e-6 && abs(door.insert!.location.x - 4) < 0.3)
        #expect(door.insert?.facingFlipped == true, "faces the side the pointer is on")
    }

    // MARK: Selection drags

    /// Drags `ids` from `from` toward `to` through 3D samples on `planeZ`, releasing with the snapped point.
    func drag(_ ctx: ToolContext, _ g: ViewGraphics, _ ids: [ElementID], from: Vec2, to: Vec2, planeZ: Double) throws {
        ctx.session.selection.select(ids)
        let tool = SelectTool(ctx: ctx)
        let (anchor, _) = ctx.snap(from)
        _ = tool.beginDrag(at: anchor, grip: nil)
        for t in [0.3, 0.7, 1.0] {
            let q = from + (to - from) * t
            let i = try #require(WorkPlane3D.toolInput(sample(at: Vec3(q, z: planeZ)), planeZ: planeZ, ctx: ctx, graphics: g, snapFrom: tool.dragAnchor, orthoOnly: true))
            tool.dragged(to: i.point, snapped: i.snap != nil)
            if t == 1 {
                #expect(!tool.preview.primitives.isEmpty, "live ghost while dragging")
                tool.endDrag(i)
            }
        }
    }

    @Test func draggingAFloorSnapsToAnotherElementsEnd() throws {
        var (m, ids) = Fx.template()
        var floor: ElementID!
        try Fx.commit(&m) { tx in
            Fx.wall(tx, ids, Vec2(10, 0), Vec2(20, 0))
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        let (ctx, g) = context(m, ids)
        try drag(ctx, g, [floor], from: Vec2(0, 0), to: Vec2(10.04, 0.03), planeZ: 0)
        let b = try #require(ctx.model[floor]?.slab?.boundary.bounds)
        let half = WallGeometry.assembly(for: m[m.elements(.walls)[0].id]!, m).totalThickness / 2
        #expect(Fx.approx(b.min.x, 10) && [0, half].contains { Fx.approx(abs(b.min.y), $0) }, "floor corner on the wall end: \(b.min)")
    }

    @Test func ceilingsRoofsAndComponentsMoveOnTheirPlanes() throws {
        var (m, ids) = Fx.template()
        var ceiling: ElementID!, roof: ElementID!, desk: ElementID!, column: ElementID!, stair: ElementID!
        try Fx.commit(&m) { tx in
            ceiling = tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))), offset: 2.7)),
                                typeID: ids.ceilingTypes["Plasterboard Ceiling"], levelID: ids.levels[0])
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))), edgeSlopes: [nil, nil, nil, nil])),
                             typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
            desk = tx.create(.furniture, data: .component(ComponentData(location: Vec2(20, 20))), typeID: ids.familyTypes["Desk: 1500 x 750"], levelID: ids.levels[0])
            column = tx.create(.columns, data: .column(ColumnData(location: Vec2(30, 20), topLevelID: ids.levels[1])),
                               typeID: ids.systemTypes["Concrete Column 400 x 400"], levelID: ids.levels[0])
            stair = tx.create(.stairs, data: .stair(StairData(origin: Vec2(40, 20), direction: 0, topLevelID: ids.levels[1])), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
        }
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        // A ceiling is grabbed 2.7 m up: its drag plane is the grab height, its snaps those of its level's plan.
        let (c1, g1) = context(m, ids, session: session)
        try drag(c1, g1, [ceiling], from: Vec2(0, 0), to: Vec2(1.5, 0), planeZ: 2.7)
        #expect(Fx.approx(try #require(session.model[ceiling]?.slab?.boundary.bounds).min, Vec2(1.5, 0), 1e-6))
        let (c2, g2) = context(session.model, ids, level: 1, session: session)
        let z2 = c2.levelElevation
        try drag(c2, g2, [roof], from: Vec2(4, 3), to: Vec2(6, 3), planeZ: z2)
        #expect(Fx.approx(try #require(session.model[roof]?.roof?.footprint.bounds).max, Vec2(6, 3), 1e-6))
        let (c3, g3) = context(session.model, ids, session: session)
        try drag(c3, g3, [desk, column, stair], from: Vec2(20, 20), to: Vec2(20, 23), planeZ: 0)
        #expect(Fx.approx(try #require(session.model[desk]?.component?.location), Vec2(20, 23), 1e-6))
        #expect(Fx.approx(try #require(session.model[column]?.column?.location), Vec2(30, 23), 1e-6))
        #expect(Fx.approx(try #require(session.model[stair]?.stair?.origin), Vec2(40, 23), 1e-6))
    }

    @Test func typedDistanceWhileDraggingInThreeD() throws {
        var (m, ids) = Fx.template()
        var floor: ElementID!
        try Fx.commit(&m) { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 3))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        let (ctx, g) = context(m, ids)
        ctx.session.selection.select([floor])
        let tool = SelectTool(ctx: ctx)
        _ = tool.beginDrag(at: Vec2(2, 1.5), grip: nil)
        let i = try #require(WorkPlane3D.toolInput(sample(at: Vec3(2, 2.7, 0)), planeZ: 0, ctx: ctx, graphics: g, snapFrom: tool.dragAnchor, orthoOnly: true))
        tool.dragged(to: i.point, snapped: i.snap != nil)
        #expect(tool.numericLabel == "Distance")
        #expect(tool.numericInput("2500"))
        let b = try #require(ctx.model[floor]?.slab?.boundary.bounds)
        #expect(Fx.approx(b.min.x, 0, 1e-6) && abs(b.min.y - 2.5) < 0.05, "moved 2.5 m along the drag: \(b.min)")
    }

    // MARK: Plan picking (2D)

    @Test func planClicksFindFloorsCeilingsAndComponents() throws {
        var (m, ids) = Fx.template()
        var floor: ElementID!, ceiling: ElementID!, desk: ElementID!, column: ElementID!, stair: ElementID!, roof: ElementID!
        try Fx.commit(&m) { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            ceiling = tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), offset: 2.7)),
                                typeID: ids.ceilingTypes["Plasterboard Ceiling"], levelID: ids.levels[0])
            desk = tx.create(.furniture, data: .component(ComponentData(location: Vec2(3, 3))), typeID: ids.familyTypes["Desk: 1500 x 750"], levelID: ids.levels[0])
            column = tx.create(.columns, data: .column(ColumnData(location: Vec2(8, 6), topLevelID: ids.levels[1])),
                               typeID: ids.systemTypes["Concrete Column 400 x 400"], levelID: ids.levels[0])
            stair = tx.create(.stairs, data: .stair(StairData(origin: Vec2(20, 2), direction: 0, topLevelID: ids.levels[1])), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [nil, nil, nil, nil])),
                             typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
        }
        let plan = ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[0]]!]!).build()
        func hits(_ g: ViewGraphics, _ p: Vec2) -> [ElementID] { WorkPlane3D.hitCandidates(g, at: p, tolerance: 0.05, model: m) }
        #expect(hits(plan, Vec2(0, 5)).contains(floor), "floor edge")
        #expect(hits(plan, Vec2(6, 1)).contains(floor), "floor interior (Tab reaches it under other elements)")
        #expect(hits(plan, Vec2(3, 3)).first == desk, "furniture over the floor")
        #expect(hits(plan, Vec2(8, 6)).first == column)
        #expect(hits(plan, Vec2(20.3, 2.3)).contains(stair))
        let rcp = ViewGraphicsBuilder(model: m, view: m[ids.ceilingViews[ids.levels[0]]!]!).build()
        #expect(hits(rcp, Vec2(6, 1)).contains(ceiling), "ceilings in the reflected ceiling plan")
        let plan2 = ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[1]]!]!).build()
        #expect(hits(plan2, Vec2(0, 5)).contains(roof), "roof edge on its level's plan")
    }

    // MARK: Nudge

    @Test func arrowNudgesFollowTheScreenSquaredToWorldAxes() {
        // Looking north, level.
        #expect(WorkPlane3D.nudge(dx: 1, dy: 0, cameraRight: .unitX, cameraUp: .unitZ, cameraForward: .unitY, step: 0.1) == Vec2(0.1, 0))
        #expect(WorkPlane3D.nudge(dx: 0, dy: 1, cameraRight: .unitX, cameraUp: .unitZ, cameraForward: .unitY, step: 0.1) == Vec2(0, 0.1))
        // Top view, north up.
        #expect(WorkPlane3D.nudge(dx: 0, dy: -1, cameraRight: .unitX, cameraUp: .unitY, cameraForward: -.unitZ, step: 0.2) == Vec2(0, -0.2))
        // Looking east: screen right is south.
        #expect(WorkPlane3D.nudge(dx: 1, dy: 0, cameraRight: -.unitY, cameraUp: .unitZ, cameraForward: .unitX, step: 0.1) == Vec2(0, -0.1))
        // Southwest isometric: right is south-east, squared to +X.
        let r = Vec3(1, -1, 0).normalized, f = Vec3(1, 1, -1).normalized
        #expect(WorkPlane3D.nudge(dx: 1, dy: 0, cameraRight: r, cameraUp: r.cross(f), cameraForward: f, step: 1) == Vec2(1, 0))
    }
}
