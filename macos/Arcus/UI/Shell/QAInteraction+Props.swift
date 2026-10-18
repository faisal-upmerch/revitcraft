import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-PROPS: interaction QA for the Properties palette subject (hooked from `interaction()` with one line).
extension QAHarness {
    /// Door tool → "New Doors" rows; Sill Height set before placement; Esc → the active view; a browser preview is
    /// dropped by a canvas click; opening another view makes the palette follow it.
    static func propertiesInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Properties: New Doors, sill before placement, back to the active view") {
            guard let active = s.activeViewID else { throw QAError("no active view") }
            CommandRouter(state: s).run(.door)
            await pause(120)
            guard case .newElement(.doors, let type)? = Optional(s.paletteSubject) else { throw QAError("palette subject is \(s.paletteSubject), not New Doors") }
            let rows = NewElementProperties.rows(category: .doors, typeID: type, tool: s.activeTool, levelID: nil, model: s.model, defaults: nil)
            try check(rows.contains { $0.entry.name == "Sill Height" } && !rows.contains { $0.entry.name == "Cut Plane Offset" }, "New Doors shows the wrong rows")
            var defaults = CreationDefaults(categories: [.doors])
            try NewElementProperties.set(ParameterID("insert.sillHeight"), value: .double(0.9), category: .doors, typeID: type, tool: s.activeTool,
                                         levelID: nil, model: s.model, defaults: &defaults)
            try check((s.activeTool as? InsertTool)?.sillHeight == 0.9, "Sill Height did not reach the door tool")
            d.escape(); d.escape()
            await pause(80)
            try check(s.paletteSubject == .view(active), "after Esc the palette shows \(s.paletteSubject), not the active view")
            if let other = s.model.views.first(where: { $0.id != active && $0.view?.kind == .floorPlan })?.id {
                s.previewViewProperties(other)
                try check(s.paletteSubject == .view(other), "browser preview not shown")
                s.paletteCanvasClicked()
                try check(s.paletteSubject == .view(active), "canvas click kept the preview")
                s.session.selection.select([other]) // the browser's current single-click behaviour
                s.open(other); await pause(120)
                try check(s.paletteSubject == .view(other), "palette did not follow the activated view")
                s.open(active); await pause(120)
                try check(s.paletteSubject == .view(active), "palette did not follow the view tab switch")
            }
            return "ok"
        }
    }
}
