import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain

// W4-FAMED: the family canvas. Plan, elevation and 3D views of the family drawn with CoreGraphics, navigated like the
// project's 2D views (wheel zooms about the cursor, trackpad scroll and middle-drag pan, pinch zooms, double-click fits),
// with selection, plane dragging and the Create tools sketched directly on it.
// F1415: Back and Left elevations (mirrored horizontal axis), orbit in the Default 3D view, sketch mode (loops, paths and
// rectangles whose points lock to the planes they snap to), model and reference lines, controls, model text, masking
// regions and the work plane.

struct FamilyCanvas: NSViewRepresentable {
    let model: FamilyEditorModel
    /// FES: the floating shell's insets; zoom to fit and the canvas's own captions keep to the part not under it.
    var insets = NSEdgeInsets()

    func makeNSView(context: Context) -> FamilyCanvasView {
        let v = FamilyCanvasView()
        v.model = model
        v.chromeInsets = insets
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) } // FES: F, Esc and Delete work as soon as the window opens
        return v
    }
    func updateNSView(_ v: FamilyCanvasView, context: Context) {
        v.chromeInsets = insets // FES
        if let z = model.chrome.zoomRequest { // FES: the bottom pill's zoom menu
            DispatchQueue.main.async { model.chrome.zoomRequest = nil }
            v.zoom(toScale: z)
        }
        if v.revision != model.drawingRevision {
            v.revision = model.drawingRevision
            v.drawing = FamilyPreviewDrawing.make(model.evaluated, model.family, mode: model.view, detail: model.detail, applyVisibility: model.applyVisibility,
                                                  orbit: model.orbit, fast: model.orbiting, formatLength: model.length)
        }
        v.selection = model.selection
        v.sketch = model.sketch // F1415
        if v.tool != model.tool { v.tool = model.tool; v.pending = nil; v.pendingPlane = nil; v.chainStart = nil; v.pendingCorner = nil }
        if v.viewMode != model.view { v.viewMode = model.view; v.fitted = false }
        if v.fitSeen != model.fitRequest { v.fitSeen = model.fitRequest; v.fitted = false }
        if !v.fitted { v.zoomToFit() }
        v.needsDisplay = true
    }
}

final class FamilyCanvasView: NSView {
    weak var model: FamilyEditorModel?
    var drawing = FamilyPreviewDrawing()
    var selection: FamilyEditing.Item?
    var tool: FamilyCanvasTool?
    var viewMode: FamilyPreviewMode = .plan
    var camera = FamilyEditing.Camera() { didSet { if camera.scale != oldValue.scale { reportZoom() } } } // FES: the bottom pill's readout
    /// FES: the floating shell's insets from the view's edges (top-left origin, the view is flipped).
    var chromeInsets = NSEdgeInsets() { didSet { needsDisplay = true; refitIfUntouched() } }
    /// FES: the last zoom to fit; while the camera hasn't moved since, the view stays fitted as the window or shell changes.
    var lastFit: FamilyCanvasFit.Record?
    var fitted = false
    var fitSeen = 0
    var revision = -1
    private var hover: FamilyEditing.Item?
    private var hoverPlane: String?
    var cursor: Vec2? // SFE: read by the snap feedback
    /// SFE: object snapping (FamilyCanvas+SFE.swift).
    var snapState: FamilySnapState?
    /// First plane or point of a two-click tool.
    var pending: Vec2?
    var pendingPlane: String?
    /// F1415: the sketch being drawn, the last point of a model-line chain and a rectangle's first corner (sketch coordinates).
    var sketch: FamilyEditing.Sketch?
    var chainStart: FamilyEditing.SketchVertex?
    var pendingCorner: FamilyEditing.SketchVertex?
    private enum Drag { case none, pan(CGPoint), plane(String, Double), rubber(FamilyEditing.SketchVertex, FamilyEditing.SketchVertex), maybeSelect, orbit(CGPoint, moved: Bool) }
    private var drag: Drag = .none
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    private var size: Vec2 { Vec2(bounds.width, bounds.height) }
    private func screen(_ p: Vec2) -> CGPoint { let s = camera.toScreen(p, size: size); return CGPoint(x: s.x, y: s.y) }
    private func modelPoint(_ e: NSEvent) -> Vec2 { let p = convert(e.locationInWindow, from: nil); return camera.toModel(Vec2(p.x, p.y), size: size) }
    private var tolerance: Double { 6 / camera.scale }

    func zoomToFit() {
        guard bounds.width > 10, bounds.height > 10 else { return }
        camera = FamilyCanvasFit.camera(drawing.fitBounds, size: size, insets: chromeInsets) // FES: fits the part not under the shell
        lastFit = FamilyCanvasFit.Record(size: bounds.size, insets: chromeInsets, camera: camera)
        fitted = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if !fitted { zoomToFit() } else { refitIfUntouched() }
    }

    /// Snaps a view point like the project's 2D views (endpoints, intersections, reference planes, tracking…), else to the
    /// millimetre. // SFE
    private func snap(_ p: Vec2) -> Vec2 { sfeSnap(p).0 }

    private func planeLines() -> [FamilyEditing.PlaneLine] { drawing.planes.map { .init(name: $0.name, vertical: $0.vertical, value: $0.value) } }

    /// F1415: the view's sketch frame (plan in 3D, where nothing is sketched).
    private var viewFrame: FamilyEditing.ViewFrame { viewMode.frame ?? .plan }
    /// A view point snapped like `snap(_:)`, in sketch coordinates, locked to the planes it lies on. // SFE
    private func vertex(_ p: Vec2) -> FamilyEditing.SketchVertex { sfeVertex(p) }
    /// A sketch-coordinate point on screen.
    private func screen(_ v: FamilyEditing.SketchVertex, in f: FamilyEditing.ViewFrame? = nil) -> CGPoint { screen((f ?? viewFrame).view(v.point)) }

    private func hitTest(_ p: Vec2) -> FamilyEditing.Item? {
        if let n = FamilyEditing.hitPlane(planeLines(), at: p, tolerance: tolerance) { return .plane(n) }
        if let d = hitDimension(p) { return .dimension(d) }
        for l in drawing.labels where l.item != nil && l.position.distance(to: p) < tolerance * 3 { return l.item }
        for c in drawing.controls where c.item != nil && c.position.distance(to: p) < tolerance * 3 { return c.item } // F1415
        return FamilyEditing.hitOutline(drawing.outlines, at: p, tolerance: tolerance)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let p = modelPoint(event)
        cursor = p
        model?.cursorText = String(format: "u %@  v %@", model?.length(p.x) ?? "", model?.length(p.y) ?? "")
        sfeHover(p) // SFE
        let before = hover, beforePlane = hoverPlane
        if tool == .dimension { hoverPlane = FamilyEditing.hitPlane(planeLines(), at: p, tolerance: tolerance); hover = nil }
        else if tool == nil { hover = hitTest(p); hoverPlane = nil }
        else { hover = nil; hoverPlane = nil }
        if hover != before || hoverPlane != beforePlane || tool != nil || pending != nil { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; cursor = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let raw = modelPoint(event)
        if event.clickCount == 2 && tool == nil && viewMode != .threeD { zoomToFit(); return }
        if event.modifierFlags.contains(.option) { drag = .pan(convert(event.locationInWindow, from: nil)); return }
        guard let model else { return }
        if viewMode == .threeD && tool == nil {
            // F1415: click selects, drag orbits (Default 3D view).
            model.select(hitTest(raw))
            drag = .orbit(convert(event.locationInWindow, from: nil), moved: false)
            return
        }
        switch tool {
        case nil:
            let hit = hitTest(raw)
            model.select(hit)
            if case .plane(let n)? = hit, let pl = drawing.planes.first(where: { $0.name == n }) { drag = .plane(n, pl.vertical ? raw.x : raw.y); sfeExclude(.plane(n)) } else { drag = .maybeSelect } // SFE
        case .referencePlane(let vertical)?:
            let p = snap(raw)
            model.addPlane(vertical: vertical, at: vertical ? p.x * viewMode.uSign : p.y) // F1415: Back/Left run −X/−Y
        case .dimension?:
            guard let n = FamilyEditing.hitPlane(planeLines(), at: raw, tolerance: tolerance) else { model.message = "Click a reference plane."; return }
            if let a = pendingPlane {
                model.addDimension(a, n); pendingPlane = nil
            } else { pendingPlane = n }
        case .symbolicLine?, .annotationLine?:
            let p = snap(raw)
            if let a = pending { model.addLine(from: a, to: p, annotation: tool == .annotationLine); pending = nil } else { pending = p }
        case .label?:
            model.addLabel(at: snap(raw))
        case .sketch?:
            guard viewMode != .threeD else { return }
            let v = vertex(raw)
            if model.sketchDraw == .rectangle, sketch?.drawsPath == false { drag = .rubber(v, v) } else { model.addSketchVertex(v) }
        case .axisLine?:
            model.setSketchAxis(vertex(raw))
        case .modelLine(let reference)?:
            let v = vertex(raw)
            if let a = chainStart { model.addModelLine(from: a, to: v, reference: reference) }
            chainStart = v // the next line starts where this one ended
        case .control(let kind)?:
            model.placeControl(at: vertex(raw), kind: kind)
        case .modelText(let text)?:
            model.placeModelText(text, at: vertex(raw))
        }
        if tool != nil { sfePickDone() } // SFE
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        switch drag {
        case .pan(let last):
            camera = camera.panned(by: Vec2(sp.x - last.x, sp.y - last.y))
            drag = .pan(sp)
        case .plane(let n, _):
            let p = snap(modelPoint(event))
            guard let pl = drawing.planes.first(where: { $0.name == n }) else { return }
            drag = .plane(n, pl.vertical ? p.x : p.y)
        case .rubber(let a, _):
            cursor = modelPoint(event) // SFE: the snap feedback follows the drag
            drag = .rubber(a, vertex(modelPoint(event)))
        case .orbit(let last, let moved):
            guard let model else { return }
            let dx = Double(sp.x - last.x), dy = Double(sp.y - last.y)
            guard moved || abs(dx) + abs(dy) > 3 else { return }
            var o = model.orbit
            o.yaw -= dx * 0.4
            o.pitch = max(-89, min(89, o.pitch + dy * 0.4))
            model.orbiting = true
            model.orbit = o
            drag = .orbit(sp, moved: true)
        default: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none; needsDisplay = true; sfeExclude(nil) } // SFE
        switch drag {
        case .plane(let n, let v):
            guard let pl = drawing.planes.first(where: { $0.name == n }), abs(v - pl.value) > 1e-6 else { return }
            model?.movePlane(n, to: pl.vertical ? v * viewMode.uSign : v)
        case .rubber(let a, let b):
            // F1415: a dragged rectangle, or a rectangle by two clicks.
            if abs(a.u - b.u) > tolerance && abs(a.v - b.v) > tolerance { model?.addSketchRectangle(a, b); pendingCorner = nil }
            else if let c = pendingCorner { model?.addSketchRectangle(c, a); pendingCorner = nil }
            else { pendingCorner = a }
        case .orbit(_, let moved):
            if moved { model?.orbiting = false }
        default: break
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        // F1415: as in project 3D views, Shift + middle drag orbits; middle drag pans.
        drag = viewMode == .threeD && event.modifierFlags.contains(.shift) ? .orbit(sp, moved: false) : .pan(sp)
    }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        guard let model else { return }
        let hit = hitTest(modelPoint(event))
        if hit != nil { model.select(hit) }
        let menu = NSMenu()
        if let s = model.selection {
            menu.addItem(withTitle: "Delete \(model.title(s))", action: #selector(deleteSelection), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Duplicate", action: #selector(duplicateSelection), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Zoom to Fit", action: #selector(fit), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func deleteSelection() { model?.deleteSelection() }
    @objc private func duplicateSelection() { model?.duplicateSelection() }
    @objc private func fit() { zoomToFit() }

    override func scrollWheel(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) {
            camera = camera.panned(by: Vec2(event.scrollingDeltaX, event.scrollingDeltaY))
        } else {
            let dy = Double(event.scrollingDeltaY) * (!event.hasPreciseScrollingDeltas && event.isDirectionInvertedFromDevice ? -1 : 1)
            camera = camera.zoomed(by: NavigationZoom.factor(dy: dy, precise: event.hasPreciseScrollingDeltas), at: Vec2(sp.x, sp.y), size: size)
        }
        needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        let sp = convert(event.locationInWindow, from: nil)
        camera = camera.zoomed(by: 1 + event.magnification, at: Vec2(sp.x, sp.y), size: size)
        needsDisplay = true
    }
    override func smartMagnify(with event: NSEvent) { zoomToFit() }

    override func keyDown(with event: NSEvent) {
        guard let model else { super.keyDown(with: event); return }
        if sfeKey(event) { return } // SFE: Tab cycles snaps, typed SE, SM, … override the next pick
        switch event.keyCode {
        case 51, 117:
            if model.sketch != nil { model.undoSketchVertex() } else { model.deleteSelection() }
        case 36 where model.sketch != nil, 76 where model.sketch != nil: model.finishSketch() // F1415: Return finishes the sketch
        case 53:
            if model.sketch != nil {
                // F1415: in sketch mode Esc ends the chain; Cancel Edit Mode leaves it (a blank sketch is left at once).
                if pendingCorner != nil || model.tool == .axisLine { pendingCorner = nil; model.tool = .sketch }
                else if model.sketch?.vertices.isEmpty == true { model.cancelSketch() }
            } else if case .modelLine? = model.tool, chainStart != nil {
                chainStart = nil
            } else if model.tool != nil { model.tool = nil; pending = nil; pendingPlane = nil } else { model.select(nil) }
            needsDisplay = true
        default:
            if event.charactersIgnoringModifiers == "f" && !event.modifierFlags.contains(.command) { zoomToFit() } else { super.keyDown(with: event) }
        }
    }

    // MARK: Drawing

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Tokens.canvas.setFill()
        ctx.fill(bounds)
        drawGrid(ctx)
        let ink = NSColor.labelColor
        let selectColor = Tokens.selection, hoverColor = Tokens.preselection
        func isSelected(_ i: FamilyEditing.Item?) -> Bool { i != nil && i == selection }
        func isHover(_ i: FamilyEditing.Item?) -> Bool { i != nil && i == hover && !isSelected(i) }

        // Reference planes.
        let planeColor = NSColor(calibratedRed: 0.1, green: 0.55, blue: 0.2, alpha: 1)
        for p in drawing.planes {
            let sel = isSelected(.plane(p.name)), hov = isHover(.plane(p.name)) || (tool == .dimension && (hoverPlane == p.name || pendingPlane == p.name))
            var value = p.value
            if case .plane(let n, let v) = drag, n == p.name { value = v }
            let a = p.vertical ? Vec2(value, camera.toModel(Vec2(0, size.y), size: size).y) : Vec2(camera.toModel(.zero, size: size).x, value)
            let b = p.vertical ? Vec2(value, camera.toModel(.zero, size: size).y) : Vec2(camera.toModel(Vec2(size.x, 0), size: size).x, value)
            ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : planeColor.withAlphaComponent(p.strong ? 0.9 : 0.6)).cgColor)
            ctx.setLineWidth(sel ? 2 : p.strong ? 1.1 : 0.8)
            ctx.setLineDash(phase: 0, lengths: [8, 4])
            ctx.move(to: screen(a)); ctx.addLine(to: screen(b)); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            let name = p.origin ? "\(p.name) ⌖" : p.name
            let at = p.vertical ? CGPoint(x: screen(a).x + 4, y: chromeInsets.top + 6) : CGPoint(x: chromeInsets.left + 6, y: screen(a).y - 14) // FES: names in view, not under the shell
            text(name, at: at, size: 10, color: sel ? selectColor : planeColor, weight: p.strong ? .semibold : .regular)
        }

        // Fills and strokes.
        for f in drawing.fills {
            let path = CGMutablePath()
            path.addLines(between: f.polygon.points.map(screen)); path.closeSubpath()
            ctx.addPath(path)
            // F1415: a masking region hides what is under it.
            let base = f.masking ? Tokens.canvas : NSColor(white: isDark ? 0.75 : 0.5, alpha: 0.22)
            ctx.setFillColor((isSelected(f.item) ? selectColor.withAlphaComponent(0.22) : isHover(f.item) ? hoverColor.withAlphaComponent(0.18) : base).cgColor)
            ctx.fillPath()
        }
        for st in drawing.strokes {
            let path = CGMutablePath()
            path.addLines(between: st.points.map(screen))
            if st.closed { path.closeSubpath() }
            ctx.addPath(path)
            let sel = isSelected(st.item), hov = isHover(st.item)
            switch st.style {
            case .solid: ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : ink).cgColor); ctx.setLineWidth(sel ? 2.2 : 1)
            case .symbol: ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : ink).cgColor); ctx.setLineWidth(sel ? 2.4 : 1.3)
            case .swing: ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : NSColor.secondaryLabelColor).cgColor); ctx.setLineWidth(sel ? 2 : 0.8)
            case .void: ctx.setStrokeColor((sel ? selectColor : NSColor.systemOrange).cgColor); ctx.setLineWidth(sel ? 2 : 1); ctx.setLineDash(phase: 0, lengths: [4, 2])
            case .hiddenByVisibility: ctx.setStrokeColor((sel ? selectColor : NSColor.secondaryLabelColor.withAlphaComponent(0.5)).cgColor); ctx.setLineWidth(0.8); ctx.setLineDash(phase: 0, lengths: [2, 2])
            case .reference: ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : planeColor).cgColor); ctx.setLineWidth(sel ? 2 : 1.1) // F1415: reference lines are green
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        for l in drawing.labels {
            let sel = isSelected(l.item), hov = isHover(l.item)
            let p = screen(l.position)
            let w = CGFloat(l.text.count) * 6.5 + 10
            let box = CGRect(x: p.x - w / 2, y: p.y - 9, width: w, height: 18)
            ctx.setStrokeColor((sel ? selectColor : hov ? hoverColor : NSColor.tertiaryLabelColor).cgColor)
            ctx.setLineWidth(sel ? 1.5 : 0.6)
            ctx.stroke(box)
            text(l.text, at: CGPoint(x: box.minX + 5, y: box.minY + 2), size: 10, color: sel ? selectColor : ink)
        }

        for c in drawing.controls { // F1415: flip controls, thin arrows
            let col = isSelected(c.item) ? selectColor : isHover(c.item) ? hoverColor : NSColor.systemBlue
            drawControl(ctx, at: screen(c.position), kind: c.kind, color: col)
        }

        drawDimensions(ctx)
        drawWorkPlane(ctx)
        drawSketch(ctx)
        drawToolFeedback(ctx)
        sfeDrawSnap(ctx) // SFE
    }

    private func drawGrid(_ ctx: CGContext) {
        // A step that is at least 28 pt on screen, from a 1-2-5 series in metres.
        let steps: [Double] = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50]
        guard let step = steps.first(where: { $0 * camera.scale >= 28 }) else { return }
        let lo = camera.toModel(Vec2(0, size.y), size: size), hi = camera.toModel(Vec2(size.x, 0), size: size)
        let minor = (Tokens.construction).withAlphaComponent(isDark ? 0.18 : 0.14).cgColor
        let major = (Tokens.construction).withAlphaComponent(isDark ? 0.4 : 0.32).cgColor
        ctx.setLineWidth(0.5)
        var x = (lo.x / step).rounded(.down) * step
        while x <= hi.x {
            let k = Int((x / step).rounded())
            ctx.setStrokeColor(k % 5 == 0 ? major : minor)
            let sx = screen(Vec2(x, 0)).x
            ctx.move(to: CGPoint(x: sx, y: 0)); ctx.addLine(to: CGPoint(x: sx, y: bounds.height)); ctx.strokePath()
            x += step
        }
        var y = (lo.y / step).rounded(.down) * step
        while y <= hi.y {
            let k = Int((y / step).rounded())
            ctx.setStrokeColor(k % 5 == 0 ? major : minor)
            let sy = screen(Vec2(0, y)).y
            ctx.move(to: CGPoint(x: 0, y: sy)); ctx.addLine(to: CGPoint(x: bounds.width, y: sy)); ctx.strokePath()
            y += step
        }
        // Origin cross.
        let o = screen(.zero)
        ctx.setStrokeColor(Tokens.construction.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: o.x - 8, y: o.y)); ctx.addLine(to: CGPoint(x: o.x + 8, y: o.y))
        ctx.move(to: CGPoint(x: o.x, y: o.y - 8)); ctx.addLine(to: CGPoint(x: o.x, y: o.y + 8)); ctx.strokePath()
        reportGrid(step) // FES: the zoom and grid step read out in the bottom pill
    }

    /// Dimension lines stacked outside the content: strings between vertical planes run below it, others to its left.
    private func drawDimensions(_ ctx: CGContext) {
        var below = 0, left = 0
        let content = drawing.contentBounds.isEmpty ? Rect2(center: .zero, halfSize: Vec2(0.1, 0.1)) : drawing.contentBounds
        for dim in drawing.dimensions {
            let sel = selection == .dimension(dim.id)
            let color = dim.conflict ? NSColor.systemRed : sel ? Tokens.selection : NSColor.systemBlue
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(sel ? 1.6 : 0.8)
            let values = [dim.a, dim.b] + (dim.c.map { [$0] } ?? [])
            let lo = values.min()!, hi = values.max()!
            if dim.vertical {
                below += 1
                let y = screen(Vec2(0, content.min.y)).y + CGFloat(below) * 22
                ctx.move(to: CGPoint(x: screen(Vec2(lo, 0)).x, y: y)); ctx.addLine(to: CGPoint(x: screen(Vec2(hi, 0)).x, y: y))
                for v in values {
                    let x = screen(Vec2(v, 0)).x
                    ctx.move(to: CGPoint(x: x, y: y - 6)); ctx.addLine(to: CGPoint(x: x, y: y + 6))
                    ctx.move(to: CGPoint(x: x - 3, y: y + 3)); ctx.addLine(to: CGPoint(x: x + 3, y: y - 3))
                }
                ctx.strokePath()
                let segs = dim.c != nil ? [(dim.a, dim.b), (dim.b, dim.c!)] : [(lo, hi)]
                for (u0, u1) in segs {
                    let mid = (screen(Vec2(u0, 0)).x + screen(Vec2(u1, 0)).x) / 2
                    text(dim.text, at: CGPoint(x: mid, y: y - 15), size: 10, color: color, weight: dim.labeled || dim.c != nil ? .semibold : .regular, centered: true)
                }
            } else {
                left += 1
                let x = screen(Vec2(content.min.x, 0)).x - CGFloat(left) * 22
                ctx.move(to: CGPoint(x: x, y: screen(Vec2(0, lo)).y)); ctx.addLine(to: CGPoint(x: x, y: screen(Vec2(0, hi)).y))
                for v in values {
                    let y = screen(Vec2(0, v)).y
                    ctx.move(to: CGPoint(x: x - 6, y: y)); ctx.addLine(to: CGPoint(x: x + 6, y: y))
                    ctx.move(to: CGPoint(x: x - 3, y: y + 3)); ctx.addLine(to: CGPoint(x: x + 3, y: y - 3))
                }
                ctx.strokePath()
                let segs = dim.c != nil ? [(dim.a, dim.b), (dim.b, dim.c!)] : [(lo, hi)]
                for (v0, v1) in segs {
                    let mid = CGPoint(x: x - 3, y: (screen(Vec2(0, v0)).y + screen(Vec2(0, v1)).y) / 2)
                    ctx.saveGState()
                    ctx.translateBy(x: mid.x, y: mid.y)
                    ctx.rotate(by: -.pi / 2)
                    text(dim.text, at: CGPoint(x: 0, y: -13), size: 10, color: color, weight: dim.labeled || dim.c != nil ? .semibold : .regular, centered: true)
                    ctx.restoreGState()
                }
            }
        }
    }

    private func hitDimension(_ p: Vec2) -> String? {
        // Dimension strings sit at screen offsets; test in screen space.
        var below = 0, left = 0
        let content = drawing.contentBounds.isEmpty ? Rect2(center: .zero, halfSize: Vec2(0.1, 0.1)) : drawing.contentBounds
        let sp = screen(p)
        for dim in drawing.dimensions {
            let values = [dim.a, dim.b] + (dim.c.map { [$0] } ?? [])
            let lo = values.min()!, hi = values.max()!
            if dim.vertical {
                below += 1
                let y = screen(Vec2(0, content.min.y)).y + CGFloat(below) * 22
                if abs(sp.y - y) < 9, sp.x >= screen(Vec2(lo, 0)).x - 6, sp.x <= screen(Vec2(hi, 0)).x + 6 { return dim.id }
            } else {
                left += 1
                let x = screen(Vec2(content.min.x, 0)).x - CGFloat(left) * 22
                if abs(sp.x - x) < 9, sp.y >= screen(Vec2(0, hi)).y - 6, sp.y <= screen(Vec2(0, lo)).y + 6 { return dim.id }
            }
        }
        return nil
    }

    private func drawToolFeedback(_ ctx: CGContext) {
        guard let tool, let cursor else { return }
        let c = snap(cursor)
        ctx.setStrokeColor(Tokens.selection.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        switch tool {
        case .referencePlane(let vertical):
            ctx.setLineDash(phase: 0, lengths: [8, 4])
            if vertical { let x = screen(c).x; ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)) }
            else { let y = screen(c).y; ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)) }
            ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
        case .symbolicLine, .annotationLine:
            if let a = pending { ctx.move(to: screen(a)); ctx.addLine(to: screen(c)); ctx.strokePath() }
            crosshair(ctx, at: screen(c))
        case .label, .dimension, .control, .modelText:
            crosshair(ctx, at: screen(c))
        case .sketch, .axisLine:
            crosshair(ctx, at: screen(vertex(cursor)))
        case .modelLine(let reference):
            let v = vertex(cursor)
            if let a = chainStart {
                ctx.setStrokeColor((reference ? NSColor(calibratedRed: 0.1, green: 0.55, blue: 0.2, alpha: 1) : NSColor.labelColor).cgColor)
                ctx.move(to: screen(a)); ctx.addLine(to: screen(v)); ctx.strokePath()
            }
            crosshair(ctx, at: screen(v))
        }
    }

    // MARK: F1415 drawing

    /// A flip control: a thin arrow, or two opposed arrows side by side for double controls (RevitCraft `paint_control`).
    private func drawControl(_ ctx: CGContext, at p: CGPoint, kind: FamilyControlKind, color: NSColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.2)
        let len: CGFloat = 9, head: CGFloat = 4
        // Screen y runs down: "up" in plan is −y.
        let dir = kind.isHorizontal ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: -1)
        let side = CGPoint(x: -dir.y, y: dir.x)
        func arrow(_ base: CGPoint, _ d: CGPoint) {
            let tail = CGPoint(x: base.x - d.x * len, y: base.y - d.y * len), tip = CGPoint(x: base.x + d.x * len, y: base.y + d.y * len)
            ctx.move(to: tail); ctx.addLine(to: tip)
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - d.x * head + d.y * head, y: tip.y - d.y * head - d.x * head))
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: tip.x - d.x * head - d.y * head, y: tip.y - d.y * head + d.x * head))
        }
        if kind.isDouble {
            arrow(CGPoint(x: p.x + side.x * 3, y: p.y + side.y * 3), dir)
            arrow(CGPoint(x: p.x - side.x * 3, y: p.y - side.y * 3), CGPoint(x: -dir.x, y: -dir.y))
        } else {
            arrow(p, dir)
        }
        ctx.strokePath()
    }

    /// Work Plane ▸ Show: the work plane tinted when it faces the view, or its edge drawn heavy when seen edge-on.
    private func drawWorkPlane(_ ctx: CGContext) {
        guard let model, model.showWorkPlane, viewMode != .threeD else { return }
        let tint = Tokens.selection
        if let n = model.workPlane, let pl = drawing.planes.first(where: { $0.name == n }) {
            ctx.setStrokeColor(tint.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(6)
            if pl.vertical { let x = screen(Vec2(pl.value, 0)).x; ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)) }
            else { let y = screen(Vec2(0, pl.value)).y; ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)) }
            ctx.strokePath()
            text("Work Plane: \(n)", at: CGPoint(x: chromeInsets.left + 8, y: bounds.height - chromeInsets.bottom - 20), size: 10, color: tint) // FES: above the bottom pill
            return
        }
        ctx.setFillColor(tint.withAlphaComponent(0.05).cgColor)
        ctx.fill(bounds)
        let name = model.workPlane ?? viewFrame.plane.label
        text("Work Plane: \(name)", at: CGPoint(x: chromeInsets.left + 8, y: bounds.height - chromeInsets.bottom - 20), size: 10, color: tint) // FES: above the bottom pill
    }

    /// Sketch mode: the loop or path being drawn (magenta), the stages already finished (halftone), a revolve's axis and a
    /// sweep's profile plane.
    private func drawSketch(_ ctx: CGContext) {
        guard let s = sketch, let model, viewMode != .threeD else { return }
        let ink = NSColor.systemPink
        let half = ink.withAlphaComponent(0.35)
        ctx.setLineWidth(1.4)
        if s.form == .blend, s.stage == 1, viewMode == .plan, s.base.count >= 3 {
            let pts = s.base.map { screen(Vec2(model.value(of: $0.x), model.value(of: $0.y))) }
            ctx.setStrokeColor(half.cgColor); ctx.addLines(between: pts); ctx.closePath(); ctx.strokePath()
        }
        if s.form == .sweep || s.form == .sweptBlend, s.stage > 0 {
            let path = s.path.map { Vec2(model.value(of: $0.x), model.value(of: $0.y)) }
            if viewMode == .plan {
                ctx.setStrokeColor(half.cgColor); ctx.setLineWidth(2); ctx.addLines(between: path.map(screen)); ctx.strokePath(); ctx.setLineWidth(1.4)
            } else if let st = FamilyEditing.profileStation(path, form: s.form, atEnd: s.stage == 2) {
                // The profile plane seen edge-on, at the path's height.
                let u = st.point.dot(viewFrame.uAxisPlan) * viewFrame.uSign, z0 = model.value(of: s.pathZ)
                ctx.setStrokeColor(half.cgColor); ctx.setLineDash(phase: 0, lengths: [6, 3])
                let x = screen(Vec2(u, 0)).x, y = screen(Vec2(0, z0)).y
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height))
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y))
                ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
                text("Profile plane", at: CGPoint(x: x + 4, y: y - 14), size: 9, color: half)
            }
        }
        if s.form == .revolve, viewMode.frame?.plane == s.frame.plane {
            let x = screen(Vec2(s.axisU * viewFrame.uSign, 0)).x
            ctx.setStrokeColor(ink.cgColor); ctx.setLineDash(phase: 0, lengths: [10, 3, 2, 3])
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            text("Axis", at: CGPoint(x: x + 4, y: chromeInsets.top + 6), size: 9, color: ink) // FES: under the shell
        }
        guard s.frame == viewFrame else {
            if !s.vertices.isEmpty { text("The sketch is in \(FamilyPreviewMode.view(for: s.frame).viewTitle).", at: CGPoint(x: chromeInsets.left + 8, y: chromeInsets.top + 8), size: 11, color: ink) } // FES: under the shell
            return
        }
        let pts = s.vertices.map { screen($0) }
        ctx.setStrokeColor(ink.cgColor)
        if pts.count >= 2 { ctx.addLines(between: pts); ctx.strokePath() }
        if !s.drawsPath, pts.count >= 3 {
            ctx.setLineDash(phase: 0, lengths: [3, 3]); ctx.move(to: pts[pts.count - 1]); ctx.addLine(to: pts[0]); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
        }
        for p in pts { ctx.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)) }
        ctx.setFillColor(ink.cgColor)
        // Rubber bands.
        if let cursor, tool == .sketch {
            let c = vertex(cursor)
            if case .rubber(let a, let b) = drag { rect(ctx, screen(a), screen(b), ink) }
            else if let a = pendingCorner { rect(ctx, screen(a), screen(c), ink) }
            else if model.sketchDraw == .line || s.drawsPath, let last = pts.last {
                ctx.setStrokeColor(ink.withAlphaComponent(0.7).cgColor); ctx.move(to: last); ctx.addLine(to: screen(c)); ctx.strokePath()
            }
        }
    }

    private func rect(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ color: NSColor) {
        let r = CGRect(origin: a, size: .zero).union(CGRect(origin: b, size: .zero))
        ctx.setFillColor(color.withAlphaComponent(0.08).cgColor); ctx.fill(r)
        ctx.setStrokeColor(color.cgColor); ctx.stroke(r)
    }

    private func crosshair(_ ctx: CGContext, at p: CGPoint) {
        ctx.move(to: CGPoint(x: p.x - 7, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + 7, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: p.y - 7)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + 7)); ctx.strokePath()
    }

    private func text(_ s: String, at p: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attrs)
        let w = str.size().width
        // Labels stay inside the canvas: a plane near the right edge is named to the left of it.
        let x = min(centered ? p.x - w / 2 : p.x, bounds.width - w - 4)
        str.draw(at: CGPoint(x: max(2, x), y: p.y))
    }
}
