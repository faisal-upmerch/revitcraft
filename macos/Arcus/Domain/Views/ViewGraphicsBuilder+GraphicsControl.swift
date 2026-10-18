import Foundation
import ArcusGeometry

// BL-VG: per-category detail level, subcategory graphics, 2D wireframe and Reveal Constraints.

extension ViewGraphicsBuilder {
    /// Detail level for a category: the view's Visibility/Graphics setting for it, else the view's detail level.
    public func detailLevel(_ c: Category) -> DetailLevel {
        resolver.vg.categoryDetailLevels?[c] ?? data.detailLevel
    }

    /// Override for one subcategory of an element whose element-level override is `o`; nil when the subcategory is
    /// hidden. Skips the second resolve when the view has no subcategory settings.
    func subcategoryOverride(_ e: Element, _ o: GraphicOverride, _ sub: FamilySubcategory) -> GraphicOverride? {
        guard sub != .general else { return o }
        let vg = resolver.vg
        guard vg.hiddenSubcategories?.isEmpty == false || vg.subcategoryOverrides?.isEmpty == false else { return o }
        return resolver.resolve(e, subcategory: sub.rawValue)
    }

    /// Stroke for a subcategory of an element (object style of the subcategory, then its override).
    func stroke(_ e: Element, cut: Bool, _ o: GraphicOverride, _ sub: FamilySubcategory) -> GStroke {
        stroke(e.category, cut: cut, o, subcategory: sub == .general ? nil : sub.rawValue)
    }

    /// Wireframe in 2D views: model graphics as lines only (cut and surface patterns off). Masking and annotation
    /// fills stay.
    static func wireframe(_ items: [GItem]) -> [GItem] {
        items.map { item in
            guard [.fills, .model, .cut].contains(item.layer) else { return item }
            var copy = item
            copy.primitives = item.primitives.filter { if case .fill = $0 { return false }; return true }
            return copy
        }
    }

    /// Reveal Constraints: every locked dimension, alignment lock and EQ constraint drawn in red over plan views,
    /// with a padlock (or "EQ") at the middle of each constrained span.
    func constraintItems() -> [GItem] {
        guard data.kind.isPlan || data.kind == .drafting else { return [] }
        let red = RGBColor(0.86, 0.12, 0.12)
        let dash = GStroke(weight: 2, color: red, pattern: .dash)
        var items: [GItem] = []
        for (_, c) in ConstraintSolver.activeConstraints(model) where c.kind != .join {
            let pts = c.references.compactMap { DimensionQueries.resolve($0, model)?.point }
            guard pts.count >= 2 else { continue }
            var prims: [GPrimitive] = [.polyline(pts, closed: false, dash)]
            for i in 0..<(pts.count - 1) {
                let m = (pts[i] + pts[i + 1]) * 0.5
                if c.kind == .equality {
                    prims.append(.text(GText(position: m, height: 0.0025, string: "EQ", alignment: .center, verticalAnchor: 0.5, bold: true, color: red)))
                } else {
                    prims += padlock(at: m, color: red)
                }
            }
            items.append(GItem(elementID: nil, category: .constraints, layer: .overlay, primitives: prims, selectable: false))
        }
        return items
    }

    /// A small padlock (3 mm on paper) centred on `p`.
    func padlock(at p: Vec2, color: RGBColor) -> [GPrimitive] {
        let w = paper(0.0012), h = paper(0.001)
        let body = Polygon2([p + Vec2(-w, -h), p + Vec2(w, -h), p + Vec2(w, h * 0.6), p + Vec2(-w, h * 0.6)])
        let st = GStroke(weight: 2, color: color)
        return [.fill([body], GFill(pattern: .solid, color: color)),
                .arc(Arc2(center: p + Vec2(0, h * 0.6), radius: w * 0.7, startAngle: 0, sweep: .pi), st)]
    }
}
