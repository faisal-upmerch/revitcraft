import Foundation
import ArcusGeometry
import ArcusDomain

/// F2: Work Plane ▸ Set ▸ Pick a plane: click a reference plane (or, in sections and elevations, a level) and it
/// becomes the view's work plane.
@MainActor
public final class WorkPlanePickTool: BaseTool, InteractiveTool {
    public var commandID: CommandID { .workPlaneSet }
    public var title: String { "Work Plane" }
    /// S3D2: the view whose work plane is set (a 3D view runs this tool in a plan context); nil = the tool's view.
    public var targetViewID: ElementID?
    public var prompt: String { ctx.isPlan ? "Pick a reference plane to be the work plane." : "Pick a reference plane or a level to be the work plane." }

    func plane(_ i: ToolInput) -> WorkPlaneRef? {
        let ids = i.hitCandidates.isEmpty ? (i.hit.map { [$0] } ?? []) : i.hitCandidates
        for id in ids {
            guard let e = ctx.model[id] else { continue }
            if e.referencePlane != nil { return .referencePlane(id) }
            if e.level != nil, !ctx.isPlan { return .level(id) }
        }
        // S3D2: in a 3D view, the face under the pointer.
        if let p = i.surfacePoint, let id = i.hit, let e = ctx.model[id], e.category.isModel, let f = FacePlanes.frame(of: e, at: p, ctx.model) {
            return .face(id, f)
        }
        return nil
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        switch plane(i) {
        case .referencePlane(let id)?, .level(let id)?, .face(let id, _)?: preview.highlight = [id]; preview.cursor = .pick
        case nil: preview.cursor = .notAllowed
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let w = plane(i) else { message(prompt); return }
        WorkPlanes.set(w, on: targetViewID ?? ctx.viewID, in: ctx.session)
        message("Work plane: \(WorkPlanes.name(w, ctx.model)).")
        ctx.toolFinished?()
    }

    public func escape() -> EscapeResult { .exitTool }
}

extension WorkPlanes {
    /// Sets a view's work plane (one undo step).
    @MainActor public static func set(_ w: WorkPlaneRef?, on viewID: ElementID, in session: DocumentSession) {
        guard session.model[viewID]?.view?.workPlane != w else { return }
        session.perform("Set Work Plane") { tx in tx.update(viewID) { $0.view?.workPlane = w } }
    }

    /// Work Plane ▸ Show: toggles the view's work plane grid (one undo step).
    @MainActor public static func toggleShown(_ viewID: ElementID, in session: DocumentSession) {
        let on = session.model[viewID]?.view?.showsWorkPlane ?? false
        session.perform(on ? "Hide Work Plane" : "Show Work Plane") { tx in tx.update(viewID) { $0.view?.showsWorkPlane = on ? nil : true } }
    }
}
