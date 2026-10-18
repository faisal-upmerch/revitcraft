import Foundation
import ArcusGeometry

// W2-LIB: ceiling-mounted library components (lights, fans, diffusers) in reflected ceiling plans.
extension PlanGraphics {
    /// Plan symbols of fixtures hosted on this view's level whose geometry reaches above the cut plane, as seen
    /// looking up from the cut plane (the floor plan leaves them out once they rise above it).
    func ceilingFixtures(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list where e.levelID == levelID {
            let b = ElementMeshes.bounds(e, model)
            guard !b.isEmpty, b.max.z >= cutZ - Tolerance.length else { continue }
            let st = builder.stroke(e.category, cut: false, o)
            var prims: [GPrimitive] = []
            for s in ComponentGeometry.planSymbols(e, model) where s.visibleAt.contains(builder.detailLevel(e.category)) { // BL-VG
                switch s.curve {
                case .line(let seg): prims.append(.polyline([seg.start, seg.end], closed: false, st))
                case .arc(let a): prims.append(.arc(a, st))
                }
            }
            let outlines = ComponentGeometry.planOutline(e, model)
            if prims.isEmpty { prims = ComponentGeometry.planOutline(e, model, detail: builder.detailLevel(e.category)).map { .polyline($0.points, closed: true, st) } } // BL-VG
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: outlines))
        }
        return items
    }
}
