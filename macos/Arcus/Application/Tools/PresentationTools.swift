import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F810: View tab tools ported from RevitCraft's canvas_tools.rs: Show/Remove Hidden Lines, Cut Profile (pick the
// wall), Framing Elevation, Walkthrough and Matchline.

// MARK: - Show / Remove Hidden Lines

/// Pick the element that obscures, then the element whose lines it hides (RevitCraft `ToolKind::ShowHiddenLines`).
@MainActor
public final class HiddenLinesTool: BaseTool, InteractiveTool {
    public let show: Bool
    public var commandID: CommandID { show ? .showHiddenLines : .removeHiddenLines }
    public var title: String { show ? "Show Hidden Lines" : "Remove Hidden Lines" }
    /// The obscuring element picked first.
    public private(set) var obscuring: ElementID?

    public init(ctx: ToolContext, show: Bool) { self.show = show; super.init(ctx: ctx) }

    public var prompt: String { obscuring == nil ? "Select an element that is obscuring other elements." : "Select element whose lines are hidden." }

    /// Model elements only (view-specific annotation can't hide or be hidden). The second pick looks past the
    /// obscuring element, which usually lies on top.
    func target(_ i: ToolInput) -> Element? {
        let ids = [i.hit].compactMap({ $0 }) + i.hitCandidates
        let models = ids.compactMap { ctx.model[$0] }.filter { $0.ownerViewID == nil && $0.category.isModel }
        return models.first { $0.id != obscuring } ?? models.first
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let o = obscuring { preview.highlight = [o] }
        if let e = target(i) { preview.highlight.insert(e.id); preview.cursor = .pick } else { preview.cursor = .notAllowed }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let e = target(i) else { message("Select a model element."); return }
        guard let o = obscuring else {
            obscuring = e.id
            ctx.session.selection.select([e.id])
            return
        }
        let view = ctx.viewID, show = show
        ctx.session.perform(title) { tx in
            if show { try HiddenLines.show(e.id, behind: o, in: view, tx) } else { try HiddenLines.remove(e.id, behind: o, in: view, tx) }
        }
        if let err = ctx.session.lastError { message(err.message) }
        obscuring = nil
        ctx.session.selection.clear()
        preview = ToolPreview()
    }

    public func escape() -> EscapeResult {
        if obscuring != nil { obscuring = nil; ctx.session.selection.clear(); preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Cut Profile

/// Pick the wall whose cut to edit; the host then starts the cut profile sketch (RevitCraft `ToolKind::CutProfileHost`).
@MainActor
public final class CutProfileTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.cutProfile
    public let title = "Cut Profile"
    /// Called with the picked wall; the host starts the sketch.
    public var onPicked: ((ElementID) -> Void)?

    public override init(ctx: ToolContext) { super.init(ctx: ctx) }

    public var prompt: String { "Select a wall to edit its cut profile." }

    /// A wall cut by the plan's cut plane.
    func wall(_ i: ToolInput) -> Element? {
        guard let w = hit(i, [.walls]), let v = ctx.view else { return nil }
        return WallGeometry.planCut(w, atZ: CutProfiles.cutZ(v, ctx.model), ctx.model).isEmpty ? nil : w
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let w = wall(i) { preview.highlight = [w.id]; preview.cursor = .pick } else { preview.cursor = .notAllowed }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let w = wall(i) else { message("Select a wall cut in this view."); return }
        onPicked?(w.id)
    }

    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Framing Elevation

/// Click near a grid, on the side to look from (RevitCraft `ToolKind::FramingElevation`).
@MainActor
public final class FramingElevationTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.framingElevation
    public let title = "Framing Elevation"
    public override init(ctx: ToolContext) { super.init(ctx: ctx) }

    public var prompt: String { ctx.isPlan ? "Click near a grid, on the side to look from." : "Place framing elevations in a plan view." }

    /// The straight grid under (or nearest to) the pointer.
    func grid(_ i: ToolInput) -> Element? {
        if let g = hit(i, [.grids]), g.grid?.curve.asSegment != nil { return g }
        let tol = ctx.pixel * 12
        return ctx.model.elements(.grids).filter { $0.grid?.curve.asSegment != nil }
            .map { ($0, $0.grid!.curve.distance(to: i.rawPoint)) }.filter { $0.1 <= tol }.min { $0.1 < $1.1 }?.0
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let g = grid(i), let seg = g.grid?.curve.asSegment else { preview.cursor = .notAllowed; return }
        preview.highlight = [g.id]
        preview.cursor = .pick
        // The marker beside the grid, looking at it.
        let n = seg.direction.perpendicular
        let side: Double = (i.rawPoint - seg.start).dot(n) >= 0 ? 1 : -1
        let o = seg.closestPoint(to: i.rawPoint) + n * side * FramingElevations.offset
        let r = ctx.paper(0.005)
        preview.primitives = [.arc(Arc2(center: o, radius: r, startAngle: 0, sweep: Angle.twoPi), ctx.previewHeavy),
                              ctx.line(o, o - n * side * r * 1.8, heavy: true)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Place framing elevations in a plan view."); return }
        guard let g = grid(i) else { message("Click near a grid."); return }
        let scale = ctx.scale
        var created: ElementID?
        ctx.session.perform("Create Framing Elevation") { tx in created = try FramingElevations.create(grid: g.id, side: i.rawPoint, scale: scale, tx) }
        if let created { message("Created “\(ctx.model[created]?.name ?? "")”. Double-click the marker to open it.") }
        else if let err = ctx.session.lastError { message(err.message) }
    }

    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Walkthrough

/// Click the camera positions in plan, then Finish Walkthrough (Enter) (RevitCraft `ToolKind::Walkthrough`).
@MainActor
public final class WalkthroughTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.walkthrough
    public let title = "Walkthrough"
    public private(set) var points: [Vec2] = []
    var current: Vec2?
    public var eyeHeight: Double
    public var frames = WalkthroughData.defaultFrames
    /// Called with the new walkthrough view (the host opens it).
    public var onCreated: ((ElementID) -> Void)?

    public override init(ctx: ToolContext) {
        eyeHeight = Walkthroughs.eyeHeight(ctx.units)
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Walkthroughs are placed in plan views." }
        return points.count < 2 ? "Click to place the walkthrough's camera positions." : "Click the next camera position, or Finish Walkthrough (↩)."
    }
    public var snapFrom: Vec2? { points.last }
    public var numericLabel: String? { points.isEmpty ? nil : "Length" }

    public var options: [ToolOption] {
        [ToolOption(id: "eyeHeight", label: "Offset", kind: .length, value: .double(eyeHeight)),
         ToolOption(id: "frames", label: "Total Frames", kind: .integer, value: .int(frames))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "eyeHeight", let d = value.doubleValue, d.isFinite { eyeHeight = d }
        if id == "frames", let n = value.intValue, n >= 2 { frames = min(n, 10_000) }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        var pts = points
        if let c = current, !points.isEmpty { pts.append(c) }
        if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: false, ctx.previewHeavy)) }
        let r = ctx.pixel * 4
        for q in points { preview.primitives.append(.arc(Arc2(center: q, radius: r, startAngle: 0, sweep: Angle.twoPi), ctx.previewStroke)) }
        if let a = points.last, let c = current { preview.tempDims = [tempDim(a, c)] }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Walkthroughs are placed in plan views."); return }
        if let last = points.last, last.distance(to: i.point) < Tolerance.shortCurve { return }
        points.append(i.point)
        rebuild()
    }

    public func numericInput(_ text: String) -> Bool {
        guard let a = points.last, let c = current, let d = ctx.parse(text), d > 0 else { return false }
        let dir = (c - a).length > 1e-9 ? (c - a).normalized : Vec2(1, 0)
        points.append(a + dir * d)
        rebuild()
        return true
    }

    /// Finish Walkthrough: creates the walkthrough view from the clicked path.
    public func finish() -> Bool {
        guard points.count >= 2 else { message("Click at least two points along the walkthrough path."); return false }
        let path = points, level = ctx.levelID, h = eyeHeight, n = frames
        var created: ElementID?
        ctx.session.perform("Create Walkthrough") { tx in created = try Walkthroughs.create(path: path, levelID: level, eyeHeight: h, frames: n, tx) }
        guard let created else { if let err = ctx.session.lastError { message(err.message) }; return false }
        points = []
        preview = ToolPreview()
        ctx.toolFinished?()
        onCreated?(created)
        return true
    }

    public func escape() -> EscapeResult {
        if !points.isEmpty { points.removeLast(); rebuild(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Matchline

/// Click the start and the end of the matchline (RevitCraft `ToolKind::Matchline`).
@MainActor
public final class MatchlineTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.matchline
    public let title = "Matchline"
    var start: Vec2?
    var current: Vec2?
    public override init(ctx: ToolContext) { super.init(ctx: ctx) }

    public var prompt: String { start == nil ? "Click the start of the matchline." : "Click the end of the matchline." }
    public var snapFrom: Vec2? { start }
    public var numericLabel: String? { start == nil ? nil : "Length" }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let s = start else { return }
        var st = ViewGraphicsBuilder.matchlineStroke
        st.color = ctx.previewStroke.color
        preview.primitives = [.polyline([s, i.point], closed: false, st)]
        preview.tempDims = [tempDim(s, i.point), angleDim(s, i.point)]
    }

    public func pointerDown(_ i: ToolInput) { place(i.point) }

    func place(_ p: Vec2) {
        guard ctx.isPlan else { message("Draw matchlines in a plan view."); return }
        guard let s = start else { start = p; return }
        ctx.session.perform("Matchline") { tx in try Matchlines.create(from: s, to: p, tx) }
        if let err = ctx.session.lastError { message(err.message); return }
        start = nil
        preview = ToolPreview()
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let d = ctx.parse(text), d > 0, (c - s).length > 1e-9 else { return false }
        place(s + (c - s).normalized * d)
        return true
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Guide grid snapping

extension SelectTool {
    /// Viewports dragged on a sheet with a guide grid: their edges and centres snap to the guide lines (within 8 points).
    func f810GuideGridMove(_ v: Vec2, _ sel: [Element]) -> Vec2? {
        guard ctx.isSheet, let spacing = ctx.view?.sheet?.guideGridSpacing, spacing > 0, !sel.isEmpty, sel.allSatisfy({ $0.viewport != nil }) else { return nil }
        let boxes = sel.compactMap { GuideGrids.viewportBox($0, ctx.model) }
        return GuideGrids.snap(v, boxes: boxes, spacing: spacing, tolerance: ctx.pixel * 8)
    }
}
