import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// S3D2: 3D snapping to datums and 2D CAD (drawn in 3D views as their visibility allows), tangent, quadrant and
/// apparent-intersection snaps on 3D curves, and 3D tools on any work plane (reference planes, picked faces) keeping
/// it as their sketch plane.
@MainActor
@Suite("3D datums, curves and work planes")
struct S3D2Tests {
    static func query(_ cam: ScreenProjection3D, at p: Vec2) -> Snap3DQuery { Snap3DQuery(pointer: p, camera: cam) }
    static func screen(_ cam: ScreenProjection3D, _ p: Vec3) throws -> Vec2 { try #require(cam.project(p)) }
    static let view3D = Element(id: ElementID(UInt64.max - 77), category: .views, name: "{3D}", data: .view(ViewData(kind: .threeD)))
    /// A 3D view whose V/G turns reference planes on (3D views hide them by default, as in Revit).
    static let view3DPlanes: Element = {
        var d = ViewData(kind: .threeD)
        d.visibility.setCategoryVisible(.referencePlanes, true, in: .threeD)
        return Element(id: ElementID(UInt64.max - 78), category: .views, name: "{3D} planes", data: .view(d))
    }()

    /// A template with a grid (0,0)–(10,0), a reference plane x = 12 and a model line on Level 2.
    func datumModel() throws -> (m: BIMModel, ids: ProjectTemplates.Ids, grid: ElementID, plane: ElementID, line: ElementID) {
        var (m, ids) = Fx.template()
        var grid: ElementID!, plane: ElementID!, line: ElementID!
        try Fx.commit(&m) { tx in
            var g = GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(10, 0))))
            g.bottomElevation = -1
            g.topElevation = 7
            grid = tx.create(.grids, name: "A", data: .grid(g))
            plane = tx.create(.referencePlanes, name: "East", data: .referencePlane(ReferencePlaneData(line: Segment2(Vec2(12, -3), Vec2(12, 3)))))
            line = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(2, 5), Vec2(8, 5))))), levelID: ids.levels[1])
        }
        return (m, ids, grid, plane, line)
    }

    // MARK: 1. Datums and 2D CAD in 3D

    @Test func gridsLevelsReferencePlanesAndModelLinesAreDrawnInThreeD() throws {
        let (m, ids, grid, plane, line) = try datumModel()
        let items = Lines3D.items(model: m, view: Self.view3DPlanes, resolver: VisibilityResolver(model: m, view: Self.view3DPlanes))
        let g = try #require(items.first { $0.id == grid })
        let gz = Set(g.mesh.positions.map(\.z))
        #expect(gz == [-1, 7], "the grid's vertical extent: \(gz)")
        #expect(g.mesh.indices.isEmpty && g.mesh.featureEdges.count == 8, "bottom, top and two verticals: lines only")
        let level = try #require(items.first { $0.id == ids.levels[1] })
        let z2 = try #require(m[ids.levels[1]]?.level?.elevation)
        #expect(level.mesh.positions.allSatisfy { abs($0.z - z2) < 1e-9 } && level.mesh.featureEdges.count == 8, "a rectangle at the level")
        let rp = try #require(items.first { $0.id == plane })
        #expect(rp.mesh.positions.allSatisfy { abs($0.x - 12) < 1e-9 } && rp.mesh.featureEdges.count == 10, "outline and centre line")
        let ml = try #require(items.first { $0.id == line })
        #expect(ml.mesh.positions.allSatisfy { abs($0.z - z2) < 1e-9 }, "a model line at its level")

        // Hidden in the view: not drawn (and so not snapped).
        var hidden = ViewData(kind: .threeD)
        hidden.visibility.setCategoryVisible(.referencePlanes, true, in: .threeD)
        hidden.visibility.hiddenCategories = [.grids, .levels]
        let v = Element(id: Self.view3D.id, category: .views, data: .view(hidden))
        let shown = Lines3D.items(model: m, view: v, resolver: VisibilityResolver(model: m, view: v)).map(\.id)
        #expect(!shown.contains(grid) && !shown.contains(ids.levels[0]) && shown.contains(plane))
    }

    @Test func threeDViewsHideReferencePlanesUntilVisibilityGraphicsTurnsThemOn() throws {
        let (m, ids, grid, plane, _) = try datumModel()
        let shown = Lines3D.items(model: m, view: Self.view3D, resolver: VisibilityResolver(model: m, view: Self.view3D)).map(\.id)
        #expect(shown.contains(grid) && shown.contains(ids.levels[0]) && !shown.contains(plane), "grids and levels show; reference planes don't")
        #expect(!Lines3D.traces(on: .level(0), model: m, visible: { VisibilityResolver(model: m, view: Self.view3D).resolve($0) != nil })
            .contains { $0.category == .referencePlanes }, "and don't snap where they cross the work plane")
        var vg = VisibilityGraphics()
        #expect(!vg.isCategoryVisible(.referencePlanes, in: .threeD) && vg.isCategoryVisible(.referencePlanes, in: .floorPlan))
        vg.setCategoryVisible(.referencePlanes, true, in: .threeD)
        #expect(vg.isCategoryVisible(.referencePlanes, in: .threeD) && vg.shownOptInCategories == [.referencePlanes])
        #expect(Lines3D.items(model: m, view: Self.view3DPlanes, resolver: VisibilityResolver(model: m, view: Self.view3DPlanes)).contains { $0.id == plane })
        vg.setCategoryVisible(.referencePlanes, false, in: .threeD)
        #expect(!vg.isCategoryVisible(.referencePlanes, in: .threeD) && vg.shownOptInCategories == nil)
    }

    @Test func datumLinesSnapInThreeDWithTheirNames() throws {
        let (m, _, grid, plane, _) = try datumModel()
        let index = Snap3DIndex(model: m, view: Self.view3DPlanes)
        let cam = ScreenProjection3D.looking(from: Vec3(-8, -16, 12), at: Vec3(6, 0, 3), perspective: true, size: Vec2(1200, 900))
        let top = Vec3(10, 0, 7)
        let c = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, top) + Vec2(2, 1))))
        #expect(c.kind == .endpoint && c.point.distance(to: top) < 1e-9 && c.elementIDs == [grid], "the grid's top end: \(c.point)")
        let ctx = ToolContext(session: DocumentSession(model: m), viewID: m.views[0].id)
        #expect(ctx.label3D(c).label == "ENDPOINT of [\(ctx.elementLabel(grid))]")
        // The reference plane's centre line.
        let b = Lines3D.extentBox(m)
        let mid = Vec3(12, 0, b.min.z + 0.37 * (b.max.z - b.min.z))
        // (Levels hidden: their outlines cross the centre line on screen, an apparent intersection.)
        var noLevels = ViewData(kind: .threeD)
        noLevels.visibility.setCategoryVisible(.referencePlanes, true, in: .threeD)
        noLevels.visibility.hiddenCategories = [.levels]
        let plain = Snap3DIndex(model: m, view: Element(id: Self.view3D.id, category: .views, data: .view(noLevels)))
        let r = try #require(plain.snap(Self.query(cam, at: try Self.screen(cam, mid))))
        #expect(r.elementIDs == [plane] && r.kind == .nearest && r.point.distance(to: mid) < 1e-6, "\(r.kind) \(r.point)")
        // Where it meets a level's outline: a real crossing.
        let z2 = m.levels.compactMap { $0.level?.elevation }.max() ?? 0
        let x = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(12, 0, z2)))))
        #expect(x.kind == .intersection && Set(x.elementIDs).contains(plane))
        // Views that don't draw lines (no edges in the style) don't snap to them.
        var q = Self.query(cam, at: try Self.screen(cam, top))
        q.includeLineElements = false
        #expect(!index.candidates(q).contains { $0.elementIDs == [grid] })
    }

    @Test func gridsCrossingTheWorkPlaneSnapAsGridIntersections() throws {
        var (m, _, _, _, _) = try datumModel()
        var b: ElementID!
        try Fx.commit(&m) { tx in b = tx.create(.grids, name: "1", data: .grid(GridData(curve: .line(Segment2(Vec2(4, -5), Vec2(4, 5)))))) }
        let f = WorkPlaneFrame.level(0)
        let traces = Lines3D.traces(on: f, model: m).map { Snap3DExtraLine(segment: $0.segment, id: $0.id, category: $0.category) }
        #expect(traces.contains { $0.id == b && abs($0.segment.a.z) < 1e-9 }, "grid 1 on the plane")
        #expect(traces.contains { $0.category == .referencePlanes }, "and the reference plane's trace")
        let cam = ScreenProjection3D.looking(from: Vec3(-4, -12, 14), at: Vec3(4, 0, 0), perspective: true, size: Vec2(1000, 800))
        var q = Self.query(cam, at: try Self.screen(cam, Vec3(4, 0, 0)) + Vec2(1, 2))
        q.extraLines = traces
        q.workPlane = f
        let x = try #require(Snap3DIndex(sources: []).snap(q))
        #expect(x.kind == .gridIntersection && x.point.distance(to: Vec3(4, 0, 0)) < 1e-9, "\(x.kind) \(x.point)")
        // On a vertical plane (the reference plane x = 12): the levels and the grids crossing it.
        let rp = try #require(m.elements(.referencePlanes).first?.referencePlane?.frame)
        let onPlane = Lines3D.traces(on: rp, model: m)
        #expect(onPlane.contains { $0.category == .levels } && !onPlane.contains { $0.category == .grids && $0.id != b }, "grid A runs along x = 0…10 and misses it")
    }

    @Test func cadImportsSnapAtTheirLevelsElevation() throws {
        var (m, ids) = Fx.template()
        let d = ReferenceDrawing(layers: [.init(name: "A-WALL"), .init(name: "OFF", isOn: false)],
                                 entities: [.line(Segment2(Vec2(0, 0), Vec2(5, 0)), .init(layer: 0)), .line(Segment2(Vec2(0, 2), Vec2(5, 2)), .init(layer: 1))],
                                 extents: Rect2(min: .zero, max: Vec2(5, 2)))
        m.referenceDrawings[d.contentKey] = d
        var cad: ElementID!
        try Fx.commit(&m) { tx in
            var ld = LinkData(format: .dxf, isLinked: false, sourcePath: "/tmp/a.dxf", sourceName: "a.dxf", contentKey: d.contentKey)
            ld.isLoaded = true
            ld.layers = [LinkLayerState(name: "A-WALL"), LinkLayerState(name: "OFF")]
            cad = tx.create(.importedCAD, name: "a.dxf", data: .link(ld), levelID: ids.levels[1])
        }
        let z = m.elevation(ofLevel: ids.levels[1])
        let items = Lines3D.items(model: m, view: Self.view3D, resolver: VisibilityResolver(model: m, view: Self.view3D))
        let item = try #require(items.first { $0.id == cad })
        #expect(item.mesh.featureEdges.count == 2 && item.mesh.positions.allSatisfy { abs($0.z - z) < 1e-9 }, "the layer that is on, at Level 2")
        let index = Snap3DIndex(model: m, view: Self.view3D)
        let cam = ScreenProjection3D.looking(from: Vec3(-3, -9, z + 8), at: Vec3(2.5, 1, z), perspective: true, size: Vec2(1000, 800))
        let e = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(5, 0, z)) + Vec2(-2, 1))))
        #expect(e.kind == .endpoint && e.point.distance(to: Vec3(5, 0, z)) < 1e-9 && e.elementIDs == [cad])
        // Show Links off: nothing.
        var off = ViewData(kind: .threeD)
        off.visibility.showLinks = false
        let v = Element(id: Self.view3D.id, category: .views, data: .view(off))
        #expect(!Lines3D.items(model: m, view: v, resolver: VisibilityResolver(model: m, view: v)).contains { $0.id == cad })
    }

    // MARK: 2. Tangents, quadrants and apparent intersections

    static func ring(_ c: Vec3, rx: Double, ry: Double, n: Int = 48, vertical: Bool = false) -> Mesh {
        var m = Mesh()
        m.positions = (0..<n).map { k in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return vertical ? c + Vec3(rx * cos(a), 0, ry * sin(a)) : c + Vec3(rx * cos(a), ry * sin(a), 0)
        }
        m.featureEdges = (0..<n).flatMap { [UInt32($0), UInt32(($0 + 1) % n)] }
        return m
    }

    @Test func circlesAndEllipsesOfferQuadrantsAndTangents() throws {
        let circle = Self.ring(Vec3(0, 0, 1), rx: 2, ry: 2)
        let ellipse = Self.ring(Vec3(8, 0, 1), rx: 3, ry: 1.5)
        let index = Snap3DIndex(sources: [Snap3DSource(id: ElementID(1), category: .genericModels, meshes: [circle]),
                                          Snap3DSource(id: ElementID(2), category: .genericModels, meshes: [ellipse])])
        let cam = ScreenProjection3D.looking(from: Vec3(4, -6, 14), at: Vec3(4, 0, 1), perspective: true, size: Vec2(1200, 900))
        // Quadrants of the circle: plan ±X and ±Y.
        let q = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(0, 2, 1)) + Vec2(1, 1))))
        #expect(q.kind == .quadrant && q.feature == .curveQuadrant && q.point.distance(to: Vec3(0, 2, 1)) < 1e-6, "\(q.kind) \(q.point)")
        // The ellipse's ends of axes.
        let e = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(11, 0, 1)))))
        #expect(e.kind == .quadrant && e.point.distance(to: Vec3(11, 0, 1)) < 1e-6, "\(e.kind) \(e.point)")
        let minor = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(8, 1.5, 1)))))
        #expect(minor.kind == .quadrant && minor.point.distance(to: Vec3(8, 1.5, 1)) < 1e-6)
        // Tangent from a start point outside the circle.
        let from = Vec3(-6, 0, 1)
        let t = Vec3(-2.0 / 3.0, (32.0 / 9.0).squareRoot(), 1) // the tangent point from (-6, 0) to r = 2
        var tq = Self.query(cam, at: try Self.screen(cam, t))
        tq.from = from
        let tan = try #require(index.snap(tq))
        #expect(tan.kind == .tangent && tan.point.distance(to: t) < 1e-6 && abs((tan.point - from).dot(tan.point - Vec3(0, 0, 1))) < 1e-6, "\(tan.kind) \(tan.point)")
        // Tangent to the ellipse (flattened): where the line from the start point grazes it.
        let ef = Vec3(8, -6, 1)
        let tangentPts = Snap3DIndex.tangentPoints(from: ef, to: try #require(index.features(1).curves.first))
        #expect(tangentPts.count == 2 && tangentPts.allSatisfy { abs($0.y + 0.375) < 0.05 }, "tangent points y = -b²/6: \(tangentPts)")
    }

    @Test func verticalArcsOfferQuadrantsOnTheirSweep() throws {
        // A half circle standing up (an arched opening): its top and its two ends, not the missing bottom.
        var m = Mesh()
        let n = 24
        m.positions = (0...n).map { k in let a = Double.pi * Double(k) / Double(n); return Vec3(2 * cos(a), 0, 3 + 2 * sin(a)) }
        m.featureEdges = (0..<n).flatMap { [UInt32($0), UInt32($0 + 1)] }
        let index = Snap3DIndex(sources: [Snap3DSource(id: ElementID(1), category: .walls, meshes: [m])])
        let quadrants = index.features(0).extras.filter { $0.kind == .quadrant }.map(\.p)
        #expect(quadrants.count == 3 && quadrants.contains { $0.distance(to: Vec3(0, 0, 5)) < 1e-6 }, "\(quadrants)")
        #expect(index.features(0).extras.contains { $0.kind == .center && $0.p.distance(to: Vec3(0, 0, 3)) < 1e-6 })
    }

    @Test func apparentIntersectionsResolveOntoTheWorkPlaneOrTheNearerEdge() throws {
        // A line on the floor along x and one 2 m up along y: they cross only on screen.
        var low = Mesh(), high = Mesh()
        low.positions = [Vec3(-4, 0, 0), Vec3(4, 0, 0)]; low.featureEdges = [0, 1]
        high.positions = [Vec3(1, -4, 2), Vec3(1, 4, 2)]; high.featureEdges = [0, 1]
        let index = Snap3DIndex(sources: [Snap3DSource(id: ElementID(1), category: .importedCAD, meshes: [low]),
                                          Snap3DSource(id: ElementID(2), category: .importedCAD, meshes: [high])])
        let cam = ScreenProjection3D.looking(from: Vec3(-6, -9, 10), at: Vec3(0, 0, 1), perspective: true, size: Vec2(1000, 800))
        // Where they cross on screen.
        let a0 = try Self.screen(cam, Vec3(-4, 0, 0)), a1 = try Self.screen(cam, Vec3(4, 0, 0))
        let b0 = try Self.screen(cam, Vec3(1, -4, 2)), b1 = try Self.screen(cam, Vec3(1, 4, 2))
        let x = try #require(Segment2(a0, a1).intersection(Segment2(b0, b1)))
        var q = Self.query(cam, at: x + Vec2(1, 0))
        q.workPlane = .level(0)
        let c = try #require(index.snap(q))
        #expect(c.feature == .apparentIntersection && c.kind == .intersection && Set(c.elementIDs) == [ElementID(1), ElementID(2)])
        let shown = try Self.screen(cam, c.point)
        #expect(abs(c.point.z) < 1e-9 && shown.distance(to: x) < 1e-6, "on the work plane under the crossing: \(c.point)")
        q.apparentOntoNearerEdge = true
        let n = try #require(index.snap(q))
        #expect(abs(n.point.z - 2) < 1e-6 && abs(n.point.x - 1) < 1e-6, "on the upper (nearer) edge: \(n.point)")
        // A true intersection near by wins.
        var cross = Mesh()
        cross.positions = [Vec3(-4, 0.05, 0), Vec3(4, -0.05, 0), Vec3(0, -4, 0), Vec3(0, 4, 0)]; cross.featureEdges = [0, 1, 2, 3]
        let both = Snap3DIndex(sources: [Snap3DSource(id: ElementID(3), category: .importedCAD, meshes: [cross]),
                                         Snap3DSource(id: ElementID(2), category: .importedCAD, meshes: [high])])
        let real = try Self.screen(cam, Vec3(0, 0, 0))
        var rq = Self.query(cam, at: real)
        rq.workPlane = .level(0)
        rq.radius = 40
        let best = try #require(both.snap(rq))
        #expect(best.feature == .edgeIntersection, "true crossings rank before apparent ones: \(best.feature)")
        let ctx = ToolContext(session: DocumentSession(model: BIMModel()), viewID: ElementID(1))
        #expect(ctx.label3D(c).short == "Apparent Intersection" && ctx.label3D(c).label.hasPrefix("APPARENT INTERSECTION of"))
    }

    // MARK: 3. Tools on any work plane

    /// A wall (0,0)–(10,0) and a reference plane on its south face (y = −0.1), u = +X, v = up, facing south.
    func faceScene() throws -> (m: BIMModel, ids: ProjectTemplates.Ids, wall: ElementID, plane: ElementID, host: WorkPlaneHost, height: Double) {
        var (m, ids) = Fx.template()
        var wall: ElementID!, plane: ElementID!
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0))
            plane = tx.create(.referencePlanes, name: "South Face", data: .referencePlane(ReferencePlaneData(line: Segment2(Vec2(-2, -0.1), Vec2(12, -0.1)))))
        }
        let f = try #require(WorkPlanes.frame(.referencePlane(plane), m))
        #expect(f.normal.distance(to: Vec3(0, -1, 0)) < 1e-9)
        let h = ElementMeshes.parts(m[wall]!, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }.max.z
        return (m, ids, wall, plane, WorkPlaneHost(frame: f, reference: .referencePlane(plane)), h)
    }

    func planContext(_ m: BIMModel, _ ids: ProjectTemplates.Ids, sketch: WorkPlaneHost?) -> ToolContext {
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        s.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: s, viewID: WorkPlane3D.planView(forLevel: ids.levels[0], in: m)!)
        ctx.pixel = 0.01
        ctx.sketchPlane = sketch
        return ctx
    }

    @Test func modelLinesDrawnOnAReferencePlaneKeepIt() throws {
        let (m, ids, wall, _, host, h) = try faceScene()
        let ctx = planContext(m, ids, sketch: host)
        let index = Snap3DIndex(model: m)
        ctx.snapIndex = index.planeSnapIndex(host.frame)
        let cam = ScreenProjection3D.looking(from: Vec3(5, -15, 2), at: Vec3(5, 0, 1.5), perspective: true, size: Vec2(1200, 900))
        func sample(_ p: Vec2) -> WorkPlane3D.PointerSample { let r = cam.ray(at: p); return WorkPlane3D.PointerSample(origin: r.origin, direction: r.direction) }
        let tool = LineTool(ctx: ctx, kind: .model, commandID: .modelLine)
        // Near the wall's top east corner: it snaps there, in the plane's coordinates (x + 2, z).
        let corner = Vec3(10, -0.1, h)
        let at = try Self.screen(cam, corner) + Vec2(2, -1)
        let (i, _) = try #require(Snap3DInput.toolInput(sample(at), plane: host.frame, ctx: ctx, snapFrom: tool.snapFrom, index: index, query: Self.query(cam, at: at)))
        #expect(i.snap?.kind == .endpoint && Fx.approx(i.point, Vec2(12, h), 1e-6), "\(String(describing: i.snap?.kind)) \(i.point)")
        tool.pointerMoved(i)
        tool.pointerDown(i)
        // Tracking in the plane: level with the start point, past the wall's end.
        let far = Vec3(14, -0.1, h + 0.01)
        let at2 = try Self.screen(cam, far)
        let (i2, _) = try #require(Snap3DInput.toolInput(sample(at2), plane: host.frame, ctx: ctx, snapFrom: tool.snapFrom, index: index, query: Self.query(cam, at: at2)))
        #expect(abs(i2.point.y - h) < 1e-6, "held level with the start (horizontal or the edge's extension): \(i2.point) \(String(describing: i2.snap?.label))")
        tool.pointerMoved(i2)
        tool.pointerDown(i2)
        _ = tool.escape()
        let line = try #require(ctx.model.allElements.first { $0.modelLine?.sketchPlane != nil })
        let w = try #require(line.modelLine?.worldPolyline(baseZ: 0))
        #expect(w.first.map { $0.distance(to: corner) < 1e-6 } == true && w.allSatisfy { abs($0.y + 0.1) < 1e-9 && abs($0.z - h) < 1e-6 }, "\(w)")
        #expect(line.modelLine?.sketchPlane?.reference == host.reference)
        // Plan shows its projection; Move carries its plane.
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.view!).build()
        #expect(g.items.contains { $0.elementID == line.id })
        var moved = line
        ElementTransform.apply(.translation(Vec2(0, 3)), to: &moved)
        #expect(moved.modelLine?.worldPolyline(baseZ: 0).first.map { $0.distance(to: corner + Vec3(0, 3, 0)) < 1e-9 } == true)
        #expect(ElementOperations.curveOf(line) == nil && GripService.grips(for: line, ctx.model, viewKind: .floorPlan).isEmpty, "not edited as a plan line")
        _ = wall
    }

    @Test func referencePlanesDrawnOnAVerticalPlaneFollowRevit() throws {
        let (_, _, _, _, host, _) = try faceScene()
        // Along the plane: a horizontal reference plane through the line, extending along the work plane's normal.
        let flat = try #require(ReferencePlaneData.drawn(on: host, from: Vec2(2, 1), to: Vec2(8, 1)))
        let ff = try #require(flat.frame)
        #expect(flat.plane3D != nil && ff.isHorizontal && abs(ff.origin.z - 1) < 1e-9, "horizontal at 1 m")
        // Straight up: a vertical plane across the work plane.
        let up = try #require(ReferencePlaneData.drawn(on: host, from: Vec2(4, 0), to: Vec2(4, 3)))
        #expect(up.plane3D == nil && abs(up.line.direction.x) < 1e-9 && abs(up.line.start.x - 2) < 1e-9, "a vertical plane x = 2: \(up.line)")
        // Drawn with the tool on the plane.
        let (m, ids, _, _, _, _) = try faceScene()
        let ctx = planContext(m, ids, sketch: host)
        let tool = LineTool(ctx: ctx, kind: .referencePlane, commandID: .referencePlane)
        for p in [Vec2(2, 1), Vec2(8, 1)] { let i = ToolInput(point: p, rawPoint: p); tool.pointerMoved(i); tool.pointerDown(i) }
        let made = try #require(ctx.model.elements(.referencePlanes).first { $0.referencePlane?.plane3D != nil })
        #expect(WorkPlanes.frame(.referencePlane(made.id), ctx.model)?.isHorizontal == true, "usable as a work plane")
        let lines = Lines3D.items(model: ctx.model, view: Self.view3DPlanes, resolver: VisibilityResolver(model: ctx.model, view: Self.view3DPlanes))
        #expect(lines.first { $0.id == made.id }?.mesh.positions.allSatisfy { abs($0.z - 1) < 1e-9 } == true, "drawn flat at 1 m in 3D")
    }

    @Test func modelTextAndComponentsSitOnTheWorkPlane() throws {
        TestGlyphs.install()
        let (m, ids, _, _, host, _) = try faceScene()
        let ctx = planContext(m, ids, sketch: host)
        let text = ModelTextTool(ctx: ctx, text: "AB")
        let at = Vec2(3, 1)
        text.pointerMoved(ToolInput(point: at, rawPoint: at))
        text.pointerDown(ToolInput(point: at, rawPoint: at))
        let t = try #require(ctx.model.allElements.first { $0.modelText != nil })
        #expect(t.modelText?.sketchPlane == host)
        let b = ElementMeshes.parts(t, ctx.model).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(abs(b.max.y + 0.1) < 1e-6 && b.min.y < -0.1 - 1e-4, "on the face, standing out of it: \(b)")
        #expect(abs(b.min.z - 1) < 1e-6 && abs(b.min.x - 1) < 1e-6, "at (3, 1) on the plane: x = 1, z = 1: \(b)")
        #expect(ModelTextGeometry.planOutlines(t).allSatisfy { $0.points.allSatisfy { abs($0.y + 0.1) < 0.1 } }, "plan sees it edge-on")

        let type = try #require(ctx.model.types(for: .furniture).first?.id)
        ctx.currentTypes[.furniture] = type
        let comp = ComponentTool(ctx: ctx, category: .furniture, commandID: .component)
        let p = Vec2(6, 1.5)
        comp.pointerMoved(ToolInput(point: p, rawPoint: p))
        comp.pointerDown(ToolInput(point: p, rawPoint: p))
        let c = try #require(ctx.model.elements(.furniture).first)
        let place = try #require(ComponentGeometry.placement(c, ctx.model))
        #expect(place.world.origin.distance(to: host.point(p)) < 1e-9, "on the plane at (6, 1.5)")
        #expect(place.world.applyVector(.unitZ).distance(to: host.frame.normal) < 1e-9, "its up is the plane's normal")
    }

    @Test func pickingAFaceInThreeDSetsItAsTheWorkPlane() throws {
        var (m, ids) = Fx.template()
        var wall: ElementID!, view: ElementID!
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0))
            view = tx.create(.views, name: "3D", data: .view(ViewData(kind: .threeD)))
        }
        let ctx = planContext(m, ids, sketch: nil)
        let tool = WorkPlanePickTool(ctx: ctx)
        tool.targetViewID = view
        var i = ToolInput(point: Vec2(5, -0.1), rawPoint: Vec2(5, -0.1))
        i.hit = wall
        i.surfacePoint = Vec3(5, -0.1, 1.5)
        tool.pointerDown(i)
        guard case .face(let id, let f)? = ctx.model[view]?.view?.workPlane else { Issue.record("no face work plane"); return }
        #expect(id == wall && f.normal.distance(to: Vec3(0, -1, 0)) < 1e-6 && f.u.z == 0 && f.v.z > 0.99, "the south face, u level, v up: \(f)")
        #expect(WorkPlanes.name(.face(id, f), ctx.model).hasPrefix("Face : "))
        #expect(WorkPlanes.viewerView(.face(id, f), ctx.model)?.view?.kind == .elevation, "the viewer looks straight at it")
    }

    @Test func sketchPlanesDecodeFromOlderFiles() throws {
        let host = WorkPlaneHost(frame: WorkPlaneFrame(origin: Vec3(1, 2, 3), u: .unitX, v: .unitZ), reference: .face(ElementID(9), .level(0)))
        var l = ModelLineData(curve: .line(Segment2(.zero, Vec2(1, 0))))
        l.sketchPlane = host
        let back = try JSONDecoder().decode(ModelLineData.self, from: JSONEncoder().encode(l))
        #expect(back == l)
        let old = try JSONEncoder().encode(ModelLineData(curve: .line(Segment2(.zero, Vec2(1, 0)))))
        #expect(try JSONDecoder().decode(ModelLineData.self, from: old).sketchPlane == nil)
        var r = ReferencePlaneData(line: Segment2(.zero, Vec2(1, 0)))
        r.plane3D = ReferencePlane3D(start: .zero, end: .unitX, extrusion: .unitY)
        #expect(try JSONDecoder().decode(ReferencePlaneData.self, from: JSONEncoder().encode(r)) == r)
    }
}
