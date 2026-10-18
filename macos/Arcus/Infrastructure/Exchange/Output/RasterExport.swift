import CoreGraphics
import Foundation
import ImageIO
import ArcusGeometry
import ArcusDomain

// BL-SCHED: File ▸ Export ▸ Images — PNG/JPEG of a view or sheet, rendered locally with the same renderer as PDF.

public enum RasterImageFormat: String, CaseIterable, Sendable {
    case png = "PNG", jpeg = "JPEG"
    public var fileExtension: String { self == .png ? "png" : "jpg" }
    var typeIdentifier: CFString { (self == .png ? "public.png" : "public.jpeg") as CFString }
}

/// Renders display lists to bitmaps and encodes them as PNG or JPEG.
public enum RasterExporter {
    /// Largest side of an exported image, in pixels.
    public static let maximumPixels = 16_384

    /// The area an export shows: a sheet's whole paper (paper meters), or a view's crop region — else its extents —
    /// with a 5 % margin (model meters).
    public static func region(_ g: ViewGraphics, paper: Vec2?) -> Rect2 {
        if let paper { return Rect2(min: .zero, max: paper) }
        let r = g.crop ?? g.extents
        guard !r.isEmpty, r.width > 0 || r.height > 0 else { return Rect2(min: Vec2(-1, -1), max: Vec2(1, 1)) }
        return r.expanded(by: max(r.width, r.height) * 0.05 + 1e-3)
    }

    /// Pixel size for a region at `pixelWidth` (height follows the aspect ratio; both clamped to `maximumPixels`).
    public static func pixelSize(_ region: Rect2, pixelWidth: Int) -> (width: Int, height: Int) {
        let w = max(16, min(pixelWidth, maximumPixels))
        let aspect = region.width > 0 ? region.height / region.width : 1
        var h = Int((Double(w) * aspect).rounded())
        var width = w
        if h > maximumPixels { width = Int(Double(w) * Double(maximumPixels) / Double(h)); h = maximumPixels }
        return (max(16, width), max(16, h))
    }

    /// Renders a view (`paper` nil; model meters) or a sheet (`paper` = its size; paper meters) with print styling on
    /// a solid background.
    public static func render(_ g: ViewGraphics, paper: Vec2? = nil, pixelWidth: Int, background: RGBColor = .white, showOverlays: Bool = false) -> CGImage? {
        let r = region(g, paper: paper)
        let (w, h) = pixelSize(r, pixelWidth: pixelWidth)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: background.r, green: background.g, blue: background.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let s = Double(w) / max(r.width, 1e-9)
        let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: -r.min.x * s, ty: -r.min.y * s)
        var opts = RenderOptions()
        opts.printing = true
        opts.background = background
        opts.showOverlays = showOverlays
        opts.minimumDevicePixel = 1
        let ppm = paper != nil ? s : s * Double(max(g.scale, 1))
        GraphicsRenderer.draw(g, in: ctx, viewToDevice: t, pointsPerPaperMeter: ppm, options: opts, clip: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Encodes an image. `dpi` is written as the image resolution (so a sheet prints at its paper size); JPEG uses
    /// `quality` (0…1).
    public static func encode(_ image: CGImage, as format: RasterImageFormat, quality: Double = 0.9, dpi: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, format.typeIdentifier, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        if let dpi { props[kCGImagePropertyDPIWidth] = dpi; props[kCGImagePropertyDPIHeight] = dpi }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Resolution that makes a sheet image print at its paper size.
    public static func dpi(pixelWidth: Int, paperWidth: Double) -> Double { Double(pixelWidth) / (paperWidth / 0.0254) }
}
