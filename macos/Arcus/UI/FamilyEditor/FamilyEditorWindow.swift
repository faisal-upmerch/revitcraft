import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// W4-FAMED: one window per family being edited, with a persisted frame.
// FES: the window is built like the project window (`DocumentWindowController`): full-size content with a transparent,
// hidden title bar and no NSToolbar; one hosting view fills it with the canvas edge to edge and the floating shell over
// it (FamilyEditorShellView); the traffic lights move into the left dock.

@MainActor
final class FamilyEditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static var open: [FamilyEditorWindowController] = []
    let model: FamilyEditorModel
    private let container = NSView()
    private var host: NSHostingView<FamilyEditorShellView>?

    static func open(familyID: ElementID, state: DocumentState) {
        if let existing = open.first(where: { $0.model.familyID == familyID && $0.model.state === state }) { existing.window?.makeKeyAndOrderFront(nil); return }
        guard let fam = state.model[familyID]?.family else { return }
        present(FamilyEditorModel(family: fam, state: state, familyID: familyID))
    }
    static func open(new family: FamilyDefinition, state: DocumentState) {
        present(FamilyEditorModel(family: family, state: state, familyID: nil))
    }
    @discardableResult
    private static func present(_ m: FamilyEditorModel) -> FamilyEditorWindowController {
        let wc = FamilyEditorWindowController(model: m)
        open.append(wc)
        wc.showWindow(nil)
        return wc
    }

    init(model: FamilyEditorModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.minSize = FamilyEditorChrome.minimumSize
        w.titlebarAppearsTransparent = true // the canvas shows through the title bar area
        w.titleVisibility = .hidden // the family name and view are shown at the top of the left dock
        w.tabbingMode = .disallowed
        super.init(window: w)
        let vc = NSViewController()
        container.wantsLayer = true
        vc.view = container
        w.contentViewController = vc
        let content = NSHostingView(rootView: FamilyEditorShellView(model: model))
        content.sizingOptions = []
        content.safeAreaRegions = [] // the shell lays itself out from the window's top edge
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        host = content
        w.setFrameAutosaveName("ArcusFamilyEditor")
        let min = FamilyEditorChrome.minimumSize
        if w.frame.width < min.width || w.frame.height < min.height { w.setContentSize(NSSize(width: 1440, height: 900)); w.center() }
        w.delegate = self
        model.chrome.windowController = self
        rememberTrafficLights()
        updateTitle()
        model.onRename = { [weak self] _ in self?.updateTitle() }
        model.onClose = { [weak self] in self?.close() } // F1415: Load into Project and Close
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The title is hidden but names the window in the Window menu and Mission Control.
    func updateTitle() {
        window?.title = "Family Editor – \(model.family.name)"
        window?.subtitle = "\(model.family.template.rawValue) family" + (model.familyID == nil ? " · not loaded" : "")
    }

    func windowWillClose(_ notification: Notification) {
        FamilyEditorWindowController.open.removeAll { $0 === self }
        window?.makeFirstResponder(nil)
        trafficLightsHosts.removeAllObjects(); placeTrafficLights() // the buttons return to the title bar before the host goes
        host?.removeFromSuperview()
        host = nil
    }
    /// Edit ▸ Undo/Redo and ⌘Z in the window use the family's own undo stack.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undo }
    func windowDidResize(_ notification: Notification) { placeTrafficLights() }
    func windowDidUpdate(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights() }
    func windowDidEnterFullScreen(_ notification: Notification) { placeTrafficLights() }

    // MARK: Docks

    /// Sidebar button, View ▸ Show/Hide Sidebar (⌥⌘S), Window ▸ Project Browser (⌥⌘1): the left dock.
    @objc func toggleSidebar(_ sender: Any?) { model.chrome.toggleBrowser() }
    /// Controls-pill inspector button, Window ▸ Properties (⌥⌘2): the right dock.
    @objc func toggleInspector(_ sender: Any?) { model.chrome.toggleProperties() }

    // MARK: Menu commands

    /// Menu commands while the editor is key: the dock toggles and the Family Editor's own commands run here; app
    /// commands (Home, Settings…) go on to the app delegate.
    @objc func performArcusCommand(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let id = CommandID(rawValue: raw) else { return }
        switch id {
        case .toggleNavigator: toggleSidebar(sender)
        case .toggleProperties: toggleInspector(sender)
        default:
            if CommandRouter.f1415Commands.contains(id) { model.perform(id) } else { AppDelegate.shared?.performArcusCommand(sender) }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleSidebar(_:)) || item.action == #selector(AppDelegate.toggleDocumentSidebar(_:)) {
            item.title = model.chrome.browserShown ? "Hide Sidebar" : "Show Sidebar"
            return true
        }
        guard item.action == #selector(performArcusCommand(_:)), let raw = item.representedObject as? String, let id = CommandID(rawValue: raw) else { return true }
        switch id {
        case .toggleNavigator: item.state = model.chrome.browserShown ? .on : .off; return true
        case .toggleProperties: item.state = model.chrome.propertiesShown ? .on : .off; return true
        default:
            if CommandRouter.f1415Commands.contains(id) {
                let reason = model.disabledReason(id)
                item.toolTip = reason
                return reason == nil
            }
            return AppDelegate.shared?.validateMenuItem(item) ?? false
        }
    }

    // MARK: Traffic lights (as DocumentWindowController)

    /// The views (the dock's top row, the collapsed strip) that can hold the standard window buttons.
    private let trafficLightsHosts = NSHashTable<TrafficLightsView>.weakObjects()
    private var trafficLightsHome: (superview: NSView, frames: [NSRect])?
    private static let trafficLightTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var trafficLights: [NSButton] { Self.trafficLightTypes.compactMap { window?.standardWindowButton($0) } }

    var trafficLightsHost: TrafficLightsView? {
        let live = trafficLightsHosts.allObjects.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
        return live.last ?? trafficLightsHosts.allObjects.last
    }
    private func rememberTrafficLights() {
        let buttons = trafficLights
        guard let sv = buttons.first?.superview else { return }
        trafficLightsHome = (sv, buttons.map(\.frame))
    }
    func registerTrafficLightsHost(_ host: TrafficLightsView) {
        if !trafficLightsHosts.contains(host) { trafficLightsHosts.add(host) }
        placeTrafficLights()
    }
    func unregisterTrafficLightsHost(_ host: TrafficLightsView) {
        trafficLightsHosts.remove(host)
        placeTrafficLights()
    }
    /// Moves the buttons into the host (or back to the title bar) at their slots; a no-op when nothing moved.
    func placeTrafficLights() {
        let buttons = trafficLights
        guard !buttons.isEmpty else { return }
        if let host = trafficLightsHost {
            for (i, b) in buttons.enumerated() {
                if b.superview !== host { host.addSubview(b) }
                let origin = NSPoint(x: (CGFloat(i) * TrafficLightsView.spacing).rounded(), y: ((host.bounds.height - b.frame.height) / 2).rounded())
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
}

/// Places the traffic lights in the Family Editor's SwiftUI layout (the dock's top row or the collapsed strip).
struct FamilyTrafficLightsHost: NSViewRepresentable {
    let chrome: FamilyEditorChrome
    func makeNSView(context: Context) -> TrafficLightsView {
        let v = TrafficLightsView(frame: .zero)
        v.onLayout = { [weak v, weak chrome] in
            guard let v, let wc = chrome?.windowController ?? v.window?.windowController as? FamilyEditorWindowController else { return }
            wc.registerTrafficLightsHost(v)
        }
        return v
    }
    func updateNSView(_ v: TrafficLightsView, context: Context) { chrome.windowController?.registerTrafficLightsHost(v) }
    static func dismantleNSView(_ v: TrafficLightsView, coordinator: ()) {
        (v.window?.windowController as? FamilyEditorWindowController)?.unregisterTrafficLightsHost(v)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrafficLightsView, context: Context) -> CGSize? { nsView.intrinsicContentSize }
}
