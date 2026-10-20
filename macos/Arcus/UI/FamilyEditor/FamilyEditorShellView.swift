import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// FES: the Family Editor window's content, laid out like the project window's `ContentAreaView`: the family canvas
// fills the window edge to edge and everything else floats over it on Liquid Glass shields (GlassShieldView):
// the ribbon tab pill and the controls pill, the ribbon strip, the Options Bar while a tool or sketch runs, the view
// tabs when more than one view is open, the bottom pill, and the left (Project Browser) and right (Properties) docks.
// Positions come from `DockLayout` and `ShellLayout`, the same pure layouts the project window uses.

struct FamilyEditorShellView: View {
    @Bindable var model: FamilyEditorModel

    var body: some View {
        let chrome = model.chrome
        GeometryReader { geo in
            let region = DockRegion(width: geo.size.width, height: geo.size.height)
            let docks = DockLayout.layout(region: region,
                                          leading: DockRequest(edge: .leading, width: chrome.docks.prefs.leadingWidth, visible: chrome.browserShown),
                                          trailing: DockRequest(edge: .trailing, width: chrome.docks.prefs.trailingWidth,
                                                                 visible: chrome.propertiesShown || AIAssistantPanel.existing(family: model)?.isShown == true), // AICORE
                                          metrics: .familyEditor)
            let shell = ShellLayout.layout(shellRequest(region, docks), metrics: .arcus)
            ZStack(alignment: .topLeading) {
                FamilyCanvas(model: model, insets: NSEdgeInsets(top: shell.topInset, left: shell.leadingInset, bottom: shell.bottomInset, right: shell.trailingInset))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Family canvas, \(model.view.viewTitle)")
                if chrome.problemsShown, model.hasProblems {
                    FamilyProblemsCard(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, shell.contentLeft + 4).padding(.bottom, shell.bottomInset + 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                FamilyEditorChromeView(model: model, shell: shell)
                FamilyEditorDocksView(model: model, layout: docks, regionWidth: geo.size.width)
            }
            .animation(AccessibilityPrefs.reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.08), value: [chrome.browserShown, chrome.propertiesShown])
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.2), value: chrome.ribbonCollapsed)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: model.tool == nil && model.sketch == nil)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: model.openViews.count > 1)
            .animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: chrome.problemsShown)
        }
        .coordinateSpace(.named(FamilyEditorChrome.space))
        .ignoresSafeArea()
        .background(Color(nsColor: Tokens.canvas))
        .sheet(item: $model.sheet) { s in
            switch s {
            case .familyTypes: FamilyTypesDialog(model: model)
            case .categoryAndParameters: FamilyCategoryDialog(model: model)
            case .workPlane: FamilyWorkPlaneDialog(model: model) // F1415
            }
        }
        // The contextual tab opens when a sketch, a tool or a selection begins; the task tab returns when it ends.
        .onChange(of: model.ribbonContextualTitle, initial: true) { old, new in
            if new != nil && (new != old || old == nil) { chrome.ribbonShowsContextual = true } else if new == nil { chrome.ribbonShowsContextual = false }
        }
        .onChange(of: model.flexResults) { _, r in if r != nil { chrome.problemsShown = true } }
        .onChange(of: model.evaluated.errors.count) { old, new in if new > old { chrome.problemsShown = true } }
        .onKeyPress(.init("z"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) { model.undo.redo() } else { model.undo.undo() }
            return .handled
        }
    }

    /// What the shell has to place: the docks' insets and which rows apply.
    private func shellRequest(_ region: DockRegion, _ docks: DockLayoutResult) -> ShellRequest {
        var r = ShellRequest(region: region)
        r.leadingInset = docks.leadingInset; r.trailingInset = docks.trailingInset
        r.sidebarCollapsed = !model.chrome.browserShown
        r.ribbonMinimized = model.chrome.ribbonCollapsed
        r.optionsShown = model.tool != nil || model.sketch != nil
        r.viewTabsShown = model.openViews.count > 1
        r.controlsWidth = model.chrome.controlsWidth > 0 ? model.chrome.controlsWidth : nil
        return r
    }
}

extension FamilyEditorModel {
    /// A flex test result, or evaluation errors or warnings, to show on the problems card.
    var hasProblems: Bool { flexResults != nil || !evaluated.errors.isEmpty || !evaluated.warnings.isEmpty }
}

/// Every floating piece except the docks, placed by a `ShellLayoutResult` (as the project window's `ShellChromeView`).
struct FamilyEditorChromeView: View {
    @Bindable var model: FamilyEditorModel
    let shell: ShellLayoutResult

    var body: some View {
        let m = ShellMetrics.arcus
        let chrome = model.chrome
        ZStack(alignment: .topLeading) {
            if let strip = shell.strip {
                FamilyCollapsedStrip(model: model).offset(x: strip.x, y: strip.y)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: m.margin) {
                FamilyRibbonTabsPill(model: model, available: shell.tabs.width).frame(maxWidth: shell.tabs.width, alignment: .leading)
                Spacer(minLength: 0)
                FamilyControlsPill(model: model)
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { w in if abs(w - chrome.controlsWidth) > 0.5 { chrome.controlsWidth = w } }
            }
            .frame(width: shell.contentWidth, alignment: .topLeading)
            .offset(x: shell.contentLeft, y: shell.tabs.y)
            if let r = shell.ribbon {
                FamilyRibbonStrip(model: model).frame(width: r.width, height: r.height).offset(x: r.x, y: r.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let o = shell.options {
                FamilyOptionsBar(model: model)
                    .frame(maxWidth: o.width, alignment: .leading).frame(height: o.height)
                    .offset(x: o.x, y: o.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let t = shell.viewTabs {
                FamilyViewTabPills(model: model).frame(width: t.width, height: t.height, alignment: .leading).offset(x: t.x, y: t.y)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let b = shell.bottom {
                FamilyBottomPill(model: model).frame(width: b.width, height: b.height).offset(x: b.x, y: b.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The two floating docks: the Project Browser on the left (with the traffic lights and the family's header) and
/// Properties on the right, resizable by their inner edge and hidden with ⌥⌘S / ⌥⌘1 and the inspector button / ⌥⌘2.
struct FamilyEditorDocksView: View {
    @Bindable var model: FamilyEditorModel
    let layout: DockLayoutResult
    let regionWidth: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let p = layout.placement(.leading) {
                panel(p) {
                    VStack(spacing: 0) {
                        FamilyDockTopRow(model: model)
                        FamilyHeader(model: model)
                        FamilyBrowserView(model: model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel("Project Browser")
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if let p = layout.placement(.trailing) {
                panel(p) { FamilyTrailingDock(model: model) } // AICORE: Properties and/or the AI assistant
                    .accessibilityLabel("Properties")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func panel<C: View>(_ p: DockPlacement, @ViewBuilder content: () -> C) -> some View {
        let docks = model.chrome.docks
        let other = layout.placement(p.edge == .leading ? .trailing : .leading)?.frame.width ?? 0
        return DockPanelHost(edge: p.edge, content: AnyView(content()), resize: { startWidth, dragX in
            docks.setWidth(DockLayout.resized(edge: p.edge, startWidth: startWidth, dragX: dragX, regionWidth: regionWidth, otherDockWidth: other, metrics: .familyEditor), p.edge)
        }, resizeEnded: { docks.save() }, startWidth: { docks.prefs.width(p.edge) })
            .frame(width: p.frame.width, height: p.frame.height)
            .offset(x: p.frame.x, y: p.frame.y)
            .accessibilityElement(children: .contain)
    }
}
