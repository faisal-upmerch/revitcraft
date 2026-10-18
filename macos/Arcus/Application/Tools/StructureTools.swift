import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F34: Structure ▸ Truss and Brace. Both are drawn like a beam (two clicks, or a typed length) in a plan view and
// create Structural Framing members, as RevitCraft does (canvas_tools.rs, ToolKind::Brace | ToolKind::Truss).

@MainActor
public final class TrussBraceTool: BaseTool, InteractiveTool {
    public enum Kind: Sendable { case truss, brace }
    public let kind: Kind
    public var commandID: CommandID { kind == .truss ? .truss : .brace }
    public var title: String { kind == .truss ? "Truss" : "Brace" }
    var start: Vec2?
    var current: Vec2?
    /// Truss: height of the top chord above the bottom chord.
    public var depth: Double

    public init(ctx: ToolContext, kind: Kind) {
        self.kind = kind
        depth = StructuralFraming.trussDepth(ctx.model)
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan else { return "\(title) is drawn in plan views." }
        if kind == .brace { return start == nil ? "Click the start of the brace (at this level)." : "Click the end of the brace (at the level above), or type a length." }
        return start == nil ? "Click the start of the truss." : "Click the end of the truss, or type a length."
    }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] {
        kind == .truss ? [ToolOption(id: "depth", label: "Height", kind: .length, value: .double(depth))] : []
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "depth", let d = value.doubleValue, d > 0.1 { depth = d }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let s = start else { return }
        preview.primitives.append(ctx.line(s, i.point, heavy: true))
        if kind == .truss {
            // The panel points of the diagonals, as ticks across the line.
            let len = s.distance(to: i.point)
            if len > Tolerance.shortCurve {
                let panels = max(2, Int((len / depth).rounded()))
                let n = (i.point - s).normalized.perpendicular * ctx.paper(0.0015)
                for k in 0...panels {
                    let q = s + (i.point - s) * (Double(k) / Double(panels))
                    preview.primitives.append(ctx.line(q - n, q + n))
                }
            }
        }
        preview.tempDims = [tempDim(s, i.point), angleDim(s, i.point)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to draw a \(title.lowercased())."); return }
        guard let s = start else { start = i.point; return }
        commit(Segment2(s, i.point))
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let len = ctx.parse(text), len > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        commit(Segment2(s, s + d * len))
        return true
    }

    func commit(_ seg: Segment2) {
        guard seg.length > Tolerance.shortCurve else { return }
        let type = ctx.type(for: .structuralFraming), level = ctx.levelID, depth = depth
        switch kind {
        case .brace:
            // Braces run from this level up to the next.
            let up = StructuralFraming.storeyHeight(above: level, ctx.model)
            ctx.session.perform("Create Brace") { tx in
                StructuralFraming.brace(from: seg.start, to: seg.end, z0: 0, z1: up, type: type, level: level, in: tx)
            }
        case .truss:
            // Trusses stand on this level.
            ctx.session.perform("Create Truss") { tx in
                _ = try StructuralFraming.truss(from: seg.start, to: seg.end, depth: depth, type: type, level: level, in: tx)
            }
        }
        if let e = ctx.session.lastError { message(e.message) } else { start = nil; preview = ToolPreview() }
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}
