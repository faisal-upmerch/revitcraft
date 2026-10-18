import AppKit
import ArcusDomain
import ArcusApplication

// F810: View, sheets and presentation: hidden lines, cut profile, walkthrough, title blocks, windows, render. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f810MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f810Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f810DisabledReason(_ id: CommandID) -> String? { nil }
}
