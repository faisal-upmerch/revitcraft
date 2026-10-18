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
}
