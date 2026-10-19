import AppKit
import ArcusDomain
import ArcusApplication

// FMG1: routing for this batch's commands: Blend's Edit Top / Edit Base, in a Blend sketch (switches the sketch) or on
// a selected blend (opens its top or base for editing), as in Revit.

extension CommandRouter {
    /// The running Blend sketch, if any.
    var fmg1BlendSketch: SketchTool? { (state.activeTool as? SketchTool).flatMap { $0.isBlendSketch ? $0 : nil } }
    /// The one selected blend, if any.
    var fmg1SelectedBlend: Element? {
        guard selection.count == 1, let e = model[selection[0]], e.furnitureForm?.kind == .blend, e.furnitureForm?.topProfile != nil else { return nil }
        return e
    }

    /// Why one of this batch's commands can't run now, or nil.
    func fmg1DisabledReason(_ id: CommandID) -> String? {
        guard id == .furnitureBlendEditTop || id == .furnitureBlendEditBase else { return nil }
        let top = id == .furnitureBlendEditTop
        if let t = fmg1BlendSketch { return t.isEditingBlendTop == top ? (top ? "You're sketching the top." : "You're sketching the base.") : nil }
        guard fmg1SelectedBlend != nil else { return "Sketch or select a blend." }
        return isPlan ? nil : "Edit a blend's sketch in a plan view."
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fmg1MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard id == .furnitureBlendEditTop || id == .furnitureBlendEditBase, fmg1BlendSketch == nil, let e = fmg1SelectedBlend else { return nil }
        return SketchTool.editBlend(c, e.id, top: id == .furnitureBlendEditTop, commandID: e.furnitureForm?.isVoid == true ? .furnitureVoidBlend : .furnitureBlend)
    }

    /// Runs one of this batch's commands; true when handled.
    func fmg1Perform(_ id: CommandID) -> Bool {
        guard id == .furnitureBlendEditTop || id == .furnitureBlendEditBase, let t = fmg1BlendSketch else { return false }
        t.editBlend(top: id == .furnitureBlendEditTop)
        state.toolRevision += 1
        return true
    }
}
