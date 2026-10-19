import AppKit
import ArcusApplication

// STAIR: routing for the stairs batch.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func stairDisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func stairMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func stairPerform(_ id: CommandID) -> Bool { false }
}
