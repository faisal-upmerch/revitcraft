import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Camera

/// Places a perspective camera in a plan: click the eye position, then the target. The new 3D view's eye and target
/// sit at the given heights above the plan's level.
@MainActor
public final class CameraTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .cameraView
    public var title: String { "Camera" }
    var eye: Vec2?
    var current: Vec2?
    public var eyeHeight = CameraViews.defaultEyeHeight
    public var targetHeight = CameraViews.defaultTargetHeight
    /// Called with the new view after it is created (the host opens it).
    public var onCreated: ((ElementID) -> Void)?

    public override init(ctx: ToolContext) { super.init(ctx: ctx) }

    public var prompt: String {
        guard ctx.isPlan else { return "Cameras are placed in plan views. Open a floor plan first." }
        return eye == nil ? "Click to place the camera (eye position)." : "Click the point the camera looks at."
    }
    public var snapFrom: Vec2? { eye }

    public var options: [ToolOption] {
        [ToolOption(id: "eyeHeight", label: "Eye Height", kind: .length, value: .double(eyeHeight)),
         ToolOption(id: "targetHeight", label: "Target Height", kind: .length, value: .double(targetHeight))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        guard let d = value.doubleValue, d.isFinite else { return }
        if id == "eyeHeight" { eyeHeight = d }
        if id == "targetHeight" { targetHeight = d }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let e = eye else { return }
        let d = i.point - e
        guard d.length > 1e-9 else { return }
        let spread = tan(CameraViews.defaultFieldOfView / 2) * d.length
        let s = d.normalized.perpendicular * spread
        preview.primitives = [ctx.line(e, i.point), ctx.line(e, i.point + s), ctx.line(e, i.point - s), ctx.line(i.point - s, i.point + s)]
        preview.tempDims = [tempDim(e, i.point)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a floor plan to place a camera."); return }
        guard let e = eye else { eye = i.point; return }
        guard e.distance(to: i.point) > Tolerance.shortCurve else { message("Pick a target away from the camera."); return }
        var created: ElementID?
        let level = ctx.levelID, eh = eyeHeight, th = targetHeight
        ctx.session.perform("Create Camera") { tx in
            created = try CameraViews.create(eye: e, target: i.point, levelID: level, in: tx, eyeHeight: eh, targetHeight: th)
        }
        eye = nil
        preview = ToolPreview()
        if let created {
            onCreated?(created)
            ctx.toolFinished?()
        } else if let err = ctx.session.lastError {
            message(err.message)
        }
    }

    public func escape() -> EscapeResult {
        if eye != nil { eye = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Scope box

/// Draws a scope box as a rectangle in plan (two opposite corners).
@MainActor
public final class ScopeBoxTool: BaseTool, InteractiveTool {
    public let commandID: CommandID = .scopeBox
    public var title: String { "Scope Box" }
    var start: Vec2?
    public var name: String

    public override init(ctx: ToolContext) {
        name = ScopeBoxes.nextName(ctx.model)
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Scope boxes are drawn in plan views." }
        return start == nil ? "Click the first corner of \(name)." : "Click the opposite corner."
    }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] {
        [ToolOption(id: "name", label: "Name", kind: .choice([name]), value: .text(name))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "name", let s = value.textValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty { name = s }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let s = start else { return }
        let r = Rect2(points: [s, i.point])
        preview.primitives = [.polyline(r.corners, closed: true, GStroke(weight: 1, color: RGBColor(0.42, 0.33, 0.66), pattern: .dashDot))]
        preview.tempDims = [tempDim(Vec2(r.min.x, r.min.y), Vec2(r.max.x, r.min.y)), tempDim(Vec2(r.max.x, r.min.y), Vec2(r.max.x, r.max.y), active: false)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to draw a scope box."); return }
        guard let s = start else { start = i.point; return }
        let r = Rect2(points: [s, i.point])
        guard r.width > Tolerance.shortCurve, r.height > Tolerance.shortCurve else { message("Drag out a rectangle with some width and depth."); return }
        let (bottom, top) = ScopeBoxes.defaultElevations(ctx.model)
        let box = ScopeBoxData(rect: r, bottomElevation: bottom, topElevation: top)
        let n = name
        ctx.session.perform("Create Scope Box") { tx in tx.create(.scopeBoxes, name: n, data: .scopeBox(box)) }
        if let err = ctx.session.lastError { message(err.message) }
        start = nil
        preview = ToolPreview()
        name = ScopeBoxes.nextName(ctx.model)
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Grid Pick Lines

extension LineTool {
    /// Draw modes offered for grids (shown in the Draw panel).
    static let gridModes = ["Line", "Pick Lines"]

    /// Pick Lines for grids: hover highlights the line under the cursor; a click creates a grid on it.
    func pickLinesMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let (seg, _) = ctx.snapIndex.nearestSegment(i.rawPoint, radius: ctx.pixel * 8) {
            preview.primitives = [.polyline([seg.start, seg.end], closed: false, ctx.previewHeavy)]
            preview.cursor = .pick
        }
    }

    func pickLinesDown(_ i: ToolInput) {
        guard let (seg, _) = ctx.snapIndex.nearestSegment(i.rawPoint, radius: ctx.pixel * 8) else {
            message("Click a line, wall face, reference plane or CAD line to place a grid on it.")
            return
        }
        commit(.line(seg))
    }
}
