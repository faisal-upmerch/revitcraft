import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusOutput
@testable import ArcusApplication
@testable import ArcusUI

/// STAIR: stairs on screen, rendered offscreen to `/tmp/arcus-stair/`: each stair kind in plan at its base and upper
/// level and in section (3D renders: Viewport3DTests/STAIR3DRenderTests). The test checks that every drawing draws; the PNGs are for visual review.
@MainActor
@Suite("STAIR stairs UI", .serialized)
struct STAIRUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-stair")

    /// A view's drawing as a PNG; the number of items drawn.
    @discardableResult
    static func draw(_ m: BIMModel, _ view: Element, _ name: String, overlay: [GPrimitive] = [], width: Int = 1400) -> Int {
        var g = ViewGraphicsBuilder(model: m, view: view).build()
        if !overlay.isEmpty { g.items.append(GItem(elementID: nil, category: .genericModels, layer: .overlay, primitives: overlay, hitPolygons: [])) }
        guard let img = RasterExporter.render(g, pixelWidth: width, showOverlays: !overlay.isEmpty), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    /// A section view looking along `direction` through `origin`.
    static func section(_ origin: Vec3, _ direction: Vec2, crop: Rect2, scale: Int = 50) -> Element {
        var v = ViewData(kind: .section, scale: scale)
        v.planeOrigin = origin; v.viewDirection = direction; v.farClip = 20
        v.cropRegion = crop
        v.detailLevel = .fine
        return Element(id: ElementID(UInt64.max - 70), category: .views, name: "Section", data: .view(v))
    }

    static func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let session = DocumentSession(model: m)
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        return (ctx, ids)
    }

    static func click(_ tool: some InteractiveTool, _ p: Vec2) {
        let i = ToolInput(point: p, rawPoint: p)
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    /// Plan crop around a rectangle.
    static func cropPlan(_ m: BIMModel, _ ids: ProjectTemplates.Ids, level: Int, _ r: Rect2) -> Element {
        var v = m[ids.planViews[ids.levels[level]]!]!
        v.view?.cropRegion = r
        v.view?.cropActive = true
        v.view?.scale = 50
        return v
    }

    /// The audit set, as the older stair tools made them (shape-only stairs with a railing each side): straight, L
    /// and U, and a multistory straight stair, in every view. They read as component stairs now.
    @Test func auditRenders() throws {
        let (ctx, ids) = Self.context()
        ctx.session.perform("Older stairs") { tx in
            for (k, shape) in [StairShape.straight, .lShaped, .uShaped, .straight].enumerated() {
                var s = StairData(shape: shape, origin: Vec2([0.0, 6, 12, 20][k], 0), direction: .pi / 2, width: 1.1, topLevelID: ids.levels[1])
                if k == 3 { s.multistoryTopLevelID = ids.levels[2] }
                let sid = tx.create(.stairs, data: .stair(s), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
                for left in [true, false] {
                    var r = RailingData(path: [])
                    r.followsHost = true; r.hostSideLeft = left
                    tx.create(.railings, data: .railing(r), typeID: ids.systemTypes["Railing"], levelID: ids.levels[0], hostID: sid)
                }
            }
        }
        let m = ctx.model
        #expect(m.elements(.stairs).count == 4)
        let crop = Rect2(min: Vec2(-3, -3), max: Vec2(24, 10))
        #expect(Self.draw(m, Self.cropPlan(m, ids, level: 0, crop), "audit-plan-L1") > 0)
        #expect(Self.draw(m, Self.cropPlan(m, ids, level: 1, crop), "audit-plan-L2") > 0)
        for (k, name) in ["straight", "l", "u", "multistory"].enumerated() {
            let x = [0.0, 6, 12, 20][k]
            let r = Rect2(min: Vec2(x - 3.5, -1.5), max: Vec2(x + 4, 7.5))
            Self.draw(m, Self.cropPlan(m, ids, level: 0, r), "audit-\(name)-L1", width: 900)
            Self.draw(m, Self.cropPlan(m, ids, level: 1, r), "audit-\(name)-L2", width: 900)
        }
        #expect(Self.draw(m, Self.section(Vec3(0, -4, 0), Vec2(0, 1), crop: Rect2(min: Vec2(-3, -1), max: Vec2(24, 9))), "audit-section-across") > 0)
        #expect(Self.draw(m, Self.section(Vec3(0.1, 0, 0), Vec2(1, 0), crop: Rect2(min: Vec2(-12, -1), max: Vec2(12, 9))), "audit-section-along") > 0)
    }

    /// Stairs of every kind drawn with Create Stair: straight; L and U from two runs with automatic landings; Full-Step
    /// spiral; L- and U-Shape winders; a sketched run. Returns the model and the plan crop of each.
    static func componentStairs(type: String? = nil) throws -> (BIMModel, ProjectTemplates.Ids, [(String, Rect2)]) {
        let (ctx, ids) = context()
        if let type, let t = ctx.model.types(for: .stairs).first(where: { $0.name == type }) { ctx.currentTypes[.stairs] = t.id }
        var crops: [(String, Rect2)] = []
        func make(_ name: String, at x: Double, _ draw: (StairTool) throws -> Void) throws {
            let t = StairTool(ctx: ctx)
            try draw(t)
            #expect(t.finish(), "\(name) did not finish")
            crops.append((name, Rect2(min: Vec2(x - 3.5, -2), max: Vec2(x + 4.5, 8))))
        }
        let tread = 0.28
        try make("straight", at: 0) { t in click(t, Vec2(0, 0)); click(t, Vec2(0, 22 * tread)) }
        try make("l", at: 8) { t in
            click(t, Vec2(8, 0)); click(t, Vec2(8, 11 * tread))
            let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(-1, 0), tolerance: 1e-6) })
            click(t, c.point); click(t, c.point + Vec2(-10 * tread, 0))
        }
        try make("u", at: 16) { t in
            click(t, Vec2(16, 0)); click(t, Vec2(16, 11 * tread))
            let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(0, -1), tolerance: 1e-6) && $0.point.x < 16 })
            click(t, c.point); click(t, c.point + Vec2(0, -10 * tread))
        }
        try make("spiral", at: 24) { t in
            t.choose(StairTool.RunMode.fullStepSpiral)
            click(t, Vec2(24, 3)); click(t, Vec2(25.6, 3))
        }
        try make("lwinder", at: 32) { t in t.choose(StairTool.RunMode.lWinder); click(t, Vec2(32, 0)) }
        try make("uwinder", at: 40) { t in t.choose(StairTool.RunMode.uWinder); click(t, Vec2(39, 0)) }
        try make("sketch", at: 48) { t in
            t.choose(StairTool.RunMode.sketch)
            t.choose(StairTool.SketchLine.boundary)
            click(t, Vec2(47.4, 0)); click(t, Vec2(47.4, 5)); _ = t.escape()
            click(t, Vec2(48.6, 0)); click(t, Vec2(49.4, 5)); _ = t.escape()
            t.choose(StairTool.SketchLine.riser)
            for k in 0..<12 { let y = Double(k) * 0.4; click(t, Vec2(47.2, y)); click(t, Vec2(49.6, y)) }
            t.choose(StairTool.SketchLine.path)
            click(t, Vec2(48.1, 0)); click(t, Vec2(48.3, 4.6)); _ = t.escape()
            #expect(t.finish(), "the run sketch finishes first")
        }
        return (ctx.model, ids, crops)
    }

    /// Every kind in plan on its base level and the level it arrives at, light and dark.
    @Test func componentStairRenders() throws {
        for type in ["Assembled - 175 max riser", "Monolithic - 175 max riser"] {
            let (m, ids, crops) = try Self.componentStairs(type: type)
            #expect(m.elements(.stairs).count == crops.count)
            let tag = type.hasPrefix("Assembled") ? "assembled" : "monolithic"
            for (name, r) in crops {
                #expect(Self.draw(m, Self.cropPlan(m, ids, level: 0, r), "\(tag)-\(name)-L1", width: 800) > 0)
                Self.draw(m, Self.cropPlan(m, ids, level: 1, r), "\(tag)-\(name)-L2", width: 800)
            }
            Self.draw(m, Self.section(Vec3(8.3, 0, 0), Vec2(1, 0), crop: Rect2(min: Vec2(-8, -1), max: Vec2(2, 5))), "\(tag)-section-l")
            Self.draw(m, Self.section(Vec3(0.1, 0, 0), Vec2(1, 0), crop: Rect2(min: Vec2(-7, -1), max: Vec2(2, 5))), "\(tag)-section-straight")
        }
    }

    /// Create Stair while a run is drawn: the riser readout, and Edit Stairs with a selected run's grips.
    @Test func createStairModeRenders() throws {
        let (ctx, ids) = Self.context()
        let t = StairTool(ctx: ctx)
        Self.click(t, Vec2(0, 0))
        t.pointerMoved(ToolInput(point: Vec2(0, 2.3), rawPoint: Vec2(0, 2.3)))
        let crop = Rect2(min: Vec2(-3, -2), max: Vec2(4, 7))
        Self.draw(ctx.model, Self.cropPlan(ctx.model, ids, level: 0, crop), "mode-readout", overlay: t.preview.primitives, width: 800)
        #expect(t.preview.primitives.contains { if case .text(let g) = $0 { return g.string.contains("RISERS CREATED") }; return false })
        Self.click(t, Vec2(0, 2.24))
        let c = try #require(t.startCandidates.first { $0.direction.isAlmostEqual(Vec2(0, -1), tolerance: 1e-6) && $0.point.x > 0 })
        Self.click(t, c.point)
        t.pointerMoved(ToolInput(point: c.point + Vec2(0, -1.5), rawPoint: c.point + Vec2(0, -1.5)))
        Self.draw(ctx.model, Self.cropPlan(ctx.model, ids, level: 0, crop), "mode-second-run", overlay: t.preview.primitives, width: 800)
        _ = t.escape(); _ = t.escape()
        Self.click(t, Vec2(0, 1))
        Self.draw(ctx.model, Self.cropPlan(ctx.model, ids, level: 0, crop), "mode-selected-run", overlay: t.preview.primitives, width: 800)
        #expect(t.selection == .run(0))
    }

    static func renderView<V: View>(_ view: V, size: CGSize, _ name: String) async throws {
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

    /// The Architecture tab's Circulation panel, Modify | Create Stair (Components, Draw, Tools, Mode), its Options Bar,
    /// the Railing dialog, light and dark.
    @Test func ribbonOptionsBarAndRailingDialogRender() async throws {
        _ = NSApplication.shared
        let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let state = DocumentState(session: DocumentSession(model: m))
        let arch = RibbonContent.panels(.architecture)
        let circulation = try #require(arch.first { $0.title == "Circulation" })
        #expect(circulation.items.map(\.id).contains(.stair))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            state.open(ids.planViews[ids.levels[0]]!)
            state.ribbonTab = .architecture
            state.ribbonShowsContextual = false
            try await Self.renderView(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-ribbon-architecture-\(suffix)")
            CommandRouter(state: state).run(.stair)
            let tool = try #require(state.activeTool as? StairTool)
            state.ribbonShowsContextual = true
            #expect(RibbonContent.contextualTitle(state) == "Modify | Create Stair")
            try await Self.renderView(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-create-stair-ribbon-\(suffix)")
            try await Self.renderView(OptionsBarView(state: state), size: CGSize(width: 1100, height: 44), "ui-create-stair-options-\(suffix)")
            CommandRouter(state: state).run(.stairComponentLanding)
            #expect(tool.component == .landing)
            try await Self.renderView(RibbonView(state: state), size: CGSize(width: 2000, height: 120), "ui-create-stair-landing-ribbon-\(suffix)")
            try await Self.renderView(StairRailingDialogView(model: state.model, typeID: tool.railingTypeID, position: tool.railingPosition) { _ in },
                                      size: CGSize(width: 360, height: 210), "ui-railing-dialog-\(suffix)")
            state.cancelTool()
        }
        NSApp.appearance = nil
    }
}
