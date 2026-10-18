import Foundation
import ArcusGeometry

// W2-ANNOT: text notes — type styles, the text block, leaders (straight with a shoulder or elbow, or arcs) and graphics.

/// Resolved appearance of a text note: its type's size, faces, background and arrowhead, with instance overrides.
public struct TextNoteStyle: Sendable, Hashable {
    /// Cap height on paper (meters).
    public var size: Double
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var opaque: Bool
    public var arrowhead: LeaderArrowhead

    public init(size: Double = 0.0025, bold: Bool = false, italic: Bool = false, underline: Bool = false, opaque: Bool = false,
                arrowhead: LeaderArrowhead = .arrow) {
        self.size = size; self.bold = bold; self.italic = italic; self.underline = underline; self.opaque = opaque; self.arrowhead = arrowhead
    }

    /// The style of a text type (no instance).
    public static func of(type td: TypeData?) -> TextNoteStyle {
        let p = td?.params ?? [:]
        return TextNoteStyle(size: p[AnnotationParams.textSize]?.doubleValue ?? 0.0025,
                             bold: p[AnnotationParams.textBold]?.boolValue ?? false,
                             italic: p[AnnotationParams.textItalic]?.boolValue ?? false,
                             underline: p[AnnotationParams.textUnderline]?.boolValue ?? false,
                             opaque: p[AnnotationParams.textBackground]?.textValue == TextBackground.opaque.rawValue,
                             arrowhead: LeaderArrowhead(rawValue: p[AnnotationParams.textArrowhead]?.textValue ?? "") ?? .arrow)
    }

    public static func resolve(_ e: Element, _ model: BIMModel) -> TextNoteStyle {
        var s = of(type: model.typeData(of: e))
        if let n = e.textNote {
            if let b = n.bold { s.bold = b }
            if let i = n.italic { s.italic = i }
            if let u = n.underline { s.underline = u }
        }
        return s
    }
}

/// Geometry of a text note in view coordinates. `scale` is view units per paper meter (the view scale; 1 on sheets).
public enum TextNoteGeometry {
    /// The text block: `origin` is its top-left corner, `u` runs along the text over its width and `v` runs down over
    /// its height (both in view units, rotated with the note).
    public struct Box: Sendable, Hashable {
        public var origin: Vec2
        public var u: Vec2
        public var v: Vec2
        public func point(_ x: Double, _ y: Double) -> Vec2 { origin + u * x + v * y }
        public var corners: [Vec2] { [point(0, 0), point(1, 0), point(1, 1), point(0, 1)] }
        public var polygon: Polygon2 { Polygon2(corners) }
        public var center: Vec2 { point(0.5, 0.5) }
        public var width: Double { u.length }
        public var height: Double { v.length }
    }

    /// Paper size (meters) of the text block.
    public static func paperSize(_ n: TextNoteData, _ style: TextNoteStyle) -> Vec2 {
        let size = TextMetrics.blockSize(n.text.isEmpty ? " " : n.text, height: style.size, bold: style.bold, wrap: n.width)
        return Vec2(n.width > 0 ? n.width : max(size.x, style.size), size.y)
    }

    public static func box(_ n: TextNoteData, _ style: TextNoteStyle, scale: Double) -> Box {
        let size = paperSize(n, style) * scale
        let dir = Vec2.fromAngle(n.rotation), down = -dir.perpendicular
        let shift: Double
        switch n.alignment {
        case .left: shift = 0
        case .center: shift = size.x / 2
        case .right: shift = size.x
        }
        return Box(origin: n.position - dir * shift, u: dir * size.x, v: down * size.y)
    }

    /// Distance between the text block and where leaders attach (paper meters).
    static let attachGap = 0.0008
    /// Length of the automatic horizontal shoulder of straight leaders (paper meters).
    static let shoulder = 0.003

    /// Leader `i`: the polyline (or arc) from the text to its end, and the direction it arrives at the end.
    public struct Leader: Sendable {
        public var points: [Vec2]
        public var arc: Arc2?
        public var end: Vec2
        public var arrival: Vec2
        /// Where it leaves the text block.
        public var attach: Vec2
    }

    /// Leaders attach beside the first line of text, on the side facing their end.
    public static func leader(_ n: TextNoteData, _ i: Int, _ style: TextNoteStyle, scale: Double) -> Leader? {
        guard i < n.leaders.count else { return nil }
        let b = box(n, style, scale: scale)
        let end = n.leaders[i]
        let elbow = n.elbow(i)
        let target = elbow ?? end
        let dir = b.u.length > 0 ? b.u.normalized : .unitX
        let right = (target - b.center).dot(dir) > 0
        let firstLineMid = min(0.5, (style.size * scale / 2) / max(b.height, 1e-9))
        let gap = attachGap * scale
        let attach = right ? b.point(1, firstLineMid) + dir * gap : b.point(0, firstLineMid) - dir * gap
        if n.leaderShape == .arc {
            let chord = end - attach
            guard chord.length > 1e-9 else { return nil }
            let mid = attach.midpoint(end) + chord.perpendicular.normalized * (chord.length * 0.22) * (right ? 1 : -1)
            if let a = Arc2(through: attach, mid, end) {
                return Leader(points: [], arc: a, end: end, arrival: a.tangent(at: 1), attach: attach)
            }
        }
        var pts = [attach]
        if let e = elbow { pts.append(e) } else {
            let sh = attach + dir * (right ? 1 : -1) * shoulder * scale
            // A shoulder only helps when the end lies beyond it.
            if ((end - sh).dot(dir) > 0) == right { pts.append(sh) }
        }
        pts.append(end)
        let last = pts[pts.count - 1] - pts[pts.count - 2]
        return Leader(points: pts, arc: nil, end: end, arrival: last.lengthSquared > 0 ? last.normalized : dir, attach: attach)
    }

    /// The default elbow of leader `i` (the shoulder end), for grips.
    public static func elbowPoint(_ n: TextNoteData, _ i: Int, _ style: TextNoteStyle, scale: Double) -> Vec2? {
        guard let l = leader(n, i, style, scale: scale), l.arc == nil else { return nil }
        return l.points.count >= 3 ? l.points[1] : l.attach.midpoint(l.end)
    }
}

extension AnnotationRenderer {
    /// Arrowheads at leader ends (sizes on paper).
    static func arrowhead(_ kind: LeaderArrowhead, at p: Vec2, direction d: Vec2, scale s: Double, st: GStroke) -> [GPrimitive] {
        let dir = d.lengthSquared > 0 ? d.normalized : .unitX
        switch kind {
        case .arrow: return arrowHead(at: p, direction: dir, scale: s, st: st)
        case .openArrow:
            let a = s * 0.0025, n = dir.perpendicular
            return [.polyline([p - dir * a + n * a * 0.35, p, p - dir * a - n * a * 0.35], closed: false, GStroke(weight: 1, color: st.color, halftone: st.halftone))]
        case .dot:
            let r = s * 0.0006
            return [.fill([Polygon2(Arc2(center: p, radius: r, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: r * 0.05).dropLast())],
                          GFill(pattern: .solid, color: st.color, halftone: st.halftone))]
        case .none: return []
        }
    }

    static func textNote(_ e: Element, _ n: TextNoteData, model: BIMModel, scale s: Double, st: GStroke) -> GItem {
        let style = TextNoteStyle.resolve(e, model)
        var prims: [GPrimitive] = []
        let leaderSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        var hit: [Polygon2] = []
        for i in n.leaders.indices {
            guard let l = TextNoteGeometry.leader(n, i, style, scale: s) else { continue }
            if let a = l.arc { prims.append(.arc(a, leaderSt)) } else { prims.append(.polyline(l.points, closed: false, leaderSt)) }
            prims += arrowhead(style.arrowhead, at: l.end, direction: l.arrival, scale: s, st: st)
        }
        let box = TextNoteGeometry.box(n, style, scale: s)
        // Leaders are drawn first so an opaque text block covers their start cleanly.
        prims.append(.text(GText(position: n.position, height: style.size, string: n.text, rotation: n.rotation, alignment: n.alignment,
                                 verticalAnchor: 1, bold: style.bold, color: st.color, halftone: st.halftone, wrapWidth: n.width,
                                 italic: style.italic, underline: style.underline, opaque: style.opaque)))
        hit.append(box.polygon)
        return GItem(elementID: e.id, category: .textNotes, layer: .annotation, primitives: prims, hitPolygons: hit)
    }
}
