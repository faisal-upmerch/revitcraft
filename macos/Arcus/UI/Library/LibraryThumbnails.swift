import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain

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

    static let yaw = -35.0 * Double.pi / 180
    static let pitch = 27.0 * Double.pi / 180

    /// Screen position (x right, y up) and depth (larger is farther) of a family-space point.
    static func project(_ v: Vec3) -> (Double, Double, Double) {
        let c = cos(yaw), s = sin(yaw)
        let xr = v.x * c - v.y * s, yr = v.x * s + v.y * c
        return (xr, v.z * cos(pitch) + yr * sin(pitch), yr * cos(pitch) - v.z * sin(pitch))
    }

    static func drawShaded(_ ev: EvaluatedFamily, colors: [String: RGBColor], fallback: RGBColor, _ ctx: CGContext, width: Int, height: Int) {
        struct Tri { var a: (Double, Double, Double); var b: (Double, Double, Double); var c: (Double, Double, Double); var rgba: (Double, Double, Double, Double) }
        let viewDir = Vec3(sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), -sin(pitch))
        let light = Vec3(-0.45, -0.65, 0.9).normalized
        var tris: [Tri] = []
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var zMin = Double.infinity
        for s in ev.solids where !s.isVoid && s.visibleIn3D {
            let mesh = s.familyMesh
            let base = s.materialParameter.flatMap { colors[$0] } ?? fallback
            let idx = mesh.indices
            var i = 0
            while i + 2 < idx.count {
                let a = mesh.positions[Int(idx[i])], b = mesh.positions[Int(idx[i + 1])], c = mesh.positions[Int(idx[i + 2])]
                i += 3
                var n = (b - a).cross(c - a)
                guard n.length > 1e-12 else { continue }
                n = n.normalized
                if n.dot(viewDir) > 0 { n = n * -1 }
                let shade = 0.5 + 0.5 * max(0, n.dot(light))
                let pa = project(a), pb = project(b), pc = project(c)
                for q in [pa, pb, pc] { minX = min(minX, q.0); maxX = max(maxX, q.0); minY = min(minY, q.1); maxY = max(maxY, q.1) }
                zMin = min(zMin, a.z, b.z, c.z)
                tris.append(Tri(a: pa, b: pb, c: pc, rgba: (base.r * shade, base.g * shade, base.b * shade, base.a)))
            }
        }
        guard !tris.isEmpty, maxX > minX || maxY > minY else { return }
        let margin = 0.08
        let w = max(maxX - minX, 1e-3), h = max(maxY - minY, 1e-3)
        let scale = min(Double(width) * (1 - 2 * margin) / w, Double(height) * (1 - 2 * margin) / h)
        let ox = Double(width) / 2 - (minX + w / 2) * scale, oy = Double(height) / 2 - (minY + h / 2) * scale

        // Soft ground shadow under the footprint.
        let bb = ev.bounds
        if bb.min.x.isFinite {
            let corners = [Vec3(bb.min.x, bb.min.y, zMin), Vec3(bb.max.x, bb.min.y, zMin), Vec3(bb.max.x, bb.max.y, zMin), Vec3(bb.min.x, bb.max.y, zMin)]
            let ps = corners.map { v -> CGPoint in let q = project(v); return CGPoint(x: q.0 * scale + ox, y: q.1 * scale + oy) }
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07))
            ctx.move(to: ps[0]); for q in ps.dropFirst() { ctx.addLine(to: q) }; ctx.closePath(); ctx.fillPath()
        }

        // Depth-buffered rasterization at 2x, then a smooth downsample into the context.
        let ss = 2
        let W = width * ss, H = height * ss
        var color = [UInt8](repeating: 0, count: W * H * 4)
        var depth = [Double](repeating: .infinity, count: W * H)
        let k = scale * Double(ss), kx = ox * Double(ss), ky = oy * Double(ss)
        for t in tris {
            // Image rows run top-down; screen y runs up.
            let p0 = (t.a.0 * k + kx, Double(H) - (t.a.1 * k + ky), t.a.2)
            let p1 = (t.b.0 * k + kx, Double(H) - (t.b.1 * k + ky), t.b.2)
            let p2 = (t.c.0 * k + kx, Double(H) - (t.c.1 * k + ky), t.c.2)
            let area = (p1.0 - p0.0) * (p2.1 - p0.1) - (p2.0 - p0.0) * (p1.1 - p0.1)
            guard abs(area) > 1e-9 else { continue }
            let x0 = max(0, Int(min(p0.0, p1.0, p2.0).rounded(.down))), x1 = min(W - 1, Int(max(p0.0, p1.0, p2.0).rounded(.up)))
            let y0 = max(0, Int(min(p0.1, p1.1, p2.1).rounded(.down))), y1 = min(H - 1, Int(max(p0.1, p1.1, p2.1).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            let a = t.rgba.3
            let r = UInt8(max(0, min(255, t.rgba.0 * a * 255))), g = UInt8(max(0, min(255, t.rgba.1 * a * 255)))
            let bl = UInt8(max(0, min(255, t.rgba.2 * a * 255))), al = UInt8(max(0, min(255, a * 255)))
            for y in y0...y1 {
                let py = Double(y) + 0.5
                for x in x0...x1 {
                    let px = Double(x) + 0.5
                    let w0 = ((p1.0 - px) * (p2.1 - py) - (p2.0 - px) * (p1.1 - py)) / area
                    let w1 = ((p2.0 - px) * (p0.1 - py) - (p0.0 - px) * (p2.1 - py)) / area
                    let w2 = 1 - w0 - w1
                    guard w0 >= -1e-6, w1 >= -1e-6, w2 >= -1e-6 else { continue }
                    let d = w0 * p0.2 + w1 * p1.2 + w2 * p2.2
                    let i = y * W + x
                    guard d < depth[i] - 1e-7 else { continue }
                    depth[i] = d
                    color[i * 4] = r; color[i * 4 + 1] = g; color[i * 4 + 2] = bl; color[i * 4 + 3] = al
                }
            }
        }
        let image: CGImage? = color.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
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
