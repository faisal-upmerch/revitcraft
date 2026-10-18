import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// W2-CAM: interaction QA for cameras (hooked from `QAHarness.interaction()`).

extension QAHarness {
    /// Places a camera from the plan with real clicks, navigates it (keypad 7, ⌥-drag) with Lock Camera to View on,
    /// undoes back to the placed camera, and checks the camera's glyph and grips in the plan.
    static func cameraInteraction(_ s: DocumentState, _ d: CanvasDriver, plan: Element,
                                  run: @MainActor (String, () async throws -> String) async -> Void) async {
        await run("camera: place from the plan, navigate with the lock on, undo, glyph and grips") {
            s.open(plan.id)
            await d.settle()
            CommandRouter(state: s).run(.cameraView)
            d.click(d.windowPoint(canvasFraction: 0.35, 0.45))
            d.click(d.windowPoint(canvasFraction: 0.65, 0.55))
            await d.flushEvents(); await pause(200)
            guard let camID = s.activeViewID, let placed = s.model[camID], placed.isCameraView, let saved = placed.view?.camera else {
                throw QAError("placing a camera did not open a camera view (active: \(s.activeView?.name ?? "-"))")
            }
            var host: Viewport3DHost?
            for _ in 0..<200 { host = s.canvases[camID] as? Viewport3DHost; if host?.viewport.statistics.triangles ?? 0 > 0 { break }; await pause(30) }
            guard let h = host else { throw QAError("the camera view has no 3D viewport") }
            let vp = h.viewport
            try check(vp.cameraFrameAspect != nil, "the camera frame is not shown")
            s.window?.makeFirstResponder(vp)
            // Keypad 7: top view. Cameras lock to the view by default, so the saved camera follows once navigation settles.
            d.key("7", keyCode: 89, flags: .numericPad)
            for _ in 0..<60 { if s.model[camID]?.view?.camera != saved { break }; await pause(50) }
            let top = s.model[camID]?.view?.camera
            try check(top.map { $0.forward.z < -0.99 } == true, "keypad 7 did not turn the locked camera to look down (\(String(describing: top?.forward)))")
            // ⌥-drag orbits (three-button emulation for trackpads). From the top view the eye sits on the orbit axis, so
            // a sideways drag only spins the view: drag up as well to tilt the camera off the pole.
            let before = vp.camera
            let mid = vp.convert(NSPoint(x: vp.bounds.midX, y: vp.bounds.midY), to: nil)
            d.drag(from: mid, to: NSPoint(x: mid.x + 80, y: mid.y + 60), flags: .option)
            await d.flushEvents()
            let after = vp.camera
            try check(!after.hasSamePose(as: before) && !after.eye.isAlmostEqual(before.eye, tolerance: 1e-3) && after.forward.z > -0.99,
                      "⌥-drag did not orbit (eye \(before.eye) → \(after.eye), forward \(before.forward) → \(after.forward))")
            for _ in 0..<40 { if s.model[camID]?.view?.camera != top { break }; await pause(50) }
            try check(s.model[camID]?.view?.camera != top, "the ⌥-drag was not saved to the locked camera")
            // Each navigation is one undo step.
            for _ in 0..<4 where s.model[camID]?.view?.camera?.hasSamePose(as: saved) != true {
                d.undo(); await d.flushEvents(); await pause(100)
            }
            try check(s.model[camID]?.view?.camera?.hasSamePose(as: saved) == true, "undo did not restore the placed camera")
            // The plan shows the camera; selecting it offers eye and target grips.
            s.open(plan.id)
            await d.settle()
            try check(d.canvas?.graphics?.items.contains { $0.elementID == camID && $0.category == .cameras } == true, "no camera glyph in the plan")
            let grips = GripService.grips(for: s.model[camID]!, s.model, viewKind: .floorPlan)
            try check(grips.count == 2, "the camera has \(grips.count) grips in plan")
            return "camera placed; keypad 7 and ⌥-drag moved the locked camera and undid in steps; glyph and 2 grips in plan"
        }
    }
}
