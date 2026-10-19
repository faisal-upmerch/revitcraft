import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// STAIR: screenshots of stairs (hooked from `screenshots()` with one line, per appearance), in the open sample project
// beside the house: Create Stair while a run is drawn (the riser readout, Modify | Create Stair's Components, Draw and
// Tools panels, the Options Bar), the second run with its automatic landing, the Railing dialog, Edit Stairs with a
// selected run's grips; then every kind of stair (straight, L and U with landings, spiral, L- and U-shape winders, a
// multistory stair) on the plan it starts from and on the plan it arrives at, a section and the 3D view. Everything
// added is undone afterwards.
extension QAHarness {
    static func stairScreenshots(_ s: DocumentState, _ w: NSWindow, suffix: String) async {
        guard let plan = view(s, kind: .floorPlan, level: "Ground Floor"), let base = plan.levelID,
              let upperLevel = s.model.levelAbove(base), let upper = view(s, kind: .floorPlan, level: upperLevel.name) else { return }
        let before = Set(s.model.allElements.map(\.id))
        var changes = 0
        let origin = Vec2(-60, -40)
        let tread = 0.28
        s.open(plan.id)
        _ = await waitForGraphics(s, plan.id)
        func zoom(_ v: ElementID, _ r: Rect2) async {
            (s.canvases[v] as? Canvas2DView)?.zoom(to: r)
            await pause(500)
        }
        let area = Rect2(min: origin + Vec2(-3, -3), max: origin + Vec2(52, 9))
        await zoom(plan.id, Rect2(min: origin + Vec2(-4, -3), max: origin + Vec2(6, 8)))
        // Create Stair: the first run being drawn.
        let router = CommandRouter(state: s)
        router.run(.stair)
        guard let t = s.activeTool as? StairTool else { return }
        click(t, origin)
        t.pointerMoved(input(origin + Vec2(0, 2.3)))
        s.toolChangedState()
        await pause(500)
        await shot(w, "stair-create-readout-\(suffix)")
        click(t, origin + Vec2(0, 11 * tread))
        if let c = t.startCandidates.first(where: { $0.direction.isAlmostEqual(Vec2(0, -1), tolerance: 1e-6) && $0.point.x < origin.x }) {
            click(t, c.point)
            t.pointerMoved(input(c.point + Vec2(0, -1.4)))
            s.toolChangedState()
            await pause(400)
            await shot(w, "stair-create-second-run-\(suffix)")
            click(t, c.point + Vec2(0, -10 * tread))
        }
        StairRailingDialog.present(state: s, tool: t)
        await pause(700)
        if let sheet = w.attachedSheet { await shot(sheet, "stair-railing-dialog-\(suffix)"); w.endSheet(sheet) }
        _ = t.escape()
        click(t, origin + Vec2(0, 1))
        s.toolChangedState()
        await pause(400)
        await shot(w, "stair-create-selected-run-\(suffix)")
        if t.finish() { changes += 1 }
        s.cancelTool()
        // The other kinds, each drawn with Create Stair.
        func make(_ draw: (StairTool) -> Void) {
            router.run(.stair)
            guard let t = s.activeTool as? StairTool else { return }
            draw(t)
            if t.finish() { changes += 1 }
            s.cancelTool()
        }
        make { t in click(t, origin + Vec2(8, 0)); click(t, origin + Vec2(8, 22 * tread)) }
        make { t in
            click(t, origin + Vec2(16, 0)); click(t, origin + Vec2(16, 11 * tread))
            if let c = t.startCandidates.first(where: { $0.direction.isAlmostEqual(Vec2(-1, 0), tolerance: 1e-6) }) { click(t, c.point); click(t, c.point + Vec2(-10 * tread, 0)) }
        }
        make { t in t.choose(StairTool.RunMode.fullStepSpiral); click(t, origin + Vec2(26, 3)); click(t, origin + Vec2(27.6, 3)) }
        make { t in t.choose(StairTool.RunMode.lWinder); click(t, origin + Vec2(34, 0)) }
        make { t in t.choose(StairTool.RunMode.uWinder); click(t, origin + Vec2(42, 0)) }
        make { t in t.multistoryTopLevelID = s.model.levelAbove(upperLevel.id)?.id; click(t, origin + Vec2(50, 0)); click(t, origin + Vec2(50, 22 * tread)) }
        _ = await waitForGraphics(s, plan.id)
        await zoom(plan.id, area)
        await shot(w, "stair-kinds-base-plan-\(suffix)")
        s.open(upper.id)
        _ = await waitForGraphics(s, upper.id)
        await zoom(upper.id, area)
        await shot(w, "stair-kinds-upper-plan-\(suffix)")
        // Close-ups: the U stair on both levels.
        let u = Rect2(min: origin + Vec2(-3.5, -1.5), max: origin + Vec2(2.5, 6))
        await zoom(upper.id, u)
        await shot(w, "stair-u-upper-plan-\(suffix)")
        s.open(plan.id)
        _ = await waitForGraphics(s, plan.id)
        await zoom(plan.id, u)
        await shot(w, "stair-u-base-plan-\(suffix)")
        // A section along the straight stair, and 3D.
        s.session.perform("Stair Section") { tx in
            var v = ViewData(kind: .section, scale: 50)
            v.planeOrigin = Vec3(origin.x + 8.1, origin.y, 0); v.viewDirection = Vec2(1, 0); v.farClip = 4
            v.cropRegion = Rect2(min: Vec2(-8, -1), max: Vec2(2, 8.5)); v.cropActive = true; v.detailLevel = .fine
            tx.create(.views, name: "Stair Section", data: .view(v))
        }
        changes += 1
        if let sec = view(s, kind: .section, name: "Stair Section") {
            s.open(sec.id)
            _ = await waitForGraphics(s, sec.id)
            (s.canvases[sec.id] as? Canvas2DView)?.zoomToFit()
            await pause(600)
            await shot(w, "stair-section-\(suffix)")
        }
        router.run(.threeDView)
        await pause(1500)
        if let host = s.canvases[s.activeViewID ?? ElementID(0)] as? Viewport3DHost {
            host.viewport.orient(toDirection: Vec3(-1, -1.1, 0.8), animated: false)
            host.viewport.zoomExtents(animated: false)
            await pause(600)
            if let img = host.viewport.snapshot(size: CGSize(width: 1400, height: 900)) { save(img, "stair-3d-\(suffix)") }
        }
        // Back as it was: delete what was added.
        s.open(plan.id)
        let added = s.model.allElements.map(\.id).filter { !before.contains($0) && s.model[$0]?.category != .elementTypes }
        if changes > 0, !added.isEmpty { s.session.delete(added) }
        await pause(300)
    }
}
