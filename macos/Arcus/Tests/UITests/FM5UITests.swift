import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// FM5: the Openings panel on Create, Hardware on Create ▸ Model, the contextual Modify | Doors, Modify | Drawers and
/// Modify | Bay tabs, and the Door and Drawer tools' Options Bars, rendered offscreen to `/tmp/arcus-fm5/` (light and
/// dark); the test checks the panels, their commands and symbols.
@MainActor
@Suite("FM5 ribbon", .serialized)
struct FM5UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm5")

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

    @Test func openingsPanelContextualTabsAndOptionsBars() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.baseCabinetModel())
        let state = DocumentState(session: DocumentSession(model: model))
        let create = RibbonContent.panels(.create, mode: .furniture)
        let openings = try #require(create.first { $0.title == "Openings" })
        #expect(openings.items.map(\.id) == [.furnitureBay, .furnitureBaySeparator, .furnitureBayDivide, .furnitureBayTag, .furnitureDoor, .furnitureDrawer, .furnitureFlap])
        #expect(create.first { $0.title == "Model" }?.items.map(\.id).contains(.furnitureHardware) == true)
        // Every FM5 command has a real symbol and a help line.
        for c in CommandCatalog.all where CommandRouter.fm5IDs.contains(c.id) {
            #expect(NSImage(systemSymbolName: c.symbol, accessibilityDescription: nil) != nil, "\(c.symbol)")
            #expect(!c.help.isEmpty)
        }
        let front = try #require(model.views.first { $0.view?.kind == .elevation && $0.name == "Front" })
        state.open(front.id)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.ribbonTab = .create
            state.ribbonShowsContextual = false
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2200, height: 120), "ui-ribbon-create-\(suffix)")
            // A selected door: Modify | Doors with Flip Hinge and Pick New Host.
            let door = try #require(model.elements(.furnitureFronts).first { $0.furnitureFront?.kind == .door })
            state.session.selection.select([door.id])
            state.ribbonShowsContextual = true
            #expect(RibbonContent.contextualTitle(state) == "Modify | Doors")
            let items = RibbonContent.selectionPanel(state)?.items.map(\.id) ?? []
            #expect(items.contains(.furnitureFlipHinge) && items.contains(.furniturePickNewHost) && items.contains(.furnitureSelectHardware))
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2200, height: 120), "ui-modify-doors-\(suffix)")
            // Drawers: Modify | Drawers (no Flip Hinge).
            let drawers = model.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .drawer }.map(\.id)
            state.session.selection.select(drawers)
            #expect(RibbonContent.contextualTitle(state) == "Modify | Drawers")
            let drawerItems = RibbonContent.selectionPanel(state)?.items.map(\.id) ?? []
            #expect(drawerItems.contains(.furniturePickNewHost) && !drawerItems.contains(.furnitureFlipHinge))
            // A bay: Bay Divide.
            let bay = try #require(model.elements(.furnitureBays).first { $0.furnitureBay?.division != nil })
            state.session.selection.select([bay.id])
            #expect(RibbonContent.contextualTitle(state) == "Modify | Bays")
            let bayItems = RibbonContent.selectionPanel(state)?.items.map(\.id) ?? []
            #expect(bayItems.contains(.furnitureRemoveDivide))
            state.session.selection.clear()
            // The Door and Drawer tools: Modify | Place Door, hinge side, Tag on Placement; the Type Selector shows fronts.
            CommandRouter(state: state).run(.furnitureDoor)
            #expect(state.activeTool is FurnitureFrontTool)
            #expect(RibbonContent.contextualTitle(state) == "Modify | Place Door")
            #expect(fm5PropertiesCategory(.furnitureDoor) == .furnitureFronts)
            try await Self.render(VStack(spacing: 0) { RibbonView(state: state); OptionsBarView(state: state) }, size: CGSize(width: 2200, height: 170), "ui-place-door-\(suffix)")
            state.cancelTool()
            CommandRouter(state: state).run(.furnitureDrawer)
            #expect(state.activeTool?.options.map(\.id) == ["count", "tag"])
            try await Self.render(VStack(spacing: 0) { RibbonView(state: state); OptionsBarView(state: state) }, size: CGSize(width: 2200, height: 170), "ui-place-drawer-\(suffix)")
            state.cancelTool()
        }
        NSApp.appearance = nil
        // Drawers need the Front elevation; projects grey every FM5 tool out.
        if let plan = model.views.first(where: { $0.view?.kind == .floorPlan }) {
            state.open(plan.id)
            #expect(CommandRouter(state: state).disabledReason(.furnitureDrawer) == "Open the Front or Back elevation.")
            #expect(CommandRouter(state: state).disabledReason(.furnitureBay) == nil, "top-access bays in plan")
        }
        let project = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.empty, units: .imperial).0))
        #expect(CommandRouter(state: project).disabledReason(.furnitureDoor) == "Only in Furniture documents.")
    }
}
