import AppKit
import ArcusApplication

// AICORE: routing for the AI assistant.

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func aicoreDisabledReason(_ id: CommandID) -> String? { nil }
    /// The interactive tool for one of this batch's commands, or nil.
    func aicoreMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func aicorePerform(_ id: CommandID) -> Bool {
        guard id == .aiAssistant else { return false }
        AIAssistantPanel.toggle(in: state)
        return true
    }
}
