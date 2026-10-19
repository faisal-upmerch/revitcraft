import AppKit
import SwiftUI
import ArcusDomain
import ArcusCalc
import ArcusApplication
import ArcusPersistence
import ArcusServices
import ArcusViewport3D

/// Application delegate: menus, hub, onboarding, recovery and app-level windows.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public static weak var shared: AppDelegate?
    weak var activeState: DocumentState?

    /// View ▸ Show/Hide Sidebar for the key document window (see MainMenu).
    @objc func toggleDocumentSidebar(_ sender: Any?) {
        if let fe = NSApp.keyWindow?.windowController as? FamilyEditorWindowController { fe.toggleSidebar(sender); return } // FES: the Family Editor's left dock
        (NSApp.keyWindow?.windowController as? DocumentWindowController ?? NSApp.mainWindow?.windowController as? DocumentWindowController)?.toggleSidebar(sender)
    }
    private var hubWindow: NSWindow?
    /// The Home window's state (QA selects cards through it). // HOME
    private(set) var hubModel: HomeModel?
    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?

    public override init() {
        super.init()
        AppDelegate.shared = self
        _ = ArcusDocumentController() // DWG: the first document controller made becomes the shared one (opens DWG/DXF too)
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
        AppDelegate.f1Launch() // F1: Model Text glyphs from CoreText
        Signpost.sink = { name, seconds in DiagnosticsLog.shared.recordTiming(name, seconds: seconds) }
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true, "selection.modifiers": SelectionModel.ModifierStyle.bim.rawValue])
        SelectionModel.modifierStyle = SelectionModel.ModifierStyle(rawValue: UserDefaults.standard.string(forKey: "selection.modifiers") ?? "") ?? .bim
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLog.shared.log("app", "Launched \(AppVersionInfo.current)")
        Viewport3DView.prewarmPipelines() // compile 3D viewport pipelines off the main thread
        MCPLiveService.shared.applySetting() // MCP: listen for Claude only when Settings ▸ Claude (MCP) is on

        let t0 = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            if !CommandLine.arguments.contains("--qa") { await checkRecovery() }
            if !UserDefaults.standard.bool(forKey: "onboardingComplete") && !CommandLine.arguments.contains("--skip-onboarding") {
                showOnboarding()
            } else if NSDocumentController.shared.documents.isEmpty && !CommandLine.arguments.contains("--no-hub") {
                showHub(tab: .recent)
            }
            DiagnosticsLog.shared.recordTiming("launch to hub", seconds: ProcessInfo.processInfo.systemUptime - t0)
            QAHarness.runIfRequested()
        }
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHub(tab: .recent) }
        return true
    }
    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationWillTerminate(_ notification: Notification) {
        // Clean termination: journals for documents closed normally were already ended by NSDocument.close().
        DiagnosticsLog.shared.log("app", "Terminating")
    }

    // MARK: Recovery

    @MainActor
    func checkRecovery() async {
        let items = await AppServices.shared.journal.pendingRecoveries()
        guard !items.isEmpty else { return }
        for item in items {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Arcus quit unexpectedly while “\(item.displayName)” had unsaved changes."
            var info = "\(item.changeCount) change(s), last at \(item.lastChange.formatted(date: .abbreviated, time: .shortened))."
            if let p = item.problem { info += "\n\n\(p)" }
            info += "\n\nRecover opens the project with your changes as a new unsaved window; your saved file is not touched until you save."
            alert.informativeText = info
            alert.addButton(withTitle: "Recover")
            alert.addButton(withTitle: "Discard Changes")
            alert.addButton(withTitle: "Decide Later")
            let r = alert.runModal()
            if r == .alertFirstButtonReturn {
                do {
                    let result = try await AppServices.shared.journal.recover(item)
                    openModel(result.model, name: result.displayName + " (Recovered)")
                    try? await AppServices.shared.journal.discard(item)
                } catch {
                    let e = NSAlert(error: error)
                    e.runModal()
                }
            } else if r == .alertSecondButtonReturn {
                try? await AppServices.shared.journal.discard(item)
            }
        }
    }

    // MARK: Documents

    @MainActor
    func openModel(_ model: BIMModel, name: String) {
        let doc = ArcusDocument(model: model, displayName: name)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        doc.updateChangeCount(.changeDone)
        hubWindow?.close()
    }

    @MainActor
    func newProject(template: ProjectTemplateKind, units: UnitsSettings, name: String) {
        let (model, _) = ProjectTemplates.make(template, units: units, projectName: name)
        let doc = ArcusDocument(model: model, displayName: nil)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        hubWindow?.close()
    }

    @MainActor
    func openSample() {
        let hub = hubWindow
        Task {
            let model = await Task.detached(priority: .userInitiated) { CourtyardHouse.make() }.value
            let doc = ArcusDocument(model: model, displayName: "Courtyard House")
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            hub?.close()
        }
    }

    // MARK: Windows

    enum HubTab { case recent, new, furniture }

    /// Shows Home: `.recent` with no card selected, `.new` with the Architectural card selected, `.furniture` with the
    /// Furniture card selected. // HOME
    @MainActor
    func showHub(tab: HubTab) {
        if let w = hubWindow, let m = hubModel {
            m.apply(tab)
            m.reload()
            w.makeKeyAndOrderFront(nil)
            return
        }
        let m = HomeModel(tab: tab)
        let w = Self.makeHubWindow(model: m)
        w.center()
        w.makeKeyAndOrderFront(nil)
        hubWindow = w
        hubModel = m
    }

    /// The Home window: 1040 × 660, resizable from 920 × 600 to 1600 × 1100, full-size content under a transparent
    /// title bar. QA finds it by its title, "Home". // HOME
    @MainActor
    static func makeHubWindow(model: HomeModel) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Home"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.isMovableByWindowBackground = true
        // An empty unified toolbar gives the taller title bar, so the traffic lights sit inside the floating sidebar.
        w.toolbar = NSToolbar(identifier: "ArcusHome")
        w.toolbarStyle = .unified
        let host = NSHostingController(rootView: ProjectHubView(model: model))
        host.sizingOptions = []
        w.contentViewController = host
        w.setContentSize(NSSize(width: 1040, height: 660))
        w.contentMinSize = NSSize(width: 920, height: 600)
        w.contentMaxSize = NSSize(width: 1600, height: 1100)
        return w
    }

    @MainActor
    func closeHub() { hubWindow?.close() }

    @MainActor
    func showOnboarding() {
        if let w = onboardingWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: OnboardingView(onFinish: { [weak w] in
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            w?.close()
        }))
        // Closing by any means (Finish or the close button) releases the window.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onboardingWindow = nil }
        }
        w.center()
        w.makeKeyAndOrderFront(nil)
        onboardingWindow = w
    }

    @MainActor
    func showAbout() {
        if let w = aboutWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.title = "About Arcus"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: AboutView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        aboutWindow = w
    }

    @MainActor
    func showSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Arcus Settings"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: SettingsView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
    }

    // MARK: App-level commands (no document)

    @objc func performArcusCommand(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let id = CommandID(rawValue: raw) else { return }
        MainActor.assumeIsolated {
            switch id {
            case .home: showHub(tab: .recent)
            case .newProject: showHub(tab: .new)
            case .newFurniture: showHub(tab: .furniture) // FM3
            case .openProject: NSDocumentController.shared.openDocument(nil)
            case .about: showAbout()
            case .preferences: showSettings()
            case .onboarding: showOnboarding()
            case .designWithClaude: ClaudeSetupWindow.show() // MCP
            case .keyboardShortcuts:
                if let s = activeState { s.presented = .keyboardShortcuts } else { showHub(tab: .recent) }
            default: break
            }
        }
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performArcusCommand(_:)), let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return true }
        return [.home, .newProject, .newFurniture, .openProject, .about, .preferences, .onboarding, .designWithClaude].contains(id) // MCP
    }
}
