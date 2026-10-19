import AppKit
import SwiftUI
import Observation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

enum Workspace: String, CaseIterable, Codable {
    case bimFamiliar = "BIM Familiar"
    case macSpacious = "Mac Spacious"
}

/// Dialogs presented as sheets on the document window.
enum DialogKind: Identifiable, Equatable {
    case newSchedule(ScheduleKind), scheduleProperties(ElementID), newSheet, placeView(ElementID), visibilityGraphics(ElementID), viewRange(ElementID)
    case typeProperties(ElementID), projectInfo, projectUnits, projectParameters, materials, lineStyles, phases, designOptions, revisions, location
    case exportPDF, exportIFC, exportDXF, importCAD(URL, isLink: Bool, isDWG: Bool), importIFC(URL), manageLinks, modelHealth, rename(ElementID)
    case newFamily, keyboardShortcuts, csvImport(ElementID, URL), selectByCategory, filterSelection, pasteToLevels, purge, linkPDF(URL), linkImage(URL)
    case dwgUnavailable, report(String, String), newView(ViewKind), snaps
    case exportDWG // DWG
    case overrideGraphics(view: ElementID, elements: [ElementID]) // WP6a
    case tagAll(ElementID), colorSchemes(ElementID, placeLegend: Bool), newAreaPlan
    case importRevit(URL)
    case site(SiteDialog) // W2-DWG
    case componentLibrary([Category]) // W2-LIB: library browser, optionally limited to categories
    case findReplace(ElementID), checkSpelling(ElementID) // W2-ANNOT
    case schedulePropertiesTab(ElementID, tab: Int, fieldID: String?) // BL-SCHED: Schedule Properties opened on a tab
    case sheetTitle(ElementID) // BL-BROWSER: sheet number and name
    case filters(ElementID?), viewTemplates(ElementID?, ViewTemplatesMode, select: ElementID? = nil), objectStyles, warnings, selectByID, additionalSettings(AdditionalSettingsTab), userInterface // BL-VG
    case f34(F34Dialog) // F34: Structural Settings, Rebar Cover Settings
    case f2(F2Dialog) // F2: Work Plane, Connect Levels (Dialogs/F2Dialogs.swift)
    case f67(F67Dialog) // F67: Insert tab dialogs
    case f11(F11Dialog) // F11: Manage, schedule and export dialogs (Dialogs/F11ManageDialogs.swift)
    case f5(F5Dialog) // F5: Model In-place (Dialogs/F5MassingDialogs.swift)
    case f810(F810Dialog) // F810: Title Block, Guide Grid, Rendering, Render Gallery
    case fm3(FM3Dialog) // FM3: Family Types, Family Category and Parameters, Flex, Load into Project (FurnitureDialogs.swift)
    case fm6(FM6Dialog) // FM6: Joint Rules (FurnitureJointRulesDialog.swift)
    case fm7(FM7Dialog) // FM7: Stock Sheets, Hardware Catalog, CNC Export, Check Parts (FurnitureFabricationDialogs.swift)
    case fm8(FM8Dialog) // FM8: Load Furniture, Save as Furniture Template (Dialogs/FM8Dialogs.swift)
    case fmg2(FMG2Dialog) // FMG2: Explode Parts (Dialogs/FurnitureExplodeDialog.swift)
    var id: String { String(describing: self) }
}

/// A background task shown in the status area with progress and cancellation.
@MainActor
@Observable
final class BackgroundTaskItem: Identifiable {
    let id = UUID()
    let title: String
    var progress: Double = 0
    var detail: String = ""
    var isCancelled = false
    init(title: String) { self.title = title }
}

/// Per-document UI state: open views, active tool, panels and background work.
@MainActor
@Observable
final class DocumentState {
    let session: DocumentSession
    @ObservationIgnored weak var document: ArcusDocument?
    @ObservationIgnored weak var window: NSWindow?

    var openViews: [ElementID] = []
    /// F810: View ▸ Windows ▸ Tile Views shows the open views side by side (Tab Views returns to tabs).
    var tileViews = false
    var activeViewID: ElementID? { didSet { if activeViewID != oldValue { viewChanged(from: oldValue) } } }
    var viewHistory: [ElementID] = []
    var toolRevision = 0
    var currentTypes: [Category: ElementID] = [:]
    var message: String?
    var messageIsError = false
    var hoverDescription = ""
    var cursorPoint: Vec2?
    var snapDescription: String?
    var presented: DialogKind?
    var thinLines = false
    var backgroundTasks: [BackgroundTaskItem] = []
    var healthWarnings: [ModelWarning] = []
    var showNavigator = true
    var showProperties = true
    var workspace: Workspace = Workspace(rawValue: UserDefaults.standard.string(forKey: "workspace") ?? "") ?? .bimFamiliar {
        didSet { UserDefaults.standard.set(workspace.rawValue, forKey: "workspace"); onWorkspaceChange?() }
    }
    var commandSearchVisible = false
    var recentCommands: [CommandID] = []
    var numericEntry: String?
    var navigatorFilter = ""
    var inspectorFocusRequest = 0
    let palette = PaletteState() // BL-PROPS
    /// Floating dock widths, collapsed flags and the insets the canvas keeps from them (FloatingDock.swift). // W4-SHELL
    let docks = DockLayoutState()
    /// Ribbon minimized to tabs (panels hidden); persisted per user.
    var ribbonCollapsed = UserDefaults.standard.bool(forKey: "ribbon.collapsed") {
        didSet { UserDefaults.standard.set(ribbonCollapsed, forKey: "ribbon.collapsed"); onRibbonLayoutChange?() }
    }
    @ObservationIgnored var onRibbonLayoutChange: (() -> Void)?
    /// The ribbon tab picked by the user (the tabs live in the floating tab pill, the panels on the strip under it). // W4-WIRE
    /// Every project opens on Architecture, every Furniture document on Create (FM3: see `openInitialView`).
    var ribbonTab: RibbonTab = .architecture
    /// FM3: Architectural project or Furniture document; the ribbon tabs, browser and menus follow it.
    var mode: DocumentKind { model.projectInfo.kind }
    /// The contextual "Modify | …" tab is showing instead of `ribbonTab`.
    var ribbonShowsContextual = true
    /// Top-row width left for the ribbon tabs beside the controls pill (set by the window shell as it lays out). // W4-WIRE
    var ribbonTabsWidth: CGFloat = .infinity
    /// The active view's name as BIM users read it ("Floor Plan: Level 1"); shown under the project name.
    var viewSubtitle = ""
    /// The project's name and whether it has unsaved changes (the sidebar header shows them; the window title is hidden).
    var documentName = "Untitled"
    var documentEdited = false
    func refreshDocumentInfo() {
        let name = document?.displayName ?? "Untitled"
        let edited = document?.isDocumentEdited ?? false
        if name != documentName { documentName = name }
        if edited != documentEdited { documentEdited = edited }
    }

    /// Object snaps, angle increment and Snaps Off; per user, shared by every view.
    var snapSettings: SnapSettings = DocumentState.loadSnapSettings() {
        didSet {
            for c in toolContexts.values { c.snapSettings = snapSettings }
            if let data = try? JSONEncoder().encode(snapSettings) { UserDefaults.standard.set(data, forKey: "snapSettings") }
            UserDefaults.standard.set(snapSettings.pixelRadius, forKey: "snapRadius")
        }
    }
    static func loadSnapSettings() -> SnapSettings {
        var s = UserDefaults.standard.data(forKey: "snapSettings").flatMap { try? JSONDecoder().decode(SnapSettings.self, from: $0) } ?? SnapSettings()
        let r = UserDefaults.standard.double(forKey: "snapRadius")
        if r >= 4 { s.pixelRadius = r }
        return s
    }
    /// Re-reads the snap distance after it changes in Settings.
    func reloadSnapRadius() {
        let r = UserDefaults.standard.double(forKey: "snapRadius")
        if r >= 4, r != snapSettings.pixelRadius { snapSettings.pixelRadius = r }
    }

    @ObservationIgnored var activeTool: (any InteractiveTool)? {
        didSet { for c in toolContexts.values { c.snapExclusions = []; c.snapOverride = nil; c.acquiredLines = [] } }
    }
    @ObservationIgnored var toolContexts: [ElementID: ToolContext] = [:]
    /// Typed-alias buffer, Modify pre-selection and undo history (KeyboardSession.swift). // BL-KEYS
    @ObservationIgnored let keys = KeyboardSession()
    @ObservationIgnored var onWorkspaceChange: (() -> Void)?
    @ObservationIgnored let graphics: GraphicsStore
    @ObservationIgnored var canvases: [ElementID: NSView] = [:]
    /// The app-wide clipboard (shared by every open project, so elements can be copied between projects).
    var clipboard: ClipboardPayload? { ClipboardStore.shared.payload }
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var healthTask: Task<Void, Never>?

    init(session: DocumentSession) {
        self.session = session
        self.graphics = GraphicsStore()
        graphics.state = self
        session.onChange { [weak self] change in self?.modelChanged(change) }
        openInitialView()
        LevelRenamePrompt.install(on: self) // WP6a: offer to rename a level's views
        SaveReminder.install(on: self) // F11: "Project Not Saved Recently"
    }

    var model: BIMModel { session.model }

    /// Called when the document closes: cancels background work and drops the model, undo history, tools and display
    /// lists. Framework caches (e.g. a recently presented SwiftUI sheet) may keep this object itself alive briefly;
    /// after tear-down it no longer holds any project data.
    private(set) var isTornDown = false
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        messageTask?.cancel(); healthTask?.cancel()
        for t in backgroundTasks { t.isCancelled = true }
        backgroundTasks = []
        activeTool = nil
        toolContexts.removeAll()
        canvases.removeAll()
        for id in openViews { graphics.drop(id) }
        presented = nil
        openViews = []
        viewHistory = []
        healthWarnings = []
        onWorkspaceChange = nil
        session.discard()
    }
    var activeView: Element? { model[activeViewID] }

    // MARK: Views

    func openInitialView() {
        let m = model
        ribbonTab = RibbonTab.defaultTab(for: m.projectInfo.kind) // FM3
        if let start = StartingView.view(m) { open(start.id); return } // F11: Manage ▸ Starting View
        if let plan = m.views.first(where: { $0.view?.kind == .floorPlan && m[$0.levelID]?.level?.elevation == m.levels.first?.level?.elevation })
            ?? m.views.first(where: { $0.view?.kind == .floorPlan }) ?? m.views.first {
            open(plan.id)
        }
    }

    func open(_ id: ElementID) {
        guard let e = model[id], e.view != nil || e.sheet != nil || e.schedule != nil else { return }
        if !openViews.contains(id) { openViews.append(id) }
        activeViewID = id
    }

    func close(_ id: ElementID) {
        openViews.removeAll { $0 == id }
        canvases.removeValue(forKey: id)
        toolContexts.removeValue(forKey: id)
        graphics.drop(id)
        if activeViewID == id { activeViewID = viewHistory.last { openViews.contains($0) } ?? openViews.last }
    }

    func closeInactiveViews() {
        for v in openViews where v != activeViewID { close(v) }
    }

    func previousView() {
        while let last = viewHistory.popLast() {
            if model[last] != nil { open(last); viewHistory.removeLast(); return }
        }
    }

    private func viewChanged(from old: ElementID?) {
        if let old { viewHistory.append(old); if viewHistory.count > 50 { viewHistory.removeFirst() } }
        cancelTool()
        session.selection.preselection = nil
        paletteViewActivated() // BL-PROPS
        updateWindowSubtitle()
    }

    /// The window subtitle names the active view the way BIM users read it: "Floor Plan: Level 1", "Sheet: A101 – Plans".
    func updateWindowSubtitle() {
        var text: String
        if let e = activeView { text = ViewTitles.qualified(e) } else { text = "" } // BL-BROWSER: same titles as the view tabs
        if let mode = FurnitureShell.modeTitle(model) { text = text.isEmpty ? mode : "\(mode) — \(text)" } // FM3: "Furniture · Casework — Floor Plan: Ref. Level"
        window?.subtitle = text
        if viewSubtitle != text { viewSubtitle = text }
    }

    func toolContext(for viewID: ElementID) -> ToolContext {
        if let c = toolContexts[viewID] { return c }
        let c = ToolContext(session: session, viewID: viewID)
        c.currentTypes = currentTypes
        c.snapSettings = snapSettings
        c.showMessage = { [weak self] m in self?.show(m) }
        c.requestText = { [weak self] prompt, initial, completion in self?.requestText(prompt: prompt, initial: initial, completion: completion) }
        c.requestConfirmation = { [weak self] message, confirm, completion in self?.requestConfirmation(message: message, confirmTitle: confirm, completion: completion) }
        c.requestTextInPlace = { [weak self] p, initial, completion in self?.editTextInPlace(viewID: viewID, at: p, initial: initial, completion: completion) } // W2-ANNOT
        c.toolFinished = { [weak self] in self?.cancelTool() }
        c.presentError = { [weak self] message, detail, actions, done in self?.presentToolError(message: message, detail: detail, actions: actions, completion: done) } // BL-CANVAS
        toolContexts[viewID] = c
        return c
    }

    // MARK: Tools

    func setTool(_ tool: (any InteractiveTool)?) {
        activeTool = tool
        toolRevision += 1
        numericEntry = nil
        paletteToolChanged() // BL-PROPS
        (canvases[activeViewID ?? ElementID(0)] as? Canvas2DView)?.toolChanged()
        active3DTools?.toolChanged() // W2-3D
    }

    func cancelTool() {
        if activeTool != nil { setTool(nil) }
    }

    /// Escape semantics: first Escape cancels the current step, second returns to Modify, then the selection clears.
    /// A partly typed alias or a Modify command waiting for its selection is cancelled first; sketch mode stays. // BL-KEYS
    func escape() {
        if keysEscape() { return } // BL-KEYS
        switch ToolLifecycle.escape(tool: activeTool, selection: session.selection) { // BL-KEYS
        case .exitedTool: setTool(nil)
        case .cancelledStep: toolRevision += 1
        case .clearedSelection, .none: break
        }
    }

    func toolChangedState() { toolRevision += 1 }

    var prompt: String {
        if let p = keys.statusOverride { return p } // BL-KEYS: alias echo, pre-selection prompt
        if let t = activeTool { return t.prompt }
        if !session.selection.isEmpty { return session.selection.statusDescription(model) }
        return hoverDescription.isEmpty ? "Ready. Click to select; drag to select by window." : hoverDescription
    }

    // MARK: Messages

    func show(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
        // Toasts are visual; announce them so VoiceOver users hear results and errors too.
        if let w = window {
            NSAccessibility.post(element: w, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: (error ? NSAccessibilityPriorityLevel.high : .medium).rawValue])
        }
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 7 : 4))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    func requestText(prompt: String, initial: String, completion: @escaping (String?) -> Void) {
        guard let window else { completion(nil); return }
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        field.string = initial
        field.isRichText = false
        field.font = .systemFont(ofSize: 13)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        scroll.documentView = field
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { r in completion(r == .alertFirstButtonReturn ? field.string : nil) }
    }

    // MARK: Model changes

    private func modelChanged(_ change: ModelChange) {
        graphics.invalidate(change)
        if let e = session.lastError { show(e.message, error: true); session.clearError() }
        else if let w = session.lastWarnings.first(where: { $0.severity >= .warning }) { show(w.message) }
        // Close tabs of deleted views.
        for v in openViews where model[v] == nil { close(v) }
        scheduleHealthCheck()
    }

    func scheduleHealthCheck() {
        healthTask?.cancel()
        let snapshot = model
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { ModelHealth.check(snapshot) }.value
            guard !Task.isCancelled else { return }
            self?.healthWarnings = result
        }
    }

    // MARK: Background tasks

    func runBackground<T: Sendable>(_ title: String, work: @escaping @Sendable (_ progress: @escaping @Sendable (Double, String) -> Void, _ isCancelled: @escaping @Sendable () -> Bool) async throws -> T,
                                    completion: @escaping (Result<T, any Error>) -> Void) {
        let item = BackgroundTaskItem(title: title)
        backgroundTasks.append(item)
        let box = CancelBox()
        Task { [weak self] in
            let result: Result<T, any Error>
            do {
                let v = try await Task.detached(priority: .userInitiated) {
                    try await work({ p, d in Task { @MainActor in item.progress = p; item.detail = d } }, { box.cancelled })
                }.value
                result = .success(v)
            } catch {
                result = .failure(error)
            }
            self?.backgroundTasks.removeAll { $0.id == item.id }
            completion(result)
        }
        item.cancelHandler = { box.cancelled = true }
    }
}

nonisolated final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }
}

extension BackgroundTaskItem {
    private static var handlers: [UUID: () -> Void] = [:]
    var cancelHandler: (() -> Void)? {
        get { BackgroundTaskItem.handlers[id] }
        set { BackgroundTaskItem.handlers[id] = newValue }
    }
    func cancel() { isCancelled = true; cancelHandler?() }
}
