import AppKit
import ArcusApplication

// FM7: routing for this batch's commands (Docs/FurnitureMode.md §6).

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func fm7DisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func fm7MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fm7Perform(_ id: CommandID) -> Bool { false }
}
