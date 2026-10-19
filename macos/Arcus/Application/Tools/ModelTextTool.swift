import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F1: Model Text (RevitCraft `Cmd::ModelText`, `ToolKind::ModelText` in crates/rc-app/src/canvas_tools.rs): type the text
// in Edit Text, then its outline follows the pointer and a click places it on the level; the new text is selected.

/// Places 3D model text on the view's level.
@MainActor
public final class ModelTextTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.modelText
    public let title = "Model Text"
    /// The text to place; nil until Edit Text is answered.
    public var text: String?
    public var size: Double
    public var depth: Double
    public var alignment = ModelTextData.Alignment.left
    /// Direction of the text line (radians); Space turns it by 90°.
    public var rotation = 0.0
    var current: Vec2?

    /// With `text` nil, asks for it with the host's Edit Text dialog; cancelling it leaves the tool.
    public init(ctx: ToolContext, text: String? = nil) {
        let imperial = ctx.units.system == .imperial
        size = imperial ? 0.3048 : 0.3
        depth = imperial ? 0.0254 : 0.05
        super.init(ctx: ctx)
        if let text { self.text = text; return }
        if let ask = ctx.requestText {
            ask("Edit Text", "") { [weak self] s in
                guard let self else { return }
                if let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.text = s } else { self.ctx.toolFinished?() }
            }
        }
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Model text is placed in plan views." }
        return text == nil ? "Type the text in Edit Text." : "Click to place model text."
    }

    public var options: [ToolOption] {
        [ToolOption(id: "size", label: "Text Size", kind: .length, value: .double(size)),
         ToolOption(id: "depth", label: "Depth", kind: .length, value: .double(depth)),
         ToolOption(id: "align", label: "Horizontal Align", kind: .choice(ModelTextData.Alignment.allCases.map(\.rawValue)), value: .text(alignment.rawValue))]
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "size": if let d = value.doubleValue, d > Tolerance.length { size = d } else { message("Text size must be greater than zero.") }
        case "depth": if let d = value.doubleValue, d > Tolerance.length { depth = d } else { message("Depth must be greater than zero.") }
        case "align": alignment = ModelTextData.Alignment(rawValue: value.textValue ?? "") ?? alignment
        default: break
        }
    }

    /// The text as it would be placed at `p`.
    func data(at p: Vec2) -> ModelTextData? {
        guard let text else { return nil }
        return ModelTextData(text: text, position: p, size: size, depth: depth, rotation: rotation, alignment: alignment)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard ctx.isPlan, let t = data(at: i.point) else { return }
        preview.cursor = .crosshair
        preview.primitives = ModelTextGeometry.planContours(t).map { .polyline($0.points, closed: true, ctx.previewStroke) }
        if preview.primitives.isEmpty { preview.primitives = [ctx.line(i.point - Vec2(size, 0), i.point + Vec2(size, 0))] }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to place model text."); return }
        guard let t = data(at: i.point) else { message("Type the text first."); return }
        var placed = t
        placed.sketchPlane = ctx.sketchPlane // S3D2: on the 3D view's work plane
        guard let id = Self.place(placed, level: ctx.levelID, session: ctx.session) else {
            if let e = ctx.session.lastError { message(e.message) }
            return
        }
        // As in RevitCraft, placing ends the tool with the new text selected.
        ctx.session.selection.select([id])
        ctx.toolFinished?()
    }

    public func spaceBar() {
        rotation = Angle.normalize(rotation + .pi / 2)
        if let c = current { var i = ToolInput(point: c, rawPoint: c); i.snap = nil; pointerMoved(i) }
    }

    public func escape() -> EscapeResult { .exitTool }

    /// Creates a Model Text element on `level` (shared by the tool and tests).
    @discardableResult
    public static func place(_ t: ModelTextData, level: ElementID?, session: DocumentSession) -> ElementID? {
        guard !t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var id: ElementID?
        session.perform("Model Text") { tx in id = tx.create(.genericModels, name: "Model Text", data: .modelText(t), levelID: level) }
        return session.lastError == nil ? id : nil
    }
}
