import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import ArcusViewport3D

// F810: View ▸ Presentation ▸ Render. Renders the 3D view offscreen with the Metal viewport's Realistic style (sun
// shadows, ambient occlusion, sky), at the requested size, as RevitCraft's render dialog does (`render_size`,
// `render_realistic`). Everything runs on this Mac.

enum RenderEngine {
    enum Quality: String, CaseIterable, Identifiable {
        case draft = "Draft", low = "Low", medium = "Medium", high = "High", best = "Best"
        var id: String { rawValue }
        /// Screen resolution scale of RevitCraft's qualities (of 1280 pixels wide).
        var scale: Double { [0.5, 0.75, 1.0, 1.5, 2.0][Quality.allCases.firstIndex(of: self) ?? 2] }
        /// Rendered at twice the size and filtered down (smoother edges) from High up.
        var supersample: Int { self == .high || self == .best ? 2 : 1 }
        var ambientOcclusion: Bool { self != .draft }
    }

    struct Settings: Equatable {
        var quality = Quality.medium
        /// Printer resolution: a 10" × 6.25" image at `dpi` (else the screen size of the quality).
        var printer = false
        var dpi = 150
        /// Exterior: sun and sky (sun shadows); off: sky light only (no sun shadows).
        var sun = true
        /// Sky background (off: the canvas background).
        var sky = true
    }

    static let dpiChoices = [75, 150, 300, 600]

    /// The image size in pixels for the view's aspect (height / width).
    static func size(_ s: Settings, aspect: Double) -> (width: Int, height: Int) {
        let a = aspect.isFinite && aspect > 0.05 ? min(aspect, 20) : 0.625
        let w = s.printer ? s.dpi * 10 : Int((1280 * s.quality.scale).rounded())
        return (w, max(1, Int((Double(w) * a).rounded())))
    }

    /// The aspect of a 3D view's canvas (its camera frame when it crops).
    static func aspect(_ host: Viewport3DHost) -> Double {
        if let f = host.viewport.cameraFrameAspect, f > 0 { return 1 / f }
        let b = host.viewport.bounds.size
        return b.width > 0 ? b.height / b.width : 0.625
    }

    /// Renders the host's 3D view; the viewport's own display settings are restored afterwards.
    static func render(_ host: Viewport3DHost, _ s: Settings) -> CGImage? {
        let vp = host.viewport
        let saved = (vp.visualStyle, vp.castShadows, vp.ambientOcclusion, vp.silhouetteEdges, vp.showEdgesInShadedStyles, vp.realisticSky)
        defer {
            (vp.visualStyle, vp.castShadows, vp.ambientOcclusion, vp.silhouetteEdges, vp.showEdgesInShadedStyles, vp.realisticSky) = saved
        }
        vp.visualStyle = .realistic
        vp.castShadows = s.sun
        vp.ambientOcclusion = s.quality.ambientOcclusion
        vp.silhouetteEdges = false
        vp.showEdgesInShadedStyles = false
        vp.realisticSky = s.sky
        let (w, h) = size(s, aspect: aspect(host))
        let k = min(s.quality.supersample, max(1, 8192 / max(w, h)))
        guard let big = vp.snapshot(size: CGSize(width: w * k, height: h * k)) else { return nil }
        return k == 1 ? big : downscale(big, width: w, height: h)
    }

    /// Filters an image down to `width` × `height` (high-quality interpolation).
    static func downscale(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func png(_ image: CGImage) -> Data? { RasterExporter.encode(image, as: .png) }
}
