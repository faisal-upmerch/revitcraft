import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// STAIR: the stair tools are in StairTool.swift (Create Stair and Edit Stairs).

// MARK: - Ramps

/// Draws a ramp run: click the bottom of the run, click to turn at a landing, and Finish (↩ or double-click) at the
/// top. The options bar sets width, top level and railings; the temporary dimension compares the sloped run drawn so
/// far with the run the type's maximum slope needs. A short (too steep) ramp still commits and is reported in Model
/// Health.
@MainActor
public final class RampTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.ramp
    public let title = "Ramp"
    public var isSketchMode: Bool { true }
    public private(set) var points: [Vec2] = []
    var current: Vec2?
    public var width = 1.2
    public var topLevelID: ElementID?
    public var railings = true

    public override init(ctx: ToolContext) {
        super.init(ctx: ctx)
        topLevelID = ctx.model.levelAbove(ctx.levelID)?.id
    }

    public var prompt: String {
        points.isEmpty ? "Click the bottom of the ramp run (centerline)."
            : "Click to end the run or to turn at a landing; type a length. Finish (↩ or double-click) creates the ramp."
    }
    public var numericLabel: String? { points.isEmpty ? nil : "Length" }
    public var snapFrom: Vec2? { points.last }
    public var options: [ToolOption] {
        [ToolOption(id: "width", label: "Width", kind: .length, value: .double(width)),
         ToolOption(id: "top", label: "Top Level", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(ctx.model[topLevelID]?.name ?? "Unconnected")),
         ToolOption(id: "railings", label: "Railings", kind: .bool, value: .bool(railings))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "width":
            if let d = value.doubleValue, d >= RampGeometry.minimumWidth { width = d } else { message("A ramp must be at least 600 mm wide.") }
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        case "railings": railings = value.boolValue ?? true
        default: break
        }
        rebuild()
    }

    /// The ramp as it would be created from the clicked points (plus `extra`, the pointer position).
    func probe(_ extra: Vec2? = nil) -> Element? {
        var path = points
        if let p = extra, path.last.map({ $0.distance(to: p) > 0.05 }) ?? false { path.append(p) }
        guard path.count >= 2 else { return nil }
        let rd = RampData(path: path, width: width, topLevelID: topLevelID)
        return Element(id: ElementID(UInt64.max - 3), category: .ramps, data: .ramp(rd), typeID: ctx.type(for: .ramps), levelID: ctx.levelID)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        for k in 0..<max(0, points.count - 1) { preview.primitives.append(ctx.line(points[k], points[k + 1], heavy: true)) }
        guard let last = points.last, let c = current else { return }
        preview.primitives.append(ctx.line(last, c, heavy: true))
        guard let e = probe(c) else { return }
        if let l = RampGeometry.layout(e, ctx.model) {
            for p in l.pieces { preview.primitives.append(.polyline(p.polygon.points, closed: true, p.isLanding ? ctx.previewStroke : ctx.previewHeavy)) }
            let status = l.isTooSteep
                ? "\(ctx.format(l.slopedLength)) of \(ctx.format(l.requiredLength)) run, \(ctx.format(l.requiredLength - l.slopedLength)) to go"
                : "\(ctx.format(l.slopedLength)) run, slope 1:\(String(format: "%.1f", 1 / l.slope))"
            preview.tempDims = [TemporaryDimension(from: last, to: c, text: status, isAngle: false, isActive: true)]
        } else {
            preview.tempDims = [tempDim(last, c)]
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Draw ramps in a plan view."); return }
        if i.clickCount >= 2, points.count >= 2 { _ = finish(); return }
        if let last = points.last, last.distance(to: i.point) < 0.05 { return }
        points.append(i.point)
        rebuild()
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = points.last, let c = current, let len = ctx.parse(text), len > 0.05 else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        points.append(s + d * len)
        current = points.last
        rebuild()
        return true
    }

    public func finish() -> Bool {
        guard points.count >= 2, let e = probe(), let rd = e.ramp else { message("Click at least two points to draw a ramp run."); return false }
        if let reason = RampGeometry.invalidReason(e, ctx.model) { message(reason); return false }
        let level = ctx.levelID
        let existingType = ctx.type(for: .ramps)
        let concrete = ctx.model.material(named: "Concrete, Cast-in-Place")?.id
        let railType = railings ? ctx.model.types(for: .railings).first?.id : nil
        ctx.session.perform("Create Ramp") { tx in
            let type = existingType ?? tx.create(.elementTypes, name: RampGeometry.defaultTypeName, data: .type(RampGeometry.defaultType(material: concrete)))
            let rid = tx.create(.ramps, data: .ramp(rd), typeID: type, levelID: level)
            if let rt = railType {
                for left in [true, false] {
                    var rail = RailingData(path: [])
                    rail.followsHost = true; rail.hostSideLeft = left
                    tx.create(.railings, data: .railing(rail), typeID: rt, levelID: level, hostID: rid)
                }
            }
        }
        if let err = ctx.session.lastError { message(err.message); return false }
        for w in ctx.session.lastWarnings { message(w.message) }
        points = []
        preview = ToolPreview()
        ctx.toolFinished?()
        return true
    }

    public func cancelSketch() {
        points = []
        preview = ToolPreview()
        ctx.toolFinished?()
    }

    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); rebuild(); return .stayInTool }
        return .exitTool
    }
}
