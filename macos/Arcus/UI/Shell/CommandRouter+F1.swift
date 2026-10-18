import AppKit
import ArcusDomain
import ArcusApplication

// F1: Architecture A: Model Text, Wall: Reveal, openings, Place Model Group, spline and ellipse modes. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f1MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f1Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f1DisabledReason(_ id: CommandID) -> String? { nil }
}
