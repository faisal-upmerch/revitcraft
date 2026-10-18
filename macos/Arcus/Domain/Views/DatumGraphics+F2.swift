import Foundation
import ArcusGeometry

// F2: multi-segment grids in plan (RevitCraft plan.rs `grid_graphics`): the line through the bends, a bubble beyond each
// shown end along its end segment.

extension DatumGraphics {
    static func multiSegmentGridPlan(_ g: Element, _ gd: GridData, builder: ViewGraphicsBuilder, _ o: GraphicOverride) -> GItem {
        let st = builder.stroke(.grids, cut: false, o)
        let r = builder.paper(bubbleRadius)
        let pts = gd.polyline
        var prims: [GPrimitive] = [.polyline(pts, closed: false, st)]
        let (d0, d1) = gd.endDirections
        if gd.bubbleAtStart { prims += bubble(at: pts[0] + d0 * r, label: g.name, builder: builder, st: st) }
        if gd.bubbleAtEnd { prims += bubble(at: pts[pts.count - 1] + d1 * r, label: g.name, builder: builder, st: st) }
        return GItem(elementID: g.id, category: .grids, layer: .annotation, primitives: prims)
    }
}
