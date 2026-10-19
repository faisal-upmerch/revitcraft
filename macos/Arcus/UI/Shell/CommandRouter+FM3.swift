import AppKit
import ArcusDomain
import ArcusApplication

// FM3: routing for this batch's commands (Docs/FurnitureMode.md §6).
// Furniture documents grey out Architecture-only tools (walls, rooms, site, structure…) and projects grey out the
// Furniture commands, each with a reason (`FurnitureShell`).

extension CommandRouter {
    /// Why one of this batch's commands can't run now, or nil. Also the mode gate for every command.
    func fm3DisabledReason(_ id: CommandID) -> String? {
        if let reason = FurnitureShell.disabledReason(id, kind: state.mode) { return reason }
        switch id {
        case .furnitureLoadIntoProject, .furnitureLoadAndClose:
            return FurnitureLoad.openProjects().isEmpty ? "Open a project to load this piece into." : nil
        default: return nil
        }
    }
    /// The interactive tool for one of this batch's commands, or nil.
    func fm3MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }
    /// Runs one of this batch's commands; true when handled.
    func fm3Perform(_ id: CommandID) -> Bool {
        switch id {
        case .furnitureFamilyTypes: state.presented = .fm3(.familyTypes)
        case .furnitureCategory: state.presented = .fm3(.category)
        case .furnitureFlex: state.presented = .fm3(.flex(FurnitureParameters.flex(model)))
        case .furnitureLoadIntoProject: FurnitureLoad.run(state, close: false)
        case .furnitureLoadAndClose: FurnitureLoad.run(state, close: true)
        case .newFurniture: AppDelegate.shared?.showHub(tab: .furniture)
        default: return false
        }
        return true
    }
}
