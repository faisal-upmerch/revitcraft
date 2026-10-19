import Foundation
import ArcusGeometry
import ArcusDomain

// FM3D: Edit Sketch of an extrusion (Revit's Edit Extrusion): its profile and holes are sketched again on its own work
// plane, with its Depth and Start as they are; Finish replaces them, keeping the form's material, visibility and locks.
// It runs in the plan or elevation that sees the sketch plane, or in 3D on that plane.

public enum FurnitureFormEdit {
    /// The 3D placement an extrusion is sketched on: its profile's plane at its start, in the view that sees it.
    public static func placement(_ e: Element, _ m: BIMModel) -> FurniturePlacement3D? {
        guard let f = e.furnitureForm, f.kind == .extrusion else { return nil }
        let axis = f.plane.axes.w
        var at = Vec3.zero
        switch axis { case .x: at.x = f.w0; case .y: at.y = f.w0; case .z: at.z = f.w0 }
        if axis == .z {
            guard let host = FurniturePlacements.planHost(m) else { return nil }
            return FurniturePlacements.placement(host: host, through: at, normal: .unitZ, m)
        }
        let n = -FurniturePlacements.unit(axis)
        guard let host = FurniturePlacements.verticalHost(normal: n, m, square: true) ?? FurniturePlacements.verticalHost(normal: -n, m, square: true) else { return nil }
        return FurniturePlacements.placement(host: host, through: at, normal: n, m)
    }

    /// The sketch that edits `e` in the view of `ctx` (which must see the extrusion's sketch plane).
    @MainActor public static func tool(_ ctx: ToolContext, _ e: Element) -> SketchTool? {
        guard let f = e.furnitureForm, f.kind == .extrusion, let map = FurnitureSketchMap.of(ctx.viewData), map.plane == f.plane else { return nil }
        let t = SketchTool(ctx: ctx, target: .fm4(.form(.extrusion, isVoid: f.isVoid)), commandID: f.isVoid ? .furnitureVoidExtrusion : .furnitureExtrusion, editing: e.id)
        t.drawMode = .line
        let loops = [f.profile] + f.holes
        t.curves = loops.flatMap { loop in Polygon2(loop.map(map.toView)).edges.map { Curve2.line($0) } }
        // Start and Depth that give the form's ends back on Finish (fm4Commit's rule for this view).
        let w = t.fm4WorkPlane
        let sign = t.fm3dExtrusionSign(map)
        if sign > 0 { t.fm4.start = f.w0 - w; t.fm4.end = f.w1 - w } else { t.fm4.start = w - f.w1; t.fm4.end = w - f.w0 }
        return t
    }
}

extension SketchTool {
    /// The sign fm4Commit gives an extrusion's Start and Depth in this view: up in plans (out of a picked face in
    /// 3D), into the view in elevations.
    func fm3dExtrusionSign(_ map: FurnitureSketchMap) -> Double {
        if let s = ctx.furniture3D?.extrusionSign { return s }
        if map.plane == .xy { return 1 }
        return (map.plane == .xz ? map.forward.y : map.forward.x) > 0 ? 1 : -1
    }

    /// Finish of Edit Sketch: the edited extrusion takes the new profile, holes and ends. True when handled.
    func fm3dUpdateExtrusion(_ f: FurnitureFormData) -> Bool {
        guard let id = editingID, ctx.model[id]?.furnitureForm?.kind == .extrusion else { return false }
        ctx.session.perform("Edit Extrusion") { tx in
            tx.update(id) { e in
                guard var d = e.furnitureForm else { return }
                d.profile = f.profile; d.holes = f.holes; d.w0 = f.w0; d.w1 = f.w1
                e.furnitureForm = d
            }
        }
        if let err = ctx.session.lastError { message(err.message) } else { keepSelected(id) }
        return true
    }
}
