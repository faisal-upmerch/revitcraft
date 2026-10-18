import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Interaction QA for tools in 3D views (W2-3D): in the default 3D view, draws a wall and places a door in it with real
/// mouse events on the Level 1 work plane, then selects a floor and drags it so its corner snaps to the wall's end.
extension QAHarness {
    /// Runs the step, then undoes back to the model it started from (also after a failure, so nothing it drew can
    /// break later steps).
    static func interaction3DTools(_ d: CanvasDriver, _ s: DocumentState, plan: ElementID) async throws -> String {
        let entry = Set(s.model.allElements.map(\.id))
        func restore() async {
            s.cancelTool()
            s.session.selection.clear()
            await d.flushEvents()
            for _ in 0..<12 where Set(s.model.allElements.map(\.id)) != entry && s.session.undoManager.canUndo {
                s.session.undoManager.undo(); await pause(30)
            }
            if s.activeViewID != plan { s.open(plan) }
            await d.settle()
        }
        do {
            let result = try await interaction3DToolsSteps(d, s, plan: plan)
            await restore()
            try check(Set(s.model.allElements.map(\.id)) == entry, "undo did not remove what the 3D step added")
            return result
        } catch {
            await restore()
            throw error
        }
    }

    private static func interaction3DToolsSteps(_ d: CanvasDriver, _ s: DocumentState, plan: ElementID) async throws -> String {
        guard let v3 = s.model.views.first(where: { $0.view?.kind == .threeD }) else { throw QAError("no 3D view") }
        let level = try require3D(s.model[plan]?.levelID, "plan has no level")
        let z = s.model.elevation(ofLevel: level)
        s.open(v3.id)
        var host: Viewport3DHost?
        for _ in 0..<200 { host = s.canvases[v3.id] as? Viewport3DHost; if host?.viewport.statistics.triangles ?? 0 > 0 { break }; await pause(30) }
        guard let h = host, h.viewport.statistics.triangles > 0 else { throw QAError("3D scene has no triangles") }
        let vp = h.viewport
        vp.orient(to: .southWestIso, animated: false)
        vp.zoom(to: Box3(min: Vec3(-2, -6, z), max: Vec3(36, 12, z + 4)), animated: false)
        await d.flushEvents(); await pause(100)
        func at(_ p: Vec3) throws -> NSPoint {
            guard let q = vp.viewPoint(of: p), vp.bounds.contains(q) else { throw QAError("\(p) is off screen in 3D") }
            return vp.convert(q, to: nil)
        }
        func waitFor(_ id: ElementID) async {
            for _ in 0..<200 { if vp.sceneElementIDs.contains(id) { break }; await pause(25) }
            await pause(60)
        }
        s.session.selection.clear()

        // Wall on the Level 1 work plane.
        let wallsBefore = Set(s.model.elements(.walls).map(\.id))
        w3(vp)
        d.type("WA")
        if s.activeTool == nil { CommandRouter(state: s).run(.wall) }
        try check(s.activeTool is WallTool, "WA did not start the Wall tool in 3D (\(String(describing: s.activeTool?.title)))")
        try check((s.activeTool as? BaseTool)?.ctx.levelID == level, "the wall tool's work plane is not the last plan's level")
        var snaps: [String] = []
        for p in [Vec2(20, 0), Vec2(26, 0)] {
            d.mouse(.mouseMoved, try at(Vec3(p, z: z))); await pause(30)
            d.click(try at(Vec3(p, z: z))); await pause(40)
            snaps.append("\(p): \(s.snapDescription ?? "free") raw \(s.cursorPoint.map { "\($0)" } ?? "-")")
        }
        d.escape(); d.escape(); await d.flushEvents()
        guard let wall = s.model.elements(.walls).first(where: { !wallsBefore.contains($0.id) }), let seg = wall.wall?.location.asSegment else {
            throw QAError("no wall drawn in 3D")
        }
        try check(wall.levelID == level, "3D wall on the wrong level")
        try check(seg.start.distance(to: Vec2(20, 0)) < 0.25 && seg.end.distance(to: Vec2(26, 0)) < 0.25, "3D wall at \(seg.start)–\(seg.end); clicks: \(snaps.joined(separator: "; "))")
        await waitFor(wall.id)

        // Door in the wall face under the pointer.
        let doorsBefore = s.model.elements(.doors).count
        CommandRouter(state: s).run(.door)
        try check(s.activeTool is InsertTool, "the Door tool did not start in 3D: \(CommandRouter(state: s).disabledReason(.door) ?? "-")")
        let half = WallGeometry.assembly(for: wall, s.model).totalThickness / 2
        let face = Vec3(23, seg.start.y - half, z + 1.0)
        d.hover([try at(face + Vec3(-0.4, 0, 0)), try at(face)]); await pause(40)
        try check(vp.pick(at: vp.convert(try at(face), from: nil)).id == wall.id, "the new wall is not under the pointer in 3D")
        d.click(try at(face)); await pause(60)
        d.escape(); d.escape(); await d.flushEvents()
        let door = s.model.elements(.doors).first { $0.hostID == wall.id }
        try check(s.model.elements(.doors).count == doorsBefore + 1 && door != nil, "no door placed in the 3D wall")

        // Select a floor and drag its corner onto the wall's end.
        var floor: ElementID!
        s.session.perform("QA Floor") { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(30, 0), max: Vec2(34, 3))))),
                              typeID: tx.model.types(for: .floors).first?.id, levelID: level)
        }
        await waitFor(floor)
        // Grab 4 pt inside the corner (within snap reach, so the drag is measured from the corner) and drop 3 pt off
        // the wall's end.
        let k = vp.worldPerPoint(at: Vec3(30, 0, z))
        let grab = Vec3(30 + 4 * k, 4 * k, z)
        let gp = try at(grab)
        try check(vp.pick(at: vp.convert(gp, from: nil)).id == floor, "the floor is not under the pointer in 3D")
        d.click(gp); await d.flushEvents(); await pause(60)
        try check(s.session.selection.ids == [floor], "3D click selected \(s.session.selection.ids), expected the floor")
        let drop = try at(Vec3(26 + 2 * k, 2 * k, z))
        d.mouse(.mouseMoved, gp)
        d.mouse(.leftMouseDown, gp)
        for i in 1...12 {
            let t = Double(i) / 12
            d.mouse(.leftMouseDragged, NSPoint(x: gp.x + (drop.x - gp.x) * t, y: gp.y + (drop.y - gp.y) * t))
        }
        let dragSnap = s.snapDescription ?? ""
        let dragInfo = "anchor \(h.tools.dragTool?.dragAnchor.map { "\($0)" } ?? "-"), snap \(s.snapDescription ?? "-"), k \(k)"
        d.mouse(.leftMouseUp, drop)
        await d.flushEvents(); await pause(60)
        let b = try require3D(s.model[floor]?.slab?.boundary.bounds, "floor vanished")
        // Snapped: the corner lands exactly on an endpoint of the wall's end in plan (location line, face or layer line).
        // Measured from the wall as drawn: its start may itself have snapped a fraction off (20, 0) to a nearby guide.
        try check(dragSnap.hasPrefix("ENDPOINT") && abs(b.min.x - seg.end.x) < 1e-6 && abs(b.min.y - seg.end.y) <= half + 1e-6,
                  "floor corner at \(b.min), expected on the wall end \(seg.end); \(dragInfo)")
        s.open(plan); await d.verify("plan after 3D tools")
        return "wall \(String(format: "%.2f", seg.length)) m and door drawn in 3D; floor dragged to \(String(format: "%.3f, %.3f", b.min.x, b.min.y))"
    }

    private static func w3(_ vp: NSView) { vp.window?.makeFirstResponder(vp) }

    private static func require3D<T>(_ v: T?, _ msg: String) throws -> T {
        guard let v else { throw QAError(msg) }
        return v
    }
}
