import SwiftUI
import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

/// The window's content: the active canvas filling the whole window edge to edge (under the title bar too), with
/// the floating docks, the floating shell (ribbon tab pill, controls pill, ribbon strip, Options pill, view-tab
/// pills, bottom pill) and the canvas's own HUDs (navigation bar, toasts, command search) over it. // W4-WIRE
struct ContentAreaView: View {
    @Bindable var state: DocumentState
    @State private var controlsWidth: Double = 0

    var body: some View {
        let _ = state.toolRevision
        GeometryReader { geo in
            let _ = state.docks.revision
            let visibility = DockVisibility(state)
            let region = DockRegion(width: geo.size.width, height: geo.size.height)
            let layout = DockLayout.layout(region: region,
                                           leading: DockRequest(edge: .leading, width: state.docks.prefs.leadingWidth, visible: visibility.leading),
                                           trailing: DockRequest(edge: .trailing, width: state.docks.prefs.trailingWidth, visible: visibility.trailing),
                                           metrics: .arcus)
            let shell = ShellLayout.layout(shellRequest(region, layout, sidebarShown: visibility.leading), metrics: .arcus)
            let tabsWidth = ShellLayout.tabsWidth(contentWidth: shell.contentWidth, controlsWidth: shell.controls.width, metrics: .arcus)
            ZStack(alignment: .topLeading) {
                if state.tileViews, state.openViews.count > 1 { // F810: Tile Views
                    TiledCanvasView(state: state, leadingInset: shell.leadingInset, trailingInset: shell.trailingInset, topInset: shell.topInset, bottomInset: shell.bottomInset)
                } else if let v = state.activeViewID, state.model[v] != nil {
                    CanvasHost(state: state, viewID: v, leadingInset: shell.leadingInset, trailingInset: shell.trailingInset,
                               topInset: shell.topInset, bottomInset: shell.bottomInset).id(v)
                        .accessibilityElement(children: .contain)
                } else {
                    EmptyCanvasView(state: state)
                        .padding(.leading, shell.leadingInset).padding(.trailing, shell.trailingInset)
                        .padding(.top, shell.topInset).padding(.bottom, shell.bottomInset)
                }
                canvasControls
                    .padding(.leading, shell.leadingInset).padding(.trailing, shell.trailingInset)
                    .padding(.top, shell.topInset).padding(.bottom, shell.bottomInset)
                ShellChromeView(state: state, shell: shell, controlsWidth: $controlsWidth)
                FloatingDocksView(state: state, layout: layout, regionWidth: geo.size.width)
            }
            .onChange(of: layout.leadingInset, initial: true) { _, v in state.docks.leadingInset = v }
            .onChange(of: layout.trailingInset, initial: true) { _, v in state.docks.trailingInset = v }
            .onChange(of: shell.topInset, initial: true) { _, v in state.docks.topInset = v }
            .onChange(of: shell.bottomInset, initial: true) { _, v in state.docks.bottomInset = v }
            .onChange(of: controlsWidth, initial: true) { _, v in state.docks.controlsWidth = v }
            .onChange(of: tabsWidth, initial: true) { _, v in if abs(v - state.ribbonTabsWidth) > 0.5 { state.ribbonTabsWidth = v } }
            .animation(AccessibilityPrefs.reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.08), value: visibility)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.2), value: state.ribbonCollapsed)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: state.activeTool == nil)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: state.openViews.count > 1)
        }
        .arcusAnimation(state.message)
        .ignoresSafeArea()
        .background(Color(nsColor: Tokens.canvas))
        .sheet(item: $state.presented) { d in DialogHost(state: state, dialog: d) }
    }

    /// What the shell has to place: the docks' insets and which rows apply.
    private func shellRequest(_ region: DockRegion, _ docks: DockLayoutResult, sidebarShown: Bool) -> ShellRequest {
        var r = ShellRequest(region: region)
        r.leadingInset = docks.leadingInset; r.trailingInset = docks.trailingInset
        r.sidebarCollapsed = !sidebarShown
        r.ribbonMinimized = state.ribbonCollapsed
        r.optionsShown = state.activeTool != nil
        r.viewTabsShown = state.openViews.count > 1
        r.controlsWidth = controlsWidth > 0 ? controlsWidth : nil
        return r
    }

    /// The canvas's floating HUDs (each on its own glass shield): toasts, ⌘K search and the navigation bar. In 3D
    /// views the navigation bar sits under the orientation cube, which owns the top-right corner.
    @ViewBuilder private var canvasControls: some View {
        ZStack(alignment: .top) {
            if let msg = state.message {
                ToastView(text: msg, isError: state.messageIsError) { state.message = nil }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if state.commandSearchVisible {
                CommandSearchView(state: state).padding(.top, 24)
            }
            if let v = state.activeView, v.schedule == nil {
                NavigationBarView(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, v.view?.kind == .threeD ? 148 : 12).padding(.trailing, 12) // W4-WIRE: under the 3D orientation cube
            }
        }
    }
}

struct EmptyCanvasView: View {
    let state: DocumentState
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.dashed").font(.system(size: 40, weight: .thin)).foregroundStyle(.tertiary)
            Text("No view is open").font(.title3)
            Text("Double-click a view, sheet or schedule in the Project Browser.").foregroundStyle(.secondary).font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Wraps the persistent AppKit canvas for a view (2D canvas, 3D viewport or schedule table). The floating shell's
/// insets become the container's additional safe area (over the title bar's own), so the canvas fits and places its
/// own furniture (zoom to fit, the orientation cube) in the part of the drawing the user can see. // W4-SHELL, W4-WIRE
struct CanvasHost: NSViewRepresentable {
    let state: DocumentState
    let viewID: ElementID
    var leadingInset: Double = 0
    var trailingInset: Double = 0
    var topInset: Double = 0
    var bottomInset: Double = 0
    /// F810: Tile Views activates the tile's view on a click.
    var onActivate: (() -> Void)? = nil

    func makeNSView(context: Context) -> CanvasContainerView {
        let container = CanvasContainerView()
        container.wantsLayer = true
        let v = canvas()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.removeFromSuperview()
        container.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor), v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            v.topAnchor.constraint(equalTo: container.topAnchor), v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.desired = NSEdgeInsets(top: topInset, left: leadingInset, bottom: bottomInset, right: trailingInset)
        container.f810ObserveCanvasTheme() // F810: Canvas Theme
        container.f810SetActivation(onActivate) // F810: Tile Views
        if onActivate == nil || state.activeViewID == viewID { DispatchQueue.main.async { v.window?.makeFirstResponder(v) } }
        return container
    }

    func updateNSView(_ nsView: CanvasContainerView, context: Context) {
        nsView.desired = NSEdgeInsets(top: topInset, left: leadingInset, bottom: bottomInset, right: trailingInset)
        nsView.f810SetActivation(onActivate) // F810
    }

    func canvas() -> NSView {
        if let c = state.canvases[viewID] { return c }
        let e = state.model[viewID]
        let v: NSView
        if e?.schedule != nil { v = ScheduleTableView(state: state, scheduleID: viewID) }
        else if e?.view?.kind == .threeD { v = Viewport3DHost(state: state, viewID: viewID) }
        else { v = Canvas2DView(state: state, viewID: viewID) }
        state.canvases[viewID] = v
        return v
    }
}

/// The canvas's container: keeps its safe area at the shell's insets from the window edges, whatever the window
/// itself contributes (the title bar's height, or nothing in full screen). // W4-WIRE
final class CanvasContainerView: NSView {
    var desired = NSEdgeInsets() { didSet { applyInsets() } }
    /// F810: Tile Views activation (WindowArrangement.swift).
    var f810Activate: (() -> Void)?
    var f810Monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); applyInsets()
        if window == nil, let m = f810Monitor { NSEvent.removeMonitor(m); f810Monitor = nil } // F810
        else if window != nil, f810Monitor == nil, let a = f810Activate { f810SetActivation(a) }
    }
    override func layout() { super.layout(); applyInsets() }
    private func applyInsets() {
        let total = safeAreaInsets, extra = additionalSafeAreaInsets
        let inherited = NSEdgeInsets(top: total.top - extra.top, left: total.left - extra.left, bottom: total.bottom - extra.bottom, right: total.right - extra.right)
        let wanted = NSEdgeInsets(top: max(0, desired.top - inherited.top), left: max(0, desired.left - inherited.left),
                                  bottom: max(0, desired.bottom - inherited.bottom), right: max(0, desired.right - inherited.right))
        guard wanted.top != extra.top || wanted.left != extra.left || wanted.bottom != extra.bottom || wanted.right != extra.right else { return }
        additionalSafeAreaInsets = wanted
        func relayout(_ v: NSView) { v.needsLayout = true; v.subviews.forEach(relayout) }
        relayout(self)
    }
}

/// Document-view tabs ("Floor Plan: Level 1", "Sheet: A101 - Plans") and their titles, with an overflow menu of every
/// open view. Closing a tab activates the previously active one; ⌃Tab / ⌃⇧Tab cycle (Window menu). BL-BROWSER
struct ViewTabBar: View {
    @Bindable var state: DocumentState
    /// The row itself is drawn by `ViewTabPills` (ShellChrome.swift): one glass pill per open view. // W4-WIRE
    var body: some View { ViewTabPills(state: state) }

    @ViewBuilder func tab(_ id: ElementID, _ e: Element) -> some View {
        let active = id == state.activeViewID
        HStack(spacing: 6) {
            Image(systemName: icon(e)).font(.system(size: 10.5)).foregroundStyle(active ? Tokens.selectionColor : .secondary)
            Text(title(e)).font(.system(size: 11.5, weight: active ? .semibold : .regular)).lineLimit(1)
            Button { state.close(id) } label: {
                Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold)).frame(width: 14, height: 14).contentShape(Circle())
            }
                .buttonStyle(RibbonPressStyle())
                .modifier(HoverBackground(radius: 7))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close \(title(e))")
        }
        .padding(.leading, 11).padding(.trailing, 6).padding(.vertical, 4)
        .background {
            if active {
                Capsule().fill(Tokens.selectionColor.opacity(0.14)) // W4-WIRE: a tint on the glass pill
            }
        }
        .modifier(HoverBackground(radius: 12))
        .contentShape(Capsule())
        .onTapGesture { state.activeViewID = id }
        .contextMenu {
            Button("Close") { state.close(id) }
            Button("Close Inactive Views") { state.closeInactiveViews() }.disabled(state.openViews.count < 2)
        }
        .help(title(e))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title(e))
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { state.activeViewID = id }
    }

    func icon(_ e: Element) -> String { e.sheet != nil ? "doc.richtext" : e.schedule != nil ? "tablecells" : (e.view?.kind.symbolName ?? "rectangle") }
    func title(_ e: Element) -> String { ViewTitles.qualified(e) }
}

/// Scale, detail level, visual style, crop, temporary hide/isolate and reveal hidden for the active view.
struct ViewControlStrip: View {
    @Bindable var state: DocumentState
    var body: some View {
        let _ = state.session.changeCounter
        let v = state.activeView
        let vd = v?.view
        let temp = state.activeViewID.flatMap { state.session.temporaryVisibility[$0] }
        HStack(spacing: 10) {
            if let vd, vd.kind != .threeD {
                Menu {
                    let imperial = state.model.units.system == .imperial
                    if imperial { ForEach(ViewScales.imperial, id: \.value) { s in Button(s.label) { setScale(s.value) } } }
                    else { ForEach(ViewScales.metric, id: \.self) { s in Button("1 : \(s)") { setScale(s) } } }
                } label: { Text(ViewScales.label(vd.scale, imperial: state.model.units.system == .imperial)).font(Tokens.monoDigits) }
                .menuStyle(.borderlessButton).fixedSize()
                .help(scaleLocked(v) ? "View scale (controlled by the view template)" : "View scale").accessibilityLabel("View scale \(vd.scale)") // BL-VG
                .disabled(scaleLocked(v)) // BL-VG: only when the template controls the scale
            }
            if let vd {
                Menu {
                    ForEach(DetailLevel.allCases, id: \.self) { d in Button(d.rawValue) { CommandRouter(state: state).setViewParam(ParameterID("view.detailLevel"), .text(d.rawValue), "Detail Level") } }
                } label: { Image(systemName: vd.detailLevel == .coarse ? "circle.dotted" : vd.detailLevel == .medium ? "circle.lefthalf.filled" : "circle.fill") }
                .menuStyle(.borderlessButton).fixedSize().help("Detail level: \(vd.detailLevel.rawValue)").accessibilityLabel("Detail level \(vd.detailLevel.rawValue)")
                if vd.kind != .threeD, vd.kind.isModelView { visualStyle2D(vd) } // BL-VG: Wireframe / Hidden Line in 2D views
                if vd.kind == .threeD {
                    Menu {
                        ForEach(VisualStyle.allCases, id: \.self) { s in Button(s.rawValue) { CommandRouter(state: state).setViewParam(ParameterID("view.visualStyle"), .text(s.rawValue), "Visual Style") } }
                    } label: { Image(systemName: "cube") }
                    .menuStyle(.borderlessButton).fixedSize().help("Visual style: \(vd.visualStyle.rawValue)").accessibilityLabel("Visual style \(vd.visualStyle.rawValue)")
                    GraphicDisplayControls(state: state, options: vd.displayOptions)
                    stripButton(vd.sectionBoxActive ? "cube.transparent.fill" : "cube.transparent", "Section box", .sectionBox, on: vd.sectionBoxActive)
                } else {
                    stripButton(vd.cropActive ? "crop" : "crop", "Crop view", .cropView, on: vd.cropActive)
                    stripButton("crop.rotate", "Show crop region", .toggleCropVisible, on: vd.cropVisible)
                    stripButton("line.3.horizontal", "Thin lines (screen only)", .thinLines, on: state.thinLines)
                }
                Menu {
                    Button("Hide Element") { CommandRouter(state: state).run(.temporaryHide) }
                    Button("Hide Category") { CommandRouter(state: state).run(.temporaryHideCategory) }
                    Button("Isolate Element") { CommandRouter(state: state).run(.temporaryIsolate) }
                    Button("Isolate Category") { CommandRouter(state: state).run(.temporaryIsolateCategory) }
                    Divider()
                    Button("Reset Temporary Hide/Isolate") { CommandRouter(state: state).run(.resetTemporary) }
                } label: { Image(systemName: temp?.isActive == true ? "eyeglasses" : "eyeglasses") }
                .menuStyle(.borderlessButton).fixedSize()
                .overlay(alignment: .topTrailing) { if temp?.isActive == true { Circle().fill(Tokens.selectionColor).frame(width: 5, height: 5) } }
                .help(temp?.isActive == true ? "Temporary hide/isolate is on" : "Temporary hide/isolate")
                .accessibilityLabel(temp?.isActive == true ? "Temporary hide or isolate, active" : "Temporary hide or isolate")
                stripButton("lightbulb", "Reveal hidden elements", .revealHidden, on: temp?.revealHidden == true)
                temporaryViewPropertiesMenu(temp) // BL-VG
                if vd.kind.isPlan || vd.kind == .drafting { stripButton("lock.rectangle", "Reveal constraints", .revealConstraints, on: temp?.revealConstraints == true) } // BL-VG
            }
            if temp?.isActive == true || temp?.revealHidden == true || temp?.temporaryTemplateID != nil || temp?.revealConstraints == true { // BL-VG
                Text(temp?.revealHidden == true ? "Reveal Hidden" : temp?.isActive == true ? "Temporary Hide/Isolate" : temp?.temporaryTemplateID != nil ? "Temporary View Properties" : "Reveal Constraints") // BL-VG
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Tokens.selectionColor.opacity(0.15)))
                    .foregroundStyle(Tokens.selectionColor)
            }
        }
        .fixedSize()
    }

    func stripButton(_ symbol: String, _ help: String, _ cmd: CommandID, on: Bool) -> some View {
        Button { CommandRouter(state: state).run(cmd) } label: {
            Image(systemName: symbol).foregroundStyle(on ? Tokens.selectionColor : .primary)
                .frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .modifier(HoverBackground(active: on, tint: Tokens.selectionColor, radius: 5))
        .help(help + (on ? " (on)" : ""))
        .accessibilityLabel(help)
        .accessibilityValue(on ? "On" : "Off")
    }

    func setScale(_ s: Int) { CommandRouter(state: state).setViewParam(ParameterID("view.scale"), .int(s), "View Scale") }

    func coordinate(_ p: Vec2) -> String {
        let u = state.model.units
        if state.activeView?.sheet != nil { return String(format: "%.0f, %.0f mm", p.x * 1000, p.y * 1000) }
        if state.activeView?.view?.kind.isVerticalCut == true {
            return "El " + QuantityFormatter.format(p.y, kind: .length, units: u)
        }
        return "X " + QuantityFormatter.format(p.x, kind: .length, units: u) + "   Y " + QuantityFormatter.format(p.y, kind: .length, units: u)
    }
}

/// 3D view shadows toggle and Graphic Display Options menu (ambient shadows, silhouettes, sun) for the View Control Bar.
struct GraphicDisplayControls: View {
    let state: DocumentState
    let options: GraphicDisplayOptions

    private struct SunPreset: Identifiable {
        let id: String
        let sun: SunSettings
    }

    private static let lightingPresets: [SunPreset] = [
        SunPreset(id: "Morning (southeast)", sun: SunSettings(mode: .lighting, azimuth: 120, altitude: 25)),
        SunPreset(id: "Default (southeast, 35°)", sun: .default),
        SunPreset(id: "Midday (south, 60°)", sun: SunSettings(mode: .lighting, azimuth: 180, altitude: 60)),
        SunPreset(id: "Afternoon (southwest)", sun: SunSettings(mode: .lighting, azimuth: 225, altitude: 35)),
        SunPreset(id: "Relative to View", sun: SunSettings(mode: .lighting, azimuth: 40, altitude: 52, relativeToView: true)),
    ]
    private static let stillPresets: [SunPreset] = [
        SunPreset(id: "June 21, 9:00", sun: SunSettings(mode: .still, month: 6, day: 21, hour: 9)),
        SunPreset(id: "June 21, 12:00", sun: SunSettings(mode: .still, month: 6, day: 21, hour: 12)),
        SunPreset(id: "June 21, 15:00", sun: SunSettings(mode: .still, month: 6, day: 21, hour: 15)),
        SunPreset(id: "December 21, 12:00", sun: SunSettings(mode: .still, month: 12, day: 21, hour: 12)),
    ]

    var body: some View {
        Button { update("Shadows") { $0.castShadows.toggle() } } label: {
            Image(systemName: "shadow").foregroundStyle(options.castShadows ? Tokens.selectionColor : .primary)
        }
        .buttonStyle(.plain)
        .help(options.castShadows ? "Shadows On" : "Shadows Off")
        .accessibilityLabel("Shadows")
        .accessibilityValue(options.castShadows ? "On" : "Off")
        Menu {
            Toggle("Cast Shadows", isOn: binding(\.castShadows, "Shadows"))
            Toggle("Ambient Shadows", isOn: binding(\.ambientShadows, "Ambient Shadows"))
            Toggle("Silhouette Edges", isOn: binding(\.silhouetteEdges, "Silhouette Edges"))
            Divider()
            Section("Sun: Lighting") {
                ForEach(Self.lightingPresets) { p in sunButton(p) }
            }
            Section("Sun: Project Location") {
                ForEach(Self.stillPresets) { p in sunButton(p) }
            }
        } label: { Image(systemName: "sun.max") }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Graphic display options")
        .accessibilityLabel("Graphic display options")
    }

    private func sunButton(_ p: SunPreset) -> some View {
        Button { update("Sun Settings") { $0.sun = p.sun } } label: {
            if options.sun == p.sun { Label(p.id, systemImage: "checkmark") } else { Text(p.id) }
        }
    }

    private func binding(_ key: WritableKeyPath<GraphicDisplayOptions, Bool>, _ name: String) -> Binding<Bool> {
        Binding(get: { options[keyPath: key] }, set: { value in update(name) { $0[keyPath: key] = value } })
    }

    /// One undoable view change on the active 3D view.
    private func update(_ name: String, _ change: @escaping (inout GraphicDisplayOptions) -> Void) {
        guard let id = state.activeViewID else { return }
        state.session.perform(name) { tx in tx.update(id) { e in if var v = e.view { change(&v.displayOptions); e.view = v } } }
    }
}

/// Floating navigation bar at the canvas's right edge: zoom and pan/zoom history, as a small Liquid Glass column.
struct NavigationBarView: View {
    let state: DocumentState
    @AppStorage("navigationBar.visible") private var visible = true
    var body: some View {
        if visible {
            VStack(spacing: 2) {
                navButton(.navigationWheel) // F810: 2D / Full Navigation Wheel
                navButton(.zoomIn)
                navButton(.zoomOut)
                Menu {
                    ForEach([CommandID.zoomRegion, .zoomOutTwice, .zoomExtents, .zoomSheetSize], id: \.self) { id in
                        Button(CommandCatalog.info(id).title, systemImage: CommandCatalog.info(id).symbol) { CommandRouter(state: state).run(id) }
                    }
                    Divider()
                    Button("Previous Pan/Zoom", systemImage: "arrow.uturn.backward") { CommandRouter(state: state).run(.previousPanZoom) }
                    Button("Next Pan/Zoom", systemImage: "arrow.uturn.forward") { CommandRouter(state: state).run(.nextPanZoom) }
                    Divider()
                    Button("Hide Navigation Bar") { visible = false }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 26)
                } primaryAction: { CommandRouter(state: state).run(.zoomExtents) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .help("Zoom to Fit (ZF). Click and hold for more zoom commands")
                .accessibilityLabel("Zoom to Fit")
                navButton(.previousPanZoom)
                if state.activeView?.view?.kind == .threeD { Camera3DNavigationMenu(state: state) } // W2-CAM
            }
            .padding(4)
            .modifier(GlassPanel(cornerRadius: 12))
        }
    }

    func navButton(_ id: CommandID) -> some View {
        let info = CommandCatalog.info(id)
        return Button { CommandRouter(state: state).run(id) } label: {
            Image(systemName: info.symbol).font(.system(size: 12, weight: .medium)).frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(info.title + (info.shortcut.map { "  \($0)" } ?? ""))
        .accessibilityLabel(info.title)
    }
}

/// Liquid Glass rounded panel for a canvas HUD, with an opaque fallback for Reduce Transparency / Increase Contrast.
/// The glass is an AppKit shield (ShellChrome.swift), so a wheel or click on it never reaches the canvas. // W4-WIRE
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat
    var role: ShellPillRole = .hud
    func body(content: Content) -> some View {
        content.background(GlassBackdrop(role: role, cornerRadius: cornerRadius))
    }
}

/// The single bar under the canvas: the active view's controls on the left, then the prompt, and the cursor position,
/// background tasks, model health and selection on the right.
struct BottomBarView: View {
    @Bindable var state: DocumentState
    @AppStorage("statusBar.visible") private var statusBarVisible = true // BL-VG: View ▸ User Interface ▸ Status Bar
    var body: some View {
        HStack(spacing: 0) {
            ViewControlStrip(state: state)
            if statusBarVisible { // BL-VG
                Divider().frame(height: 16).padding(.horizontal, 10)
                ViewThatFits(in: .horizontal) { // W4-WIRE: the bottom pill is narrower than the window; drop the coordinates, then the selection controls, then the warnings
                    StatusBarView(state: state)
                    StatusBarView(state: state, level: 1)
                    StatusBarView(state: state, level: 2)
                    StatusBarView(state: state, level: 3)
                }
            } else { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 14) // W4-WIRE: inside the bottom pill (BottomPill draws the glass)
        .frame(height: Tokens.bottomBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading) // W4-WIRE: a pill too narrow for the view controls clips at its right end, never the left
    }
}

/// Status part of the bottom bar: prompt, snap, cursor position, background tasks, warnings, selection count and filter.
struct StatusBarView: View {
    @Bindable var state: DocumentState
    /// How much has been dropped to fit a narrow bottom pill: 1 the cursor position, 2 the selection controls and
    /// background tasks, 3 the warnings too (the prompt stays). // W4-WIRE
    var level = 0
    var body: some View {
        let _ = state.toolRevision
        let v = state.activeView
        HStack(spacing: 10) {
            Text(state.prompt)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 30, idealWidth: 120, maxWidth: .infinity, alignment: .leading) // W4-WIRE: fits by truncating
                .accessibilityLabel("Status: \(state.prompt)")
            if let s = state.snapDescription, state.activeTool != nil {
                Text(s).font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).lineLimit(1).accessibilityLabel("Snap \(s)")
            }
            Spacer(minLength: 8)
            if level < 1, let p = state.cursorPoint, v?.view?.kind != .threeD, v?.schedule == nil { // W4-WIRE
                let text = ViewControlStrip(state: state).coordinate(p)
                Text(text).font(Tokens.monoDigits).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .accessibilityLabel("Cursor position \(text)")
            }
            ForEach(level < 2 ? state.backgroundTasks : []) { t in // W4-WIRE
                HStack(spacing: 4) {
                    ProgressView(value: t.progress).progressViewStyle(.linear).frame(width: 70).controlSize(.mini)
                    Text(t.title).font(.system(size: 10)).lineLimit(1)
                    Button { t.cancel() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel \(t.title)")
                }
            }
            if level < 3 { // W4-WIRE
            Button { state.presented = .warnings } label: { // BL-VG: status bar opens the Warnings dialog
                let errors = state.healthWarnings.filter { $0.severity == .error }.count
                let warns = state.healthWarnings.count - errors
                HStack(spacing: 3) {
                    Image(systemName: errors > 0 ? "exclamationmark.octagon" : (warns > 0 ? "exclamationmark.triangle" : "checkmark.seal"))
                        .foregroundStyle(errors > 0 ? .red : (warns > 0 ? .orange : .secondary))
                    Text(errors + warns == 0 ? "No warnings" : "\(errors + warns)").font(.system(size: 11).monospacedDigit())
                        .lineLimit(1).fixedSize() // W4-AUDIT: never wraps to "N o" in narrow windows; the prompt truncates instead
                }
            }
            .buttonStyle(.plain)
            .help("Warnings") // BL-VG
            .accessibilityLabel(state.healthWarnings.isEmpty ? "Model health: no warnings" : "Model health: \(state.healthWarnings.count) warnings")
            }
            if level < 2 { // W4-WIRE
            Divider().frame(height: 14)
            // Selection toggles, in the order BIM users find them at the right of the status bar.
            HStack(spacing: 2) {
                selectionToggle("link", "Select Links", on: state.session.selection.selectLinks) { state.session.selection.selectLinks.toggle() }
                selectionToggle("square.3.layers.3d.down.right", "Select Underlay Elements", on: state.session.selection.selectUnderlay) { state.session.selection.selectUnderlay.toggle() }
                selectionToggle("pin", "Select Pinned Elements", on: state.session.selection.selectPinned) { state.session.selection.selectPinned.toggle() }
            }
            Divider().frame(height: 14)
            Menu {
                Button("All Categories") { state.session.selection.filter = nil }
                Divider()
                ForEach(state.session.selection.categoryCounts(state.model), id: \.0) { c, n in
                    Button("Only \(c.displayName) (\(n))") { state.session.selection.select(state.session.selection.ids.filter { state.model[$0]?.category == c }) }
                }
                Divider()
                Toggle("Select Pinned Elements", isOn: Binding(get: { state.session.selection.selectPinned }, set: { state.session.selection.selectPinned = $0 }))
                Toggle("Select Links", isOn: Binding(get: { state.session.selection.selectLinks }, set: { state.session.selection.selectLinks = $0 }))
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("\(state.session.selection.count)").font(.system(size: 11).monospacedDigit())
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Selection filter")
            .accessibilityLabel("\(state.session.selection.count) selected. Selection filter")
            }
        }
    }

    func selectionToggle(_ symbol: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).symbolVariant(on ? .none : .slash)
                .font(.system(size: 11))
                .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .modifier(HoverBackground(radius: 5))
        .help("\(title): \(on ? "on" : "off")")
        .accessibilityLabel(title)
        .accessibilityValue(on ? "On" : "Off")
    }
}

struct ToastView: View {
    let text: String
    let isError: Bool
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill").foregroundStyle(isError ? .orange : Tokens.selectionColor)
            Text(text).font(.system(size: 12)).lineLimit(3).multilineTextAlignment(.leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .modifier(GlassCapsule())
        .frame(maxWidth: 560)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Liquid Glass capsule for small floating controls, on an AppKit shield (see `GlassPanel`). // W4-WIRE
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GlassBackdrop(role: .hud, cornerRadius: nil))
    }
}

/// ⌘K command search: title, alias, keyword; recent commands first.
struct CommandSearchView: View {
    @Bindable var state: DocumentState
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var results: [CommandInfo] {
        let router = CommandRouter(state: state)
        return Array(CommandCatalog.search(query, aliases: KeyboardAliases.shared.aliases, recent: state.recentCommands, available: { _ in true }).prefix(12))
            .sorted { (router.disabledReason($0.id) == nil ? 0 : 1) < (router.disabledReason($1.id) == nil ? 0 : 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands, aliases (e.g. WA, DR, TX)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onExitCommand { state.commandSearchVisible = false }
                    .accessibilityLabel("Command search")
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, c in
                        let reason = CommandRouter(state: state).disabledReason(c.id)
                        HStack {
                            Image(systemName: c.symbol).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title).font(.system(size: 12, weight: .medium))
                                Text(reason ?? c.help).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(([c.shortcut].compactMap { $0 } + KeyboardAliases.shared.aliases(for: c.id)).joined(separator: "  "))
                                .font(.system(size: 10).monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(i == index ? Tokens.selectionColor.opacity(0.15) : .clear)
                        .opacity(reason == nil ? 1 : 0.55)
                        .contentShape(Rectangle())
                        .onTapGesture { index = i; runSelected() }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .modifier(GlassPanel(cornerRadius: 16)) // W4-SHELL
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
    }

    func runSelected() {
        guard index < results.count else { return }
        let id = results[index].id
        state.commandSearchVisible = false
        CommandRouter(state: state).run(id)
    }
}
