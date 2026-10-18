import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCanvasMetal
import ArcusViewport3D

// BL-CANVAS: selection feedback on the 2D canvas — area elements drawn in the selection colour (ARCUS-025), the model
// halftoned while sketching (ARCUS-048), element and drawing-aid tooltips (ARCUS-026/081), temporary dimension
// labels (ARCUS-080) and the wheel zoom step shared with 3D views (ARCUS-030).

/// How temporary dimension values are drawn: blue text in the size chosen in Settings, on a transparent or opaque
/// background (Settings ▸ Graphics).
enum TempDimLabelStyle {
    static var textColor: NSColor { Tokens.selection }
    static func attributes(active: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: CanvasSettings.tempDimTextSize, weight: active ? .semibold : .medium), .foregroundColor: textColor]
    }
    /// Box around a value of `size` centred at `mid` (also the click target).
    static func box(size: CGSize, mid: CGPoint) -> NSRect {
        NSRect(x: mid.x - size.width / 2 - 3, y: mid.y - size.height / 2 - 1, width: size.width + 6, height: size.height + 2)
    }
    /// Draws a value in its box. Transparent: the text only, on a thin halo of the canvas colour so it reads over
    /// linework; Opaque: a plain canvas-coloured box. Active (typing sets it) or hovered values get a thin outline.
    static func draw(_ text: String, in box: NSRect, active: Bool, highlighted: Bool, canvas: NSColor) {
        let attrs = attributes(active: active)
        let origin = NSPoint(x: box.minX + 3, y: box.minY + 1)
        switch CanvasSettings.tempDimBackground {
        case .opaque:
            canvas.setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
        case .transparent:
            var halo = attrs
            halo[.foregroundColor] = canvas.withAlphaComponent(0.9)
            halo[.strokeColor] = canvas.withAlphaComponent(0.9)
            halo[.strokeWidth] = 6.0
            (text as NSString).draw(at: origin, withAttributes: halo)
        }
        if active || highlighted {
            let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            textColor.withAlphaComponent(highlighted ? 0.9 : 0.5).setStroke()
            path.lineWidth = highlighted ? 1.5 : 0.75
            path.stroke()
        }
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }
}

extension Canvas2DView {
    // MARK: Area element highlight

    /// Categories drawn as regions whose outlines sit under walls in plan; selection and hover draw their boundary
    /// (and a light fill) above everything else so the highlight is always visible.
    static let highlightedAreaCategories: Set<Category> = [.floors, .roofs, .ceilings, .rooms, .areas, .buildingPads, .filledRegions, .topography, .shaftOpenings]

    func drawAreaHighlights(_ ctx: CGContext) {
        guard let g = graphics else { return }
        let sel = state.session.selection
        var tint: [ElementID: (NSColor, Bool)] = [:]
        for id in sel.preselectedIDs { tint[id] = (Tokens.preselection, false) }
        if let tool = state.activeTool { for id in tool.preview.highlight { tint[id] = (Tokens.preselection, false) } }
        for id in sel.ids { tint[id] = (Tokens.selection, true) }
        guard !tint.isEmpty else { return }
        for item in g.items where Self.highlightedAreaCategories.contains(item.category) {
            guard let id = item.elementID, let (color, selected) = tint[id] else { continue }
            var loops: [[Vec2]] = []
            for p in item.primitives {
                switch p {
                case .fill(let polys, _): loops += polys.map(\.points)
                case .polyline(let pts, true, _): loops.append(pts)
                default: break
                }
            }
            if loops.isEmpty { loops = item.hitPolygons.map(\.points) }
            guard !loops.isEmpty else { continue }
            let path = CGMutablePath()
            for l in loops where l.count >= 3 { path.addLines(between: l.map { toScreen($0) }); path.closeSubpath() }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setFillColor(color.withAlphaComponent(selected ? 0.12 : 0.07).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.addPath(path)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(selected ? 2.5 : 2)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: Sketch mode halftone

    /// True while a sketch (floor, roof, ceiling, region… boundary) is being drawn: the rest of the model is halftone.
    var isSketching: Bool { state.activeTool?.isSketchMode == true }

    /// Elements the GPU canvas draws halftone: everything in the view while sketching, nothing otherwise.
    func sketchHalftoneElements() -> Set<ElementID> {
        guard isSketching, let g = graphics else { return [] }
        return Set(g.items.compactMap(\.elementID))
    }

    /// The display list for the CoreGraphics path, halftoned while sketching.
    func sketchHalftoned(_ g: ViewGraphics) -> ViewGraphics {
        guard isSketching else { return g }
        var h = g
        h.items = g.items.map { item in
            var it = item
            it.primitives = item.primitives.map { p in
                switch p {
                case .polyline(let pts, let c, var st): st.halftone = true; return .polyline(pts, closed: c, st)
                case .arc(let a, var st): st.halftone = true; return .arc(a, st)
                case .fill(let polys, var f): f.halftone = true; return .fill(polys, f)
                case .text(var t): t.halftone = true; return .text(t)
                }
            }
            return it
        }
        return h
    }

    /// Per-draw updates of the GPU canvas and of tool colours that follow Settings.
    func syncFeedback(_ mv: MetalCanvasView?) {
        mv?.renderer?.halftoneElements = sketchHalftoneElements()
        SketchTool.alertColor = RGBColor.from(Tokens.alert)
    }

    // MARK: Tooltips

    /// Name of the element under the resting pointer ("Category : Family : Type"), with its Mark and level at High.
    var elementTooltipText: String? {
        let level = CanvasSettings.tooltipAssistance
        guard level == .normal || level == .high, state.activeTool == nil, let id = state.session.selection.preselection,
              let e = state.model[id] else { return nil }
        var s = describe(e)
        if level == .high {
            var extra: [String] = []
            if !e.mark.isEmpty { extra.append("Mark \(e.mark)") }
            if let l = state.model[e.levelID], l.level != nil { extra.append(l.name) }
            if !extra.isEmpty { s += "\n" + extra.joined(separator: " · ") }
        }
        return s
    }

    /// Filters the drawing-aid text by Tooltip Assistance: None hides everything, Minimal keeps snaps and drags only.
    func assistedTooltip(_ text: String?, isPrompt: Bool) -> String? {
        switch CanvasSettings.tooltipAssistance {
        case .none: return nil
        case .minimal: return isPrompt ? nil : text
        default: return text
        }
    }

    /// A compact tooltip beside the pointer, kept wholly inside the canvas: it flips to the other side of the pointer
    /// near the right or bottom edge and is clamped to every edge.
    func drawCompactTooltip(_ text: String, at m: NSPoint, _ ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        let maxWidth = max(80, min(320, bounds.width - 8))
        var size = (text as NSString).boundingRect(with: NSSize(width: maxWidth - 10, height: 400), options: [.usesLineFragmentOrigin], attributes: attrs).size
        size = CGSize(width: ceil(size.width), height: ceil(size.height))
        var box = NSRect(x: m.x + 12, y: m.y - size.height - 18, width: size.width + 10, height: size.height + 4)
        if box.maxX > bounds.maxX - 4 { box.origin.x = m.x - box.width - 8 }
        if box.minY < bounds.minY + 4 { box.origin.y = m.y + 14 }
        box.origin.x = min(max(box.minX, bounds.minX + 4), bounds.maxX - 4 - box.width)
        box.origin.y = min(max(box.minY, bounds.minY + 4), bounds.maxY - 4 - box.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.2).cgColor)
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(box)
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        (text as NSString).draw(with: NSRect(x: box.minX + 5, y: box.minY + 2, width: size.width, height: size.height),
                                options: [.usesLineFragmentOrigin], attributes: attrs)
    }

}
