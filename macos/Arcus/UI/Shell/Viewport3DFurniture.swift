import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// FM3D: Furniture tools in a 3D view's tool controller. A tool whose context has a 3D placement draws on that plane
// (snapping in it and to the model, as S3D2's work-plane tools) or, while it picks, takes the surface point under the
// pointer in its view's coordinates. Picking tools follow the face under the pointer (Place on Face): moving onto a face
// another view sees restarts the tool there, keeping its options. Options Bar ▸ Placement Plane ▸ Pick sets the work
// plane to the next face or reference plane clicked.

/// FM3D state of one 3D view's tool controller.
@MainActor
final class FM3DViewState {
    /// Options Bar ▸ Placement Plane ▸ Pick: the next click sets the work plane.
    var pickingPlane = false
    /// A press on a selected part, not yet a drag.
    var pending: (id: ElementID, grab: Vec3, flags: NSEvent.ModifierFlags, at: CGPoint)?
    enum Drag {
        /// A shape handle dragged to `value` (snapped to `snap`).
        case handle(FurnitureShapeHandle, value: Double, snap: FurnitureAxisSnap?)
        /// Parts slid in the plane of the face grabbed.
        case move(ids: [ElementID], grab: Vec3, normal: Vec3, box: Box3, move: Vec3, snaps: [(axis: FamilyAxis, snap: FurnitureAxisSnap)])
    }
    var drag: Drag?
    /// Shape handles drawn last (their screen triangles, for hit testing).
    var handleHits: [(handle: FurnitureShapeHandle, rect: CGRect)] = []
    var hoveredHandle: FurnitureShapeHandle?
    /// Temporary dimension labels drawn last (click one to type a distance).
    var dimLabels: [(dim: FurnitureTempDim3D, rect: CGRect)] = []
    var dimField: NSTextField?
    var dimEditing: FurnitureTempDim3D?
    /// Tab: the elements stacked under the pointer and the one preselected.
    var tab: (ids: [ElementID], index: Int, at: CGPoint)?
}

extension Viewport3DToolController {
    var fm3dDocument: Bool { state.model.isFurniture }

    // MARK: Tool input

    /// The input of a Furniture tool on its 3D placement (its drawing plane follows the tool's depth).
    func fm3dToolInput(_ event: NSEvent, at p: CGPoint, tool: any InteractiveTool) -> ToolInput? {
        guard let ctx = (tool as? BaseTool)?.ctx, let placement = ctx.furniture3D else { return nil }
        let t3 = tool as? any FurnitureTool3D
        let drawn = t3?.fm3dDepth.map { placement.atDepth($0) } ?? placement
        if ctx.sketchPlane?.frame != drawn.frame { ctx.sketchPlane = drawn.host }
        if t3?.fm3dPicks == true { return fm3dPickInput(event, at: p, ctx: ctx, frame: drawn.frame) }
        return sketchToolInput(event, at: p, tool: tool)
    }

    /// A pick: the surface point under the pointer (else where the ray meets the plane) in the tool's view coordinates.
    private func fm3dPickInput(_ event: NSEvent, at p: CGPoint, ctx: ToolContext, frame f: WorkPlaneFrame) -> ToolInput? {
        guard let v = viewport, let s = pointerSample(at: p, flags: event.modifierFlags, clickCount: event.type == .mouseMoved ? 1 : event.clickCount),
              let w = s.pickedPoint ?? f.intersect(origin: s.origin, direction: s.direction) else { return nil }
        ctx.pixel = max(v.worldPerPoint(at: w), 1e-6)
        let raw = f.local(w)
        planePoint = raw
        snapping3D.pick = nil
        var i = ToolInput(point: raw, rawPoint: raw)
        i.shift = s.shift; i.command = s.command; i.option = s.option; i.clickCount = s.clickCount
        if let id = s.pickedID, ctx.model[id] != nil { i.hit = id; i.hitCandidates = [id] }
        i.surfacePoint = s.pickedPoint
        return i
    }

    /// The outward normal of the face under a view point (facing the viewer), with the element and point.
    func fm3dFace(at p: CGPoint) -> (id: ElementID, point: Vec3, normal: Vec3)? {
        guard let v = viewport else { return nil }
        let hit = v.pick(at: p)
        guard let id = hit.id, let q = hit.position, let e = state.model[id], let f = FacePlanes.frame(of: e, at: q, state.model) else { return nil }
        var n = f.normal
        if n.dot(v.pointerRay(at: p).direction) > 0 { n = -n }
        return (id, q, n)
    }

    /// Place on Face: a picking tool follows the face under the pointer; a face another view sees restarts it there.
    func fm3dRetarget(at p: CGPoint) {
        guard let tool = state.activeTool, let ctx = (tool as? BaseTool)?.ctx, let placement = ctx.furniture3D,
              FurniturePlacements.need(tool.commandID) == .face, let t3 = tool as? any FurnitureTool3D, t3.fm3dPicks, !t3.fm3dBusy,
              let face = fm3dFace(at: p), let np = FurniturePlacements.face(face.normal, at: face.point, element: face.id, need: .face, state.model) else { return }
        if np.hostViewID == placement.hostViewID { ctx.furniture3D = np; return }
        CommandRouter(state: state).fm3dRestart(tool, on: np)
    }

    // MARK: Placement Plane ▸ Pick

    /// The work plane a click picks: a reference plane under the pointer, else the face.
    func fm3dPickedPlane(at p: CGPoint) -> WorkPlaneRef? {
        guard let v = viewport else { return nil }
        if let id = v.pick(at: p).id, state.model[id]?.referencePlane != nil { return .referencePlane(id) }
        guard let face = fm3dFace(at: p) else { return nil }
        return .face(face.id, FacePlanes.frame(normal: face.normal, origin: face.point))
    }

    /// Sets the view's work plane to the plane clicked and restarts the running tool on it.
    func fm3dFinishPickingPlane(at p: CGPoint) {
        fm3d.pickingPlane = false
        guard let w = fm3dPickedPlane(at: p) else { state.show("Click a face or a reference plane to draw on.", error: true); return }
        WorkPlanes.set(w, on: viewID, in: state.session)
        CommandRouter(state: state).fm3dWorkPlaneChanged()
        state.show("Work plane: \(WorkPlanes.name(w, state.model)).")
    }

    /// The tooltip while picking a plane.
    var fm3dTooltip: String? { fm3d.pickingPlane ? "Click a face or a reference plane to draw on." : nil }
}
