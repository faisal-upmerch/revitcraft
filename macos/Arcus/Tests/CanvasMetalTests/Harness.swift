import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusOutput
@testable import ArcusCanvasMetal

/// A BGRA8 premultiplied bitmap, rows top-down (CoreGraphics `premultipliedFirst | byteOrder32Little` layout).
struct Bitmap {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    subscript(x: Int, y: Int, c: Int) -> UInt8 { bytes[(y * width + x) * 4 + c] }
}

/// The device-space setup shared by both renderers.
struct CanvasSetup {
    var widthPt: Double = 300
    var heightPt: Double = 200
    /// Pixels per point (Retina = 2).
    var scale: Double = 2
    /// View units → device points.
    var viewToDevice: CGAffineTransform
    var ppm: Double

    var pixelWidth: Int { Int(widthPt * scale) }
    var pixelHeight: Int { Int(heightPt * scale) }

    /// A model view at `zoom` points per view meter with the view point `center` in the middle of the canvas.
    static func model(zoom: Double, viewScale: Int, center: Vec2 = .zero, widthPt: Double = 300, heightPt: Double = 200,
                      scale: Double = 2) -> CanvasSetup {
        let t = CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: widthPt / 2 - center.x * zoom, ty: heightPt / 2 - center.y * zoom)
        return CanvasSetup(widthPt: widthPt, heightPt: heightPt, scale: scale, viewToDevice: t, ppm: zoom * Double(viewScale))
    }
}

struct Comparison: CustomStringConvertible {
    /// Mean absolute channel difference (0…1).
    var meanAbs: Double
    /// Fraction of pixels whose 3×3-box-blurred colours differ by more than 15 % in some channel.
    var mismatch: Double
    /// Ink (deviation from the background) of Metal ÷ CoreGraphics.
    var inkRatio: Double
    var inkCG: Double

    var description: String {
        String(format: "meanAbs %.4f, mismatch %.3f%%, ink ratio %.3f (CG ink %.0f)", meanAbs, mismatch * 100, inkRatio, inkCG)
    }
}

enum Harness {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated(unsafe) static var subpixelTextDefault = true

    static func graphics(scale: Int = 100, _ items: [GItem]) -> ViewGraphics {
        ViewGraphics(viewID: ElementID(1), scale: scale, items: items, extents: .empty, crop: nil, modelRevision: 0)
    }

    static func item(_ id: UInt64? = nil, _ layer: GItem.Layer = .model, _ prims: [GPrimitive]) -> GItem {
        GItem(elementID: id.map { ElementID($0) }, category: .genericModels, layer: layer, primitives: prims)
    }

    // MARK: Rendering

    /// Renders with CoreGraphics into a Retina-style bitmap (context scaled by `setup.scale`, font smoothing off like
    /// layer-backed AppKit views).
    static func renderCG(_ g: ViewGraphics, _ setup: CanvasSetup, _ options: RenderOptions,
                         overlay: (ViewGraphics, RenderOptions)? = nil, into existing: Bitmap? = nil,
                         subpixelText: Bool = subpixelTextDefault) -> Bitmap {
        let w = setup.pixelWidth, h = setup.pixelHeight
        var bytes = existing?.bytes ?? [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            ctx.scaleBy(x: setup.scale, y: setup.scale)
            ctx.setShouldSmoothFonts(false)
            if subpixelText {
                ctx.setAllowsFontSubpixelPositioning(true)
                ctx.setShouldSubpixelPositionFonts(true)
                ctx.setAllowsFontSubpixelQuantization(false)
                ctx.setShouldSubpixelQuantizeFonts(false)
            }
            let clip = CGRect(x: 0, y: 0, width: setup.widthPt, height: setup.heightPt)
            GraphicsRenderer.draw(g, in: ctx, viewToDevice: setup.viewToDevice, pointsPerPaperMeter: setup.ppm, options: options, clip: clip)
            if let (og, oo) = overlay {
                GraphicsRenderer.draw(og, in: ctx, viewToDevice: setup.viewToDevice, pointsPerPaperMeter: setup.ppm, options: oo, clip: clip)
            }
        }
        return Bitmap(width: w, height: h, bytes: bytes)
    }

    @MainActor
    static func renderMetal(_ g: ViewGraphics, _ setup: CanvasSetup, _ options: RenderOptions,
                            overlay: (ViewGraphics, RenderOptions)? = nil,
                            configure: (MetalCanvasRenderer) -> Void = { _ in }) throws -> Bitmap {
        let ctx = try #require(MetalCanvasContext.shared)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        r.options = options
        let scene = try #require(MetalCanvasScene.build(g, context: ctx))
        r.setScene(scene)
        if let (og, oo) = overlay {
            r.overlayOptions = oo
            r.setOverlay(og)
        }
        configure(r)
        let tex = try #require(r.makeOffscreenTarget(width: setup.pixelWidth, height: setup.pixelHeight))
        let st = try #require(r.encode(to: tex, viewToDevice: setup.viewToDevice, pointsPerPaperMeter: setup.ppm, pixelsPerPoint: setup.scale))
        _ = r.waitUntilCompleted(st)
        return Bitmap(width: tex.width, height: tex.height, bytes: MetalCanvasRenderer.readPixels(tex))
    }

    // MARK: Metrics

    static func compare(_ a: Bitmap, _ b: Bitmap, background: RGBColor?) -> Comparison {
        precondition(a.width == b.width && a.height == b.height)
        let n = a.width * a.height
        var sum = 0.0
        for i in 0..<(n * 4) { sum += Double(abs(Int(a.bytes[i]) - Int(b.bytes[i]))) }
        let ba = blur(a), bb = blur(b)
        var bad = 0
        for i in 0..<n {
            var m = 0.0
            for c in 0..<4 { m = max(m, abs(ba[i * 4 + c] - bb[i * 4 + c])) }
            if m > 0.15 * 255 { bad += 1 }
        }
        // Ink = premultiplied deviation from the background (BGRA order).
        var bg: [Double] = [0, 0, 0, 0]
        if let c = background { bg = [c.b * 255 * c.a, c.g * 255 * c.a, c.r * 255 * c.a, c.a * 255] }
        func ink(_ x: Bitmap) -> Double {
            var s = 0.0
            for i in 0..<n { for c in 0..<4 { s += abs(Double(x.bytes[i * 4 + c]) - bg[c]) } }
            return s / 255
        }
        let ia = ink(a), ib = ink(b)
        return Comparison(meanAbs: sum / Double(n * 4) / 255, mismatch: Double(bad) / Double(n),
                          inkRatio: ia > 0 ? ib / ia : (ib > 0 ? .infinity : 1), inkCG: ia)
    }

    static func blur(_ x: Bitmap) -> [Double] {
        let w = x.width, h = x.height
        var out = [Double](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for xx in 0..<w {
                for c in 0..<4 {
                    var s = 0.0, k = 0.0
                    for dy in -1...1 {
                        let yy = y + dy
                        if yy < 0 || yy >= h { continue }
                        for dx in -1...1 {
                            let xq = xx + dx
                            if xq < 0 || xq >= w { continue }
                            s += Double(x.bytes[(yy * w + xq) * 4 + c]); k += 1
                        }
                    }
                    out[(y * w + xx) * 4 + c] = s / k
                }
            }
        }
        return out
    }

    // MARK: Artifacts

    static var artifactRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ArcusCanvasMetalParity", isDirectory: true) }
    static var alwaysDump: Bool { ProcessInfo.processInfo.environment["ARCUS_PARITY_DUMP"] != nil }

    /// Writes cg.png, metal.png and diff.png (|difference| × 4) for a case; returns the directory.
    @discardableResult
    static func dump(_ name: String, cg: Bitmap, metal: Bitmap) -> URL {
        let dir = artifactRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writePNG(cg, dir.appendingPathComponent("cg.png"))
        writePNG(metal, dir.appendingPathComponent("metal.png"))
        var d = cg
        for i in 0..<(d.width * d.height) {
            for c in 0..<3 { d.bytes[i * 4 + c] = UInt8(min(255, abs(Int(cg.bytes[i * 4 + c]) - Int(metal.bytes[i * 4 + c])) * 4)) }
            d.bytes[i * 4 + 3] = 255
        }
        writePNG(d, dir.appendingPathComponent("diff.png"))
        return dir
    }

    static func writePNG(_ b: Bitmap, _ url: URL) {
        var bytes = b.bytes
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: b.width, height: b.height, bitsPerComponent: 8, bytesPerRow: b.width * 4,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  let img = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
