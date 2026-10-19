import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
@testable import ArcusUI

/// FMG1: the Furniture parts and flex gaps on screen, rendered offscreen to `/tmp/arcus-fmg1/` (light and dark): the
/// Blend sketch's ribbon with Edit Top (base) and Edit Base (top) and the base dimmed under the top, a selected blend's
/// Mode panel, the Sweep's Options Bar in the Front elevation (Pick Path, Offset), a rail's Properties (y Justification,
/// Start and End Cut) and a locked dimension to a shelf face in the Front elevation.
@MainActor
@Suite("FMG1 parts and flex UI", .serialized)
struct FMG1UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fmg1")

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

    @discardableResult
    static func draw(_ m: BIMModel, _ view: Element, _ name: String, overlay: [GPrimitive] = []) -> Int {
        var g = ViewGraphicsBuilder(model: m, view: view).build()
        if !overlay.isEmpty { g.items.append(GItem(elementID: nil, category: .genericModels, layer: .overlay, primitives: overlay, hitPolygons: [])) }
        guard let img = RasterExporter.render(g, pixelWidth: 1400, showOverlays: !overlay.isEmpty), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    @Test func blendSweepRailAndDimensionScreensRender() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: model))
        let plan = try #require(model.views.first { $0.view?.kind == .floorPlan })
        let front = try #require(model.views.first { $0.name == "Front" })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            // Blend: the base, then Edit Top.
            state.open(plan.id)
            CommandRouter(state: state).run(.furnitureBlend)
            let blend = try #require(state.activeTool as? SketchTool)
            blend.setOption("mode", .text("Rectangle"))
            for p in [Vec2(-0.3, -0.12), Vec2(0.3, 0.12)] { blend.pointerDown(ToolInput(point: p, rawPoint: p)) }
            state.toolChangedState()
            state.ribbonShowsContextual = true
            #expect(RibbonContent.fmg1ToolPanels(blend).first?.items.map(\.id) == [.furnitureBlendEditTop])
            #expect(RibbonContent.contextualTitle(state) == "Modify | Create Blend Base Boundary", "\(RibbonContent.contextualTitle(state) ?? "")")
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-blend-base-ribbon-\(suffix)")
            CommandRouter(state: state).run(.furnitureBlendEditTop)
            #expect(blend.isEditingBlendTop)
            blend.setOption("mode", .text("Rectangle"))
            for p in [Vec2(-0.12, -0.05), Vec2(0.12, 0.05)] { blend.pointerDown(ToolInput(point: p, rawPoint: p)) }
            blend.pointerMoved(ToolInput(point: Vec2(0.2, 0.1), rawPoint: Vec2(0.2, 0.1)))
            state.toolChangedState()
            #expect(RibbonContent.fmg1ToolPanels(blend).first?.items.map(\.id) == [.furnitureBlendEditBase])
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-blend-top-ribbon-\(suffix)")
            try await Self.render(OptionsBarView(state: state), size: CGSize(width: 1100, height: 44), "ui-blend-options-\(suffix)")
            if suffix == "light" { Self.draw(state.model, state.model[plan.id]!, "fmg1-blend-top-sketch", overlay: blend.preview.primitives) }
            #expect(blend.finish())
            // The selected blend: Edit Top and Edit Base on its contextual tab.
            #expect(state.activeTool == nil)
            let id = try #require(state.model.elements(.furnitureForms).last?.id)
            state.session.selection.select([id])
            state.ribbonShowsContextual = true
            #expect(RibbonContent.fmg1SelectionPanels(state).first?.items.map(\.id) == [.furnitureBlendEditTop, .furnitureBlendEditBase])
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-blend-selected-ribbon-\(suffix)")
            state.session.selection.clear()
            // Sweep in the Front elevation.
            state.open(front.id)
            #expect(CommandRouter(state: state).disabledReason(.furnitureSweep) == nil, "sweeps sketch in elevations")
            CommandRouter(state: state).run(.furnitureSweep)
            let sweep = try #require(state.activeTool as? SketchTool)
            for p in [Vec2(-0.35, 0.6), Vec2(0, 0.7), Vec2(0.35, 0.6)] { sweep.pointerDown(ToolInput(point: p, rawPoint: p)) }
            state.toolChangedState()
            state.ribbonShowsContextual = true
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-sweep-front-ribbon-\(suffix)")
            try await Self.render(OptionsBarView(state: state), size: CGSize(width: 1100, height: 44), "ui-sweep-front-options-\(suffix)")
            state.cancelTool()
        }
        NSApp.appearance = nil
        // A locked dimension from the Top to a shelf's top face, before and after Height changes.
        let s = state.session
        let shelf = try #require(s.model.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .shelf })
        let top = try #require(FurniturePlanes.names(s.model).first { $0.value == "Top" }?.key)
        var dim: ElementID?
        s.perform("Dimension") { tx in
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [GeometryReference(top, .location), .partFace(shelf.id, PartFaceRef(axis: .z, atMax: true))],
                                                                        linePoint: Vec2(22 * 0.0254, 0))), typeID: tx.model.types(for: .dimensions).first?.id, ownerViewID: front.id)
        }
        s.perform("Lock") { tx in tx.update(dim!) { $0.dimension?.locked = true } }
        #expect(Self.draw(s.model, s.model[front.id]!, "fmg1-locked-dimension") > 5)
        let before = s.model[shelf.id]?.furnitureShelf?.elevation ?? 0
        s.perform("Height") { tx in try FurnitureParameters.setValue("Height", .double(80 * 0.0254), in: tx) }
        #expect(abs((s.model[shelf.id]?.furnitureShelf?.elevation ?? 0) - before - 8 * 0.0254) < 1e-6, "the locked shelf follows the Top")
        #expect(Self.draw(s.model, s.model[front.id]!, "fmg1-locked-dimension-flexed") > 5)
    }
}
