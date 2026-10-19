import AppKit
import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import simd

// COMP: thumbnails and previews of components, rendered from their real geometry (the family's solids for the chosen
// type) with the shared shaded renderer, turned so a face-mounted component faces the viewer as it would on a door.
// The 2D preview draws the component's own symbols (plan or face, at a detail level) or, when it has none, its edges
// seen from the front, side or top. Rendering runs off the main actor; results are cached.

nonisolated enum ComponentRenderer {
    /// Family coordinates → preview coordinates (X right, Y away from the viewer, Z up).
    static func orientation(_ frame: ComponentFrame) -> Transform3 {
        switch frame {
        case .face:
            // X along the face, Y up it, Z out of it toward the viewer.
            return Transform3(simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, -1, 0, 0), SIMD4(0, 0, 0, 1))))
        default: return .identity
        }
    }

    /// The evaluated family, turned for previews.
    static func evaluated(_ d: ComponentDefinition, type: String, values: [String: ParamValue] = [:]) -> EvaluatedFamily {
        var ev = FamilyEvaluator.evaluate(d.family, typeName: type, instance: values)
        let t = orientation(d.frame)
        for k in ev.solids.indices { ev.solids[k].mesh = ev.solids[k].familyMesh.transformed(t) }
        return ev
    }

    static func colors(_ d: ComponentDefinition) -> [String: RGBColor] {
        Dictionary(d.materials.map { ($0.name, $0.finish.color) }, uniquingKeysWith: { a, _ in a })
    }

    /// A shaded 3D view (yaw and pitch turn it; zoom > 1 magnifies; pan in points).
    static func shaded(_ d: ComponentDefinition, type: String, values: [String: ParamValue] = [:], yaw: Double, pitch: Double, zoom: Double = 1,
                       pan: CGSize = .zero, width: Int, height: Int) -> CGImage? {
        let ev = evaluated(d, type: type, values: values)
        guard let ctx = context(width, height) else { return nil }
        let z = max(0.2, zoom)
        let w = Int(Double(width) * z), h = Int(Double(height) * z)
        guard let big = context(w, h) else { return nil }
        ShadedFamilyRenderer.draw(ev, colors: colors(d), fallback: RGBColor(0.62, 0.64, 0.67), big, width: w, height: h, yaw: yaw, pitch: pitch)
        guard let img = big.makeImage() else { return nil }
        let x = (Double(width) - Double(w)) / 2 + pan.width, y = (Double(height) - Double(h)) / 2 - pan.height
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: x, y: y, width: Double(w), height: Double(h)))
        return ctx.makeImage()
    }

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// A 2D drawing: the component's symbols for the view at a detail level, or its edges seen from the view.
    static func drawing(_ d: ComponentDefinition, type: String, view: ComponentPreviewView, detail: DetailLevel = .medium, dark: Bool,
                        zoom: Double = 1, pan: CGSize = .zero, width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width, height) else { return nil }
        let raw = FamilyEvaluator.evaluate(d.family, typeName: type)
        var segs: [(Vec2, Vec2, Bool)] = []
        // Symbols: plans use Top (face-mounted) or Face (plan frame) symbols; the other views their own.
        let symbolView: ComponentSymbolView = switch (view, d.frame) {
        case (.top, .face): .top
        case (.top, _): .face
        case (.side, _): .side
        default: d.frame == .face ? .face : .top
        }
        for s in d.symbols where s.view == symbolView && s.levels.contains(detail) {
            for sh in s.shapes { segs += ComponentSymbols.segments(sh, raw).map { ($0.0, $0.1, s.dashed) } }
        }
        if segs.isEmpty {
            let ev = evaluated(d, type: type)
            let (yaw, pitch) = view.angles
            for sol in ev.solids where !sol.isVoid {
                let m = sol.familyMesh
                var e = 0
                let edges = m.featureEdges
                while e + 1 < edges.count {
                    let a = ShadedFamilyRenderer.project(m.positions[Int(edges[e])], yaw: yaw, pitch: pitch)
                    let b = ShadedFamilyRenderer.project(m.positions[Int(edges[e + 1])], yaw: yaw, pitch: pitch)
                    segs.append((Vec2(a.0, a.1), Vec2(b.0, b.1), false))
                    e += 2
                }
            }
        }
        guard !segs.isEmpty else { return ctx.makeImage() }
        var r = Rect2.empty
        for s in segs { r.include(s.0); r.include(s.1) }
        let margin = 0.1
        let scale = min(Double(width) * (1 - 2 * margin) / max(r.width, 1e-3), Double(height) * (1 - 2 * margin) / max(r.height, 1e-3)) * max(0.2, zoom)
        let ox = Double(width) / 2 - (r.min.x + r.width / 2) * scale + pan.width, oy = Double(height) / 2 - (r.min.y + r.height / 2) * scale - pan.height
        let ink = dark ? CGColor(srgbRed: 0.88, green: 0.89, blue: 0.91, alpha: 1) : CGColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
        let lw = max(1.0, Double(min(width, height)) / 160)
        ctx.setLineCap(.round)
        for (a, b, dashed) in segs {
            ctx.setStrokeColor(dashed ? ink.copy(alpha: 0.5)! : ink)
            ctx.setLineWidth(lw)
            ctx.setLineDash(phase: 0, lengths: dashed ? [lw * 3, lw * 2] : [])
            ctx.move(to: CGPoint(x: a.x * scale + ox, y: a.y * scale + oy))
            ctx.addLine(to: CGPoint(x: b.x * scale + ox, y: b.y * scale + oy))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

}

struct ComponentImage: @unchecked Sendable { let image: CGImage }

/// Cache of rendered thumbnails (by component, version, type and size).
@MainActor
final class ComponentThumbnailCache {
    static let shared = ComponentThumbnailCache()
    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private let limit = 1200

    static func key(_ d: ComponentDefinition, _ type: String, _ w: Int, _ h: Int) -> String { "\(d.id)|v\(d.version)|\(type)|\(w)x\(h)" }

    func cached(_ key: String) -> CGImage? { images[key] }

    func thumbnail(_ d: ComponentDefinition, type: String, width: Int, height: Int) async -> CGImage? {
        let key = Self.key(d, type, width, height)
        if let hit = images[key] { return hit }
        let rendered = await Task.detached(priority: .userInitiated) {
            ComponentRenderer.shaded(d, type: type, yaw: ShadedFamilyRenderer.yaw, pitch: ShadedFamilyRenderer.pitch, width: width, height: height).map(ComponentImage.init)
        }.value
        if let rendered {
            images[key] = rendered.image
            order.append(key)
            if order.count > limit { images.removeValue(forKey: order.removeFirst()) }
        }
        return rendered?.image
    }

    /// Renders now (offscreen captures and tests).
    func thumbnailNow(_ d: ComponentDefinition, type: String, width: Int, height: Int) -> CGImage? {
        let key = Self.key(d, type, width, height)
        if let hit = images[key] { return hit }
        let img = ComponentRenderer.shaded(d, type: type, yaw: ShadedFamilyRenderer.yaw, pitch: ShadedFamilyRenderer.pitch, width: width, height: height)
        if let img { images[key] = img; order.append(key) }
        return img
    }
}

/// A component thumbnail that renders on first appearance.
struct ComponentThumbnail: View {
    let definition: ComponentDefinition
    let type: String
    var size: CGSize
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let s = max(displayScale, 1)
        let w = Int(size.width * s), h = Int(size.height * s)
        let key = ComponentThumbnailCache.key(definition, type, w, h)
        ZStack {
            if let img = image ?? ComponentThumbnailCache.shared.cached(key) ?? (ComponentThumbnail.renderSynchronously ? ComponentThumbnailCache.shared.thumbnailNow(definition, type: type, width: w, height: h) : nil) {
                Image(decorative: img, scale: s).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: definition.category.symbol).font(.system(size: min(size.width, size.height) * 0.3)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: key) { image = await ComponentThumbnailCache.shared.thumbnail(definition, type: type, width: w, height: h) }
        .accessibilityHidden(true)
    }

    /// Offscreen captures render thumbnails inline (no run loop for the async render).
    nonisolated(unsafe) static var renderSynchronously = false
}
