import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// BL-SITE (ARCUS-070): Toposolid sketch and Sub-Divide tools.

/// Sketches a toposolid boundary (lines, rectangle or picked lines) in a plan view; Finish creates a flat toposolid at
/// the level plus the Height Offset, with the type chosen in the type selector. Shape it afterwards with Edit Surface
/// (add points, set elevations, split lines) or Excavate.
@MainActor
public final class ToposolidSketchTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable { case line = "Line", rectangle = "Rectangle", pick = "Pick Lines" }
    public let commandID: CommandID
    public let title: String
    public var mode: Mode = .line
    /// Top of the new toposolid above its level.
    public var heightOffset = 0.0
    /// Sub-Divide: the host toposolid (nil = create a toposolid).
    public let hostID: ElementID?
    /// Sub-Divide: thickness above the host (nil = the type's thickness).
    public var subdivisionHeight: Double?
    var points: [Vec2] = []
    var picked: [Curve2] = []
    var current: Vec2?

    public init(ctx: ToolContext, subdivide host: ElementID? = nil) {
        hostID = host
        commandID = host == nil ? .toposolid : .subdivideToposolid
        title = host == nil ? "Toposolid" : "Sub-Division"
        super.init(ctx: ctx)
    }

    public var isSketchMode: Bool { true }
    public var snapFrom: Vec2? { mode == .line ? points.last : nil }
    public var prompt: String {
        switch mode {
        case .line: return points.isEmpty ? "Click the first corner of the \(hostID == nil ? "toposolid" : "sub-division") boundary." : "Click the next corner, then Finish (Return) to close the boundary."
        case .rectangle: return points.isEmpty ? "Click the first corner." : "Click the opposite corner."
        case .pick: return "Click lines, property lines, walls or edges forming a closed loop, then Finish (Return)."
        }
    }
    public var numericLabel: String? { mode == .line && !points.isEmpty ? "Length" : nil }

    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Draw", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue))]
        if hostID == nil {
            o.append(ToolOption(id: "offset", label: "Height Offset", kind: .length, value: .double(heightOffset)))
        } else {
            o.append(ToolOption(id: "height", label: "Height", kind: .length, value: .double(subdivisionHeight ?? typeThickness)))
        }
        return o
    }
    var typeThickness: Double {
        let t = ctx.currentTypes[.topography].flatMap { ctx.model[$0]?.typeData?.assembly?.totalThickness }
        return t ?? 0.1
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode": if let m = Mode(rawValue: value.textValue ?? "") { mode = m; points = []; picked = [] }
        case "offset": if let d = value.doubleValue, d.isFinite { heightOffset = d }
        case "height": if let d = value.doubleValue, d.isFinite, abs(d) >= 0.001 { subdivisionHeight = d }
        default: break
        }
        refresh()
    }

    /// The closed boundary drawn so far (nil until it encloses an area).
    var boundary: Polygon2? {
        switch mode {
        case .line:
            let pts = points + (current.map { [$0] } ?? [])
            return pts.count >= 3 ? Polygon2(pts) : nil
        case .rectangle:
            guard let a = points.first, let b = current, abs(a.x - b.x) > Tolerance.length, abs(a.y - b.y) > Tolerance.length else { return nil }
            return .rectangle(Rect2(points: [a, b]))
        case .pick:
            guard let loop = Sketch.orderLoop(picked) else { return nil }
            let poly = Polygon2(loop.flatMap { Array($0.tessellate(chordTolerance: 0.05).dropLast()) })
            return poly.count >= 3 ? poly : nil
        }
    }

    func refresh() {
        preview = ToolPreview()
        if let h = hostID { preview.highlight = [h] }
        switch mode {
        case .line:
            let pts = points + (current.map { [$0] } ?? [])
            if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: pts.count >= 3, ctx.previewHeavy)) }
        case .rectangle:
            if let b = boundary { preview.primitives.append(.polyline(b.points, closed: true, ctx.previewHeavy)) }
        case .pick:
            for c in picked { preview.primitives.append(.polyline(c.tessellate(chordTolerance: 0.05), closed: false, ctx.previewHeavy)) }
        }
    }

    public func pointerMoved(_ i: ToolInput) { current = i.point; refresh() }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to sketch a \(hostID == nil ? "toposolid" : "sub-division")."); return }
        switch mode {
        case .line:
            if let f = points.first, points.count >= 3, f.distance(to: i.point) < ctx.pixel * 8 { current = nil; _ = finish(); return }
            points.append(i.point)
        case .rectangle:
            if points.isEmpty { points = [i.point]; return }
            current = i.point
            if boundary != nil { _ = finish() }
        case .pick:
            if let (seg, _) = ctx.snapIndex.nearestSegment(i.point, radius: ctx.pixel * 8) {
                let c = Curve2.line(seg)
                if let k = picked.firstIndex(where: { $0.start.isAlmostEqual(c.start) && $0.end.isAlmostEqual(c.end) }) { picked.remove(at: k) } else { picked.append(c) }
            } else { message("Click a line or an edge.") }
        }
        refresh()
    }

    public func numericInput(_ text: String) -> Bool {
        guard mode == .line, let last = points.last, let c = current, let d = ctx.parse(text), d > Tolerance.length else { return false }
        points.append(last + (c - last).normalized * d)
        refresh()
        return true
    }

    public func finish() -> Bool {
        if mode == .line { current = nil }
        guard let b = boundary else { message(mode == .pick ? "The picked lines don't form a closed loop." : "Draw at least three corners."); return false }
        let level = ctx.levelID, z = ctx.levelElevation + heightOffset
        let type = ctx.currentTypes[.topography].flatMap { ctx.model[$0]?.typeData?.systemFamily == .toposolid ? $0 : nil }
        if let h = hostID {
            let height = subdivisionHeight
            let subType = type.flatMap { ctx.model[$0]?.typeData?.params[ToposolidTypes.kindKey]?.textValue == "subdivision" ? $0 : nil }
            ctx.session.perform("Sub-Divide") { tx in try ToposolidOperations.subdivide(h, boundary: b, typeID: subType, height: height, in: tx) }
        } else {
            let solidType = type.flatMap { ctx.model[$0]?.typeData?.params[ToposolidTypes.kindKey] == nil ? $0 : nil }
            ctx.session.perform("Create Toposolid") { tx in try ToposolidOperations.create(outline: b, elevation: z, typeID: solidType, levelID: level, in: tx) }
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        points = []; picked = []
        refresh()
        ctx.toolFinished?()
        return true
    }

    public func cancelSketch() { points = []; picked = []; ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); refresh(); return .stayInTool }
        if !picked.isEmpty { picked.removeLast(); refresh(); return .stayInTool }
        return .exitTool
    }
}
