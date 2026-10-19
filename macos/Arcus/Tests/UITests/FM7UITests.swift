import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
@testable import ArcusUI

/// FM7: fabrication on screen, rendered offscreen to `/tmp/arcus-fm7/` (light and dark): the Fabricate and Manage
/// ribbons, Stock Sheets, Hardware Catalog, CNC Export and Check Parts, and the commands that open the schedules and
/// make the Nesting views. The test checks the commands, panels and routing.
@MainActor
@Suite("FM7 fabrication UI", .serialized)
struct FM7UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm7")

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

    @Test func commandsOpenTheSchedulesAndNesting() throws {
        _ = NSApplication.shared
        let state = DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel())))
        let router = CommandRouter(state: state)
        for (cmd, kind) in [(CommandID.furniturePartList, ScheduleKind.partList), (.furnitureHardwareSchedule, .hardwareSchedule),
                            (.furnitureMaterialTakeoff, .materialTakeoff), (.furnitureEdgeBanding, .edgeBanding), (.furnitureCost, .costSummary)] {
            #expect(router.fm7DisabledReason(cmd) == nil)
            router.run(cmd)
            #expect(state.activeViewID.flatMap { state.model[$0]?.schedule?.kind } == kind, "\(cmd)")
        }
        router.run(.furnitureNesting)
        #expect(state.activeViewID.flatMap { state.model[$0]?.view?.kind } == .nesting)
        #expect(FurnitureNestingViews.views(state.model).count == 3)
        router.run(.furnitureShopDrawings)
        #expect(state.activeViewID.flatMap { state.model[$0]?.sheet?.number } == "F101")
        router.run(.furnitureStockSheets)
        #expect(state.presented == .fm7(.stockSheets))
        state.presented = nil
        router.run(.furnitureCheckParts)
        #expect(state.presented == .fm7(.checkParts))
        state.presented = nil
        // Outside Furniture documents.
        let project = DocumentState(session: DocumentSession(model: BIMModel()))
        #expect(CommandRouter(state: project).fm7DisabledReason(.furniturePartList) == "Only in Furniture documents.")
        // The ribbon.
        let fab = RibbonContent.panels(.fabricate, mode: .furniture)
        #expect(fab.first { $0.title == "Part List" }?.items.map(\.id) == [.furniturePartList, .furnitureHardwareSchedule, .furnitureMaterialTakeoff, .furnitureEdgeBanding, .furnitureCost])
        #expect(fab.first { $0.title == "Nesting" }?.items.map(\.id) == [.furnitureNesting, .furnitureStockSheets])
        #expect(fab.first { $0.title == "Output" }?.items.map(\.id) == [.furnitureCNCExport, .furnitureShopDrawings, .furnitureExplodeParts, .furnitureCheckParts])
        #expect(RibbonContent.panels(.manage, mode: .furniture).first { $0.title == "Fabrication" }?.items.map(\.id).contains(.furnitureHardwareCatalog) == true)
    }

    @Test func dialogsAndRibbonRender() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.baseCabinetModel())
        let state = DocumentState(session: DocumentSession(model: model))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.ribbonTab = .fabricate
            state.ribbonShowsContextual = false
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-ribbon-fabricate-\(suffix)")
            state.ribbonTab = .manage
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-ribbon-manage-\(suffix)")
            try await Self.render(StockSheetsDialog(state: state), size: CGSize(width: 960, height: 560), "ui-stock-sheets-\(suffix)")
            try await Self.render(HardwareCatalogDialog(state: state), size: CGSize(width: 940, height: 640), "ui-hardware-catalog-\(suffix)")
            try await Self.render(CNCExportDialog(state: state), size: CGSize(width: 900, height: 640), "ui-cnc-export-\(suffix)")
            try await Self.render(CheckPartsDialog(state: state), size: CGSize(width: 760, height: 520), "ui-check-parts-\(suffix)")
        }
        NSApp.appearance = nil
    }
}
