import AppKit
import ArcusDomain
import ArcusApplication

// F5: Analyze and Massing: spaces and zones, masses, model by face, model in-place. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f5MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f5Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f5DisabledReason(_ id: CommandID) -> String? { nil }
}
