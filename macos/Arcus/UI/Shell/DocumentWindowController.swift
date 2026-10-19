import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

/// Main project window: the canvas fills the whole window edge to edge (under the transparent title bar too) and
/// everything else floats over it as Liquid Glass — the left sidebar (traffic lights, project header, Properties,
/// Project Browser), the ribbon tab pill and the controls pill in the top row, the ribbon strip, the Options pill,
/// the view-tab pills, the bottom pill and, in Mac Spacious, the right inspector (FloatingDock.swift,
/// ShellChrome.swift, ShellLayout in the Application layer). There is no NSToolbar. // W4-SHELL, W4-WIRE
final class DocumentWindowController: NSWindowController, NSMenuItemValidation, NSWindowDelegate {
    let state: DocumentState
    private let container = NSView()
    private var contentHost: NSHostingView<ContentAreaView>!

    init(document: ArcusDocument) {
        state = document.state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 980, height: 640)
        window.titlebarAppearsTransparent = true // W4-WIRE: the canvas shows through the title bar area
        // The project name and active view are shown at the top of the sidebar, which also holds the traffic lights.
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("ArcusProjectWindow")
        super.init(window: window)
        window.delegate = self
        state.window = window
        buildLayout()
        rememberTrafficLights()
        _ = state.undoHistory // start recording now, so the undo/redo history menus list every step
        state.onWorkspaceChange = { [weak self] in self?.applyWorkspace() }
        applyWorkspace()
        updateRibbonTabsWidth()
        state.updateWindowSubtitle()
        state.refreshDocumentInfo()
        if window.frame.width < 1000 { window.center() }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// One hosting view fills the window: the canvas, the docks and the floating shell are all laid out inside it.
    private func buildLayout() {
        guard let window else { return }
        container.wantsLayer = true
        let vc = NSViewController()
        vc.view = container
        window.contentViewController = vc
        let content = NSHostingView(rootView: ContentAreaView(state: state))
        content.sizingOptions = []
        content.safeAreaRegions = [] // the shell lays itself out from the window's top edge
        content.translatesAutoresizingMaskIntoConstraints = false
        contentHost = content
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Tells the ribbon tabs how much of the top row they have: the content span between the docks less the controls
    /// pill. The content view refines this from its measured layout; this is the estimate before the first layout.
    @objc func updateRibbonTabsWidth() {
        guard let window else { return }
        var r = ShellRequest(region: DockRegion(width: window.frame.width, height: window.frame.height))
        r.leadingInset = state.docks.leadingInset; r.trailingInset = state.docks.trailingInset
        r.sidebarCollapsed = !DockVisibility(state).leading
        r.controlsWidth = state.docks.controlsWidth > 0 ? state.docks.controlsWidth : nil
        let shell = ShellLayout.layout(r, metrics: .arcus)
        let available = ShellLayout.tabsWidth(contentWidth: shell.contentWidth, controlsWidth: shell.controls.width, metrics: .arcus)
        if abs(available - state.ribbonTabsWidth) > 1 { state.ribbonTabsWidth = available }
    }
    func windowDidResize(_ notification: Notification) { updateRibbonTabsWidth(); placeTrafficLights() }

    /// The docks observe the document state directly; this only nudges them for changes they can't observe
    /// (a panel detached to its own window).
    func applyWorkspace() {
        state.docks.revision += 1
    }

    /// Sidebar button, View ▸ Show/Hide Sidebar (⌥⌘S): collapses the left dock, or shows it (with its panels, if
    /// they were all hidden).
    @objc func toggleSidebar(_ sender: Any?) {
        if DockVisibility(state).leading {
            state.docks.setCollapsed(true, .leading)
        } else {
            state.docks.setCollapsed(false, .leading)
            if !state.showNavigator && !(state.workspace == .bimFamiliar && state.showProperties) { state.showNavigator = true }
        }
        state.onWorkspaceChange?()
    }
    /// Controls-pill inspector button: in Mac Spacious collapses or shows the right inspector; in BIM Familiar shows
    /// or hides Properties (which lives in the left dock there).
    @objc func toggleInspector(_ sender: Any?) {
        if state.workspace == .macSpacious {
            let visible = DockVisibility(state).trailing
            state.docks.setCollapsed(visible, .trailing)
            if !visible && !state.showProperties { state.showProperties = true }
        } else {
            state.showProperties.toggle()
        }
        state.onWorkspaceChange?()
    }

    // MARK: Traffic lights (W4-WIRE)

    /// The views (the sidebar's row, the collapsed strip) that can hold the standard window buttons; the one in the
    /// window wins. Hosts come and go with SwiftUI transitions, so this is a registry rather than one reference.
    private let trafficLightsHosts = NSHashTable<TrafficLightsView>.weakObjects()
    /// The host the buttons are in (or should be in) right now.
    var trafficLightsHost: TrafficLightsView? {
        let live = trafficLightsHosts.allObjects.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
        return live.last ?? trafficLightsHosts.allObjects.last
    }
    private var trafficLightsHome: (superview: NSView, frames: [NSRect])?
    private static let trafficLightTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var trafficLights: [NSButton] { Self.trafficLightTypes.compactMap { window?.standardWindowButton($0) } }

    /// Remembers where AppKit put the buttons, so they can go back when no host is showing.
    private func rememberTrafficLights() {
        let buttons = trafficLights
        guard let sv = buttons.first?.superview else { return }
        trafficLightsHome = (sv, buttons.map(\.frame))
    }
    func registerTrafficLightsHost(_ host: TrafficLightsView) {
        trafficLightsHosts.add(host)
        placeTrafficLights()
    }
    func unregisterTrafficLightsHost(_ host: TrafficLightsView) {
        trafficLightsHosts.remove(host)
        placeTrafficLights()
    }
    /// Moves the buttons into the host (or back to the title bar) and keeps them at their slots; AppKit re-tiles them
    /// on some window events, so this runs after every window update and is a no-op when nothing moved.
    func placeTrafficLights() {
        let buttons = trafficLights
        guard !buttons.isEmpty else { return }
        if let host = trafficLightsHost {
            for (i, b) in buttons.enumerated() {
                if b.superview !== host { host.addSubview(b) }
                let x = CGFloat(i) * TrafficLightsView.spacing
                let y = (host.bounds.height - b.frame.height) / 2
                let origin = NSPoint(x: x.rounded(), y: y.rounded())
                if b.frame.origin != origin { b.setFrameOrigin(origin) }
                if b.isHidden { b.isHidden = false }
            }
        } else if let home = trafficLightsHome {
            for (i, b) in buttons.enumerated() where b.superview !== home.superview {
                home.superview.addSubview(b)
                if i < home.frames.count { b.frame = home.frames[i] }
            }
        }
    }
    func windowDidUpdate(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights() }
    func windowDidEnterFullScreen(_ notification: Notification) { placeTrafficLights() }

    // MARK: Responder-chain commands

    @objc func performArcusCommand(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let id = CommandID(rawValue: raw) else { return }
        CommandRouter(state: state).run(id)
    }

    @objc func copy(_ sender: Any?) { Clipboard(state: state).copy() }
    @objc func cut(_ sender: Any?) { Clipboard(state: state).copy(); state.deleteSelection() } // BL-KEYS: reports pinned
    @objc func paste(_ sender: Any?) { Clipboard(state: state).paste(mode: .cursor) }
    @objc func delete(_ sender: Any?) { state.deleteSelection() } // BL-KEYS: reports pinned
    @objc override func selectAll(_ sender: Any?) { if TextInputFocus.redirectSelectAll(in: window) { return }; CommandRouter(state: state).run(.selectAll) } // BL-KEYS
    @objc override func cancelOperation(_ sender: Any?) { state.escape() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(performArcusCommand(_:)):
            guard let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return false }
            let reason = CommandRouter(state: state).disabledReason(id)
            item.toolTip = reason
            if id == .thinLines { item.state = state.thinLines ? .on : .off }
            if id == .showMass { item.state = state.session.showMass ? .on : .off } // F5
            if id == .workspaceBIMFamiliar { item.state = state.workspace == .bimFamiliar ? .on : .off }
            if id == .workspaceMacSpacious { item.state = state.workspace == .macSpacious ? .on : .off }
            if id == .toggleNavigator { item.state = state.showNavigator ? .on : .off }
            if id == .toggleProperties { item.state = state.showProperties ? .on : .off }
            return reason == nil
        case #selector(toggleSidebar(_:)), #selector(AppDelegate.toggleDocumentSidebar(_:)): item.title = DockVisibility(state).leading ? "Hide Sidebar" : "Show Sidebar"; return true // W4-SHELL
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)): return !state.session.selection.isEmpty
        case #selector(paste(_:)): return state.clipboard != nil
        default: return true
        }
    }

    // MARK: Window delegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { state.session.undoManager }
    func windowDidBecomeKey(_ notification: Notification) { AppDelegate.shared?.activeState = state }

    /// Tears the content down when the window closes. SwiftUI's focus bookkeeping can keep a reference to a closed
    /// window for a while; detaching the hosting views here guarantees that the document state and its model are
    /// released with the document regardless.
    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.makeFirstResponder(nil)
        trafficLightsHosts.removeAllObjects(); placeTrafficLights() // W4-WIRE: the buttons return to the title bar before the hosting view goes
        contentHost?.removeFromSuperview() // W4-SHELL
        window.contentViewController = nil
        window.contentView = NSView()
        state.canvases.removeAll()
    }
}

/// Left dock: Properties above the Project Browser (BIM Familiar) or the Navigator alone (Mac Spacious).
struct LeftDock: View {
    @Bindable var state: DocumentState
    var body: some View {
        let familiar = state.workspace == .bimFamiliar
        VStack(spacing: 0) {
            SidebarTopRow(state: state) // W4-WIRE: traffic lights and the hide-sidebar button
            ProjectHeader(state: state)
            Group {
            if familiar && state.showProperties && state.showNavigator && !PanelWindows.isDetached(.properties) && !PanelWindows.isDetached(.navigator) {
                PersistentVSplit(key: "leftDock.propertiesFraction", defaultFraction: 0.55, minTop: 220, minBottom: 180) { // BL-PROPS
                    PropertiesView(state: state)
                } bottom: {
                    NavigatorView(state: state)
                }
            } else if familiar && state.showProperties && !PanelWindows.isDetached(.properties) {
                PropertiesView(state: state)
            } else if state.showNavigator && !PanelWindows.isDetached(.navigator) {
                NavigatorView(state: state)
            } else {
                Color.clear // W4-SHELL: the floating dock hides itself when every panel is hidden or detached
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The project's name, its unsaved-changes state and the active view, at the top of the sidebar (the window's title
/// bar carries the ribbon tabs instead). The menu offers the document commands a title bar would.
struct ProjectHeader: View {
    @Bindable var state: DocumentState
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.33, green: 0.56, blue: 0.93), Color(red: 0.18, green: 0.38, blue: 0.78)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: state.mode == .furniture ? "chair.lounge.fill" : "building.columns.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(.white) // FM3
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(state.documentName).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if state.documentEdited {
                        Text("Edited").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                Text(state.viewSubtitle.isEmpty ? "No view open" : state.viewSubtitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Project Information…", systemImage: "info.circle") { state.presented = .projectInfo }
                Divider()
                Button("Duplicate", systemImage: "plus.square.on.square") { state.document?.duplicate(nil) }
                Button("Move To…", systemImage: "folder") { state.document?.move(nil) }
                Button("Show in Finder", systemImage: "magnifyingglass") {
                    if let url = state.document?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(state.document?.fileURL == nil)
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .help("Project")
            .accessibilityLabel("Project options")
        }
        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 10) // W4-SHELL: inset inside the floating panel; W4-WIRE: under the traffic-light row
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project \(state.documentName)\(state.documentEdited ? ", edited" : ""), \(state.viewSubtitle)")
    }
}

struct InspectorDock: View {
    @Bindable var state: DocumentState
    var body: some View {
        let properties = state.workspace == .macSpacious && state.showProperties && !PanelWindows.isDetached(.properties)
        if ComponentPanelModel.of(state).isShown { // COMP: the Components panel, under Properties in Mac Spacious
            if properties {
                PersistentVSplit(key: "inspectorDock.componentsFraction", defaultFraction: 0.45, minTop: 200, minBottom: 300) {
                    PropertiesView(state: state)
                } bottom: {
                    ComponentsPanel(state: state)
                }
            } else {
                ComponentsPanel(state: state).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if properties {
            PropertiesView(state: state).frame(maxWidth: .infinity, maxHeight: .infinity) // W4-SHELL
        } else {
            Color.clear
        }
    }
}

/// Detached panel windows (floating utility panels) that can be re-docked.
@MainActor
enum PanelWindows {
    private static var detached: [DockPanel: NSPanel] = [:]
    static func isDetached(_ p: DockPanel) -> Bool { detached[p] != nil }

    static func detach(_ p: DockPanel, state: DocumentState) {
        guard detached[p] == nil else { detached[p]?.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 560), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = p == .navigator ? "Project Browser" : "Properties"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.contentViewController = NSHostingController(rootView: DetachedPanelView(panel: p, state: state))
        panel.setFrameAutosaveName("ArcusPanel.\(p == .navigator ? "nav" : "props")")
        panel.center()
        detached[p] = panel
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated {
                detached.removeValue(forKey: p)
                state.onWorkspaceChange?()
                state.toolChangedState()
            }
        }
        panel.makeKeyAndOrderFront(nil)
        state.onWorkspaceChange?()
        state.toolChangedState()
    }
}

struct DetachedPanelView: View {
    let panel: DockPanel
    @Bindable var state: DocumentState
    var body: some View {
        if panel == .navigator { NavigatorView(state: state) } else { PropertiesView(state: state) }
    }
}
