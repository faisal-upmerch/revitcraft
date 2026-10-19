import Foundation
import ArcusGeometry

extension VisibilityResolver {
    /// Categories that stay hidden unless the view turns them on (the project base point and survey point).
    public static let optInCategories: Set<Category> = [.projectBasePoint, .surveyPoint]

    /// The opt-in categories of a view of `kind`: 3D views also keep reference planes hidden until turned on, as in Revit.
    public static func optInCategories(for kind: ViewKind?) -> Set<Category> {
        kind == .threeD ? optInCategories.union([.referencePlanes]) : optInCategories
    }

    /// Whether a category without its own elements (cameras, base point, survey point) is shown in this view.
    public func categoryShown(_ c: Category) -> Bool {
        if temp.revealHidden { return true }
        if vg.hiddenCategories.contains(c) || temp.hiddenCategories.contains(c) { return false }
        if let iso = temp.isolatedCategories, !iso.contains(c) { return false }
        if VisibilityResolver.optInCategories(for: data.kind).contains(c) { return vg.shownOptInCategories?.contains(c) == true }
        return true
    }
}

extension VisibilityGraphics {
    /// Whether a view of `kind` shows a category, honouring opt-in categories (hidden until turned on).
    public func isCategoryVisible(_ c: Category, in kind: ViewKind? = nil) -> Bool {
        if VisibilityResolver.optInCategories(for: kind).contains(c) { return shownOptInCategories?.contains(c) == true && !hiddenCategories.contains(c) }
        return !hiddenCategories.contains(c)
    }

    /// Shows or hides a category, using the opt-in set for categories that are hidden by default.
    public mutating func setCategoryVisible(_ c: Category, _ visible: Bool, in kind: ViewKind? = nil) {
        if VisibilityResolver.optInCategories(for: kind).contains(c) {
            var s = shownOptInCategories ?? []
            if visible { s.insert(c); hiddenCategories.remove(c) } else { s.remove(c) }
            shownOptInCategories = s.isEmpty ? nil : s
        } else if visible {
            hiddenCategories.remove(c)
        } else {
            hiddenCategories.insert(c)
        }
    }
}

/// Plan-only graphics for scope boxes, perspective cameras and the project base point and survey point.
enum SitePlanGraphics {
    static func items(builder: ViewGraphicsBuilder) -> [GItem] {
        ScopeBoxes.planItems(builder: builder) + cameras(builder: builder) + coordinatePoints(builder: builder)
    }

    // MARK: Cameras

    /// Camera glyphs for perspective 3D views placed from this plan's level: a body at the eye, the view cone and the
    /// target. Selecting a glyph selects its 3D view; double-clicking opens it.
    static func cameras(builder: ViewGraphicsBuilder) -> [GItem] {
        guard builder.resolver.categoryShown(.cameras), let level = builder.view.levelID else { return [] }
        var items: [GItem] = []
        for v in builder.model.views where v.levelID == level {
            guard v.isCameraView, let cam = v.view?.camera else { continue } // W2-CAM: orthographic cameras too
            items.append(cameraItem(v, cam, builder: builder))
        }
        return items
    }

    static func cameraItem(_ v: Element, _ cam: Camera3D, builder: ViewGraphicsBuilder) -> GItem {
        let st = GStroke(weight: 1, color: RGBColor(0.20, 0.35, 0.65))
        let eye = cam.eye.xy, target = cam.target.xy
        var dir = target - eye
        if dir.lengthSquared < 1e-12 { dir = .unitY }
        let f = dir.normalized, s = f.perpendicular
        let len = max(dir.length, builder.paper(0.01))
        // W2-CAM: horizontal half-width of the frame at the target (frame aspect; parallel for orthographic cameras).
        let half = min(atan(tan(cam.fieldOfView / 2) * cam.frameAspect), 1.45)
        let spread = cam.isPerspective ? tan(half) * len : cam.orthoHeight * cam.frameAspect / 2
        let start = cam.isPerspective ? 0 : spread
        let l = builder.paper(0.004), w = builder.paper(0.0025)
        // Body behind the eye, lens triangle in front.
        let body = [eye - f * (l * 1.6) - s * w, eye - f * (l * 0.2) - s * w, eye - f * (l * 0.2) + s * w, eye - f * (l * 1.6) + s * w]
        let lens = [eye - f * (l * 0.2) - s * (w * 0.6), eye, eye - f * (l * 0.2) + s * (w * 0.6)]
        let cone = GStroke(weight: 1, color: st.color, pattern: .dash)
        let prims: [GPrimitive] = [
            .polyline(body, closed: true, st),
            .polyline(lens, closed: true, st),
            .polyline([eye + s * start, eye + f * len + s * spread], closed: false, cone),
            .polyline([eye - s * start, eye + f * len - s * spread], closed: false, cone),
            .polyline([eye + f * len - s * spread, eye + f * len + s * spread], closed: false, cone),
            .arc(Arc2(center: target, radius: builder.paper(0.0012), startAngle: 0, sweep: Angle.twoPi), st),
        ] + cameraFarClip(cam, eye: eye, f: f, s: s, half: half) // W2-CAM
        return GItem(elementID: v.id, category: .cameras, layer: .annotation, primitives: prims, targetViewID: v.id,
                     hitPolygons: [Polygon2(body)])
    }

    /// W2-CAM: the far clip plane as a line across the view cone, when it is on.
    static func cameraFarClip(_ cam: Camera3D, eye: Vec2, f: Vec2, s: Vec2, half: Double) -> [GPrimitive] {
        guard let far = cam.effectiveFarClip else { return [] }
        let d = far * cam.forward.xy.length
        guard d > 1e-6 else { return [] }
        let w = cam.isPerspective ? tan(half) * d : cam.orthoHeight * cam.frameAspect / 2
        return [.polyline([eye + f * d - s * w, eye + f * d + s * w], closed: false, GStroke(weight: 1, color: RGBColor(0.20, 0.35, 0.65), pattern: .dashDot))]
    }

    // MARK: Project base point and survey point

    static func coordinatePoints(builder: ViewGraphicsBuilder) -> [GItem] {
        let info = builder.model.projectInfo
        var items: [GItem] = []
        let r = builder.paper(0.003)
        if builder.resolver.categoryShown(.projectBasePoint) {
            let st = GStroke(weight: 1, color: RGBColor(0.10, 0.30, 0.75))
            let c = info.projectBasePoint.xy
            let d = r * 0.7071
            items.append(GItem(elementID: nil, category: .projectBasePoint, layer: .annotation, primitives: [
                .arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), st),
                .polyline([c - Vec2(d, d), c + Vec2(d, d)], closed: false, st),
                .polyline([c - Vec2(d, -d), c + Vec2(d, -d)], closed: false, st),
                .text(GText(position: c + Vec2(r * 1.4, -r * 1.4), height: 0.0018, string: "Project Base Point", color: st.color)),
            ], selectable: false))
        }
        if builder.resolver.categoryShown(.surveyPoint) {
            let st = GStroke(weight: 1, color: RGBColor(0.10, 0.50, 0.30))
            let c = info.surveyPoint.xy
            let tri = [c + Vec2(0, r), c + Vec2(-r * 0.866, -r * 0.5), c + Vec2(r * 0.866, -r * 0.5)]
            items.append(GItem(elementID: nil, category: .surveyPoint, layer: .annotation, primitives: [
                .polyline(tri, closed: true, st),
                .polyline([c - Vec2(r * 0.5, 0), c + Vec2(r * 0.5, 0)], closed: false, st),
                .polyline([c - Vec2(0, r * 0.5), c + Vec2(0, r * 0.5)], closed: false, st),
                .text(GText(position: c + Vec2(r * 1.4, r * 0.6), height: 0.0018, string: "Survey Point", color: st.color)),
            ], selectable: false))
        }
        return items
    }
}
