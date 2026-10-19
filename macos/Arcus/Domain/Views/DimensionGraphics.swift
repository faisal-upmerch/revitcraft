import Foundation
import ArcusGeometry

// W2-ANNOT: dimension types (tick marks, text size, witness line gap and extensions), equality display, dragged
// value texts and dimensions in sections and elevations.

/// Resolved appearance of a dimension from its type (sizes on paper, meters).
public struct DimensionStyle: Sendable, Hashable {
    public var textSize: Double
    public var tick: DimensionTickMark
    /// Gap between the measured element and the start of its witness line.
    public var witnessGap: Double
    /// How far witness lines run past the dimension line.
    public var witnessExtension: Double
    /// How far the dimension line runs past the outer witness lines.
    public var lineExtension: Double
    /// Distance from the dimension line to its text.
    public var textOffset: Double

    public init(textSize: Double = 0.0025, tick: DimensionTickMark = .diagonal, witnessGap: Double = 0.0015, witnessExtension: Double = 0.002,
                lineExtension: Double? = nil, textOffset: Double = 0.0012) {
        self.textSize = textSize; self.tick = tick; self.witnessGap = witnessGap; self.witnessExtension = witnessExtension
        self.lineExtension = lineExtension ?? (tick == .diagonal || tick == .heavyDiagonal ? 0.002 : 0)
        self.textOffset = textOffset
    }

    public static func of(type td: TypeData?) -> DimensionStyle {
        let p = td?.params ?? [:]
        let tick = DimensionTickMark(rawValue: p[AnnotationParams.dimensionTick]?.textValue ?? "") ?? .diagonal
        return DimensionStyle(textSize: p[AnnotationParams.dimensionTextSize]?.doubleValue ?? 0.0025, tick: tick,
                              witnessGap: p[AnnotationParams.dimensionWitnessGap]?.doubleValue ?? 0.0015,
                              witnessExtension: p[AnnotationParams.dimensionWitnessExtension]?.doubleValue ?? 0.002,
                              lineExtension: p[AnnotationParams.dimensionLineExtension]?.doubleValue,
                              textOffset: p[AnnotationParams.dimensionTextOffset]?.doubleValue ?? 0.0012)
    }

    public static func resolve(_ e: Element, _ model: BIMModel) -> DimensionStyle { of(type: model.typeData(of: e)) }
}

/// Layout of a continuous linear or aligned dimension string (shared by graphics and grips).
public struct DimensionLayout: Sendable {
    /// Witness points on the measured references and their projections on the dimension line.
    public var points: [Vec2]
    public var projected: [Vec2]
    /// Reference indices sorted along the measurement direction.
    public var order: [Int]
    public var direction: Vec2
    /// Unit normal from the dimension line toward its text.
    public var textSide: Vec2
    /// Segment k (between order[k] and order[k+1]): its value and where its text sits.
    public var values: [Double]
    public var textPositions: [Vec2]
    public var first: Vec2 { projected[order.first!] }
    public var last: Vec2 { projected[order.last!] }

    public static func make(_ e: Element, _ d: DimensionData, _ model: BIMModel, scale s: Double, view: Element?) -> DimensionLayout? {
        let pts = AnnotationGeometry.points(d, model, view: view)
        guard pts.count >= 2 else { return nil }
        let style = DimensionStyle.resolve(e, model)
        let n = AnnotationGeometry.measurementDirection(d, pts, model, view: view)
        let base = d.linePoint
        let proj = pts.map { base + n * ($0 - base).dot(n) }
        let order = proj.indices.sorted { (proj[$0] - base).dot(n) < (proj[$1] - base).dot(n) }
        // Text sits above the line as it reads (to the left of vertical strings), like drafting convention.
        let textSide = Vec2.fromAngle(AnnotationRenderer.readable(n.angle)).perpendicular
        var values: [Double] = [], texts: [Vec2] = []
        for (k, (a, b)) in zip(order.dropLast(), order.dropFirst()).enumerated() {
            values.append(abs((proj[b] - proj[a]).dot(n)))
            var t = (proj[a] + proj[b]) * 0.5 + textSide * (s * style.textOffset)
            if let offs = d.textOffsets, k < offs.count { t = t + offs[k] }
            texts.append(t)
        }
        return DimensionLayout(points: pts, projected: proj, order: order, direction: n, textSide: textSide, values: values, textPositions: texts)
    }
}

extension AnnotationRenderer {
    /// End marks at `p` on a dimension line running along `n`; `outward` points from the segment toward the mark (arrows).
    static func dimensionTick(_ kind: DimensionTickMark, at p: Vec2, direction n: Vec2, outward: [Vec2], scale s: Double, st: GStroke) -> [GPrimitive] {
        switch kind {
        case .diagonal: return tick(at: p, direction: n, scale: s, st: GStroke(weight: 3, color: st.color, halftone: st.halftone))
        case .heavyDiagonal: return tick(at: p, direction: n, scale: s, st: GStroke(weight: 5, color: st.color, halftone: st.halftone))
        case .arrow: return outward.flatMap { arrowhead(.arrow, at: p, direction: $0, scale: s, st: st) }
        case .openArrow: return outward.flatMap { arrowhead(.openArrow, at: p, direction: $0, scale: s, st: st) }
        case .dot: return arrowhead(.dot, at: p, direction: n, scale: s, st: st)
        }
    }

    /// Label of segment `k` of a continuous string.
    static func segmentText(_ d: DimensionData, value: Double, count: Int, model: BIMModel) -> String {
        if let o = d.textOverride { return o }
        let formatted = d.prefix + Parameters.format(.double(value), type: .length, model: model) + d.suffix
        if let label = d.labelParameter, count == 1, model.isFurniture { return "\(label) = \(formatted)" } // FM3: labelled, as in families
        guard d.equality && count > 1 else { return formatted }
        switch d.equalityDisplay ?? .text {
        case .value: return formatted
        case .text, .formula: return "EQ"
        }
    }

    static func linearDimension(_ e: Element, _ d: DimensionData, model: BIMModel, scale s: Double, st: GStroke, view: Element?) -> [GPrimitive] {
        let style = DimensionStyle.resolve(e, model)
        guard let lay = DimensionLayout.make(e, d, model, scale: s, view: view) else { return [] }
        if let chain = d.chainStyle, chain != .continuous {
            return chainDimension(d, chain, lay.points, model: model, scale: s, textH: style.textSize, st: st, direction: lay.direction, style: style)
        }
        var prims: [GPrimitive] = []
        let n = lay.direction
        let dimSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        let first = lay.first, last = lay.last
        let lineExt = s * style.lineExtension
        prims.append(.polyline([first - n * lineExt, last + n * lineExt], closed: false, dimSt))
        let gap = s * style.witnessGap, ext = s * style.witnessExtension
        for (i, q) in lay.projected.enumerated() {
            let src = lay.points[i]
            let w = q - src
            if w.length > gap * 1.5 {
                let wd = w.normalized
                prims.append(.polyline([src + wd * gap, q + wd * ext], closed: false, dimSt))
            }
            // Arrows point outward at the string's ends and inward from both sides at interior witnesses.
            let rank = lay.order.firstIndex(of: i) ?? 0
            var outward: [Vec2] = []
            if rank > 0 { outward.append(n) }
            if rank < lay.order.count - 1 { outward.append(-n) }
            prims += dimensionTick(style.tick, at: q, direction: n, outward: outward, scale: s, st: st)
        }
        let segments = lay.values.count
        if d.equality && segments > 1 && d.textOverride == nil && (d.equalityDisplay ?? .text) == .formula {
            let total = lay.values.reduce(0, +)
            let each = Parameters.format(.double(total / Double(segments)), type: .length, model: model)
            let label = "\(segments) @ \(each) = " + Parameters.format(.double(total), type: .length, model: model)
            var pos = (first + last) * 0.5 + lay.textSide * (s * style.textOffset)
            if let offs = d.textOffsets, let o = offs.first { pos = pos + o }
            prims.append(.text(GText(position: pos, height: style.textSize, string: d.prefix + label + d.suffix, rotation: readable(n.angle),
                                     alignment: .center, verticalAnchor: 0, color: st.color, halftone: st.halftone)))
        } else {
            for k in 0..<segments {
                let txt = segmentText(d, value: lay.values[k], count: segments, model: model)
                prims.append(.text(GText(position: lay.textPositions[k], height: style.textSize, string: txt, rotation: readable(n.angle),
                                         alignment: .center, verticalAnchor: 0, color: st.color, halftone: st.halftone)))
                if !d.below.isEmpty {
                    prims.append(.text(GText(position: lay.textPositions[k] - lay.textSide * (s * style.textOffset * 2), height: style.textSize * 0.85,
                                             string: d.below, rotation: readable(n.angle), alignment: .center, verticalAnchor: 1,
                                             color: st.color, halftone: st.halftone)))
                }
            }
        }
        if d.locked {
            let lp = last + n * s * 0.003
            prims.append(.polyline(Rect2(center: lp, halfSize: Vec2(s * 0.0008, s * 0.0006)).corners, closed: true, dimSt))
            prims.append(.arc(Arc2(center: lp + Vec2(0, s * 0.0006), radius: s * 0.0005, startAngle: 0, sweep: .pi), dimSt))
        }
        return prims
    }
}
