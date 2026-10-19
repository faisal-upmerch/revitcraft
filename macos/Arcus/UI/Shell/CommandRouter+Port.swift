import AppKit
import ArcusApplication

// RevitCraft port and Furniture mode batches: one dispatch point into each batch's CommandRouter+<TAG>.swift.

extension CommandRouter {
    func portDisabledReason(_ id: CommandID) -> String? {
        let batches: [(CommandID) -> String?] = [
            f1DisabledReason, f2DisabledReason, f34DisabledReason, f5DisabledReason, f67DisabledReason, f810DisabledReason,
            f11DisabledReason, f1415DisabledReason, dwgDisabledReason,
            homeDisabledReason, fesDisabledReason, fm3DisabledReason, fm4DisabledReason, fm5DisabledReason, fm6DisabledReason,
            fm7DisabledReason, fm8DisabledReason, fm9DisabledReason, stairDisabledReason, mcpDisabledReason,
        ]
        for b in batches { if let r = b(id) { return r } }
        return nil
    }
    func portMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        let batches: [(CommandID, ToolContext) -> (any InteractiveTool)?] = [
            f1MakeTool, f2MakeTool, f34MakeTool, f5MakeTool, f67MakeTool, f810MakeTool, f11MakeTool, f1415MakeTool,
            homeMakeTool, fesMakeTool, fm3MakeTool, fm4MakeTool, fm5MakeTool, fm6MakeTool, fm7MakeTool, fm8MakeTool, fm9MakeTool, stairMakeTool, mcpMakeTool,
        ]
        for b in batches { if let t = b(id, c) { return t } }
        return nil
    }
    func portPerform(_ id: CommandID) -> Bool {
        let batches: [(CommandID) -> Bool] = [
            f1Perform, f2Perform, f34Perform, f5Perform, f67Perform, f810Perform, f11Perform, f1415Perform, dwgPerform,
            homePerform, fesPerform, fm3Perform, fm4Perform, fm5Perform, fm6Perform, fm7Perform, fm8Perform, fm9Perform, stairPerform, mcpPerform,
        ]
        return batches.contains { $0(id) }
    }
}
