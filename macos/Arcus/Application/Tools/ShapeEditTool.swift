import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Shape editing of a floor or flat roof (drainage falls).
///
/// Modify Sub Elements: click a boundary vertex or shape point to select it and type its elevation offset; drag an
/// interior point to move it. Add Point: click inside the boundary to add a point at the Elevation in the options bar
/// (clicking a vertex sets that vertex instead). Every edit is its own undoable change.
@MainActor
public final class ShapeEditTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable, Sendable { case modify = "Modify Sub Elements", addPoint = "Add Point" }

    public let elementID: ElementID
    public var mode: Mode
    /// Offset given to new points, and to the selection when changed in the options bar.
    public var elevation = 0.0
    /// Plan position of the selected vertex or point.
    public private(set) var selected: Vec2?
    var dragFrom: Vec2?
    var dragTo: Vec2?

    public init?(ctx: ToolContext, elementID: ElementID, mode: Mode) {
        guard let e = ctx.model[elementID], ShapeEditing.canEdit(e) else { return nil }
        self.elementID = elementID
        self.mode = mode
        super.init(ctx: ctx)
        rebuild()
    }

    public var commandID: CommandID { mode == .modify ? .modifySubElements : .addShapePoint }
    public var title: String { mode.rawValue }
    public var prompt: String {
        switch mode {
        case .modify:
            selected == nil ? "Click a vertex or shape point to select it; drag an interior point to move it."
                : "Type the elevation offset of the selected point (negative lowers it), or click another point."
        case .addPoint: "Click inside the boundary to add a point at the Elevation offset, or click a vertex to set its offset."
        }
    }
    public var numericLabel: String? { mode == .modify && selected == nil ? nil : "Elevation" }
    public var options: [ToolOption] {
        [ToolOption(id: "mode", label: "Edit", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue)),
         ToolOption(id: "elevation", label: "Elevation", kind: .length, value: .double(selectedOffset ?? elevation))]
    }

    var element: Element? { ctx.model[elementID] }
    var profile: Profile2? { element.flatMap(ShapeEditing.profile(of:)) }
    var shapePoints: [ShapePoint] { element.map(ShapeEditing.points(of:)) ?? [] }

    /// Every editable location: boundary vertices (offset 0 unless edited) and interior points.
    public var editablePoints: [ShapePoint] {
        guard let prof = profile else { return [] }
        var out = prof.loops.flatMap(\.points).map { v in shapePoints.first { $0.position.distance(to: v) <= ShapeEditing.snapTolerance } ?? ShapePoint(position: v, offset: 0) }
        for p in shapePoints where !out.contains(where: { $0.position.distance(to: p.position) <= ShapeEditing.snapTolerance }) { out.append(p) }
        return out
    }

    var selectedOffset: Double? {
        guard let s = selected else { return nil }
        return editablePoints.first { $0.position.distance(to: s) <= ShapeEditing.snapTolerance }?.offset
    }

    func nearest(_ p: Vec2) -> ShapePoint? {
        let tol = max(ctx.pixel * 8, ShapeEditing.snapTolerance)
        return editablePoints.filter { $0.position.distance(to: p) <= tol }.min { $0.position.distance(to: p) < $1.position.distance(to: p) }
    }

    func isVertex(_ p: Vec2) -> Bool { profile?.loops.flatMap(\.points).contains { $0.distance(to: p) <= ShapeEditing.snapTolerance } ?? false }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode": if let m = Mode(rawValue: value.textValue ?? "") { mode = m; selected = nil }
        case "elevation":
            guard let d = value.doubleValue, d.isFinite else { return }
            if let s = selected { setOffset(d, at: s) } else { elevation = d }
        default: break
        }
        rebuild()
    }

    /// Writes the point list (vertex entries with zero offset are dropped: they are the unedited default).
    func commit(_ name: String, _ pts: [ShapePoint]) {
        let kept = pts.filter { !(isVertex($0.position) && abs($0.offset) < 1e-9) }
        let id = elementID
        ctx.session.perform(name) { tx in tx.update(id) { ShapeEditing.setPoints(kept, on: &$0) } }
        if let err = ctx.session.lastError { message(err.message) }
    }

    public func setOffset(_ offset: Double, at p: Vec2) {
        var pts = shapePoints
        if let i = pts.firstIndex(where: { $0.position.distance(to: p) <= ShapeEditing.snapTolerance }) { pts[i].offset = offset }
        else { pts.append(ShapePoint(position: p, offset: offset)) }
        commit("Modify Sub Elements", pts)
    }

    public func addPoint(at p: Vec2) {
        guard let prof = profile else { return }
        if let v = prof.loops.flatMap(\.points).first(where: { $0.distance(to: p) <= max(ctx.pixel * 8, ShapeEditing.snapTolerance) }) {
            setOffset(elevation, at: v)
            selected = v
            return
        }
        guard ShapeEditing.isPlaceable(p, in: prof) else { message("Shape points go inside the boundary, away from its edges."); return }
        var pts = shapePoints
        pts.append(ShapePoint(position: p, offset: elevation))
        commit("Add Point", pts)
        selected = p
    }

    public func pointerMoved(_ i: ToolInput) {
        if dragFrom != nil { dragTo = i.point }
        rebuild()
        if mode == .modify, nearest(i.rawPoint) != nil { preview.cursor = .pick }
    }

    public func pointerDown(_ i: ToolInput) {
        switch mode {
        case .addPoint:
            addPoint(at: i.point)
        case .modify:
            if let p = nearest(i.rawPoint) {
                selected = p.position
                if !isVertex(p.position) { dragFrom = p.position }
            } else {
                selected = nil
            }
        }
        rebuild()
    }

    public func pointerDragged(_ i: ToolInput) {
        guard dragFrom != nil else { return }
        dragTo = i.point
        rebuild()
    }

    public func pointerUp(_ i: ToolInput) {
        defer { dragFrom = nil; dragTo = nil; rebuild() }
        guard let from = dragFrom, let to = dragTo, to.distance(to: from) > ShapeEditing.snapTolerance, let prof = profile else { return }
        guard ShapeEditing.isPlaceable(to, in: prof), !isVertex(to) else { message("Shape points stay inside the boundary, away from its edges."); return }
        var pts = shapePoints
        guard let k = pts.firstIndex(where: { $0.position.distance(to: from) <= ShapeEditing.snapTolerance }) else { return }
        pts[k].position = to
        commit("Move Point", pts)
        selected = to
    }

    public func numericInput(_ text: String) -> Bool {
        guard let d = ctx.parse(text), d.isFinite else { return false }
        if let s = selected { setOffset(d, at: s) } else if mode == .addPoint { elevation = d } else { return false }
        rebuild()
        return true
    }

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = .arrow
        preview.highlight = [elementID]
        let size = ctx.pixel * 4
        for p in editablePoints {
            let pos = (dragFrom.map { $0.distance(to: p.position) <= ShapeEditing.snapTolerance } ?? false) ? (dragTo ?? p.position) : p.position
            let isSel = selected.map { $0.distance(to: p.position) <= ShapeEditing.snapTolerance } ?? false
            let r = Rect2(points: [pos - Vec2(size, size), pos + Vec2(size, size)])
            preview.primitives.append(.polyline(r.corners, closed: true, isSel ? ctx.previewHeavy : ctx.previewStroke))
            if abs(p.offset) > 1e-9 || isSel {
                let label = (p.offset > 0 ? "+" : "") + ctx.format(p.offset)
                preview.primitives.append(.text(GText(position: pos + Vec2(size * 1.5, size * 1.5), height: 0.002, string: label)))
            }
        }
        // Ridges and valleys of the edited surface.
        if let e = element, let prof = profile, let s = ShapeEditing.surface(prof, points: ShapeEditing.points(of: e)), !ShapeEditing.points(of: e).isEmpty {
            for t in stride(from: 0, to: s.triangles.count, by: 3) {
                let ids = [s.triangles[t], s.triangles[t + 1], s.triangles[t + 2]]
                for k in 0..<3 where ids.contains(where: { abs(s.offsets[$0]) > 1e-9 }) {
                    preview.primitives.append(ctx.line(s.points[ids[k]], s.points[ids[(k + 1) % 3]]))
                }
            }
        }
    }

    public func escape() -> EscapeResult {
        if dragFrom != nil { dragFrom = nil; dragTo = nil; rebuild(); return .stayInTool }
        if selected != nil { selected = nil; rebuild(); return .stayInTool }
        return .exitTool
    }
}
