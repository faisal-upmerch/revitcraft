import Foundation

// AICORE: the Arcus AI assistant.

extension CommandCatalog {
    static let aicoreCommands: [CommandInfo] = [
        CommandInfo(.aiAssistant, "AI Assistant", .view, "sparkles", shortcut: "⇧⌘A",
                    help: "Open the AI assistant: describe what to create or change and Arcus makes it in this window.",
                    keywords: ["ai", "assistant", "chat", "prompt", "ask", "claude", "copilot", "generate"]),
    ]
}
