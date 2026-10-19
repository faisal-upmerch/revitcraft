import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI
import ArcusViewport3D

/// FM3D: Furniture design in a real 3D view (Viewport3DHost offscreen, with mouse events): the Create tab's tools are
/// enabled in 3D and run on the work plane; a shelf is sketched in 3D; a panel is placed on a face; a selected panel
/// shows shape handles and dragging the top one changes Height. Renders to `/tmp/arcus-fm3d/` (light and dark): the
/// Create tab in 3D, the Options Bar with Placement Plane, and the 3D view with the shelf sketch and the handles.
@MainActor
@Suite("FM3D Furniture in 3D UI", .serialized)
struct FM3DUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm3d")
    static let inch = 0.0254
    /// Documents, hosts and windows stay alive for the run (the host's observers outlive a test).
    static var kept: [AnyObject] = []

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

    /// A document state with the bookcase's 3D Design view open in a live host, in a window.
    static func open3D() async throws -> (DocumentState, Viewport3DHost, NSWindow) {
        _ = NSApplication.shared
        let m = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: m))
        let v3 = try #require(m.views.first { $0.name == FurnitureDesignView.name })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = Viewport3DHost(state: state, viewID: v3.id)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        w.contentView = host
        state.canvases[v3.id] = host
        state.open(v3.id)
        for _ in 0..<200 { if host.viewport.statistics.triangles > 0 { break }; try await Task.sleep(for: .milliseconds(25)) }
        host.layoutSubtreeIfNeeded()
        host.viewport.zoomExtents(animated: false)
        try await Task.sleep(for: .milliseconds(100))
        kept += [state, host, w]
        return (state, host, w)
    }

    static func event(_ type: NSEvent.EventType, _ p: CGPoint, _ w: NSWindow, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                           context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    /// Moves to and clicks a view point through the 3D tool controller, as the viewport hands events to it.
    static func click(_ host: Viewport3DHost, _ p: CGPoint, _ w: NSWindow) {
        let t = host.tools!
        _ = t.viewport3DMouseMoved(event(.mouseMoved, p, w), at: p)
        _ = t.viewport3DMouseDown(event(.leftMouseDown, p, w), at: p)
        _ = t.viewport3DMouseUp(event(.leftMouseUp, p, w), at: p)
    }

    /// The 3D view with its tool overlay, as a PNG.
    static func capture(_ host: Viewport3DHost, _ name: String) throws {
        let size = host.bounds.size
        let img = try #require(host.viewport.snapshot(size: CGSize(width: size.width * 2, height: size.height * 2)))
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        let g = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        g.cgContext.draw(img, in: CGRect(origin: .zero, size: size))
        host.tools.drawOverlay(g.cgContext, bounds: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    @Test func toolsAreEnabledAndDrawIn3D() async throws {
        let (state, host, w) = try await Self.open3D()
        defer { w.orderOut(nil) }
        let r = CommandRouter(state: state)
        // Every Parts, Openings and Forms tool runs in 3D (those that act on a selection say so).
        let needsSelection: Set<CommandID> = [.furnitureEditProfile, .furnitureAttach, .furniturePickNewHost, .furnitureBlendEditTop, .furnitureBlendEditBase]
        for id in CommandRouter.fm3dToolIDs where FurniturePlacements.need(id) != nil && !needsSelection.contains(id) {
            #expect(r.disabledReason(id) == nil, "\(id): \(r.disabledReason(id) ?? "")")
        }
        #expect(r.disabledReason(.furnitureEditProfile) == "Select one panel.")
        // View support: section box, temporary hide/isolate, visual styles, Explode Parts, Joint.
        for id: CommandID in [.sectionBox, .visualStyleShaded, .visualStyleWireframe, .furnitureExplodeParts, .furnitureJoint, .furniture3DDesign] {
            #expect(r.disabledReason(id) == nil, "\(id): \(r.disabledReason(id) ?? "")")
        }
        // Panel: on the level's plan context, drawing on the 3D view's work plane.
        r.run(.furniturePanel)
        let panel = try #require(state.activeTool as? FurniturePanelTool)
        #expect(panel.ctx.furniture3D?.isPlan == true && panel.map?.plane == .xy)
        state.cancelTool()
        // Back: the Front elevation's plane.
        r.run(.furnitureBack)
        let back = try #require(state.activeTool as? FurnitureBackTool)
        #expect(state.model[back.ctx.viewID]?.name == "Front")
        state.cancelTool()
        // Edit Profile of a selected side: the elevation that looks at its face.
        let side = try #require(state.model.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel && $0.furniturePanel?.plane == .xy })
        state.session.selection.select([side.id])
        #expect(r.disabledReason(.furnitureEditProfile) == nil)
        r.run(.furnitureEditProfile)
        let ep = try #require(state.activeTool as? SketchTool)
        #expect(ep.isSketchMode && ep.ctx.furniture3D?.onFace == true && state.model[ep.ctx.viewID]?.view?.kind == .elevation)
        state.cancelTool()
        state.session.selection.clear()

        // Sketch a shelf in 3D: Pick Panels inside the carcass, at the shelf's height.
        let shelvesBefore = state.model.elements(.furnitureShelves).count
        r.run(.furnitureShelf)
        let sh = try #require(state.activeTool as? SketchTool)
        sh.setOption("fm4.offset", .double(14 * Self.inch))
        let vp = host.viewport
        let inside = try #require(vp.viewPoint(of: Vec3(0, 0.05, 14 * Self.inch)))
        Self.click(host, inside, w)
        #expect(sh.curves.count == 4, "\(sh.curves.count) lines; \(state.message)")
        try Self.capture(host, "fm3d-shelf-sketch-3d")
        #expect(sh.finish())
        state.cancelTool()
        #expect(state.model.elements(.furnitureShelves).count == shelvesBefore + 1)

        // Place a panel on a face: Pick a Face, then draw on the top's top face.
        let top = try #require(state.model.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
        let tb = try #require(FurniturePartFaces.box(top, state.model))
        r.run(.furniturePanel)
        host.tools.fm3d.pickingPlane = true
        let onTop = try #require(vp.viewPoint(of: Vec3(tb.center.x, tb.center.y, tb.max.z)))
        Self.click(host, onTop, w)
        let pt = try #require(state.activeTool as? FurniturePanelTool)
        #expect(pt.extent.basePlane == "Top" && abs(pt.extent.baseOffset) < 1e-6 && pt.extent.topPlane == nil, "\(pt.extent)")
        let panelsBefore = state.model.elements(.furniturePanels).count
        for x in [-6.0, 6.0] { Self.click(host, try #require(vp.viewPoint(of: Vec3(x * Self.inch, 0, tb.max.z))), w) }
        try Self.capture(host, "fm3d-panel-on-face-3d")
        state.cancelTool()
        let made = state.model.elements(.furniturePanels).filter { $0.furniturePanel?.base ?? 0 > tb.max.z - 1e-6 }
        #expect(state.model.elements(.furniturePanels).count == panelsBefore + 1 && made.count == 1)
    }

    @Test func shapeHandlesShowOnASelectedPanelAndStretchIt() async throws {
        let (state, host, w) = try await Self.open3D()
        defer { w.orderOut(nil) }
        let side = try #require(state.model.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel && $0.furniturePanel?.plane == .xy })
        state.session.selection.select([side.id])
        NSApp.appearance = NSAppearance(named: .aqua)
        host.appearance = NSAppearance(named: .aqua)
        host.viewport.viewDidChangeEffectiveAppearance()
        try await Task.sleep(for: .milliseconds(50))
        try Self.capture(host, "fm3d-shape-handles-light")
        let handles = host.tools.fm3d.handleHits
        #expect(handles.count >= 3, "\(handles.count) handles drawn")
        #expect(!host.tools.fm3d.dimLabels.isEmpty, "temporary dimensions shown")
        // Drag the top arrow up 40 points: the top face (on Top) moves the plane, so Height grows.
        let topHandle = try #require(handles.first { $0.handle.face == PartFaceRef(axis: .z, atMax: true) })
        let h0 = FurniturePlanes.positionsByName(state.model)["Top"] ?? 0
        let a = CGPoint(x: topHandle.rect.midX, y: topHandle.rect.midY)
        let t = host.tools!
        _ = t.viewport3DMouseDown(Self.event(.leftMouseDown, a, w), at: a)
        for k in 1...8 { let p = CGPoint(x: a.x, y: a.y + CGFloat(k) * 5); _ = t.viewport3DMouseDragged(Self.event(.leftMouseDragged, p, w), at: p) }
        try Self.capture(host, "fm3d-shape-handle-drag")
        let b = CGPoint(x: a.x, y: a.y + 40)
        _ = t.viewport3DMouseUp(Self.event(.leftMouseUp, b, w), at: b)
        let h1 = FurniturePlanes.positionsByName(state.model)["Top"] ?? 0
        #expect(h1 > h0 + 0.01, "Top \(h0) → \(h1)")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        host.appearance = NSAppearance(named: .darkAqua)
        host.viewport.viewDidChangeEffectiveAppearance()
        try Self.capture(host, "fm3d-shape-handles-dark")
        NSApp.appearance = nil
    }

    @Test func createTabAndOptionsBarRender() async throws {
        let (state, _, w) = try await Self.open3D()
        defer { w.orderOut(nil) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.ribbonTab = .create
            state.ribbonShowsContextual = false
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2200, height: 120), "fm3d-create-tab-3d-\(suffix)")
            CommandRouter(state: state).run(.furnitureShelf)
            try await Self.render(OptionsBarView(state: state), size: CGSize(width: 1300, height: 44), "fm3d-options-bar-\(suffix)")
            state.cancelTool()
        }
        NSApp.appearance = nil
        // View ▸ Create ▸ 3D View offers 3D Design; the contextual tab offers Edit Sketch for an extrusion.
        let create = try #require(RibbonContent.panels(.view, mode: .furniture).first { $0.title == "Create" })
        #expect(create.items.first { $0.id == .threeDView }?.variants.contains(.furniture3DDesign) == true)
    }
}
