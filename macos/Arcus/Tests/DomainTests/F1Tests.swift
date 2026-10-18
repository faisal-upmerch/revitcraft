import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F1 (RevitCraft port, Architecture A): openings, Model Text, Wall: Reveal, Place Model Group, spline and ellipse
/// draw modes, Highlight Boundaries.
@MainActor
@Suite("F1 Architecture A")
struct F1Tests {
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
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    func floor(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, level: Int, _ r: Rect2 = Rect2(min: .zero, max: Vec2(10, 8))) -> ElementID {
        tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: r))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[level])
    }

    /// A 10 × 8 shed roof on Level 2 rising north from its sloped south eave (30°).
    func shedRoof(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids) -> ElementID {
        let data = RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [Angle.radians(30), nil, nil, nil])
        return tx.create(.roofs, data: .roof(data), typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
    }

    // MARK: Openings

    @Test func verticalOpeningCutsOnlyItsHost() throws {
        let (ctx, ids) = context()
        var lower: ElementID!, upper: ElementID!
        ctx.session.perform("Floors") { tx in lower = floor(tx, ids, level: 0); upper = floor(tx, ids, level: 1) }
        let hole = Sketch(rect: Rect2(min: Vec2(2, 2), max: Vec2(4, 5)))
        let id = try #require(HostedOpeningTool.create(hole, kind: .vertical, host: ctx.model[lower]!, session: ctx.session))
        let m = ctx.model
        let op = try #require(m[id])
        #expect(op.category == .shaftOpenings && op.hostID == lower && op.opening?.shaft?.hosted == .vertical)
        let area = { (e: ElementID) in QuantityEngine.quantities(for: m[e]!, in: m).area ?? 0 }
        #expect(Fx.approx(area(lower), 80 - 6))
        #expect(Fx.approx(area(upper), 80), "a vertical opening cuts its host only, unlike a shaft")
        let v = abs(ElementMeshes.parts(m[lower]!, m, detail: .coarse).reduce(0) { $0 + $1.mesh.signedVolume })
        #expect(Fx.approx(v, (80 - 6) * 0.2, 1e-6))
        // The level's plan shows the outline (no shaft diagonals) and the floor with its hole.
        let g = ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[0]]!]!).build()
        let item = try #require(g.items.first { $0.elementID == id })
        #expect(item.primitives.count == 1)
        // Deleting the host deletes the opening.
        ctx.session.perform("Delete") { tx in tx.delete(lower) }
        #expect(ctx.model[id] == nil)
    }

    @Test func verticalOpeningToolPicksTheHostThenSketches() throws {
        let (ctx, ids) = context()
        var f: ElementID!
        ctx.session.perform("Floor") { tx in f = floor(tx, ids, level: 0) }
        let tool = HostedOpeningTool(ctx: ctx, kind: .vertical)
        #expect(!tool.isSketchMode)
        #expect(tool.prompt == "Select a roof, floor, or ceiling.")
        click(tool, Vec2(5, 5)) // nothing under the pointer
        #expect(!tool.isSketchMode)
        click(tool, Vec2(5, 5), hit: f)
        #expect(tool.isSketchMode && tool.hostID == f)
        #expect(tool.options.contains { $0.id == "mode" }, "the sketch has the Draw panel")
        tool.setOption("mode", .text("Rectangle"))
        click(tool, Vec2(1, 1)); click(tool, Vec2(3, 2))
        var done = false
        ctx.toolFinished = { done = true }
        #expect(tool.finish())
        #expect(done)
        let op = try #require(ctx.model.elements(.shaftOpenings).first)
        #expect(op.hostID == f && op.levelID == ids.levels[0])
        #expect(Fx.approx(QuantityEngine.quantities(for: ctx.model[f]!, in: ctx.model).area ?? 0, 80 - 2, 1e-9))
        // Hosted openings list their host in Properties instead of the shaft constraints.
        let names = Parameters.instanceEntries(op, ctx.model).map(\.name)
        #expect(names.contains("Host") && !names.contains("Top Constraint"))
    }

    @Test func byFaceOpeningInASlopedRoofIsSquareToTheFace() throws {
        let (ctx, ids) = context(level: 1)
        var roof: ElementID!
        ctx.session.perform("Roof") { tx in roof = shedRoof(tx, ids) }
        let hole = Sketch(rect: Rect2(min: Vec2(4, 3), max: Vec2(6, 5)))
        let vertical = try #require(HostedOpeningTool.create(hole, kind: .vertical, host: ctx.model[roof]!, session: ctx.session))
        let m0 = ctx.model
        let t = RoofGeometry.thickness(m0[roof]!, m0)
        let vMesh = RoofGeometry.meshParts(m0[roof]!, m0)[0].mesh
        ctx.session.perform("Swap") { tx in tx.delete(vertical) }
        try #require(HostedOpeningTool.create(hole, kind: .byFace, host: ctx.model[roof]!, session: ctx.session) != nil)
        let m = ctx.model
        #expect(ShaftCuts.externalCuts(for: m[roof]!, m).isEmpty, "the roof mesh cuts By Face openings itself")
        let fMesh = RoofGeometry.meshParts(m[roof]!, m)[0].mesh
        // Both remove the same volume (an oblique prism has the volume of a straight one) and stay closed.
        #expect(Fx.approx(abs(vMesh.signedVolume), (80 - 4) * t, 1e-6))
        #expect(Fx.approx(abs(fMesh.signedVolume), (80 - 4) * t, 1e-6))
        // The By Face cut leans uphill: its lower outline is shifted north by thickness × slope.
        let shift = t * tan(Angle.radians(30))
        let top = RoofGeometry.topZ(m[roof]!, at: Vec2(4, 3 + shift), m) ?? 0
        func hasCorner(_ mesh: Mesh, _ p: Vec2) -> Bool {
            mesh.positions.contains { Fx.approx($0.xy, p, 1e-6) && Fx.approx($0.z, top - t, 1e-6) }
        }
        #expect(hasCorner(fMesh, Vec2(4, 3 + shift)))
        #expect(!hasCorner(vMesh, Vec2(4, 3 + shift)))
    }

    @Test func dormerOpeningPicksWallsOnARoof() throws {
        let (ctx, ids) = context(level: 1)
        var roof: ElementID!, f: ElementID!
        ctx.session.perform("Roof") { tx in roof = shedRoof(tx, ids); f = floor(tx, ids, level: 1) }
        let tool = HostedOpeningTool(ctx: ctx, kind: .dormer)
        click(tool, Vec2(5, 5), hit: f)
        #expect(!tool.isSketchMode, "dormers cut roofs only")
        click(tool, Vec2(5, 5), hit: roof)
        #expect(tool.sketch?.drawMode == .pickWalls, "a dormer's boundary starts from its walls")
        #expect(HostedOpeningTool.create(Sketch(rect: Rect2(min: Vec2(20, 20), max: Vec2(21, 21))), kind: .dormer, host: ctx.model[roof]!, session: ctx.session) == nil,
                "the boundary must lie over the roof")
        let id = try #require(HostedOpeningTool.create(Sketch(rect: Rect2(min: Vec2(3, 3), max: Vec2(5, 6))), kind: .dormer, host: ctx.model[roof]!, session: ctx.session))
        #expect(ShaftCuts.externalCuts(for: ctx.model[roof]!, ctx.model).count == 1, "dormer openings cut vertically")
        #expect(ShaftCuts.cutElements(by: ctx.model[id]!, ctx.model).map(\.id) == [roof])
    }
}
