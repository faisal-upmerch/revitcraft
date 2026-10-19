import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// POLISH: Revit-style ribbon panel collapsing. At 1280 pt and at the minimum window width every panel of every tab
/// (project and Furniture documents, and the Family Editor) is laid out inside the ribbon strip: panels shrink, then
/// collapse into their buttons from the right, instead of running off the strip. Captures go to /tmp/arcus-polish/.
@MainActor
@Suite("POLISH ribbon collapsing", .serialized)
struct POLISHRibbonTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-polish")
    /// The document window's minimum width (DocumentWindowController).
    static let mainMinimum: Double = 980

    /// The ribbon strip's width in a document window `window` points wide, with both docks at their default width.
    static func stripWidth(_ window: Double) -> CGFloat {
        let docks = DockLayout.layout(region: DockRegion(width: window, height: 800),
                                      leading: DockRequest(edge: .leading, width: DockPreferences.defaultLeadingWidth, visible: true),
                                      trailing: DockRequest(edge: .trailing, width: DockPreferences.defaultTrailingWidth, visible: true), metrics: .arcus)
        var r = ShellRequest(region: DockRegion(width: window, height: 800))
        r.leadingInset = docks.leadingInset; r.trailingInset = docks.trailingInset
        r.controlsWidth = 99
        return CGFloat(ShellLayout.layout(r, metrics: .arcus).ribbon?.width ?? window)
    }

    static func host<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name = .aqua) async -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: appearance)
        let h = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor))))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        await settle(h)
        return h
    }

    static func settle(_ v: NSView) async {
        for _ in 0..<6 { v.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
    }

    static func shoot(_ v: NSView, _ name: String) throws {
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    /// Hosts the ribbon strip of `state` at `width` for every tab of its mode and checks no panel is clipped.
    func checkTabs(_ state: DocumentState, width: CGFloat, label: String, capture: Bool) async throws {
        let frames = RibbonFrames.of(state)
        for tab in RibbonTab.tabs(for: state.mode) {
            state.ribbonTab = tab
            frames.reset()
            let h = await Self.host(RibbonStrip(state: state), size: CGSize(width: width, height: CGFloat(ShellMetrics.arcus.ribbonHeight)))
            let expected = RibbonContent.panels(tab, mode: state.mode).count
            #expect(frames.panels.count == expected, "\(label) \(tab.rawValue): \(frames.panels.count) of \(expected) panels laid out")
            #expect(frames.clipped().isEmpty, "\(label) \(tab.rawValue): clipped panels \(frames.clipped())")
            if capture { try Self.shoot(h, "ribbon-\(label)-\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))") }
        }
    }

    @Test("The plan shrinks panels from the right, then collapses them from the right")
    func planOrder() {
        // Three panels: full, compact, icons, collapsed.
        let w: [[CGFloat]] = [[200, 150, 100, 50], [200, 150, 100, 50], [200, 150, 100, 50]]
        #expect(RibbonPanelRow.plan(w, available: 700, spacing: 0) == [0, 0, 0])
        #expect(RibbonPanelRow.plan(w, available: 560, spacing: 0) == [0, 0, 1])
        #expect(RibbonPanelRow.plan(w, available: 450, spacing: 0) == [1, 1, 1])
        #expect(RibbonPanelRow.plan(w, available: 350, spacing: 0) == [1, 2, 2])
        #expect(RibbonPanelRow.plan(w, available: 300, spacing: 0) == [2, 2, 2])
        #expect(RibbonPanelRow.plan(w, available: 200, spacing: 0) == [2, 3, 3])
        #expect(RibbonPanelRow.plan(w, available: 10, spacing: 0) == [3, 3, 3])
        // A panel that can only collapse waits for the collapse step.
        #expect(RibbonPanelRow.plan([[200, 150], [200, 150, 100]], available: 340, spacing: 0) == [0, 2])
    }

    @Test("Project ribbon: every tab fits at 1280 pt and at the minimum width")
    func projectTabs() async throws {
        let state = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        for (window, label) in [(1280.0, "1280"), (Self.mainMinimum, "min")] {
            try await checkTabs(state, width: Self.stripWidth(window), label: "project-\(label)", capture: true)
        }
    }

    @Test("Furniture ribbon: every tab fits at 1280 pt and at the minimum width")
    func furnitureTabs() async throws {
        let state = DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel())))
        #expect(state.mode == .furniture)
        for (window, label) in [(1280.0, "1280"), (Self.mainMinimum, "min")] {
            try await checkTabs(state, width: Self.stripWidth(window), label: "furniture-\(label)", capture: true)
        }
    }

    @Test("A collapsed panel is a button that shows the whole panel")
    func collapsedPanelsStayReachable() async throws {
        let state = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        state.ribbonTab = .architecture
        let frames = RibbonFrames.of(state)
        frames.reset()
        let h = await Self.host(RibbonStrip(state: state), size: CGSize(width: 420, height: CGFloat(ShellMetrics.arcus.ribbonHeight)))
        #expect(frames.clipped().isEmpty, "\(frames.clipped())")
        #expect(frames.density.values.contains(3), "nothing collapsed at 420 pt: \(frames.density)")
        try Self.shoot(h, "ribbon-architecture-420")
        // At full width nothing shrinks.
        frames.reset()
        _ = await Self.host(RibbonStrip(state: state), size: CGSize(width: 2400, height: CGFloat(ShellMetrics.arcus.ribbonHeight)))
        #expect(frames.density.values.allSatisfy { $0 == 0 }, "\(frames.density)")
    }

    @Test("Family Editor: every tab's panels stay inside the strip at 1280 × 800 and at the minimum size")
    func familyEditorTabs() async throws {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        let m = FamilyEditorModel(family: f, state: DocumentState(session: DocumentSession(model: BIMModel())), familyID: nil)
        let wc = FamilyEditorWindowController(model: m)
        defer { wc.close() }
        guard let w = wc.window else { Issue.record("no window"); return }
        for (size, label) in [(NSSize(width: 1280, height: 800), "1280"), (FamilyEditorChrome.minimumSize, "min")] {
            for tab in FamilyRibbonTab.allCases {
                m.chrome.measuredPanels = [:]
                m.chrome.ribbonTab = tab
                if tab == FamilyRibbonTab.allCases.first { w.setContentSize(size) } // a new size lays every panel out again
                if let v = w.contentView { await Self.settle(v) }
                let strip = m.chrome.measuredStrip
                #expect(!m.chrome.measuredPanels.isEmpty, "\(label) \(tab.rawValue): no panels")
                for (title, r) in m.chrome.measuredPanels {
                    #expect(r.minX >= strip.minX - 0.5 && r.maxX <= strip.maxX + 0.5, "\(label) \(tab.rawValue) ▸ \(title) \(r) runs out of the strip \(strip)")
                }
                // Load into Project is on every tab: whole, shrunk or collapsed, but there.
                #expect(m.chrome.measuredPanels["Family Editor"] != nil || tab == .modify, "\(label) \(tab.rawValue): no Family Editor panel")
                if let v = w.contentView?.superview ?? w.contentView, tab == .create { try Self.shoot(v, "family-editor-\(label)-create") }
            }
        }
    }
}
