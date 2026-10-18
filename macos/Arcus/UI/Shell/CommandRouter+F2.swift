import AppKit
import ArcusDomain
import ArcusApplication

// F2: Architecture B: stacked walls, multi-segment grids, work planes, multistory stairs, roof tools, slanted columns. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f2MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f2Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f2DisabledReason(_ id: CommandID) -> String? { nil }
}
