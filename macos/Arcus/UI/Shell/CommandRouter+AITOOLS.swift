import AppKit
import ArcusApplication

// AITOOLS: routing for the AI assistant.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func aitoolsDisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func aitoolsMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func aitoolsPerform(_ id: CommandID) -> Bool { false }
}
