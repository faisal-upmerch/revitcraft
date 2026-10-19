import AppKit
import ArcusApplication

// RevitCraft port feature batches: one dispatch point into each batch's CommandRouter+F*.swift.

extension CommandRouter {
    func portDisabledReason(_ id: CommandID) -> String? {
        f1DisabledReason(id) ?? f2DisabledReason(id) ?? f34DisabledReason(id) ?? f5DisabledReason(id) ?? f67DisabledReason(id) ?? f810DisabledReason(id) ?? f11DisabledReason(id) ?? f1415DisabledReason(id) ?? dwgDisabledReason(id)
    }
    func portMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        f1MakeTool(id, c) ?? f2MakeTool(id, c) ?? f34MakeTool(id, c) ?? f5MakeTool(id, c) ?? f67MakeTool(id, c) ?? f810MakeTool(id, c) ?? f11MakeTool(id, c) ?? f1415MakeTool(id, c)
    }
    func portPerform(_ id: CommandID) -> Bool {
        f1Perform(id) || f2Perform(id) || f34Perform(id) || f5Perform(id) || f67Perform(id) || f810Perform(id) || f11Perform(id) || f1415Perform(id) || dwgPerform(id)
    }
}
