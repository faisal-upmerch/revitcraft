import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM3D (Furniture design in 3D views): work planes map to the plan or elevation that sees them, so every tool makes
/// the same elements in 3D as in 2D; picking a face sets the plane; shape handles stretch faces (moving the plane a face
/// is locked to, so the labelled parameter changes); temporary dimensions and drags move parts and snap.
@Suite("FM3D Furniture in 3D") @MainActor
struct FM3DTests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }
    static func view(_ m: BIMModel, _ name: String) -> ElementID { FM4Tests.view(m, name) }
    static func position(_ m: BIMModel, _ name: String) -> Double { FurniturePlanes.positionsByName(m)[name] ?? .nan }
    static func plane(_ m: BIMModel, _ name: String) -> Element { FurniturePlanes.all(m).first { $0.name == name }! }

    /// A tool context in a 3D view on `p`, as the router makes it.
    static func ctx3D(_ s: DocumentSession, _ p: FurniturePlacement3D) -> ToolContext {
        let c = ToolContext(session: s, viewID: p.hostViewID)
        c.furniture3D = p
        c.sketchPlane = p.host
        c.pixel = 0.001
        return c
    }

    /// A 3D click: the world point in the placement's view coordinates (a pick also gets the surface point).
    static func click3D(_ tool: some InteractiveTool, _ p: FurniturePlacement3D, _ w: Vec3, surface: Bool = false) {
        let q = p.local(w)
        var i = ToolInput(point: q, rawPoint: q)
        if surface { i.surfacePoint = w }
        tool.pointerMoved(i)
        tool.pointerDown(i)
        tool.pointerUp(i)
    }

    /// Part data by kind, for comparing what two sessions made.
    static func parts(_ m: BIMModel) -> [ElementData] {
        Category.furnitureParts.flatMap { m.elements($0) }.sorted { $0.id < $1.id }.map(\.data)
    }

    static func level(_ m: BIMModel) -> WorkPlaneFrame { WorkPlaneFrame(origin: Vec3(0, 0, m.elevation(ofLevel: m.levels.first?.id)), u: .unitX, v: .unitY) }

    // MARK: Placements

    @Test func workPlanesUseTheViewThatSeesThem() throws {
        let m = FurnitureTemplates.blank()
        let plan = try #require(FurniturePlacements.resolve(.square, workPlane: Self.level(m), reference: nil, m))
        #expect(plan.hostViewID == Self.view(m, "Plan") && plan.isPlan && plan.axis == .z)
        // A vertical plane facing the front (-Y) uses the Front elevation; its (u, v) are the elevation's.
        let front = try #require(FurniturePlacements.face(Vec3(0, -1, 0), at: Vec3(0.1, -0.2, 0.3), element: nil, need: .face, m))
        #expect(m[front.hostViewID]?.name == "Front" && front.axis == .y && Self.approx(front.depth, -0.2))
        let map = try #require(FurnitureSketchMap.of(m[front.hostViewID]?.view))
        let w = Vec3(0.12, -0.2, 0.4)
        #expect(front.local(w).isAlmostEqual(map.project(w)) && front.world(front.local(w)).isAlmostEqual(w))
        // Side faces: Right looks at +X faces, Left at -X faces; top faces use the plan.
        #expect(m[FurniturePlacements.face(Vec3(1, 0, 0), at: .zero, element: nil, need: .face, m)!.hostViewID]?.name == "Right")
        #expect(m[FurniturePlacements.face(Vec3(-1, 0, 0), at: .zero, element: nil, need: .face, m)!.hostViewID]?.name == "Left")
        #expect(FurniturePlacements.face(Vec3(0, 0, 1), at: Vec3(0, 0, 0.5), element: nil, need: .face, m)?.isPlan == true)
        // Plan tools on a vertical work plane fall back to the level; Back and Divider to the Front plane.
        let wall = WorkPlaneFrame(origin: Vec3(0, 0.2, 0), u: .unitX, v: .unitZ)
        #expect(FurniturePlacements.resolve(.plan, workPlane: wall, reference: nil, m)?.isPlan == true)
        let back = try #require(FurniturePlacements.resolve(.front, workPlane: Self.level(m), reference: nil, m))
        #expect(m[back.hostViewID]?.name == "Front" && Self.approx(back.depth, Self.position(m, "Front")))
        // Every Furniture tool command has a need, and the template has a view for each.
        for id in CommandRouterIDs.drawing { #expect(FurniturePlacements.need(id) != nil, "\(id)") }
        #expect(FurniturePlacements.need(.furnitureFlipPanel) == nil)
    }

    // MARK: Tools make the same elements in 3D

    @Test func panelsRailsAndLegsDrawnIn3DMatchThePlan() throws {
        let i = Self.inch
        let s2 = DocumentSession(model: FurnitureTemplates.blank()), s3 = DocumentSession(model: FurnitureTemplates.blank())
        let plan2 = ToolContext(session: s2, viewID: Self.view(s2.model, "Plan")); plan2.pixel = 0.001
        let p = try #require(FurniturePlacements.resolve(.square, workPlane: Self.level(s3.model), reference: nil, s3.model))
        let c3 = Self.ctx3D(s3, p)
        let a = Vec2(-18 * i, -9 * i), b = Vec2(-18 * i, 9 * i)
        let t2 = FurniturePanelTool(ctx: plan2), t3 = FurniturePanelTool(ctx: c3)
        FM4Tests.click(t2, a); FM4Tests.click(t2, b)
        Self.click3D(t3, p, Vec3(a, z: 0)); Self.click3D(t3, p, Vec3(b, z: 0))
        let r2 = FurnitureRailTool(ctx: plan2), r3 = FurnitureRailTool(ctx: c3)
        FM4Tests.click(r2, Vec2(-16 * i, -8 * i)); FM4Tests.click(r2, Vec2(16 * i, -8 * i))
        Self.click3D(r3, p, Vec3(-16 * i, -8 * i, 0)); Self.click3D(r3, p, Vec3(16 * i, -8 * i, 0))
        let l2 = FurnitureLegTool(ctx: plan2), l3 = FurnitureLegTool(ctx: c3)
        FM4Tests.click(l2, Vec2(10 * i, 5 * i)); Self.click3D(l3, p, Vec3(10 * i, 5 * i, 0))
        #expect(s3.model.elements(.furniturePanels).count == 1 && s3.model.elements(.furnitureRails).count == 1 && s3.model.elements(.furnitureLegs).count == 1)
        #expect(Self.parts(s2.model) == Self.parts(s3.model))
        // The rail draws at its height (Top), so the sketch shows where it goes.
        #expect(Self.approx(r3.fm3dDepth, Self.position(s3.model, "Top")))
        // In the Front elevation's plane: a rectangle of panels across the depth, as in the Front view.
        let f2 = ToolContext(session: s2, viewID: Self.view(s2.model, "Front")); f2.pixel = 0.001
        let fp = try #require(FurniturePlacements.face(Vec3(0, -1, 0), at: Vec3(0, Self.position(s3.model, "Front"), 0), element: nil, need: .square, s3.model))
        let rt2 = FurniturePanelTool(ctx: f2, mode: .rectangle), rt3 = FurniturePanelTool(ctx: Self.ctx3D(s3, fp), mode: .rectangle)
        FM4Tests.click(rt2, Vec2(-10 * i, 2 * i)); FM4Tests.click(rt2, Vec2(10 * i, 20 * i))
        let y = Self.position(s3.model, "Front")
        Self.click3D(rt3, fp, Vec3(-10 * i, y, 2 * i)); Self.click3D(rt3, fp, Vec3(10 * i, y, 20 * i))
        #expect(s3.model.elements(.furniturePanels).count == 5)
        #expect(Self.parts(s2.model) == Self.parts(s3.model))
    }

    @Test func shelvesBacksDividersAndFrontsPickedIn3DMatchTheirViews() throws {
        let i = Self.inch
        let (s2, _) = FM4Tests.bookcase(), (s3, _) = FM4Tests.bookcase()
        // Shelf: Pick Panels inside the carcass, on the plane at the shelf's height.
        let plan2 = ToolContext(session: s2, viewID: Self.view(s2.model, "Plan")); plan2.pixel = 0.001
        let sh2 = SketchTool.furniture(plan2, .shelf(.shelf), commandID: .furnitureShelf)
        sh2.setOption("fm4.offset", .double(15 * i))
        FM4Tests.click(sh2, .zero)
        #expect(sh2.finish())
        let p = try #require(FurniturePlacements.resolve(.plan, workPlane: Self.level(s3.model), reference: nil, s3.model))
        let sh3 = SketchTool.furniture(Self.ctx3D(s3, p), .shelf(.shelf), commandID: .furnitureShelf)
        sh3.setOption("fm4.offset", .double(15 * i))
        #expect(sh3.fm3dPicks && Self.approx(sh3.fm3dDepth, 15 * i))
        Self.click3D(sh3, p.atDepth(15 * i), Vec3(0, 0, 15 * i), surface: true)
        #expect(sh3.finish())
        // Back and Divider: picked in the Front elevation's plane.
        let f2 = ToolContext(session: s2, viewID: Self.view(s2.model, "Front"))
        FM4Tests.click(FurnitureBackTool(ctx: f2), Vec2(0, 5 * i))
        let fp = try #require(FurniturePlacements.resolve(.front, workPlane: Self.level(s3.model), reference: nil, s3.model))
        let back3 = FurnitureBackTool(ctx: Self.ctx3D(s3, fp))
        #expect(back3.fm3dPicks)
        // A point inside the carcass, behind the front plane: it picks the bay it's in.
        Self.click3D(back3, fp, Vec3(0, 0.05, 5 * i), surface: true)
        let d2 = FurnitureDividerTool(ctx: f2), d3 = FurnitureDividerTool(ctx: Self.ctx3D(s3, fp))
        d2.setOption("count", .int(2)); d3.setOption("count", .int(2))
        FM4Tests.click(d2, Vec2(0, 25 * i)); Self.click3D(d3, fp, Vec3(0, 0, 25 * i), surface: true)
        #expect(Self.parts(s2.model) == Self.parts(s3.model))
        #expect(s3.model.elements(.furniturePanels).filter { $0.furniturePanel?.role == .divider }.count == 2)
        // Bay and Door on the front face, as in the Front elevation.
        let b2 = FurnitureBayTool(ctx: f2), b3 = FurnitureBayTool(ctx: Self.ctx3D(s3, fp))
        b2.tagOnPlacement = false; b3.tagOnPlacement = false
        FM4Tests.click(b2, Vec2(-12 * i, 5 * i)); Self.click3D(b3, fp, Vec3(-12 * i, fp.depth, 5 * i), surface: true)
        #expect(s3.model.elements(.furnitureBays).count == 1)
        #expect(s2.model.elements(.furnitureBays).map(\.data) == s3.model.elements(.furnitureBays).map(\.data))
        FM4Tests.click(FurnitureFrontTool(ctx: f2, kind: .door), Vec2(-12 * i, 5 * i))
        Self.click3D(FurnitureFrontTool(ctx: Self.ctx3D(s3, fp), kind: .door), fp, Vec3(-12 * i, fp.depth, 5 * i), surface: true)
        #expect(s3.model.elements(.furnitureFronts).count == 1)
        #expect(s2.model.elements(.furnitureFronts).map(\.data) == s3.model.elements(.furnitureFronts).map(\.data))
    }

    @Test func formsSketchedIn3DUseTheWorkPlane() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let m = s.model
        // On the Top plane: the extrusion starts there and rises.
        let top = Self.plane(m, "Top")
        let tf = try #require(WorkPlanes.frame(.referencePlane(top.id), m))
        let p = try #require(FurniturePlacements.resolve(.square, workPlane: tf, reference: .referencePlane(top.id), m))
        #expect(p.isPlan && Self.approx(p.depth, Self.position(m, "Top")))
        let ext = SketchTool.furniture(Self.ctx3D(s, p), .form(.extrusion, isVoid: false), commandID: .furnitureExtrusion)
        ext.setOption("mode", .text("Rectangle"))
        Self.click3D(ext, p, Vec3(-0.1, -0.1, p.depth)); Self.click3D(ext, p, Vec3(0.1, 0.1, p.depth))
        #expect(ext.finish())
        let f = try #require(s.model.elements(.furnitureForms).first?.furnitureForm)
        #expect(Self.approx(f.w0, p.depth) && Self.approx(f.w1, p.depth + 12 * Self.inch))
        // On a picked front face: out of the face (toward the front).
        let y = Self.position(m, "Front")
        let fp = try #require(FurniturePlacements.face(Vec3(0, -1, 0), at: Vec3(0, y, 0.3), element: top.id, need: .square, m))
        #expect(fp.extrusionSign == -1)
        let e2 = SketchTool.furniture(Self.ctx3D(s, fp), .form(.extrusion, isVoid: false), commandID: .furnitureExtrusion)
        e2.setOption("mode", .text("Rectangle"))
        Self.click3D(e2, fp, Vec3(-0.1, y, 0.2)); Self.click3D(e2, fp, Vec3(0.1, y, 0.4))
        #expect(e2.finish())
        let g = try #require(s.model.elements(.furnitureForms).max { $0.id < $1.id }?.furnitureForm)
        #expect(g.plane == .xz && Self.approx(g.w1, y) && Self.approx(g.w0, y - 12 * Self.inch))
        // A revolve on the Front/Back centre plane; a blend on the level.
        #expect(FurniturePlacements.resolve(.vertical, workPlane: Self.level(m), reference: nil, m).map { Self.approx($0.depth, Self.position(m, "Center (Front/Back)")) } == true)
    }

    @Test func aPickedFaceOrPlaneBecomesThePlacementPlane() throws {
        let i = Self.inch
        let (s, ids) = FM4Tests.bookcase()
        let m = s.model
        // The top face of the bottom board: panels stand on it, shelves are set to it.
        let bottom = try #require(FurniturePartFaces.box(m[ids["bottom"]!]!, m))
        let p = try #require(FurniturePlacements.face(Vec3(0, 0, 1), at: Vec3(0, 0, bottom.max.z), element: ids["bottom"], need: .square, m))
        let panel = FurniturePanelTool(ctx: Self.ctx3D(s, p))
        panel.fm3dAdopt(p)
        #expect(panel.extent.basePlane == "Bottom" && Self.approx(panel.extent.baseOffset, bottom.max.z - Self.position(m, "Bottom")))
        #expect(Self.approx(panel.fm3dDepth, bottom.max.z))
        let shelf = SketchTool.furniture(Self.ctx3D(s, p), .shelf(.shelf), commandID: .furnitureShelf)
        shelf.fm3dAdopt(p)
        #expect(shelf.fm4.plane == "Bottom" && Self.approx(shelf.fm4.heightOffset, bottom.max.z))
        // A named plane: the rail runs on it.
        let topRef = Self.plane(m, "Top")
        let tp = try #require(FurniturePlacements.resolve(.square, workPlane: WorkPlanes.frame(.referencePlane(topRef.id), m), reference: .referencePlane(topRef.id), m))
        let rail = FurnitureRailTool(ctx: Self.ctx3D(s, tp))
        rail.plane = "Bottom"
        rail.fm3dAdopt(tp)
        #expect(rail.plane == "Top" && Self.approx(rail.offset, 0))
        // Binding: on a plane, or the nearest one with the offset.
        #expect(FurniturePlacements.binding(Self.position(m, "Top"), along: .z, m)?.name == "Top")
        #expect(FurniturePlacements.binding(3 * i, along: .z, m).map { $0.name == "Bottom" && Self.approx($0.offset, 3 * i) } == true)
        // A panel's face for Edit Profile: the elevation that looks at its outside face.
        let left = m[ids["left"]!]!
        let lf = try #require(FurniturePlacements.panelFace(left, m))
        #expect(m[lf.hostViewID]?.name == "Left" && lf.axis == .x && Self.approx(lf.depth, Self.position(m, "Left")))
        #expect(SketchTool.furniture(Self.ctx3D(s, lf), .panelProfile(left.id), commandID: .furnitureEditProfile).curves.count == 4)
    }

    // MARK: Shape handles

    @Test func shapeHandlesStretchFacesAndMoveTheirPlanes() throws {
        let i = Self.inch
        let (s, ids) = FM4Tests.bookcase()
        let m = s.model
        let left = m[ids["left"]!]!
        let hs = FurnitureShapeHandles.handles(left, m)
        // Ends (front and back), top and base; the faces across the thickness move the panel, so they have none.
        #expect(Set(hs.map(\.face)) == [PartFaceRef(axis: .y, atMax: false), PartFaceRef(axis: .y, atMax: true), PartFaceRef(axis: .z, atMax: false), PartFaceRef(axis: .z, atMax: true)])
        let top = try #require(hs.first { $0.face == PartFaceRef(axis: .z, atMax: true) })
        #expect(top.plane == "Top")
        // Dragging the top up moves the Top plane: Height changes and every part on the Top follows.
        _ = s.perform("Drag") { tx in try FurnitureShapeHandles.stretch(top, to: 36 * i, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(Self.approx(Self.position(s.model, "Top"), 36 * i, 1e-5))
        #expect(Self.approx(FurnitureParameters.value("Height", s.model).flatMap { if case .quantity(let v, _) = $0 { v } else { nil } }, 36 * i, 1e-5))
        #expect(Self.approx(FurniturePartFaces.box(s.model[ids["right"]!]!, s.model)?.max.z, 36 * i, 1e-5))
        #expect(Self.approx(FurniturePartFaces.box(s.model[ids["top"]!]!, s.model)?.max.z, 36 * i, 1e-5))
        // A face that isn't locked to a plane moves alone: a shelf's left edge (it follows the side's inside face, at
        // an offset from Left). Its front edge is on the Front plane: dragging that would change Depth.
        let shelf = s.model[ids["shelf2"]!]!
        let shs = FurnitureShapeHandles.handles(shelf, s.model)
        #expect(shs.first { $0.face == PartFaceRef(axis: .y, atMax: false) }?.plane == "Front")
        let edge = try #require(shs.first { $0.face == PartFaceRef(axis: .x, atMax: false) })
        #expect(edge.plane == nil)
        let target = edge.value + 2 * i
        _ = s.perform("Drag") { tx in try FurnitureShapeHandles.stretch(edge, to: target, in: tx) }
        #expect(Self.approx(FurniturePartFaces.box(s.model[shelf.id]!, s.model)?.min.x, target, 1e-6))
        #expect(Self.approx(Self.position(s.model, "Left"), Self.position(m, "Left")), "the Left plane stays")
        // Not through the opposite face.
        let h2 = try #require(FurnitureShapeHandles.handles(s.model[shelf.id]!, s.model).first { $0.face == PartFaceRef(axis: .x, atMax: false) })
        #expect(s.perform("Drag") { tx in try FurnitureShapeHandles.stretch(h2, to: h2.opposite + i, in: tx) } == nil)
        // A pinned plane refuses (Bottom is the origin).
        let base = try #require(FurnitureShapeHandles.handles(s.model[ids["left"]!]!, s.model).first { $0.face == PartFaceRef(axis: .z, atMax: false) })
        #expect(base.plane == "Bottom")
        #expect(s.perform("Drag") { tx in try FurnitureShapeHandles.stretch(base, to: -2 * i, in: tx) } == nil)
        #expect(s.lastError?.message.contains("pinned") == true)
    }

    @Test func extrusionHandlesStretchTheirEnds() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Form") { tx in _ = try FurniturePartOperations.createForm(FurnitureFormData(kind: .extrusion, profile: Polygon2.rectangle(Rect2(min: Vec2(-0.1, -0.1), max: Vec2(0.1, 0.1))).points, w0: 0, w1: 0.2), in: tx) }
        let f = try #require(s.model.elements(.furnitureForms).first)
        let hs = FurnitureShapeHandles.handles(f, s.model)
        #expect(hs.count == 2)
        let up = try #require(hs.first { $0.face.atMax })
        _ = s.perform("Drag") { tx in try FurnitureShapeHandles.stretch(up, to: 0.35, in: tx) }
        #expect(Self.approx(s.model[f.id]?.furnitureForm?.w1, 0.35))
    }

    // MARK: Temporary dimensions and moves

    @Test func temporaryDimensionsMovePartsAndDragsSnap() throws {
        let i = Self.inch
        let (s, ids) = FM4Tests.bookcase()
        let shelf = s.model[ids["shelf1"]!]!
        let dims = FurnitureTempDims3D.dims(shelf, s.model)
        // Below the shelf: the bottom board's top face (10" − 3/4" thick shelf, minus the bottom at 3/4").
        let below = try #require(dims.first { $0.axis == .z && $0.sign > 0 })
        let b = try #require(FurniturePartFaces.box(shelf, s.model))
        let bottomTop = try #require(FurniturePartFaces.box(s.model[ids["bottom"]!]!, s.model)).max.z
        #expect(Self.approx(below.value, b.min.z - bottomTop))
        // Typing 5" moves the shelf so the gap reads 5".
        let move = FurnitureTempDims3D.move(for: below, to: 5 * i)
        let plan = FurniturePlacements.planHost(s.model)
        _ = s.perform("Move") { tx in try FurnitureMove3D.translate([shelf.id], by: move, plan: plan, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let nb = try #require(FurniturePartFaces.box(s.model[shelf.id]!, s.model))
        #expect(Self.approx(nb.min.z - bottomTop, 5 * i, 1e-6))
        // Across the plan too: a leg moves in x, y and z at once.
        _ = s.perform("Leg") { tx in _ = try FurniturePartOperations.createLeg(at: Vec2(0, 0), extent: PartExtent(basePlane: "Bottom", topPlane: nil, height: 4 * i), in: tx) }
        let leg = try #require(s.model.elements(.furnitureLegs).first)
        _ = s.perform("Move") { tx in try FurnitureMove3D.translate([leg.id], by: Vec3(0.1, 0.05, 0.02), plan: plan, in: tx) }
        let l = try #require(s.model[leg.id]?.furnitureLeg)
        #expect(l.location.isAlmostEqual(Vec2(0.1, 0.05)) && Self.approx(l.base, 0.02))
        // A drag snaps the dragged box's faces to planes and parts within the tolerance.
        let box = Box3(min: Vec3(0, 0, 0), max: Vec3(0.1, 0.1, 0.1))
        let cands: [FamilyAxis: [FurnitureAxisSnap]] = [.x: [FurnitureAxisSnap(value: 0.3, label: "Right")], .z: [FurnitureAxisSnap(value: 0.5, label: "Top")]]
        let r = FurnitureMove3D.snap(box, by: Vec3(0.195, 0, 0.2), axes: [.x, .z], candidates: cands, tolerance: 0.01)
        #expect(Self.approx(r.move.x, 0.2) && Self.approx(r.move.z, 0.2) && r.snaps.map(\.snap.label) == ["Right"])
    }

    // MARK: Snapping, Edit Sketch, the 3D Design view

    @Test func partFacesCrossingAWorkPlaneSnap() throws {
        let i = Self.inch
        let (s, _) = FM4Tests.bookcase()
        let lines = FurnitureSnapTraces.traces(on: WorkPlaneFrame(origin: Vec3(0, 0, 15 * i), u: .unitX, v: .unitY), s.model)
        // Both sides are cut: their inside faces are lines on the plane.
        let xs = Set(lines.filter { abs($0.segment.a.x - $0.segment.b.x) < 1e-9 }.map { ($0.segment.a.x / 1e-6).rounded() })
        #expect(xs.contains((( -18 * i + 0.75 * i) / 1e-6).rounded()) && xs.contains(((18 * i - 0.75 * i) / 1e-6).rounded()))
        #expect(lines.allSatisfy { Self.approx($0.segment.a.z, 15 * i) })
    }

    @Test func editSketchReplacesAnExtrusionsProfile() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        _ = s.perform("Form") { tx in _ = try FurniturePartOperations.createForm(FurnitureFormData(kind: .extrusion, profile: Polygon2.rectangle(Rect2(min: Vec2(-0.1, -0.1), max: Vec2(0.1, 0.1))).points, w0: 0.1, w1: 0.3), in: tx) }
        let f = try #require(s.model.elements(.furnitureForms).first)
        let ctx = ToolContext(session: s, viewID: Self.view(s.model, "Plan"))
        let t = try #require(FurnitureFormEdit.tool(ctx, f))
        #expect(t.curves.count == 4 && t.editingID == f.id)
        t.curves = Polygon2.rectangle(Rect2(min: Vec2(-0.2, -0.1), max: Vec2(0.2, 0.1))).edges.map { .line($0) }
        #expect(t.finish())
        let g = try #require(s.model[f.id]?.furnitureForm)
        #expect(s.model.elements(.furnitureForms).count == 1)
        #expect(Self.approx(Polygon2(g.profile).bounds.width, 0.4) && Self.approx(g.w0, 0.1) && Self.approx(g.w1, 0.3))
        // In 3D on its own plane.
        let p = try #require(FurnitureFormEdit.placement(s.model[f.id]!, s.model))
        #expect(p.isPlan && Self.approx(p.depth, 0.1))
        #expect(FurnitureFormEdit.tool(Self.ctx3D(s, p), s.model[f.id]!)?.curves.count == 4)
    }

    @Test func newPiecesHaveA3DDesignViewWithTheWorkPlaneShown() throws {
        let m = FurnitureTemplates.blank()
        let v = try #require(m.views.first { $0.name == FurnitureDesignView.name })
        #expect(v.view?.kind == .threeD && v.view?.showsWorkPlane == true && v.view?.workPlane == .level(m.levels.first!.id))
        let cam = try #require(v.view?.camera)
        #expect(cam.eye.z > cam.target.z && cam.eye.y < cam.target.y && cam.eye.x < cam.target.x, "from the front left, above")
        #expect(Self.approx(WorkPlanes.spacing(m), 6 * Self.inch))
        // The {3D} view is still the first 3D view (the default 3D view and the shop drawing's).
        #expect(m.views.first { $0.view?.kind == .threeD }?.name == "{3D}")
        // Documents made before it get it on first use.
        let s = DocumentSession(model: FurnitureTemplates.blank())
        #expect(FurnitureDesignView.open(in: s) == v.id)
    }
}

/// The Furniture commands that draw (tools) in 3D.
enum CommandRouterIDs {
    static let drawing: [CommandID] = [
        .furniturePanel, .furnitureShelf, .furnitureTop, .furnitureBack, .furnitureDivider, .furnitureLeg, .furnitureLegsAtCorners, .furnitureRail,
        .furnitureSlats, .furniturePlinth, .furnitureEdgeProfile, .furnitureGroove, .furnitureEditProfile, .furnitureAttach, .furniturePanelOpening,
        .furnitureExtrusion, .furnitureBlend, .furnitureRevolve, .furnitureSweep, .furnitureSweptBlend, .furnitureCushion, .furnitureVoidExtrusion,
        .furnitureVoidBlend, .furnitureVoidRevolve, .furnitureVoidSweep, .furnitureVoidSweptBlend, .furnitureBay, .furnitureBaySeparator,
        .furnitureBayDivide, .furnitureBayTag, .furnitureDoor, .furnitureDrawer, .furnitureFlap, .furnitureHardware, .furniturePickNewHost,
    ]
}
