import AppKit
import ArcusApplication

// FM3D: routing for this batch's commands.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func fm3dDisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func fm3dMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fm3dPerform(_ id: CommandID) -> Bool { false }
}
