import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F1: the Spline, Ellipse and Partial Ellipse draw modes (RevitCraft `crates/rc-app/src/tools.rs` `draw_step` and
// `preview`, prompts from `canvas_tools.rs`), shared by the line tools (model, detail, room separation and area boundary
// lines) and boundary sketches.

/// The clicks of a spline or ellipse being drawn.
public struct FreeformDraft: Sendable, Equatable {
    public let kind: FreeformCurve.Kind
    public private(set) var points: [Vec2] = []

    public init(kind: FreeformCurve.Kind) { self.kind = kind }

    public var prompt: String {
        let n = points.count
        switch kind {
        case .spline: return n == 0 ? "Click to enter the spline start point." : "Click to add a control point. Click the last point again or press Enter to finish."
        case .ellipse: return ["Click to enter the ellipse center.", "Click to enter the end of the first axis.", "Click to enter the other radius."][min(n, 2)]
        case .partialEllipse: return ["Click to enter the start of the axis.", "Click to enter the end of the axis.", "Click to enter the other radius."][min(n, 2)]
        }
    }

    /// Adds a click. Returns the finished polylines (a spline, a half ellipse, or a full ellipse's two halves), or nil while
    /// the shape needs more clicks. A spline finishes when its last point is clicked again (within `tolerance`).
    public mutating func click(_ p: Vec2, tolerance: Double) -> [[Vec2]]? {
        switch kind {
        case .spline:
            if points.count >= 2, let last = points.last, last.distance(to: p) <= tolerance { return finishSpline().map { [$0] } }
            if points.last.map({ $0.distance(to: p) > Tolerance.shortCurve }) ?? true { points.append(p) }
            return nil
        case .ellipse, .partialEllipse:
            if points.count < 2 {
                if points.last.map({ $0.distance(to: p) > Tolerance.shortCurve }) ?? true { points.append(p) }
                return nil
            }
            let (a, b) = (points[0], points[1])
            let shape = kind == .ellipse ? FreeformCurve.ellipse(center: a, axisEnd: b, through: p) : FreeformCurve.halfEllipse(from: a, to: b, through: p).map { [$0] }
            guard let shape else { return nil } // the other radius can't be zero: keep waiting
            points = []
            return shape
        }
    }

    /// Enter: the spline through the clicks so far (two or more), which ends the draft.
    public mutating func finishSpline() -> [Vec2]? {
        guard kind == .spline, points.count >= 2 else { return nil }
        let pts = FreeformCurve.spline(through: points)
        points = []
        return pts
    }

    /// What the shape would be with the pointer at `c`.
    public func preview(_ c: Vec2) -> [[Vec2]] {
        switch kind {
        case .spline:
            return points.isEmpty ? [] : [FreeformCurve.spline(through: points + [c])]
        case .ellipse, .partialEllipse:
            guard let a = points.first else { return [] }
            guard points.count == 2 else { return [[a, c]] }
            let b = points[1]
            let shape = kind == .ellipse ? FreeformCurve.ellipse(center: a, axisEnd: b, through: c) : FreeformCurve.halfEllipse(from: a, to: b, through: c).map { [$0] }
            return shape ?? [[a, b]]
        }
    }

    /// Clears the clicks (Esc).
    public mutating func reset() { points = [] }
}

extension SketchTool.DrawMode {
    /// F1: the free-form kind a draw mode makes, if any.
    var freeformKind: FreeformCurve.Kind? {
        switch self {
        case .spline: .spline
        case .ellipse: .ellipse
        case .partialEllipse: .partialEllipse
        default: nil
        }
    }
}

// MARK: - Line tools

extension LineTool {
    /// RevitCraft offers the free-form modes for model, detail, room separation and area boundary lines.
    var usesFreeformModes: Bool { [.model, .detail, .roomSeparation, .areaBoundary].contains(kind) }

    static let freeformModes = ["Line", FreeformCurve.Kind.spline.rawValue, FreeformCurve.Kind.ellipse.rawValue, FreeformCurve.Kind.partialEllipse.rawValue]

    var freeformModeOptions: [ToolOption] {
        guard usesFreeformModes else { return [] }
        return [ToolOption(id: "mode", label: "Draw", kind: .choice(Self.freeformModes), value: .text(freeformDraft?.kind.rawValue ?? "Line"))]
    }

    func setFreeformMode(_ name: String?) {
        start = nil; arcMid = nil; preview = ToolPreview()
        freeformDraft = FreeformCurve.Kind(rawValue: name ?? "").map { FreeformDraft(kind: $0) }
    }

    func freeformMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let d = freeformDraft else { return }
        let st = (kind == .detail || kind == .model) ? ctx.model[styleID]?.lineStyle.map { GStroke(weight: $0.weight, color: ctx.previewStroke.color, pattern: $0.pattern) } ?? ctx.previewStroke : ctx.previewStroke
        preview.primitives = d.preview(i.point).map { .polyline($0, closed: false, st) }
        preview.primitives += d.points.map { p in .arc(Arc2(center: p, radius: ctx.pixel * 3, startAngle: 0, sweep: 2 * .pi), ctx.previewStroke) }
    }

    func freeformDown(_ i: ToolInput) {
        guard var d = freeformDraft else { return }
        let done = d.click(i.point, tolerance: max(ctx.pixel * 6, Tolerance.shortCurve))
        freeformDraft = d
        if let done { commitFreeform(done, kind: d.kind) }
        freeformMoved(i)
    }

    /// Enter finishes a spline in progress.
    public func finish() -> Bool {
        guard var d = freeformDraft, let pts = d.finishSpline() else { return false }
        freeformDraft = d
        commitFreeform([pts], kind: d.kind)
        preview = ToolPreview()
        return true
    }

    /// Each polyline becomes one line (its curve the chord).
    func commitFreeform(_ shapes: [[Vec2]], kind k: FreeformCurve.Kind) {
        for pts in shapes {
            let f = FreeformCurve(kind: k, points: pts)
            guard let chord = f.chord else { message("A spline that ends where it starts can't be drawn as one line; end it elsewhere."); continue }
            commit(chord, freeform: f)
        }
    }
}

// MARK: - Sketches

extension SketchTool {
    var freeformPrompt: String? { drawMode.freeformKind.map { k in (freeformDraft?.kind == k ? freeformDraft! : FreeformDraft(kind: k)).prompt } }

    /// The draft for the current draw mode (a fresh one when the mode changed).
    var currentDraft: FreeformDraft? {
        guard let k = drawMode.freeformKind else { return nil }
        return freeformDraft?.kind == k ? freeformDraft : FreeformDraft(kind: k)
    }

    func previewFreeform(at c: Vec2) -> Bool {
        guard let d = currentDraft else { return false }
        for pts in d.preview(c) { preview.primitives.append(.polyline(pts, closed: false, ctx.previewHeavy)) }
        return true
    }

    func clickFreeform(at p: Vec2) -> Bool {
        guard var d = currentDraft else { freeformDraft = nil; return false }
        let done = d.click(p, tolerance: max(ctx.pixel * 6, Tolerance.shortCurve))
        freeformDraft = d
        for pts in done ?? [] { addFreeform(pts, kind: d.kind) }
        return true
    }

    /// Boundary lines from a polyline (the Options Bar Offset doesn't apply: offsetting each segment would open gaps).
    func addFreeform(_ pts: [Vec2], kind: FreeformCurve.Kind) {
        for s in FreeformCurve(kind: kind, points: pts).segments { add(.line(s)) }
    }

    /// Finish (or Enter) first turns a spline in progress into boundary lines.
    func commitPendingSpline() {
        guard var d = freeformDraft, let pts = d.finishSpline() else { return }
        freeformDraft = d
        addFreeform(pts, kind: d.kind)
    }

    var hasFreeformDraft: Bool { !(freeformDraft?.points.isEmpty ?? true) }
}
