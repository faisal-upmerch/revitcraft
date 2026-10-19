import AppKit
import ArcusDomain
import ArcusApplication

// FM8: routing for this batch's commands (Docs/FurnitureMode.md §6).
// Load Furniture (the library browser) and Save as Furniture Template; Insert ▸ Load Family also takes .arcusfurniture
// files; Edit Family on a piece from Furniture mode reopens it there (FamilyEditorWindowController.open asks
// FurnitureEditFamily first, so the command, the Project Browser and double-click all do it).

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil.
    func fm8DisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .saveAsFurnitureTemplate: state.mode == .furniture ? nil : "Only in Furniture documents."
        default: nil
        }
    }
    /// The interactive tool for one of this batch's commands, or nil.
    func fm8MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fm8Perform(_ id: CommandID) -> Bool {
        switch id {
        case .loadFurniture: state.presented = .fm8(.loadFurniture)
        case .saveAsFurnitureTemplate: state.presented = .fm8(.saveTemplate)
        case .loadFamily: FurnitureFileLoad.chooseAndLoad(state) // families and Furniture documents
        default: return false
        }
        return true
    }
}
