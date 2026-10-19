import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
@testable import ArcusUI

/// FM6: joints on screen, rendered offscreen to `/tmp/arcus-fm6/` (light and dark): the bookcase's section and side
/// elevation at Fine (dados, the back's groove, hidden dowel and shelf-pin holes) and Coarse, a box of panels in plan,
/// the Joint tool's markers with a picked joint and its Options Bar, the ribbon's Joints panels and the Joint Rules
/// dialog. The test checks the commands and panels are there and that the drawings draw.
@MainActor
@Suite("FM6 joints UI", .serialized)
struct FM6UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm6")
    static let inch = 0.0254

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

    /// A view's drawing (plus extra overlay primitives) as a PNG; the number of items drawn.
    @discardableResult
    static func draw(_ m: BIMModel, _ view: Element, _ name: String, overlay: [GPrimitive] = []) -> Int {
        var g = ViewGraphicsBuilder(model: m, view: view).build()
        if !overlay.isEmpty { g.items.append(GItem(elementID: nil, category: .genericModels, layer: .overlay, primitives: overlay, hitPolygons: [])) }
        guard let img = RasterExporter.render(g, pixelWidth: 1600, showOverlays: !overlay.isEmpty), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    /// The sample bookcase with its second shelf fixed (dadoed into the sides).
    static func bookcase() throws -> BIMModel {
        let m = try #require(FurnitureSamples.bookcaseModel())
        let tx = TransactionContext(model: m, name: "Fix")
        let shelves = m.elements(.furnitureShelves).filter { $0.furnitureShelf?.adjustable == true }.sorted { $0.id < $1.id }
        tx.update(shelves[1].id) { $0.furnitureShelf?.adjustable = false; $0.furnitureShelf?.pins = nil }
        return try tx.commit().model
    }

    static func section(_ m: BIMModel, frontToBack: Bool, detail: DetailLevel) throws -> (BIMModel, Element) {
        let tx = TransactionContext(model: m, name: "Section")
        var v = ViewData(kind: .section, scale: 6)
        v.planeOrigin = frontToBack ? Vec3(0, -0.01, 0) : Vec3(-0.30, 0, 0)
        v.viewDirection = frontToBack ? Vec2(0, 1) : Vec2(1, 0)
        v.farClip = 2
        v.detailLevel = detail
        let id = tx.create(.views, name: "Section", data: .view(v))
        let r = try tx.commit().model
        return (r, r[id]!)
    }

    @Test func jointDrawingsDraw() throws {
        let m = try Self.bookcase()
        for (front, label) in [(true, "front"), (false, "side")] {
            for d in [DetailLevel.coarse, .fine] {
                let (sm, sv) = try Self.section(m, frontToBack: front, detail: d)
                #expect(Self.draw(sm, sv, "fm6-bookcase-section-\(label)-\(d.rawValue.lowercased())") > 5)
            }
        }
        let tx = TransactionContext(model: m, name: "Fine")
        let left = try #require(m.views.first { $0.name == "Left" })
        tx.update(left.id) { $0.view?.detailLevel = .fine; $0.view?.scale = 8 }
        let fm = try tx.commit().model
        #expect(Self.draw(fm, fm[left.id]!, "fm6-bookcase-left-fine") > 10)
        // A box drawn as a rectangle of panels: corners resolved in plan.
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Box"))
        _ = s.perform("Rectangle") { tx in
            _ = try FurniturePartOperations.createPanelRectangle(Rect2(min: Vec2(-15 * Self.inch, -8 * Self.inch), max: Vec2(15 * Self.inch, 8 * Self.inch)),
                                                                 extent: PartExtent(topPlane: nil, height: 24 * Self.inch), in: tx)
        }
        let plan = try #require(s.model.views.first { $0.view?.kind == .floorPlan })
        #expect(Self.draw(s.model, plan, "fm6-box-plan") > 3)
        // Mitred corners.
        _ = s.perform("Miter") { tx in for j in FurnitureJoints.joints(tx.model) { try FurnitureJointOperations.set(j.key, type: .miter, in: tx) } }
        #expect(Self.draw(s.model, plan, "fm6-box-plan-mitred") > 3)
    }

    @Test func jointToolRibbonOptionsBarAndJointRulesRender() async throws {
        _ = NSApplication.shared
        let model = try Self.bookcase()
        let state = DocumentState(session: DocumentSession(model: model))
        // Ribbon: Fabricate ▸ Joints, Manage ▸ Joints, Modify ▸ Geometry ▸ Joint.
        let fab = RibbonContent.panels(.fabricate, mode: .furniture)
        let joints = try #require(fab.first { $0.title == "Joints" })
        #expect(joints.items.map(\.id) == [.furnitureJoint, .furnitureJointRules, .furnitureAllowJoin, .furnitureDisallowJoin])
        #expect(RibbonContent.panels(.manage, mode: .furniture).contains { $0.title == "Joints" })
        let geometry = try #require(RibbonContent.panels(.modify, mode: .furniture).first { $0.title == "Geometry" })
        #expect(geometry.items.map(\.id).contains(.furnitureJoint) && !geometry.items.map(\.id).contains(.joinGeometry))
        #expect(CommandCatalog.info(.furnitureJoint).aliases == ["JT"])
        let front = try #require(model.views.first { $0.name == "Front" })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.ribbonTab = .fabricate
            state.ribbonShowsContextual = false
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-ribbon-fabricate-\(suffix)")
            // The Joint tool: Modify | Joints, the Options Bar for a picked joint.
            state.open(front.id)
            CommandRouter(state: state).run(.furnitureJoint)
            let tool = try #require(state.activeTool as? FurnitureJointTool)
            let map = try #require(FurnitureSketchMap.of(front.view))
            let sides = model.elements(.furniturePanels).filter { $0.furniturePanel?.role == .panel }.map(\.id)
            let top = try #require(model.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
            let j = try #require(FurnitureJoints.joint(sides[0], top.id, state.model))
            let p = map.project(j.marker)
            tool.ctx.pixel = 0.002
            tool.pointerDown(ToolInput(point: p, rawPoint: p))
            tool.pointerMoved(ToolInput(point: p, rawPoint: p))
            state.toolChangedState()
            state.ribbonShowsContextual = true
            #expect(RibbonContent.contextualTitle(state) == "Modify | Joints")
            try await Self.render(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-modify-joints-\(suffix)")
            try await Self.render(OptionsBarView(state: state), size: CGSize(width: 1100, height: 44), "ui-joint-options-\(suffix)")
            if suffix == "light" { Self.draw(state.model, state.model[front.id]!, "fm6-joint-markers-front", overlay: tool.preview.primitives) }
            state.cancelTool()
            // Joint Rules.
            try await Self.render(FurnitureJointRulesDialog(state: state), size: CGSize(width: 1230, height: 640), "ui-joint-rules-\(suffix)")
        }
        NSApp.appearance = nil
    }
}
