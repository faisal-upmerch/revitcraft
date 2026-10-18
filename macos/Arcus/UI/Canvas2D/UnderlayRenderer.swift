import AppKit
import ArcusGeometry
import ArcusDomain

/// Draws PDF page and raster image underlays (link elements of format .pdf/.image) beneath the display list.
/// PDF pages are drawn as vectors with CGContext.drawPDFPage; images with CGContext.draw. Sources are resolved
/// from their security-scoped bookmarks and cached; a missing file draws a labeled placeholder.
@MainActor
enum UnderlayRenderer {
    private static var pdfCache: [String: CGPDFDocument] = [:]
    private static var imageCache: [String: CGImage] = [:]

    static func underlays(for viewID: ElementID, model: BIMModel) -> [Element] {
        let view = model[viewID]
        return model.elements(.importedCAD).filter { e in
            guard let l = e.link, l.format == .pdf || l.format == .image, l.isLoaded else { return false }
            if let o = e.ownerViewID { return o == viewID }
            return e.levelID != nil && e.levelID == view?.levelID
        }
    }

    static func url(_ l: LinkData) -> URL? {
        var stale = false
        if let b = l.bookmark, let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return u }
        return FileManager.default.fileExists(atPath: l.sourcePath) ? URL(fileURLWithPath: l.sourcePath) : nil
    }

    static func draw(for viewID: ElementID, model: BIMModel, in ctx: CGContext, viewToDevice: CGAffineTransform) {
        for e in underlays(for: viewID, model: model) {
            guard let l = e.link else { continue }
            let t = l.placement
            let m = CGAffineTransform(a: t.a, b: t.c, c: t.b, d: t.d, tx: t.tx, ty: t.ty).concatenating(viewToDevice)
            ctx.saveGState()
            ctx.concatenate(m)
            ctx.setAlpha(l.opacity)
            if l.format == .pdf {
                if let doc = pdf(l), let page = doc.page(at: Int(l.page ?? "1") ?? 1) {
                    ctx.drawPDFPage(page)
                } else { placeholder(ctx, l) }
            } else if let img = image(l) {
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            } else { placeholder(ctx, l) }
            ctx.restoreGState()
        }
    }

    private static func pdf(_ l: LinkData) -> CGPDFDocument? {
        if let d = pdfCache[l.sourcePath] { return d }
        guard let u = url(l) else { return nil }
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let d = CGPDFDocument(u as CFURL) else { return nil }
        pdfCache[l.sourcePath] = d
        return d
    }

    private static func image(_ l: LinkData) -> CGImage? {
        if let d = l.embeddedData { return embedded(d) } // F67: Import Image / Import PDF
        if let i = imageCache[l.sourcePath] { return i }
        guard let u = url(l) else { return nil }
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        imageCache[l.sourcePath] = img
        return img
    }

    private static func placeholder(_ ctx: CGContext, _ l: LinkData) {
        let r = CGRect(x: 0, y: 0, width: 800, height: 600)
        ctx.setStrokeColor(NSColor.systemOrange.cgColor)
        ctx.setLineWidth(4)
        ctx.stroke(r)
        ctx.move(to: r.origin); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); ctx.strokePath()
    }

    static func purge() { pdfCache.removeAll(); imageCache.removeAll(); embeddedCache.removeAll() }

    // F67: pictures stored in the project (imported images and PDF pages, DWF markup pictures), keyed by content.
    private static var embeddedCache: [Data: CGImage] = [:]
    static func embedded(_ d: Data) -> CGImage? {
        if let i = embeddedCache[d] { return i }
        guard let src = CGImageSourceCreateWithData(d as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        if embeddedCache.count > 64 { embeddedCache.removeAll() }
        embeddedCache[d] = img
        return img
    }

    /// F67: the pictures of DWF markups on a sheet, drawn under the display list like underlays.
    static func drawMarkupPictures(for viewID: ElementID, model: BIMModel, in ctx: CGContext, viewToDevice: CGAffineTransform) {
        for e in model.owned(byView: viewID) {
            guard let m = e.markup, m.isLoaded else { continue }
            for p in m.pictures {
                guard let img = embedded(p.image) else { continue }
                ctx.saveGState()
                ctx.concatenate(viewToDevice)
                ctx.draw(img, in: CGRect(x: p.bounds.min.x + m.offset.x, y: p.bounds.min.y + m.offset.y, width: p.bounds.width, height: p.bounds.height))
                ctx.restoreGState()
            }
        }
    }
}
