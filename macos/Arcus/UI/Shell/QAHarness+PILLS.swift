import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// PILLS: screenshots of every selected capsule (hooked from `screenshots()` with one line, per appearance): a
// Furniture bookcase with three view tabs open (Elevation: Front chosen), the ribbon tabs, a selection's contextual
// tab, Sketch Sweep's ribbon and status line, the bottom bar with toggles on, the Components panel, the Family
// Editor's view tabs, and Home's Recent filter. QA step "Pills sketch ribbon" checks one ribbon shows in sketch mode.
extension QAHarness {
    static func pillsScreenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Pills Check", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Bookcase") { tx in ids = try FurnitureSamples.bookcase(in: tx) }
        guard let plan = view(s, kind: .floorPlan, name: "Ref. Level"), let front = view(s, kind: .elevation, name: "Front"),
              let v3 = view(s, kind: .threeD, name: "{3D}") else { return }
        for v in [plan.id, v3.id, front.id] { s.open(v) }
        _ = await waitForGraphics(s, front.id)
        (s.canvases[front.id] as? Canvas2DView)?.zoomToFit()
        s.ribbonTab = .create; s.ribbonShowsContextual = false
        // View tabs, ribbon tabs, bottom bar: crop region on so a toggle shows its "on" capsule.
        s.session.perform("Crop") { tx in tx.update(front.id) { e in if var v = e.view { v.cropActive = true; e.view = v } } }
        await pause(700)
        await shot(w, "pills-shell-\(suffix)")
        // A selection's contextual tab (Modify | Panels).
        if let left = ids["left"] { s.session.selection.select([left]) }
        await pause(600)
        await shot(w, "pills-contextual-\(suffix)")
        s.session.selection.clear()
        // Sketch Sweep in the front elevation: one ribbon (the sketch's), one status line.
        RibbonFrames.of(s).reset()
        CommandRouter(state: s).run(.furnitureSweep)
        await pause(150) // inside the shell's animation
        await shot(w, "pills-sketch-entering-\(suffix)")
        await pause(500)
        await step("Pills sketch ribbon \(suffix)") {
            let panels = RibbonFrames.of(s).panels.keys.sorted()
            try check(s.activeTool?.isSketchMode == true, "Sketch Sweep did not start")
            try check(s.ribbonShowsContextual, "the contextual tab is not showing")
            try check(panels.contains("c Draw"), "no Draw panel: \(panels)")
            try check(panels.allSatisfy { $0.hasPrefix("c ") }, "panels of two ribbons: \(panels)")
            return "\(RibbonContent.contextualTitle(s) ?? "?"): \(panels.count) panels"
        }
        await shot(w, "pills-sketch-\(suffix)")
        s.cancelTool()
        await pause(400)
        await shot(w, "pills-sketch-left-\(suffix)")
        // The Components panel (segmented filters, 3D/2D, Iso/Front/Side/Top).
        CommandRouter(state: s).run(.components)
        await pause(900)
        await shot(w, "pills-components-\(suffix)")
        CommandRouter(state: s).run(.components)
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(500)
        // Home: the Recent filter (All / Projects / Furniture / Families) with Furniture chosen.
        let m = HomeModel(tab: .recent)
        m.recentFilter = .furniture
        let hub = AppDelegate.makeHubWindow(model: m)
        hub.title = "Home (QA)"
        hub.center()
        hub.orderFront(nil)
        await pause(1000)
        await shot(hub, "pills-home-\(suffix)")
        hub.close()
    }
}
