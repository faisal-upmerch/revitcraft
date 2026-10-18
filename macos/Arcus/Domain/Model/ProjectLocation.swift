import Foundation
import ArcusGeometry

// F11: Manage ▸ Project Location ▸ Coordinates and Position (RevitCraft rc-core model.rs `to_shared`, `relocate`,
// `specify_shared`; edit.rs `rotate_project`, `mirror_project`, `transform_views`).

/// A point in shared (survey) coordinates.
public struct SharedPoint: Hashable, Sendable {
    public var northSouth: Double
    public var eastWest: Double
    public var elevation: Double
    public init(northSouth: Double, eastWest: Double, elevation: Double) { self.northSouth = northSouth; self.eastWest = eastWest; self.elevation = elevation }
}

/// Shared coordinates: the survey point (internal position) reads (`surveyNorthing`, `surveyEasting`,
/// `surveyElevation`) and true north lies `trueNorthAngle` counter-clockwise from project north.
public enum SharedCoordinates {
    /// Directions of true north and east in project coordinates.
    static func axes(_ info: ProjectInfoData) -> (north: Vec2, east: Vec2) {
        let a = info.trueNorthAngle
        return (Vec2(-sin(a), cos(a)), Vec2(cos(a), sin(a)))
    }

    /// A project point in shared coordinates.
    public static func shared(_ p: Vec3, _ info: ProjectInfoData) -> SharedPoint {
        let (n, e) = axes(info)
        let d = p.xy - info.surveyPoint.xy
        return SharedPoint(northSouth: info.surveyNorthing + d.dot(n), eastWest: info.surveyEasting + d.dot(e),
                           elevation: info.surveyElevation + p.z - info.surveyPoint.z)
    }

    /// Specify Coordinates at Point: sets the shared coordinates so the project point `p` reads `value`, with true
    /// north `angle` (radians, counter-clockwise from project north). The survey point keeps its place in the model.
    public static func specify(at p: Vec3, reads value: SharedPoint, trueNorth angle: Double, _ info: inout ProjectInfoData) {
        info.trueNorthAngle = angle
        info.surveyNorthing = 0; info.surveyEasting = 0; info.surveyElevation = 0
        let now = shared(p, info)
        info.surveyNorthing = value.northSouth - now.northSouth
        info.surveyEasting = value.eastWest - now.eastWest
        info.surveyElevation = value.elevation - now.elevation
    }

    /// Relocate Project: the project moves by `delta` (project directions) against the shared coordinates, so every
    /// point now reads the shared position `delta` away from it.
    public static func relocate(by delta: Vec2, _ info: inout ProjectInfoData) {
        let (n, e) = axes(info)
        info.surveyNorthing += delta.dot(n)
        info.surveyEasting += delta.dot(e)
    }

    /// "N/S 12.000 m, E/W 3.500 m, Elev 0.000 m" in project units.
    public static func report(_ p: SharedPoint, _ model: BIMModel) -> String {
        func f(_ v: Double) -> String { Parameters.format(.double(v), type: .length, model: model) }
        return "N/S \(f(p.northSouth)), E/W \(f(p.eastWest)), Elev \(f(p.elevation))"
    }
}

/// Rotate Project North and Mirror Project: the whole project — model, plan annotations, view crops, section and
/// elevation planes, 3D cameras and section boxes, the base and survey points — turns or flips about the internal
/// origin. Rotating turns true north back so the site stays where it is. Pins don't stop a project-wide move.
public enum ProjectPosition {
    /// Rotate Project North: `degrees` counter-clockwise (RevitCraft offers 90° clockwise, 90° counter-clockwise, 180°).
    public static func rotate(degrees: Double, in tx: TransactionContext) {
        let t = Transform2.rotation(Angle.radians(degrees))
        transformProject(t, in: tx)
        tx.updateManageInfo { $0.trueNorthAngle = Angle.normalize($0.trueNorthAngle - Angle.radians(degrees)) }
    }

    /// Mirror Project about the north-south axis (x flips) or the east-west axis (y flips) through the origin.
    public static func mirror(northSouth: Bool, in tx: TransactionContext) {
        let t = northSouth ? Transform2.scale(-1, 1) : Transform2.scale(1, -1)
        transformProject(t, in: tx)
    }

    static func transformProject(_ t: Transform2, in tx: TransactionContext) {
        let m = tx.model
        let mirror = t.isMirroring
        let flipAlong = Transform2.scale(-1, 1)
        for e in m.allElements {
            if let v = e.view { tx.update(e.id) { $0.view = transformed(v, t) }; continue }
            guard ElementTransform.isTransformable(e) else { continue }
            if let owner = e.ownerViewID, let ov = m[owner] {
                // Plan annotations live in model XY; annotations of sections and elevations in (along, up), which a
                // mirror reverses; sheets, drafting views and legends don't move.
                if let k = ov.view?.kind, k.isPlan { tx.update(e.id) { ElementTransform.apply(t, to: &$0) } }
                else if let k = ov.view?.kind, k.isVerticalCut, mirror { tx.update(e.id) { ElementTransform.apply(flipAlong, to: &$0) } }
                continue
            }
            tx.update(e.id) { ElementTransform.apply(t, to: &$0) }
            // Grids' per-view 2D ends (points) and bubble elbows (offsets) turn with their view.
            if let extents = e.grid?.viewExtents {
                tx.update(e.id) { el in
                    el.grid?.viewExtents = extents.map { x in
                        let k = m[x.viewID]?.view?.kind
                        let f: Transform2? = k?.isPlan == true ? t : (k?.isVerticalCut == true && mirror ? flipAlong : nil)
                        guard let f else { return x }
                        var y = x
                        y.start = x.start.map(f.apply); y.end = x.end.map(f.apply)
                        y.elbowStart = x.elbowStart.map(f.applyVector); y.elbowEnd = x.elbowEnd.map(f.applyVector)
                        return y
                    }
                }
            }
        }
        tx.updateManageInfo { info in
            info.projectBasePoint = Vec3(t.apply(info.projectBasePoint.xy), z: info.projectBasePoint.z)
            info.surveyPoint = Vec3(t.apply(info.surveyPoint.xy), z: info.surveyPoint.z)
        }
    }

    static func transformed(_ v: ViewData, _ t: Transform2) -> ViewData {
        var v = v
        let mirror = t.isMirroring
        if v.kind.isPlan, let c = v.cropRegion { v.cropRegion = Rect2(points: c.corners.map(t.apply)) }
        if v.kind.isVerticalCut, mirror, let c = v.cropRegion { v.cropRegion = Rect2(min: Vec2(-c.max.x, c.min.y), max: Vec2(-c.min.x, c.max.y)) }
        if let o = v.planeOrigin { v.planeOrigin = Vec3(t.apply(o.xy), z: o.z) }
        if let d = v.viewDirection { v.viewDirection = t.applyVector(d).normalized }
        if let p = v.markerPosition { v.markerPosition = t.apply(p) }
        if var c = v.camera {
            c.eye = Vec3(t.apply(c.eye.xy), z: c.eye.z)
            c.target = Vec3(t.apply(c.target.xy), z: c.target.z)
            c.up = Vec3(t.applyVector(c.up.xy), z: c.up.z)
            v.camera = c
        }
        if let b = v.sectionBox, b.min.x.isFinite {
            let corners = [Vec2(b.min.x, b.min.y), Vec2(b.max.x, b.min.y), Vec2(b.max.x, b.max.y), Vec2(b.min.x, b.max.y)].map(t.apply)
            let r = Rect2(points: corners)
            v.sectionBox = Box3(min: Vec3(r.min, z: b.min.z), max: Vec3(r.max, z: b.max.z))
        }
        return v
    }
}

extension TransactionContext {
    /// Edits Project Information (location fields) in place.
    func updateManageInfo(_ change: (inout ProjectInfoData) -> Void) {
        guard let pid = model.projectInfoElement?.id else { return }
        update(pid) { e in
            guard var info = e.projectInfo else { return }
            change(&info)
            e.projectInfo = info
        }
    }
}
