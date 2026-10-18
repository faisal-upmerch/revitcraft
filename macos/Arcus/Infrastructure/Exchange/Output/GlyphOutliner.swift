import CoreGraphics
import CoreText
import Foundation
import ArcusGeometry
import ArcusDomain

/// F1: glyph outlines for Model Text from CoreText (installed into `ModelTextGlyphs` by the app). Lines are laid out with
/// CoreText (kerning, font fallback for missing glyphs) and every glyph's path is flattened into closed contours.
public enum GlyphOutliner {
    /// One line of text in `fontName` (a PostScript or family name; Arial, then Helvetica, when it isn't installed),
    /// scaled so the font's capital height is 1, with the baseline on y = 0 from x = 0.
    public static func outline(_ line: String, fontName: String) -> (contours: [[Vec2]], advance: Double) {
        let font = resolve(fontName)
        let cap = CTFontGetCapHeight(font)
        let scale = 1 / Double(cap > 0 ? cap : CTFontGetSize(font) * 0.716)
        let attributed = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let pen = Pen(scale: scale)
        for run in (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName].map { $0 as! CTFont } ?? font
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for k in 0..<count {
                var t = CGAffineTransform(translationX: positions[k].x, y: positions[k].y)
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[k], &t) else { continue }
                pen.draw(path)
            }
        }
        let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        return (pen.contours, width * scale)
    }

    /// Installs the outliner as Model Text's glyph source.
    public static func install() {
        ModelTextGlyphs.install { line, font in outline(line, fontName: font) }
    }

    static func resolve(_ name: String) -> CTFont {
        for n in [name, ModelTextData.defaultFont, "Helvetica"] where !n.isEmpty {
            let f = CTFontCreateWithName(n as CFString, 100, nil)
            let family = CTFontCopyFamilyName(f) as String, ps = CTFontCopyPostScriptName(f) as String
            if family.caseInsensitiveCompare(n) == .orderedSame || ps.caseInsensitiveCompare(n) == .orderedSame || (CTFontCopyFullName(f) as String).caseInsensitiveCompare(n) == .orderedSame {
                return f
            }
        }
        return CTFontCreateWithName("Helvetica" as CFString, 100, nil)
    }

    /// Collects a glyph path as closed polylines (quadratic curves in 6 steps, cubic ones in 8, as RevitCraft).
    final class Pen {
        let scale: Double
        var contours: [[Vec2]] = []
        var current: [Vec2] = []
        init(scale: Double) { self.scale = scale }

        func p(_ q: CGPoint) -> Vec2 { Vec2(Double(q.x) * scale, Double(q.y) * scale) }

        func flush() {
            var c = current
            current = []
            if c.count >= 2, c[0].distance(to: c[c.count - 1]) < 1e-9 { c.removeLast() }
            if c.count >= 3 { contours.append(c) }
        }

        func draw(_ path: CGPath) {
            path.applyWithBlock { el in
                let pts = el.pointee.points
                switch el.pointee.type {
                case .moveToPoint:
                    self.flush(); self.current = [self.p(pts[0])]
                case .addLineToPoint:
                    self.current.append(self.p(pts[0]))
                case .addQuadCurveToPoint:
                    let a = self.current.last ?? .zero, c = self.p(pts[0]), b = self.p(pts[1])
                    for k in 1...6 {
                        let t = Double(k) / 6, u = 1 - t
                        self.current.append(a * (u * u) + c * (2 * t * u) + b * (t * t))
                    }
                case .addCurveToPoint:
                    let a = self.current.last ?? .zero, c0 = self.p(pts[0]), c1 = self.p(pts[1]), b = self.p(pts[2])
                    for k in 1...8 {
                        let t = Double(k) / 8, u = 1 - t
                        self.current.append(a * (u * u * u) + c0 * (3 * u * u * t) + c1 * (3 * u * t * t) + b * (t * t * t))
                    }
                case .closeSubpath:
                    self.flush()
                @unknown default:
                    break
                }
            }
            flush()
        }
    }
}
