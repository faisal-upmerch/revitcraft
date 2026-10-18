import AppKit
import ArcusDomain
import ArcusApplication

// F11: Manage, schedules and export: global parameters, coordinates, design options, selections, schedule tools, export formats. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f11MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f11Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f11DisabledReason(_ id: CommandID) -> String? { nil }
}
