import CoreGraphics
import Foundation
import ImageIO
import ArcusGeometry
import ArcusDomain

// FM9: the shaded three-quarter preview of a family's solids (moved here from the UI's component library renderer, so
// the Furniture Library generator in arcus-bench draws the same thumbnails), and the preview of a Furniture document as
// it loads into a project: Medium detail (fronts and hardware, no machining), its materials' colours, transparent
// background.

public enum ShadedFamilyRenderer {
    public static let yaw = -35.0 * Double.pi / 180
    public static let pitch = 27.0 * Double.pi / 180

    /// Screen position (x right, y up) and depth (larger is farther) of a family-space point.
    public static func project(_ v: Vec3, yaw: Double = yaw, pitch: Double = pitch) -> (Double, Double, Double) {
        let c = cos(yaw), s = sin(yaw)
        let xr = v.x * c - v.y * s, yr = v.x * s + v.y * c
        return (xr, v.z * cos(pitch) + yr * sin(pitch), yr * cos(pitch) - v.z * sin(pitch))
    }

    /// Draws the evaluated family's solids shaded and depth-sorted into `ctx`. `yaw` and `pitch` turn the view (the defaults: from the front left, a little above; 0 and 0: the front).
    public static func draw(_ ev: EvaluatedFamily, colors: [String: RGBColor], fallback: RGBColor, _ ctx: CGContext, width: Int, height: Int,
                           yaw: Double = yaw, pitch: Double = pitch) {
        let project = { (v: Vec3) in Self.project(v, yaw: yaw, pitch: pitch) }
        struct Tri { var a: (Double, Double, Double); var b: (Double, Double, Double); var c: (Double, Double, Double); var rgba: (Double, Double, Double, Double) }
        let viewDir = Vec3(sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), -sin(pitch))
        let light = Vec3(-0.45, -0.65, 0.9).normalized
        var tris: [Tri] = []
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var zMin = Double.infinity
        for s in ev.solids where !s.isVoid && s.visibleIn3D {
            let mesh = s.displayMesh
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

public enum FurniturePreview {
    /// The preview of a Furniture document (of a type, from a view direction, at a detail level), or nil when it has
    /// nothing to show.
    public static func image(_ m: BIMModel, width: Int, height: Int, type: String? = nil, yaw: Double = ShadedFamilyRenderer.yaw,
                             pitch: Double = ShadedFamilyRenderer.pitch, detail: DetailLevel = .medium) -> CGImage? {
        guard m.isFurniture else { return nil }
        let f = FurnitureCompiler.family(from: m)
        let typeName = type ?? m.furnitureSetup.map(\.currentType).flatMap { f.type(named: $0)?.name } ?? f.types.first?.name ?? ""
        var ev = FamilyEvaluator.evaluate(f, typeName: typeName, units: .imperial)
        // Colours by material: a solid's material parameter (this type's value) or the material its nested family set.
        var colors: [String: RGBColor] = [:]
        ev.solids = ev.solids.filter { !$0.isVoid && $0.visibleIn3D && $0.visibleAt.contains(detail) }.map { s in
            var s = s
            var id = s.resolvedMaterial
            if id == nil, let p = s.materialParameter, case .quantity(let raw, _)? = ev.values[p], raw >= 1 { id = ElementID(UInt64(raw)) }
            if let id, let mat = m[id]?.material {
                let key = "#\(id.raw)"
                colors[key] = mat.color
                s.materialParameter = key
            } else {
                s.materialParameter = nil
            }
            return s
        }
        guard !ev.solids.isEmpty, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true)
        ShadedFamilyRenderer.draw(ev, colors: colors, fallback: ElementMeshes.defaultColor(f.template.category), ctx, width: width, height: height, yaw: yaw, pitch: pitch)
        return ctx.makeImage()
    }

    /// The preview as PNG data.
    public static func png(_ m: BIMModel, width: Int = 512, height: Int = 384) -> Data? {
        guard let image = image(m, width: width, height: height) else { return nil }
        return pngData(image)
    }

    /// A PNG of `image`.
    public static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
