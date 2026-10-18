import CoreGraphics
import CoreText
import Foundation
import ArcusGeometry
import ArcusDomain

/// Draws Arcus display lists (`ViewGraphics`) into any CoreGraphics context: screen layers, bitmaps and vector PDF.
///
/// Conventions
/// - `viewToDevice` maps view units (model meters for views, paper meters for sheets) into the context's user space.
/// - `pointsPerPaperMeter` converts paper sizes (text heights, pen widths, drafting pattern spacing, dash lengths).
/// - Pen widths: `LineWeights.paperWidth(weight, scale: item.lineScale ?? g.scale)` millimeters on paper, converted to
///   device units and clamped to `RenderOptions.minimumDevicePixel`.
/// - Strokes use **round caps and round joins** (plotter-pen appearance: clean wall corners, dot patterns as dots).
///   Dash patterns come from `LinePatternKind.dashPattern` (paper mm); a pattern whose period is under ~1.5 device
///   pixels is drawn solid.
/// - Arcs are emitted as true arcs (`CGPath.addArc(… transform:)`), never tessellated; polylines are single subpaths.
/// - Consecutive strokes with identical resolved style are batched into one path (painter's order is preserved).
/// - Text is CoreText (real text in PDFs). `GText.height` is the **cap height** on paper; the font size is
///   `capHeight / (font.capHeight / font.pointSize)` (≈ 1.4 × height for Helvetica Neue). Baseline-to-baseline spacing
///   for multi-line text is 1.7 × cap height. Vertical anchor 0 puts the last line's baseline on the position,
///   1 puts the first line's cap top on it, 0.5 centers the block.
public enum GraphicsRenderer {
    /// Draws a display list. `viewToDevice` maps view units to device space; `pointsPerPaperMeter` is device points per
    /// paper meter (for text sizes, line weights, paper-based patterns). `clip` (device space) limits drawing and culls
    /// items whose bounds fall outside it; when nil the context's current clip bounds are used for culling.
    public static func draw(_ g: ViewGraphics, in ctx: CGContext, viewToDevice: CGAffineTransform, pointsPerPaperMeter: Double,
                            options: RenderOptions, clip: CGRect? = nil) {
        guard pointsPerPaperMeter.isFinite, pointsPerPaperMeter > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let clip { ctx.clip(to: clip) }
        var r = RenderPass(g: g, ctx: ctx, t: viewToDevice, ppm: pointsPerPaperMeter, options: options, clip: clip)
        r.run()
    }

    /// Screen helper: `modelToScreen` maps view units to the context's user space (it carries the zoom); the paper scale
    /// is derived from it and the view scale (points per paper meter = zoom × view scale denominator). Items whose bounds
    /// fall outside `visibleRect` (device space) are culled.
    public static func drawScreen(_ g: ViewGraphics, in ctx: CGContext, modelToScreen: CGAffineTransform, visibleRect: CGRect, options: RenderOptions) {
        let zoom = transformScale(modelToScreen)
        draw(g, in: ctx, viewToDevice: modelToScreen, pointsPerPaperMeter: zoom * Double(max(g.scale, 1)), options: options, clip: visibleRect)
    }

    /// Size in device points of a text block (width of the widest line × cap top of the first line to the baseline of the last).
    public static func textBounds(_ t: GText, pointsPerPaperMeter: Double) -> CGSize {
        var fonts = FontCache()
        return TextLayout(t, ppm: pointsPerPaperMeter, fonts: &fonts, color: nil).size
    }

    /// Uniform scale factor of an affine transform.
    static func transformScale(_ t: CGAffineTransform) -> Double {
        let det = Double(t.a * t.d - t.b * t.c)
        return abs(det).squareRoot()
    }
}

// MARK: - Render pass

private struct StrokeKey: Equatable {
    var width: CGFloat
    var color: RGBColor
    var dash: [CGFloat]
}

struct RenderPass {
    let g: ViewGraphics
    let ctx: CGContext
    let t: CGAffineTransform
    let ppm: Double
    let o: RenderOptions
    let devicePixel: CGFloat
    let dark: Bool
    /// Paper/canvas color used for masks and halftone.
    let canvas: RGBColor
    /// Device-space cull rectangle (nil = no culling).
    let deviceCull: CGRect?
    /// View-space cull rectangle, expanded by a margin for pen widths.
    let viewCull: Rect2?
    let viewUnitToDevice: Double
    var fonts = FontCache()
    private var batchKey: StrokeKey?
    private var batchPath = CGMutablePath()
    private var batchSegments = 0

    init(g: ViewGraphics, ctx: CGContext, t: CGAffineTransform, ppm: Double, options: RenderOptions, clip: CGRect?) {
        self.g = g; self.ctx = ctx; self.t = t; self.ppm = ppm; self.o = options
        let dm = ctx.userSpaceToDeviceSpaceTransform
        let ds = GraphicsRenderer.transformScale(dm)
        devicePixel = ds > 1e-9 ? CGFloat(1 / ds) : 1
        dark = options.darkCanvas && !options.printing
        if dark {
            if let b = options.background ?? options.canvasColor, b.luminance < 0.5 { canvas = b } else { canvas = RGBColor(0.13, 0.13, 0.14) }
        } else {
            canvas = options.background ?? options.canvasColor ?? .white
        }
        viewUnitToDevice = GraphicsRenderer.transformScale(t)
        let bounds = clip ?? ctx.boundingBoxOfClipPath
        if bounds.isNull || bounds.isInfinite || bounds.width > 1e8 || viewUnitToDevice <= 0 {
            deviceCull = nil; viewCull = nil
        } else {
            deviceCull = bounds
            let inv = t.inverted()
            let vr = bounds.applying(inv)
            let margin = 24 / viewUnitToDevice
            viewCull = Rect2(min: Vec2(Double(vr.minX), Double(vr.minY)), max: Vec2(Double(vr.maxX), Double(vr.maxY))).expanded(by: margin)
        }
    }

    mutating func run() {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.textMatrix = .identity
        // Only a pass that asks for a background paints one. Overlay passes (tool previews, drag previews) draw with
        // `background == nil` on top of the already-drawn view; painting the dark canvas colour there erased the view.
        if o.background != nil {
            let r = deviceCull ?? ctx.boundingBoxOfClipPath
            if !r.isNull && !r.isInfinite {
                ctx.setFillColor(cgColor(canvas))
                ctx.fill(r)
            }
        }
        for item in g.items {
            if item.layer == .overlay && !o.showOverlays { continue }
            if let id = item.elementID, o.hiddenElements.contains(id) { continue }
            let highlight = item.elementID.flatMap { o.highlight[$0] }
            let highlightFill = highlight == nil ? nil : item.elementID.flatMap { o.highlightFill[$0] }
            var contained = true
            if let vc = viewCull {
                if item.bounds.isEmpty || !vc.intersects(item.bounds) {
                    // Text extends beyond the insertion point stored in item bounds.
                    guard item.primitives.contains(where: { if case .text = $0 { return true }; return false }) else { continue }
                    contained = false
                } else {
                    contained = vc.contains(item.bounds)
                }
            }
            let scale = item.lineScale ?? g.scale
            for p in item.primitives {
                switch p {
                case .polyline(let pts, let closed, let st):
                    addPolyline(pts, closed: closed, st, scale: scale, highlight: highlight, cull: !contained)
                case .arc(let a, let st):
                    addArc(a, st, scale: scale, highlight: highlight, cull: !contained)
                case .fill(let polys, let f):
                    drawFill(polys, f, scale: scale, highlight: highlight, highlightFill: highlightFill, isMaskingLayer: item.layer == .masking)
                case .text(let tx):
                    drawText(tx, highlight: highlight)
                }
            }
        }
        flush()
    }

    // MARK: Colors

    func cgColor(_ c: RGBColor) -> CGColor {
        CGColor(srgbRed: CGFloat(clamp01(c.r)), green: CGFloat(clamp01(c.g)), blue: CGFloat(clamp01(c.b)), alpha: CGFloat(clamp01(c.a)))
    }

    /// Dark-canvas mapping: near-white → canvas, grays invert their lightness toward the canvas, dark colors are lifted.
    func darkMap(_ c: RGBColor) -> RGBColor {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let sat = mx - mn
        let lum = c.luminance
        if lum > 0.92 && sat < 0.08 { return RGBColor(canvas.r, canvas.g, canvas.b, c.a) }
        if sat < 0.12 {
            let cl = canvas.luminance
            let v = cl + (0.9 - cl) * (1 - lum)
            return RGBColor(v, v, min(1, v + 0.01), c.a)
        }
        if lum < 0.5 {
            let m = c.mixed(with: .white, amount: 0.5 - lum)
            return RGBColor(m.r, m.g, m.b, c.a)
        }
        return c
    }

    func ink(_ c: RGBColor, halftone: Bool, highlight: RGBColor?) -> RGBColor {
        if let h = highlight { return RGBColor(h.r, h.g, h.b, h.a * c.a) }
        var x = dark ? darkMap(c) : c
        if halftone {
            let m = x.mixed(with: canvas, amount: max(0, min(1, o.halftoneAmount)))
            x = RGBColor(m.r, m.g, m.b, x.a)
        }
        return x
    }

    // MARK: Strokes

    func strokeWidth(weight: Int, scale: Int) -> CGFloat {
        if o.thinLines && !o.printing { return devicePixel }
        let mm = LineWeights.paperWidth(weight, scale: max(scale, 1))
        return max(CGFloat(mm / 1000 * ppm), CGFloat(o.minimumDevicePixel))
    }

    private func key(_ st: GStroke, scale: Int, highlight: RGBColor?) -> StrokeKey {
        var dash: [CGFloat] = []
        let pattern = st.pattern.dashPattern
        if !pattern.isEmpty {
            let lengths = pattern.map { CGFloat($0 / 1000 * ppm) }
            if lengths.reduce(0, +) >= devicePixel * 1.5 { dash = lengths }
        }
        var width = strokeWidth(weight: st.weight, scale: scale)
        if highlight != nil { width = Self.highlightedWidth(width) }
        return StrokeKey(width: width, color: ink(st.color, halftone: st.halftone, highlight: highlight), dash: dash)
    }

    /// I1: highlighted outlines get heavier, as in RevitCraft (`paint_highlight`): under a point stays one point,
    /// otherwise 1.2 pt wider and at least 2 pt. The Metal canvas applies the same rule.
    static func highlightedWidth(_ w: CGFloat) -> CGFloat { w < 1 ? 1 : max(w + 1.2, 2) }

    /// `top` composited over `bottom` (straight alpha).
    static func over(_ top: RGBColor, _ bottom: RGBColor) -> RGBColor {
        let a = top.a + bottom.a * (1 - top.a)
        guard a > 1e-9 else { return RGBColor(top.r, top.g, top.b, 0) }
        func ch(_ t: Double, _ b: Double) -> Double { (t * top.a + b * bottom.a * (1 - top.a)) / a }
        return RGBColor(ch(top.r, bottom.r), ch(top.g, bottom.g), ch(top.b, bottom.b), a)
    }

    @inline(__always) func dev(_ p: Vec2) -> CGPoint {
        CGPoint(x: t.a * CGFloat(p.x) + t.c * CGFloat(p.y) + t.tx, y: t.b * CGFloat(p.x) + t.d * CGFloat(p.y) + t.ty)
    }

    private mutating func begin(_ k: StrokeKey) {
        if batchKey != k || batchSegments > 20_000 {
            flush()
            batchKey = k
        }
    }

    mutating func flush() {
        guard let k = batchKey, batchSegments > 0 else { batchKey = nil; return }
        ctx.setLineWidth(k.width)
        ctx.setStrokeColor(cgColor(k.color))
        ctx.setLineDash(phase: 0, lengths: k.dash)
        ctx.addPath(batchPath)
        ctx.strokePath()
        batchPath = CGMutablePath()
        batchSegments = 0
        batchKey = nil
    }

    mutating func addPolyline(_ pts: [Vec2], closed: Bool, _ st: GStroke, scale: Int, highlight: RGBColor?, cull: Bool) {
        guard pts.count >= 2 else { return }
        if cull, let vc = viewCull {
            var r = Rect2.empty
            for p in pts { r.include(p) }
            if !vc.intersects(r) { return }
        }
        begin(key(st, scale: scale, highlight: highlight))
        batchPath.move(to: dev(pts[0]))
        for i in 1..<pts.count { batchPath.addLine(to: dev(pts[i])) }
        if closed { batchPath.closeSubpath() }
        batchSegments += pts.count
    }

    mutating func addArc(_ a: Arc2, _ st: GStroke, scale: Int, highlight: RGBColor?, cull: Bool) {
        guard a.radius > 0, a.radius.isFinite, a.sweep != 0 else { return }
        if cull, let vc = viewCull, !vc.intersects(a.bounds) { return }
        begin(key(st, scale: scale, highlight: highlight))
        batchPath.move(to: dev(a.start))
        batchPath.addArc(center: CGPoint(x: a.center.x, y: a.center.y), radius: CGFloat(a.radius), startAngle: CGFloat(a.startAngle),
                         endAngle: CGFloat(a.startAngle + a.sweep), clockwise: a.sweep < 0, transform: t)
        batchSegments += 8
    }

    // MARK: Fills

    mutating func drawFill(_ polys: [Polygon2], _ f: GFill, scale: Int, highlight: RGBColor?, highlightFill: RGBColor? = nil, isMaskingLayer: Bool) {
        flush()
        let path = CGMutablePath()
        for poly in polys where poly.points.count >= 3 {
            path.move(to: dev(poly.points[0]))
            for i in 1..<poly.points.count { path.addLine(to: dev(poly.points[i])) }
            path.closeSubpath()
        }
        if path.isEmpty { return }
        let box = path.boundingBoxOfPath
        if let dc = deviceCull, !dc.intersects(box.insetBy(dx: -1, dy: -1)) { return }
        if f == GFill.mask || (isMaskingLayer && f.pattern == .solid && f.color == .white) {
            ctx.setFillColor(cgColor(canvas))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            return
        }
        let alpha = max(0, min(1, 1 - f.transparency))
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if alpha < 1 { ctx.setAlpha(CGFloat(alpha)) }
        if let bg = f.background {
            let c = dark ? darkMap(bg) : bg
            ctx.setFillColor(cgColor(c))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        }
        var color = ink(f.color, halftone: f.halftone, highlight: nil)
        if let t = highlightFill { color = Self.over(t, color) }
        else if let h = highlight { color = color.mixed(with: RGBColor(h.r, h.g, h.b, color.a), amount: 0.65) }
        if f.pattern == .solid {
            ctx.setFillColor(cgColor(color))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            return
        }
        if let h = f.hatch, !h.isEmpty, drawHatch(polys, h, path: path, scale: max(scale, 1), color: color) { return } // W4-HATCH: line-family patterns
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        let visible = ctx.boundingBoxOfClipPath
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
        // Pattern space: paper millimeters (drafting) or model meters (model patterns), anchored at the view origin.
        let s = max(scale, 1)
        let devicePerUnit = f.isModelPattern ? ppm / Double(s) : ppm / 1000
        let lin = viewUnitToDevice > 0
            ? CGAffineTransform(a: t.a / CGFloat(viewUnitToDevice), b: t.b / CGFloat(viewUnitToDevice),
                                c: t.c / CGFloat(viewUnitToDevice), d: t.d / CGFloat(viewUnitToDevice), tx: 0, ty: 0)
            : .identity
        let origin = dev(.zero)
        let frame = lin.scaledBy(x: CGFloat(devicePerUnit), y: CGFloat(devicePerUnit)).concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
        let lineWidth = strokeWidth(weight: 1, scale: s)
        let ok = FillPatterns.draw(f.pattern, isModel: f.isModelPattern, in: ctx, visible: visible, frame: frame,
                                   devicePerUnit: devicePerUnit, color: cgColor(color), lineWidth: lineWidth, devicePixel: devicePixel)
        if !ok {
            // Too dense at this zoom (or too many elements): a light tint instead of a moiré.
            ctx.setFillColor(cgColor(color.mixed(with: RGBColor(canvas.r, canvas.g, canvas.b, color.a), amount: 0.8)))
            ctx.fill(visible)
        }
    }

    /// W4-HATCH: draws a project fill pattern's line families, pre-clipped to the region by `HatchGenerator` (cached per
    /// region, pattern and scale). Returns false when the hatch is over budget or denser than ~2 device pixels, so the
    /// caller falls back to the procedural kind (which tints at that density).
    mutating func drawHatch(_ polys: [Polygon2], _ h: HatchPattern, path: CGPath, scale: Int, color: RGBColor) -> Bool {
        guard let lines = HatchCache.shared.lines(polys, h, scale: scale) else { return false }
        if lines.minSpacing * viewUnitToDevice < Double(devicePixel) * 2 {
            // Denser than two device pixels at this zoom: a light tint instead of a moiré.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(cgColor(color.mixed(with: RGBColor(canvas.r, canvas.g, canvas.b, color.a), amount: 0.8)))
            ctx.fill(ctx.boundingBoxOfClipPath)
            ctx.restoreGState()
            return true
        }
        let lineWidth = strokeWidth(weight: 1, scale: scale)
        let cull = deviceCull.map { $0.insetBy(dx: -lineWidth, dy: -lineWidth) }
        let strokes = CGMutablePath()
        for seg in lines.segments {
            let a = dev(seg.start), b = dev(seg.end)
            if let cull, !cull.contains(a), !cull.contains(b), !cull.intersects(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))) { continue }
            strokes.move(to: a); strokes.addLine(to: b)
        }
        let dots = CGMutablePath()
        let r = max(lineWidth * 0.75, devicePixel * 0.6)
        for d in lines.dots {
            let c = dev(d)
            if let cull, !cull.contains(c) { continue }
            dots.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(cgColor(color))
        ctx.setFillColor(cgColor(color))
        if !strokes.isEmpty { ctx.addPath(strokes); ctx.strokePath() }
        if !dots.isEmpty { ctx.addPath(dots); ctx.fillPath() }
        return true
    }

    // MARK: Text

    mutating func drawText(_ tx: GText, highlight: RGBColor?) {
        guard tx.height > 0, tx.height.isFinite, !tx.string.isEmpty else { return }
        let p = dev(tx.position)
        let capPts = tx.height * ppm
        if let dc = deviceCull {
            let longest = tx.string.split(separator: "\n").map(\.count).max() ?? tx.string.count
            let lines = Double(tx.string.split(separator: "\n", omittingEmptySubsequences: false).count)
            var reach = capPts * (Double(longest) * 1.0 + lines * 1.8 + 1)
            if tx.wrapWidth > 0 { reach = max(tx.wrapWidth * ppm, capPts * 2) + capPts * lines * 4 }
            if !dc.insetBy(dx: -CGFloat(reach), dy: -CGFloat(reach)).contains(p) { return }
        }
        // Sub-pixel text is unreadable on screen; PDFs keep every string (searchable).
        if !o.printing && capPts < Double(devicePixel) * 0.75 { return }
        flush()
        let color = ink(tx.color, halftone: tx.halftone, highlight: highlight)
        let layout = TextLayout(tx, ppm: ppm, fonts: &fonts, color: cgColor(color))
        guard !layout.lines.isEmpty else { return }
        var u = t.applyingToVector(CGVector(dx: cos(tx.rotation), dy: sin(tx.rotation)))
        var v = t.applyingToVector(CGVector(dx: -sin(tx.rotation), dy: cos(tx.rotation)))
        let ul = (u.dx * u.dx + u.dy * u.dy).squareRoot(), vl = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard ul > 0, vl > 0 else { return }
        u = CGVector(dx: u.dx / ul, dy: u.dy / ul); v = CGVector(dx: v.dx / vl, dy: v.dy / vl)
        ctx.saveGState()
        ctx.concatenate(CGAffineTransform(a: u.dx, b: u.dy, c: v.dx, d: v.dy, tx: p.x, ty: p.y))
        ctx.textMatrix = .identity
        let cap = CGFloat(capPts)
        if tx.opaque {
            // Opaque text masks the block (plus a margin, and room for descenders) with the canvas colour first.
            let box = TextLayout.backgroundRect(layout.blockRect, cap: cap)
            ctx.setFillColor(cgColor(canvas))
            ctx.fill(box)
        }
        for line in layout.lines {
            ctx.textPosition = CGPoint(x: line.x, y: line.baseline)
            CTLineDraw(line.line, ctx)
        }
        if tx.underline {
            ctx.setStrokeColor(cgColor(color))
            ctx.setLineWidth(max(cap * CGFloat(GText.underlineThickness), devicePixel))
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [])
            for line in layout.lines where line.width > 0 {
                let y = line.baseline - cap * CGFloat(GText.underlineOffset)
                ctx.move(to: CGPoint(x: line.x, y: y))
                ctx.addLine(to: CGPoint(x: line.x + line.width, y: y))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

extension CGAffineTransform {
    func applyingToVector(_ v: CGVector) -> CGVector { CGVector(dx: a * v.dx + c * v.dy, dy: b * v.dx + d * v.dy) }
}

@inline(__always) func clamp01(_ x: Double) -> Double { x.isFinite ? max(0, min(1, x)) : 0 }
