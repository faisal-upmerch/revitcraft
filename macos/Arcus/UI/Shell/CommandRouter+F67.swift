import AppKit
import ArcusDomain
import ArcusApplication

// F67: Insert: links, imports, load as group, insert from file, decals, point clouds, topography, DWF markup. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f67MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands that has no tool; true when handled.
    func f67Perform(_ id: CommandID) -> Bool { false }
    /// Why one of this batch's commands can't run now, or nil.
    func f67DisabledReason(_ id: CommandID) -> String? { nil }
}
