import AppKit
import ArcusApplication

// FMG4: routing for this batch's commands.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func fmg4DisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func fmg4MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fmg4Perform(_ id: CommandID) -> Bool { false }
}
