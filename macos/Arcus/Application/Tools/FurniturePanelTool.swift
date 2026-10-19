import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// FM4: Create ▸ Parts ▸ Panel (PA), drawn as Wall is: Line (chained), Rectangle or Pick Lines; Location Line; Base and
// Top Constraint to the piece's planes with offsets or an Unconnected Height; Space flips the outside face. In a plan
// the panel stands up from its line; in a Front/Back or Left/Right elevation it lies in the line's plane and runs
// across the view (Front to Back, or Left to Right).

@MainActor
public final class FurniturePanelTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable { case line = "Line", rectangle = "Rectangle", pickLines = "Pick Lines" }

    public var mode: Mode
    public let commandID: CommandID = .furniturePanel
    public var title: String { "Panel" }
    public var chain = true
    public var locationLine: PanelLocationLine = .faceOutside
    /// Space: the outside face on the right of the drawing direction.
    public var flipSide = false
    public var extent: PartExtent
    public let map: FurnitureSketchMap?
    var start: Vec2?
    var current: Vec2?
    var created = 0

    public init(ctx: ToolContext, mode: Mode = .line) {
        self.mode = mode
        map = FurnitureSketchMap.of(ctx.viewData)
        let d = map?.defaultExtent ?? (base: "Bottom", top: "Top")
        extent = PartExtent(basePlane: d.base, baseOffset: 0, topPlane: d.top, topOffset: 0, height: 30 * 0.0254)
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard map != nil else { return "Draw panels in a plan, or in an elevation or section square to the piece." }
        let flip = " Space flips the outside face."
        switch mode {
        case .line: return start == nil ? "Click to start the panel." : "Click to end the panel, or type a length. Esc ends the chain." + flip
        case .rectangle: return start == nil ? "Click the first corner." : "Click the opposite corner." + flip
        case .pickLines: return "Click a reference plane or line to put a panel on it."
        }
    }
    public var numericLabel: String? { mode == .line && start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }

    var axis: FamilyAxis { (map?.plane ?? .xy).axes.w }

    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Draw", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue))]
        o += FurnitureToolOptions.extentOptions(extent, axis: axis, ctx.model, topLabel: map?.plane == .xy ? "Height" : "Depth")
        o.append(ToolOption(id: "location", label: "Location Line", kind: .choice(PanelLocationLine.allCases.map(\.rawValue)), value: .text(locationLine.rawValue)))
        if mode == .line { o.append(ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain))) }
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        if FurnitureToolOptions.setExtent(&extent, id, value) { rebuild(); return }
        switch id {
        case "mode": if let m = Mode(rawValue: value.textValue ?? "") { mode = m; start = nil }
        case "location": if let l = PanelLocationLine(rawValue: value.textValue ?? "") { locationLine = l }
        case "chain": chain = value.boolValue ?? true
        default: break
        }
        rebuild()
    }

    var typeID: ElementID? { FurnitureToolOptions.type(.furniturePanels, family: "Panel", ctx) }
    var thickness: Double { FurniturePartTypes.Values(ctx.model[typeID]?.typeData).thickness }

    /// The panel outline for a view line, in view coordinates, with its outside face first.
    func outline(_ a: Vec2, _ b: Vec2, flip: Bool? = nil) -> (outside: Segment2, inside: Segment2)? {
        guard let map, a.distance(to: b) > Tolerance.shortCurve else { return nil }
        let s = map.toSketch(a), e = map.toSketch(b)
        let p = PanelData(start: s, end: e, locationLine: locationLine, flipped: (flip ?? flipSide) != map.mirrored, base: 0, top: 1)
        let (fo, fi) = FurniturePartSolids.faceOffsets(p, thickness: thickness)
        let n = (e - s).normalized.perpendicular
        let out = Segment2(map.toView(s + n * fo), map.toView(e + n * fo)), inn = Segment2(map.toView(s + n * fi), map.toView(e + n * fi))
        return (out, inn)
    }

    func ghost(_ a: Vec2, _ b: Vec2) -> [GPrimitive] {
        guard let (o, i) = outline(a, b) else { return [] }
        var prims: [GPrimitive] = [.polyline([o.start, o.end], closed: false, ctx.previewHeavy), .polyline([i.start, i.end], closed: false, ctx.previewStroke),
                                   ctx.line(o.start, i.start), ctx.line(o.end, i.end), ctx.line(a, b)]
        // The outside marker at mid-length, as walls show their exterior.
        let m = o.midpoint, d = (o.end - o.start).normalized, n = (o.midpoint - i.midpoint).normalized
        let size = ctx.pixel * 10
        prims.append(.polyline([m + d * size * 0.6, m + n * size, m - d * size * 0.6], closed: false, ctx.previewStroke))
        return prims
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        guard let c = current else { return }
        switch mode {
        case .line:
            if let s = start {
                preview.primitives = ghost(s, c)
                preview.tempDims = [tempDim(s, c), angleDim(s, c)] + referenceDims(for: Segment2(s, c))
            }
        case .rectangle:
            if let s = start {
                let r = Rect2(points: [s, c])
                for e in Polygon2.rectangle(r).clockwise.edges { preview.primitives += ghost(e.start, e.end) }
                preview.tempDims = [tempDim(Vec2(r.min.x, r.min.y), Vec2(r.max.x, r.min.y)), tempDim(Vec2(r.max.x, r.min.y), Vec2(r.max.x, r.max.y), active: false)]
            }
        case .pickLines:
            if let (seg, _) = ctx.snapIndex.nearestSegment(c, radius: ctx.pixel * 8) {
                preview.primitives = ghost(seg.start, seg.end)
                preview.cursor = .pick
            }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard map != nil else { message(prompt); return }
        let p = i.point
        switch mode {
        case .line:
            if let s = start {
                if create([(s, p)]) { start = chain ? p : nil }
            } else { start = p }
        case .rectangle:
            if let s = start {
                let r = Rect2(points: [s, p])
                guard r.width > Tolerance.shortCurve, r.height > Tolerance.shortCurve else { return }
                createRectangle(r)
                start = nil
            } else { start = p }
        case .pickLines:
            if let (seg, _) = ctx.snapIndex.nearestSegment(p, radius: ctx.pixel * 8) { create([(seg.start, seg.end)]) }
            else { message("Click a reference plane or a line.") }
        }
        rebuild()
    }

    /// Creates panels on view lines; true when created.
    @discardableResult
    func create(_ lines: [(Vec2, Vec2)]) -> Bool {
        guard let map else { return false }
        let ext = extent, loc = locationLine, flip = flipSide != map.mirrored, type = typeID
        ctx.session.perform(lines.count == 1 ? "Create Panel" : "Create Panels") { tx in
            for (a, b) in lines {
                try FurniturePartOperations.createPanel(start: map.toSketch(a), end: map.toSketch(b), plane: map.plane, locationLine: loc, flipped: flip,
                                                        extent: ext, typeID: type, in: tx)
            }
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        created += lines.count
        return true
    }

    func createRectangle(_ r: Rect2) {
        guard let map else { return }
        let a = map.toSketch(r.min), b = map.toSketch(r.max)
        let sr = Rect2(points: [a, b])
        let ext = extent, loc = locationLine, flip = flipSide, type = typeID
        ctx.session.perform("Create Panels") { tx in
            try FurniturePartOperations.createPanelRectangle(sr, plane: map.plane, locationLine: loc, flipped: flip, extent: ext, typeID: type, in: tx)
        }
        if let e = ctx.session.lastError { message(e.message) } else { created += 4 }
    }

    public func numericInput(_ text: String) -> Bool {
        guard mode == .line, let s = start, let c = current, let v = ctx.parse(text), v > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        let e = s + d * v
        if create([(s, e)]) { start = chain ? e : nil; current = e }
        rebuild()
        return true
    }

    public func spaceBar() {
        flipSide.toggle()
        message(flipSide ? "Outside face: right of the drawing direction." : "Outside face: left of the drawing direction.")
        rebuild()
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}
