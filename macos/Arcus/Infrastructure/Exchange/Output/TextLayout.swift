import CoreGraphics
import CoreText
import Foundation
import ArcusDomain

/// Font lookup for drawing text. Helvetica Neue (regular / bold) with a system-font fallback.
/// Fonts are sized so that their cap height equals the requested paper text height.
public struct FontCache {
    private struct Base { let font: CTFont; let capRatio: CGFloat }
    /// Keyed by style: bit 0 = bold, bit 1 = italic.
    private var bases: [Int: Base] = [:]
    private var sized: [Int: CTFont] = [:]

    public static let regularName = "HelveticaNeue"
    public static let boldName = "HelveticaNeue-Bold"
    public static let italicName = "HelveticaNeue-Italic"
    public static let boldItalicName = "HelveticaNeue-BoldItalic"

    public init() {}

    private static func makeBase(bold: Bool, italic: Bool) -> CTFont {
        let name = italic ? (bold ? boldItalicName : italicName) : (bold ? boldName : regularName)
        let f = CTFontCreateWithName(name as CFString, 12, nil)
        if (CTFontCopyPostScriptName(f) as String) == name { return f }
        let ui = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, 12, nil) ?? f
        guard italic else { return ui }
        return CTFontCreateCopyWithSymbolicTraits(ui, 12, nil, .traitItalic, .traitItalic) ?? ui
    }

    private mutating func base(bold: Bool, italic: Bool) -> Base {
        let style = (bold ? 1 : 0) | (italic ? 2 : 0)
        if let b = bases[style] { return b }
        let f = FontCache.makeBase(bold: bold, italic: italic)
        let cap = CTFontGetCapHeight(f)
        let b = Base(font: f, capRatio: cap > 0 ? cap / CTFontGetSize(f) : 0.714)
        bases[style] = b
        return b
    }

    /// Font whose cap height is `capHeight` points.
    public mutating func font(bold: Bool, capHeight: CGFloat) -> CTFont { font(bold: bold, italic: false, capHeight: capHeight) }

    /// Font whose cap height is `capHeight` points, in the regular, bold, italic or bold italic face.
    public mutating func font(bold: Bool, italic: Bool, capHeight: CGFloat) -> CTFont {
        let b = base(bold: bold, italic: italic)
        let size = max(0.01, capHeight / b.capRatio)
        let style = (bold ? 1 : 0) | (italic ? 2 : 0)
        let key = Int((size * 64).rounded()) * 4 + style
        if let f = sized[key] { return f }
        let f = CTFontCreateCopyWithAttributes(b.font, CGFloat(key / 4) / 64, nil, nil)
        sized[key] = f
        return f
    }
}

/// CoreText layout of a `GText` in local text space (points, x along the text, y up, origin at the insertion point).
public struct TextLayout {
    public struct Line {
        public let line: CTLine
        public let x: CGFloat
        public let baseline: CGFloat
        public let width: CGFloat
    }
    public var lines: [Line] = []
    public var size: CGSize = .zero
    public var fontSize: CGFloat = 0

    /// Baseline-to-baseline distance as a multiple of the cap height.
    public static let lineSpacing: CGFloat = 1.7

    public init(_ t: GText, ppm: Double, fonts: inout FontCache, color: CGColor?) {
        let cap = CGFloat(t.height * ppm)
        guard cap > 0, cap.isFinite, !t.string.isEmpty else { return }
        let font = fonts.font(bold: t.bold, italic: t.italic, capHeight: cap)
        fontSize = CTFontGetSize(font)
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let color {
            attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        } else {
            attrs[NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)] = true
        }
        let wrap = CGFloat(max(0, t.wrapWidth) * ppm)
        let text = t.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var ctLines: [(CTLine, CGFloat)] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = NSAttributedString(string: String(para), attributes: attrs)
            if wrap > 0 && s.length > 0 {
                let ts = CTTypesetterCreateWithAttributedString(s)
                var start = 0
                var guardCount = 0
                while start < s.length && guardCount < 10_000 {
                    guardCount += 1
                    var count = CTTypesetterSuggestLineBreak(ts, start, Double(wrap))
                    if count <= 0 { count = 1 }
                    let line = CTTypesetterCreateLine(ts, CFRange(location: start, length: count))
                    ctLines.append((line, TextLayout.width(line)))
                    start += count
                }
            } else {
                let line = CTLineCreateWithAttributedString(s)
                ctLines.append((line, TextLayout.width(line)))
            }
        }
        let n = CGFloat(ctLines.count)
        let step = cap * TextLayout.lineSpacing
        let blockHeight = cap + (n - 1) * step
        let anchor = CGFloat(max(0, min(1, t.verticalAnchor)))
        let top = blockHeight * (1 - anchor)
        var maxW: CGFloat = 0
        for (i, (line, w)) in ctLines.enumerated() {
            let x: CGFloat
            switch t.alignment {
            case .left: x = 0
            case .center: x = -w / 2
            case .right: x = -w
            }
            lines.append(Line(line: line, x: x, baseline: top - cap - CGFloat(i) * step, width: w))
            maxW = max(maxW, w)
        }
        size = CGSize(width: maxW, height: blockHeight)
    }

    /// The text block in local text space: from the widest line's left to its right, and from the last line's baseline
    /// to the first line's cap top.
    public var blockRect: CGRect {
        guard !lines.isEmpty else { return .null }
        let minX = lines.map(\.x).min() ?? 0, maxX = lines.map { $0.x + $0.width }.max() ?? 0
        let bottom = lines.map(\.baseline).min() ?? 0
        return CGRect(x: minX, y: bottom, width: maxX - minX, height: size.height)
    }

    /// The area an opaque text masks: the block plus `GText.backgroundMargin` cap heights, and room for descenders.
    public static func backgroundRect(_ block: CGRect, cap: CGFloat) -> CGRect {
        guard !block.isNull else { return .null }
        let m = cap * CGFloat(GText.backgroundMargin)
        return CGRect(x: block.minX - m, y: block.minY - m - cap * 0.25, width: block.width + 2 * m, height: block.height + 2 * m + cap * 0.25)
    }

    public static func width(_ line: CTLine) -> CGFloat {
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        return max(0, w)
    }
}
