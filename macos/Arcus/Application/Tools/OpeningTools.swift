import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Wall Opening

/// Cuts a rectangular opening in a wall: pick the wall, then two corners, in an elevation or section.
@MainActor
public final class WallOpeningTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.wallOpening
    public let title = "Wall Opening"
    var hostID: ElementID?
    var first: Vec2?
    var current: Vec2?

    public var prompt: String {
        guard ctx.isVertical else { return "Wall openings are drawn in elevations and sections. Open one that shows the wall." }
        if hostID == nil { return "Click the wall to cut." }
        return first == nil ? "Click the first corner of the opening." : "Click the opposite corner of the opening."
    }

    /// The wall under the cursor (basic walls only; curtain walls use empty panels instead).
    func wall(at i: ToolInput) -> Element? {
        let m = ctx.model
        if let e = hit(i, [.walls]), !CurtainWallGeometry.isCurtain(e, m), station(i.rawPoint.x, e) != nil { return e }
        guard let vd = ctx.viewData, let o = vd.planeOrigin, let fwd = vd.viewDirection?.normalized else { return nil }
        var best: (Element, Double)?
        for w in m.elements(.walls) where !CurtainWallGeometry.isCurtain(w, m) {
            guard let f = WallGeometry.frame(w, m), i.rawPoint.y >= f.baseZ, i.rawPoint.y <= f.topZ,
                  let s = station(i.rawPoint.x, w) else { continue }
            let depth = (WallGeometry.point(atStation: s, on: f.location) - o.xy).dot(fwd)
            guard depth >= -0.01, depth <= vd.farClip else { continue }
            if best == nil || depth < best!.1 { best = (w, depth) }
        }
        return best?.0
    }

    /// Station along a wall under view coordinate u, when the view does not look along the wall.
    func station(_ u: Double, _ w: Element) -> Double? {
        guard let vd = ctx.viewData, let f = WallGeometry.frame(w, ctx.model),
              let s = CurtainWallGeometry.station(ofViewU: u, view: vd, wall: f), s >= -1e-6, s <= f.length + 1e-6 else { return nil }
        return s
    }

    /// View u of a wall station.
    func viewU(_ s: Double, _ f: WallFrame) -> Double? {
        guard let vd = ctx.viewData, let o = vd.planeOrigin, let r = vd.rightVector else { return nil }
        return (WallGeometry.point(atStation: s, on: f.location) - o.xy).dot(r)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        if hostID == nil {
            if let w = wall(at: i) { preview.highlight = [w.id]; preview.cursor = .pick }
            return
        }
        preview.highlight = [hostID!]
        guard let a = first else { return }
        let b = i.point
        preview.primitives = [.polyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, ctx.previewHeavy)]
        preview.tempDims = [tempDim(Vec2(a.x, min(a.y, b.y)), Vec2(b.x, min(a.y, b.y))), tempDim(Vec2(max(a.x, b.x), a.y), Vec2(max(a.x, b.x), b.y), active: false)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isVertical else { message("Open an elevation or section to cut a wall opening."); return }
        guard let host = hostID.flatMap({ ctx.model[$0] }) else {
            if let w = wall(at: i) { hostID = w.id } else { message("Click a wall. Curtain walls take empty panels instead of openings.") }
            pointerMoved(i)
            return
        }
        guard let a = first else { first = i.point; return }
        create(host, a, i.point)
        first = nil
        pointerMoved(i)
    }

    func create(_ host: Element, _ a: Vec2, _ b: Vec2) {
        guard let f = WallGeometry.frame(host, ctx.model), let s0 = station(a.x, host) ?? clampStation(a.x, f), let s1 = station(b.x, host) ?? clampStation(b.x, f) else {
            message("This view looks along the wall; use a view that faces it.")
            return
        }
        let lo = max(0, min(s0, s1)), hi = min(f.length, max(s0, s1))
        let z0 = max(f.baseZ, min(a.y, b.y)) - f.baseZ, z1 = min(f.topZ, max(a.y, b.y)) - f.baseZ
        guard hi - lo > 0.01, z1 - z0 > 0.01 else { message("The opening must overlap the wall."); return }
        let data = WallOpeningData(start: lo, end: hi, bottom: z0, top: z1)
        let id = host.id
        ctx.session.perform("Create Wall Opening") { tx in
            tx.create(.wallOpenings, data: .opening(.wall(data)), levelID: tx.model[id]?.levelID, hostID: id)
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    /// Corners clicked beyond the wall's ends clamp to them.
    func clampStation(_ u: Double, _ f: WallFrame) -> Double? {
        guard let u0 = viewU(0, f), let u1 = viewU(f.length, f), abs(u1 - u0) > 1e-9 else { return nil }
        return min(max((u - u0) / (u1 - u0), 0), 1) * f.length
    }

    public func escape() -> EscapeResult {
        if first != nil { first = nil; preview = ToolPreview(); return .stayInTool }
        if hostID != nil { hostID = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Shaft Opening

/// Sketches a shaft boundary (lines, rectangles, circles) in a plan; Finish creates a shaft that cuts every floor,
/// ceiling and roof between its base (this level plus Base Offset) and its top.
@MainActor
public final class ShaftOpeningTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable { case line = "Line", rectangle = "Rectangle", circle = "Circle" }
    public let commandID = CommandID.shaftOpening
    public let title = "Shaft Opening"
    public var isSketchMode: Bool { true }
    public var mode: Mode = .rectangle
    public var topLevelID: ElementID?
    public var unconnectedHeight = 3.0
    public var baseOffset = 0.0
    public var topOffset = 0.0
    /// Closed boundary loops sketched so far.
    var loops: [[Curve2]] = []
    /// Points of the line chain in progress, or the first corner / centre.
    var points: [Vec2] = []
    var current: Vec2?

    public override init(ctx: ToolContext) {
        super.init(ctx: ctx)
        topLevelID = ctx.model.levelAbove(ctx.levelID)?.id
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Shafts are sketched in plan views." }
        switch mode {
        case .line: return points.isEmpty ? "Click the first point of the shaft boundary." : "Click the next point; click the first point to close the loop. Finish when done."
        case .rectangle: return points.isEmpty ? "Click the first corner of the shaft." : "Click the opposite corner."
        case .circle: return points.isEmpty ? "Click the centre of the shaft." : "Click a point on the circle, or type the radius."
        }
    }
    public var numericLabel: String? { points.isEmpty ? nil : (mode == .circle ? "Radius" : mode == .line ? "Length" : nil) }
    public var snapFrom: Vec2? { points.last }

    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Draw", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue)),
                 ToolOption(id: "baseOffset", label: "Base Offset", kind: .length, value: .double(baseOffset)),
                 ToolOption(id: "top", label: "Top Constraint", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(ctx.model[topLevelID]?.name ?? "Unconnected"))]
        if topLevelID == nil { o.append(ToolOption(id: "height", label: "Unconnected Height", kind: .length, value: .double(unconnectedHeight))) }
        else { o.append(ToolOption(id: "topOffset", label: "Top Offset", kind: .length, value: .double(topOffset))) }
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode": if let m = Mode(rawValue: value.textValue ?? "") { mode = m; points = [] }
        case "baseOffset": baseOffset = value.doubleValue ?? baseOffset
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        case "height": if let d = value.doubleValue, d > 0.01 { unconnectedHeight = d }
        case "topOffset": topOffset = value.doubleValue ?? topOffset
        default: break
        }
    }

    func rectangle(_ a: Vec2, _ b: Vec2) -> [Curve2]? {
        let r = Rect2(points: [a, b])
        guard r.width > Tolerance.shortCurve, r.height > Tolerance.shortCurve else { return nil }
        return Polygon2.rectangle(r).edges.map { .line($0) }
    }
    func circle(_ c: Vec2, _ r: Double) -> [Curve2]? {
        guard r > Tolerance.shortCurve else { return nil }
        return [.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: .pi)), .arc(Arc2(center: c, radius: r, startAngle: .pi, sweep: .pi))]
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuildPreview()
    }

    func rebuildPreview() {
        preview = ToolPreview()
        for loop in loops { for c in loop { preview.primitives.append(prim(c, ctx.previewHeavy)) } }
        guard let c = current, let last = points.last else { return }
        switch mode {
        case .line:
            preview.primitives.append(.polyline(points + [c], closed: false, ctx.previewHeavy))
            preview.tempDims = [tempDim(last, c), angleDim(last, c)]
        case .rectangle:
            for e in rectangle(points[0], c) ?? [] { preview.primitives.append(prim(e, ctx.previewHeavy)) }
        case .circle:
            for e in circle(points[0], points[0].distance(to: c)) ?? [] { preview.primitives.append(prim(e, ctx.previewHeavy)) }
            preview.tempDims = [tempDim(points[0], c)]
        }
    }

    func prim(_ c: Curve2, _ st: GStroke) -> GPrimitive {
        switch c {
        case .line(let s): .polyline([s.start, s.end], closed: false, st)
        case .arc(let a): .arc(a, st)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to sketch a shaft."); return }
        add(i.point)
        rebuildPreview()
    }

    func add(_ p: Vec2) {
        switch mode {
        case .line:
            if points.count >= 3, p.distance(to: points[0]) <= max(ctx.pixel * 8, Tolerance.shortCurve) { closeChain(); return }
            if let last = points.last, last.distance(to: p) <= Tolerance.shortCurve { return }
            points.append(p)
        case .rectangle:
            if let a = points.first { if let r = rectangle(a, p) { loops.append(r); points = [] } } else { points = [p] }
        case .circle:
            if let c = points.first { if let r = circle(c, c.distance(to: p)) { loops.append(r); points = [] } } else { points = [p] }
        }
    }

    func closeChain() {
        guard points.count >= 3 else { return }
        loops.append(Polygon2(points).edges.map { .line($0) })
        points = []
    }

    public func numericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text), v > Tolerance.shortCurve, let last = points.last else { return false }
        switch mode {
        case .circle:
            guard let r = circle(last, v) else { return false }
            loops.append(r); points = []
        case .line:
            let c = current ?? last + .unitX
            let d = (c - last).lengthSquared > 0 ? (c - last).normalized : .unitX
            add(last + d * v)
        case .rectangle:
            return false
        }
        rebuildPreview()
        return true
    }

    public func finish() -> Bool {
        if mode == .line { closeChain() }
        let sketch = Sketch(loops: loops)
        switch sketch.profile() {
        case .failure(let e):
            message(e.description)
            return false
        case .success:
            break
        }
        guard let level = ctx.levelID else { return false }
        let data = ShaftOpeningData(boundary: sketch, baseOffset: baseOffset, topLevelID: topLevelID, topOffset: topOffset, unconnectedHeight: unconnectedHeight)
        let base = ctx.model.elevation(ofLevel: level) + baseOffset
        let top = ctx.model.topElevation(base: base, topLevelID: topLevelID, topOffset: topOffset, unconnectedHeight: unconnectedHeight)
        guard top > base + 0.01 else { message("The shaft's top must be above its base."); return false }
        ctx.session.perform("Create Shaft Opening") { tx in
            tx.create(.shaftOpenings, data: .opening(.shaft(data)), levelID: level)
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        loops = []; points = []
        ctx.toolFinished?()
        return true
    }

    public func cancelSketch() { loops = []; points = []; ctx.toolFinished?() }

    /// Esc removes the last sketched point; with nothing sketched it leaves the tool.
    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); rebuildPreview(); return .stayInTool }
        return loops.isEmpty ? .exitTool : .stayInTool
    }
}
