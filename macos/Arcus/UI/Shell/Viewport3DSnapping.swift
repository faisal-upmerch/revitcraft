import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// S3D: object snapping to model geometry in 3D views (ArcusApplication's Snapping3D) wired into the 3D tool
// controller: the index of the view's scene, pointer input with 3D snaps, Tab cycling, and the plan's magenta markers
// and snap label drawn at the snapped point on the model, with dashed tracking lines.

/// 3D snapping state of one 3D view.
@MainActor
final class Viewport3DSnapping {
    private var scene: Viewport3DScene?
    private var index: Snap3DIndex?
    /// The snap in force (its feature puts the marker on the model rather than on the work plane).
    var pick: Snap3DPick?
    /// Snaps stepped through with Tab; the chosen one holds while the pointer stays within 3 points of where Tab was pressed.
    var tab: (picks: [Snap3DPick], index: Int, at: CGPoint)?
    /// S3D2: datum traces on a work plane, and a work plane's 2D snap index, per plane and model revision.
    private var traceCache: (frame: WorkPlaneFrame, revision: UInt64, lines: [Snap3DExtraLine])?
    private var planeCache: (frame: WorkPlaneFrame, revision: UInt64, index: SnapIndex)?

    /// The viewport got a new scene: the index is rebuilt from it on the next query.
    func sceneChanged(_ s: Viewport3DScene) {
        scene = s
        index = nil
        planeCache = nil
    }

    /// The index of the current scene (built lazily; it only records element bounds until a query reaches an element).
    var snapIndex: Snap3DIndex? {
        if index == nil, let s = scene, !s.elements.isEmpty { index = Snap3DIndex(scene: s) }
        return index
    }

    /// S3D2: where visible grids, levels and reference planes cross the plane `f` (snappable lines in it).
    func traces(_ f: WorkPlaneFrame, model: BIMModel, view: Element?) -> [Snap3DExtraLine] {
        if let c = traceCache, c.frame == f, c.revision == model.revision { return c.lines }
        let resolver = view.map { VisibilityResolver(model: model, view: $0) }
        let lines = Lines3D.traces(on: f, model: model, visible: { e in resolver?.resolve(e) != nil })
            .map { Snap3DExtraLine(segment: $0.segment, id: $0.id, category: $0.category) }
            + FurnitureSnapTraces.traces(on: f, model) // FM3D: part faces crossing the plane
        traceCache = (f, model.revision, lines)
        return lines
    }

    /// S3D2: the 2D snap index of a work plane other than a level (edges lying in it, datum traces).
    func planeIndex(_ f: WorkPlaneFrame, model: BIMModel, view: Element?) -> SnapIndex {
        if let c = planeCache, c.frame == f, c.revision == model.revision { return c.index }
        let idx = (snapIndex ?? Snap3DIndex(sources: [])).planeSnapIndex(f, traces: traces(f, model: model, view: view))
        planeCache = (f, model.revision, idx)
        return idx
    }

    func reset() {
        pick = nil
        tab = nil
    }
}

extension Snap3DIndex {
    /// Everything a 3D view draws: model elements, linked models, imports, point clouds and (S3D2) the line elements:
    /// datums, model lines and 2D CAD. Ghosted and glass parts snap but do not hide what is behind them.
    convenience init(scene: Viewport3DScene) {
        let sources = scene.elements.map { e in
            Snap3DSource(id: e.id, category: e.category, meshes: e.parts.map(\.mesh), opaque: e.parts.map { $0.color.a > 0.98 }, bounds: e.bounds)
        }
        self.init(sources: sources, revision: scene.modelRevision)
    }
}

extension Viewport3DToolController {
    /// S3D2: the work plane of this view when it isn't a level (a reference plane or a picked face, Work Plane ▸ Set):
    /// tools that can sit on any plane draw on it.
    var activeSketchPlane: WorkPlaneHost? {
        let m = state.model
        guard let w = m[viewID]?.view?.workPlane else { return nil }
        if case .level = w { return nil }
        guard let f = WorkPlanes.frame(w, m) else { return nil }
        return WorkPlaneHost(frame: f, reference: w)
    }

    /// S3D2: the plane previews and snaps are drawn on: the running tool's work plane, else the level's plane.
    var drawFrame: WorkPlaneFrame {
        if dragTool == nil, let sp = (state.activeTool as? BaseTool)?.ctx.sketchPlane { return sp.frame }
        return .level(planeZ)
    }

    /// The snap query at a view point with the viewport's camera, section box and visual style.
    func snapQuery(at p: CGPoint) -> Snap3DQuery? {
        guard let v = viewport else { return nil }
        var q = Snap3DQuery(pointer: Vec2(Double(p.x), Double(p.y)), camera: v.screenProjection)
        q.clip = v.sectionBox
        q.occlusion = v.visualStyle != .wireframe && v.visualStyle != .transparent
        q.includeLineElements = v.drawsEdges // S3D2: datums, model lines and CAD snap where they are drawn
        return q
    }

    /// The tool input for a pointer sample, snapped to the model geometry of the view and to the work plane.
    func snappedInput(_ s: WorkPlane3D.PointerSample, at p: CGPoint, planeZ z: Double, ctx: ToolContext, graphics: ViewGraphics?,
                      snapFrom: Vec2?, preferSurface: Bool = false, orthoOnly: Bool = false, constrainOrtho: Bool = false) -> ToolInput? {
        guard var q = snapQuery(at: p) else {
            snapping3D.pick = nil
            return WorkPlane3D.toolInput(s, planeZ: z, ctx: ctx, graphics: graphics, snapFrom: snapFrom, preferSurface: preferSurface,
                                         orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
        }
        q.extraLines = snapping3D.traces(.level(z), model: state.model, view: state.model[viewID]) // S3D2
        if let t = snapping3D.tab {
            if hypot(p.x - t.at.x, p.y - t.at.y) <= 3, let raw = WorkPlane3D.planPoint(s, planeZ: z, preferSurface: preferSurface)?.xy {
                let pick = t.picks[t.index]
                snapping3D.pick = pick
                return Snap3DInput.input(s, raw: raw, pick: pick, ctx: ctx, graphics: graphics, preferSurface: preferSurface)
            }
            snapping3D.tab = nil
        }
        guard let r = Snap3DInput.toolInput(s, planeZ: z, ctx: ctx, graphics: graphics, snapFrom: snapFrom, index: snapping3D.snapIndex, query: q,
                                            preferSurface: preferSurface, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho) else {
            snapping3D.pick = nil
            return nil
        }
        snapping3D.pick = r.pick
        return r.input
    }

    /// S3D2: the pointer sample at a view point, with the viewport's pick.
    func pointerSample(at p: CGPoint, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> WorkPlane3D.PointerSample? {
        guard let v = viewport else { return nil }
        let ray = v.pointerRay(at: p)
        let hit = v.pick(at: p)
        var s = WorkPlane3D.PointerSample(origin: ray.origin, direction: ray.direction, pickedID: hit.id, pickedPoint: hit.position)
        s.shift = flags.contains(.shift); s.command = flags.contains(.command); s.option = flags.contains(.option)
        s.clickCount = clickCount
        return s
    }

    /// S3D2: input for a tool drawing on its sketch plane (a reference plane, a face, a named plane): the pointer ray
    /// meets the plane, points are in the plane's coordinates, and the plane's own snap index (edges in it, datum
    /// traces) gives tracking, extension, parallel and perpendicular snaps there, competing with 3D snaps.
    func sketchToolInput(_ event: NSEvent, at p: CGPoint, tool: any InteractiveTool) -> ToolInput? {
        guard let ctx = (tool as? BaseTool)?.ctx, let sp = ctx.sketchPlane, let v = viewport,
              let s = pointerSample(at: p, flags: event.modifierFlags, clickCount: event.type == .mouseMoved ? 1 : event.clickCount),
              var q = snapQuery(at: p) else { return nil }
        let f = sp.frame
        guard let w = f.intersect(origin: s.origin, direction: s.direction) ?? s.pickedPoint else { return nil }
        // Screen tolerances on the plane: a little larger where it is seen at a grazing angle.
        ctx.pixel = max(v.worldPerPoint(at: w), 1e-6) / max(abs(v.cameraAxes.forward.dot(f.normal)), 0.3).squareRoot()
        ctx.snapIndex = snapping3D.planeIndex(f, model: state.model, view: state.model[viewID])
        q.extraLines = snapping3D.traces(f, model: state.model, view: state.model[viewID])
        planePoint = f.local(w)
        if let t = snapping3D.tab {
            if hypot(p.x - t.at.x, p.y - t.at.y) <= 3 {
                let pick = t.picks[t.index]
                snapping3D.pick = pick
                return Snap3DInput.input(s, raw: f.local(w), pick: pick, ctx: ctx, graphics: nil, preferSurface: false)
            }
            snapping3D.tab = nil
        }
        guard let r = Snap3DInput.toolInput(s, plane: f, ctx: ctx, snapFrom: tool.snapFrom, index: snapping3D.snapIndex, query: q,
                                            constrainOrtho: event.modifierFlags.contains(.shift)) else { snapping3D.pick = nil; return nil }
        snapping3D.pick = r.pick
        return r.input
    }

    /// Tab while a tool runs: steps through the snaps under the pointer (model geometry and work plane), as in plan.
    /// Returns the input the tool was given, or nil when there is at most one snap here.
    func cycleSnap3D() -> ToolInput? {
        guard let tool = state.activeTool, let ctx = (tool as? BaseTool)?.ctx, let p = lastMouse, var q = snapQuery(at: p),
              let s = pointerSample(at: p) else { return nil }
        let surface = prefersSurface(tool)
        let f: WorkPlaneFrame = ctx.sketchPlane?.frame ?? .level(planeZ)
        let raw: Vec2
        if ctx.sketchPlane != nil {
            guard let w = f.intersect(origin: s.origin, direction: s.direction) ?? s.pickedPoint else { return nil }
            raw = f.local(w)
            ctx.snapIndex = snapping3D.planeIndex(f, model: state.model, view: state.model[viewID])
        } else {
            guard let q = WorkPlane3D.planPoint(s, planeZ: planeZ, preferSurface: surface) else { return nil }
            raw = q.xy
        }
        q.extraLines = snapping3D.traces(f, model: state.model, view: state.model[viewID])
        if var t = snapping3D.tab, hypot(p.x - t.at.x, p.y - t.at.y) <= 3 {
            t.index = (t.index + 1) % t.picks.count
            snapping3D.tab = t
        } else {
            let found = ctx.snap3DCandidates(raw, plane: f, index: snapping3D.snapIndex, query: q, from: tool.snapFrom)
            guard found.count > 1 else { return nil }
            snapping3D.tab = (found, 1, p)
        }
        guard let t = snapping3D.tab else { return nil }
        let pick = t.picks[t.index]
        snapping3D.pick = pick
        let g = ctx.sketchPlane != nil ? nil : state.graphics.graphics(ctx.viewID).map { WorkPlane3D.modelGraphics($0, model: state.model) }
        let i = Snap3DInput.input(s, raw: raw, pick: pick, ctx: ctx, graphics: g, preferSurface: surface)
        tool.pointerMoved(i)
        state.snapDescription = pick.snap?.description
        state.hoverDescription = "\(pick.snap?.shortLabel ?? pick.snap?.kind.rawValue ?? "Snap") (\(t.index + 1) of \(t.picks.count)). Tab for the next snap."
        state.toolChangedState()
        return i
    }

    /// True when the snap draws a marker and its label (the cursor tooltip then stays out of the way, as in plan).
    var snapLabelShown: Bool {
        guard let s = snap, CanvasSettings.tooltipAssistance != .none else { return false }
        return snapping3D.pick?.feature?.feature != .face && Canvas2DView.snapTooltip(s) != nil
    }

    // MARK: Drawing

    /// Draws the snap as in plan (Canvas2DView.drawSnap): its tracking guides on the work plane, the magenta marker of
    /// its kind at the snapped point (on the model for 3D snaps, with a dashed line down or up to the work plane where
    /// the tool takes it) and its label beside it.
    func drawSnap3D(_ s: SnapResult, _ cg: CGContext, bounds: CGRect, plane: WorkPlaneFrame) {
        guard let v = viewport else { return }
        let feature = snapping3D.pick.flatMap { $0.point.isAlmostEqual(s.point, tolerance: 1e-9) ? $0.feature : nil }
        let onPlane = plane.point(s.point.x, s.point.y)
        let at = feature?.point ?? onPlane
        let axis = s.kind == .angle && (s.label == "HORIZONTAL" || s.label == "VERTICAL")
        drawTrackingGuides(s.guides, cg, plane: plane, acrossView: axis, bounds: bounds)
        // Work-plane tools take the projection of a point off the plane (face-hosted tools take the point itself).
        let onFace = state.activeTool.map(prefersSurface) ?? false
        if let f = feature, f.feature != .face, !onFace, f.point.distance(to: onPlane) > 1e-6 {
            drawTrackingGuides3D([(f.point, onPlane)], cg)
            if let q = v.viewPoint(of: onPlane) {
                cg.saveGState()
                cg.setStrokeColor(Canvas2DView.snapColor.cgColor)
                cg.setLineWidth(1.2)
                cg.strokeEllipse(in: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5))
                cg.restoreGState()
            }
        }
        guard feature?.feature != .face, let p = v.viewPoint(of: at), bounds.insetBy(dx: -20, dy: -20).contains(p) else { return }
        var axisDir = CGVector(dx: 1, dy: 0)
        if axis, let q = v.viewPoint(of: at + (s.label == "HORIZONTAL" ? plane.u : plane.v) * v.worldPerPoint(at: at) * 20) {
            let d = CGVector(dx: q.x - p.x, dy: q.y - p.y), l = hypot(d.dx, d.dy)
            if l > 1e-6 { axisDir = CGVector(dx: d.dx / l, dy: d.dy / l) }
        }
        Self.drawSnapMarker(s.kind, axis: axis ? axisDir : nil, at: p, cg)
        if let text = Canvas2DView.snapTooltip(s), CanvasSettings.tooltipAssistance != .none {
            Self.drawSnapLabel(text, at: CGPoint(x: p.x + 8, y: p.y - 12), cg, bounds: bounds)
        }
    }

    /// Plan guides (view units on the work plane) in plan's tracking-line style; axis guides run across the view.
    private func drawTrackingGuides(_ guides: [Segment2], _ cg: CGContext, plane f: WorkPlaneFrame, acrossView: Bool, bounds: CGRect) {
        func w(_ p: Vec2) -> Vec3 { f.point(p.x, p.y) }
        let segs: [(Vec3, Vec3)] = guides.map { g in
            guard acrossView, let v = viewport else { return (w(g.start), w(g.end)) }
            // Long enough to cross the view at the guide's depth.
            let reach = v.worldPerPoint(at: w(g.start)) * Double(max(bounds.width, bounds.height)) * 2
            let d = (g.end - g.start).normalized
            return (w(g.start - d * reach), w(g.end + d * reach))
        }
        drawTrackingGuides3D(segs, cg)
    }

    /// World segments as dashed tracking lines (Canvas2DView.drawGuides' colour and dash).
    private func drawTrackingGuides3D(_ segs: [(Vec3, Vec3)], _ cg: CGContext) {
        guard let v = viewport, !segs.isEmpty else { return }
        cg.saveGState()
        cg.setStrokeColor(NSColor(srgbRed: 120 / 255, green: 170 / 255, blue: 230 / 255, alpha: 1).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [12, 3, 2, 3])
        for (a, b) in segs { if let (p, q) = v.viewSegment(a, b) { cg.move(to: p); cg.addLine(to: q) } }
        cg.strokePath()
        cg.restoreGState()
    }

    /// The plan's snap markers (Canvas2DView.drawSnap, RevitCraft canvas.rs `paint_snap`), in view points with y up.
    /// `axis`: screen direction of the horizontal/vertical tracking axis, drawn as a hollow double arrow.
    static func drawSnapMarker(_ kind: SnapKind, axis: CGVector?, at p: CGPoint, _ ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(Canvas2DView.snapColor.cgColor)
        ctx.setLineWidth(1.6)
        let r: CGFloat = 5
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: p.x + x, y: p.y - y) }
        func poly(_ q: [CGPoint], close: Bool = true) { ctx.move(to: q[0]); for c in q.dropFirst() { ctx.addLine(to: c) }; if close { ctx.closePath() }; ctx.strokePath() }
        switch kind {
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
            guard let d = axis else { return }
            let n = CGVector(dx: -d.dy, dy: d.dx)
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

    /// The plan's snap label (Canvas2DView.drawSnapLabel): small grey text in a flat light box, top-left at `topLeft`,
    /// kept inside the view.
    static func drawSnapLabel(_ text: String, at topLeft: CGPoint, _ ctx: CGContext, bounds: CGRect) {
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
}
