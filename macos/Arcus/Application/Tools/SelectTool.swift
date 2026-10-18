import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Selecting-and-dragging behavior (Modify mode): click/window/crossing selection is handled by the canvas;
/// this tool handles dragging selected elements and grips with live preview, typed values during a drag, the
/// temporary dimensions of a single selected element, and on-canvas controls (flip arrows, bubble boxes, EQ, lock).
@MainActor
public final class SelectTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.modify
    public let title = "Modify"
    public var prompt: String {
        if dragging { return numericLabel.map { "Release to place, or type a \($0.lowercased()) and press Return." } ?? "Release to place." }
        return ctx.session.selection.isEmpty
            ? "Click to select, drag for a window (left→right) or crossing (right→left) selection. Tab cycles overlapping elements."
            : ctx.session.selection.statusDescription(ctx.model)
    }
    var dragStart: Vec2?
    var dragGrip: Grip?
    var dragCurrent: Vec2?
    var dragging = false

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.cursor = .arrow
    }
    public func pointerDown(_ i: ToolInput) {}

    /// Begins dragging: returns true if the press is on a grip or on a selected element (so the canvas should not start a window selection).
    public func beginDrag(at p: Vec2, grip: Grip?) -> Bool {
        dragGrip = grip
        dragStart = p
        dragCurrent = p
        dragging = false
        // What is being dragged never snaps to its own geometry.
        ctx.snapExclusions = grip.map { [$0.elementID] }
            ?? ElementOperations.dependentsToCarry(Set(ctx.session.selection.ids), ctx.model, viewID: ctx.viewID)
        return true
    }
    public func dragged(to p: Vec2, snapped: Bool = false) {
        pointerSnapped = snapped
        guard let s = dragStart else { return }
        dragging = true
        dragCurrent = p
        preview = ToolPreview()
        if let g = dragGrip {
            // W2-ANNOT: annotations preview live with the grip applied (text, leaders, dimension texts, spots, tags).
            if let prims = annotationGripPreview(g, to: p) { preview.primitives = prims; return }
            preview.primitives = [ctx.line(g.position, p, heavy: true)]
            if case .witness = g.kind { return }
            if let e = ctx.model[g.elementID], let c = ElementOperations.curveOf(e) {
                let other = g.kind == .start ? c.end : c.start
                preview.primitives.append(ctx.line(other, p, heavy: true))
                preview.tempDims = [tempDim(other, p)]
            }
        } else {
            let ids = ctx.session.selection.ids
            let v = moveVector(p, from: s)
            defer { if let g = grabGuide(from: s, by: v) { preview.guides = [g] } }
            // Preview the move on a scratch copy of the model: joined walls stretch to follow, as they will on release.
            let tx = TransactionContext(model: ctx.model, name: "Drag preview")
            if (try? ElementOperations.transform(ids, by: .translation(v), in: tx, viewID: ctx.viewID)) != nil {
                var prims: [GPrimitive] = []
                for id in tx.touchedIDs {
                    guard let e = tx.model[id], e.wall != nil, let poly = WallGeometry.footprint(e, tx.model) else { continue }
                    prims.append(.polyline(poly.points, closed: true, ctx.previewStroke))
                }
                let others = ids.filter { ctx.model[$0]?.wall == nil }
                preview.primitives = prims + MoveCopyTool(ctx: ctx, ids: others, copy: false).ghost(others, .translation(v))
                preview.tempDims = dragDimensions(in: tx.model) ?? [tempDim(s, s + v)]
            } else {
                preview.primitives = MoveCopyTool(ctx: ctx, ids: ids, copy: false).ghost(ids, .translation(v))
                preview.tempDims = [tempDim(s, s + v)]
            }
        }
    }
    /// The annotation being edited by `g`, drawn as it will be when the grip is released (nil for model elements).
    func annotationGripPreview(_ g: Grip, to p: Vec2) -> [GPrimitive]? {
        if case .witness = g.kind { return nil }
        guard let e = ctx.model[g.elementID], e.ownerViewID != nil, e.category.isAnnotation else { return nil }
        let tx = TransactionContext(model: ctx.model, name: "Grip preview")
        GripService.apply(g, to: p, in: tx)
        guard let moved = tx.model[g.elementID], let prims = AnnotationRenderer.previewItem(moved, model: tx.model, scale: ctx.isSheet ? 1 : ctx.scale) else { return nil }
        return AnnotationPreview.tinted(prims, ctx.previewStroke.color)
    }

    public func endDrag(at p: Vec2) { endDrag(ToolInput(point: p, rawPoint: p)) }
    /// Ends a drag. A witness line dropped on another reference re-references the dimension (using the hit and snap in `i`).
    public func endDrag(_ i: ToolInput) {
        let p = i.point
        if i.snap != nil { pointerSnapped = true } else if i.rawPoint == i.point { pointerSnapped = false }
        defer { reset() }
        guard dragging, let s = dragStart, p.distance(to: s) > Tolerance.length * 10 else { return }
        if let g = dragGrip {
            let e = ctx.model[g.elementID]
            if e?.pinned == true { message("The element is pinned. Unpin it to edit."); return }
            if case .witness(let index) = g.kind { moveWitness(g.elementID, index, to: i); return }
            ctx.session.perform("Drag \(e?.category.singularName ?? "Element")") { tx in GripService.apply(g, to: p, in: tx) }
        } else {
            let ids = ctx.session.selection.ids
            let view = ctx.viewID
            let v = moveVector(p, from: s)
            ctx.session.perform("Move") { tx in try ElementOperations.transform(ids, by: .translation(v), in: tx, viewID: view) }
        }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public var isDragging: Bool { dragging }
    /// A grip (an end or shape handle) is being dragged, rather than the selected elements.
    public var isDraggingGrip: Bool { dragging && dragGrip != nil }

    /// A dashed guide through the grab point along the move, a little beyond both ends.
    func grabGuide(from s: Vec2, by v: Vec2) -> Segment2? {
        guard v.length > ctx.pixel * 2 else { return nil }
        let d = v.normalized
        return Segment2(s - d * ctx.pixel * 24, s + v + d * ctx.pixel * 24)
    }

    /// The point the drag started from (snapping measures guides and increments from it).
    public var dragAnchor: Vec2? {
        guard let g = dragGrip else { return dragStart }
        // An end grip measures from the fixed end, so the element stays square and its length snaps to increments.
        if g.kind == .start || g.kind == .end, let e = ctx.model[g.elementID], let c = ElementOperations.curveOf(e) { return g.kind == .start ? c.end : c.start }
        return g.position
    }

    /// How far a body drag moves the selection. Walls move perpendicular to themselves (joined walls stretch to
    /// follow), as in other BIM tools; everything else follows the pointer.
    func moveVector(_ p: Vec2, from s: Vec2) -> Vec2 {
        let v = p - s
        let sel = ctx.session.selection.ids.compactMap { ctx.model[$0] }
        guard !sel.isEmpty, sel.allSatisfy({ $0.wall != nil }) else { return v }
        let dirs = sel.compactMap { $0.wall?.location.asSegment?.direction }
        guard dirs.count == sel.count, let d = dirs.first, dirs.allSatisfy({ abs($0.cross(d)) < 1e-6 }) else { return v }
        let n = Vec2(-d.y, d.x)
        // A free drag moves in round steps for the zoom; a drag locked onto a snap keeps its exact distance.
        var along = v.dot(n)
        if !pointerSnapped { let step = ctx.lengthIncrement; along = (along / step).rounded() * step }
        return n * along
    }
    /// The pointer of the current drag is held by a snap (see `moveVector`).
    var pointerSnapped = false

    /// Live temporary dimensions while dragging one element: its distances to the nearest references, measured on a
    /// scratch copy of the model with the move (and the joined walls following) already applied.
    func dragDimensions(in moved: BIMModel) -> [TemporaryDimension]? {
        guard let id = ctx.session.selection.single, ctx.isPlan else { return nil }
        let dims = SelectionDimensions.compute(for: id, in: moved, view: ctx.view)
        guard !dims.isEmpty else { return nil }
        // The nearest gap is the one a typed value sets (highlighted, as with a selected element).
        activeDragDimension = dims.filter { $0.role == .offset }.min { $0.value < $1.value }
        return dims.map { TemporaryDimension(from: $0.from, to: $0.to, text: ctx.format($0.value), isAngle: false, isActive: $0 == activeDragDimension) }
    }
    /// The live dimension a typed value applies to while dragging (measured with the move applied).
    var activeDragDimension: SelectionDimension?

    private func reset() {
        dragStart = nil; dragGrip = nil; dragCurrent = nil; dragging = false; preview = ToolPreview(); ctx.snapExclusions = []; activeDragDimension = nil
    }

    // MARK: Typed values while dragging

    /// While dragging the selection, a typed value is the move distance along the drag direction; while dragging an
    /// end grip of a line element, it is the new length measured from the fixed end.
    public var numericLabel: String? {
        guard dragging else { return nil }
        guard let g = dragGrip else { return "Distance" }
        if g.kind == .start || g.kind == .end, let e = ctx.model[g.elementID], ElementOperations.curveOf(e)?.asSegment != nil { return "Length" }
        return nil
    }

    public func numericInput(_ text: String) -> Bool {
        guard dragging, let s = dragStart, let cur = dragCurrent, numericLabel != nil else { return false }
        guard let v = ctx.parse(text) else { return false }
        defer { reset() }
        if let g = dragGrip {
            guard let e = ctx.model[g.elementID], let c = ElementOperations.curveOf(e) else { return false }
            guard v > Tolerance.shortCurve else { message("Enter a length greater than zero."); return true }
            if e.pinned { message("The element is pinned. Unpin it to edit."); return true }
            let fixed = g.kind == .start ? c.end : c.start
            let dir = cur - fixed
            guard dir.length > 1e-9 else { return true }
            let target = fixed + dir.normalized * v
            ctx.session.perform("Drag \(e.category.singularName)") { tx in GripService.apply(g, to: target, in: tx) }
        } else {
            let ids = ctx.session.selection.ids
            let view = ctx.viewID
            let current = moveVector(cur, from: s)
            let move: Vec2
            if let d = activeDragDimension {
                // Sets the highlighted gap: the move so far, plus the change that dimension needs.
                move = current + d.direction * (v - d.value)
            } else {
                guard current.length > 1e-9 else { message("Drag in the direction to move first."); return true }
                move = current.normalized * v
            }
            ctx.session.perform("Move") { tx in try ElementOperations.transform(ids, by: .translation(move), in: tx, viewID: view) }
        }
        if let err = ctx.session.lastError { message(err.message) }
        return true
    }

    // MARK: Temporary dimensions on the selection

    private var dimensionCache: (id: ElementID, view: ElementID, revision: UInt64, dims: [SelectionDimension])?

    /// Temporary dimensions of the single selected element (none while dragging).
    public var selectionDimensions: [SelectionDimension] {
        guard !dragging, let id = ctx.session.selection.single else { return [] }
        let m = ctx.model
        if let c = dimensionCache, c.id == id, c.view == ctx.viewID, c.revision == m.revision { return c.dims }
        let dims = SelectionDimensions.compute(for: id, in: m, view: ctx.view)
        dimensionCache = (id, ctx.viewID, m.revision, dims)
        return dims
    }

    /// Display form of a selection dimension.
    public func temporaryDimension(_ d: SelectionDimension) -> TemporaryDimension {
        TemporaryDimension(from: d.from, to: d.to, text: ctx.format(d.value), isAngle: false, isActive: false)
    }

    /// Applies a value typed into a temporary dimension. Returns false when the text is not a length.
    @discardableResult
    public func setDimension(_ d: SelectionDimension, to text: String) -> Bool {
        guard let v = ctx.parse(text) else { return false }
        let name = ctx.model[d.elementID].map { "Move \($0.category.singularName)" } ?? "Move"
        let view = ctx.viewID
        ctx.session.perform(d.role == .length ? "Change Length" : name) { tx in try SelectionDimensions.apply(d, value: v, in: tx, viewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
        return true
    }

    /// Turns a temporary dimension into a permanent one in this view.
    public func makePermanent(_ d: SelectionDimension) {
        let data = SelectionDimensions.permanent(d, in: ctx.model, offset: ctx.paper(0.006))
        let view = ctx.viewID
        let type = ctx.model.types(for: .dimensions).first?.id
        var created: ElementID?
        ctx.session.perform("Create Dimension") { tx in created = tx.create(.dimensions, data: .dimension(data), typeID: type, ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) } else if created != nil { message("Dimension added. It stays when the selection changes.") }
    }

    // MARK: Controls

    /// Runs a clicked control (flip arrows, bubble box, EQ or padlock).
    public func click(_ control: Grip) {
        guard control.isControl, let name = GripService.actionName(control.kind) else { return }
        ctx.session.perform(name) { tx in GripService.toggle(control, in: tx) }
        if let err = ctx.session.lastError { message(err.message) }
    }

    // MARK: Witness lines

    /// Re-references witness line `index` of a dimension to whatever is under the drop point (the dimension itself is
    /// ignored). Dropping on empty space keeps the snap point, or the raw point, as a fixed reference.
    func moveWitness(_ dimID: ElementID, _ index: Int, to i: ToolInput) {
        guard let dim = ctx.model[dimID]?.dimension, index < dim.references.count else { return }
        var probe = i
        probe.hitCandidates = i.hitCandidates.filter { $0 != dimID }
        probe.hit = probe.hitCandidates.first
        if probe.snap == nil { probe.snap = SnapResult(point: i.point, kind: .nearest, elementIDs: []) }
        let picker = DimensionTool(ctx: ctx, kind: dim.kind)
        guard let (ref, p) = picker.reference(for: probe) else { return }
        if dim.references.enumerated().contains(where: { $0.offset != index && $0.element == ref && ref.elementID != nil }) {
            message("The dimension already measures to that reference.")
            return
        }
        ctx.session.perform("Move Witness Line") { tx in
            tx.update(dimID) { e in
                guard var d = e.dimension else { return }
                d.references[index] = ref
                if index < d.fallbackPoints.count { d.fallbackPoints[index] = p }
                e.dimension = d
            }
        }
    }

    public func escape() -> EscapeResult {
        if dragging { reset(); return .stayInTool }
        if !ctx.session.selection.isEmpty { ctx.session.selection.clear(); return .stayInTool }
        return .exitTool
    }
}
