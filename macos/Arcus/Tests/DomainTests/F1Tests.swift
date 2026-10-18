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

// MARK: - Model Text

/// Block glyphs for tests (DomainTests can't reach ArcusOutput's CoreText outliner): every character is a 0.6 × 1
/// box advancing 0.7, and "O" has a box-shaped hole.
enum TestGlyphs {
    static func install() {
        guard !ModelTextGlyphs.isInstalled else { return }
        ModelTextGlyphs.install { line, _ in
            var contours: [[Vec2]] = []
            for (k, ch) in line.enumerated() where ch != " " {
                let x = Double(k) * 0.7
                contours.append([Vec2(x, 0), Vec2(x + 0.6, 0), Vec2(x + 0.6, 1), Vec2(x, 1)])
                if ch == "O" { contours.append([Vec2(x + 0.2, 0.2), Vec2(x + 0.2, 0.8), Vec2(x + 0.4, 0.8), Vec2(x + 0.4, 0.2)]) }
            }
            return (contours, Double(line.count) * 0.7)
        }
    }
}

extension F1Tests {
    @Test func modelTextToolPlacesExtrudedTextOnTheLevel() throws {
        TestGlyphs.install()
        let (ctx, ids) = context()
        // Without a host to ask, the tool waits for its text.
        let blank = ModelTextTool(ctx: ctx)
        #expect(blank.text == nil && blank.prompt == "Type the text in Edit Text.")
        ctx.requestText = { prompt, _, done in #expect(prompt == "Edit Text"); done("HO") }
        let tool = ModelTextTool(ctx: ctx)
        #expect(tool.text == "HO" && Fx.approx(tool.size, 0.3) && Fx.approx(tool.depth, 0.05))
        tool.pointerMoved(ToolInput(point: Vec2(1, 2), rawPoint: Vec2(1, 2)))
        #expect(!tool.preview.primitives.isEmpty, "the outline follows the pointer")
        var done = false
        ctx.toolFinished = { done = true }
        click(tool, Vec2(1, 2))
        #expect(done)
        let e = try #require(ctx.model.elements(.genericModels).first { $0.modelText != nil })
        #expect(ctx.session.selection.ids == [e.id] && e.levelID == ids.levels[0])
        let shapes = ModelTextGeometry.shapes(ModelTextGeometry.localContours(e.modelText!))
        #expect(shapes.count == 2 && shapes.map(\.holes.count).reduce(0, +) == 1, "H and O, with the O's counter as a hole")
        // 3D: capitals 0.3 tall in plan, extruded 0.05 up from the level.
        let mesh = ElementMeshes.parts(e, ctx.model).reduce(into: Mesh()) { $0.append($1.mesh) }
        let b = mesh.bounds
        #expect(Fx.approx(b.min.z, 0, 1e-9) && Fx.approx(b.max.z, 0.05, 1e-9))
        #expect(Fx.approx(b.max.y - b.min.y, 0.3, 1e-6) && Fx.approx(b.min.x, 1, 1e-9))
        // The plan shows the glyph outlines (H, O and the O's hole).
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.model[ids.planViews[ids.levels[0]]!]!).build()
        let item = try #require(g.items.first { $0.elementID == e.id })
        #expect(item.primitives.count == 3)
    }

    @Test func modelTextParametersEditTheTextAndStandItUp() throws {
        TestGlyphs.install()
        let (ctx, ids) = context()
        let id = try #require(ModelTextTool.place(ModelTextData(text: "AB", position: .zero), level: ids.levels[0], session: ctx.session))
        let names = Parameters.instanceEntries(ctx.model[id]!, ctx.model).map(\.name)
        for n in ["Work Plane", "Elevation", "Text", "Horizontal Align", "Material", "Depth", "Text Size"] { #expect(names.contains(n)) }
        func set(_ name: String, _ v: ParamValue) throws {
            let pid = try #require(Parameters.id(named: name, for: ctx.model[id]!, ctx.model))
            ctx.session.perform("Set") { tx in try Parameters.set(pid, to: v, on: id, in: tx) }
        }
        try set("Text", .text("ABC"))
        try set("Horizontal Align", .text("Center"))
        try set("Elevation", .double(1))
        #expect(ctx.model[id]?.modelText?.text == "ABC")
        try set("Text", .text("  "))
        #expect(ctx.session.lastError != nil && ctx.model[id]?.modelText?.text == "ABC", "model text cannot be empty")
        // Centred: the line's advance width (3 × 0.7 capital heights) straddles the insertion point.
        let lb = try #require(ModelTextGeometry.localBounds(ctx.model[id]!.modelText!))
        #expect(Fx.approx(lb.min.x, -3 * 0.7 * 0.3 / 2, 1e-9))
        // Upright text stands as tall as its capitals and is extruded behind its plane.
        ctx.session.perform("Upright") { tx in tx.update(id) { $0.modelText?.upright = true } }
        let b = ElementMeshes.parts(ctx.model[id]!, ctx.model).reduce(into: Mesh()) { $0.append($1.mesh) }.bounds
        #expect(Fx.approx(b.min.z, 1, 1e-9) && Fx.approx(b.max.z, 1.3, 1e-6))
        #expect(Fx.approx(b.min.y, -0.05, 1e-9) && Fx.approx(b.max.y, 0, 1e-9))
        // Rotating turns the text; mirroring keeps it readable.
        ctx.session.perform("Mirror") { tx in tx.update(id) { ElementTransform.apply(.mirror(through: .zero, direction: Vec2(0, 1)), to: &$0) } }
        let t = try #require(ctx.model[id]?.modelText)
        #expect(Fx.approx(Vec2.fromAngle(t.rotation), Vec2(1, 0), 1e-9) && t.alignment == .center)
    }
}
