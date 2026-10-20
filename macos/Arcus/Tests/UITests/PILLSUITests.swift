import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// PILLS: selected capsules keep their distance (`PillSpec`), and the ribbon and status text never draw twice while a
/// contextual tab comes or goes. Captures of every pill and segmented control go to /tmp/arcus-pills/ (light and dark).
@MainActor
@Suite("PILLS pills and selection", .serialized)
struct PILLSUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-pills")

    /// Hosts `view` in an unshown window on the canvas colour (so the glass reads as it does over a drawing).
    static func host<V: View>(_ view: V, size: CGSize, dark: Bool, settle: Int = 6) async -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        ComponentThumbnail.renderSynchronously = true
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let h = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: Tokens.canvas))))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<settle { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
        return h
    }

    static func shoot(_ v: NSView, _ name: String) throws {
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    /// Light captures show the glass; dark ones the opaque surface (offscreen glass stays light).
    static func render<V: View>(_ view: V, _ size: CGSize, _ name: String, dark: Bool) async throws {
        GlassShieldView.forceOpaque = dark
        defer { GlassShieldView.forceOpaque = false }
        try shoot(await host(view.padding(10), size: size, dark: dark), "\(name)-\(dark ? "dark" : "light")")
    }

    /// A bookcase with its plan, front elevation and 3D view open, the front elevation active.
    static func furniture() throws -> (DocumentState, front: ElementID) {
        let m = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: m))
        let plan = try #require(m.views.first { $0.view?.kind.isPlan == true }?.id)
        let front = try #require(m.views.first { $0.view?.kind == .elevation && $0.name == "Front" }?.id ?? m.views.first { $0.view?.kind == .elevation }?.id)
        let v3 = try #require(m.views.first { $0.view?.kind == .threeD }?.id)
        state.openViews = [plan, front, v3]
        state.activeViewID = front
        return (state, front)
    }

    static func familyModel() -> FamilyEditorModel {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        let m = FamilyEditorModel(family: f, state: DocumentState(session: DocumentSession(model: BIMModel())), familyID: nil)
        m.openViews = Array(FamilyPreviewMode.allCases.prefix(3))
        m.view = m.openViews[1]
        return m
    }

    /// Runs the main run loop for `seconds` (SwiftUI commits updates and runs `onChange` from run-loop observers).
    static func spin(_ v: NSView, _ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)); v.layoutSubtreeIfNeeded() }
    }

    /// The hosted view's pixels (RGBA, at the window's backing scale).
    static func pixels(_ v: NSView) -> (data: [UInt8], width: Int)? {
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w)
    }

    /// Fraction of pixels that differ by more than a few levels between two captures of the same size.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var n = 0
        for i in stride(from: 0, to: a.count, by: 4) where abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 24 { n += 1 }
        return Double(n) / Double(a.count / 4)
    }

    @Test("Every pill and segmented control, light and dark")
    func captures() async throws {
        for dark in [false, true] {
            let (s, _) = try Self.furniture()
            try await Self.render(ViewTabPills(state: s), CGSize(width: 720, height: 52), "view-tabs", dark: dark)
            try await Self.render(FamilyViewTabPills(model: Self.familyModel()), CGSize(width: 560, height: 52), "family-view-tabs", dark: dark)
            s.ribbonTab = .create; s.ribbonShowsContextual = false
            s.ribbonTabsWidth = 900
            try await Self.render(RibbonTabsPill(state: s), CGSize(width: 760, height: 58), "ribbon-tabs", dark: dark)
            try await Self.render(ShellControlsPill(state: s, compact: false), CGSize(width: 320, height: 58), "controls", dark: dark)
            try await Self.render(BottomPill(state: s), CGSize(width: 1100, height: 58), "bottom", dark: dark)
            // The contextual tab of a sketch (Modify | Create Sweep) and the compact tab menu.
            CommandRouter(state: s).run(.furnitureSweep)
            s.ribbonShowsContextual = true
            try await Self.render(RibbonTabsPill(state: s), CGSize(width: 760, height: 58), "ribbon-tabs-contextual", dark: dark)
            try await Self.render(RibbonStrip(state: s), CGSize(width: 1100, height: 120), "ribbon-sketch", dark: dark)
            try await Self.render(OptionsBarView(state: s), CGSize(width: 760, height: 58), "options", dark: dark)
            s.ribbonTabsWidth = 260
            try await Self.render(RibbonTabsPill(state: s), CGSize(width: 300, height: 58), "ribbon-tabs-compact", dark: dark)
            s.cancelTool()
            let fm = Self.familyModel()
            try await Self.render(FamilyRibbonTabsPill(model: fm, available: 900), CGSize(width: 760, height: 58), "family-ribbon-tabs", dark: dark)
            try await Self.render(FamilyBottomPill(model: fm), CGSize(width: 700, height: 58), "family-bottom", dark: dark)
            // Component panel (segmented filters, chips) and its preview (3D/2D, Iso/Front/Side/Top).
            let cs = DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel())))
            let pm = COMPUITests.model(query: "hinge", select: FurnitureHardware.concealedHinge)
            try await Self.render(ComponentsPanel(state: cs, model: pm), CGSize(width: 340, height: 780), "components-panel", dark: dark)
            if let d = pm.selected {
                try await Self.render(ComponentPreview(model: pm, definition: d, height: 200), CGSize(width: 360, height: 270), "component-preview", dark: dark)
            }
            try await Self.render(ComponentLibraryView(state: cs, categories: [], furnitureItems: []), CGSize(width: 1120, height: 720), "component-library", dark: dark)
            // Home: the Recent filter with Furniture chosen, and the Start cards with one selected.
            let home = HomeModel(tab: .recent, readsDisk: false)
            home.recentFilter = .furniture
            home.selected = .furniture
            Self.renderHome(home, "home", dark: dark)
            // Segmented controls at each size, as dialogs and panels use them.
            var pick = 1
            let segs = VStack(alignment: .leading, spacing: 10) {
                PillSegmented(selection: Binding(get: { pick }, set: { pick = $0 }), [(0, "Model Objects"), (1, "Annotation Objects"), (2, "Imported Objects")])
                PillSegmented(selection: Binding(get: { pick }, set: { pick = $0 }), [(0, "Line"), (1, "Rectangle")], size: .small)
                PillSegmented(selection: Binding(get: { pick }, set: { pick = $0 }), [(0, "All"), (1, "Projects"), (2, "Furniture"), (3, "Families")], size: .large)
            }
            try await Self.render(segs, CGSize(width: 520, height: 140), "segmented", dark: dark)
        }
    }

    /// Home in its own window, as HomeRenderTests draws it.
    static func renderHome(_ model: HomeModel, _ name: String, dark: Bool) {
        let w = AppDelegate.makeHubWindow(model: model)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setContentSize(CGSize(width: 1040, height: 660))
        GlassShieldView.forceOpaque = dark
        defer { GlassShieldView.forceOpaque = false; w.close() }
        w.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        w.contentView?.layoutSubtreeIfNeeded()
        if let v = w.contentView?.superview ?? w.contentView { try? shoot(v, "\(name)-\(dark ? "dark" : "light")") }
    }

    @Test("The spec: concentric radii, capsule heights inside each pill")
    func spec() {
        #expect(PillSpec.height(in: CGFloat(ShellMetrics.arcus.pillHeight)) == PillSpec.shellItemHeight)
        #expect(PillSpec.height(in: CGFloat(ShellMetrics.arcus.viewTabsHeight)) == PillSpec.viewTabItemHeight)
        #expect(PillSpec.height(in: CGFloat(ShellMetrics.arcus.bottomHeight)) == PillSpec.shellItemHeight)
        #expect(PillSpec.radius(inside: 16) == 12 && PillSpec.radius(inside: 2) == 0)
        #expect(PillSpec.inset >= 3 && PillSpec.padding >= 12 && PillSpec.rowPadding >= 12)
        // A tab's width is its title plus 12 pt either side; the row adds the chosen tab's extra weight once.
        let w = RibbonTabMetrics.width("Create")
        #expect(abs(w - RibbonTabMetrics.text("Create", RibbonTabMetrics.font) - 24) < 0.01)
        #expect(RibbonTabMetrics.rowWidth(["Create", "Insert"]) >= RibbonTabMetrics.width("Create") + RibbonTabMetrics.width("Insert"))
    }

    @Test("Entering or leaving a sketch shows one ribbon: the sketch's panels replace the tab's, and back")
    func sketchRibbonDrawsOnce() async throws {
        let (s, front) = try Self.furniture()
        s.ribbonTab = .create; s.ribbonShowsContextual = false
        // The ribbon and the status line under the shell's own animations, as ContentAreaView applies them.
        func shell() -> some View {
            VStack(spacing: 0) {
                RibbonStrip(state: s).frame(height: CGFloat(ShellMetrics.arcus.ribbonHeight))
                BottomPill(state: s).frame(height: CGFloat(ShellMetrics.arcus.bottomHeight))
            }
            .modifier(ShellAnimations(state: s))
        }
        let size = CGSize(width: 1400, height: 150)
        let frames = RibbonFrames.of(s)
        frames.reset()
        let h = await Self.host(shell(), size: size, dark: false)
        Self.spin(h, 0.2)
        #expect(s.activeViewID == front)
        let createPanels = Set(frames.panels.keys)
        #expect(!createPanels.isEmpty && createPanels.allSatisfy { !$0.hasPrefix("c ") }, "Create tab: \(createPanels)")
        let create = try #require(Self.pixels(h))

        for step in ["enter", "leave"] {
            if step == "enter" {
                CommandRouter(state: s).run(.furnitureSweep)
                #expect(s.activeTool?.isSketchMode == true)
                // The contextual tab switches in the same update as the tool, not from an onChange a frame later inside
                // the shell's animation (where the Create panels and the sketch's cross-faded over each other).
                #expect(s.ribbonShowsContextual)
            } else {
                s.cancelTool()
            }
            Self.spin(h, 0.4)
            try Self.shoot(h, "transition-\(step)")
            let live = try #require(Self.pixels(h))
            // The ribbon that went through the change is exactly the one a fresh window draws: one set of panels and
            // one status line, nothing left over from before.
            frames.reset()
            let fresh = await Self.host(shell(), size: size, dark: false)
            Self.spin(fresh, 0.2)
            let panels = Set(frames.panels.keys)
            let d = Self.difference(live.data, try #require(Self.pixels(fresh)).data)
            #expect(d < 0.002, "\(step): the live ribbon differs from a fresh one in \(String(format: "%.2f", d * 100))% of pixels")
            if step == "enter" {
                #expect(panels.contains("c Draw") && panels.allSatisfy { $0.hasPrefix("c ") }, "sketch ribbon: \(panels.sorted())")
                #expect(Self.difference(create.data, live.data) > 0.01, "the sketch's ribbon looks like the Create tab's")
            } else {
                #expect(panels == createPanels, "after Cancel: \(panels.sorted())")
                #expect(Self.difference(create.data, live.data) < 0.002, "after Cancel the Create tab's ribbon is not back as it was")
            }
        }
    }
}
