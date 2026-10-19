import Foundation
import ArcusGeometry
import ArcusDomain

/// STAIR: Edit Path of a railing on a stair (Revit's "Modify | Railings ▸ Edit Path"): sketch the railing's new plan
/// path as a chain of lines; Finish replaces the stair edge with it, the railing still rising with the stair. The
/// current path shows dashed while sketching. Reset Railing puts it back on the stair's edge.
@MainActor
public final class StairRailingPathTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.stairRailingEditPath
    public let title = "Railing Path"
    public var isSketchMode: Bool { true }
    public let railingID: ElementID
    public private(set) var points: [Vec2] = []
    var current: Vec2?

    public init?(ctx: ToolContext, railingID: ElementID) {
        guard ctx.model[railingID]?.railing?.followsHost == true else { return nil }
        self.railingID = railingID
        super.init(ctx: ctx)
        rebuild()
    }

    public var prompt: String { points.isEmpty ? "Click the start of the railing's new path." : "Click the next point; Finish (↩) applies the path." }
    public var snapFrom: Vec2? { points.last }
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public var numericLabel: String? { points.isEmpty ? nil : "Length" }

    public func pointerMoved(_ i: ToolInput) { current = i.point; rebuild() }

    public func pointerDown(_ i: ToolInput) {
        if let last = points.last, last.distance(to: i.point) < 0.01 { if i.clickCount >= 2 { _ = finish() }; return }
        points.append(i.point)
        rebuild()
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = points.last, let c = current, let len = ctx.parse(text), len > 0.01 else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        points.append(s + d * len)
        rebuild()
        return true
    }

    func rebuild() {
        preview = ToolPreview()
        preview.highlight = [railingID]
        let old = RailingGeometry.path(ctx.model[railingID]!, ctx.model).map(\.xy)
        if old.count >= 2 { preview.primitives.append(.polyline(old, closed: false, GStroke(weight: 1, color: ctx.previewStroke.color, pattern: .hidden))) }
        if points.count >= 2 { preview.primitives.append(.polyline(points, closed: false, ctx.previewHeavy)) }
        if let last = points.last, let c = current {
            preview.primitives.append(ctx.line(last, c, heavy: true))
            preview.tempDims = [tempDim(last, c)]
        }
    }

    public func finish() -> Bool {
        guard points.count >= 2 else { message("Sketch at least one line of the railing's path."); return false }
        let path = points
        ctx.session.perform("Edit Railing Path") { tx in tx.update(railingID) { $0.railing?.editedHostPath = path } }
        if let err = ctx.session.lastError { message(err.message); return false }
        ctx.toolFinished?()
        return true
    }

    public func cancelSketch() { ctx.toolFinished?() }

    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); rebuild() }
        return .stayInTool
    }
}
