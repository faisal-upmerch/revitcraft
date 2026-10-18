import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-CANVAS: interaction QA for sketch-mode halftone and the floor selection highlight (hooked from `interaction()`
// with one line). Screenshots: bl-canvas-sketch-halftone.png, bl-canvas-floor-selected.png, bl-canvas-floor-hover.png.
extension QAHarness {
    /// Sketches a rectangular floor on the active plan: while sketching every element of the view is halftone; after
    /// Finish the floor stays selected and its boundary draws in the selection colour. The floor is deleted afterwards
    /// so later steps see the same model.
    static func canvasFeedbackInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Canvas: sketch halftone, floor stays selected and highlighted (BL-CANVAS)") {
            let before = d.failures.count
            guard let c = d.canvas else { throw QAError("no canvas") }
            CommandRouter(state: s).run(.floor)
            await pause(120)
            guard let tool = s.activeTool as? SketchTool else { throw QAError("FL did not start floor sketch mode") }
            try check(RibbonContent.contextualTitle(s) == "Modify | Create Floor Boundary", "tab is “\(RibbonContent.contextualTitle(s) ?? "")”")
            tool.setOption("mode", .text("Rectangle"))
            for p in [Vec2(1, 1), Vec2(5, 3)] { tool.pointerMoved(ToolInput(point: p, rawPoint: p)); tool.pointerDown(ToolInput(point: p, rawPoint: p)) }
            s.toolChangedState()
            c.needsDisplay = true; c.displayIfNeeded(); await pause(120)
            try check(!c.sketchHalftoneElements().isEmpty, "nothing is halftone while sketching")
            d.saveCanvas(c, "bl-canvas-sketch-halftone")
            CommandRouter(state: s).run(.finishSketch)
            await pause(200)
            try check(s.activeTool == nil, "Finish did not leave sketch mode")
            try check(c.sketchHalftoneElements().isEmpty, "the model stayed halftone after Finish")
            let floors = s.model.elements(.floors).filter { $0.slab?.boundary.bounds.contains(Vec2(3, 2)) == true }
            guard let floor = floors.last else { throw QAError("no floor was created") }
            try check(s.session.selection.ids == [floor.id], "the floor is not selected after Finish (selection: \(s.session.selection.ids))")
            s.session.selection.select([floor.id])
            c.needsDisplay = true; c.displayIfNeeded(); await pause(120)
            d.saveCanvas(c, "bl-canvas-floor-selected")
            s.session.selection.clear()
            s.session.selection.preselection = floor.id
            c.needsDisplay = true; c.displayIfNeeded(); await pause(120)
            d.saveCanvas(c, "bl-canvas-floor-hover")
            s.session.selection.preselection = nil
            s.session.delete([floor.id])
            await pause(60)
            let new = d.failures.dropFirst(before)
            try check(new.isEmpty, new.joined(separator: " || "))
            return "floor sketched with the model halftone; selected after Finish; screenshots saved"
        }
    }
}
