import AppKit
import ArcusGeometry
import ArcusApplication

/// SFE: the snap feedback of the project's 2D canvas (`Canvas2DView.drawSnap` / `drawSnapLabel` / `drawGuides`) for other
/// canvases: RevitCraft's magenta markers, the light blue dash-dot tracking lines and the small grey label beside the
/// snap. `yDown` is true for flipped views (the Family Editor canvas); markers are drawn the same way up either way.
enum SnapMarkerRenderer {
    static func draw(_ s: SnapResult, in ctx: CGContext, bounds: CGRect, yDown: Bool, toScreen: (Vec2) -> CGPoint) {
        let p = toScreen(s.point)
        let axis = s.kind == .angle && (s.label == "HORIZONTAL" || s.label == "VERTICAL")
        drawGuides(s.guides, in: ctx, bounds: bounds, acrossView: axis, toScreen: toScreen)
        ctx.saveGState()
        ctx.setStrokeColor(Canvas2DView.snapColor.cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineDash(phase: 0, lengths: [])
        let r: CGFloat = 5
        // RevitCraft's marker coordinates run y down.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: p.x + x, y: yDown ? p.y + y : p.y - y) }
        func poly(_ q: [CGPoint], close: Bool = true) { ctx.move(to: q[0]); for c in q.dropFirst() { ctx.addLine(to: c) }; if close { ctx.closePath() }; ctx.strokePath() }
        switch s.kind {
        case .endpoint: ctx.stroke(CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        case .midpoint: poly([pt(0, -r), pt(r, r * 0.8), pt(-r, r * 0.8)])
        case .center:
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            poly([pt(-3, 0), pt(3, 0)], close: false)
        case .intersection, .gridIntersection:
            poly([pt(-r, -r), pt(r, r)], close: false); poly([pt(r, -r), pt(-r, r)], close: false)
        case .perpendicular:
            poly([pt(-r, r), pt(r, r)], close: false); poly([pt(-r * 0.2, r), pt(-r * 0.2, -r)], close: false)
            poly([pt(-r * 0.2, r * 0.2), pt(r * 0.4, r * 0.2)], close: false)
        case .tangent:
            let c = pt(0, 3)
            ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.7, width: r * 1.4, height: r * 1.4))
            poly([pt(-r, -r * 0.5), pt(r, -r * 0.5)], close: false)
        case .quadrant: poly([pt(0, -r), pt(r, 0), pt(0, r), pt(-r, 0)])
        case .nearest: poly([pt(-r, -r), pt(r, -r), pt(-r, r), pt(r, r)])
        case .midBetweenPoints:
            poly([pt(0, -r), pt(r, r * 0.8), pt(-r, r * 0.8)]); poly([pt(-r, -r * 0.2), pt(r, -r * 0.2)], close: false)
        case .parallel:
            poly([pt(-r, r * 0.4), pt(r * 0.4, -r)], close: false); poly([pt(-r * 0.4, r), pt(r, -r * 0.4)], close: false)
        case .extension:
            poly([pt(-4, -4), pt(4, 4)], close: false); poly([pt(4, -4), pt(-4, 4)], close: false)
        case .angle:
            if axis {
                // A hollow double arrow along the axis: two shaft lines and open heads.
                let d = s.label == "HORIZONTAL" ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1), n = CGVector(dx: -d.dy, dy: d.dx)
                let (len, head, w): (CGFloat, CGFloat, CGFloat) = (9, 4, 4.5)
                func q(_ along: CGFloat, _ across: CGFloat) -> CGPoint { CGPoint(x: p.x + d.dx * along + n.dx * across, y: p.y + d.dy * along + n.dy * across) }
                ctx.setLineWidth(1.3)
                for side: CGFloat in [1, -1] { poly([q(-(len - head), 1.4 * side), q(len - head, 1.4 * side)], close: false) }
                for sgn: CGFloat in [1, -1] {
                    let base = (len - head) * sgn
                    poly([q(len * sgn, 0), q(base, w), q(base, 1.4), q(base, -1.4), q(base, -w)])
                }
            }
        }
        ctx.restoreGState()
        if let text = Canvas2DView.snapTooltip(s), CanvasSettings.tooltipAssistance != .none {
            drawLabel(text, at: pt(8, 12), in: ctx, bounds: bounds, yDown: yDown)
        }
    }

    /// Dashed tracking lines (view coordinates); horizontal and vertical ones run across the view when `acrossView`.
    static func drawGuides(_ guides: [Segment2], in ctx: CGContext, bounds: CGRect, acrossView: Bool, toScreen: (Vec2) -> CGPoint) {
        guard !guides.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(srgbRed: 120 / 255, green: 170 / 255, blue: 230 / 255, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [12, 3, 2, 3])
        let span = max(bounds.width, bounds.height) * 2
        for g in guides {
            let a = toScreen(g.start), b = toScreen(g.end)
            let d = CGVector(dx: b.x - a.x, dy: b.y - a.y), len = hypot(d.dx, d.dy)
            if acrossView, len > 1e-6, abs(d.dx) < 1e-6 * len || abs(d.dy) < 1e-6 * len {
                let u = CGVector(dx: d.dx / len, dy: d.dy / len)
                ctx.move(to: CGPoint(x: a.x - u.dx * span, y: a.y - u.dy * span)); ctx.addLine(to: CGPoint(x: a.x + u.dx * span, y: a.y + u.dy * span))
            } else {
                ctx.move(to: a); ctx.addLine(to: b)
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// RevitCraft's snap label: small grey text in a flat light box with a grey border, hanging below-right of `corner`
    /// (on screen), kept inside the canvas.
    static func drawLabel(_ text: String, at corner: CGPoint, in ctx: CGContext, bounds: CGRect, yDown: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor(white: 60 / 255, alpha: 1)]
        let size = (text as NSString).size(withAttributes: attrs)
        let w = ceil(size.width) + 6, h = ceil(size.height) + 2
        var box = CGRect(x: corner.x + 3, y: yDown ? corner.y + 3 : corner.y - size.height - 3, width: w, height: h)
        box.origin.x = min(max(box.minX, bounds.minX + 2), bounds.maxX - 2 - box.width)
        box.origin.y = min(max(box.minY, bounds.minY + 2), bounds.maxY - 2 - box.height)
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 245 / 255, alpha: 1).cgColor)
        ctx.fill(box)
        ctx.setStrokeColor(NSColor(white: 170 / 255, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        (text as NSString).draw(at: CGPoint(x: box.minX + 3, y: box.minY + 1), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}
