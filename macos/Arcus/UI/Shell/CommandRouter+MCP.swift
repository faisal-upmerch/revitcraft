import AppKit
import ArcusApplication

// MCP: routing for Design with Claude (Docs/MCP.md §6).

extension CommandRouter {
    func mcpDisabledReason(_ id: CommandID) -> String? { nil }
    func mcpMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    func mcpPerform(_ id: CommandID) -> Bool {
        guard id == .designWithClaude else { return false }
        ClaudeSetupWindow.show()
        return true
    }
}
