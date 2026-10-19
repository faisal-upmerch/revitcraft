import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Attach wall tops to a roof or floor: pick the target element.
@MainActor
public final class AttachTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.attachTop
    public let title = "Attach Top/Base"
    let walls: [ElementID]
    public var attachBase = false
    public init(ctx: ToolContext, walls: [ElementID]) { self.walls = walls; super.init(ctx: ctx) }
    public var prompt: String { "Click the roof or floor to attach the \(attachBase ? "base" : "top") of \(walls.count) wall(s) to." }
    public var options: [ToolOption] { [ToolOption(id: "base", label: "Attach", kind: .choice(["Top", "Base"]), value: .text(attachBase ? "Base" : "Top"))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "base" { attachBase = value.textValue == "Base" } }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let e = hit(i, [.roofs, .floors]) { preview.highlight = [e.id]; preview.cursor = .pick } else { preview.cursor = .notAllowed }
        preview.highlight.formUnion(walls)
    }
    public func pointerDown(_ i: ToolInput) {
        guard let target = hit(i, [.roofs, .floors]) else { message("Click a roof or floor."); return }
        let base = attachBase
        ctx.session.perform(base ? "Attach Base" : "Attach Top") { tx in
            for w in walls {
                tx.update(w) {
                    if base { if !($0.wall?.attachedBaseIDs.contains(target.id) ?? true) { $0.wall?.attachedBaseIDs.append(target.id) } }
                    else if !($0.wall?.attachedTopIDs.contains(target.id) ?? true) {
                        $0.wall?.attachedTopIDs.append(target.id)
                        // Attached walls extend up to the roof: raise the top so the roof underside governs.
                        if let ridge = RoofGeometry.ridgeHeight(target, tx.model), var wd = $0.wall {
                            let baseZ = tx.model.elevation(ofLevel: $0.levelID) + wd.baseOffset
                            if wd.topLevelID == nil { wd.unconnectedHeight = max(wd.unconnectedHeight, ridge - baseZ) } else {
                                wd.topOffset = max(wd.topOffset, ridge - tx.model.elevation(ofLevel: wd.topLevelID))
                            }
                            $0.wall = wd
                        }
                    }
                }
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
        ctx.toolFinished?()
    }
    public func escape() -> EscapeResult { .exitTool }
}

/// Moves a door or window to another wall.
@MainActor
public final class PickHostTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.pickHost
    public let title = "Pick New Host"
    let insertID: ElementID
    public init(ctx: ToolContext, insertID: ElementID) { self.insertID = insertID; super.init(ctx: ctx) }
    public var prompt: String { "Click a wall to move the insert to." }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let w = hit(i, [.walls]) { preview.highlight = [w.id]; preview.cursor = .pick } else { preview.cursor = .notAllowed }
    }
    public func pointerDown(_ i: ToolInput) {
        guard let w = hit(i, [.walls]), let f = WallGeometry.frame(w, ctx.model), let ins = ctx.model[insertID] else { message("Click a wall."); return }
        let width = InsertGeometry.openingSize(ins, ctx.model)?.width ?? 0.9
        guard let p = InsertGeometry.constrainToHost(i.rawPoint, width: width, host: f) else { message("That wall is too short for this \(ins.category.singularName.lowercased())."); return }
        ctx.session.perform("Pick New Host") { tx in tx.update(insertID) { $0.hostID = w.id; $0.levelID = w.levelID; $0.insert?.location = p } }
        if let e = ctx.session.lastError { message(e.message) }
        ctx.toolFinished?()
    }
    public func escape() -> EscapeResult { .exitTool }
}

/// Edit a wall's elevation profile in an elevation or section view parallel to the wall.
@MainActor
public final class WallProfileTool: BaseTool, InteractiveTool {
    /// The points placed so far snap and align, as in Revit.
    public var snapCurves: [Curve2] { SnapIndex.chain(points) }
    public let commandID = CommandID.editProfile
    public let title = "Edit Wall Profile"
    let wallID: ElementID
    var points: [Vec2] = []
    public var isSketchMode: Bool { true }
    public init(ctx: ToolContext, wallID: ElementID) {
        self.wallID = wallID
        super.init(ctx: ctx)
        // Seed with the current outline in view coordinates.
        if let w = ctx.model[wallID], let f = WallGeometry.frame(w, ctx.model), let seg = f.location.asSegment, let (u0, u1) = stations(seg) {
            if let p = w.wall?.profile {
                points = p.points.map { Vec2(u0 + ($0.x / f.length) * (u1 - u0), $0.y + f.baseZ) }
            } else {
                points = [Vec2(u0, f.baseZ), Vec2(u1, f.baseZ), Vec2(u1, f.topZ), Vec2(u0, f.topZ)]
            }
        }
    }
    /// View u of the wall start and end (the view must look perpendicular to the wall).
    func stations(_ seg: Segment2) -> (Double, Double)? {
        guard let vd = ctx.viewData, let o = vd.planeOrigin, let r = vd.rightVector, let d = vd.viewDirection else { return nil }
        guard abs(d.normalized.dot(seg.direction)) < 0.05 else { return nil }
        return ((seg.start - o.xy).dot(r), (seg.end - o.xy).dot(r))
    }
    public var prompt: String { "Click to replace the profile outline point by point; Finish when the outline is closed. Cancel keeps the current profile." }
    var fresh = true
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard !points.isEmpty else { return }
        preview.primitives = [.polyline(points + (fresh ? [] : [i.point]), closed: fresh, ctx.previewHeavy)]
    }
    public func pointerDown(_ i: ToolInput) {
        if fresh { points = []; fresh = false }
        points.append(i.point)
    }
    public func finish() -> Bool {
        guard let w = ctx.model[wallID], let f = WallGeometry.frame(w, ctx.model), let seg = f.location.asSegment else { return false }
        guard let (u0, u1) = stations(seg) else { message("Edit profiles in an elevation or section that looks straight at the wall."); return false }
        let poly = Polygon2(points)
        guard points.count >= 3, !poly.isDegenerate, poly.isSimple else { message("The profile must be a closed, non-crossing outline."); return false }
        let local = Polygon2(poly.points.map { Vec2(($0.x - u0) / (u1 - u0) * f.length, $0.y - f.baseZ) }).counterClockwise
        ctx.session.perform("Edit Wall Profile") { tx in tx.update(wallID) { $0.wall?.profile = local } }
        if let e = ctx.session.lastError { message(e.message); return false }
        ctx.toolFinished?()
        return true
    }
    public func cancelSketch() { ctx.toolFinished?() }
    public func escape() -> EscapeResult {
        if !fresh && !points.isEmpty { points.removeLast(); return .stayInTool }
        return .stayInTool
    }
}

/// Demolish: click model elements to mark them demolished in the view's phase. Hosted doors, windows and railings
/// are demolished with their host.
@MainActor
public final class DemolishTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.demolish
    public let title = "Demolish"
    /// The phase elements are demolished in: the view's phase, else the latest phase.
    public var phaseID: ElementID? { ctx.viewData?.phaseID ?? ctx.model.latestPhase?.id }

    func target(_ i: ToolInput) -> Element? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            if let e = ctx.model[id], ElementOperations.isDemolishable(e) { return e }
        }
        return nil
    }
    public var prompt: String {
        guard let p = phaseID, let name = ctx.model[p]?.name else { return "This project has no phases. Add one in Manage ▸ Phases." }
        return "Click elements to demolish them in the phase “\(name)”."
    }
    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard phaseID != nil, let e = target(i) else { preview.cursor = .notAllowed; return }
        preview.highlight = [e.id]
        preview.highlight.formUnion(ctx.model.hosted(by: e.id).filter { $0.insert != nil || $0.railing != nil }.map(\.id))
        preview.cursor = .pick
    }
    public func pointerDown(_ i: ToolInput) {
        guard let phase = phaseID else { message("This project has no phases. Add one in Manage ▸ Phases."); return }
        guard let e = target(i) else { message("Click a model element to demolish."); return }
        var changed: [ElementID] = []
        ctx.session.perform("Demolish") { tx in changed = try ElementOperations.demolish([e.id], phase: phase, in: tx) }
        if let err = ctx.session.lastError { message(err.message) }
        else if changed.isEmpty { message("That \(e.category.singularName.lowercased()) is already demolished.") }
    }
    public func escape() -> EscapeResult { .exitTool }
}
