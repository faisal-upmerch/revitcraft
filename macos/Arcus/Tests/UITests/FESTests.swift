import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// FES (Docs/FurnitureMode.md §5): the Family Editor on the project window's shell. Regression tests for the owner's
/// screenshot (no tab names in the ribbon's tab row, ribbon panels clipped under the toolbar): the tab row and the
/// panel row keep their own heights however little room the window gives them, and in the shell every tab name is
/// laid out at its full width and every panel sits inside the ribbon strip. With `ARCUS_UI_CAPTURES=1` the window is
/// also rendered offscreen to `/tmp/arcus-fes/` (light and dark, 1280 × 800 and the minimum size).
@MainActor
@Suite("FES Family Editor shell", .serialized)
struct FESTests {
    static func model() -> FamilyEditorModel {
        _ = NSApplication.shared
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        let state = DocumentState(session: DocumentSession(model: BIMModel()))
        return FamilyEditorModel(family: f, state: state, familyID: nil)
    }

    /// Hosts `view` in an offscreen window of `size` and lets layout and the geometry callbacks settle.
    @discardableResult
    static func host<V: View>(_ view: V, size: CGSize) async -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).coordinateSpace(.named(FamilyEditorChrome.space)))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        await settle(h)
        return w
    }

    static func settle(_ v: NSView) async {
        for _ in 0..<6 {
            v.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    static func textWidth(_ s: String, weight: NSFont.Weight) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: weight)]).width
    }

    // MARK: Root causes

    @Test("Tab names keep their size when the window offers the tab row almost no height")
    func tabRowNeverCollapses() async throws {
        let m = Self.model()
        await Self.host(FamilyRibbonTabsBar(model: m, available: 600).frame(height: 4), size: CGSize(width: 640, height: 40))
        for t in FamilyRibbonTab.allCases {
            let r = try #require(m.chrome.measuredTabs[t.rawValue], "\(t.rawValue) tab not laid out")
            #expect(r.height >= 14, "\(t.rawValue) tab text is \(r.height) pt tall")
            #expect(r.width >= Self.textWidth(t.rawValue, weight: .medium) - 1, "\(t.rawValue) tab text is \(r.width) pt wide")
        }
    }

    @Test("The panel row keeps the project ribbon's height and shows every panel whole when squeezed")
    func panelRowNeverSqueezes() async throws {
        let m = Self.model()
        for tab in FamilyRibbonTab.allCases {
            m.chrome.ribbonTab = tab
            m.chrome.measuredPanels = [:]
            await Self.host(FamilyRibbonPanels(model: m).frame(height: 40), size: CGSize(width: 1800, height: 120))
            let row = m.chrome.measuredPanelRow
            #expect(row.height >= Tokens.ribbonPanelHeight - 0.5, "\(tab.rawValue): the panel row is \(row.height) pt tall")
            #expect(!m.chrome.measuredPanels.isEmpty, "\(tab.rawValue): no panels")
            for (title, r) in m.chrome.measuredPanels {
                #expect(r.height >= RibbonMetrics.contentHeight + RibbonMetrics.titleHeight + 8, "\(tab.rawValue) ▸ \(title) is \(r.height) pt tall")
                #expect(r.minY >= row.minY - 0.5 && r.maxY <= row.maxY + 0.5, "\(tab.rawValue) ▸ \(title) \(r) is clipped by the row \(row)")
            }
        }
    }

    @Test("The tabs fit in full at 1280 pt and keep their names at the minimum width")
    func tabFit() {
        let available = { (window: Double) -> CGFloat in
            let docks = DockLayout.layout(region: DockRegion(width: window, height: 800),
                                          leading: DockRequest(edge: .leading, width: FamilyDockStore.defaultLeadingWidth, visible: true),
                                          trailing: DockRequest(edge: .trailing, width: FamilyDockStore.defaultTrailingWidth, visible: true), metrics: .familyEditor)
            var r = ShellRequest(region: DockRegion(width: window, height: 800))
            r.leadingInset = docks.leadingInset; r.trailingInset = docks.trailingInset
            r.controlsWidth = 99
            return CGFloat(ShellLayout.layout(r, metrics: .arcus).tabs.width) - 10
        }
        #expect(FamilyRibbonTabsBar.fit(contextual: nil, available: available(1280)) == .full)
        #expect(FamilyRibbonTabsBar.fit(contextual: "Modify | Create Extrusion", available: available(1280)) == .full)
        #expect(FamilyRibbonTabsBar.fit(contextual: nil, available: available(Double(FamilyEditorChrome.minimumSize.width))) == .full)
        #expect(FamilyRibbonTabsBar.fit(contextual: "Modify | Create Extrusion", available: available(Double(FamilyEditorChrome.minimumSize.width))) == .truncatedContextual)
    }

    @Test("Zoom to fit centres the family in the part of the canvas not under the shell")
    func fitInsideInsets() {
        let insets = NSEdgeInsets(top: 160, left: 290, bottom: 56, right: 300)
        let size = Vec2(1280, 800)
        let b = Rect2(center: Vec2(0.3, -0.2), halfSize: Vec2(0.5, 0.25))
        let c = FamilyCanvasFit.camera(b, size: size, insets: insets)
        let s = c.toScreen(b.center, size: size)
        #expect(abs(s.x - (290 + (1280 - 290 - 300) / 2)) < 1e-6)
        #expect(abs(s.y - (160 + (800 - 160 - 56) / 2)) < 1e-6)
        let lo = c.toScreen(b.min, size: size), hi = c.toScreen(b.max, size: size)
        #expect(lo.x >= 290 && hi.x <= 1280 - 300 && hi.y >= 160 && lo.y <= 800 - 56)
    }

    // MARK: The whole window

    /// Opens the editor window offscreen at `size` and checks the shell: tab names at full width, panels inside the strip.
    func checkWindow(_ wc: FamilyEditorWindowController, size: NSSize, label: String) async throws {
        guard let w = wc.window else { Issue.record("no window"); return }
        w.setContentSize(size)
        wc.model.chrome.measuredPanels = [:] // the tabs keep their last frames: a tab that didn't move reports nothing new
        if let v = w.contentView { await Self.settle(v) }
        let chrome = wc.model.chrome
        // At 1280 pt and at the minimum width the six task tabs never collapse into the menu (`tabFit`).
        for t in FamilyRibbonTab.allCases {
            let r = try #require(chrome.measuredTabs[t.rawValue], "\(label): \(t.rawValue) tab missing")
            #expect(r.width >= Self.textWidth(t.rawValue, weight: .medium) - 1 && r.height >= 14, "\(label): \(t.rawValue) tab is \(r.size)")
            #expect(r.minY >= 0 && r.maxY <= CGFloat(ShellMetrics.arcus.margin + ShellMetrics.arcus.pillHeight), "\(label): \(t.rawValue) tab outside the tab pill: \(r)")
        }
        let strip = chrome.measuredStrip
        #expect(strip.height >= CGFloat(ShellMetrics.arcus.ribbonHeight) - 0.5, "\(label): strip is \(strip.size)")
        #expect(strip.minY >= CGFloat(ShellMetrics.arcus.pillHeight + ShellMetrics.arcus.margin), "\(label): strip at \(strip.minY)")
        let row = chrome.measuredPanelRow
        #expect(row.minY >= strip.minY - 0.5 && row.maxY <= strip.maxY + 0.5, "\(label): the panel row \(row) is outside the strip \(strip)")
        for (title, r) in chrome.measuredPanels {
            #expect(r.minY >= row.minY - 0.5 && r.maxY <= row.maxY + 0.5, "\(label): \(title) panel \(r) is clipped by the row \(row)")
            #expect(r.minY >= strip.minY - 0.5 && r.maxY <= strip.maxY + 0.5, "\(label): \(title) panel \(r) clips out of the strip \(strip)")
        }
    }

    @Test("The editor window lays out its shell without clipping at 1280 × 800 and at the minimum size")
    func windowShell() async throws {
        let m = Self.model()
        let wc = FamilyEditorWindowController(model: m)
        defer { wc.close() }
        #expect(wc.window?.toolbar == nil)
        #expect(wc.window?.styleMask.contains(.fullSizeContentView) == true)
        for size in [NSSize(width: 1280, height: 800), FamilyEditorChrome.minimumSize] {
            for tab in FamilyRibbonTab.allCases {
                m.chrome.ribbonTab = tab
                try await checkWindow(wc, size: size, label: "\(Int(size.width)) \(tab.rawValue)")
            }
            m.perform(.feExtrusion)
            try await checkWindow(wc, size: size, label: "\(Int(size.width)) sketch")
            m.cancelSketch()
        }
    }

    // MARK: Captures

    @Test("Offscreen captures of the editor (ARCUS_UI_CAPTURES=1)", .enabled(if: ProcessInfo.processInfo.environment["ARCUS_UI_CAPTURES"] == "1"))
    func captures() async throws {
        let out = URL(fileURLWithPath: "/tmp/arcus-fes")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let m = Self.model()
            let wc = FamilyEditorWindowController(model: m)
            guard let w = wc.window else { continue }
            w.appearance = NSAppearance(named: appearance)
            for (size, label) in [(NSSize(width: 1280, height: 800), "1280"), (FamilyEditorChrome.minimumSize, "min")] {
                w.setContentSize(size)
                m.select(nil); m.view = .plan; m.zoomToFit()
                try await shoot(w, out, "fe-\(label)-\(suffix)")
                if let s = m.family.solids.first { m.select(.solid(s.id)) }
                try await shoot(w, out, "fe-\(label)-selected-\(suffix)")
                m.select(nil)
                m.perform(.feExtrusion)
                m.addSketchVertex(.init(u: -0.2, v: -0.2)); m.addSketchVertex(.init(u: 0.25, v: -0.2)); m.addSketchVertex(.init(u: 0.1, v: 0.3))
                try await shoot(w, out, "fe-\(label)-sketch-\(suffix)")
                m.cancelSketch()
            }
            w.setContentSize(NSSize(width: 1280, height: 800))
            m.view = .front
            try await shoot(w, out, "fe-front-tabs-\(suffix)")
            m.view = .back
            try await shoot(w, out, "fe-back-\(suffix)")
            m.perform(.feDefault3D)
            m.orbit = FamilyOrbit(yaw: 120, pitch: -25)
            try await shoot(w, out, "fe-3d-\(suffix)")
            m.view = .plan
            m.flex()
            try await shoot(w, out, "fe-flex-\(suffix)")
            m.chrome.toggleBrowser()
            try await shoot(w, out, "fe-collapsed-\(suffix)")
            m.chrome.toggleBrowser()
            m.chrome.ribbonTab = .annotate
            try await shoot(w, out, "fe-annotate-\(suffix)")
            wc.close()
        }
    }

    func shoot(_ w: NSWindow, _ dir: URL, _ name: String) async throws {
        guard let v = w.contentView?.superview ?? w.contentView else { return }
        await Self.settle(v)
        v.displayIfNeeded()
        let rep = try #require(v.bitmapImageRepForCachingDisplay(in: v.bounds))
        v.cacheDisplay(in: v.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
