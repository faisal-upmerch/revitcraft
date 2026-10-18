import CoreGraphics
import CoreText
import Foundation
import ArcusDomain
import ArcusOutput

/// A `GText` laid out once, in em units of its primary font, by GraphicsRenderer's own `TextLayout` (same font
/// choice, cap-height sizing, 1.7× line spacing, alignment, vertical anchor and wrapping). Positions scale linearly
/// with the cap height, so the same layout serves every zoom level.
nonisolated struct ShapedText: Sendable {
    struct Glyph: Sendable {
        var key: GlyphKey
        /// Glyph origin relative to the insertion point, em units of the primary font (x along the text, y up).
        var pen: SIMD2<Float>
        /// Run font size / primary font size (fallback fonts).
        var planeScale: Float
    }
    var glyphs: [Glyph]
    /// Primary font size / cap height.
    var emPerCap: Float
    /// Conservative reach of the text block from its insertion point, in em.
    var reachEm: Float
    /// Each line's left end, baseline and width, in em (for underlines).
    var lines: [SIMD3<Float>] = []
    /// The text block (widest line × last baseline to first cap top) as (minX, minY, maxX, maxY) in em.
    var block: SIMD4<Float> = .zero
}

/// Shapes texts with CoreText and memoises identical strings (room tags, marks and dimension values repeat a lot).
nonisolated struct TextShaper {
    /// Cap height (points) of the reference layout.
    static let referenceCap: Double = 100

    private struct Key: Hashable {
        var string: String
        var bold: Bool
        var italic: Bool
        var alignment: Int
        var anchor: Double
        var wrapRatio: Double
    }
    private var fonts = FontCache()
    private var cache: [Key: ShapedText?] = [:]
    /// Fonts of the runs that use each glyph (needed to rasterise missing glyphs into the atlas).
    private(set) var runFonts: [GlyphKey: CTFont] = [:]

    init() {}

    mutating func shape(_ t: GText) -> ShapedText? {
        guard t.height > 0, t.height.isFinite, !t.string.isEmpty else { return nil }
        let align: Int = switch t.alignment { case .left: 0; case .center: 1; case .right: 2 }
        let key = Key(string: t.string, bold: t.bold, italic: t.italic, alignment: align, anchor: t.verticalAnchor,
                      wrapRatio: max(0, t.wrapWidth) / t.height)
        if let hit = cache[key] { return hit }
        let shaped = layout(t)
        cache[key] = .some(shaped)
        return shaped
    }

    private mutating func layout(_ t: GText) -> ShapedText? {
        var unit = t
        unit.height = 1
        unit.wrapWidth = max(0, t.wrapWidth) / t.height
        unit.position = .zero
        unit.rotation = 0
        let layout = TextLayout(unit, ppm: Self.referenceCap, fonts: &fonts, color: nil)
        guard !layout.lines.isEmpty, layout.fontSize > 0 else { return nil }
        let primary = Double(layout.fontSize)
        var glyphs: [ShapedText.Glyph] = []
        var reach: Double = 0
        for line in layout.lines {
            guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { continue }
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let attrs = CTRunGetAttributes(run) as NSDictionary
                guard let fontRef = attrs[kCTFontAttributeName as String],
                      CFGetTypeID(fontRef as CFTypeRef) == CTFontGetTypeID() else { continue }
                let font = fontRef as! CTFont  // type checked above
                let name = CTFontCopyPostScriptName(font) as String
                let runSize = Double(CTFontGetSize(font))
                var ids = [CGGlyph](repeating: 0, count: count)
                var pos = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
                for i in 0..<count {
                    let k = GlyphKey(font: name, glyph: ids[i])
                    if runFonts[k] == nil { runFonts[k] = font }
                    let x = (Double(line.x) + Double(pos[i].x)) / primary
                    let y = (Double(line.baseline) + Double(pos[i].y)) / primary
                    glyphs.append(.init(key: k, pen: SIMD2(Float(x), Float(y)), planeScale: Float(runSize / primary)))
                    reach = max(reach, abs(x) + runSize / primary * 1.5, abs(y) + runSize / primary * 1.5)
                }
            }
        }
        var shaped = ShapedText(glyphs: glyphs, emPerCap: Float(primary / Self.referenceCap), reachEm: Float(reach))
        shaped.lines = layout.lines.map { SIMD3(Float(Double($0.x) / primary), Float(Double($0.baseline) / primary), Float(Double($0.width) / primary)) }
        let b = layout.blockRect
        if !b.isNull { shaped.block = SIMD4(Float(Double(b.minX) / primary), Float(Double(b.minY) / primary), Float(Double(b.maxX) / primary), Float(Double(b.maxY) / primary)) }
        return shaped
    }
}
