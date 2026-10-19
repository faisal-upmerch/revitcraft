import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// FM3: document icons for `.arcus`, `.arcusfamily` and `.arcusfurniture`, drawn in code so the build makes them
// (`arcus-bench --document-icons <Resources dir>`): a page with a folded corner, the kind's glyph and its name.

enum DocumentIcons {
    enum Kind: CaseIterable {
        case project, family, furniture
        var fileName: String {
            switch self {
            case .project: "ArcusProjectDocument.icns"
            case .family: "ArcusFamilyDocument.icns"
            case .furniture: "ArcusFurnitureDocument.icns"
            }
        }
        var label: String {
            switch self {
            case .project: "ARCUS"
            case .family: "FAMILY"
            case .furniture: "FURNITURE"
            }
        }
        /// Glyph colours (top, bottom of the gradient).
        var colors: (CGColor, CGColor) {
            switch self {
            case .project: (CGColor(srgbRed: 0.33, green: 0.56, blue: 0.93, alpha: 1), CGColor(srgbRed: 0.16, green: 0.36, blue: 0.76, alpha: 1))
            case .family: (CGColor(srgbRed: 0.98, green: 0.64, blue: 0.26, alpha: 1), CGColor(srgbRed: 0.86, green: 0.42, blue: 0.10, alpha: 1))
            case .furniture: (CGColor(srgbRed: 0.76, green: 0.52, blue: 0.30, alpha: 1), CGColor(srgbRed: 0.50, green: 0.31, blue: 0.16, alpha: 1))
            }
        }
    }

    /// Writes the three icons into `dir`; returns the files written.
    @discardableResult
    static func writeAll(to dir: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for k in Kind.allCases {
            let url = dir.appendingPathComponent(k.fileName)
            if let data = icns(k) { do { try data.write(to: url); out.append(url); print("wrote \(url.path)") } catch { print("error: \(url.path): \(error)") } }
        }
        return out
    }

    /// The ICNS container: PNG renditions from 16 to 1024 px (1x and 2x types).
    static func icns(_ k: Kind) -> Data? {
        let entries: [(String, Int)] = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                                        ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
        var cache: [Int: Data] = [:]
        var body = Data()
        for (type, px) in entries {
            guard let png = cache[px] ?? png(k, px) else { return nil }
            cache[px] = png
            body.append(contentsOf: Array(type.utf8))
            body.append(bigEndian(UInt32(png.count + 8)))
            body.append(png)
        }
        var file = Data("icns".utf8)
        file.append(bigEndian(UInt32(body.count + 8)))
        file.append(body)
        return file
    }

    static func bigEndian(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }

    /// One rendition as PNG.
    static func png(_ k: Kind, _ px: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(k, in: ctx, size: CGFloat(px))
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Draws the page, the glyph and the label (y up, origin bottom-left).
    static func draw(_ k: Kind, in c: CGContext, size s: CGFloat) {
        let page = CGRect(x: s * 0.16, y: s * 0.05, width: s * 0.68, height: s * 0.90)
        let fold = s * 0.17
        let path = CGMutablePath()
        path.move(to: CGPoint(x: page.minX, y: page.minY))
        path.addLine(to: CGPoint(x: page.maxX, y: page.minY))
        path.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
        path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
        path.addLine(to: CGPoint(x: page.minX, y: page.maxY))
        path.closeSubpath()
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.28))
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.addPath(path); c.fillPath()
        c.restoreGState()
        c.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
        c.setLineWidth(max(1, s * 0.006))
        c.addPath(path); c.strokePath()
        // The folded corner.
        let corner = CGMutablePath()
        corner.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
        corner.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
        corner.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
        corner.closeSubpath()
        c.setFillColor(CGColor(gray: 0.88, alpha: 1))
        c.addPath(corner); c.fillPath()
        c.addPath(corner); c.strokePath()

        // Glyph, filled with the kind's gradient.
        let g = CGRect(x: s * 0.27, y: s * (isSmall(s) ? 0.26 : 0.34), width: s * 0.46, height: s * 0.42)
        let glyph = glyphPath(k, in: g)
        c.saveGState()
        c.addPath(glyph); c.clip()
        let (top, bottom) = k.colors
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: g.maxY), end: CGPoint(x: 0, y: g.minY), options: [])
        }
        c.restoreGState()

        // The kind's name under the glyph (large renditions only).
        guard s >= 64 else { return }
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, s * (k == .furniture ? 0.072 : 0.085), nil)
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): k.colors.1,
                                                    NSAttributedString.Key(kCTKernAttributeName as String): s * 0.004]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: k.label, attributes: attrs))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        c.textPosition = CGPoint(x: (s - width) / 2, y: s * 0.13)
        CTLineDraw(line, c)
    }

    /// Small renditions have no label, so the glyph is centred.
    static func isSmall(_ s: CGFloat) -> Bool { s < 64 }

    /// The kind's glyph in `r`: a building, a cube, or a chair.
    static func glyphPath(_ k: Kind, in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) { p.addRect(CGRect(origin: pt(x, y), size: CGSize(width: w * r.width, height: h * r.height))) }
        switch k {
        case .project:
            // A gabled building with two towers.
            p.move(to: pt(0.30, 0)); p.addLine(to: pt(0.70, 0)); p.addLine(to: pt(0.70, 0.62)); p.addLine(to: pt(0.50, 0.86)); p.addLine(to: pt(0.30, 0.62)); p.closeSubpath()
            rect(0.04, 0, 0.22, 0.48)
            rect(0.74, 0, 0.22, 0.66)
        case .family:
            // An isometric cube: three faces.
            let c = pt(0.5, 0.5), w = r.width * 0.46, h = r.height * 0.27
            p.move(to: CGPoint(x: c.x, y: c.y + h)); p.addLine(to: CGPoint(x: c.x + w, y: c.y + h * 1.9)); p.addLine(to: CGPoint(x: c.x, y: c.y + h * 2.8)); p.addLine(to: CGPoint(x: c.x - w, y: c.y + h * 1.9)); p.closeSubpath()
            p.move(to: CGPoint(x: c.x - w * 1.02, y: c.y + h * 1.7)); p.addLine(to: CGPoint(x: c.x - w * 0.04, y: c.y + h * 0.8)); p.addLine(to: CGPoint(x: c.x - w * 0.04, y: c.y - h * 1.8)); p.addLine(to: CGPoint(x: c.x - w * 1.02, y: c.y - h * 0.9)); p.closeSubpath()
            p.move(to: CGPoint(x: c.x + w * 1.02, y: c.y + h * 1.7)); p.addLine(to: CGPoint(x: c.x + w * 0.04, y: c.y + h * 0.8)); p.addLine(to: CGPoint(x: c.x + w * 0.04, y: c.y - h * 1.8)); p.addLine(to: CGPoint(x: c.x + w * 1.02, y: c.y - h * 0.9)); p.closeSubpath()
        case .furniture:
            // A chair from the side: back, seat and legs.
            rect(0.22, 0.0, 0.10, 0.98)   // back leg and back
            rect(0.22, 0.42, 0.62, 0.11)  // seat
            rect(0.74, 0.0, 0.10, 0.45)   // front leg
            rect(0.32, 0.18, 0.42, 0.06)  // stretcher
        }
        return p
    }
}
