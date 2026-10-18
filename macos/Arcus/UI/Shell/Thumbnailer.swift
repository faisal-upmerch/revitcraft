import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusOutput

/// Renders a small PNG preview of a project (the lowest floor plan) for the package thumbnail and the hub.
nonisolated enum Thumbnailer {
    static func png(model: BIMModel, size: CGSize = CGSize(width: 512, height: 384)) -> Data? {
        let plans = model.views.filter { $0.view?.kind == .floorPlan && $0.view?.parentViewID == nil }
        guard let view = plans.min(by: { model.elevation(ofLevel: $0.levelID) < model.elevation(ofLevel: $1.levelID) }) else { return nil }
        let g = ViewGraphicsBuilder(model: model, view: view).build()
        let r = g.extents
        guard !r.isEmpty, let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.985, green: 0.98, blue: 0.965, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let s = min(size.width * 0.9 / max(r.width, 1e-6), size.height * 0.9 / max(r.height, 1e-6))
        let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: size.width / 2 - r.center.x * s, ty: size.height / 2 - r.center.y * s)
        var opts = RenderOptions()
        opts.background = RGBColor(0.985, 0.98, 0.965)
        GraphicsRenderer.draw(g, in: ctx, viewToDevice: t, pointsPerPaperMeter: s * Double(g.scale), options: opts)
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}
