import Foundation
import ArcusGeometry

// MARK: - Baseline and ordinate dimensions

extension AnnotationRenderer {
    /// Baseline (stacked lines from the first reference) and ordinate (witnesses labelled with their distance from the
    /// first reference) layouts of a linear or aligned dimension. The first reference in `d.references` is the origin.
    static func chainDimension(_ d: DimensionData, _ style: DimensionChainStyle, _ pts: [Vec2], model: BIMModel, scale s: Double,
                               textH: Double, st: GStroke, direction: Vec2? = nil, style dimStyle: DimensionStyle = DimensionStyle()) -> [GPrimitive] {
        var prims: [GPrimitive] = []
        let n = direction ?? DimensionQueries.measurementDirection(d, pts, model)
        let base = d.linePoint
        func onLine(_ q: Vec2) -> Vec2 { base + n * (q - base).dot(n) }
        let proj = pts.map(onLine)
        let origin = proj[0]
        let dimSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        let ext = s * dimStyle.witnessExtension, gap = s * dimStyle.witnessGap
        func tick(at p: Vec2, direction n: Vec2, scale s: Double, st _: GStroke) -> [GPrimitive] {
            dimensionTick(dimStyle.tick, at: p, direction: n, outward: [n, -n], scale: s, st: st)
        }
        let tickSt = st
        // The side of the line the references lie on; stacked lines grow away from them.
        let away = (base - pts[0]).dot(n.perpendicular) >= 0 ? n.perpendicular : -n.perpendicular
        func text(_ v: Double) -> String {
            d.textOverride ?? (d.prefix + Parameters.format(.double(v), type: .length, model: model) + d.suffix)
        }
        func witness(_ src: Vec2, _ q: Vec2) {
            let w = q - src
            if w.length > gap * 1.5 { let wd = w.normalized; prims.append(.polyline([src + wd * gap, q + wd * ext], closed: false, dimSt)) }
        }
        // References other than the origin, nearest first.
        let others = proj.indices.dropFirst().sorted { abs((proj[$0] - origin).dot(n)) < abs((proj[$1] - origin).dot(n)) }
        switch style {
        case .baseline:
            let spacing = s * 0.007
            witness(pts[0], origin + away * (spacing * Double(max(others.count - 1, 0))))
            prims += tick(at: origin, direction: n, scale: s, st: tickSt)
            for (k, i) in others.enumerated() {
                let shift = away * (spacing * Double(k))
                let a = origin + shift, b = proj[i] + shift
                let dir = (b - a).lengthSquared > 0 ? (b - a).normalized : n
                prims.append(.polyline([a - dir * ext, b + dir * ext], closed: false, dimSt))
                prims += tick(at: a, direction: n, scale: s, st: tickSt)
                prims += tick(at: b, direction: n, scale: s, st: tickSt)
                witness(pts[i], b)
                prims.append(.text(GText(position: (a + b) * 0.5 + away * (s * 0.0012), height: textH, string: text(abs((proj[i] - origin).dot(n))),
                                         rotation: readable(n.angle), alignment: .center, verticalAnchor: 0, color: st.color, halftone: st.halftone)))
            }
        case .ordinate:
            for i in proj.indices {
                witness(pts[i], proj[i])
                let value = i == 0 ? 0 : abs((proj[i] - origin).dot(n))
                let label = i == 0 && d.textOverride == nil ? "0" : text(value)
                prims.append(.text(GText(position: proj[i] + away * (s * 0.001), height: textH, string: label,
                                         rotation: readable(away.angle), alignment: .left, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
            }
            prims.append(.arc(Arc2(center: origin, radius: s * 0.0008, startAngle: 0, sweep: Angle.twoPi), dimSt))
        case .continuous:
            break
        }
        return prims
    }
}
