import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-SITE: interaction QA for toposolids (ARCUS-070) and the Modify | Walls panels at 1440 pt (ARCUS-043).
// Hooked from `QAHarness.interaction()`.

extension QAHarness {
    static func blSiteInteraction(_ s: DocumentState, _ d: CanvasDriver, plan: Element,
                                  run: @MainActor (String, () async throws -> String) async -> Void) async {
        await run("toposolid: sketch a rectangle, Sub-Divide, section shows layers") {
            s.open(plan.id)
            await d.settle()
            d.canvas?.zoom(to: Rect2(min: Vec2(-8, -8), max: Vec2(22, 18))); await pause(60) // every pick on screen
            let before = s.model.elements(.topography).count
            CommandRouter(state: s).run(.toposolid)
            guard let tool = s.activeTool as? ToposolidSketchTool else { throw QAError("Toposolid did not start its sketch tool") }
            tool.setOption("mode", .text("Rectangle")); s.toolChangedState()
            d.click(model: Vec2(-6, -6)); await pause(40)
            d.click(model: Vec2(20, 16)); await d.flushEvents(); await pause(100)
            let solids = s.model.elements(.topography).filter(\.isToposolid)
            try check(s.model.elements(.topography).count == before + 1 && solids.count == 1, "no toposolid was created (\(s.session.lastError?.message ?? "-"))")
            let id = solids[0].id
            try check(ElementMeshes.parts(s.model[id]!, s.model).count == 2, "the toposolid is not layered")
            s.session.selection.select([id])
            await d.verify("toposolid selected")
            CommandRouter(state: s).run(.subdivideToposolid)
            guard let sub = s.activeTool as? ToposolidSketchTool else { throw QAError("Sub-Divide did not start") }
            sub.setOption("mode", .text("Rectangle")); s.toolChangedState()
            d.click(model: Vec2(14, 2)); await pause(40)
            d.click(model: Vec2(18, 6)); await d.flushEvents(); await pause(100)
            try check(s.model.hosted(by: id).contains(where: \.isToposolidSubdivision), "no sub-division was created")
            d.escape(); d.escape()
            return "toposolid with 2 layers and a sub-division"
        }
        await run("Modify | Walls panels fit at 1440 pt") {
            guard let w = s.window else { throw QAError("no window") }
            let old = w.frame.size
            defer { w.setContentSize(old) }
            w.setContentSize(NSSize(width: 1440 + CGFloat(s.docks.leadingInset) + 10, height: 900)) // W4-WIRE: the ribbon strip starts after the floating sidebar, so 1440 pt of ribbon room needs the sidebar's inset on top
            s.open(plan.id)
            await d.settle()
            guard let wall = s.model.elements(.walls).first else { return "no wall to select" }
            s.session.selection.select([wall.id])
            await d.flushEvents(); await pause(400)
            await d.verify("Modify | Walls at 1440")
            // The ribbon's horizontal scroll view: its document must fit its visible width.
            var found: [(CGFloat, CGFloat)] = []
            @MainActor func walk(_ v: NSView) {
                if let sv = v as? NSScrollView, sv.frame.height < 120, sv.frame.height > 60 {
                    found.append((sv.documentView?.frame.width ?? 0, sv.contentView.bounds.width))
                }
                v.subviews.forEach(walk)
            }
            if let root = w.contentView?.superview ?? w.contentView { walk(root) }
            guard let (doc, visible) = found.max(by: { $0.0 < $1.0 }) else { return "ribbon scroll view not found (check the screenshot)" }
            try check(doc <= visible + 1, "the Modify | Walls panels need \(Int(doc)) pt but \(Int(visible)) pt are visible")
            return "ribbon content \(Int(doc)) pt in \(Int(visible)) pt"
        }
    }
}
