import Foundation
import ArcusGeometry

// W2-ANNOT: view-aware geometry shared by annotation tools, grips and graphics.

/// Where annotations attach in a view. Plans (and drafting views and sheets) use plan coordinates directly. Sections
/// and elevations use (u, z): the distance along the view's right vector and the elevation, so a wall face, grid or
/// column that runs across the view shows as a vertical line at its station and a level as a horizontal line.
public enum AnnotationGeometry {
    /// The view an annotation belongs to (its owner view), or the given one.
    public static func view(of e: Element, _ model: BIMModel, fallback: Element? = nil) -> Element? {
        fallback ?? model[e.ownerViewID]
    }

    static func verticalFrame(_ view: Element?) -> VerticalGraphics.Frame? {
        guard let vd = view?.view, vd.kind.isVerticalCut else { return nil }
        return VerticalGraphics.frame(vd)
    }

    /// True when the view shows (u, z) coordinates.
    public static func isVertical(_ view: Element?) -> Bool { verticalFrame(view) != nil }

    /// A plan point in the view's coordinates at elevation `z` (identity in plans).
    public static func viewPoint(_ p: Vec2, z: Double, view: Element?) -> Vec2 {
        guard let f = verticalFrame(view) else { return p }
        return Vec2(f.u(p), z)
    }

    // MARK: References

    /// Resolves a dimension reference in a view: a line (point and direction) or a point. In sections and elevations
    /// plan references become vertical lines at their station along the view; levels are horizontal lines.
    public static func resolve(_ r: GeometryReference, _ model: BIMModel, view: Element?) -> (point: Vec2, direction: Vec2?)? {
        guard let f = verticalFrame(view) else { return DimensionQueries.resolve(r, model) }
        if r.kind == .point { return r.point.map { ($0, nil) } }
        guard let e = model[r.elementID] else { return r.point.map { ($0, nil) } }
        if case .level(let l) = e.data { return (Vec2(0, l.elevation), Vec2(1, 0)) }
        if let rp = e.referencePlane, FurniturePlanes.isHorizontal(rp), let z = FurniturePlanes.position(rp) { return (Vec2(0, z), Vec2(1, 0)) } // FM3
        guard let plan = DimensionQueries.resolve(r, model) else { return nil }
        // A plan line parallel to the view plane has no station of its own: it can't be dimensioned across the view.
        if let d = plan.direction, abs(d.dot(f.right)) > 0.999 { return nil }
        let z = ElementMeshes.bounds(e, model).center.z
        return (Vec2(f.u(plan.point), z.isFinite ? z : 0), Vec2(0, 1))
    }

    /// The point a witness line starts from: on the reference line, as near as possible to where it was picked.
    public static func anchor(_ r: GeometryReference, fallback: Vec2?, _ model: BIMModel, view: Element?) -> Vec2? {
        guard let res = resolve(r, model, view: view) else { return nil }
        guard let d = res.direction, let f = fallback, d.lengthSquared > 0 else { return res.point }
        let n = d.normalized
        return res.point + n * (f - res.point).dot(n)
    }

    /// Witness points of a dimension (unresolvable references use their cached points).
    public static func points(_ d: DimensionData, _ model: BIMModel, view: Element?) -> [Vec2] {
        d.references.enumerated().map { i, r in
            let fb = i < d.fallbackPoints.count ? d.fallbackPoints[i] : nil
            return anchor(r, fallback: fb, model, view: view) ?? fb ?? d.linePoint
        }
    }

    /// Direction a linear or aligned dimension measures along.
    public static func measurementDirection(_ d: DimensionData, _ pts: [Vec2], _ model: BIMModel, view: Element?) -> Vec2 {
        if let a = d.direction { return Vec2.fromAngle(a) }
        if let first = d.references.first, let r = resolve(first, model, view: view), let dir = r.direction, dir.lengthSquared > 0 {
            return dir.perpendicular.normalized
        }
        guard pts.count >= 2 else { return .unitX }
        let v = pts[1] - pts[0]
        return v.lengthSquared > 0 ? v.normalized : .unitX
    }

    /// Measured values between consecutive references of a linear or aligned dimension in its view.
    public static func measure(_ e: Element, _ model: BIMModel) -> [Double] {
        guard let d = e.dimension, d.kind == .linear || d.kind == .aligned else { return DimensionQueries.measure(e, model) }
        let view = model[e.ownerViewID]
        let pts = points(d, model, view: view)
        guard pts.count >= 2 else { return [] }
        let n = measurementDirection(d, pts, model, view: view)
        return (0..<(pts.count - 1)).map { abs((pts[$0 + 1] - pts[$0]).dot(n)) }
    }

    // MARK: Tags

    /// Where a tag's leader points on an element in a view (plans: the element's plan anchor; sections and
    /// elevations: its station at mid-height).
    public static func leaderAnchor(_ e: Element, _ model: BIMModel, view: Element?) -> Vec2? {
        guard let f = verticalFrame(view) else { return planAnchor(e, model) }
        let b = ElementMeshes.bounds(e, model)
        if !b.isEmpty { return Vec2(f.u(b.center.xy), b.center.z) }
        return planAnchor(e, model).map { Vec2(f.u($0), model.baseElevation(of: e)) }
    }

    /// Plan anchor of taggable elements (as `AnnotationRenderer.leaderAnchor`, extended to more categories).
    public static func planAnchor(_ e: Element, _ model: BIMModel) -> Vec2? {
        if let p = AnnotationRenderer.leaderAnchor(e, model) { return p }
        switch e.data {
        case .slab(let s): return (try? s.boundary.profile().get())?.outer.centroid
        case .roof: return RoofGeometry.footprint(e)?.polygon.centroid
        case .beam(let b): return b.curve.midpoint
        case .stair: return StairGeometry.layout(e, model).flatMap { l in l.runs.first.map { l.runRect($0).centroid } }
        case .railing(let r): return r.path.isEmpty ? nil : r.path[r.path.count / 2].midpoint
        case .ramp: return RampGeometry.layout(e, model)?.pieces.first?.polygon.centroid
        default:
            let b = ElementMeshes.bounds(e, model)
            return b.isEmpty ? nil : b.center.xy
        }
    }
}
