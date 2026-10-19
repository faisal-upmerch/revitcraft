import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
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

    /// The audit set: straight, L and U stairs with railings and a multistory straight stair, in every view.
    @Test func auditRenders() throws {
        let (ctx, ids) = Self.context()
        for (cmd, a, b) in [(StairShape.straight, Vec2(0, 0), Vec2(0, 5)), (.lShaped, Vec2(6, 0), Vec2(6, 5)), (.uShaped, Vec2(12, 0), Vec2(12, 5))] {
            let t = StairTool(ctx: ctx, shape: cmd)
            Self.click(t, a); Self.click(t, b)
        }
        let ms = StairTool(ctx: ctx, shape: .straight)
        ms.multistoryTopLevelID = ids.levels[2]
        Self.click(ms, Vec2(20, 0)); Self.click(ms, Vec2(20, 5))
        let m = ctx.model
        #expect(m.elements(.stairs).count == 4)
        let crop = Rect2(min: Vec2(-3, -3), max: Vec2(24, 10))
        #expect(Self.draw(m, Self.cropPlan(m, ids, level: 0, crop), "audit-plan-L1") > 0)
        #expect(Self.draw(m, Self.cropPlan(m, ids, level: 1, crop), "audit-plan-L2") > 0)
        #expect(Self.draw(m, Self.section(Vec3(0, -4, 0), Vec2(0, 1), crop: Rect2(min: Vec2(-3, -1), max: Vec2(24, 9))), "audit-section-across") > 0)
        #expect(Self.draw(m, Self.section(Vec3(0.1, 0, 0), Vec2(1, 0), crop: Rect2(min: Vec2(-12, -1), max: Vec2(12, 9))), "audit-section-along") > 0)
    }
}
