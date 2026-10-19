import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusOutput

// W2-LIB: previews for the component library, rendered at runtime from each family's own geometry (a shaded
// three-quarter view of its solids, or its plan symbol) and kept in memory.

/// A rendered preview. CGImage is immutable, so sharing it across tasks is safe.
struct LibraryPreviewImage: @unchecked Sendable {
    let image: CGImage
}

nonisolated enum LibraryThumbnailRenderer {
    /// Renders a shaded three-quarter view (`plan == false`) or the plan symbol of one type of a family.
    static func render(_ family: FamilyDefinition, type: String, colors: [String: RGBColor], fallback: RGBColor, plan: Bool,
                       width: Int, height: Int) -> LibraryPreviewImage? {
        let ev = FamilyEvaluator.evaluate(family, typeName: type)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        if plan { drawPlan(ev, ctx, width: width, height: height) } else { drawShaded(ev, colors: colors, fallback: fallback, ctx, width: width, height: height) }
        return ctx.makeImage().map(LibraryPreviewImage.init)
    }

    // MARK: Plan

    static func drawPlan(_ ev: EvaluatedFamily, _ ctx: CGContext, width: Int, height: Int) {
        var lines = ev.planLines.filter { $0.visibleAt.contains(.fine) }
        if lines.isEmpty { lines = ev.planLines }
        var r = Rect2.empty
        for l in lines { r.include(l.curve.bounds) }
        if lines.isEmpty {
            for s in ev.solids where !s.isVoid { r.include(s.profile.outer.bounds) }
        }
        guard r.width.isFinite, r.height.isFinite, r.width + r.height > 1e-6 else { return }
        let margin = 0.1
        let scale = min(Double(width) * (1 - 2 * margin) / max(r.width, 1e-3), Double(height) * (1 - 2 * margin) / max(r.height, 1e-3))
        let ox = Double(width) / 2 - (r.min.x + r.width / 2) * scale, oy = Double(height) / 2 - (r.min.y + r.height / 2) * scale
        func p(_ v: Vec2) -> CGPoint { CGPoint(x: v.x * scale + ox, y: v.y * scale + oy) }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let ink = CGColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
        let faint = CGColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 0.45)
        let lw = max(1.0, Double(min(width, height)) / 120)
        if lines.isEmpty {
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(lw)
            for s in ev.solids where !s.isVoid {
                let pts = s.profile.outer.points.map(p)
                guard let f = pts.first else { continue }
                ctx.move(to: f); for q in pts.dropFirst() { ctx.addLine(to: q) }; ctx.closePath()
            }
            ctx.strokePath()
            return
        }
        for l in lines {
            let dashed = l.subcategory == .hidden || l.subcategory == .swing
            ctx.setStrokeColor(dashed ? faint : ink)
            ctx.setLineWidth(dashed ? lw * 0.8 : lw)
            ctx.setLineDash(phase: 0, lengths: dashed ? [lw * 3, lw * 2] : [])
            switch l.curve {
            case .line(let s):
                ctx.move(to: p(s.start)); ctx.addLine(to: p(s.end))
            case .arc(let a):
                let pts = a.tessellate(chordTolerance: max(1e-4, 0.5 / scale))
                guard let f = pts.first else { continue }
                ctx.move(to: p(f)); for q in pts.dropFirst() { ctx.addLine(to: p(q)) }
            }
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    // MARK: Shaded three-quarter view

    // FM9: the renderer lives in ArcusOutput (ShadedFamilyRenderer), so arcus-bench draws the same previews.
    static let yaw = ShadedFamilyRenderer.yaw
    static let pitch = ShadedFamilyRenderer.pitch

    static func project(_ v: Vec3, yaw: Double = yaw, pitch: Double = pitch) -> (Double, Double, Double) { ShadedFamilyRenderer.project(v, yaw: yaw, pitch: pitch) }

    static func drawShaded(_ ev: EvaluatedFamily, colors: [String: RGBColor], fallback: RGBColor, _ ctx: CGContext, width: Int, height: Int,
                           yaw: Double = yaw, pitch: Double = pitch) {
        ShadedFamilyRenderer.draw(ev, colors: colors, fallback: fallback, ctx, width: width, height: height, yaw: yaw, pitch: pitch)
    }
}


/// In-memory cache of rendered previews, keyed by family, type, view and pixel size. Rendering runs off the main actor.
@MainActor
final class LibraryThumbnailCache {
    static let shared = LibraryThumbnailCache()
    private var images: [String: LibraryPreviewImage] = [:]
    private var order: [String] = []
    private let limit = 900

    func cached(_ key: String) -> CGImage? { images[key]?.image }

    func image(for item: ComponentLibraryItem, type: String, plan: Bool, width: Int, height: Int) async -> CGImage? {
        let key = "\(item.name)|\(type)|\(plan ? "P" : "3")|\(width)x\(height)"
        if let hit = images[key] { return hit.image }
        let family = item.family
        let colors = item.materials.mapValues(\.color)
        let fallback = ElementMeshes.defaultColor(item.category)
        let rendered = await Task.detached(priority: .userInitiated) {
            LibraryThumbnailRenderer.render(family, type: type, colors: colors, fallback: fallback, plan: plan, width: width, height: height)
        }.value
        if let rendered {
            images[key] = rendered
            order.append(key)
            if order.count > limit { images.removeValue(forKey: order.removeFirst()) }
        }
        return rendered?.image
    }
}

/// A library preview image that renders on first appearance.
struct LibraryPreview: View {
    let item: ComponentLibraryItem
    let type: String
    var plan = false
    var size: CGSize
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let w = Int(size.width * max(displayScale, 1)), h = Int(size.height * max(displayScale, 1))
        let key = "\(item.name)|\(type)|\(plan ? "P" : "3")|\(w)x\(h)"
        ZStack {
            if let img = image ?? LibraryThumbnailCache.shared.cached(key) {
                Image(decorative: img, scale: max(displayScale, 1)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small).opacity(0.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: key) {
            image = await LibraryThumbnailCache.shared.image(for: item, type: type, plan: plan, width: w, height: h)
        }
        .accessibilityHidden(true)
    }
}
