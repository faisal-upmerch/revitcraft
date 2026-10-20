import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// W4-WIRE: the floating shell over the edge-to-edge canvas. Every floating piece (side docks, the ribbon tab pill,
// the controls pill, the ribbon strip, the Options pill, the view-tab pills, the bottom pill, the collapsed-sidebar
// strip, the canvas HUDs) sits on a `GlassShieldView`: an AppKit Liquid Glass view (opaque under Reduce Transparency
// / Increase Contrast) that keeps every click and wheel over it away from the drawing. Geometry comes from
// `ShellLayout` (Application, tested); this file draws it.

/// What a floating piece is, so QA can find it and the shield knows how to behave.
enum ShellPillRole: String {
    case dock, collapsedStrip, tabs, controls, ribbon, options, viewTab, bottom, hud
}

extension ShellMetrics {
    static let arcus = ShellMetrics()
}

// MARK: - Glass shield

/// An AppKit glass surface: `NSGlassEffectView` (or an opaque window-coloured panel with a separator border under
/// Reduce Transparency / Increase Contrast), a soft shadow, and input containment — nothing over it reaches the
/// canvas. A mouse-down on a pill's empty area drags the window, as it does on a toolbar.
class GlassShieldView: NSView {
    let role: ShellPillRole
    /// Rounded corners of this radius, or a capsule (half the height) when nil.
    var cornerRadius: CGFloat?
    let glass = NSGlassEffectView()
    let solid = NSView()
    private(set) var usesGlass = true

    init(role: ShellPillRole, cornerRadius: CGFloat?) {
        self.role = role
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        for v in [glass, solid] { v.translatesAutoresizingMaskIntoConstraints = false; v.isHidden = true; addSubview(v) }
        glass.style = .regular
        solid.wantsLayer = true
        solid.layer?.cornerCurve = .continuous
        solid.layer?.borderWidth = 1
        for v in [glass, solid] {
            NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
        let s = NSShadow()
        s.shadowBlurRadius = role == .dock ? 14 : 10
        s.shadowOffset = NSSize(width: 0, height: role == .dock ? -4 : -2)
        s.shadowColor = NSColor.black.withAlphaComponent(role == .dock ? 0.16 : 0.12)
        shadow = s
        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    var effectiveRadius: CGFloat { cornerRadius ?? bounds.height / 2 }
    /// PILLS (offscreen captures): draw the opaque surface, as Reduce Transparency does. Offscreen glass can't follow
    /// a dark appearance, so dark captures use this to show the pills as they read on screen.
    nonisolated(unsafe) static var forceOpaque = false

    /// Chooses glass or the opaque fallback; called when the accessibility settings or the appearance may have changed.
    func applyAppearance() {
        let wantGlass = !(Self.forceOpaque || AccessibilityPrefs.reduceTransparency || AccessibilityPrefs.increaseContrast)
        if wantGlass != usesGlass || (glass.isHidden && solid.isHidden) {
            usesGlass = wantGlass
            glass.isHidden = !wantGlass
            solid.isHidden = wantGlass
            surfaceChanged()
        }
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.borderColor = NSColor.separatorColor.cgColor
        applyRadius()
    }
    /// Subclasses that host content move it between the glass and the opaque surface here.
    func surfaceChanged() {}

    func applyRadius() {
        let r = effectiveRadius
        if glass.cornerRadius != r { glass.cornerRadius = r }
        solid.layer?.cornerRadius = r
    }

    override func layout() {
        super.layout()
        if cornerRadius == nil { applyRadius() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    // MARK: Input containment

    /// Everything over the shield is the shield's: nothing falls through to the canvas below. Hits on the bare glass
    /// come back as the shield itself so it gets the mouse-down (window drag) and the wheel (swallowed).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        guard let v = super.hitTest(point), v !== glass, v !== solid else { return self }
        return v
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1, dragsWindow(at: convert(event.locationInWindow, from: nil)) else { return }
        window?.performDrag(with: event)
    }
    /// Whether a mouse-down at `p` (view coordinates) on the bare surface moves the window.
    func dragsWindow(at p: NSPoint) -> Bool { role != .hud }
}

/// The glass surface as a SwiftUI background: the shield sits under the content, so the content's controls work as
/// usual while clicks and wheels on the bare surface stop at the shield.
struct GlassBackdrop: NSViewRepresentable {
    var role: ShellPillRole
    /// Nil for a capsule.
    var cornerRadius: CGFloat?
    func makeNSView(context: Context) -> GlassShieldView { GlassShieldView(role: role, cornerRadius: cornerRadius) }
    func updateNSView(_ v: GlassShieldView, context: Context) {
        if v.cornerRadius != cornerRadius { v.cornerRadius = cornerRadius; v.applyRadius() }
        v.applyAppearance()
    }
}

/// A floating pill: capsule (default) or rounded glass behind the content.
struct GlassPill: ViewModifier {
    var role: ShellPillRole
    var cornerRadius: CGFloat? = nil
    func body(content: Content) -> some View {
        content.background(GlassBackdrop(role: role, cornerRadius: cornerRadius))
    }
}

// MARK: - Traffic lights

/// Holds the window's standard close / minimize / zoom buttons where the sidebar (or the collapsed strip) wants them.
/// The buttons stay the window's own (`standardWindowButton`), so they keep their behaviour; the group answers the
/// hover query the buttons make of their container, so the glyphs light up together as in a title bar.
final class TrafficLightsView: NSView {
    static let spacing: CGFloat = 20
    private var mouseInside = false
    var onLayout: (() -> Void)?
    weak var controller: DocumentWindowController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window controls")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.spacing * 2 + 14, height: 16) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { mouseInside = true; redrawButtons() }
    override func mouseExited(with event: NSEvent) { mouseInside = false; redrawButtons() }
    private func redrawButtons() { for v in subviews { v.needsDisplay = true } }
    /// The standard window buttons ask their container whether the pointer is over the group to draw their glyphs.
    @objc func _mouseInGroup(_ button: NSButton) -> Bool { mouseInside }

    override func layout() {
        super.layout()
        onLayout?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onLayout?()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }
    override func scrollWheel(with event: NSEvent) {}
}

/// Places the traffic lights in a SwiftUI layout; the window controller moves the buttons into whichever host is
/// currently in the window (the sidebar's, or the collapsed strip's while the sidebar animates out).
struct TrafficLightsHost: NSViewRepresentable {
    let state: DocumentState
    func makeNSView(context: Context) -> TrafficLightsView {
        let v = TrafficLightsView(frame: .zero)
        let controller = state.window?.windowController as? DocumentWindowController
        v.controller = controller
        v.onLayout = { [weak controller] in controller?.placeTrafficLights() }
        controller?.registerTrafficLightsHost(v)
        return v
    }
    func updateNSView(_ v: TrafficLightsView, context: Context) {
        if v.controller == nil, let controller = state.window?.windowController as? DocumentWindowController {
            v.controller = controller
            v.onLayout = { [weak controller] in controller?.placeTrafficLights() }
            controller.registerTrafficLightsHost(v)
        }
    }
    static func dismantleNSView(_ v: TrafficLightsView, coordinator: ()) { v.controller?.unregisterTrafficLightsHost(v) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrafficLightsView, context: Context) -> CGSize? { nsView.intrinsicContentSize }
}

// MARK: - Pills

/// A 28 pt icon button for the controls pill and the sidebar row.
struct PillIconButton: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: PillSpec.shellItemHeight + 4, height: PillSpec.shellItemHeight)
                .pillHighlight(false) // PILLS: a 28 pt capsule, 4 pt inside the 36 pt pill
        }
        .buttonStyle(RibbonPressStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Undo or Redo with a history drop-down (BL-KEYS): clicking undoes or redoes one step; the arrow lists the steps,
/// newest first, and picking one undoes (or redoes) through it.
struct UndoHistoryMenu: View {
    @Bindable var state: DocumentState
    let redo: Bool
    private static let maxEntries = 30
    var body: some View {
        let _ = state.session.changeCounter
        let um = state.session.undoManager
        let enabled = redo ? um.canRedo : um.canUndo
        Menu {
            let h = state.undoHistory
            let names = redo ? h.redoNames : h.undoNames
            if names.isEmpty {
                Text(redo ? "Nothing to Redo" : "Nothing to Undo")
            }
            ForEach(Array(names.prefix(Self.maxEntries).enumerated()), id: \.offset) { i, name in
                Button((redo ? "Redo " : "Undo ") + name) { if redo { h.redo(through: i) } else { h.undo(through: i) } }
            }
            if names.count > Self.maxEntries { Text("\(names.count - Self.maxEntries) earlier steps…") }
        } label: {
            HStack(spacing: 1) {
                Image(systemName: redo ? "arrow.uturn.forward" : "arrow.uturn.backward").font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            }
            .frame(width: 40, height: PillSpec.shellItemHeight).pillHighlight(false) // PILLS
        } primaryAction: {
            if redo { um.redo() } else { um.undo() }
        }
        .menuStyle(.button).buttonStyle(RibbonPressStyle()).menuIndicator(.hidden)
        .opacity(enabled ? 1 : 0.4)
        .help(redo ? "Redo (⇧⌘Z). Click the arrow for the list of steps." : "Undo (⌘Z). Click the arrow for the list of steps.")
        .accessibilityLabel(redo ? "Redo" : "Undo")
    }
}

/// The right-hand pill of the top row: undo/redo with history, previous view, 3D, command search, workspace menu and
/// the inspector toggle. In a narrow window previous view and 3D move into the workspace menu.
struct ShellControlsPill: View {
    @Bindable var state: DocumentState
    let compact: Bool
    var body: some View {
        let router = CommandRouter(state: state)
        HStack(spacing: PillSpec.gap) {
            UndoHistoryMenu(state: state, redo: false)
            UndoHistoryMenu(state: state, redo: true)
            if !compact {
                PillIconButton(symbol: "chevron.backward", help: "Previous view (⌘[)", enabled: state.viewHistory.count > 1) { state.previousView() }
                PillIconButton(symbol: "cube", help: "Open the default 3D coordination view") { router.run(.threeDView) }
            }
            PillIconButton(symbol: "magnifyingglass", help: "Command search (⌘K)") { state.commandSearchVisible.toggle() }
            Menu {
                if compact {
                    Button("Previous View", systemImage: "chevron.backward") { state.previousView() }
                    Button("3D View", systemImage: "cube") { router.run(.threeDView) }
                    Divider()
                }
                ForEach([("BIM Familiar", CommandID.workspaceBIMFamiliar), ("Mac Spacious", .workspaceMacSpacious)], id: \.0) { title, cmd in
                    Button { router.run(cmd) } label: {
                        if (cmd == .workspaceBIMFamiliar) == (state.workspace == .bimFamiliar) { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
                Divider()
                Button("Reset Workspace") { router.run(.resetWorkspace) }
            } label: {
                HStack(spacing: 1) {
                    Image(systemName: "rectangle.3.group").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                }
                .frame(width: 40, height: PillSpec.shellItemHeight).pillHighlight(false) // PILLS
            }
            .menuStyle(.button).buttonStyle(RibbonPressStyle()).menuIndicator(.hidden)
            .help("Choose a panel layout")
            .accessibilityLabel("Workspace")
            PillIconButton(symbol: "sidebar.trailing", help: state.workspace == .macSpacious ? "Show or hide the inspector" : "Show or hide Properties") {
                (state.window?.windowController as? DocumentWindowController)?.toggleInspector(nil)
            }
            AIToolbarButton(panel: AIAssistantPanel.of(state)) { AIAssistantPanel.toggle(in: state) } // AICORE: the AI assistant (⇧⌘A)
        }
        .padding(.horizontal, PillSpec.inset) // PILLS: the end buttons' capsules 4 pt from the pill's ends
        .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
        .modifier(GlassPill(role: .controls))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window controls")
    }
}

/// The top row inside the sidebar: the traffic lights and the hide-sidebar button.
struct SidebarTopRow: View {
    @Bindable var state: DocumentState
    var body: some View {
        HStack(spacing: 0) {
            TrafficLightsHost(state: state).padding(.leading, 12)
            Spacer(minLength: 8)
            PillIconButton(symbol: "sidebar.leading", help: "Hide Sidebar (⌥⌘S)") {
                (state.window?.windowController as? DocumentWindowController)?.toggleSidebar(nil)
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 8)
        }
        .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
    }
}

/// The strip that stands in for the collapsed sidebar: the traffic lights and a show-sidebar button.
struct CollapsedSidebarStrip: View {
    @Bindable var state: DocumentState
    var body: some View {
        HStack(spacing: 0) {
            TrafficLightsHost(state: state).padding(.leading, 12)
            Spacer(minLength: 6)
            PillIconButton(symbol: "sidebar.leading", help: "Show Sidebar (⌥⌘S)") {
                (state.window?.windowController as? DocumentWindowController)?.toggleSidebar(nil)
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
        }
        .frame(width: CGFloat(ShellMetrics.arcus.collapsedStripWidth), height: CGFloat(ShellMetrics.arcus.pillHeight))
        .modifier(GlassPill(role: .collapsedStrip))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collapsed sidebar")
    }
}

/// The ribbon tab pill: the tabs bar in a capsule.
struct RibbonTabsPill: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonTabsBar(state: state)
            .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
            .modifier(GlassPill(role: .tabs))
    }
}

/// The ribbon strip: the active tab's panels on a rounded glass bar.
struct RibbonStrip: View {
    @Bindable var state: DocumentState
    var body: some View {
        RibbonView(state: state)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(ShellMetrics.arcus.ribbonHeight))
            .modifier(GlassPill(role: .ribbon, cornerRadius: Tokens.dockCornerRadius))
    }
}

/// The open-view tabs as a row of small pills (only when more than one view is open), with the overflow menu.
struct ViewTabPills: View {
    @Bindable var state: DocumentState
    var body: some View {
        let _ = state.session.changeCounter
        let bar = ViewTabBar(state: state)
        let row = HStack(spacing: 6) {
            ForEach(state.openViews, id: \.self) { id in
                if let e = state.model[id] {
                    bar.tab(id, e).id(id)
                        .frame(height: CGFloat(ShellMetrics.arcus.viewTabsHeight))
                        .modifier(GlassPill(role: .viewTab))
                }
            }
        }
        .padding(.vertical, 1)
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) { // the row hugs its pills; a long row scrolls
                row.fixedSize()
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { row.fixedSize() }
                        .onChange(of: state.activeViewID) { _, v in if let v { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(v) } } }
                }
            }
            Menu {
                ForEach(state.openViews, id: \.self) { id in
                    if let e = state.model[id] {
                        Button { state.activeViewID = id } label: {
                            if id == state.activeViewID { Label(bar.title(e), systemImage: "checkmark") } else { Text(bar.title(e)) }
                        }
                    }
                }
                Divider()
                Button("Close Inactive Views") { state.closeInactiveViews() }.disabled(state.openViews.count < 2)
            } label: {
                // PILLS: a 22 pt hover circle 4 pt inside the 30 pt glass circle, as the tabs' capsules.
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .frame(width: PillSpec.viewTabItemHeight, height: PillSpec.viewTabItemHeight)
                    .pillHighlight(false)
                    .padding(PillSpec.inset)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .modifier(GlassPill(role: .viewTab))
            .help("All open views")
            .accessibilityLabel("Open views, \(state.openViews.count)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open views")
    }
}

/// The bottom pill: the view controls, the status bar and the selection controls.
struct BottomPill: View {
    @Bindable var state: DocumentState
    var body: some View {
        BottomBarView(state: state)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(ShellMetrics.arcus.bottomHeight))
            .clipShape(Capsule())
            .modifier(GlassPill(role: .bottom))
    }
}

/// Every floating piece except the side docks, placed by a `ShellLayoutResult` in the canvas region.
struct ShellChromeView: View {
    @Bindable var state: DocumentState
    let shell: ShellLayoutResult
    @Binding var controlsWidth: Double
    var body: some View {
        let _ = state.toolRevision
        let m = ShellMetrics.arcus
        ZStack(alignment: .topLeading) {
            if let strip = shell.strip {
                CollapsedSidebarStrip(state: state).offset(x: strip.x, y: strip.y)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: m.margin) {
                RibbonTabsPill(state: state).frame(maxWidth: shell.tabs.width, alignment: .leading)
                Spacer(minLength: 0)
                ShellControlsPill(state: state, compact: shell.controlsCompact)
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { controlsWidth = $0 }
            }
            .frame(width: shell.contentWidth, alignment: .topLeading)
            .offset(x: shell.contentLeft, y: shell.tabs.y)
            if let r = shell.ribbon {
                RibbonStrip(state: state).frame(width: r.width, height: r.height).offset(x: r.x, y: r.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let o = shell.options {
                OptionsBarView(state: state)
                    .frame(maxWidth: o.width, alignment: .leading).frame(height: o.height)
                    .offset(x: o.x, y: o.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let t = shell.viewTabs {
                ViewTabPills(state: state).frame(width: t.width, height: t.height, alignment: .leading).offset(x: t.x, y: t.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let b = shell.bottom {
                BottomPill(state: state).frame(width: b.width, height: b.height).offset(x: b.x, y: b.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
