import Foundation
import ArcusGeometry
import ArcusDomain

/// Drawing and moving in 3D views on a level work plane (W2-3D).
///
/// Tools are plan state machines. A 3D view drives the same tool instances through the floor-plan `ToolContext` of the
/// work-plane level: the pointer ray is intersected with the horizontal plane at the level's elevation (or, for tools
/// that pick a host face, the picked surface point is used), the plan point is snapped with the plan's snap index, and
/// the plan elements under that point are offered as hit candidates after the element the GPU picked.
public enum WorkPlane3D {
    /// Where a ray meets the horizontal plane `z = planeZ`; nil when the ray is parallel to it or points away.
    public static func intersect(origin: Vec3, direction: Vec3, planeZ: Double) -> Vec3? {
        guard abs(direction.z) > 1e-9 else { return nil }
        let t = (planeZ - origin.z) / direction.z
        guard t > 0, t.isFinite else { return nil }
        return origin + direction * t
    }

    /// The plan view tools use for a level: its floor plan (not a dependent view), else any other plan of it.
    public static func planView(forLevel level: ElementID, in model: BIMModel) -> ElementID? {
        let plans = model.views.filter { $0.levelID == level && ($0.view?.kind.isPlan ?? false) }
        func rank(_ e: Element) -> Int {
            guard let v = e.view else { return 9 }
            let kind = v.kind == .floorPlan ? 0 : v.kind == .structuralPlan ? 1 : v.kind == .ceilingPlan ? 2 : 3
            return kind * 2 + (v.parentViewID == nil ? 0 : 1)
        }
        return plans.min { (rank($0), $0.id.raw) < (rank($1), $1.id.raw) }?.id
    }

    /// Levels that can be work planes (they have a plan view), lowest first.
    public static func levels(in model: BIMModel) -> [Element] {
        model.levels.filter { planView(forLevel: $0.id, in: model) != nil }
    }

    /// The work plane a 3D view starts with: the level of the most recently active plan view, else the lowest level.
    /// - Parameter recentViews: views in the order they were active (oldest first).
    public static func defaultLevel(in model: BIMModel, recentViews: [ElementID]) -> ElementID? {
        for v in recentViews.reversed() {
            guard let e = model[v], e.view?.kind.isPlan == true, let l = e.levelID, planView(forLevel: l, in: model) != nil else { continue }
            return l
        }
        return levels(in: model).first?.id
    }

    /// The level whose plane a selection moves on: the level of `preferred` (the grabbed element) when it has one,
    /// else the first selected element with a level that has a plan.
    public static func level(of ids: [ElementID], preferred: ElementID? = nil, in model: BIMModel) -> ElementID? {
        for id in [preferred].compactMap({ $0 }) + ids {
            guard let e = model[id] else { continue }
            let l = e.levelID ?? e.ownerViewID.flatMap { model[$0]?.levelID }
            if let l, planView(forLevel: l, in: model) != nil { return l }
        }
        return nil
    }

    /// The part of a plan's display list that exists in 3D: model elements, datums (grids, levels, reference planes) and
    /// model lines. View markers, tags, dimensions, text and other annotations are left out, so a pointer on the work
    /// plane never snaps to (or picks) something that isn't drawn in the 3D view, e.g. an elevation marker's quadrant.
    public static func modelGraphics(_ g: ViewGraphics, model: BIMModel) -> ViewGraphics {
        let items = g.items.filter { item in
            guard item.targetViewID == nil else { return false }
            switch item.category.categoryClass {
            case .model, .datum: return true
            case .annotation:
                guard let e = item.elementID.flatMap({ model[$0] }) else { return false }
                return e.modelLine != nil && e.ownerViewID == nil
            case .view, .internal_: return false
            }
        }
        return ViewGraphics(viewID: g.viewID, scale: g.scale, items: items, extents: g.extents, crop: g.crop, modelRevision: g.modelRevision)
    }

    /// Selectable plan elements within `tolerance` of `p`, best first (lines and annotations over fills, then nearest).
    /// The same ranking as the 2D canvas, so Tab cycles through the same candidates.
    public static func hitCandidates(_ graphics: ViewGraphics, at p: Vec2, tolerance tol: Double, model: BIMModel,
                                     allows: (Element) -> Bool = { _ in true }) -> [ElementID] {
        let box = Rect2(center: p, halfSize: Vec2(tol, tol))
        var hits: [(ElementID, Int, Double)] = []
        for item in graphics.items where item.selectable && !item.bounds.isEmpty && item.bounds.intersects(box) {
            guard let id = item.elementID, let d = hitDistance(item, p, tol, scale: Double(max(graphics.scale, 1))) else { continue }
            if let e = model[id], !allows(e) { continue }
            hits.append((id, item.layer.rawValue, d))
        }
        let sorted = hits.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
        var seen = Set<ElementID>()
        return sorted.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
    }

    static func hitDistance(_ item: GItem, _ p: Vec2, _ tol: Double, scale: Double) -> Double? {
        var best: Double?
        func take(_ d: Double) { if d <= tol { best = min(best ?? d, d) } }
        for prim in item.primitives {
            switch prim {
            case .polyline(let pts, let closed, _):
                let n = closed ? pts.count : pts.count - 1
                guard n > 0 else { continue }
                for i in 0..<n { take(Segment2(pts[i], pts[(i + 1) % pts.count]).distance(to: p)) }
            case .arc(let a, _):
                take(a.closestPoint(to: p).distance(to: p))
            case .fill(let polys, _):
                if polys.contains(where: { $0.contains(p) }) { take(tol * 0.9) }
            case .text(let t):
                let h = t.height * scale
                let w = h * 0.6 * Double(max(1, t.string.split(separator: "\n").map(\.count).max() ?? 1))
                if Rect2(center: t.position, halfSize: Vec2(w, h * 1.2)).contains(p) { take(tol * 0.8) }
            }
        }
        for poly in item.hitPolygons where poly.contains(p) { take(tol * 0.95) }
        return best
    }

    /// A 3D pointer sample: the ray through the pointer and what the GPU pick found under it.
    public struct PointerSample: Sendable {
        public var origin: Vec3
        public var direction: Vec3
        public var pickedID: ElementID?
        public var pickedPoint: Vec3?
        public var shift = false, command = false, option = false
        public var clickCount = 1
        public init(origin: Vec3, direction: Vec3, pickedID: ElementID? = nil, pickedPoint: Vec3? = nil) {
            self.origin = origin; self.direction = direction; self.pickedID = pickedID; self.pickedPoint = pickedPoint
        }
    }

    /// The plan point a sample maps to on the plane `z = planeZ`. With `preferSurface` (doors, windows, split …) a
    /// picked surface point wins, so a door follows the wall face under the pointer rather than the floor behind it.
    /// Falls back to the picked point when the ray misses the plane (looking level or up at it).
    public static func planPoint(_ s: PointerSample, planeZ: Double, preferSurface: Bool = false) -> Vec3? {
        if preferSurface, s.pickedID != nil, let q = s.pickedPoint { return Vec3(q.x, q.y, planeZ) }
        if let q = intersect(origin: s.origin, direction: s.direction, planeZ: planeZ) { return q }
        return s.pickedPoint.map { Vec3($0.x, $0.y, planeZ) }
    }

    /// Builds the `ToolInput` a plan tool receives for a 3D pointer sample: plan point on the work plane, snapped with
    /// the plan context (`ctx.pixel` must already be the world size of a screen point at that depth), with the picked
    /// element first among the hit candidates.
    @MainActor
    public static func toolInput(_ s: PointerSample, planeZ: Double, ctx: ToolContext, graphics: ViewGraphics?, snapFrom: Vec2?,
                                 preferSurface: Bool = false, orthoOnly: Bool = false, constrainOrtho: Bool = false) -> ToolInput? {
        guard let q = planPoint(s, planeZ: planeZ, preferSurface: preferSurface) else { return nil }
        let raw = q.xy
        let (pt, snap) = ctx.snap(raw, from: snapFrom, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
        var i = ToolInput(point: pt, rawPoint: raw, snap: snap)
        i.shift = s.shift; i.command = s.command; i.option = s.option; i.clickCount = s.clickCount
        var hits: [ElementID] = []
        if let id = s.pickedID, let e = ctx.model[id], ctx.session.selection.allows(e) { hits.append(id) }
        if let g = graphics {
            for id in hitCandidates(g, at: raw, tolerance: ctx.pixel * 5, model: ctx.model, allows: { ctx.session.selection.allows($0) }) where !hits.contains(id) {
                hits.append(id)
            }
        }
        i.hit = hits.first
        i.hitCandidates = hits
        return i
    }

    /// Screen-relative nudge in a 3D view: the arrow's screen direction projected on the plan and squared to the
    /// nearer world axis, `step` long. `dx`/`dy` are −1, 0 or 1 (right and up positive).
    public static func nudge(dx: Int, dy: Int, cameraRight: Vec3, cameraUp: Vec3, cameraForward: Vec3, step: Double) -> Vec2 {
        // Screen up on the plan: the camera's up for steep views, its forward for flatter ones (whichever is longer on plan).
        let upOnPlan = cameraUp.xy.length >= cameraForward.xy.length ? cameraUp.xy : cameraForward.xy
        let d = cameraRight.xy.normalized * Double(dx) + upOnPlan.normalized * Double(dy)
        guard d.length > 1e-9 else { return .zero }
        let axis = abs(d.x) >= abs(d.y) ? Vec2(d.x >= 0 ? 1 : -1, 0) : Vec2(0, d.y >= 0 ? 1 : -1)
        return axis * step
    }
}
