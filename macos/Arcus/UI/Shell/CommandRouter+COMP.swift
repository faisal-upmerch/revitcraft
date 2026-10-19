import AppKit
import ArcusApplication

// COMP: routing for the Component Library.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func compDisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func compMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func compPerform(_ id: CommandID) -> Bool { false }
}
