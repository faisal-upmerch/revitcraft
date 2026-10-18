import AppKit
import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// W2-CAM: 3D navigation and camera commands, the View ▸ 3D Navigation menu and the navigation bar's 3D menu.

extension CommandRouter {
    static let cameraCommands: [CommandID] = [.view3DFront, .view3DBack, .view3DLeft, .view3DRight, .view3DTop, .view3DBottom,
                                              .view3DToggleProjection, .view3DFrameSelected, .view3DFly,
                                              .viewThroughCamera, .alignCameraToView, .lockCameraToView, .createCameraFromView]

    /// The 3D viewport host of the active view.
    var active3DHost: Viewport3DHost? { state.activeViewID.flatMap { state.canvases[$0] as? Viewport3DHost } }

    func cameraDisabledReason(_ id: CommandID) -> String? {
        guard CommandRouter.cameraCommands.contains(id) else { return nil }
        return active3DHost == nil ? "Available in 3D views." : nil
    }

    func performCameraCommand(_ id: CommandID) {
        guard let host = active3DHost else { state.show("\(CommandCatalog.info(id).title): Available in 3D views."); return }
        let v = host.viewport
        switch id {
        case .view3DFront: v.orient(to: .front, animated: true)
        case .view3DBack: v.orient(to: .back, animated: true)
        case .view3DLeft: v.orient(to: .left, animated: true)
        case .view3DRight: v.orient(to: .right, animated: true)
        case .view3DTop: v.orient(to: .top, animated: true)
        case .view3DBottom: v.orient(to: .bottom, animated: true)
        case .view3DToggleProjection: v.toggleProjection()
        case .view3DFrameSelected: v.frameSelection()
        case .view3DFly: v.window?.makeFirstResponder(v); v.beginFly()
        case .viewThroughCamera: host.toggleViewThroughCamera()
        case .alignCameraToView: host.alignCameraToView()
        case .lockCameraToView: host.toggleCameraLock()
        case .createCameraFromView: host.createCameraFromView()
        default: break
        }
    }
}

/// Menu items for 3D navigation (View menu and the canvas navigation bar).
@MainActor
final class CameraMenus: NSObject, NSMenuItemValidation {
    static let shared = CameraMenus()

    /// Adds "3D Navigation" to the View menu. Hooked from `MainMenuBuilder.build()`.
    static func addNavigationItems(to menu: NSMenu?) {
        guard let menu else { return }
        let nav = NSMenu(title: "3D Navigation")
        for i in MainMenuBuilder.commands([.view3DFront, .view3DBack, .view3DLeft, .view3DRight, .view3DTop, .view3DBottom, nil,
                                           .view3DToggleProjection, .view3DFrameSelected, .zoomExtents, nil, .view3DFly, nil,
                                           .viewThroughCamera, .alignCameraToView, .lockCameraToView, .createCameraFromView, .cameraView]) {
            nav.addItem(i)
        }
        nav.addItem(.separator())
        let orbitSel = NSMenuItem(title: "Orbit Around Selection", action: #selector(toggleOrbitAroundSelection(_:)), keyEquivalent: "")
        orbitSel.target = shared
        nav.addItem(orbitSel)
        let style = NSMenuItem(title: "Middle Button", action: nil, keyEquivalent: "")
        let styles = NSMenu(title: "Middle Button")
        for s in Viewport3DNavigationStyle.allCases {
            let i = NSMenuItem(title: s.title, action: #selector(setNavigationStyle(_:)), keyEquivalent: "")
            i.target = shared
            i.representedObject = s.rawValue
            styles.addItem(i)
        }
        style.submenu = styles
        nav.addItem(style)
        let item = NSMenuItem(title: "3D Navigation", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "rotate.3d", accessibilityDescription: nil)
        item.submenu = nav
        menu.addItem(.separator())
        menu.addItem(item)
    }

    @objc func toggleOrbitAroundSelection(_ sender: Any?) { Viewport3DNavigationSettings.orbitAroundSelection.toggle() }

    @objc func setNavigationStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let s = Viewport3DNavigationStyle(rawValue: raw) { Viewport3DNavigationSettings.style = s }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleOrbitAroundSelection(_:)) { item.state = Viewport3DNavigationSettings.orbitAroundSelection ? .on : .off }
        if item.action == #selector(setNavigationStyle(_:)) {
            item.state = (item.representedObject as? String) == Viewport3DNavigationSettings.style.rawValue ? .on : .off
        }
        return true
    }
}

/// The navigation bar's 3D menu: view presets, projection, framing, fly mode and cameras.
struct Camera3DNavigationMenu: View {
    let state: DocumentState
    @State private var styleRevision = 0

    var body: some View {
        let _ = state.session.changeCounter
        let _ = styleRevision
        let cams = CameraSessionState.of(state)
        let host = state.activeViewID.flatMap { state.canvases[$0] as? Viewport3DHost }
        let locked = state.activeViewID.map { cams.isLocked($0, state.model) } ?? false
        Menu {
            Section("View") {
                ForEach([CommandID.view3DFront, .view3DBack, .view3DLeft, .view3DRight, .view3DTop, .view3DBottom], id: \.self) { item($0) }
            }
            Section {
                item(.view3DToggleProjection)
                item(.view3DFrameSelected)
                item(.zoomExtents)
                item(.view3DFly)
            }
            Section("Camera") {
                item(.viewThroughCamera)
                item(.alignCameraToView)
                Toggle(isOn: Binding(get: { locked }, set: { _ in CommandRouter(state: state).run(.lockCameraToView) })) {
                    Label("Lock Camera to View", systemImage: "lock")
                }
                item(.createCameraFromView)
                if !state.model.cameraViews.isEmpty {
                    Menu("Look Through") {
                        ForEach(state.model.cameraViews, id: \.id) { c in
                            Button(c.name + (cams.activeCamera(in: state.model) == c.id ? " (active)" : "")) { host?.lookThrough(c.id) }
                        }
                    }
                }
            }
            Section("Navigation") {
                Toggle("Orbit Around Selection", isOn: Binding(get: { Viewport3DNavigationSettings.orbitAroundSelection },
                                                               set: { Viewport3DNavigationSettings.orbitAroundSelection = $0; styleRevision += 1 }))
                Picker("Middle Button", selection: Binding(get: { Viewport3DNavigationSettings.style },
                                                           set: { Viewport3DNavigationSettings.style = $0; styleRevision += 1 })) {
                    ForEach(Viewport3DNavigationStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } label: {
            Image(systemName: "rotate.3d").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 26)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help("3D navigation: views, projection, fly mode and cameras")
        .accessibilityLabel("3D navigation")
    }

    private func item(_ id: CommandID) -> some View {
        let info = CommandCatalog.info(id)
        return Button(info.title + (info.shortcut.map { "  \($0)" } ?? ""), systemImage: info.symbol) { CommandRouter(state: state).run(id) }
    }
}
