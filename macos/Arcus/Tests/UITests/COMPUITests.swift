import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// COMP: the Component Library on screen, rendered offscreen to `/tmp/arcus-comp/` (light and dark): the docked
/// Components panel with a preview, the Component Browser layout, 2D and 3D previews from each view, and the dialogs.
/// The test also checks the commands, the dock and the Place Component tool on the sample cabinet.
@MainActor
@Suite("COMP component library UI", .serialized)
struct COMPUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-comp")

    static func render<V: View>(_ view: V, size: CGSize, _ name: String, dark: Bool) async throws {
        _ = NSApplication.shared
        ComponentThumbnail.renderSynchronously = true
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        h.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.appearance = h.appearance
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<8 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(40)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    static func state() throws -> DocumentState {
        DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel())))
    }

    /// A panel model on its own store (no user library, empty favorites).
    static func model(query: String = "", select name: String? = nil) -> ComponentPanelModel {
        let defaults = UserDefaults(suiteName: "comp-ui-tests")!
        defaults.removePersistentDomain(forName: "comp-ui-tests")
        let store = ComponentLibraryStore(defaults: defaults, directory: FileManager.default.temporaryDirectory.appendingPathComponent("comp-ui-none"), loadUser: false)
        let m = ComponentPanelModel(store: store)
        m.query = query
        if let name, let d = store.catalog.definition(named: name) { m.select(id: d.id) } else if let r = m.results.first { m.select(r) }
        store.toggleFavorite(m.selectedID ?? "")
        return m
    }

    @Test func rendersThePanelAndBrowser() async throws {
        let s = try Self.state()
        for dark in [false, true] {
            try await Self.render(ComponentsPanel(state: s, model: Self.model(query: "hinge", select: FurnitureHardware.concealedHinge)), size: CGSize(width: 320, height: 780), "panel-docked", dark: dark)
            let list = Self.model(query: "drawer slide 450")
            list.gridView = false
            try await Self.render(ComponentsPanel(state: s, model: list), size: CGSize(width: 320, height: 780), "panel-list", dark: dark)
            try await Self.render(ComponentsPanel(state: s, model: Self.model(query: "xyzzy")), size: CGSize(width: 320, height: 520), "panel-empty", dark: dark)
            let browser = Self.model(select: FurnitureHardware.barPull)
            browser.category = .handles
            try await Self.render(ComponentsPanel(state: s, layout: .browser, model: browser), size: CGSize(width: 1180, height: 720), "browser", dark: dark)
        }
    }

    @Test func rendersPreviews() async throws {
        let m = Self.model(select: FurnitureHardware.barPull)
        let d = try #require(m.selected)
        for v in ComponentPreviewView.allCases {
            m.setPreview(v)
            m.previewMode = .threeD
            try await Self.render(ComponentPreview(model: m, definition: d, height: 220).padding(10), size: CGSize(width: 340, height: 280), "preview-3d-\(v.rawValue.lowercased())", dark: false)
            m.previewMode = .plan
            try await Self.render(ComponentPreview(model: m, definition: d, height: 220).padding(10), size: CGSize(width: 340, height: 280), "preview-2d-\(v.rawValue.lowercased())", dark: v == .top)
        }
        // A thumbnail from real geometry has pixels.
        let img = try #require(ComponentRenderer.shaded(d, type: d.defaultType!.name, yaw: ShadedFamilyRendererAngles.yaw, pitch: ShadedFamilyRendererAngles.pitch, width: 120, height: 100))
        let rep = NSBitmapImageRep(cgImage: img)
        var opaque = 0
        for x in stride(from: 0, to: 120, by: 4) { for y in stride(from: 0, to: 100, by: 4) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 } }
        #expect(opaque > 10)
    }

    @Test func rendersTheDialogs() async throws {
        let s = try Self.state()
        for entry in QAHarness.compDialogCatalog(s) {
            for dark in [false, true] {
                let size = try await DialogRenderTests.render(COMPDialogHost(state: s, dialog: { if case .comp(let d) = entry.kind { return d }; return .update }()), entry.name, dark: dark)
                #expect(size.width >= 420 && size.height > 100, "\(entry.name): \(size)")
            }
        }
    }

    @Test func commandsDockAndTool() throws {
        _ = NSApplication.shared
        let s = try Self.state()
        let router = CommandRouter(state: s)
        let panel = ComponentPanelModel.of(s)
        #expect(!DockVisibility(s).trailing || s.workspace == .macSpacious)
        router.run(.components)
        #expect(panel.isShown && DockVisibility(s).trailing)
        #expect(router.compDisabledReason(.componentPlace) != nil, "nothing picked yet")
        panel.select(id: try #require(ComponentLibrary.component(named: FurnitureHardware.barPull)).id)
        let front = try #require(s.model.views.first { $0.name == "Front" && $0.view?.kind == .elevation })
        s.open(front.id)
        #expect(router.compDisabledReason(.componentPlace) == nil)
        router.run(.componentPlace)
        let tool = try #require(s.activeTool as? ComponentPlaceTool)
        // Pointing at the left door in the front elevation: the door's front face; a click places a bar pull on it.
        let door = try #require(s.model.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .door }.min { $0.id < $1.id })
        let face = try #require(ComponentPlacement.face(door, .front, s.model))
        let map = try #require(ComponentViewMap(s.model[front.id]?.view))
        let p = map.toView(face.origin)
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
        let placed = s.model.hosted(by: door.id).filter { $0.params[ComponentInstanceKeys.face] != nil }
        #expect(placed.count == 1, "\(s.session.lastError?.message ?? "")")
        #expect(placed.first.flatMap { ComponentSettings($0) }?.face == .front)
        // One-click actions show for the door.
        s.session.selection.select([door.id])
        #expect(router.compDisabledReason(.componentAddHinges) == nil)
        router.run(.componentAddHinges)
        #expect(s.presented == .comp(.action(.hinges, [door.id])))
        router.run(.components)
        #expect(!panel.isShown)
    }
}
