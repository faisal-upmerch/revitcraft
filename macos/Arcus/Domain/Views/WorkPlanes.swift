import Foundation
import ArcusGeometry

// F2: work planes (RevitCraft `WorkPlaneRef`, the Work Plane dialog, `paint_work_plane_grid`, Work Plane ▸ Viewer).

/// A view's work plane: a level (horizontal) or a reference plane (vertical, through its plan line).
public enum WorkPlaneRef: Hashable, Codable, Sendable {
    case level(ElementID)
    case referencePlane(ElementID)
    /// S3D2: a face picked in a 3D view (the element it lies on, and the plane as picked).
    case face(ElementID, WorkPlaneFrame)
}

/// A work plane in model space: an origin and two in-plane unit axes (`u` horizontal, `v` up the plane), the normal
/// `u × v`. A level's plane is horizontal (`v` = +Y); a reference plane's is vertical (`v` = +Z).
public struct WorkPlaneFrame: Hashable, Codable, Sendable {
    public var origin: Vec3
    public var u: Vec3
    public var v: Vec3
    public var normal: Vec3 { u.cross(v).normalized }
    public var isHorizontal: Bool { abs(normal.z) > 0.999 }
    public func point(_ a: Double, _ b: Double) -> Vec3 { origin + u * a + v * b }
    public init(origin: Vec3, u: Vec3, v: Vec3) { self.origin = origin; self.u = u; self.v = v }
}

public enum WorkPlanes {
    /// Grid spacing of the shown work plane, as RevitCraft (3000 mm, or 10' in imperial projects).
    public static func spacing(_ model: BIMModel) -> Double { model.units.system == .imperial ? 3.048 : 3.0 }

    /// The work plane a view uses: the one set on it, else its default (a plan's level; nil for sections, elevations
    /// and 3D views, whose default is the view plane or the 3D tools' level).
    public static func current(_ view: Element, _ model: BIMModel) -> WorkPlaneRef? {
        if let w = view.view?.workPlane, isValid(w, model) { return w }
        if view.view?.kind.isPlan == true, let l = view.levelID { return .level(l) }
        return nil
    }

    public static func isValid(_ w: WorkPlaneRef, _ model: BIMModel) -> Bool {
        switch w {
        case .level(let id): model[id]?.level != nil
        case .referencePlane(let id): model[id]?.referencePlane != nil
        case .face(let id, _): model[id] != nil // S3D2
        }
    }

    /// "Level : Level 1", "Reference Plane : Center", as in RevitCraft's Work Plane dialog.
    public static func name(_ w: WorkPlaneRef?, _ model: BIMModel) -> String {
        switch w {
        case .level(let id)?: model[id].map { "Level : \($0.name)" } ?? "<not associated>"
        case .referencePlane(let id)?:
            model[id].map { "Reference Plane : \($0.name.isEmpty ? "(unnamed)" : $0.name)" } ?? "<not associated>"
        case .face(let id, _)?: model[id].map { "Face : \($0.category.singularName)\($0.name.isEmpty ? "" : " : \($0.name)")" } ?? "<not associated>" // S3D2
        case nil: "<not associated>"
        }
    }

    /// The planes the Name list offers: every level, then the named reference planes (lowest level first).
    public static func candidates(_ model: BIMModel) -> [WorkPlaneRef] {
        let levels = model.levels.sorted { ($0.level?.elevation ?? 0, $0.id.raw) < ($1.level?.elevation ?? 0, $1.id.raw) }.map { WorkPlaneRef.level($0.id) }
        let planes = model.elements(.referencePlanes).filter { !$0.name.isEmpty && $0.ownerViewID == nil }.sorted { $0.name < $1.name }.map { WorkPlaneRef.referencePlane($0.id) }
        return levels + planes
    }

    /// The plane in model space; nil when its element is gone.
    public static func frame(_ w: WorkPlaneRef, _ model: BIMModel) -> WorkPlaneFrame? {
        switch w {
        case .level(let id):
            guard let l = model[id]?.level else { return nil }
            return WorkPlaneFrame(origin: Vec3(0, 0, l.elevation), u: Vec3(1, 0, 0), v: Vec3(0, 1, 0))
        case .referencePlane(let id):
            return model[id]?.referencePlane?.frame // S3D2: vertical, or drawn on another work plane
        case .face(let id, let f): // S3D2
            return model[id] != nil ? f : nil
        }
    }

    /// The model's plan extents (walls, slabs, roofs, grids …) and height range, for sizing a shown plane.
    public static func modelBounds(_ model: BIMModel) -> Box3 {
        var b = Box3.empty
        for e in model.allElements where e.category.categoryClass == .model || e.grid != nil {
            let x = ElementMeshes.bounds(e, model)
            if !x.isEmpty { b.include(x) }
        }
        if b.isEmpty { b = Box3(min: Vec3(-10, -10, 0), max: Vec3(10, 10, 3)) }
        let zs = model.levels.compactMap { $0.level?.elevation }
        if let lo = zs.min(), let hi = zs.max() { b.include(Vec3(b.min.x, b.min.y, lo)); b.include(Vec3(b.max.x, b.max.y, hi)) }
        return b
    }

    /// The plane's rectangle in its own (u, v) coordinates: the model extents, two grid steps beyond, on grid lines.
    public static func extent(_ f: WorkPlaneFrame, _ model: BIMModel) -> Rect2 {
        let b = modelBounds(model)
        var r = Rect2.empty
        for c in b.corners { let d = c - f.origin; r.include(Vec2(d.dot(f.u), d.dot(f.v))) }
        let s = spacing(model)
        func snapDown(_ x: Double) -> Double { (x / s).rounded(.down) * s - s }
        func snapUp(_ x: Double) -> Double { (x / s).rounded(.up) * s + s }
        return Rect2(min: Vec2(snapDown(r.min.x), snapDown(r.min.y)), max: Vec2(snapUp(r.max.x), snapUp(r.max.y)))
    }

    /// Grid lines of the shown plane in its (u, v) coordinates (the border included).
    public static func gridLines(_ r: Rect2, spacing s: Double) -> [Segment2] {
        var out: [Segment2] = []
        var x = r.min.x
        while x <= r.max.x + 1e-6 { out.append(Segment2(Vec2(x, r.min.y), Vec2(x, r.max.y))); x += s }
        var y = r.min.y
        while y <= r.max.y + 1e-6 { out.append(Segment2(Vec2(r.min.x, y), Vec2(r.max.x, y))); y += s }
        return out
    }

    /// Id of the transient view the Work Plane Viewer shows for a reference plane (never in the model).
    public static let viewerViewID = ElementID(UInt64.max - 10)

    /// Work Plane ▸ Viewer: the view that looks straight at `w`: a level's floor plan, or a transient elevation facing
    /// a reference plane (from its normal side). nil when the plane is gone or the level has no plan.
    public static func viewerView(_ w: WorkPlaneRef, _ model: BIMModel) -> Element? {
        switch w {
        case .level(let l):
            let plans = model.views.filter { $0.levelID == l && ($0.view?.kind.isPlan ?? false) }
            return plans.first { $0.view?.kind == .floorPlan && $0.view?.parentViewID == nil } ?? plans.first
        case .referencePlane, .face: // S3D2: any vertical plane
            guard let f = frame(w, model), abs(f.normal.z) < 1e-6 else { return nil }
            var line = Segment2(f.origin.xy, f.origin.xy + f.u.xy)
            if case .referencePlane(let id) = w, let l = model[id]?.referencePlane?.line, l.length > Tolerance.length, model[id]?.referencePlane?.plane3D == nil { line = l }
            var v = ViewData(kind: .elevation, scale: 100)
            let n = f.normal.xy.normalized
            // Stand back on the normal side, looking straight at the plane, deep enough to see the whole model.
            let b = modelBounds(model)
            let back = max(b.diagonal, 10)
            v.planeOrigin = Vec3(line.midpoint + n * back, z: b.min.z)
            v.viewDirection = n * -1
            v.farClip = back * 2
            return Element(id: viewerViewID, category: .views, name: "Workplane Viewer", data: .view(v))
        }
    }

    static let fillColor = RGBColor(110.0 / 255, 170.0 / 255, 235.0 / 255)
    static let lineColor = RGBColor(80.0 / 255, 150.0 / 255, 230.0 / 255)
    static let borderColor = RGBColor(60.0 / 255, 130.0 / 255, 220.0 / 255)

    /// Work Plane ▸ Show in a plan, section or elevation: as RevitCraft, a translucent plane with dashed grid lines and
    /// a solid border where the plane lies in the view; a heavy line where the view sees it edge-on.
    static func shownItems(_ builder: ViewGraphicsBuilder, extents: Rect2) -> [GItem] {
        guard builder.data.showsWorkPlane == true else { return [] }
        let model = builder.model
        let view = builder.view
        let wp = current(view, model)
        let fill = GFill(pattern: .solid, color: fillColor, transparency: 0.85)
        let dashed = GStroke(weight: 1, color: lineColor, pattern: .dash)
        let border = GStroke(weight: 2, color: borderColor)
        let s = spacing(model)
        func plane(_ r: Rect2, _ map: (Vec2) -> Vec2) -> GItem {
            var prims: [GPrimitive] = [.fill([Polygon2(r.corners.map(map))], fill)]
            for g in gridLines(r, spacing: s) { prims.append(.polyline([map(g.start), map(g.end)], closed: false, dashed)) }
            prims.append(.polyline(r.corners.map(map), closed: true, border))
            return GItem(elementID: nil, category: .views, layer: .underlay, primitives: prims, selectable: false)
        }
        let d = builder.data
        if d.kind.isPlan {
            guard let wp, let f = frame(wp, model) else { return [] }
            if f.isHorizontal { return [plane(extent(f, model), { Vec2($0.x + f.origin.x, $0.y + f.origin.y) })] }
            // A vertical plane seen from above: its trace across the model.
            let r = extent(f, model)
            let a = f.origin.xy + f.u.xy * r.min.x, b = f.origin.xy + f.u.xy * r.max.x
            return [GItem(elementID: nil, category: .views, layer: .underlay, primitives: [.polyline([a, b], closed: false, border)], selectable: false)]
        }
        guard d.kind.isVerticalCut, let o = d.planeOrigin, let fwd = d.viewDirection?.normalized, let right = d.rightVector else { return [] }
        let viewPlane = WorkPlaneFrame(origin: o, u: Vec3(right.x, right.y, 0), v: Vec3(0, 0, 1))
        let f = wp.flatMap { frame($0, model) } ?? viewPlane
        func toView(_ p: Vec3) -> Vec2 { Vec2((p.xy - o.xy).dot(right), p.z) }
        if f.isHorizontal {
            let r = extent(viewPlane, model)
            return [GItem(elementID: nil, category: .views, layer: .underlay,
                          primitives: [.polyline([Vec2(r.min.x, f.origin.z), Vec2(r.max.x, f.origin.z)], closed: false, border)], selectable: false)]
        }
        if abs(f.normal.xy.cross(fwd)) < 1e-3 {
            // Parallel to the view: the plane itself, in the view's (along, up) coordinates.
            let r = extent(f, model)
            return [plane(r, { toView(f.point($0.x, $0.y)) })]
        }
        // Seen edge-on: where it crosses the view plane.
        let trace = Segment2(f.origin.xy, f.origin.xy + f.u.xy)
        guard let hit = trace.lineIntersection(Segment2(o.xy, o.xy + right)) else { return [] }
        let u = (hit.point - o.xy).dot(right), b = modelBounds(model)
        return [GItem(elementID: nil, category: .views, layer: .underlay,
                      primitives: [.polyline([Vec2(u, b.min.z), Vec2(u, b.max.z)], closed: false, border)], selectable: false)]
    }
}
