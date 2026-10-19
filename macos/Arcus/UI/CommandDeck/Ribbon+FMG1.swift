import SwiftUI
import ArcusDomain
import ArcusApplication

// FMG1: Blend's Mode panel, as Revit's: Edit Top while sketching the base, Edit Base while sketching the top, and both
// on a selected blend.

extension RibbonContent {
    @MainActor static func fmg1ToolPanels(_ tool: any InteractiveTool) -> [RibbonPanel] {
        guard let t = tool as? SketchTool, t.isBlendSketch else { return [] }
        return [RibbonPanel(title: "Blend", items: [.large(t.isEditingBlendTop ? .furnitureBlendEditBase : .furnitureBlendEditTop)], tint: build)]
    }

    @MainActor static func fmg1SelectionPanels(_ state: DocumentState) -> [RibbonPanel] {
        guard state.mode == .furniture, state.activeTool == nil, state.session.selection.ids.count == 1,
              state.model[state.session.selection.ids[0]]?.furnitureForm?.kind == .blend else { return [] }
        return [RibbonPanel(title: "Mode", items: [.large(.furnitureBlendEditTop), .large(.furnitureBlendEditBase)], tint: build)]
    }
}
