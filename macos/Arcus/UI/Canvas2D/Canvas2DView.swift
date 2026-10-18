import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusCanvasMetal

/// The 2D drawing surface for plans, sections, elevations, drafting views and sheets. Purpose-built AppKit view
/// drawing cached vector display lists; interaction is routed to tools and the selection model.
///
/// Rendering: on Metal 4 GPUs the display list is drawn by a `MetalCanvasView` subview (retained GPU scene; panning,
/// zooming and highlight changes only update uniforms and small tables). This view then draws only the backdrop (canvas
/// colour, sheet paper, underlays) beneath it, and a transparent `CanvasOverlayView` above it draws the interactive
/// overlays (grips, temporary dimensions, snaps, selection rectangles). Without Metal 4 — or with
/// `ARCUS_CANVAS=coregraphics` — everything is drawn here with CoreGraphics, as PDF and print always are.
final class Canvas2DView: NSView, NSTextFieldDelegate {
    unowned let state: DocumentState
    let viewID: ElementID
    private(set) var graphics: ViewGraphics?
    private var itemGrid = SpatialGrid<Int>(cellSize: 5)
    /// Points per view unit.
    var zoom: Double = 20 { didSet { viewportEditor?.sync(); inPlaceText?.reposition() } }
    /// View-coordinate point at the center of the bounds.
    var center = Vec2.zero { didSet { viewportEditor?.sync(); inPlaceText?.reposition() } }
    /// Text being typed on the canvas (W2-ANNOT).
    var inPlaceText: InPlaceTextEditor?
    /// WP6a viewport activation: the sheet canvas hosting this (embedded) view canvas, and a sheet's active viewport editor.
    weak var sheetHost: Canvas2DView?
    var viewportEditor: ViewportEditor?
    private var didFit = false
    /// True once the user pans or zooms; until then the view keeps refitting as the window resizes.
    private var userAdjusted = false
    private var listener: UUID?
    private var selectionObservation: Task<Void, Never>?

    private enum Drag { case none, window(NSPoint), pan(NSPoint), tool, selectDrag, zoomRegion(NSPoint) }
    private var drag: Drag = .none
    private var dragCurrent: NSPoint?
    private var mouseDownLocation: NSPoint?
    private var lastMouse: NSPoint?
    private var snap: SnapResult?
    private var numericField: NSTextField?
    /// What a committed numeric field applies to: the active tool, the drag in progress, or a selection dimension.
    private enum NumericTarget { case tool, drag, dimension(SelectionDimension) }
    private var numericTarget = NumericTarget.tool
    /// The mouse was released while a typed drag value was being entered: the drag waits for Return or Esc.
    private var dragAwaitingValue = false
    /// Snap chosen with Tab while a tool runs; it holds while the pointer stays where Tab was pressed.
    private var tabSnap: (candidates: [SnapResult], index: Int, at: NSPoint)?
    private lazy var selectTool = SelectTool(ctx: toolContext)
    var zoomRegionArmed = false
    private var trackingArea: NSTrackingArea?
    /// GPU renderer for the display list and the view drawing the interactive overlays above it (nil: CoreGraphics path).
    private var metalView: MetalCanvasView?
    private var overlayView: CanvasOverlayView?
    /// The snap marker position last drawn on screen (diagnostics and QA: what the user actually sees).
    private(set) var lastDrawnSnap: Vec2?
    /// Cursor tooltip (see `drawCursorTooltip`).
    private var cursorTooltipVisible = false
    private var tooltipTimer: Timer?
    static var usesMetal: Bool {
        MetalCanvasContext.isSupported && ProcessInfo.processInfo.environment["ARCUS_CANVAS"] != "coregraphics"
    }

    init(state: DocumentState, viewID: ElementID) {
        self.state = state
        self.viewID = viewID
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        listener = state.graphics.listen(viewID) { [weak self] g in self?.setGraphics(g) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setUpMetal()
        observeSelection()
        if state.model[viewID]?.sheet != nil { registerForDraggedTypes([.string]) } // WP6a: drop views onto sheets
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayOptionsChanged), name: .arcusCanvasSettingsChanged, object: nil) // BL-CANVAS
    }
    @objc private func displayOptionsChanged() { needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    private func setUpMetal() {
        guard Self.usesMetal else { return }
        let mv = MetalCanvasView(frame: bounds)
        guard mv.renderer != nil else { return }
        mv.autoresizingMask = [.width, .height]
        mv.paintsBackground = false
        addSubview(mv)
        let ov = CanvasOverlayView(frame: bounds)
        ov.autoresizingMask = [.width, .height]
        ov.canvas = self
        addSubview(ov, positioned: .above, relativeTo: mv)
        metalView = mv
        overlayView = ov
    }

    private func syncMetal() {
        guard let mv = metalView else { return }
        mv.viewToDevice = viewToDevice
        mv.pointsPerPaperMeter = zoom * scaleDenominator
        let opts = renderOptions()
        mv.options = opts
        var po = RenderOptions()
        po.darkCanvas = opts.darkCanvas
        po.canvasColor = opts.background
        mv.overlayOptions = po
        mv.setOverlay(primitives: previewPrimitives, scale: graphics?.scale ?? 100)
        overlayView?.needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    var isSheet: Bool { state.model[viewID]?.sheet != nil }
    var viewElement: Element? { state.model[viewID] }
    var toolContext: ToolContext {
        let c = state.toolContext(for: viewID)
        c.pixel = 1 / max(zoom, 1e-9)
        c.currentTypes = state.currentTypes
        return c
    }

    private func observeSelection() {
        withObservationTracking {
            _ = state.session.selection.ids
            _ = state.session.selection.preselection
            _ = state.thinLines
            _ = state.toolRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.needsDisplay = true
                self?.updateAccessibility()
                self?.observeSelection()
            }
        }
    }

    func setGraphics(_ g: ViewGraphics) {
        graphics = g
        metalView?.setGraphics(g)
        var grid = SpatialGrid<Int>(cellSize: max(0.5, Double(g.scale) / 20))
        for (i, item) in g.items.enumerated() where item.selectable && item.elementID != nil && !item.bounds.isEmpty {
            grid.insert(i, bounds: item.bounds)
        }
        itemGrid = grid
        let ctx = state.toolContext(for: viewID)
        ctx.snapIndex = SnapIndex(graphics: g, model: state.model, view: state.model[viewID] ?? Element(id: viewID, category: .views, data: .view(ViewData(kind: .drafting))))
        if !didFit && bounds.width > 10 && sheetHost == nil { zoomToFit() }
        needsDisplay = true
        updateAccessibility()
        viewportEditor?.sync(); sheetHost?.viewportEditor?.sync() // WP6a
    }

    func toolChanged() {
        if let child = viewportEditor?.child { child.toolChanged(); return } // WP6a
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if state.activeTool != nil { window?.makeFirstResponder(self) }
    }

    // MARK: Coordinates

    var viewToDevice: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: bounds.midX - center.x * zoom, ty: bounds.midY - center.y * zoom)
    }
    func toView(_ p: NSPoint) -> Vec2 { Vec2((p.x - bounds.midX) / zoom + center.x, (p.y - bounds.midY) / zoom + center.y) }
    func toScreen(_ v: Vec2) -> NSPoint { NSPoint(x: (v.x - center.x) * zoom + bounds.midX, y: (v.y - center.y) * zoom + bounds.midY) }
    var scaleDenominator: Double { Double(max(graphics?.scale ?? 1, 1)) }

    func zoomToFit() {
        guard let g = graphics, bounds.width > 10, bounds.height > 10 else { return }
        var r = isSheet ? g.extents : (g.crop ?? g.extents)
        if !isSheet, let crop = g.crop {
            // Include annotations that belong with the cropped drawing (level and grid heads, dimensions just
            // outside the crop) but not far-away markers.
            let near = crop.expanded(by: max(crop.width, crop.height) * 0.25)
            for item in g.items where item.layer == .annotation && !item.bounds.isEmpty && near.contains(item.bounds.center) {
                r = r.union(item.bounds.intersection(near))
            }
        }
        if r.isEmpty { r = Rect2(center: .zero, halfSize: Vec2(10, 10)) }
        let margin = 0.08
        let fit = fitRect // W4-SHELL: the part of the canvas not under a floating dock
        let zx = fit.width * (1 - 2 * margin) / max(r.width, 1e-6)
        let zy = fit.height * (1 - 2 * margin) / max(r.height, 1e-6)
        zoom = max(1e-4, min(zx, zy))
        center = centered(r.center, in: fit)
        didFit = true
        needsDisplay = true
    }

    func zoom(to r: Rect2) {
        guard !r.isEmpty else { return }
        let fit = fitRect // W4-SHELL
        let zx = fit.width * 0.8 / max(r.width, 0.5), zy = fit.height * 0.8 / max(r.height, 0.5)
        zoom = min(zx, zy)
        center = centered(r.center, in: fit)
        needsDisplay = true
    }

    /// The visible part of the canvas (the safe area excludes the floating docks), or the whole bounds when the safe
    /// area is degenerate. // W4-SHELL
    var fitRect: NSRect {
        let s = safeAreaRect
        return s.width > 40 && s.height > 40 ? s : bounds
    }
    /// The model point that must sit at the canvas centre for `p` to sit at the centre of `rect` (at the current zoom). // W4-SHELL
    func centered(_ p: Vec2, in rect: NSRect) -> Vec2 {
        Vec2(p.x - (rect.midX - bounds.midX) / zoom, p.y - (rect.midY - bounds.midY) / zoom)
    }

    func zoom(by factor: Double, at p: NSPoint) {
        userAdjusted = true
        let before = toView(p)
        zoom = min(max(zoom * factor, 1e-3), 1e6)
        let after = toView(p)
        center = center + (before - after)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if (!didFit || !userAdjusted) && graphics != nil && newSize.width > 10 && sheetHost == nil { zoomToFit() }
    }

    // MARK: Drawing

    override var isOpaque: Bool { true }
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func draw(_ dirtyRect: NSRect) {
        // Each redraw request lands here once: refresh the GPU layer and the overlay layer (camera, options, previews) too.
        syncFeedback(metalView) // BL-CANVAS: sketch halftone, alert colour
        if metalView != nil { syncMetal() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(canvasColor.cgColor)
        ctx.fill(dirtyRect)
        guard let g = graphics else {
            if metalView == nil { drawCentered("Building view…") }
            return
        }
        if isSheet {
            let paper = CGRect(origin: toScreen(g.extents.min), size: CGSize(width: g.extents.width * zoom, height: g.extents.height * zoom))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(paper)
            ctx.restoreGState()
        }
        UnderlayRenderer.draw(for: viewID, model: state.model, in: ctx, viewToDevice: viewToDevice)
        // Metal draws the display list and previews in its own layer above; overlays draw in the overlay layer.
        guard metalView == nil else { return }
        let ppm = zoom * scaleDenominator
        GraphicsRenderer.draw(sketchHalftoned(g), in: ctx, viewToDevice: viewToDevice, pointsPerPaperMeter: ppm, options: renderOptions(), clip: dirtyRect) // BL-CANVAS
        viewportEditor?.drawDimming(in: ctx) // WP6a
        let previews = previewPrimitives
        if !previews.isEmpty {
            let pg = ViewGraphics(viewID: viewID, scale: g.scale, items: [GItem(elementID: nil, category: .views, layer: .overlay, primitives: previews, selectable: false)],
                                  extents: .empty, crop: nil, modelRevision: 0)
            var po = RenderOptions()
            po.background = nil
            po.darkCanvas = !isPaper && isDark
            po.canvasColor = isPaper ? .white : RGBColor.from(canvasColor)
            GraphicsRenderer.draw(pg, in: ctx, viewToDevice: viewToDevice, pointsPerPaperMeter: ppm, options: po, clip: dirtyRect)
        }
        drawOverlays(ctx)
    }

    private var canvasColor: NSColor { sheetHost != nil ? NSColor.white : isSheet ? Tokens.sheetBackdrop : Tokens.canvas }

    /// Options for the display list: thin lines, canvas colour, Increase Contrast, selection/preselection/tool highlight.
    private func renderOptions() -> RenderOptions {
        var opts = RenderOptions()
        opts.thinLines = state.thinLines
        opts.background = isPaper ? .white : RGBColor.from(canvasColor)
        opts.darkCanvas = !isPaper && isDark
        if AccessibilityPrefs.increaseContrast {
            // Increase Contrast: halftoned (underlay, linked, other-phase) graphics stay legible and hairlines get heavier.
            opts.halftoneAmount = 0.3
            opts.minimumDevicePixel = 1
        }
        var hl: [ElementID: RGBColor] = [:]
        var fills: [ElementID: RGBColor] = [:]
        let sel = RGBColor.from(Tokens.selection)
        let pre = RGBColor.from(Tokens.preselection)
        for id in state.session.selection.ids { hl[id] = sel; fills[id] = Self.selectionFill }
        for p in state.session.selection.preselectedIDs where hl[p] == nil { hl[p] = pre; fills[p] = RGBColor(pre.r, pre.g, pre.b, 60 / 255) }
        if let tool = state.activeTool { for id in tool.preview.highlight { hl[id] = pre; fills[id] = RGBColor(pre.r, pre.g, pre.b, 60 / 255) } }
        opts.highlight = hl
        opts.highlightFill = fills // I1: RevitCraft lays its selection blue over areas (canvas.rs SELECT_FILL)
        return opts
    }

    /// RevitCraft's selection blue for areas, (19, 57, 159) at 55 %: over white it reads as (125, 146, 202).
    static let selectionFill = RGBColor(19 / 255, 57 / 255, 159 / 255, 140 / 255)

    /// I1: selected walls cut by a floor plan fill evenly with the selection blue between their openings, as in
    /// RevitCraft (`paint_selected_wall_fills`). The cut pieces already stop at openings and at the walls they join.
    private var selectedWallFills: [GPrimitive] {
        guard viewElement?.view?.kind == .floorPlan, let g = graphics else { return [] }
        let sel = Set(state.session.selection.ids)
        guard !sel.isEmpty else { return [] }
        var polys: [Polygon2] = []
        for item in g.items where item.layer == .cut && item.category == .walls {
            if let id = item.elementID, sel.contains(id) { polys += item.hitPolygons }
        }
        guard !polys.isEmpty else { return [] }
        let c = Self.selectionFill
        return [.fill(polys, GFill(pattern: .solid, color: RGBColor(c.r, c.g, c.b), transparency: 1 - c.a))]
    }

    /// Tool and selection-drag preview geometry (drawn in the overlay pass).
    private var previewPrimitives: [GPrimitive] {
        var previews: [GPrimitive] = selectedWallFills
        if let tool = state.activeTool { previews += tool.preview.primitives }
        if selectTool.isDragging { previews += selectTool.preview.primitives }
        return previews
    }

    /// Interactive overlays above the drawing: temporary dimensions, grips, controls, snaps, selection rectangles.
    func drawOverlays(_ ctx: CGContext) {
        if metalView != nil {
            guard graphics != nil else { drawCentered("Building view…"); return }
            viewportEditor?.drawDimming(in: ctx) // WP6a
        }
        drawAreaHighlights(ctx) // BL-CANVAS: ARCUS-025
        var guides: [Segment2] = []
        if let tool = state.activeTool { guides += tool.preview.guides }
        if selectTool.isDragging { guides += selectTool.preview.guides }
        drawGuides(guides, ctx)
        var dims: [TemporaryDimension] = []
        if let tool = state.activeTool { dims += tool.preview.tempDims }
        if selectTool.isDragging { dims += selectTool.preview.tempDims }
        for d in dims { drawTempDim(d, ctx) }
        drawSelectionDimensions(ctx)
        drawGrips(ctx)
        drawControls(ctx)
        // Doors and windows follow their host wall; a point-snap marker would only get in the way of their spacing.
        if let s = snap, !(state.activeTool is InsertTool) { drawSnap(s, ctx) }
        lastDrawnSnap = snap?.point
        if case .window(let start) = drag, let cur = dragCurrent { drawSelectionRect(from: start, to: cur, ctx) }
        if case .zoomRegion(let start) = drag, let cur = dragCurrent { drawSelectionRect(from: start, to: cur, ctx) }
        drawTemporaryVisibilityFrame(ctx)
        drawCursorTooltip(ctx)
    }

    /// Temporary hide/isolate (or Reveal Hidden) changes what the view shows without changing the model; like other
    /// BIM tools, frame the canvas so hidden elements never look like they vanished.
    private func drawTemporaryVisibilityFrame(_ ctx: CGContext) {
        guard let t = state.session.temporaryVisibility[viewID], t.isActive || t.revealHidden || t.revealConstraints || t.temporaryTemplateID != nil else { return } // BL-VG
        let color = t.revealHidden ? NSColor.systemPink : t.isActive ? NSColor.systemTeal : t.revealConstraints ? NSColor.systemRed : NSColor.systemIndigo // BL-VG
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(bounds.insetBy(dx: 1.5, dy: 1.5))
        ctx.restoreGState()
        let label = t.revealHidden ? "Reveal Hidden Elements — hidden elements shown in colour" : t.isActive ? "Temporary Hide/Isolate — type HR to reset"
            : t.revealConstraints ? "Reveal Constraints" : "Temporary View Properties — restore from the view control bar" // BL-VG
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
        let size = (label as NSString).size(withAttributes: attrs)
        let box = NSRect(x: 8, y: bounds.maxY - size.height - 14, width: size.width + 14, height: size.height + 6)
        color.setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (label as NSString).draw(at: NSPoint(x: box.minX + 7, y: box.minY + 3), withAttributes: attrs)
    }

    private func drawCentered(_ s: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        let size = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    /// Angle of a rubber band: a thin horizontal reference from the start, an arc sweeping to the line, and the angle
    /// between them on the arc.
    private func drawAngleArc(_ d: TemporaryDimension, _ ctx: CGContext) {
        let a = toScreen(d.from), b = toScreen(d.to)
        let v = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let len = hypot(v.dx, v.dy)
        guard len > 30 else { return }
        let lineAngle = atan2(v.dy, v.dx)
        // Measured from the previous segment when chaining (its forward extension), else the horizontal on the line's side.
        var refAngle: CGFloat = v.dx >= 0 ? 0 : .pi
        if let r = d.angleReference {
            let e = toScreen(d.from + r)
            refAngle = atan2(e.y - a.y, e.x - a.x)
        }
        var sweep = lineAngle - refAngle
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }
        // Straight on (or straight back) has no angle to show.
        guard abs(sweep) > 0.004, .pi - abs(sweep) > 0.004 else { return }
        let radius = min(len * 0.85, 220)
        let color = Tokens.construction
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: a); ctx.addLine(to: CGPoint(x: a.x + cos(refAngle) * radius * 1.15, y: a.y + sin(refAngle) * radius * 1.15))
        ctx.addArc(center: a, radius: radius, startAngle: refAngle, endAngle: refAngle + sweep, clockwise: sweep < 0)
        ctx.strokePath()
        ctx.restoreGState()
        let mid = refAngle + sweep / 2
        let text = String(format: "%.2f°", abs(sweep) * 180 / .pi) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        var at = CGPoint(x: a.x + cos(mid) * (radius + 14) - size.width / 2, y: a.y + sin(mid) * (radius + 14) - size.height / 2)
        // A small angle: set the value clear of the two lines.
        if abs(sweep) < 0.05 { at = CGPoint(x: a.x + cos(mid) * radius * 0.6 - size.width / 2, y: a.y + sin(mid) * radius * 0.6 + (sweep < 0 ? -size.height - 5 : 5)) }
        text.draw(at: at, withAttributes: attrs)
    }

    private func drawTempDim(_ d: TemporaryDimension, _ ctx: CGContext, highlighted: Bool = false) {
        if d.isAngleArc {
            drawAngleArc(d, ctx); return
        }
        let a = toScreen(d.from), b = toScreen(d.to)
        let color = Tokens.construction
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        if d.isAngle {
            ctx.setLineDash(phase: 0, lengths: [3, 3])
        }
        let v = Vec2(b.x - a.x, b.y - a.y)
        let len = v.length
        guard len > 1 else { ctx.restoreGState(); return }
        let n = Vec2(-v.y, v.x) / len * 14
        let pa = NSPoint(x: a.x + n.x, y: a.y + n.y), pb = NSPoint(x: b.x + n.x, y: b.y + n.y)
        if !d.isAngle {
            ctx.move(to: a); ctx.addLine(to: NSPoint(x: pa.x + n.x * 0.3, y: pa.y + n.y * 0.3))
            ctx.move(to: b); ctx.addLine(to: NSPoint(x: pb.x + n.x * 0.3, y: pb.y + n.y * 0.3))
            ctx.move(to: pa); ctx.addLine(to: pb)
            ctx.strokePath()
        }
        ctx.restoreGState()
        guard let box = tempDimLabelRect(d) else { return }
        TempDimLabelStyle.draw(d.text, in: box, active: d.isActive, highlighted: highlighted, canvas: canvasColor) // BL-CANVAS: ARCUS-080
    }

    private func tempDimAttributes(_ d: TemporaryDimension) -> [NSAttributedString.Key: Any] {
        TempDimLabelStyle.attributes(active: d.isActive) // BL-CANVAS
    }

    /// Screen rectangle of a temporary dimension's value box (also its click target).
    private func tempDimLabelRect(_ d: TemporaryDimension) -> NSRect? {
        let a = toScreen(d.from), b = toScreen(d.to)
        let v = Vec2(b.x - a.x, b.y - a.y)
        let len = v.length
        guard len > 1 else { return nil }
        let n = Vec2(-v.y, v.x) / len * 14
        let pa = NSPoint(x: a.x + n.x, y: a.y + n.y), pb = NSPoint(x: b.x + n.x, y: b.y + n.y)
        // Length labels sit on the dimension line; angle labels go on the opposite side near the start point so the two never overlap.
        let mid = d.isAngle
            ? NSPoint(x: a.x + v.x * 0.25 - n.x * 1.6, y: a.y + v.y * 0.25 - n.y * 1.6)
            : NSPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
        let size = (d.text as NSString).size(withAttributes: tempDimAttributes(d))
        var box = TempDimLabelStyle.box(size: size, mid: mid) // BL-CANVAS
        // Keep the value clear of flip arrows and other controls: slide it along the dimension line.
        let controls = currentControls.map { g -> NSRect in let s = toScreen(g.position); return NSRect(x: s.x - 11, y: s.y - 11, width: 22, height: 22) }
        if let hit = controls.first(where: { $0.intersects(box.insetBy(dx: -3, dy: -3)) }), len > 1 {
            let u = Vec2(v.x / len, v.y / len)
            let step = abs(u.x) * box.width / 2 + abs(u.y) * box.height / 2 + hit.width / 2 + 6
            let side: Double = (Vec2(mid.x - hit.midX, mid.y - hit.midY).dot(u)) >= 0 ? 1 : -1
            box = box.offsetBy(dx: u.x * step * side, dy: u.y * step * side)
        }
        return box
    }

    // MARK: Temporary dimensions on the selection

    /// Temporary dimensions of the single selected element (Modify mode, not while dragging).
    private var selectionDimensions: [SelectionDimension] {
        guard state.activeTool == nil, !selectTool.isDragging else { return [] }
        return selectTool.selectionDimensions
    }
    /// The small "make this dimension permanent" button to the right of a value box.
    private func permanentButtonRect(_ label: NSRect) -> NSRect { NSRect(x: label.maxX + 3, y: label.midY - 7, width: 14, height: 14) }

    /// Selection dimension under a screen point, and whether the point is on its make-permanent button.
    private func selectionDimension(at sp: NSPoint) -> (SelectionDimension, permanent: Bool)? {
        for d in selectionDimensions {
            guard let r = tempDimLabelRect(selectTool.temporaryDimension(d)) else { continue }
            if r.insetBy(dx: -2, dy: -2).contains(sp) { return (d, false) }
            if permanentButtonRect(r).insetBy(dx: -2, dy: -2).contains(sp) { return (d, true) }
        }
        return nil
    }

    private func drawSelectionDimensions(_ ctx: CGContext) {
        let hover = lastMouse.flatMap(selectionDimension(at:))
        for d in selectionDimensions {
            let td = selectTool.temporaryDimension(d)
            drawTempDim(td, ctx, highlighted: hover?.0 == d && hover?.permanent == false)
            guard let label = tempDimLabelRect(td) else { continue }
            // Dimension glyph: a line with end ticks, in a small rounded box.
            let r = permanentButtonRect(label)
            let hot = hover?.0 == d && hover?.permanent == true
            let box = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            box.fill()
            (hot ? Tokens.selection : NSColor.separatorColor).setStroke()
            box.lineWidth = hot ? 1.5 : 1
            box.stroke()
            let g = NSBezierPath()
            g.move(to: NSPoint(x: r.minX + 3, y: r.midY)); g.line(to: NSPoint(x: r.maxX - 3, y: r.midY))
            g.move(to: NSPoint(x: r.minX + 3, y: r.midY - 3)); g.line(to: NSPoint(x: r.minX + 3, y: r.midY + 3))
            g.move(to: NSPoint(x: r.maxX - 3, y: r.midY - 3)); g.line(to: NSPoint(x: r.maxX - 3, y: r.midY + 3))
            (hot ? Tokens.selection : NSColor.secondaryLabelColor).setStroke()
            g.lineWidth = 1
            g.stroke()
        }
    }

    /// Opens the value box of a selection dimension for typing; Return moves the element.
    private func beginDimensionEdit(_ d: SelectionDimension) {
        let td = selectTool.temporaryDimension(d)
        guard let r = tempDimLabelRect(td) else { return }
        beginNumericEntry(td.text, target: .dimension(d), label: d.role == .length ? "Length" : "Distance",
                          frame: NSRect(x: r.midX - 60, y: r.midY - 11, width: 120, height: 22), selectAll: true)
    }

    private var currentGrips: [Grip] {
        guard state.activeTool == nil, let id = state.session.selection.single, let e = state.model[id] else { return [] }
        return GripService.grips(for: e, state.model, viewKind: viewElement?.view?.kind, levelLine: levelLine(id))
    }

    /// Click targets on the single selected element (flip arrows, bubble boxes, EQ and padlock).
    private var currentControls: [Grip] {
        guard state.activeTool == nil, !selectTool.isDragging, let id = state.session.selection.single, let e = state.model[id] else { return [] }
        return GripService.controls(for: e, state.model, view: viewElement, pixel: 1 / max(zoom, 1e-9), levelLine: levelLine(id))
    }

    /// Drawn ends of a level line in an elevation or section (its first primitive), for levels without explicit extents.
    private func levelLine(_ id: ElementID) -> (Double, Double)? {
        guard viewElement?.view?.kind.isVerticalCut == true, state.model[id]?.level != nil, let g = graphics else { return nil }
        for item in g.items where item.elementID == id {
            if case .polyline(let pts, _, _)? = item.primitives.first, pts.count == 2 { return (pts[0].x, pts[1].x) }
        }
        return nil
    }

    private func control(at sp: NSPoint) -> Grip? {
        currentControls.first { g in let s = toScreen(g.position); return hypot(s.x - sp.x, s.y - sp.y) <= 9 }
    }

    private func drawControls(_ ctx: CGContext) {
        let hover = lastMouse.flatMap(control(at:))
        for g in currentControls {
            let p = toScreen(g.position)
            let color = (hover == g ? Tokens.preselection : Tokens.selection).cgColor // I1: RevitCraft's PRESELECT when hot
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            switch g.kind {
            case .flipWall, .flipFacing, .flipHand:
                // Double-headed arrow along the flip axis, on a light halo so it reads over hatching.
                let d = g.direction.normalized
                let u = CGVector(dx: d.x, dy: d.y), w = CGVector(dx: -d.y, dy: d.x)
                let a = CGPoint(x: p.x - u.dx * 9, y: p.y - u.dy * 9), b = CGPoint(x: p.x + u.dx * 9, y: p.y + u.dy * 9)
                func arrow() {
                    ctx.move(to: a); ctx.addLine(to: b)
                    for (tip, s) in [(a, 1.0), (b, -1.0)] {
                        ctx.move(to: CGPoint(x: tip.x + (u.dx * 4 + w.dx * 3.5) * s, y: tip.y + (u.dy * 4 + w.dy * 3.5) * s))
                        ctx.addLine(to: tip)
                        ctx.addLine(to: CGPoint(x: tip.x + (u.dx * 4 - w.dx * 3.5) * s, y: tip.y + (u.dy * 4 - w.dy * 3.5) * s))
                    }
                }
                ctx.setStrokeColor(NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(4.5); arrow(); ctx.strokePath()
                ctx.setStrokeColor(color)
                ctx.setLineWidth(1.6); arrow(); ctx.strokePath()
            case .bubble:
                // Check box: ticked when the bubble is shown at that end.
                let r = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
                ctx.setStrokeColor(color); ctx.setLineWidth(1); ctx.stroke(r)
                if g.isOn {
                    ctx.move(to: CGPoint(x: r.minX + 2, y: r.midY)); ctx.addLine(to: CGPoint(x: r.minX + 4.2, y: r.minY + 2.2))
                    ctx.addLine(to: CGPoint(x: r.maxX - 2, y: r.maxY - 2)); ctx.setLineWidth(1.5); ctx.strokePath()
                }
            case .dimensionEquality:
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor(cgColor: color) ?? Tokens.selection]
                let size = ("EQ" as NSString).size(withAttributes: attrs)
                let r = CGRect(x: p.x - size.width / 2 - 3, y: p.y - size.height / 2 - 1, width: size.width + 6, height: size.height + 2)
                ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor); ctx.fill(r)
                ctx.setStrokeColor(color); ctx.setLineWidth(1); ctx.stroke(r)
                NSGraphicsContext.saveGraphicsState()
                ("EQ" as NSString).draw(at: NSPoint(x: r.minX + 3, y: r.minY + 1), withAttributes: attrs)
                NSGraphicsContext.restoreGraphicsState()
                // Struck through while the segments are not held equal.
                if !g.isOn { ctx.move(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); ctx.strokePath() }
            case .dimensionLock:
                // Padlock: closed shackle when locked, raised to one side when unlocked.
                let body = CGRect(x: p.x - 4.5, y: p.y - 5, width: 9, height: 6.5)
                ctx.setFillColor(NSColor.windowBackgroundColor.cgColor); ctx.fill(body.insetBy(dx: -1.5, dy: -1.5))
                ctx.setStrokeColor(color); ctx.setLineWidth(1.2); ctx.stroke(body)
                let cx = g.isOn ? p.x : p.x + 3, lift: CGFloat = g.isOn ? 0 : 2
                ctx.move(to: CGPoint(x: cx - 3, y: body.maxY + lift))
                ctx.addArc(center: CGPoint(x: cx, y: body.maxY + 2 + lift), radius: 3, startAngle: .pi, endAngle: 0, clockwise: true)
                if g.isOn { ctx.addLine(to: CGPoint(x: cx + 3, y: body.maxY)) }
                ctx.strokePath()
                if g.isOn { ctx.setFillColor(color); ctx.fill(body.insetBy(dx: 1.5, dy: 1.5)) }
            default: break
            }
            ctx.restoreGState()
        }
    }

    private func drawGrips(_ ctx: CGContext) {
        // I1: RevitCraft's grips (grips.rs `paint`): solid blue dots (64, 112, 210) with a dark blue rim (20, 60, 160),
        // lighter (110, 165, 250) under the pointer; smaller on witness lines.
        let hot = lastMouse.flatMap(grip(at:))
        for g in currentGrips {
            let p = toScreen(g.position)
            let radius: CGFloat
            if case .witness = g.kind { radius = 3 } else { radius = 4 }
            let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            let fill = hot == g ? NSColor(srgbRed: 110 / 255, green: 165 / 255, blue: 250 / 255, alpha: 1) : NSColor(srgbRed: 64 / 255, green: 112 / 255, blue: 210 / 255, alpha: 1)
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(NSColor(srgbRed: 20 / 255, green: 60 / 255, blue: 160 / 255, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: r)
        }
    }

    /// I2: RevitCraft's tracking lines (canvas.rs `track_line`): thin light-blue (120, 170, 230) dash-dot lines.
    /// `acrossView` runs horizontal and vertical ones across the whole canvas, as RevitCraft does for axis tracking.
    private func drawGuides(_ guides: [Segment2], _ ctx: CGContext, acrossView: Bool = false) {
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

    /// The snap colour RevitCraft draws its markers in (style.rs SNAP).
    static let snapColor = NSColor(srgbRed: 230 / 255, green: 0, blue: 210 / 255, alpha: 1)

    /// The label RevitCraft shows beside a snap: the kind ("Endpoint"), "Horizontal" / "Vertical" for axis tracking,
    /// "Horizontal and Extension" where the drawing direction crosses an alignment. Other angles show no label.
    static func snapTooltip(_ s: SnapResult) -> String? {
        let text = s.shortLabel ?? s.kind.rawValue
        if s.kind == .angle && text.hasPrefix("Angle") { return nil }
        return text.isEmpty ? nil : text
    }

    private func drawSnap(_ s: SnapResult, _ ctx: CGContext) {
        let p = toScreen(s.point)
        let axis = s.kind == .angle && (s.label == "HORIZONTAL" || s.label == "VERTICAL")
        // Tracking guides (extensions, horizontal/vertical through the start point).
        drawGuides(s.guides, ctx, acrossView: axis)
        ctx.saveGState()
        ctx.setStrokeColor(Self.snapColor.cgColor)
        ctx.setLineWidth(1.6)
        // I2: RevitCraft's markers (canvas.rs `paint_snap`), mirrored for this view's upward y axis.
        let r: CGFloat = 5
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: p.x + x, y: p.y - y) }
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
                let h = s.label == "HORIZONTAL"
                let d = h ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1), n = CGVector(dx: -d.dy, dy: d.dx)
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
        // I2: the label shows at once beside the snap, as in RevitCraft (Tooltip Assistance None hides it).
        if let text = Self.snapTooltip(s), CanvasSettings.tooltipAssistance != .none { drawSnapLabel(text, at: pt(8, 12), ctx) }
    }

    /// RevitCraft's snap label (style.rs `canvas_tooltip`): small grey text in a flat light box with a grey border,
    /// its top-left corner at `topLeft`, kept inside the canvas.
    private func drawSnapLabel(_ text: String, at topLeft: CGPoint, _ ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor(white: 60 / 255, alpha: 1)]
        let size = (text as NSString).size(withAttributes: attrs)
        var box = CGRect(x: topLeft.x + 3, y: topLeft.y - size.height - 3, width: ceil(size.width) + 6, height: ceil(size.height) + 2)
        box.origin.x = min(max(box.minX, bounds.minX + 2), bounds.maxX - 2 - box.width)
        box.origin.y = min(max(box.minY, bounds.minY + 2), bounds.maxY - 2 - box.height)
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 245 / 255, alpha: 1).cgColor)
        ctx.fill(box)
        ctx.setStrokeColor(NSColor(white: 170 / 255, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        (text as NSString).draw(at: CGPoint(x: box.minX + 3, y: box.minY + 1), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Cursor tooltip

    /// What the tooltip beside the cursor says: the snap in short form, else the tool's prompt; while dragging, the drag hint.
    private var cursorTooltipText: String? {
        if selectTool.isDragging { return assistedTooltip("Drag to new position", isPrompt: false) } // BL-CANVAS: Tooltip Assistance
        guard let tool = state.activeTool else { return elementTooltipText } // BL-CANVAS: ARCUS-026
        if snap != nil, !(tool is InsertTool) { return nil } // I2: the snap label is drawn at once beside the snap
        return assistedTooltip(tool.prompt, isPrompt: true)
    }

    /// Restarts the rest timer: the tooltip shows once the pointer has been still for a moment, as in other BIM tools.
    private func pointerMovedForTooltip() {
        cursorTooltipVisible = false
        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: CanvasSettings.tooltipDelay(element: state.activeTool == nil && !selectTool.isDragging), repeats: false) { [weak self] _ in // BL-CANVAS
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cursorTooltipVisible = true
                self.needsDisplay = true
            }
        }
    }

    private func drawCursorTooltip(_ ctx: CGContext) {
        guard cursorTooltipVisible, let text = cursorTooltipText, !text.isEmpty, let m = lastMouse, bounds.contains(m) else { return }
        drawCompactTooltip(text, at: m, ctx) // BL-CANVAS: ARCUS-081
    }

    private func drawSelectionRect(from a: NSPoint, to b: NSPoint, _ ctx: CGContext) {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        let crossing = b.x < a.x
        ctx.saveGState()
        // I1: a plain thin rectangle as in RevitCraft: solid for window, dashed for crossing selection, no fill.
        ctx.setStrokeColor(isDark && !isPaper ? NSColor(white: 0.85, alpha: 1).cgColor : NSColor(white: 40 / 255, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        if crossing { ctx.setLineDash(phase: 0, lengths: [5, 3]) }
        ctx.stroke(r)
        ctx.restoreGState()
    }

    // MARK: Hit testing

    /// Candidate elements under a screen point, best first.
    func hitCandidates(at sp: NSPoint) -> [ElementID] {
        guard let g = graphics else { return [] }
        let p = toView(sp)
        let tol = 5 / zoom
        let box = Rect2(center: p, halfSize: Vec2(tol, tol))
        var hits: [(ElementID, Int, Double)] = []
        for i in itemGrid.query(box) {
            let item = g.items[i]
            guard let id = item.elementID, item.selectable else { continue }
            if let d = hitDistance(item, p, tol) {
                if let e = state.model[id], !state.session.selection.allows(e) { continue }
                hits.append((id, item.layer.rawValue, d))
            }
        }
        // Prefer annotations and lines (layer high), then nearest, then smallest bounds.
        let sorted = hits.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
        var seen = Set<ElementID>()
        return sorted.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
    }

    private func hitDistance(_ item: GItem, _ p: Vec2, _ tol: Double) -> Double? {
        var best: Double?
        func take(_ d: Double) { if d <= tol { best = min(best ?? d, d) } }
        for prim in item.primitives {
            switch prim {
            case .polyline(let pts, let closed, _):
                let n = closed ? pts.count : pts.count - 1
                guard n > 0 else { continue }
                for i in 0..<n { take(Segment2(pts[i], pts[(i + 1) % pts.count]).distance(to: p)) }
            case .arc(let a, _):
                take(a.closestPoint(to: p).distance(to: p))
            case .fill(let polys, _):
                if polys.contains(where: { $0.contains(p) }) { take(tol * 0.9) }
            case .text(let t):
                let h = t.height * scaleDenominator
                let w = h * 0.6 * Double(max(1, t.string.split(separator: "\n").map(\.count).max() ?? 1))
                if Rect2(center: t.position, halfSize: Vec2(w, h * 1.2)).contains(p) { take(tol * 0.8) }
            }
        }
        for poly in item.hitPolygons where poly.contains(p) { take(tol * 0.95) }
        return best
    }

    private func grip(at sp: NSPoint) -> Grip? {
        currentGrips.first { g in let s = toScreen(g.position); return abs(s.x - sp.x) <= 6 && abs(s.y - sp.y) <= 6 }
    }

    private func input(for event: NSEvent, snapFrom: Vec2? = nil, orthoOnly: Bool = false) -> ToolInput {
        let sp = convert(event.locationInWindow, from: nil)
        let raw = toView(sp)
        let ctx = toolContext
        var (pt, s) = ctx.snap(raw, from: snapFrom ?? state.activeTool?.snapFrom, orthoOnly: orthoOnly, constrainOrtho: state.activeTool != nil && event.modifierFlags.contains(.shift))
        if let t = tabSnap {
            // A snap picked with Tab holds until the pointer moves away from where Tab was pressed.
            if hypot(sp.x - t.at.x, sp.y - t.at.y) <= 3 { s = t.candidates[t.index]; pt = t.candidates[t.index].point } else { tabSnap = nil }
        }
        var i = ToolInput(point: pt, rawPoint: raw, snap: s)
        i.shift = event.modifierFlags.contains(.shift)
        i.command = event.modifierFlags.contains(.command)
        i.option = event.modifierFlags.contains(.option)
        i.clickCount = event.clickCount
        let hits = hitCandidates(at: sp)
        i.hit = hits.first
        i.hitCandidates = hits
        return i
    }

    // MARK: Mouse

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMovedForTooltip()
        if viewportEditor != nil { return } // WP6a: the activated view's canvas handles the pointer
        let sp = convert(event.locationInWindow, from: nil)
        lastMouse = sp
        let i = input(for: event)
        state.cursorPoint = i.rawPoint
        if let tool = state.activeTool {
            snap = i.snap
            tool.pointerMoved(i)
            state.snapDescription = i.snap?.description
        } else {
            snap = nil
            state.session.selection.setCycleCandidates(i.hitCandidates, model: state.model)
            state.hoverDescription = i.hit.flatMap { state.model[$0] }.map { describe($0) } ?? ""
        }
        updateCursor()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        state.session.selection.preselection = nil
        tooltipTimer?.invalidate(); cursorTooltipVisible = false
        snap = nil
        needsDisplay = true
    }

    func describe(_ e: Element) -> String {
        let m = state.model
        if let t = m.type(of: e), let td = t.typeData { return "\(e.category.displayName) : \(td.familyName) : \(t.name)" }
        if e.room != nil { return "Rooms : \(e.room?.number ?? "") \(e.name)" }
        return e.category.displayName + (e.name.isEmpty ? "" : " : \(e.name)")
    }

    /// Mouse-down count (QA diagnostics).
    var mouseDownCount = 0
    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
        // W2-ANNOT: a click on the canvas finishes text being typed in place (and does nothing else).
        if let editor = inPlaceText { editor.finish(commit: true); return }
        window?.makeFirstResponder(self)
        state.paletteCanvasClicked() // BL-PROPS: the palette returns to the active view
        let sp = convert(event.locationInWindow, from: nil)
        mouseDownLocation = sp
        dragCurrent = sp
        if zoomRegionArmed { drag = .zoomRegion(sp); return }
        if let editor = viewportEditor { editor.sheetMouseDown(event); return } // WP6a
        if state.activeTool == nil {
            // Controls and temporary dimensions on the selection come first, so quick repeated clicks on a flip arrow
            // each flip instead of turning into a double-click.
            if let c = control(at: sp) {
                selectTool.click(c)
                drag = .none
                needsDisplay = true
                return
            }
            if let (d, permanent) = selectionDimension(at: sp) {
                if permanent { selectTool.makePermanent(d) } else { beginDimensionEdit(d) }
                drag = .none
                needsDisplay = true
                return
            }
        }
        if event.clickCount == 2, state.activeTool == nil { doubleClick(at: sp, event: event); return }
        if let tool = state.activeTool {
            let i = input(for: event)
            tool.pointerDown(i)
            toolContext.snapOverride = nil
            tabSnap = nil
            drag = .tool
            state.toolChangedState()
            needsDisplay = true
            return
        }
        // Modify mode.
        if let g = grip(at: sp) {
            _ = selectTool.beginDrag(at: g.position, grip: g)
            drag = .selectDrag
            return
        }
        let hits = hitCandidates(at: sp)
        let sel = state.session.selection
        let pre = sel.preselection
        let target = (pre != nil && hits.contains(pre!)) ? pre : hits.first
        let shift = event.modifierFlags.contains(.shift), cmd = event.modifierFlags.contains(.command)
        if let t = target {
            if sel.isChainPreselected && sel.cycleChain.contains(t) {
                // Tab reached the chain of joined walls: the click picks them all.
                let op = SelectionModel.operation(shift: shift, command: cmd)
                sel.apply(op == .toggle ? .add : op, sel.cycleChain)
            } else if !sel.contains(t) || shift || cmd {
                sel.click(t, shift: shift, command: cmd)
            }
            if state.session.selection.contains(t) && !cmd {
                let (pt, _) = toolContext.snap(toView(sp))
                _ = selectTool.beginDrag(at: pt, grip: nil)
                drag = .selectDrag
            } else { drag = .none }
        } else {
            if !shift && !cmd { state.session.selection.clear() }
            drag = .window(sp)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        pointerMovedForTooltip()
        let sp = convert(event.locationInWindow, from: nil)
        dragCurrent = sp
        switch drag {
        case .tool:
            if let tool = state.activeTool {
                let i = input(for: event)
                tool.pointerDragged(i)
                tool.pointerMoved(i)
                snap = i.snap
            }
        case .selectDrag:
            guard let down = mouseDownLocation, hypot(sp.x - down.x, sp.y - down.y) > 3 else { return }
            lastMouse = sp
            let i = input(for: event, snapFrom: selectTool.dragAnchor, orthoOnly: true)
            snap = i.snap
            selectTool.dragged(to: i.point, snapped: i.snap != nil)
        case .pan(let last):
            center = center - Vec2(sp.x - last.x, sp.y - last.y) / zoom
            drag = .pan(sp)
        default: break
        }
        updateCursor() // I1: crosshair while an end is dragged, four-way arrow while elements are
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        defer { drag = .none; dragCurrent = nil; needsDisplay = true; updateCursor() }
        switch drag {
        case .tool:
            state.activeTool?.pointerUp(input(for: event))
        case .selectDrag:
            if numericField != nil, case .drag = numericTarget, selectTool.isDragging {
                // A value is being typed: keep the drag preview until Return or Esc.
                dragAwaitingValue = true
                return
            }
            let i = input(for: event, snapFrom: selectTool.dragAnchor, orthoOnly: true)
            selectTool.endDrag(i)
            snap = nil
        case .window(let start):
            guard hypot(sp.x - start.x, sp.y - start.y) > 3 else { return }
            windowSelect(from: start, to: sp, op: SelectionModel.operation(shift: event.modifierFlags.contains(.shift), command: event.modifierFlags.contains(.command)))
        case .zoomRegion(let start):
            zoomRegionArmed = false
            let a = toView(start), b = toView(sp)
            if a.distance(to: b) * zoom > 5 { recordNavigation(); zoom(to: Rect2(points: [a, b])) }
        default: break
        }
    }

    private func windowSelect(from a: NSPoint, to b: NSPoint, op: SelectionModel.Operation) {
        guard let g = graphics else { return }
        let r = Rect2(points: [toView(a), toView(b)])
        let crossing = b.x < a.x
        var ids: [ElementID] = []
        var seen = Set<ElementID>()
        for i in itemGrid.query(r) {
            let item = g.items[i]
            guard let id = item.elementID, item.selectable, !seen.contains(id) else { continue }
            if let e = state.model[id], !state.session.selection.allows(e) { continue }
            let inside = crossing ? r.intersects(item.bounds) : r.contains(item.bounds)
            if inside { ids.append(id); seen.insert(id) }
        }
        // A toggle window (Mac style ⌘-drag) adds; toggling each element in a window is never what people mean.
        state.session.selection.apply(op == .toggle ? .add : op, ids)
    }

    private func doubleClick(at sp: NSPoint, event: NSEvent) {
        guard let g = graphics else { return }
        let p = toView(sp)
        // View markers and viewports open their target view.
        for i in itemGrid.query(Rect2(center: p, halfSize: Vec2(5 / zoom, 5 / zoom))) {
            let item = g.items[i]
            if let target = item.targetViewID, hitDistance(item, p, 5 / zoom) != nil {
                if item.category == .viewports, let handled = viewportDoubleClickPreference(target) { if handled { return } } // BL-CANVAS: ARCUS-085
                if activateViewportIfHit(item) { return } // WP6a
                state.open(target)
                return
            }
        }
        guard let id = hitCandidates(at: sp).first, let e = state.model[id] else { return }
        CommandRouter(state: state).doubleClick(e)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let editor = viewportEditor { NSMenu.popUpContextMenu(editor.sheetContextMenu(), with: event, for: self); return } // WP6a
        let sp = convert(event.locationInWindow, from: nil)
        let hits = hitCandidates(at: sp)
        if state.activeTool == nil, let h = hits.first, !state.session.selection.contains(h) { state.session.selection.select([h]) } // BL-KEYS: drawing menu keeps the selection
        let menu = ContextMenuBuilder(state: state, viewID: viewID, canvas: self).menu(for: hits.first)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseDown(with event: NSEvent) {
        if let h = sheetHost { h.otherMouseDown(with: event); return } // WP6a: pan the sheet
        recordNavigation()
        if event.buttonNumber == 2 && event.clickCount == 2 {
            // Double-clicking the wheel zooms to fit, as in other CAD and BIM tools.
            drag = .none
            zoomToFit()
            return
        }
        drag = .pan(convert(event.locationInWindow, from: nil))
    }
    override func otherMouseDragged(with event: NSEvent) {
        if let h = sheetHost { h.otherMouseDragged(with: event); return } // WP6a
        let sp = convert(event.locationInWindow, from: nil)
        if case .pan(let last) = drag {
            center = center - Vec2(sp.x - last.x, sp.y - last.y) / zoom
            drag = .pan(sp)
            needsDisplay = true
        }
    }
    override func otherMouseUp(with event: NSEvent) { if let h = sheetHost { h.otherMouseUp(with: event); return }; drag = .none }

    override func scrollWheel(with event: NSEvent) {
        if let h = sheetHost { h.scrollWheel(with: event); return } // WP6a: zoom and pan the sheet
        noteNavigationStart()
        let sp = convert(event.locationInWindow, from: nil)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) {
            center = center - Vec2(-event.scrollingDeltaX, event.scrollingDeltaY) / zoom
            userAdjusted = true
            needsDisplay = true
        } else {
            // BL-SITE (ARCUS-030): the 3D views' ratio per wheel notch; a wheel rolled forward zooms in whatever the scroll direction setting.
            let dy = Double(event.scrollingDeltaY) * (!event.hasPreciseScrollingDeltas && event.isDirectionInvertedFromDevice ? -1 : 1)
            zoom(by: NavigationZoom.factor(dy: dy, precise: event.hasPreciseScrollingDeltas), at: sp)
        }
        if let lm = lastMouse, state.activeTool != nil {
            _ = lm
        }
    }

    override func magnify(with event: NSEvent) {
        if let h = sheetHost { h.magnify(with: event); return } // WP6a
        noteNavigationStart()
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }
    override func smartMagnify(with event: NSEvent) { if let h = sheetHost { h.smartMagnify(with: event); return }; recordNavigation(); zoomToFit() }

    // MARK: Pan/zoom history (Previous / Next Pan/Zoom)

    private var navBack: [(center: Vec2, zoom: Double)] = []
    private var navForward: [(center: Vec2, zoom: Double)] = []
    private var lastNavigationRecord = 0.0

    /// Remembers the current pan and zoom before a discrete navigation step.
    func recordNavigation() {
        if let last = navBack.last, last.center == center, last.zoom == zoom { return }
        navBack.append((center, zoom))
        if navBack.count > 50 { navBack.removeFirst() }
        navForward.removeAll()
        lastNavigationRecord = ProcessInfo.processInfo.systemUptime
    }
    /// Continuous gestures record once per burst, not once per event.
    private func noteNavigationStart() {
        if ProcessInfo.processInfo.systemUptime - lastNavigationRecord > 0.6 { recordNavigation() }
        lastNavigationRecord = ProcessInfo.processInfo.systemUptime
    }
    var canStepNavigationBack: Bool { !navBack.isEmpty }
    var canStepNavigationForward: Bool { !navForward.isEmpty }
    @discardableResult func stepNavigation(back: Bool) -> Bool {
        guard let s = back ? navBack.popLast() : navForward.popLast() else { return false }
        if back { navForward.append((center, zoom)) } else { navBack.append((center, zoom)) }
        center = s.center; zoom = s.zoom
        userAdjusted = true
        lastNavigationRecord = 0
        needsDisplay = true
        return true
    }

    /// Zooms so one millimetre on paper is one millimetre on this display.
    func zoomSheetSize() {
        recordNavigation()
        var pointsPerMM = 72.0 / 25.4
        if let screen = window?.screen, let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let mm = CGDisplayScreenSize(CGDirectDisplayID(n.uint32Value))
            if mm.width > 0 { pointsPerMM = screen.frame.width / mm.width }
        }
        // Model views are in metres at the view scale; sheets are in metres of paper.
        zoom = pointsPerMM * 1000 / (isSheet ? 1 : scaleDenominator)
        userAdjusted = true
        needsDisplay = true
    }

    // MARK: Cursor

    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    private func updateCursor() {
        // I1: RevitCraft's cursors. Drawing, placing and dragging an end: the small grey crosshair. Move and Copy: the
        // arrow with a move glyph. The other Modify tools: the arrow. Over a selected element: the four-way move arrow.
        if let tool = state.activeTool {
            let c = tool.preview.cursor
            switch c {
            case .crosshair, .crosshairPlus, .rotate, .move:
                if [.move, .copy].contains(tool.commandID) { CanvasCursors.arrowWithMove.set() }
                else if Self.arrowCursorTools.contains(tool.commandID) { NSCursor.arrow.set() }
                else { CanvasCursors.crosshair.set() }
            case .arrow: NSCursor.arrow.set()
            case .notAllowed: NSCursor.operationNotAllowed.set()
            case .pick: NSCursor.pointingHand.set()
            case .copy: NSCursor.dragCopy.set()
            }
            return
        }
        if selectTool.isDraggingGrip { CanvasCursors.crosshair.set(); return }
        if selectTool.isDragging { CanvasCursors.fourWayMove.set(); return }
        guard let m = lastMouse else { NSCursor.arrow.set(); return }
        if control(at: m) != nil || selectionDimension(at: m) != nil { NSCursor.pointingHand.set(); return }
        if grip(at: m) != nil { NSCursor.arrow.set(); return }
        let sel = state.session.selection
        if !sel.isEmpty, let hit = hitCandidates(at: m).first, sel.ids.contains(hit), state.model[hit]?.pinned != true {
            CanvasCursors.fourWayMove.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if keysHandle(event) { return } // BL-KEYS: text-focus rule, Return in Modify, Space flips (Canvas2DView+Keys.swift)
        let chars = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        switch event.keyCode {
        case 53: // Escape
            numericField?.removeFromSuperview(); numericField = nil
            if selectTool.isDragging { _ = selectTool.escape(); dragAwaitingValue = false; snap = nil; needsDisplay = true; return }
            state.escape(); needsDisplay = true; return
        case 36, 76: // Return / Enter
            if let t = state.activeTool { if t.finish() { state.toolChangedState() } }
            needsDisplay = true; return
        case 48: // Tab
            if state.activeTool != nil, cycleSnap() { needsDisplay = true; return }
            let sel = state.session.selection
            sel.cycle()
            if sel.isChainPreselected {
                state.hoverDescription = "Chain of \(sel.cycleChain.count) joined walls. Click to select them."
            } else if let p = sel.preselection, let e = state.model[p] {
                state.hoverDescription = describe(e)
            }
            needsDisplay = true; return
        case 51, 117: // Delete
            if state.activeTool == nil { state.deleteSelection() } // BL-KEYS: reports pinned elements
            return
        case 49: // Space
            state.activeTool?.spaceBar(); state.toolChangedState(); needsDisplay = true; return
        case 123, 124, 125, 126: // arrows: nudge
            if event.keyCode == 123, flags == [.option, .command] || flags == .control {
                // ⌥⌘← Select Previous (⌃←, the usual BIM binding, only arrives when macOS isn’t using it to switch Spaces).
                CommandRouter(state: state).run(.selectPrevious); needsDisplay = true; return
            }
            if state.activeTool == nil, !state.session.selection.isEmpty {
                let step = (event.modifierFlags.contains(.shift) ? 20 : 4) / zoom
                let v: Vec2 = event.keyCode == 123 ? Vec2(-step, 0) : event.keyCode == 124 ? Vec2(step, 0) : event.keyCode == 125 ? Vec2(0, -step) : Vec2(0, step)
                let ids = state.session.selection.ids
                let view = viewID
                state.session.perform("Nudge") { tx in try ElementOperations.transform(ids, by: .translation(v), in: tx, viewID: view) }
                return
            }
        default: break
        }
        guard flags.isEmpty else { super.keyDown(with: event); return }
        if state.activeTool == nil, chars == "]" || chars == "[" {
            stepSelection(chars == "]" ? 1 : -1)
            return
        }
        if let first = chars.first, first.isNumber || first == "-" || first == "." || first == "=" || first == "(" {
            if let label = state.activeTool?.numericLabel {
                beginNumericEntry(String(first), target: .tool, label: label)
                return
            }
            if state.activeTool == nil, let label = selectTool.numericLabel {
                // Typing while dragging the selection or a grip: the value sets the distance or length exactly.
                beginNumericEntry(String(first), target: .drag, label: label)
                return
            }
        }
        if let first = chars.first, first.isLetter || first.isNumber {
            state.feedAlias(first) // BL-KEYS: shared alias buffer (KeyboardSession.swift)
            return
        }
        super.keyDown(with: event)
    }

    private func beginNumericEntry(_ initial: String, target: NumericTarget, label: String?, frame: NSRect? = nil, selectAll: Bool = false) {
        numericField?.removeFromSuperview()
        numericTarget = target
        dragAwaitingValue = false
        let f = NSTextField(string: initial)
        f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        f.placeholderString = label
        f.delegate = self
        f.target = self
        f.action = #selector(numericCommitted(_:))
        f.bezelStyle = .roundedBezel
        f.setAccessibilityLabel(label ?? "Value")
        let p = lastMouse ?? NSPoint(x: bounds.midX, y: bounds.midY)
        f.frame = frame.map { NSRect(x: min(max($0.minX, 4), bounds.maxX - $0.width - 4), y: min(max($0.minY, 4), bounds.maxY - $0.height - 4), width: $0.width, height: $0.height) }
            ?? NSRect(x: min(p.x + 16, bounds.maxX - 130), y: max(p.y - 30, 4), width: 120, height: 22)
        addSubview(f)
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectedRange = selectAll ? NSRange(location: 0, length: (initial as NSString).length) : NSRange(location: initial.count, length: 0)
        numericField = f
    }

    @objc private func numericCommitted(_ sender: NSTextField) {
        let text = sender.stringValue
        sender.removeFromSuperview()
        numericField = nil
        window?.makeFirstResponder(self)
        switch numericTarget {
        case .tool:
            if let t = state.activeTool, !t.numericInput(text) {
                state.show("“\(text)” is not a valid \(t.numericLabel?.lowercased() ?? "value").", error: true)
            }
        case .drag:
            let label = selectTool.numericLabel?.lowercased() ?? "value"
            if !selectTool.numericInput(text) {
                state.show("“\(text)” is not a valid \(label).", error: true)
                // Released already: nothing else will finish the drag, so drop it.
                if dragAwaitingValue { _ = selectTool.escape() }
            } else if !dragAwaitingValue {
                // Committed with the button still down: ignore the rest of this drag.
                drag = .none
            }
            dragAwaitingValue = false
            snap = nil
        case .dimension(let d):
            if !selectTool.setDimension(d, to: text) {
                state.show("“\(text)” is not a valid \(d.role == .length ? "length" : "distance").", error: true)
            }
        }
        numericTarget = .tool
        state.toolChangedState()
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            numericField?.removeFromSuperview(); numericField = nil
            if case .drag = numericTarget, dragAwaitingValue { _ = selectTool.escape(); snap = nil }
            dragAwaitingValue = false
            numericTarget = .tool
            window?.makeFirstResponder(self)
            needsDisplay = true
            return true
        }
        return false
    }

    /// Tab while a tool runs: steps through the object snaps under the pointer. Returns false when there is at most
    /// one snap here (Tab then falls back to cycling elements).
    private func cycleSnap() -> Bool {
        guard let tool = state.activeTool, let sp = lastMouse else { return false }
        if var t = tabSnap, hypot(sp.x - t.at.x, sp.y - t.at.y) <= 3 {
            t.index = (t.index + 1) % t.candidates.count
            tabSnap = t
        } else {
            let ctx = toolContext
            let found = ctx.snapCandidates(toView(sp), from: tool.snapFrom)
            guard found.count > 1 else { return false }
            tabSnap = (found, 1, sp)
        }
        guard let t = tabSnap else { return false }
        let s = t.candidates[t.index]
        snap = s
        var i = ToolInput(point: s.point, rawPoint: toView(sp), snap: s)
        let hits = hitCandidates(at: sp)
        i.hit = hits.first
        i.hitCandidates = hits
        tool.pointerMoved(i)
        state.snapDescription = s.description
        state.hoverDescription = "\(s.kind.rawValue) (\(t.index + 1) of \(t.candidates.count)). Tab for the next snap."
        state.toolChangedState()
        return true
    }

    // MARK: Accessibility

    func updateAccessibility() {
        let name = viewElement?.name ?? "View"
        let kind = isSheet ? "Sheet" : (viewElement?.view?.kind.rawValue ?? "View")
        setAccessibilityLabel("\(kind): \(name)")
        let sel = state.session.selection
        var value = sel.isEmpty ? "Nothing selected" : sel.statusDescription(state.model)
        if let t = state.activeTool { value += ". Tool: \(t.title). \(t.prompt)" }
        setAccessibilityValue(value)
        setAccessibilityHelp("Press ] and [ to step through the elements shown in this view, Tab to cycle overlapping elements, arrow keys to nudge the selection, and Delete to remove it. Type two-letter shortcuts such as WA for Wall.")
        // Expose selected elements (bounded) as children for VoiceOver.
        var children: [NSAccessibilityElement] = []
        for id in sel.ids.prefix(50) {
            guard let e = state.model[id] else { continue }
            let el = NSAccessibilityElement()
            el.setAccessibilityRole(.staticText)
            el.setAccessibilityLabel(describe(e))
            el.setAccessibilityParent(self)
            let b = ElementMeshes.bounds(e, state.model).xy
            if !b.isEmpty, viewElement?.view?.kind.isPlan == true, let w = window {
                let a = toScreen(b.min), c = toScreen(b.max)
                let local = NSRect(x: min(a.x, c.x), y: min(a.y, c.y), width: abs(c.x - a.x), height: abs(c.y - a.y))
                el.setAccessibilityFrame(w.convertToScreen(convert(local, to: nil)))
            }
            children.append(el)
        }
        setAccessibilityChildren(children)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [
            NSAccessibilityCustomAction(name: "Select next element") { [weak self] in self?.stepSelection(1); return true },
            NSAccessibilityCustomAction(name: "Select previous element") { [weak self] in self?.stepSelection(-1); return true },
            NSAccessibilityCustomAction(name: "Zoom to fit") { [weak self] in self?.zoomToFit(); return true },
        ]
        // On-canvas controls (flip arrows, bubble boxes, EQ, padlock) are reachable without pointing at them.
        for g in currentControls {
            guard let name = GripService.actionName(g.kind) else { continue }
            actions.append(NSAccessibilityCustomAction(name: name) { [weak self] in self?.selectTool.click(g); return true })
        }
        if !state.session.selection.isEmpty {
            actions.append(NSAccessibilityCustomAction(name: "Zoom to selection") { [weak self] in self?.zoomToSelection(); return true })
            actions.append(NSAccessibilityCustomAction(name: "Delete selection") { [weak self] in
                guard let self else { return false }
                state.session.delete(state.session.selection.ids); return true
            })
        }
        return actions
    }

    /// Selectable elements shown in this view in reading order (top to bottom, then left to right).
    private var readingOrder: [ElementID] {
        guard let g = graphics else { return [] }
        var best: [ElementID: Rect2] = [:]
        for item in g.items where item.selectable && !item.bounds.isEmpty {
            guard let id = item.elementID else { continue }
            best[id] = best[id].map { $0.union(item.bounds) } ?? item.bounds
        }
        return best.sorted { a, b in
            let ya = (a.value.max.y * 2).rounded(), yb = (b.value.max.y * 2).rounded()
            return ya != yb ? ya > yb : (a.value.min.x, a.key) < (b.value.min.x, b.key)
        }.map(\.key)
    }

    /// Keyboard (] / [) and VoiceOver element stepping: selects the next visible element, keeps it on screen and
    /// announces it.
    func stepSelection(_ delta: Int) {
        let order = readingOrder
        guard !order.isEmpty else { return }
        let current = state.session.selection.single.flatMap { order.firstIndex(of: $0) }
        let next = current.map { ($0 + delta + order.count) % order.count } ?? (delta > 0 ? 0 : order.count - 1)
        state.session.selection.select([order[next]])
        if let e = state.model[order[next]] {
            if let b = graphics?.items.first(where: { $0.elementID == e.id })?.bounds, !b.isEmpty, !visibleViewRect.contains(b.center) { center = b.center }
            let text = "\(describe(e)), \(next + 1) of \(order.count)"
            state.hoverDescription = text
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        needsDisplay = true
    }

    private var visibleViewRect: Rect2 { Rect2(points: [toView(NSPoint(x: bounds.minX, y: bounds.minY)), toView(NSPoint(x: bounds.maxX, y: bounds.maxY))]) }

    func zoomToSelection() {
        let ids = Set(state.session.selection.ids)
        let r = (graphics?.items ?? []).filter { $0.elementID.map(ids.contains) == true && !$0.bounds.isEmpty }.reduce(Rect2.empty) { $0.union($1.bounds) }
        if !r.isEmpty { userAdjusted = true; zoom(to: r) }
    }
}

/// Transparent layer above the Metal canvas for the interactive overlays; events pass through to the canvas.
final class CanvasOverlayView: NSView {
    weak var canvas: Canvas2DView?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        canvas?.drawOverlays(ctx)
    }
}

extension Canvas2DView {
    /// What is on screen, as a bitmap: backdrop, the display list (rendered offscreen by the same Metal renderer when the
    /// GPU path is active) and the overlays. `cacheDisplay` can't see a Metal layer, so QA and diagnostics use this.
    func renderedSnapshot() -> NSBitmapImageRep? {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = gctx
        gctx.cgContext.scaleBy(x: scale, y: scale)
        // Resolve dynamic colours (canvas, overlays) with this view’s appearance, as AppKit does when it draws the view.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            draw(bounds)
            if let mv = metalView, let g = graphics {
            if let image = metalImage(mv, width: w, height: h, scale: scale) {
                gctx.cgContext.draw(image, in: bounds)
            } else {
                // Scene still building: draw the same display list with CoreGraphics.
                GraphicsRenderer.draw(g, in: gctx.cgContext, viewToDevice: viewToDevice, pointsPerPaperMeter: zoom * scaleDenominator,
                                      options: { var o = mv.options; o.background = nil; return o }(), clip: bounds)
            }
                drawOverlays(gctx.cgContext)
            }
        }
        return rep
    }

    private func metalImage(_ mv: MetalCanvasView, width: Int, height: Int, scale: Double) -> CGImage? {
        guard mv.scene != nil, let r = mv.renderer, let target = r.makeOffscreenTarget(width: width, height: height),
              let stats = r.encode(to: target, viewToDevice: viewToDevice, pointsPerPaperMeter: zoom * scaleDenominator, pixelsPerPoint: scale) else { return nil }
        _ = r.waitUntilCompleted(stats)
        let bytes = MetalCanvasRenderer.readPixels(target)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
