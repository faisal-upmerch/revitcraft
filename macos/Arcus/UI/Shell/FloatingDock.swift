import AppKit
import SwiftUI
import ArcusApplication

// W4-SHELL: the floating Liquid Glass docks. The canvas fills the whole content area; the left sidebar (project
// header, Properties, Project Browser) and the right inspector (Mac Spacious) float over it as inset glass panels,
// resizable by dragging their inner edge and collapsible with the toolbar buttons and ⌥⌘S. Geometry comes from
// `DockLayout` (Application layer, tested); this file draws it and keeps pointer input from reaching the canvas.

/// Per-document dock state: the persisted widths and collapsed flags, and the overlay insets the current layout produced.
@MainActor
@Observable
final class DockLayoutState {
    var prefs: DockPreferences
    /// Bumped by the window when something the view can't observe changes (a panel is detached or re-docked).
    var revision = 0
    /// Insets the canvas's floating controls and the canvas itself (zoom to fit, the orientation cube) keep from the docks.
    var leadingInset: Double = 0
    var trailingInset: Double = 0
    /// Insets the canvas keeps from the floating top rows and the bottom pill (ShellLayout). // W4-WIRE
    var topInset: Double = 0
    var bottomInset: Double = 0
    /// The controls pill's measured width, so the ribbon tabs know how much of the top row is theirs. // W4-WIRE
    var controlsWidth: Double = 0
    @ObservationIgnored private let store: any DockPreferenceStore

    init(store: any DockPreferenceStore = UserDefaults.standard) {
        self.store = store
        prefs = DockPreferences.load(from: store)
    }

    func setWidth(_ w: Double, _ edge: DockEdge) { prefs.setWidth(w, edge) }
    func setCollapsed(_ c: Bool, _ edge: DockEdge) { prefs.setCollapsed(c, edge); save() }
    func save() { prefs.save(to: store) }
}

/// Which docks have something to show, from the workspace, the panel toggles and detached panels.
struct DockVisibility: Equatable {
    var leading: Bool
    var trailing: Bool

    @MainActor init(_ state: DocumentState) {
        let familiar = state.workspace == .bimFamiliar
        let navigator = state.showNavigator && !PanelWindows.isDetached(.navigator)
        let properties = state.showProperties && !PanelWindows.isDetached(.properties)
        leading = !state.docks.prefs.leadingCollapsed && (navigator || (familiar && properties))
        trailing = !state.docks.prefs.trailingCollapsed && ((!familiar && properties) || ComponentPanelModel.of(state).isShown) // COMP: the Components panel
    }
}

extension DockMetrics {
    /// The app's metrics: the design tokens for the docks.
    static let arcus: DockMetrics = {
        var m = DockMetrics()
        m.minWidth = Double(Tokens.sidebarMinWidth)
        m.maxWidth = Double(Tokens.sidebarMaxWidth)
        m.canvasMinWidth = Double(Tokens.canvasMinWidth)
        m.margin = Double(Tokens.dockMargin)
        m.cornerRadius = Double(Tokens.dockCornerRadius)
        return m
    }()
}

/// Both floating docks, laid out in the canvas region. Sits in the canvas ZStack above the canvas and its controls.
struct FloatingDocksView: View {
    @Bindable var state: DocumentState
    let layout: DockLayoutResult
    let regionWidth: Double
    var body: some View {
        let _ = state.docks.revision
        ZStack(alignment: .topLeading) {
            if let p = layout.placement(.leading) {
                panel(p) { LeftDock(state: state) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if let p = layout.placement(.trailing) {
                panel(p) { InspectorDock(state: state) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func panel<C: View>(_ p: DockPlacement, @ViewBuilder content: () -> C) -> some View {
        let other = layout.placement(p.edge == .leading ? .trailing : .leading)?.frame.width ?? 0
        return DockPanelHost(edge: p.edge, content: AnyView(content()), resize: { startWidth, dragX in
            state.docks.setWidth(DockLayout.resized(edge: p.edge, startWidth: startWidth, dragX: dragX, regionWidth: regionWidth, otherDockWidth: other, metrics: .arcus), p.edge)
        }, resizeEnded: { state.docks.save() }, startWidth: { state.docks.prefs.width(p.edge) })
            .frame(width: p.frame.width, height: p.frame.height)
            .offset(x: p.frame.x, y: p.frame.y)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(dockLabel(p.edge))
    }

    /// Names the dock after the palettes it holds (BIM Familiar stacks Properties above the Project Browser on the left).
    private func dockLabel(_ edge: DockEdge) -> String {
        guard edge == .leading else { return "Properties" }
        let properties = state.workspace == .bimFamiliar && state.showProperties && !PanelWindows.isDetached(.properties)
        let browser = state.showNavigator && !PanelWindows.isDetached(.navigator)
        switch (properties, browser) {
        case (true, true): return "Properties and Project Browser"
        case (true, false): return "Properties"
        default: return "Project Browser"
        }
    }
}

/// An AppKit glass container for one dock (`GlassShieldView`, ShellChrome.swift) holding a SwiftUI content host.
/// Being a real view above the canvas it takes every click and scroll over the panel, so wheel zooms and clicks never
/// leak to the drawing; a drag zone along its inner edge resizes.
struct DockPanelHost: NSViewRepresentable {
    let edge: DockEdge
    let content: AnyView
    let resize: (Double, Double) -> Void
    let resizeEnded: () -> Void
    let startWidth: () -> Double

    func makeNSView(context: Context) -> DockPanelView {
        let v = DockPanelView(edge: edge, content: content)
        v.resize = resize; v.resizeEnded = resizeEnded; v.startWidth = startWidth
        return v
    }
    func updateNSView(_ v: DockPanelView, context: Context) {
        v.host.rootView = content
        v.resize = resize; v.resizeEnded = resizeEnded; v.startWidth = startWidth
        v.applyAppearance()
    }
}

final class DockPanelView: GlassShieldView { // W4-WIRE: one glass shield for every floating piece; the docks add a content host and a resize handle
    let edge: DockEdge
    let host: NSHostingView<AnyView>
    var resize: ((Double, Double) -> Void)?
    var resizeEnded: (() -> Void)?
    var startWidth: (() -> Double)?
    private var dragStart: (x: CGFloat, width: Double)?

    init(edge: DockEdge, content: AnyView) {
        self.edge = edge
        host = NSHostingView(rootView: content)
        super.init(role: .dock, cornerRadius: Tokens.dockCornerRadius)
        host.sizingOptions = []
        host.safeAreaRegions = [] // W4-WIRE: the panel overlaps the title bar area; its content must not inset for it
        host.translatesAutoresizingMaskIntoConstraints = false
        surfaceChanged()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Moves the content into the glass or onto the opaque panel, whichever `applyAppearance` chose (a no-op when
    /// it is already there: re-setting the glass's content view after removing it would leave the host orphaned).
    override func surfaceChanged() {
        if usesGlass {
            guard glass.contentView !== host else { return }
            host.removeFromSuperview()
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            host.frame = glass.bounds
            glass.contentView = host
        } else {
            guard host.superview !== solid else { return }
            if glass.contentView === host { glass.contentView = nil }
            host.removeFromSuperview()
            host.translatesAutoresizingMaskIntoConstraints = false
            solid.addSubview(host)
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: solid.leadingAnchor), host.trailingAnchor.constraint(equalTo: solid.trailingAnchor),
                                         host.topAnchor.constraint(equalTo: solid.topAnchor), host.bottomAnchor.constraint(equalTo: solid.bottomAnchor)])
        }
        // Glass content is clipped to the panel's corners by the effect view; clip the opaque host the same way.
        host.wantsLayer = true
        host.layer?.cornerRadius = Tokens.dockCornerRadius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
    }

    // MARK: Input containment

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if handleRect.contains(local) { return self }
        return super.hitTest(point)
    }
    /// Only the header row (traffic lights, project name) drags the window; the panels below take their own input.
    override func dragsWindow(at p: NSPoint) -> Bool { p.y > bounds.height - CGFloat(ShellMetrics.arcus.pillHeight) - 44 }

    // MARK: Resize handle

    private var handleRect: NSRect {
        let w = CGFloat(DockMetrics.arcus.resizeHandleWidth)
        return edge == .leading ? NSRect(x: bounds.maxX - w, y: 0, width: w, height: bounds.height) : NSRect(x: 0, y: 0, width: w, height: bounds.height)
    }
    override func resetCursorRects() { addCursorRect(handleRect, cursor: .resizeLeftRight) }
    override func layout() {
        super.layout()
        if usesGlass, host.frame != glass.bounds { host.frame = glass.bounds }
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard handleRect.contains(p) else { super.mouseDown(with: event); return }
        dragStart = (event.locationInWindow.x, startWidth?() ?? Double(bounds.width))
        if event.clickCount == 2 {
            resize?(DockPreferences.defaultLeadingWidth, 0); resizeEnded?(); dragStart = nil
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        resize?(start.width, Double(event.locationInWindow.x - start.x))
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        resizeEnded?()
    }
}

extension Tokens {
    /// Gap between a floating dock and the canvas region's edges.
    static let dockMargin: CGFloat = 10
    /// Corner radius of a floating dock (the canvas controls use 12–14, so the docks read as the larger, outer shape).
    static let dockCornerRadius: CGFloat = 16
}
