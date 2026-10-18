import AppKit
import ArcusDomain
import ArcusApplication

// F11: Manage, schedules and export: global parameters, coordinates, design options, selections, schedule tools, export formats. Docs/RevitCraftPort.md §5.
// The schedule tools (F12) route through ScheduleCommands (UI/Schedules/ScheduleCommands+F12.swift), like the rest of
// the Modify Schedule/Quantities tab.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f11MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .specifyCoordinates:
            let t = SharedCoordinatesTool(ctx: c, reports: false)
            t.onPick = { [weak state] p in state?.cancelTool(); state?.presented = .f11(.specifyCoordinates(p)) }
            return t
        case .reportCoordinates: return SharedCoordinatesTool(ctx: c, reports: true)
        case .relocateProject: return RelocateProjectTool(ctx: c)
        case .pickToEdit:
            let t = PickToEditTool(ctx: c)
            t.onPick = { [weak state] o in if let state { F11Actions(state: state).setActiveOption(o) } }
            return t
        default: return nil
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f11Perform(_ id: CommandID) -> Bool {
        let a = F11Actions(state: state)
        switch id {
        case .globalParameters: state.presented = .f11(.globalParameters)
        case .rotateTrueNorth: a.rotateTrueNorth()
        case .rotateProjectNorth: state.presented = .f11(.projectTurn(mirror: false))
        case .mirrorProject: state.presented = .f11(.projectTurn(mirror: true))
        case .addToSet: state.presented = .f11(.addToSet)
        case .startingView: state.presented = .f11(.startingView)
        case .saveSelection: a.saveSelection()
        case .loadSelection: state.presented = .f11(.selectionSets(edit: false))
        case .editSelection: state.presented = .f11(.selectionSets(edit: true))
        case .selectJoinedElements: a.selectJoined()
        case .keynoteLegend: a.newKeynoteLegend()
        case .keynotingSettings: state.presented = .f11(.keynotingSettings)
        case .exportDWFx: state.presented = .f11(.exportDWFx)
        case .exportSTL: a.exportSTL()
        case .exportGbXML: a.exportGbXML()
        case .exportRoomAreaReport: a.exportRoomAreaReport()
        case .exportFamilyTypes: a.exportFamilyTypes()
        case .printSetup: state.presented = .f11(.printSetup)
        case .printPreview: F13Print.render(state) { [weak state] data, title in state?.presented = .f11(.printPreview(data, title)) }
        // F13: Print and DXF export honour Print Setup (and DXF offers AIA layers).
        case .print: F13Print.render(state) { [weak state] data, title in if let state { F13Print.printPDF(data, title: title, state: state) } }
        case .exportDXF: a.exportDXF()
        default: return false
        }
        return true
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f11DisabledReason(_ id: CommandID) -> String? {
        let m = model
        let hasOptions = !m.elements(.designOptions).isEmpty
        switch id {
        case .specifyCoordinates, .reportCoordinates, .relocateProject:
            return isPlan ? nil : "Open a plan view to use this tool."
        case .addToSet:
            if !hasOptions { return "Create design options first (Manage ▸ Design Options)." }
            if session.activeDesignOptionID != nil { return "Return to the main model first: Add to Set moves main model elements." }
            if !selection.contains(where: { m[$0]?.category.isModel == true && m[$0]?.designOptionID == nil }) { return "Select main model elements first." }
        case .pickToEdit:
            if !hasOptions { return "Create design options first (Manage ▸ Design Options)." }
            if !isPlan && viewKind != .threeD && !(viewKind?.isVerticalCut ?? false) { return "Open a model view to pick an element." }
        case .saveSelection:
            if selection.isEmpty { return "Select elements first." }
        case .loadSelection, .editSelection:
            if m.manageData.selectionSets.isEmpty { return "No saved selections yet." }
        case .selectJoinedElements:
            if !selection.contains(where: { m[$0]?.wall != nil }) && !selection.contains(where: { id in m.elements(.constraints).contains { $0.constraint?.kind == .join && $0.constraint?.references.contains { $0.elementID == id } == true } }) {
                return "Select walls or joined elements first."
            }
        case .exportSTL:
            if !m.allElements.contains(where: { $0.ownerViewID == nil && $0.category.isModel && ElementMeshes.hasModelGeometry($0) }) { return "The model has no 3D elements." }
        case .exportGbXML, .exportRoomAreaReport:
            if m.elements(.rooms).isEmpty && m.elements(.areas).isEmpty { return "The project has no rooms or areas to export." }
        case .exportFamilyTypes:
            if F11Actions(state: state).editedFamily == nil { return "Open a family in the Family Editor first." }
        case .exportDWFx:
            if m.sheets.isEmpty && state.activeView?.view == nil && state.activeView?.schedule == nil { return "Open a view or create a sheet to export." }
        case .printPreview:
            guard let a = state.activeView, a.sheet != nil || a.view != nil || a.schedule != nil else { return "Open a view, sheet or schedule to preview." }
            if a.view?.kind == .threeD { return "3D views print as an image: use Export Image." }
        default: break
        }
        return nil
    }
}
