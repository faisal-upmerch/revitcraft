import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// FM4: the Furniture mode ribbon with the Parts and Forms panels, the contextual tab of a selected panel and of the
/// Panel and Shelf tools, rendered offscreen to `/tmp/arcus-fm4/` (light and dark); the test checks the panels and their
/// commands are there.
@MainActor
@Suite("FM4 ribbon", .serialized)
struct FM4UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm4")

    static func render<V: View>(_ view: V, size: CGSize, _ name: String) async throws {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<6 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    @Test func createTabHasPartsAndFormsAndContextualTabsWork() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: model))
        #expect(state.mode == .furniture)
        let create = RibbonContent.panels(.create, mode: .furniture)
        let parts = try #require(create.first { $0.title == "Parts" })
        #expect(parts.items.map(\.id) == [.furniturePanel, .furnitureShelf, .furnitureTop, .furnitureBack, .furnitureDivider, .furniturePlinth, .furnitureLeg, .furnitureRail, .furnitureEdgeProfile])
        let forms = try #require(create.first { $0.title == "Forms" })
        #expect(forms.items.map(\.id).contains(.furnitureCushion) && !forms.items.map(\.id).contains(.modelInPlace))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.ribbonTab = .create
            state.ribbonShowsContextual = false
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-ribbon-create-\(suffix)")
            // A selected side: Modify | Panels.
            let side = try #require(model.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel })
            state.session.selection.select([side.id])
            state.ribbonShowsContextual = true
            #expect(RibbonContent.contextualTitle(state) == "Modify | Panels")
            let items = RibbonContent.selectionPanel(state)?.items.map(\.id) ?? []
            #expect(items.contains(.furnitureEditProfile) && items.contains(.furnitureAttach) && items.contains(.furniturePanelOpening))
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-modify-panels-\(suffix)")
            state.session.selection.clear()
            // The Panel tool: Modify | Place Panel with its draw modes and options.
            if let plan = model.views.first(where: { $0.view?.kind == .floorPlan }) {
                state.open(plan.id)
                CommandRouter(state: state).run(.furniturePanel)
                #expect(state.activeTool is FurniturePanelTool)
                #expect(RibbonContent.contextualTitle(state) == "Modify | Place Panel")
                try await Self.render(VStack(spacing: 0) { RibbonView(state: state); OptionsBarView(state: state) }, size: CGSize(width: 2000, height: 170), "ui-place-panel-\(suffix)")
                state.cancelTool()
                CommandRouter(state: state).run(.furnitureShelf)
                #expect(state.activeTool?.isSketchMode == true)
                try await Self.render(VStack(spacing: 0) { RibbonView(state: state); OptionsBarView(state: state) }, size: CGSize(width: 2000, height: 170), "ui-sketch-shelf-\(suffix)")
                state.cancelTool()
            }
        }
        NSApp.appearance = nil
        // Projects grey the part tools out.
        let project = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.empty, units: .imperial).0))
        #expect(CommandRouter(state: project).disabledReason(.furniturePanel) == "Only in Furniture documents.")
    }
}
