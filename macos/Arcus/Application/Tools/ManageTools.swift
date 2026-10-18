import Foundation
import ArcusGeometry
import ArcusDomain

// F11: Manage tools (RevitCraft rc-app canvas_tools.rs `ToolKind::SpecifyCoords`, `ReportCoords`, `Relocate`,
// `PickToEdit`).

/// Specify Coordinates at Point and Report Shared Coordinates: click a point in plan. Reporting shows its shared
/// coordinates beside the pointer and in the status bar; specifying hands the point to `onPick`, where the dialog asks
/// for the coordinates it should read.
@MainActor
public final class SharedCoordinatesTool: BaseTool, InteractiveTool {
    public let reports: Bool
    public var commandID: CommandID { reports ? .reportCoordinates : .specifyCoordinates }
    public var title: String { reports ? "Report Shared Coordinates" : "Specify Coordinates at Point" }
    /// Specify: the picked point (plan XY at the view's level elevation).
    public var onPick: ((Vec3) -> Void)?
    public private(set) var lastReport: String?

    public init(ctx: ToolContext, reports: Bool) { self.reports = reports; super.init(ctx: ctx) }

    public var prompt: String { reports ? (lastReport.map { "\($0) — click another point." } ?? "Click a point to report its shared coordinates.") : "Click a point to specify its shared coordinates." }

    func point(_ p: Vec2) -> Vec3 { Vec3(p, z: ctx.levelElevation) }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        let r = ctx.pixel * 5
        preview.primitives.append(.arc(Arc2(center: i.point, radius: r, startAngle: 0, sweep: Angle.twoPi), ctx.previewStroke))
        if reports {
            let s = SharedCoordinates.shared(point(i.point), ctx.model.projectInfo)
            let lines = ["N/S \(ctx.format(s.northSouth))", "E/W \(ctx.format(s.eastWest))", "Elev \(ctx.format(s.elevation))"]
            for (k, l) in lines.enumerated() {
                preview.primitives.append(.text(GText(position: i.point + Vec2(ctx.pixel * 14, ctx.pixel * (30 - Double(k) * 15)), height: ctx.pixel * 9 / Double(max(ctx.scale, 1)), string: l,
                                                      color: RGBColor(0.18, 0.43, 0.66))))
            }
        }
        preview.cursor = .crosshair
    }

    public func pointerDown(_ i: ToolInput) {
        let p = point(i.point)
        if reports {
            let text = SharedCoordinates.report(SharedCoordinates.shared(p, ctx.model.projectInfo), ctx.model)
            lastReport = text
            message(text)
        } else {
            onPick?(p)
        }
    }

    public func escape() -> EscapeResult {
        if lastReport != nil { lastReport = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Relocate Project: click a start and an end point; the project moves by that vector against the shared coordinates
/// (the model itself stays where it is in the project).
@MainActor
public final class RelocateProjectTool: BaseTool, InteractiveTool {
    public var commandID: CommandID { .relocateProject }
    public var title: String { "Relocate Project" }
    var start: Vec2?

    public var prompt: String { start == nil ? "Click to enter move start point." : "Click to enter move end point, or type the distance." }
    public var snapFrom: Vec2? { start }
    public var numericLabel: String? { start == nil ? nil : "Distance" }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let a = start {
            preview.primitives.append(ctx.line(a, i.point))
            preview.tempDims.append(tempDim(a, i.point))
            preview.rubberBand = Segment2(a, i.point)
        }
        preview.cursor = .crosshair
    }

    public func pointerDown(_ i: ToolInput) {
        guard let a = start else { start = i.point; return }
        relocate(by: i.point - a)
    }

    public func numericInput(_ text: String) -> Bool {
        guard let a = start, let d = ctx.parse(text), let last = preview.rubberBand else { return false }
        let dir = (last.end - a).normalized
        guard dir.length > 0.5 else { return false }
        relocate(by: dir * d)
        return true
    }

    func relocate(by delta: Vec2) {
        start = nil
        preview = ToolPreview()
        guard delta.length > Tolerance.length else { return }
        let ok = ctx.session.perform("Relocate Project") { tx in
            guard let pid = tx.model.projectInfoElement?.id else { return }
            tx.update(pid) { e in guard var info = e.projectInfo else { return }; SharedCoordinates.relocate(by: delta, &info); e.projectInfo = info }
        } != nil
        if ok { message("The project was relocated against the shared coordinates.") }
        ctx.toolFinished?()
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Pick to Edit: click an element in a design option to make its option the one being edited.
@MainActor
public final class PickToEditTool: BaseTool, InteractiveTool {
    public var commandID: CommandID { .pickToEdit }
    public var title: String { "Pick to Edit" }
    public var onPick: ((ElementID) -> Void)?
    public var prompt: String { "Click an element in a design option to edit that option." }

    func target(_ i: ToolInput) -> Element? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            if let e = ctx.model[id], DesignOptionEditing.pickTarget(id, ctx.model) != nil { return e }
        }
        return nil
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let e = target(i) { preview.highlight = [e.id]; preview.cursor = .pick } else { preview.cursor = .notAllowed }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let e = target(i), let opt = DesignOptionEditing.pickTarget(e.id, ctx.model) else { message("Pick an element in a design option."); return }
        onPick?(opt)
        ctx.toolFinished?()
    }

    public func escape() -> EscapeResult { .exitTool }
}
