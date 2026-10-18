import AppKit
import ArcusDomain
import ArcusApplication

// F1415: Family Editor: main-window editor, views, reference/model lines, controls, swept blend, voids, openings. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f1415MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f1415Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f1415DisabledReason(_ id: CommandID) -> String? { nil }
}
