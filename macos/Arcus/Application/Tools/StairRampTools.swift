import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Stairs

@MainActor
public final class StairTool: BaseTool, InteractiveTool {
    public let shape: StairShape
    public var commandID: CommandID { shape == .straight ? .stairStraight : shape == .lShaped ? .stairL : .stairU }
    public var title: String { "Stair – \(shape.rawValue)" }
    var start: Vec2?
    public var width = 1.1
    public var topLevelID: ElementID?
    public var turnsLeft = true
    public var railings = true
    /// F2: Connect Levels: the stair repeats up to this level (multistory).
    public var multistoryTopLevelID: ElementID?

    public init(ctx: ToolContext, shape: StairShape) {
        self.shape = shape
        super.init(ctx: ctx)
        topLevelID = ctx.model.levelAbove(ctx.levelID)?.id
    }
    public var prompt: String { start == nil ? "Click the bottom of the first run (centerline)." : "Click to set the run direction." }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] {
        var o = [ToolOption(id: "width", label: "Run Width", kind: .length, value: .double(width)),
                 ToolOption(id: "top", label: "Top Level", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(ctx.model[topLevelID]?.name ?? "Unconnected")),
                 ToolOption(id: "railings", label: "Railings", kind: .bool, value: .bool(railings))]
        if shape != .straight { o.append(ToolOption(id: "left", label: "Turn Left", kind: .bool, value: .bool(turnsLeft))) }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "width": if let d = value.doubleValue, d >= 0.6 { width = d }
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        case "left": turnsLeft = value.boolValue ?? true
        case "railings": railings = value.boolValue ?? true
        default: break
        }
    }

    func probe(_ dirPoint: Vec2) -> Element? {
        guard let s = start, let t = ctx.type(for: .stairs), dirPoint.distance(to: s) > 0.05 else { return nil }
        var sd = StairData(shape: shape, origin: s, direction: (dirPoint - s).angle, width: width, topLevelID: topLevelID)
        sd.turnsLeft = turnsLeft
        sd.multistoryTopLevelID = multistoryTopLevelID // F2
        return Element(id: ElementID(UInt64.max - 2), category: .stairs, data: .stair(sd), typeID: t, levelID: ctx.levelID)
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let e = probe(i.point), let l = StairGeometry.layout(e, ctx.model) else { return }
        for r in l.runs { preview.primitives.append(.polyline(l.runRect(r).points, closed: true, ctx.previewHeavy)) }
        for land in l.landings { preview.primitives.append(.polyline(land.polygon.points, closed: true, ctx.previewStroke)) }
        let lines = StairGeometry.planLines(e, ctx.model, cutZ: .infinity)
        for s in lines.treads { preview.primitives.append(ctx.line(s.start, s.end)) }
        preview.tempDims = [TemporaryDimension(from: start!, to: i.point, text: "\(l.riserCount) risers, \(ctx.format(l.riserHeight)) each", isAngle: false, isActive: false)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Place stairs in a plan view."); return }
        guard start != nil else { start = i.point; return }
        guard let e = probe(i.point), let sd = e.stair, let t = e.typeID else { return }
        let railType = railings ? ctx.model.types(for: .railings).first?.id : nil
        ctx.session.perform("Create Stair") { tx in
            let sid = tx.create(.stairs, data: .stair(sd), typeID: t, levelID: ctx.levelID)
            if let rt = railType {
                for left in [true, false] {
                    var rd = RailingData(path: [])
                    rd.followsHost = true; rd.hostSideLeft = left
                    tx.create(.railings, data: .railing(rd), typeID: rt, levelID: ctx.levelID, hostID: sid)
                }
            }
        }
        if let err = ctx.session.lastError { message(err.message) }
        for w in ctx.session.lastWarnings { message(w.message) }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}


// MARK: - Ramps

/// Draws a ramp run: click the bottom of the run, click to turn at a landing, and Finish (↩ or double-click) at the
/// top. The options bar sets width, top level and railings; the temporary dimension compares the sloped run drawn so
/// far with the run the type's maximum slope needs. A short (too steep) ramp still commits and is reported in Model
/// Health.
@MainActor
public final class RampTool: BaseTool, InteractiveTool {
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

// MARK: - Edit Stair

/// Edits a placed stair in place: drag the start, the run direction, the run width or (L and U stairs) the landing to
/// move risers between the flights. The options bar edits shape, width, turn, riser counts. Finish commits one
/// undoable change; Cancel leaves the stair untouched.
@MainActor
public final class EditStairTool: BaseTool, InteractiveTool {
    public enum Handle: String, Sendable, CaseIterable { case origin, direction, widthLeft, widthRight, landing }

    public let commandID = CommandID.editStair
    public let title = "Edit Stair"
    public var isSketchMode: Bool { true }
    public let stairID: ElementID
    public private(set) var draft: StairData
    var dragging: Handle?
    var hover: Handle?

    public init?(ctx: ToolContext, stairID: ElementID) {
        guard let s = ctx.model[stairID]?.stair else { return nil }
        self.stairID = stairID
        self.draft = s
        super.init(ctx: ctx)
        rebuild()
    }

    public var prompt: String {
        switch dragging ?? hover {
        case .origin?: "Drag to move the start of the stair."
        case .direction?: "Drag to turn the run direction."
        case .widthLeft?, .widthRight?: "Drag to change the run width."
        case .landing?: "Drag along the first run to move risers between the flights."
        case nil: "Drag a handle to edit the stair, or change values in the options bar. Finish (↩) applies; Cancel discards."
        }
    }

    public var options: [ToolOption] {
        var o = [ToolOption(id: "shape", label: "Shape", kind: .choice(StairShape.allCases.map(\.rawValue)), value: .text(draft.shape.rawValue)),
                 ToolOption(id: "width", label: "Run Width", kind: .length, value: .double(draft.width)),
                 ToolOption(id: "risers", label: "Risers", kind: .integer, value: .int(layout()?.riserCount ?? draft.desiredRiserCount ?? 0))]
        if draft.shape != .straight {
            o.append(ToolOption(id: "left", label: "Turn Left", kind: .bool, value: .bool(draft.turnsLeft)))
            o.append(ToolOption(id: "firstRun", label: "First Run Risers", kind: .integer, value: .int(firstRunRisers)))
        }
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "shape": if let s = StairShape(rawValue: value.textValue ?? "") { draft.shape = s }
        case "width":
            if let w = value.doubleValue, w >= 0.6 { draft.width = w } else { message("A stair run must be at least 600 mm wide.") }
        case "risers":
            if let n = value.intValue, n >= 2, n <= 60 { draft.desiredRiserCount = n } else { message("Risers must be between 2 and 60.") }
        case "left": draft.turnsLeft = value.boolValue ?? true
        case "firstRun": if let n = value.intValue { setFirstRun(n) }
        default: break
        }
        rebuild()
    }

    var probe: Element? {
        guard var e = ctx.model[stairID] else { return nil }
        e.data = .stair(draft)
        return e
    }
    func layout() -> StairLayout? { probe.flatMap { StairGeometry.layout($0, ctx.model) } }

    /// Risers in the first flight of an L or U stair (the layout's split).
    var firstRunRisers: Int { layout()?.runs.first?.risers ?? draft.firstRunRisers ?? 0 }

    func setFirstRun(_ n: Int) {
        guard let total = layout()?.riserCount, total >= 4 else { return }
        draft.firstRunRisers = min(max(2, n), total - 2)
    }

    /// Handle positions for the current draft.
    public func handles() -> [(Handle, Vec2)] {
        guard let l = layout(), let run = l.runs.first else { return [] }
        let dir = run.direction, side = dir.perpendicular
        let runEnd = run.start + dir * (Double(max(run.risers - 1, 0)) * l.treadDepth)
        let mid = run.start.lerp(to: runEnd, t: 0.5)
        var out: [(Handle, Vec2)] = [(.origin, draft.origin),
                                     (.direction, runEnd + dir * max(0.3, l.treadDepth)),
                                     (.widthLeft, mid + side * (draft.width / 2)),
                                     (.widthRight, mid - side * (draft.width / 2))]
        if draft.shape != .straight, let land = l.landings.first { out.append((.landing, land.polygon.centroid)) }
        return out
    }

    func handle(at p: Vec2) -> Handle? {
        let tol = ctx.pixel * 8
        return handles().filter { $0.1.distance(to: p) <= tol }.min { $0.1.distance(to: p) < $1.1.distance(to: p) }?.0
    }

    public func pointerMoved(_ i: ToolInput) {
        if dragging == nil { hover = handle(at: i.rawPoint) }
        rebuild()
    }

    public func pointerDown(_ i: ToolInput) {
        dragging = handle(at: i.rawPoint)
        rebuild()
    }

    public func pointerDragged(_ i: ToolInput) {
        guard let h = dragging, let l = layout(), let run = l.runs.first else { return }
        let p = i.point
        let dir = run.direction, side = dir.perpendicular
        switch h {
        case .origin:
            draft.origin = p
        case .direction:
            let v = p - draft.origin
            guard v.length > 0.1 else { return }
            // Snap to 15° increments unless an object snap placed the point.
            let a = v.angle
            draft.direction = i.snap?.elementIDs.isEmpty == false ? a : (a / (.pi / 12)).rounded() * (.pi / 12)
        case .widthLeft, .widthRight:
            let runEnd = run.start + dir * (Double(max(run.risers - 1, 0)) * l.treadDepth)
            let d = abs((p - run.start.lerp(to: runEnd, t: 0.5)).dot(side))
            draft.width = max(0.6, (d * 2 / 0.01).rounded() * 0.01)
        case .landing:
            // The landing handle sits half a run width beyond the last riser of the first flight.
            let along = (p - draft.origin).dot(Vec2.fromAngle(draft.direction)) - draft.width / 2
            setFirstRun(Int((along / l.treadDepth).rounded()) + 1)
        }
    }

    public func pointerUp(_ i: ToolInput) {
        dragging = nil
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = (dragging ?? hover) == nil ? .arrow : .move
        guard let e = probe, let l = StairGeometry.layout(e, ctx.model) else { return }
        for r in l.runs { preview.primitives.append(.polyline(l.runRect(r).points, closed: true, ctx.previewHeavy)) }
        for land in l.landings { preview.primitives.append(.polyline(land.polygon.points, closed: true, ctx.previewStroke)) }
        for s in StairGeometry.planLines(e, ctx.model, cutZ: .infinity).treads { preview.primitives.append(ctx.line(s.start, s.end)) }
        let size = ctx.pixel * 4
        for (h, p) in handles() {
            let r = Rect2(points: [p - Vec2(size, size), p + Vec2(size, size)])
            preview.primitives.append(.polyline(r.corners, closed: true, h == (dragging ?? hover) ? ctx.previewHeavy : ctx.previewStroke))
        }
        preview.tempDims = l.runs.map { r in
            let end = r.start + r.direction * (Double(max(r.risers - 1, 0)) * l.treadDepth)
            let side = r.direction.perpendicular * (r.width / 2 + ctx.pixel * 12)
            return TemporaryDimension(from: r.start + side, to: end + side, text: "\(r.risers) risers", isAngle: false, isActive: false)
        }
        preview.highlight = [stairID]
    }

    public func finish() -> Bool {
        let data = draft
        guard data != ctx.model[stairID]?.stair else { ctx.toolFinished?(); return true }
        ctx.session.perform("Edit Stair") { tx in tx.update(stairID) { $0.stair = data } }
        if let err = ctx.session.lastError { message(err.message); return false }
        for w in ctx.session.lastWarnings { message(w.message) }
        ctx.toolFinished?()
        return true
    }

    public func cancelSketch() { ctx.toolFinished?() }

    public func escape() -> EscapeResult {
        if dragging != nil { dragging = nil; rebuild() }
        return .stayInTool
    }
}
