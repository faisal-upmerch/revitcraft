import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication
import ArcusOutput

// F810: View ▸ Windows (Switch Windows, Tab Views, Tile Views, Canvas Theme) and View ▸ Presentation ▸ Export OBJ.

// MARK: - Canvas theme

/// The view canvas's theme (RevitCraft's light/black canvas, plus a dark one): Follow System uses the app's appearance.
nonisolated enum CanvasTheme: String, CaseIterable, Identifiable {
    case system = "Follow System", light = "Light", dark = "Dark", black = "Black"
    var id: String { rawValue }
    static let key = "canvas.theme"
    static var current: CanvasTheme { CanvasTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
    @MainActor static func set(_ t: CanvasTheme) {
        UserDefaults.standard.set(t.rawValue, forKey: key)
        CanvasSettings.changed()
    }
    /// The appearance canvases take (nil: the window's).
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .black: NSAppearance(named: .darkAqua)
        }
    }
    /// The black canvas colour of the Black theme (the dark canvas colour stays graphite otherwise).
    static let blackCanvas = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
}

extension CanvasContainerView {
    /// Applies the canvas theme to the canvas inside this container and follows later changes.
    func f810ObserveCanvasTheme() {
        NotificationCenter.default.removeObserver(self, name: .arcusCanvasSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(f810CanvasThemeChanged), name: .arcusCanvasSettingsChanged, object: nil)
        f810CanvasThemeChanged()
    }
    @objc func f810CanvasThemeChanged() {
        let a = CanvasTheme.current.appearance
        guard appearance?.name != a?.name else { return }
        appearance = a
        func redraw(_ v: NSView) { v.needsDisplay = true; v.subviews.forEach(redraw) }
        redraw(self)
    }
}

// MARK: - Menus

@MainActor
enum F810WindowMenus {
    /// Pops a menu up under the pointer in the document window.
    static func popUp(_ menu: NSMenu, _ state: DocumentState) {
        guard let w = state.window ?? NSApp.keyWindow, let content = w.contentView else { return }
        let p = content.convert(w.mouseLocationOutsideOfEventStream, from: nil)
        menu.popUp(positioning: nil, at: p, in: content)
    }

    /// Switch Windows: the open views, the active one checked.
    static func switchWindows(_ state: DocumentState) {
        let menu = NSMenu(title: "Switch Windows")
        for (i, id) in state.openViews.enumerated() {
            guard let e = state.model[id] else { continue }
            let item = MenuAction.item("\(i + 1) \(ViewTitles.qualified(e))") { state.activeViewID = id }
            item.state = id == state.activeViewID ? .on : .off
            menu.addItem(item)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No open views", action: nil, keyEquivalent: "") }
        popUp(menu, state)
    }

    /// Canvas Theme: Follow System, Light, Dark or Black.
    static func canvasTheme(_ state: DocumentState) {
        let menu = NSMenu(title: "Canvas Theme")
        for t in CanvasTheme.allCases {
            let item = MenuAction.item(t.rawValue) { CanvasTheme.set(t) }
            item.state = t == CanvasTheme.current ? .on : .off
            menu.addItem(item)
        }
        popUp(menu, state)
    }
}

/// A menu item running a closure.
final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func perform(_ sender: Any?) { run() }
    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.perform(_:)), keyEquivalent: "")
        item.target = a
        item.representedObject = a // keeps the target alive
        return item
    }
}

// MARK: - Tile Views

/// Tile Views: every open view in a grid of canvases, the active one outlined; a click in a tile activates it.
struct TiledCanvasView: View {
    @Bindable var state: DocumentState
    var leadingInset: Double, trailingInset: Double, topInset: Double, bottomInset: Double

    var body: some View {
        let views = state.openViews.filter { state.model[$0] != nil }
        let cols = max(1, Int(Double(views.count).squareRoot().rounded(.up)))
        let rows = max(1, (views.count + cols - 1) / cols)
        GeometryReader { geo in
            let gap: CGFloat = 6
            let w = (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            ZStack(alignment: .topLeading) {
                ForEach(Array(views.enumerated()), id: \.element) { i, v in
                    tile(v).frame(width: max(w, 10), height: max(h, 10))
                        .offset(x: CGFloat(i % cols) * (w + gap), y: CGFloat(i / cols) * (h + gap))
                }
            }
        }
        .padding(.leading, leadingInset).padding(.trailing, trailingInset).padding(.top, topInset).padding(.bottom, bottomInset)
        .onAppear { focusActive() }
        .onChange(of: state.activeViewID) { _, _ in focusActive() }
    }

    @ViewBuilder func tile(_ v: ElementID) -> some View {
        let active = v == state.activeViewID
        CanvasHost(state: state, viewID: v, onActivate: { if state.activeViewID != v { state.activeViewID = v } })
            .id(v)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(active ? Tokens.selectionColor : Color.secondary.opacity(0.35), lineWidth: active ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Text(state.model[v].map(ViewTitles.qualified) ?? "").font(.system(size: 10.5, weight: active ? .semibold : .regular))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule()).padding(6)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(state.model[v].map(ViewTitles.qualified) ?? "View")
    }

    /// The active tile's canvas takes the keyboard.
    func focusActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let id = state.activeViewID, let c = state.canvases[id] else { return }
            c.window?.makeFirstResponder((c as? Viewport3DHost)?.viewport ?? c)
        }
    }
}

extension CanvasContainerView {
    /// Tile Views: a mouse press anywhere in this container activates its view first.
    func f810SetActivation(_ onActivate: (() -> Void)?) {
        f810Activate = onActivate
        if let m = f810Monitor { NSEvent.removeMonitor(m); f810Monitor = nil }
        guard onActivate != nil else { return }
        f810Monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, let w = self.window, e.window === w else { return }
                let p = self.convert(e.locationInWindow, from: nil)
                if self.bounds.contains(p) { self.f810Activate?() }
            }
            return e
        }
    }
}

// MARK: - Export OBJ

@MainActor
struct OBJExportAction {
    let state: DocumentState

    func run() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "obj") ?? .data]
        panel.nameFieldStringValue = "\(state.documentName.isEmpty ? "Model" : state.documentName).obj"
        panel.message = "Exports the model's 3D geometry as OBJ, with its materials in an .mtl file beside it."
        let state = state
        let done: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, var url = panel.url else { return }
            if url.pathExtension.lowercased() != "obj" { url.appendPathExtension("obj") }
            do {
                let out = try OBJExporter.write(state.model, to: url)
                state.show("Exported \(url.lastPathComponent): \(out.elementCount) elements, \(out.triangleCount) triangles.")
            } catch {
                state.show("Export failed: \(error.localizedDescription)", error: true)
            }
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }
}

// MARK: - Walkthrough ribbon

extension RibbonContent {
    /// "Edit Walkthrough" while a walkthrough view is open with nothing selected, as in RevitCraft.
    @MainActor static func f810ContextualTitle(_ state: DocumentState) -> String? {
        state.activeTool == nil && state.session.selection.isEmpty && state.activeView?.view?.walkthrough != nil ? "Edit Walkthrough" : nil
    }

    /// Finish Walkthrough while the path is clicked; Previous/Next Frame, Play and Export in a walkthrough view.
    @MainActor static func f810ContextualPanels(_ state: DocumentState) -> [RibbonPanel] {
        if state.activeTool is WalkthroughTool { return [RibbonPanel(title: "Walkthrough", items: [.large(.finishWalkthrough)], tint: view)] }
        guard state.activeTool == nil, state.activeView?.view?.walkthrough != nil else { return [] }
        return [RibbonPanel(title: "Navigation", items: [.large(.walkthroughPreviousFrame), .large(.walkthroughNextFrame), .large(.walkthroughPlay)], tint: view),
                RibbonPanel(title: "Walkthrough", items: [.large(.walkthroughExport)], tint: view)]
    }
}
