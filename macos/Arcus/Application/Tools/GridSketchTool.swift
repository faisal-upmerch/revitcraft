import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// F2: Grid ▸ Multi-Segment (RevitCraft `SketchKind::Grid`, `add_grid_path`): sketch mode for a grid of several
/// connected straight segments. Clicks add the bend points (a typed number sets the next segment's length); Finish
/// creates one grid through the chain, Cancel discards it. With `editing`, the sketch edits that grid's path.
@MainActor
public final class GridSketchTool: BaseTool, InteractiveTool {
    public let commandID: CommandID
    public let editingID: ElementID?
    /// The chain's points so far.
    public private(set) var points: [Vec2] = []
    var current: Vec2?
    public var name: String

    public init(ctx: ToolContext, editing: ElementID? = nil) {
        self.editingID = editing
        self.commandID = editing == nil ? .gridMultiSegment : .editBoundary
        let existing = editing.flatMap { ctx.model[$0] }
        name = existing?.name ?? GridNaming.next(after: ctx.model.elements(.grids).map(\.name))
        super.init(ctx: ctx)
        if let g = existing?.grid { points = g.polyline }
    }

    public var title: String { "Grid" }
    public var isSketchMode: Bool { true }
    public var prompt: String {
        points.isEmpty ? "Click to start grid \(name). Sketch its segments as one connected chain; Finish (↩) creates it."
            : "Click the next bend or the end, or type a length. Finish (↩) creates the grid; Cancel discards it."
    }
    public var numericLabel: String? { points.isEmpty ? nil : "Length" }
    public var snapFrom: Vec2? { points.last }
    public var options: [ToolOption] {
        [ToolOption(id: "mode", label: "Draw", kind: .choice(["Line"]), value: .text("Line")),
         ToolOption(id: "name", label: "Name", kind: .choice([name]), value: .text(name))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "name", let s = value.textValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty { name = s }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = .crosshair
        if points.count >= 2 { preview.primitives.append(.polyline(points, closed: false, ctx.previewHeavy)) }
        guard let last = points.last, let c = current else { return }
        preview.primitives.append(ctx.line(last, c, heavy: true))
        let previous = points.count >= 2 ? (points[points.count - 1] - points[points.count - 2]).normalized : nil
        preview.tempDims = [tempDim(last, c), angleDim(last, c, reference: previous)]
    }

    public func pointerDown(_ i: ToolInput) {
        add(i.point)
    }

    func add(_ p: Vec2) {
        if let last = points.last, last.distance(to: p) <= Tolerance.shortCurve { return }
        points.append(p)
        rebuild()
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = points.last, let c = current, let len = ctx.parse(text), len > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        add(s + d * len)
        return true
    }

    /// Esc drops the last point (the sketch stays open until Finish or Cancel).
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); rebuild() }
        return .stayInTool
    }

    public func cancelSketch() {
        points = []
        ctx.toolFinished?()
    }

    public func finish() -> Bool {
        guard ctx.isPlan || editingID != nil else { message("Sketch grids in a plan view."); return false }
        guard let g = GridData(path: points) else { message("Sketch the grid's segments as one connected chain."); return false }
        guard g.pathLength > 0.1 else { message("The grid is too short."); return false }
        let name = name
        var created: ElementID?
        if let id = editingID {
            ctx.session.perform("Edit Grid Sketch") { tx in
                tx.update(id) { e in
                    guard var old = e.grid else { return }
                    old.curve = g.curve; old.vertices = g.vertices
                    old.viewExtents = nil // the model ends moved: per-view 2D ends no longer apply
                    e.grid = old
                }
            }
        } else {
            ctx.session.perform("Create Grid") { tx in created = tx.create(.grids, name: name, data: .grid(g)) }
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        if let id = created ?? editingID { ctx.session.selection.select([id]) }
        points = []
        ctx.toolFinished?()
        return true
    }
}
