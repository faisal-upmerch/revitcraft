import SwiftUI
import ArcusDomain
import ArcusApplication

/// Routes `DialogKind` to its sheet content.
struct DialogHost: View {
    let state: DocumentState
    let dialog: DialogKind

    var body: some View {
        Group {
            switch dialog {
            case .newSchedule(let k): NewScheduleDialog(state: state, kind: k)
            case .scheduleProperties(let id): SchedulePropertiesDialog(state: state, scheduleID: id)
            case .newSheet: NewSheetDialog(state: state)
            case .placeView(let s): PlaceViewDialog(state: state, sheetID: s)
            case .visibilityGraphics(let v): VisibilityGraphicsDialog(state: state, viewID: v)
            case .viewRange(let v): ViewRangeDialog(state: state, viewID: v)
            case .typeProperties(let t): TypePropertiesDialog(state: state, typeID: t)
            case .projectInfo: ProjectInfoDialog(state: state)
            case .projectUnits: ProjectUnitsDialog(state: state)
            case .projectParameters: ProjectParametersDialog(state: state)
            case .materials: MaterialsDialog(state: state)
            case .lineStyles: LineStylesDialog(state: state)
            case .phases: PhasesDialog(state: state)
            case .designOptions: DesignOptionsDialog(state: state)
            case .revisions: RevisionsDialog(state: state)
            case .location: LocationDialog(state: state)
            case .exportPDF: ExportPDFDialog(state: state)
            case .exportIFC: ExportIFCDialog(state: state)
            case .exportDXF: EmptyView()
            case .importCAD(let url, let isLink, let isDWG): ImportCADDialog(state: state, url: url, isLink: isLink, isDWG: isDWG)
            case .importIFC(let url): ImportIFCDialog(state: state, url: url)
            case .manageLinks: ManageLinksDialog(state: state)
            case .modelHealth: ModelHealthDialog(state: state)
            case .rename(let id): RenameDialog(state: state, elementID: id)
            case .newFamily: NewFamilyDialog(state: state)
            case .keyboardShortcuts: KeyboardShortcutsDialog(state: state)
            case .csvImport(let s, let url): CSVImportDialog(state: state, scheduleID: s, url: url)
            case .selectByCategory: CategoryPickDialog(state: state, mode: .selectInView)
            case .filterSelection: CategoryPickDialog(state: state, mode: .filterSelection)
            case .pasteToLevels: PasteToLevelsDialog(state: state)
            case .purge: PurgeDialog(state: state)
            case .linkPDF(let url): UnderlayDialog(state: state, url: url, isPDF: true)
            case .linkImage(let url): UnderlayDialog(state: state, url: url, isPDF: false)
            case .dwgUnavailable: DWGUnavailableDialog(state: state)
            case .report(let title, let text): ReportDialog(state: state, title: title, text: text)
            case .newView(let kind): NewViewDialog(state: state, kind: kind)
            case .snaps: SnapsDialog(state: state)
            case .overrideGraphics(let v, let ids): OverrideGraphicsDialog(state: state, viewID: v, elementIDs: ids) // WP6a
            case .tagAll(let v): TagAllDialog(state: state, viewID: v)
            case .colorSchemes(let v, let placeLegend): ColorSchemesDialog(state: state, viewID: v, placeLegend: placeLegend)
            case .newAreaPlan: NewAreaPlanDialog(state: state)
            case .importRevit(let url): RevitImportDialog(state: state, url: url)
            case .site(let d): SiteDialogHost(state: state, dialog: d) // W2-DWG
            case .componentLibrary(let cats): ComponentLibraryView(state: state, categories: cats) // W2-LIB
            case .findReplace(let v): FindReplaceDialog(state: state, viewID: v) // W2-ANNOT
            case .checkSpelling(let v): CheckSpellingDialog(state: state, viewID: v) // W2-ANNOT
            case .schedulePropertiesTab(let id, let tab, let field): SchedulePropertiesDialog(state: state, scheduleID: id, initialTab: tab, initialField: field) // BL-SCHED
            case .sheetTitle(let s): SheetTitleDialog(state: state, sheetID: s) // BL-BROWSER
            case .filters(let f): FiltersDialog(state: state, initial: f) // BL-VG
            case .viewTemplates(let v, let mode, let t): ViewTemplatesDialog(state: state, viewID: v, mode: mode, initial: t) // BL-VG
            case .objectStyles: ObjectStylesDialog(state: state) // BL-VG
            case .warnings: WarningsDialog(state: state) // BL-VG
            case .selectByID: SelectByIDDialog(state: state) // BL-VG
            case .additionalSettings(let tab): AdditionalSettingsDialog(state: state, tab: tab) // BL-VG
            case .userInterface: UserInterfaceDialog(state: state) // BL-VG
            case .f11(let d): F11DialogHost(state: state, dialog: d) // F11
            }
        }
        .frame(minWidth: 420)
        .presentationSizing(.fitted)
        .onExitCommand { state.presented = nil } // W4-AUDIT: Escape closes dialogs that have only a Done button (Cancel buttons keep their own .cancelAction)
        .background(SheetEscapeCloser { state.presented = nil }) // Escape regardless of which control has focus
    }
}

/// Closes the sheet on Escape at the AppKit level: SwiftUI's `onExitCommand` needs the focus system to route the key,
/// which tables, toggles and lists inside a sheet don't always do. A text field being edited keeps its own Escape
/// (it cancels the edit first).
private struct SheetEscapeCloser: NSViewRepresentable {
    let close: () -> Void
    func makeNSView(context: Context) -> EscapeView { EscapeView(close: close) }
    func updateNSView(_ v: EscapeView, context: Context) { v.close = close }
    final class EscapeView: NSView {
        var close: () -> Void
        private var monitor: Any?
        init(close: @escaping () -> Void) { self.close = close; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard let window else { return } // leaving the window (the sheet closing) removes the monitor above
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] e in
                guard let self, let window, e.window === window, e.keyCode == 53, e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return e }
                if window.firstResponder is NSTextView { return e }
                self.close()
                return nil
            }
        }
    }
}

/// Standard dialog chrome: title, content, and a button row.
struct DialogFrame<Content: View>: View {
    let title: String
    var subtitle: String = ""
    var okTitle = "OK"
    var okDisabled = false
    var showCancel = true
    let state: DocumentState
    let onOK: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DialogMetrics.spacing) { // W4-SHELL: DialogGrammar.swift
            DialogTitle(title: title, subtitle: subtitle)
            content
            DialogButtonRow(okTitle: okTitle, okDisabled: okDisabled, showCancel: showCancel, onCancel: { state.presented = nil }, onOK: onOK)
        }
        .padding(DialogMetrics.padding)
    }
}

/// Labeled form row with a fixed label column.
struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).frame(width: 150, alignment: .trailing).foregroundStyle(.secondary)
            content
        }
    }
}
