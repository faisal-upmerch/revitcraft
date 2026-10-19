import AppKit
import ArcusDomain
import ArcusApplication

// COMP: routing for the Component Library (Domain/Furniture/Components, UI/Library/Components).

extension CommandRouter {
    static let compIDs: Set<CommandID> = Set(CommandID.allCases.filter { $0.rawValue.hasPrefix("component") && ![.component, .componentLibrary].contains($0) })

    var compSelectedHosts: [ElementID] { selection.filter { model[$0].map { ComponentPlacement.hostKind($0, model) != nil } ?? false } }

    /// Why one of this batch's commands can't run now, or nil.
    func compDisabledReason(_ id: CommandID) -> String? {
        guard Self.compIDs.contains(id) else { return nil }
        let furnitureOnly: Set<CommandID> = [.componentAssembly, .componentHardwareRules, .componentBOM, .componentPowerSummary]
        if furnitureOnly.contains(id), state.mode != .furniture { return "Only in Furniture documents." }
        switch id {
        case .componentPlace:
            if ComponentPanelModel.of(state).selected == nil { return "Pick a component in the Components panel." }
            let kind = model[state.editingViewID]?.view?.kind
            return kind?.isPlan == true || kind?.isVerticalCut == true || kind == .threeD ? nil : "Open a plan, an elevation, a section or a 3D view."
        case .componentReplace:
            if ComponentPanelActions.selectedComponents(state).isEmpty { return "Select placed components." }
            return ComponentPanelModel.of(state).selected == nil ? "Pick the new component in the Components panel." : nil
        case .componentAssembly:
            return selection.count == 1 && model[selection[0]]?.furnitureBay != nil ? nil : "Select one empty bay."
        case .componentSaveSelection:
            return selection.isEmpty ? "Select parts, fronts or hardware." : nil
        default:
            if let a = CommandCatalog.compAction(id) {
                return ComponentActions.available(for: selection, model).contains(a) ? nil : "Select a door, drawer, flap or bay that can take it."
            }
            return nil
        }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func compMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard id == .componentPlace else { return nil }
        let panel = ComponentPanelModel.of(state)
        guard let d = panel.selected else { return nil }
        let tool = ComponentPlaceTool(ctx: c, definition: d, typeName: panel.selectedType, values: panel.presetValues,
                                      alignment: panel.presetName.flatMap { n in panel.store.presets(for: d).first { $0.name == n }?.alignment })
        tool.placed = { _ in ComponentLibraryStore.shared.used(d.id) }
        return tool
    }

    /// Runs one of this batch's commands; true when handled.
    func compPerform(_ id: CommandID) -> Bool {
        guard Self.compIDs.contains(id) else { return false }
        let panel = ComponentPanelModel.of(state)
        switch id {
        case .components:
            panel.isShown.toggle()
            state.onWorkspaceChange?()
        case .componentBrowser: ComponentBrowserWindow.show(state)
        case .componentReplace: ComponentPanelActions.replace(state)
        case .componentAssembly: state.presented = .comp(.assembly(selection[0]))
        case .componentHardwareRules: state.presented = .comp(.hardwareRules)
        case .componentSaveSelection: state.presented = .comp(.saveSelection(selection))
        case .componentUpdate: state.presented = .comp(.update)
        case .componentBOM, .componentPowerSummary:
            let name = id == .componentBOM ? ComponentSchedules.bomName : ComponentSchedules.powerName
            var sid: ElementID?
            session.perform("Open \(name)") { tx in sid = ComponentSchedules.ensure(name, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true) } else if let sid { state.open(sid) }
        case .componentNewFamily:
            // The Furniture Hardware / Component template in the Family Editor: forms, parameters, material slots and types
            // as in any family; Load into Project, place it, then Save Selection as Component adds it to My Components.
            FamilyEditorWindowController.open(new: ComponentUserLibrary.template(name: "Component").family, state: state)
        default:
            guard let a = CommandCatalog.compAction(id) else { return false }
            state.presented = .comp(.action(a, compSelectedHosts))
        }
        return true
    }
}
