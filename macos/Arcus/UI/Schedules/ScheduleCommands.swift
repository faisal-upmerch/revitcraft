import AppKit
import Observation
import ArcusDomain
import ArcusApplication

// BL-SCHED: the "Modify Schedule/Quantities" commands (columns, rows, titles & headers, appearance, Highlight in Model).

/// Observable tick bumped when a schedule's active cell or table changes, so ribbon buttons re-evaluate availability.
@MainActor
@Observable
final class ScheduleUIState {
    static let shared = ScheduleUIState()
    var revision = 0
}

/// Schedule Properties dialog tabs.
enum ScheduleTab: Int, CaseIterable {
    case fields, filter, sorting, formatting, appearance
    var title: String {
        switch self {
        case .fields: "Fields"
        case .filter: "Filter"
        case .sorting: "Sorting/Grouping"
        case .formatting: "Formatting"
        case .appearance: "Appearance"
        }
    }
}

@MainActor
enum ScheduleCommands {
    static let all: Set<CommandID> = [.scheduleProperties, .scheduleInsertColumn, .scheduleDeleteColumn, .scheduleHideColumn, .scheduleUnhideAllColumns,
                                      .scheduleResizeColumn, .scheduleInsertRow, .scheduleDeleteRow, .scheduleMergeHeaders, .scheduleGroupHeaders,
                                      .scheduleUngroupHeaders, .scheduleAppearance, .scheduleFormatUnit, .scheduleCalculatedField, .highlightInModel]

    /// The active schedule view, when the active view is a schedule.
    static func activeTable(_ state: DocumentState) -> ScheduleTableView? {
        guard let id = state.activeViewID, state.model[id]?.schedule != nil else { return nil }
        return state.canvases[id] as? ScheduleTableView
    }

    static func disabledReason(_ id: CommandID, _ state: DocumentState) -> String? {
        guard all.contains(id) else { return nil }
        _ = ScheduleUIState.shared.revision
        guard let sid = state.activeViewID, let def = state.model[sid]?.schedule else { return "Open a schedule first." }
        let table = activeTable(state)
        let hasCell = table?.active != nil
        switch id {
        case .scheduleDeleteColumn, .scheduleHideColumn, .scheduleResizeColumn, .scheduleGroupHeaders, .scheduleMergeHeaders, .scheduleFormatUnit:
            if !hasCell { return "Click a cell in the column first." }
            if id == .scheduleDeleteColumn, let t = table, t.selectedFieldIDs.count >= def.fields.count { return "A schedule needs at least one field." }
        case .scheduleUngroupHeaders:
            guard let t = table, hasCell else { return "Click a cell in a grouped column first." }
            if !def.headerGroups.contains(where: { g in g.fieldIDs.contains { t.selectedFieldIDs.contains($0) } }) { return "The selected columns aren't grouped." }
        case .scheduleUnhideAllColumns:
            if !def.fields.contains(where: \.hidden) { return "No columns are hidden." }
        case .scheduleInsertRow:
            if def.kind != .sheetList { return "Rows of this schedule come from the model: add elements to add rows." }
        case .scheduleDeleteRow, .highlightInModel:
            if table?.selectedElementIDs.isEmpty ?? true { return "Click a cell in a row with elements first." }
        default: break
        }
        return nil
    }

    static func perform(_ id: CommandID, _ state: DocumentState) {
        guard let sid = state.activeViewID, state.model[sid]?.schedule != nil else { return }
        let table = activeTable(state)
        let fields = table?.selectedFieldIDs ?? []
        switch id {
        case .scheduleProperties: state.presented = .schedulePropertiesTab(sid, tab: ScheduleTab.fields.rawValue, fieldID: nil)
        case .scheduleInsertColumn, .scheduleCalculatedField: state.presented = .schedulePropertiesTab(sid, tab: ScheduleTab.fields.rawValue, fieldID: nil)
        case .scheduleAppearance: state.presented = .schedulePropertiesTab(sid, tab: ScheduleTab.appearance.rawValue, fieldID: nil)
        case .scheduleFormatUnit: state.presented = .schedulePropertiesTab(sid, tab: ScheduleTab.formatting.rawValue, fieldID: fields.first)
        case .scheduleDeleteColumn:
            state.session.editSchedule(sid, fields.count == 1 ? "Delete Column" : "Delete Columns") { def in for f in fields { def.removeField(f) } }
        case .scheduleHideColumn:
            state.session.editSchedule(sid, "Hide Column") { def in for i in def.fields.indices where fields.contains(def.fields[i].id) { def.fields[i].hidden = true } }
            state.show("Hidden columns still filter and sort. Unhide All shows them again.")
        case .scheduleUnhideAllColumns:
            state.session.editSchedule(sid, "Unhide All Columns") { def in for i in def.fields.indices { def.fields[i].hidden = false } }
        case .scheduleResizeColumn:
            let current = state.model[sid]?.schedule?.field(fields.first ?? "")?.width ?? 0.025
            state.requestText(prompt: "Column width on paper (mm)", initial: String(format: "%g", current * 1000)) { text in
                guard let text, let mm = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)),
                      mm >= 5, mm <= 400 else {
                    if text != nil { state.show("Type a width between 5 and 400 mm.", error: true) }
                    return
                }
                state.session.editSchedule(sid, "Resize Column") { def in for i in def.fields.indices where fields.contains(def.fields[i].id) { def.fields[i].width = mm / 1000 } }
            }
        case .scheduleInsertRow: state.presented = .newSheet
        case .scheduleDeleteRow:
            let ids = table?.selectedElementIDs ?? []
            let noun = ids.count == 1 ? "element" : "\(ids.count) elements"
            state.requestConfirmation(message: "Delete the \(noun) of the selected row\(ids.count == 1 ? "" : "s") from the model?", confirmTitle: "Delete") { ok in
                guard ok else { return }
                state.session.delete(ids)
                if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
            }
        case .scheduleGroupHeaders: groupHeaders(state, sid, fields)
        case .scheduleUngroupHeaders: state.session.editSchedule(sid, "Ungroup Headers") { $0.ungroupHeaders(fields) }
        case .scheduleMergeHeaders:
            if state.model[sid]?.schedule?.headerGroups.contains(where: { g in g.fieldIDs.contains { fields.contains($0) } }) == true {
                state.session.editSchedule(sid, "Unmerge Headers") { $0.ungroupHeaders(fields) }
            } else {
                groupHeaders(state, sid, fields)
            }
        case .highlightInModel: table?.highlightInModel()
        default: break
        }
    }

    static func groupHeaders(_ state: DocumentState, _ sid: ElementID, _ fields: [String]) {
        guard !fields.isEmpty else { return }
        let first = state.model[sid]?.schedule?.field(fields[0])?.heading ?? "Group"
        state.requestText(prompt: "Heading over the selected columns", initial: fields.count == 1 ? first : "Group") { text in
            guard let text else { return }
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            state.session.editSchedule(sid, "Group Headers") { $0.groupHeaders(fields, title: title) }
        }
    }

    static func renameHeaderGroup(_ table: ScheduleTableView, groupID: String, current: String) {
        let state = table.state, sid = table.scheduleID
        state.requestText(prompt: "Group heading", initial: current) { text in
            guard let text else { return }
            state.session.editSchedule(sid, "Rename Header Group") { def in
                var groups = def.headerGroups
                if let i = groups.firstIndex(where: { $0.id == groupID }) { groups[i].title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                def.headerGroups = groups
            }
        }
    }

    /// Right-click menu of a schedule cell.
    static func contextMenu(_ state: DocumentState) -> NSMenu {
        let b = ContextMenuBuilder(state: state, viewID: state.activeViewID ?? ElementID(0), canvas: nil)
        let menu = NSMenu()
        for (cmd, symbol) in [(CommandID.highlightInModel, "scope"), (.scheduleProperties, "slider.horizontal.3")] {
            menu.addItem(b.item(CommandCatalog.info(cmd).title, symbol, cmd))
        }
        menu.addItem(.separator())
        for cmd in [CommandID.scheduleInsertColumn, .scheduleDeleteColumn, .scheduleHideColumn, .scheduleUnhideAllColumns, .scheduleResizeColumn] {
            menu.addItem(b.item(CommandCatalog.info(cmd).title, CommandCatalog.info(cmd).symbol, cmd))
        }
        menu.addItem(.separator())
        for cmd in [CommandID.scheduleGroupHeaders, .scheduleUngroupHeaders, .scheduleFormatUnit, nil, .scheduleDeleteRow, .exportScheduleCSV] {
            guard let cmd else { menu.addItem(.separator()); continue }
            menu.addItem(b.item(CommandCatalog.info(cmd).title, CommandCatalog.info(cmd).symbol, cmd))
        }
        return menu
    }
}
