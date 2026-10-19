import Foundation
import ArcusGeometry

// STAIR: the stair annotations on any run shape: Tread Number (each tread's number, from the stair's Tread/Riser Start
// Number, on the side of the runs the user picked) and Stair Path (the walk line through runs and landings with its
// start circle, arrow and UP — or DN on the plan of the level the stair arrives at).
extension AnnotationRenderer {
    static func stairTreadNumbers(_ t: TagData, target: Element, model: BIMModel, scale s: Double, st: GStroke) -> (prims: [GPrimitive], hits: [Polygon2])? {
        guard let l = StairGeometry.layout(target, model), let first = l.runs.first else { return nil }
        // The side and how far from the centre line, from where the annotation was placed (first run's frame).
        let near = first.walk.min { $0.distance(to: t.head) < $1.distance(to: t.head) } ?? first.start
        let off = (t.head - near).dot(first.direction.perpendicular)
        var prims: [GPrimitive] = [], hits: [Polygon2] = []
        for r in l.runs {
            let clamped = max(-r.width / 2 * 0.8, min(r.width / 2 * 0.8, off))
            for tr in r.treads {
                let side = tr.walkDirection.perpendicular
                let p = tr.walkPoint + side * clamped
                prims.append(.text(GText(position: p, height: 0.002, string: "\(tr.number)", rotation: readable(tr.walkDirection.angle + .pi / 2),
                                         alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
                hits.append(.rectangle(Rect2(center: p, halfSize: Vec2(s * 0.0015, s * 0.0015))))
            }
        }
        return (prims, hits)
    }

    static func stairPathSymbol(_ e: Element, target: Element, model: BIMModel, scale s: Double, st: GStroke) -> (prims: [GPrimitive], hits: [Polygon2])? {
        guard let l = StairGeometry.layout(target, model), !l.runs.isEmpty, let sd = target.stair else { return nil }
        var pts = StairGeometry.walkPath(l)
        guard pts.count >= 2 else { return nil }
        // Down on the plan of the level the stair arrives at.
        let viewLevel = model[e.ownerViewID]?.levelID.flatMap { model[$0]?.level?.elevation }
        let down = viewLevel.map { l.topZ <= $0 + 0.01 && l.baseZ < $0 - 0.01 } ?? false
        if down { pts.reverse() }
        let pathSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        var prims: [GPrimitive] = [.polyline(pts, closed: false, pathSt)]
        prims.append(.arc(Arc2(center: pts[0], radius: s * 0.001, startAngle: 0, sweep: Angle.twoPi), pathSt))
        let d = (pts[pts.count - 1] - pts[pts.count - 2]).normalized
        prims += arrowhead(.openArrow, at: pts[pts.count - 1], direction: d, scale: s * 1.4, st: st)
        let d0 = (pts[1] - pts[0]).normalized
        prims.append(.text(GText(position: pts[0] - d0 * (s * 0.0035), height: 0.0025, string: down ? (sd.downText ?? "DN") : (sd.upText ?? "UP"),
                                 rotation: readable(d0.angle + .pi / 2), alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
        var hits: [Polygon2] = []
        for q in zip(pts, pts.dropFirst()) {
            let seg = Segment2(q.0, q.1)
            let n = seg.length > 0 ? seg.direction.perpendicular * (s * 0.0012) : .zero
            hits.append(Polygon2([q.0 - n, q.1 - n, q.1 + n, q.0 + n]))
        }
        return (prims, hits)
    }
}
