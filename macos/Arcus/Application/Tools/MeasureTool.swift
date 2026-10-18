import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Measure: reads distances without changing the model. "Between two references" measures from point to point (in
/// a chain with a running total); "along an element" measures the length of a wall, line or beam, or the perimeter
/// of a floor, roof, ceiling or region. Results stay on screen as temporary dimensions and in the status bar.
@MainActor
public final class MeasureTool: BaseTool, InteractiveTool {
    public enum Mode: Sendable { case between, along }
    public let mode: Mode
    public var commandID: CommandID { mode == .between ? .measureBetween : .measureAlong }
    public var title: String { mode == .between ? "Measure Between Two References" : "Measure Along an Element" }
    /// Between: keep measuring from the last point and add to a total.
    public var chain = false

    /// Picked points of the current measurement (between).
    var points: [Vec2] = []
    /// Measured elements and their lengths (along).
    var measured: [(ElementID, [Curve2])] = []
    /// The last result, shown in the prompt.
    public private(set) var result: String?

    public init(ctx: ToolContext, mode: Mode) { self.mode = mode; super.init(ctx: ctx) }

    public var prompt: String {
        let head: String
        switch mode {
        case .between: head = points.isEmpty ? "Click the first point to measure from." : "Click the next point."
        case .along: head = "Click a wall, line, beam or the edge of a floor, roof or region. Shift-click adds to the total."
        }
        return result.map { "\($0) — \(head)" } ?? head
    }
    public var options: [ToolOption] {
        mode == .between ? [ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain))] : []
    }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "chain" { chain = value.boolValue ?? false } }
    public var snapFrom: Vec2? { points.last }

    /// Total of the chained segments (between) or measured elements (along), in model units.
    public var total: Double {
        switch mode {
        case .between: zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        case .along: measured.reduce(0) { $0 + $1.1.reduce(0) { $0 + $1.length } }
        }
    }

    // MARK: Between two references

    func describe(_ a: Vec2, _ b: Vec2) -> String {
        let d = b - a
        let angle = Angle.degrees(Angle.normalize(d.angle))
        var s = "Length \(ctx.format(a.distance(to: b)))  ·  Angle \(String(format: "%.2f°", angle))  ·  ΔX \(ctx.format(abs(d.x)))  ·  ΔY \(ctx.format(abs(d.y)))"
        if points.count > 2 { s += "  ·  Total \(ctx.format(total))" }
        return s
    }

    func showPoints(cursor: Vec2?) {
        preview = ToolPreview()
        for (a, b) in zip(points, points.dropFirst()) {
            preview.primitives.append(ctx.line(a, b, heavy: true))
            preview.tempDims.append(tempDim(a, b, active: false))
        }
        if let last = points.last, let c = cursor, last.distance(to: c) > Tolerance.length {
            preview.primitives.append(ctx.line(last, c))
            preview.tempDims.append(tempDim(last, c))
        }
    }

    // MARK: Along an element

    /// The curves measured for an element: its location curve, or its boundary.
    func curves(of e: Element) -> [Curve2]? {
        // Plan geometry reads true only in plan views; view-owned elements are drawn in their own view's coordinates.
        guard ctx.isPlan || e.ownerViewID == ctx.viewID else { return nil }
        if let c = ElementOperations.curveOf(e) { return [c] }
        switch e.data {
        case .slab(let s): return s.boundary.allCurves
        case .roof(let r): return r.footprint.allCurves
        case .filledRegion(let f): return f.boundary.allCurves
        case .insulation(let i): return [.line(i.line)]
        default: return nil
        }
    }
    func pickElement(_ i: ToolInput) -> (Element, [Curve2])? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            if let e = ctx.model[id], let cs = curves(of: e), !cs.isEmpty { return (e, cs) }
        }
        return nil
    }
    func showMeasured(hover: [Curve2]) {
        preview = ToolPreview()
        for (_, cs) in measured {
            for c in cs {
                preview.primitives.append(.polyline(c.tessellate(chordTolerance: 0.01), closed: false, ctx.previewHeavy))
                if let s = c.asSegment { preview.tempDims.append(tempDim(s.start, s.end, active: false)) }
            }
        }
        for c in hover { preview.primitives.append(.polyline(c.tessellate(chordTolerance: 0.01), closed: false, ctx.previewStroke)) }
    }

    // MARK: Input

    public func pointerMoved(_ i: ToolInput) {
        switch mode {
        case .between:
            showPoints(cursor: points.isEmpty ? nil : i.point)
            preview.cursor = .crosshair
        case .along:
            let hover = pickElement(i)
            showMeasured(hover: hover?.1 ?? [])
            preview.cursor = hover == nil ? .notAllowed : .pick
            if let (e, _) = hover { preview.highlight = [e.id] }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        switch mode {
        case .between:
            if points.count >= 2 && !chain { points = [] }
            points.append(i.point)
            guard points.count >= 2 else { showPoints(cursor: nil); return }
            let text = describe(points[points.count - 2], points[points.count - 1])
            result = text
            message(text)
            showPoints(cursor: nil)
        case .along:
            guard let (e, cs) = pickElement(i) else { message("Click a wall, line, beam or the edge of a floor, roof or region."); return }
            if !i.shift { measured = [] }
            if !measured.contains(where: { $0.0 == e.id }) { measured.append((e.id, cs)) }
            let own = cs.reduce(0) { $0 + $1.length }
            let label = cs.count > 1 ? "Perimeter" : "Length"
            var text = "\(e.category.singularName) \(label.lowercased()): \(ctx.format(own))"
            if measured.count > 1 { text += "  ·  Total of \(measured.count): \(ctx.format(total))" }
            result = text
            message(text)
            showMeasured(hover: [])
        }
    }

    public func escape() -> EscapeResult {
        if !points.isEmpty || !measured.isEmpty {
            points = []; measured = []; result = nil; preview = ToolPreview()
            return .stayInTool
        }
        return .exitTool
    }
}
