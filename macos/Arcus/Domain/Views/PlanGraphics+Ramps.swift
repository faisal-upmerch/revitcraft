import Foundation
import ArcusGeometry

extension PlanGraphics {
    /// Ramps: outline below the cut, the part above the cut dashed, a break line at the cut, and the walk line from
    /// the bottom with an arrow at the top and an "UP" label at the start.
    func ramps(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let l = RampGeometry.layout(e, model), l.baseZ <= cutZ + 0.01, l.topZ >= depthZ else { continue }
            let lines = RampGeometry.planLines(e, model, cutZ: cutZ)
            let st = builder.stroke(.ramps, cut: false, o)
            let cutSt = builder.stroke(.ramps, cut: true, o)
            let hidden = GStroke(weight: 1, color: st.color, pattern: .hidden, halftone: st.halftone)
            var prims: [GPrimitive] = []
            for s in lines.below { prims.append(.polyline([s.start, s.end], closed: false, cutSt)) }
            for s in lines.above { prims.append(.polyline([s.start, s.end], closed: false, hidden)) }
            if let b = lines.breakLine {
                let m = b.midpoint, d = b.direction, n = b.normal * builder.paper(0.0015)
                prims.append(.polyline([b.start, m - d * builder.paper(0.002), m + n, m - n, m + d * builder.paper(0.002), b.end], closed: false, st))
            }
            if lines.walk.count >= 2 {
                prims.append(.polyline(lines.walk, closed: false, st))
                let end = lines.walk[lines.walk.count - 1], prev = lines.walk[lines.walk.count - 2]
                let d = (end - prev).normalized, n = d.perpendicular
                let a = builder.paper(0.0025)
                prims.append(.polyline([end - d * a + n * a * 0.4, end, end - d * a - n * a * 0.4], closed: false, st))
                let first = (lines.walk[1] - lines.walk[0]).normalized
                prims.append(.text(GText(position: lines.walk[0] - first * builder.paper(0.003), height: 0.0022, string: "UP", alignment: .center, verticalAnchor: 0.5)))
            }
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: l.pieces.map(\.polygon)))
        }
        return items
    }
}
