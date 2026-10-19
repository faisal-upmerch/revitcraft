import Foundation
import ArcusGeometry
import ArcusDomain

// FMG1: Blend's Edit Base / Edit Top, as Revit's Blend sketch: the base and the top are separate sketches. The sketch
// starts on the base; Edit Top keeps the base's lines (shown dimmed) and sketches the top; Edit Base goes back.
// First End and Second End (the Options Bar and Properties) are the two sketches' offsets from the work plane. A
// selected blend opens its base or top for editing.

extension SketchTool {
    /// True for a Blend sketch (solid or void) in a Furniture document.
    public var isBlendSketch: Bool { if case .fm4(.form(.blend, _)) = target { return true }; return false }
    /// True while a Blend sketch is on its top.
    public var isEditingBlendTop: Bool { isBlendSketch && fm4.editingTop }

    /// "Blend Base Boundary" or "Blend Top Boundary" while sketching a blend.
    var fmg1Title: String? {
        guard isBlendSketch, case .fm4(.form(_, let v)) = target else { return nil }
        return (v ? "Void " : "") + (fm4.editingTop ? "Blend Top Boundary" : "Blend Base Boundary")
    }

    /// Switches a Blend sketch to its top (true) or base: the lines drawn so far are kept for the other sketch.
    public func editBlend(top: Bool) {
        guard isBlendSketch, top != fm4.editingTop else { return }
        commitPendingSpline()
        swap(&curves, &fm4.otherSketch)
        fm4.editingTop = top
        start = nil; arcEnd = nil; filletPicks = []; errorCurves = []
        message(top ? "Sketch the top loop. Edit Base goes back to the base." : "Sketch the base loop. Edit Top sketches the top.")
        rebuild()
    }

    /// The other sketch of a blend, dimmed under the one being drawn.
    func fmg1RebuildBlend() {
        guard isBlendSketch, !fm4.otherSketch.isEmpty else { return }
        let dim = GStroke(weight: 1, color: RGBColor(0.55, 0.6, 0.66), pattern: .dash)
        for c in fm4.otherSketch {
            switch c {
            case .line(let s): preview.primitives.append(.polyline([s.start, s.end], closed: false, dim))
            case .arc(let a): preview.primitives.append(.arc(a, dim))
            }
        }
    }

    /// The blend's base and top loops (plan points): each from its own sketch. A sketch with both loops in it (as before
    /// Edit Top) still gives the larger as the base.
    func fmg1BlendLoops(_ polys: [Polygon2]) -> ([Vec2], [Vec2])? {
        let other: Polygon2? = {
            guard !fm4.otherSketch.isEmpty, case .success(let p) = Sketch(loops: splitLoops(fm4.otherSketch)).polygons() else { return nil }
            return p.max { $0.area < $1.area }
        }()
        guard let mine = polys.max(by: { $0.area < $1.area }) else { return nil }
        if let other { return fm4.editingTop ? (other.points, mine.points) : (mine.points, other.points) }
        guard fm4.otherSketch.isEmpty, polys.count >= 2 else { return nil }
        let sorted = polys.sorted { $0.area > $1.area }
        return (sorted[0].points, sorted[1].points)
    }

    /// Finish for a blend: both sketches must be closed loops (the one on screen is checked as any sketch is); the
    /// blend is created, or the selected one updated. False keeps the sketch open.
    func fmg1FinishBlend() -> Bool {
        guard case .fm4(.form(_, let isVoid)) = target else { return false }
        let loops = splitLoops(curves)
        if let issue = SketchValidation.validate(curves, loops: loops) { presentSketchIssue(issue); return false }
        guard case .success(let polys) = Sketch(loops: loops).polygons(), ctx.isPlan, let (base, top) = fmg1BlendLoops(polys) else {
            message(fmg1BlendMessage)
            return false
        }
        let w = fm4WorkPlane
        var f = FurnitureFormData(kind: .blend, isVoid: isVoid, profile: base, w0: w + fm4.start, w1: w + fm4.end)
        f.topProfile = top
        guard f.w1 - f.w0 > Tolerance.length else { message("Second End must be above First End."); return false }
        if fmg1UpdateBlend(f) { return ctx.session.lastError == nil }
        var created: ElementID?
        ctx.session.perform(isVoid ? "Create Void Blend" : "Create Blend") { tx in created = try FurniturePartOperations.createForm(f, in: tx) }
        guard ctx.session.lastError == nil else { return false }
        keepSelected(created)
        return true
    }

    var fmg1BlendMessage: String {
        guard ctx.isPlan else { return "Sketch a blend in a plan." }
        return fm4.editingTop ? "Sketch the base too: Edit Base." : "Sketch the top too: Edit Top."
    }

    /// Editing a selected blend: its base and top replace the old ones (keeping its material and settings). True when
    /// handled.
    func fmg1UpdateBlend(_ f: FurnitureFormData) -> Bool {
        guard let id = editingID, ctx.model[id]?.furnitureForm?.kind == .blend else { return false }
        ctx.session.perform("Edit Blend") { tx in
            tx.update(id) { e in
                guard var d = e.furnitureForm else { return }
                d.profile = f.profile; d.topProfile = f.topProfile; d.w0 = f.w0; d.w1 = f.w1
                e.furnitureForm = d
            }
        }
        if ctx.session.lastError == nil { keepSelected(id) }
        return true
    }

    /// A sketch that edits a selected blend's base or top, with the other loop kept, and its ends as First End and
    /// Second End.
    public static func editBlend(_ ctx: ToolContext, _ id: ElementID, top: Bool, commandID: CommandID) -> SketchTool? {
        guard let e = ctx.model[id], let f = e.furnitureForm, f.kind == .blend, let topLoop = f.topProfile else { return nil }
        let t = SketchTool(ctx: ctx, target: .fm4(.form(.blend, isVoid: f.isVoid)), commandID: commandID, editing: id)
        let base = Polygon2(f.profile).edges.map { Curve2.line($0) }, upper = Polygon2(topLoop).edges.map { Curve2.line($0) }
        t.curves = top ? upper : base
        t.fm4.otherSketch = top ? base : upper
        t.fm4.editingTop = top
        let w = ctx.levelElevation
        t.fm4.start = f.w0 - w
        t.fm4.end = f.w1 - w
        t.drawMode = .line
        return t
    }
}
