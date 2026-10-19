import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// S3D: object snapping to model geometry in 3D views: the screen projection, the 3D snap index (corners, edge
/// midpoints, nearest, crossings, perpendicular, point clouds), occlusion, Revit's priority order, Tab cycling, and
/// tools taking the snapped point on a work plane and on a face.
@MainActor
@Suite("3D object snapping")
struct S3DTests {
    // MARK: Fixtures

    /// A closed box mesh with its 12 outline edges (each face adds its own outline; the index removes duplicates).
    static func boxMesh(_ lo: Vec3, _ hi: Vec3) -> Mesh {
        var m = Mesh()
        let (a, b) = (lo, hi)
        let faces: [([Vec3], Vec3)] = [
            ([Vec3(a.x, a.y, a.z), Vec3(a.x, b.y, a.z), Vec3(b.x, b.y, a.z), Vec3(b.x, a.y, a.z)], Vec3(0, 0, -1)),
            ([Vec3(a.x, a.y, b.z), Vec3(b.x, a.y, b.z), Vec3(b.x, b.y, b.z), Vec3(a.x, b.y, b.z)], Vec3(0, 0, 1)),
            ([Vec3(a.x, a.y, a.z), Vec3(b.x, a.y, a.z), Vec3(b.x, a.y, b.z), Vec3(a.x, a.y, b.z)], Vec3(0, -1, 0)),
            ([Vec3(b.x, b.y, a.z), Vec3(a.x, b.y, a.z), Vec3(a.x, b.y, b.z), Vec3(b.x, b.y, b.z)], Vec3(0, 1, 0)),
            ([Vec3(a.x, b.y, a.z), Vec3(a.x, a.y, a.z), Vec3(a.x, a.y, b.z), Vec3(a.x, b.y, b.z)], Vec3(-1, 0, 0)),
            ([Vec3(b.x, a.y, a.z), Vec3(b.x, b.y, a.z), Vec3(b.x, b.y, b.z), Vec3(b.x, a.y, b.z)], Vec3(1, 0, 0)),
        ]
        for (pts, n) in faces { m.addConvexFace(pts, normal: n, edges: true) }
        return m
    }

    static let boxID = ElementID(1)

    /// The box (0,0,0)–(2,2,2) seen from the south-west, above: the corner (0,0,2) faces the viewer and (2,2,0) is
    /// hidden behind the box.
    static func boxScene(perspective: Bool = true) -> (Snap3DIndex, ScreenProjection3D) {
        let index = Snap3DIndex(sources: [Snap3DSource(id: boxID, category: .genericModels, meshes: [boxMesh(.zero, Vec3(2, 2, 2))])])
        let cam = ScreenProjection3D.looking(from: Vec3(-5, -8, 8), at: Vec3(1, 1, 1), perspective: perspective, fieldOfView: 30 * .pi / 180,
                                             orthoHeight: 5, size: Vec2(800, 600))
        return (index, cam)
    }

    static func query(_ cam: ScreenProjection3D, at p: Vec2) -> Snap3DQuery { Snap3DQuery(pointer: p, camera: cam) }

    /// Where a world point shows on screen (throws behind the camera).
    static func screen(_ cam: ScreenProjection3D, _ p: Vec3) throws -> Vec2 { try #require(cam.project(p)) }

    // MARK: Projection

    @Test func projectionAndPointerRaysAgree() throws {
        for perspective in [true, false] {
            let (_, cam) = Self.boxScene(perspective: perspective)
            for p in [Vec3(0, 0, 2), Vec3(2, 0, 0), Vec3(1, 1, 1), Vec3(-3, 4, 0.5)] {
                let s = try Self.screen(cam, p)
                let ray = cam.ray(at: s)
                // The ray through a point's projection passes through the point.
                let t = (p - ray.origin).dot(ray.direction)
                #expect((ray.origin + ray.direction * t).distance(to: p) < 1e-9, "perspective \(perspective): \(p)")
            }
            #expect(Fx.approx(try Self.screen(cam, Vec3(1, 1, 1)), Vec2(400, 300), 1e-6), "the target is the view centre")
        }
        let (_, cam) = Self.boxScene()
        #expect(cam.project(cam.eye - cam.forward) == nil, "behind the camera")
    }

    // MARK: Index picks on a projected box

    @Test func vertexMidpointAndNearestPicks() throws {
        let (index, cam) = Self.boxScene()
        let corner = Vec3(0, 0, 2)
        let c = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, corner) + Vec2(3, -2))))
        #expect(c.kind == .endpoint && c.feature == .vertex && c.point.distance(to: corner) < 1e-9 && c.elementIDs == [Self.boxID])

        // The midpoint of the top front edge, a few points off the edge.
        let mid = Vec3(1, 0, 2)
        let m = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, mid) + Vec2(1, 2))))
        #expect(m.kind == .midpoint && m.feature == .edgeMidpoint && m.point.distance(to: mid) < 1e-9)

        // Nearest: on the front vertical edge, away from its ends and midpoint.
        let on = Vec3(0, 0, 0.45)
        let n = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, on))))
        #expect(n.kind == .nearest && n.feature == .edge && n.point.distance(to: on) < 1e-6, "\(n.kind) \(n.point)")
        #expect(n.edge.map { $0.a.xy == .zero && $0.b.xy == .zero } == true, "it lies on the vertical edge")

        // Parallel cameras pick the same way.
        let (_, ortho) = Self.boxScene(perspective: false)
        let o = try #require(index.snap(Self.query(ortho, at: try Self.screen(ortho, corner) + Vec2(-2, 3))))
        #expect(o.kind == .endpoint && o.point.distance(to: corner) < 1e-9)
    }

    @Test func hiddenCornersDoNotSnapUnlessNothingHidesThem() throws {
        let (index, cam) = Self.boxScene()
        let hidden = Vec3(2, 2, 0)
        let at = try Self.screen(cam, hidden)
        var q = Self.query(cam, at: at)
        let visible = index.candidates(q)
        #expect(!visible.contains { $0.point.distance(to: hidden) < 1e-6 }, "the far corner is behind the box: \(visible.map(\.point))")
        #expect(!visible.contains { $0.edge.map { $0.a.distance(to: hidden) < 1e-6 || $0.b.distance(to: hidden) < 1e-6 } == true && $0.kind == .nearest },
                "nor its hidden edges")
        // Wireframe: nothing hides it.
        q.occlusion = false
        let all = index.candidates(q)
        #expect(all.first.map { $0.kind == .endpoint && $0.point.distance(to: hidden) < 1e-9 } == true)
        // Glass does not hide it either.
        let glass = Snap3DIndex(sources: [Snap3DSource(id: Self.boxID, category: .windows, meshes: [Self.boxMesh(.zero, Vec3(2, 2, 2))], opaque: [false])])
        #expect(glass.snap(Self.query(cam, at: at))?.point.distance(to: hidden).isLess(than: 1e-9) == true)
    }

    @Test func endpointsBeatMidpointsWhichBeatNearest() throws {
        let (index, cam) = Self.boxScene()
        let a = try Self.screen(cam, Vec3(0, 0, 2)), b = try Self.screen(cam, Vec3(2, 0, 2))
        let along = (b - a).normalized
        // Exactly on the edge 6 points from the corner: the corner wins over the nearest point under the pointer.
        let near = try #require(index.snap(Self.query(cam, at: a + along * 6)))
        #expect(near.kind == .endpoint && near.screenDistance > 5)
        // On the edge 4 points from its midpoint: the midpoint wins.
        let mid = try Self.screen(cam, Vec3(1, 0, 2))
        let m = try #require(index.snap(Self.query(cam, at: mid + along * 4)))
        #expect(m.kind == .midpoint)
        // Turned off kinds don't snap.
        var q = Self.query(cam, at: a + along * 6)
        q.enabled = [.nearest]
        #expect(index.snap(q)?.kind == .nearest)
    }

    @Test func excludedElementsAndGeometryOutsideTheSectionBoxDoNotSnap() throws {
        let (index, cam) = Self.boxScene()
        let at = try Self.screen(cam, Vec3(0, 0, 2))
        var q = Self.query(cam, at: at)
        q.exclude = [Self.boxID]
        #expect(index.candidates(q).isEmpty)
        q.exclude = []
        q.clip = Box3(min: Vec3(-1, -1, -1), max: Vec3(3, 3, 1.5))
        #expect(!index.candidates(q).contains { $0.point.z > 1.5 + 1e-6 }, "the top is cut away")
    }

    @Test func edgeCrossingsWorkPlanePiercingAndPerpendicular() throws {
        var lines = Mesh()
        lines.positions = [Vec3(0, 0, 0), Vec3(3, 3, 0), Vec3(0, 2, 0), Vec3(3, -1, 0), Vec3(5, 0, 0), Vec3(5, 0, 3), Vec3(-2, -2, 1), Vec3(4, -2, 1)]
        lines.featureEdges = [0, 1, 2, 3, 4, 5, 6, 7]
        let index = Snap3DIndex(sources: [Snap3DSource(id: ElementID(9), category: .importedCAD, meshes: [lines])])
        let cam = ScreenProjection3D.looking(from: Vec3(1, -9, 9), at: Vec3(1.5, 0, 0.5), perspective: true, fieldOfView: 40 * .pi / 180, size: Vec2(900, 700))
        // Two lines crossing in space (not at their ends): an intersection.
        let x = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(1, 1, 0)))))
        #expect(x.kind == .intersection && x.feature == .edgeIntersection && x.point.distance(to: Vec3(1, 1, 0)) < 1e-6)
        // A vertical edge piercing the work plane at 1.2 m.
        var q = Self.query(cam, at: try Self.screen(cam, Vec3(5, 0, 1.2)))
        q.workPlaneZ = 1.2
        let w = try #require(index.snap(q))
        #expect(w.feature == .workPlaneIntersection && w.point.distance(to: Vec3(5, 0, 1.2)) < 1e-9)
        // Perpendicular from the start point to an edge, on plan.
        var p = Self.query(cam, at: try Self.screen(cam, Vec3(0.5, -2, 1)))
        p.from = Vec3(0.5, -5, 0)
        let perp = try #require(index.snap(p))
        #expect(perp.kind == .perpendicular && perp.point.distance(to: Vec3(0.5, -2, 1)) < 1e-9)
    }

    @Test func pointCloudsSnapToTheirFrontPoints() throws {
        // Point markers as LinkedGeometry draws them: small tetrahedra around each point.
        let pts = [Vec3(4, 0, 1), Vec3(4.3, 0, 1), Vec3(4, 3, 1)]
        let mesh = try #require(LinkedGeometry.pointParts(PointCloudData.testCloud(pts), color: RGBColor(0.5, 0.5, 0.5)).first?.mesh)
        let index = Snap3DIndex(sources: [Snap3DSource(id: ElementID(5), category: .pointClouds, meshes: [mesh])])
        let cam = ScreenProjection3D.looking(from: Vec3(4, -10, 1), at: Vec3(4, 0, 1), perspective: true, size: Vec2(800, 600))
        let c = try #require(index.snap(Self.query(cam, at: try Self.screen(cam, Vec3(4, 0, 1)) + Vec2(2, 1))))
        #expect(c.feature == .point && c.point.distance(to: Vec3(4, 0, 1)) < 0.01, "the front point, not (4, 3, 1) behind it: \(c.point)")
    }

    // MARK: Tab cycling and the work-plane merge

    func context(_ m: BIMModel, _ ids: ProjectTemplates.Ids, level: Int = 0) -> (ToolContext, ViewGraphics) {
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        s.undoManager.beginUndoGrouping()
        let plan = WorkPlane3D.planView(forLevel: ids.levels[level], in: s.model)!
        let ctx = ToolContext(session: s, viewID: plan)
        ctx.pixel = 0.01
        let g = WorkPlane3D.modelGraphics(ViewGraphicsBuilder(model: s.model, view: s.model[plan]!).build(), model: s.model)
        ctx.snapIndex = SnapIndex(graphics: g, model: s.model, view: s.model[plan]!)
        return (ctx, g)
    }

    @Test func tabStepsThroughEveryDistinctSnapBestFirst() throws {
        let (m, ids) = Fx.template()
        let (ctx, _) = context(m, ids)
        let (index, cam) = Self.boxScene()
        let a = try Self.screen(cam, Vec3(0, 0, 2)), b = try Self.screen(cam, Vec3(2, 0, 2))
        let at = a + (b - a).normalized * 4
        let q = Self.query(cam, at: at)
        let raw = try #require(WorkPlane3D.intersect(origin: cam.ray(at: at).origin, direction: cam.ray(at: at).direction, planeZ: 0)).xy
        let picks = ctx.snap3DCandidates(raw, planeZ: 0, index: index, query: q, from: nil)
        #expect(picks.count > 1, "a corner and the nearest points of its edges")
        let best = ctx.snap3D(raw, planeZ: 0, index: index, query: q, from: nil)
        #expect(picks.first?.feature?.point == best.feature?.point && best.snap?.kind == .endpoint)
        #expect(best.snap?.label == "ENDPOINT of [\(ctx.elementLabel(Self.boxID))]" && best.snap?.shortLabel == "Endpoint")
        for (i, p) in picks.enumerated() {
            for o in picks[(i + 1)...] { #expect(p.location(planeZ: 0).distance(to: o.location(planeZ: 0)) > 1e-4, "distinct") }
        }
        let priorities = picks.compactMap { $0.snap?.kind.priority }
        #expect(priorities == priorities.sorted(), "best first: \(picks.compactMap { $0.snap?.kind })")
        // The tool gets the corner's projection on the work plane.
        #expect(Fx.approx(best.point, Vec2(0, 0), 1e-9))
    }

    // MARK: Tools using the snapped point

    /// A wall (0,0)–(10,0) on Level 1, its top corner at the east end facing a camera south-east of it.
    func wallScene() throws -> (m: BIMModel, ids: ProjectTemplates.Ids, wall: ElementID, box: Box3, cam: ScreenProjection3D) {
        var (m, ids) = Fx.template()
        var wall: ElementID!
        try Fx.commit(&m) { tx in wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0)) }
        let box = ElementMeshes.parts(m[wall]!, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        let cam = ScreenProjection3D.looking(from: Vec3(16, -12, 10), at: Vec3(10, 0, 1.5), perspective: true, fieldOfView: 45 * .pi / 180, size: Vec2(1000, 700))
        return (m, ids, wall, box, cam)
    }

    func sample(_ cam: ScreenProjection3D, at p: Vec2, picked: ElementID? = nil, surface: Vec3? = nil) -> WorkPlane3D.PointerSample {
        let r = cam.ray(at: p)
        return WorkPlane3D.PointerSample(origin: r.origin, direction: r.direction, pickedID: picked, pickedPoint: surface)
    }

    @Test func lineDrawnOnTheWorkPlaneStartsUnderAWallsTopCorner() throws {
        let (m, ids, _, box, cam) = try wallScene()
        let (ctx, g) = context(m, ids)
        let index = Snap3DIndex(model: m)
        let corner = Vec3(box.max.x, box.min.y, box.max.z)
        #expect(corner.z > 2, "the top of the wall, well above the work plane")
        let tool = LineTool(ctx: ctx, kind: .model, commandID: .modelLine)
        let at = try Self.screen(cam, corner) + Vec2(2, 1)
        let (i, pick) = try #require(Snap3DInput.toolInput(sample(cam, at: at), planeZ: 0, ctx: ctx, graphics: g, snapFrom: tool.snapFrom,
                                                           index: index, query: Self.query(cam, at: at)))
        #expect(pick.feature?.feature == .vertex && pick.feature?.point.distance(to: corner) ?? 1 < 1e-9)
        #expect(Fx.approx(i.point, corner.xy, 1e-9) && i.snap?.kind == .endpoint)
        #expect(i.rawPoint.distance(to: corner.xy) > 1, "the pointer's ray meets the floor far from the corner")
        tool.pointerMoved(i)
        tool.pointerDown(i)
        let end = Vec3(box.max.x + 3, -6, 0)
        let at2 = try Self.screen(cam, end)
        let (i2, _) = try #require(Snap3DInput.toolInput(sample(cam, at: at2), planeZ: 0, ctx: ctx, graphics: g, snapFrom: tool.snapFrom,
                                                         index: index, query: Self.query(cam, at: at2)))
        tool.pointerMoved(i2)
        tool.pointerDown(i2)
        _ = tool.escape()
        let line = try #require(ctx.model.allElements.first { $0.modelLine != nil })
        let seg = try #require(line.modelLine?.curve.asSegment)
        #expect(Fx.approx(seg.start, corner.xy, 1e-9), "the line starts at the corner's projection on the work plane: \(seg.start)")
        #expect(line.levelID == ids.levels[0])
    }

    @Test func revealSnapsToTheMidpointOfAWallEdge() throws {
        let (m, ids, wall, box, cam) = try wallScene()
        let (ctx, g) = context(m, ids)
        let index = Snap3DIndex(model: m)
        let mid = Vec3(box.max.x, box.min.y, (box.min.z + box.max.z) / 2)
        let at = try Self.screen(cam, mid) + Vec2(1, -1)
        // The GPU pick finds the wall's south face a little off the edge.
        let face = Vec3(box.max.x - 0.03, box.min.y, mid.z + 0.04)
        let tool = WallRevealTool(ctx: ctx)
        let (i, pick) = try #require(Snap3DInput.toolInput(sample(cam, at: at, picked: wall, surface: face), planeZ: 0, ctx: ctx, graphics: g, snapFrom: nil,
                                                           index: index, query: Self.query(cam, at: at), preferSurface: true))
        #expect(pick.feature?.kind == .midpoint && i.surfacePoint.map { $0.distance(to: mid) < 1e-9 } == true, "\(String(describing: pick.feature))")
        #expect(i.hit == wall)
        tool.pointerDown(i)
        let reveal = try #require(ctx.model.elements(.reveals).first?.wallReveal)
        #expect(reveal.orientation == .horizontal && Fx.approx(reveal.offset, (box.max.z - box.min.z) / 2, 1e-6), "at mid-height: \(reveal.offset)")
    }

    // MARK: Scale

    @Test func queriesStayFastOnA20kElementModel() throws {
        var sources: [Snap3DSource] = []
        let side = 142
        for k in 0..<20_000 {
            let x = Double(k % side) * 3, y = Double(k / side) * 3
            sources.append(Snap3DSource(id: ElementID(UInt64(k + 1)), category: .walls, meshes: [Self.boxMesh(Vec3(x, y, 0), Vec3(x + 2.2, y + 2.2, 3))]))
        }
        let index = Snap3DIndex(sources: sources)
        let cam = ScreenProjection3D.looking(from: Vec3(-60, -80, 120), at: Vec3(213, 213, 0), perspective: true, size: Vec2(1600, 1000))
        let start = Date()
        var hits = 0
        for k in 0..<40 {
            let p = Vec2(200 + Double(k * 31 % 1200), 150 + Double(k * 17 % 700))
            if index.snap(Self.query(cam, at: p)) != nil { hits += 1 }
        }
        let ms = Date().timeIntervalSince(start) * 1000 / 40
        #expect(hits > 0)
        #expect(ms < 150, "per query: \(ms) ms")
        print("S3D: 20k-element snap query \(String(format: "%.2f", ms)) ms")
    }
}

extension PointCloudData {
    /// A loaded cloud of plain grey points (tests).
    static func testCloud(_ pts: [Vec3]) -> PointCloudData {
        PointCloudData(source: ExternalFileRef(path: "/tmp/cloud.xyz"), points: pts.map { ($0, (128, 128, 128)) }, sourceCount: pts.count, hasColor: false, unitScale: 1)
    }
}
