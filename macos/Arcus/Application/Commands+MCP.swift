import Foundation

// MCP: Design with Claude (Docs/MCP.md §6): Help, Manage ▸ Add-Ins ▸ Claude, command search.

extension CommandCatalog {
    static let mcpCommands: [CommandInfo] = [
        CommandInfo(.designWithClaude, "Design with Claude…", .manage, "sparkles",
                    help: "Set up Claude Desktop or Claude Code to build and edit Arcus designs from a description, and let Claude edit open documents.",
                    keywords: ["claude", "mcp", "ai", "assistant", "chat", "prompt", "describe", "generate", "agent"]),
    ]
}
