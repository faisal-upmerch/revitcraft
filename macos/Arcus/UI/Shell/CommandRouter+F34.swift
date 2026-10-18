import AppKit
import ArcusDomain
import ArcusApplication

// F34: Structure and reinforcement: truss, brace, beam system, structural settings, rebar, area/path/fabric reinforcement. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f34MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f34Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f34DisabledReason(_ id: CommandID) -> String? { nil }
}
