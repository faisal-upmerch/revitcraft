import AppKit
import ArcusApplication

// FMG2: routing for this batch's commands.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func fmg2DisabledReason(_ id: CommandID) -> String? {
        guard id == .furnitureExplodeParts else { return nil }
        guard state.mode == .furniture else { return "Only in Furniture documents." }
        return state.activeViewID.flatMap { model[$0]?.view?.kind } == .threeD ? nil : "Open a 3D view."
    }
    /// The interactive tool for one of this batch's commands, or nil.
    func fmg2MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fmg2Perform(_ id: CommandID) -> Bool {
        guard id == .furnitureExplodeParts else { return false }
        if let reason = fmg2DisabledReason(id) { state.show(reason, error: true); return true }
        if let v = state.activeViewID { state.presented = .fmg2(.explodeParts(v)) }
        return true
    }
}
