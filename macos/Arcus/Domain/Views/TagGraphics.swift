import Foundation
import ArcusGeometry

// W2-ANNOT: tags — category tags with leaders and elbows, material tags, keynotes, tread numbers, view references,
// span direction symbols, stair paths and scale bars.

/// Materials of elements, for material tags and material keynotes.
public enum MaterialPick {
    /// The material at `p` (view coordinates) on `e`: the wall layer under the point in plans, the exposed layer of
    /// floors, roofs and ceilings, else the type or family material.
    public static func material(at p: Vec2?, of e: Element, _ model: BIMModel, view: Element? = nil) -> ElementID? {
        if let p, e.wall != nil, !AnnotationGeometry.isVertical(view), let f = WallGeometry.frame(e, model), f.assembly.layers.count > 0 {
            let d = f.exteriorFace.distance(to: p)
            var acc = 0.0
            for l in f.assembly.layers where l.thickness > 0 {
                acc += l.thickness
                if d <= acc + 1e-6 { return l.materialID }
            }
            return f.assembly.layers.last { $0.thickness > 0 }?.materialID
        }
        if let a = model.typeData(of: e)?.assembly, !a.layers.isEmpty {
            return SlabGeometry.surfaceMaterial(e, model)
        }
        if let m = model.typeParam(e, ParameterID("type.material"))?.refValue { return m }
        // Family instances: the first material parameter with a value.
        if let td = model.typeData(of: e) {
            for (k, v) in td.params.sorted(by: { $0.key.key < $1.key.key }) where k.key.lowercased().contains("material") {
                if let id = v.refValue, model[id]?.material != nil { return id }
            }
        }
        return nil
    }
}

/// Where a tag draws, for grips and picking.
public enum TagGeometry {
    /// Half size (view units) of the label box around a tag head, estimated from its text.
    public static func halfSize(text: String, height: Double, scale s: Double) -> Vec2 {
        let size = TextMetrics.blockSize(text.isEmpty ? "?" : text, height: height)
        return Vec2(size.x / 2 + height * 0.5, size.y / 2 + height * 0.5) * s
    }

    /// The point on the border of `box` along the way from its centre to `toward`.
    static func border(_ box: Rect2, toward p: Vec2) -> Vec2 {
        let c = box.center, d = p - c
        guard d.lengthSquared > 1e-18 else { return c }
        let hx = box.width / 2, hy = box.height / 2
        let tx = abs(d.x) > 1e-12 ? hx / abs(d.x) : .infinity
        let ty = abs(d.y) > 1e-12 ? hy / abs(d.y) : .infinity
        let t = min(1, min(tx, ty))
        return c + d * t
    }

    /// The leader of a tag: from the label box border through the elbow to the end (nil without a leader).
    public static func leader(_ t: TagData, box: Rect2, end: Vec2) -> [Vec2] {
        var pts: [Vec2] = []
        let next = t.leaderElbow ?? end
        pts.append(border(box, toward: next))
        if let e = t.leaderElbow { pts.append(e) }
        pts.append(end)
        return pts
    }

    /// The end of a tag's leader: where it was dragged, else the tagged element's anchor in the view.
    public static func leaderEnd(_ t: TagData, _ model: BIMModel, view: Element?) -> Vec2? {
        if let e = t.leaderEnd { return e }
        guard let target = model[t.taggedID] else { return nil }
        return AnnotationGeometry.leaderAnchor(target, model, view: view)
    }
}

extension AnnotationRenderer {
    static func leaderStroke(_ st: GStroke) -> GStroke { GStroke(weight: 1, color: st.color, halftone: st.halftone) }

    static func tagItem(_ e: Element, _ t: TagData, model: BIMModel, scale s: Double, st: GStroke, view: Element?) -> GItem? {
        if let k = t.kind {
            return specialTag(e, t, k, model: model, scale: s, st: st, view: view)
        }
        var prims = tag(e, t, model: model, scale: s, st: st, view: view)
        guard !prims.isEmpty else { return nil }
        let box = labelBox(prims, head: t.head, scale: s)
        if t.hasLeader, let end = TagGeometry.leaderEnd(t, model, view: view), end.distance(to: t.head) > 1e-9 {
            prims.insert(.polyline(TagGeometry.leader(t, box: box, end: end), closed: false, leaderStroke(st)), at: 0)
        }
        return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims, hitPolygons: [.rectangle(box)])
    }

    /// The label box of a family tag: its lines and fills, and its text estimated from the strings.
    static func labelBox(_ prims: [GPrimitive], head: Vec2, scale s: Double) -> Rect2 {
        var r = Rect2.empty
        for p in prims {
            switch p {
            case .polyline(let pts, _, _): for q in pts { r.include(q) }
            case .arc(let a, _): r.include(a.bounds)
            case .fill(let polys, _): for poly in polys { r.include(poly.bounds) }
            case .text(let tx):
                let h = TagGeometry.halfSize(text: tx.string, height: tx.height, scale: s)
                let size = TextMetrics.blockSize(tx.string, height: tx.height) * s
                let dy = size.y * (tx.verticalAnchor - 0.5)
                let dx: Double = tx.alignment == .left ? h.x - tx.height * 0.5 * s : tx.alignment == .right ? -(h.x - tx.height * 0.5 * s) : 0
                let c = tx.position + Vec2(dx, dy)
                r.include(Rect2(center: c, halfSize: h))
            }
        }
        if r.isEmpty { r = Rect2(center: head, halfSize: Vec2(s * 0.002, s * 0.002)) }
        return r
    }

    // MARK: Special tags

    static func keynoteKey(_ t: TagData, _ kind: TagKind, target: Element?, model: BIMModel) -> String {
        switch kind {
        case .keynoteElement:
            guard let target else { return "" }
            return model.typeParam(target, ParameterID("type.keynote"))?.textValue ?? ""
        case .keynoteMaterial:
            let mid = t.materialID ?? target.flatMap { MaterialPick.material(at: nil, of: $0, model) }
            return model[mid]?.material?.keynote ?? ""
        default:
            return t.keynote ?? ""
        }
    }

    /// The text a keynote shows.
    public static func keynoteLabel(_ t: TagData, _ kind: TagKind, target: Element?, model: BIMModel) -> String {
        let key = keynoteKey(t, kind, target: target, model: model)
        guard !key.isEmpty else { return "?" }
        let text = KeynoteTable.text(for: key) ?? ""
        switch t.keynoteDisplay ?? .key {
        case .key: return key
        case .keyAndText: return text.isEmpty ? key : "\(key) \(text)"
        case .text: return text.isEmpty ? key : text
        }
    }

    static func specialTag(_ e: Element, _ t: TagData, _ kind: TagKind, model: BIMModel, scale s: Double, st: GStroke, view: Element?) -> GItem? {
        let target = model[t.taggedID]
        let textSt = st
        var prims: [GPrimitive] = []
        var hit: [Polygon2] = []
        var targetView: ElementID?
        func label(_ text: String, boxed: Bool, height: Double = 0.0025) {
            let half = TagGeometry.halfSize(text: text, height: height, scale: s)
            let box = Rect2(center: t.head, halfSize: half)
            if t.hasLeader, let end = TagGeometry.leaderEnd(t, model, view: view), !box.contains(end) {
                prims.append(.polyline(TagGeometry.leader(t, box: box, end: end), closed: false, leaderStroke(st)))
                prims += arrowhead(.dot, at: end, direction: .unitX, scale: s * 0.7, st: st)
            }
            if boxed {
                prims.append(.fill([.rectangle(box)], .mask))
                prims.append(.polyline(box.corners, closed: true, leaderStroke(st)))
            }
            prims.append(.text(GText(position: t.head, height: height, string: text, alignment: .center, verticalAnchor: 0.5,
                                     color: textSt.color, halftone: textSt.halftone)))
            hit.append(.rectangle(box))
        }
        switch kind {
        case .material:
            let mid = t.materialID ?? target.flatMap { MaterialPick.material(at: nil, of: $0, model) }
            label(model[mid]?.name ?? "?", boxed: false)
        case .keynoteElement, .keynoteMaterial, .keynoteUser:
            label(keynoteLabel(t, kind, target: target, model: model), boxed: (t.keynoteDisplay ?? .key) == .key)
        case .viewReference:
            guard let v = target, v.view != nil else { return nil }
            let vp = model.viewports(showing: v.id).first
            let sheet = vp.flatMap { model[$0.ownerViewID]?.sheet?.number } ?? ""
            let detail = vp?.viewport?.detailNumber ?? ""
            let ref = detail.isEmpty && sheet.isEmpty ? "–" : "\(detail.isEmpty ? "–" : detail)/\(sheet.isEmpty ? "–" : sheet)"
            label(ref, boxed: true)
            let h = TagGeometry.halfSize(text: ref, height: 0.0025, scale: s)
            prims.append(.text(GText(position: t.head + Vec2(0, h.y + s * 0.0008), height: 0.0018, string: v.name, alignment: .center,
                                     verticalAnchor: 0, color: st.color, halftone: st.halftone)))
            targetView = v.id
        case .treadNumber:
            guard let target, let l = StairGeometry.layout(target, model) else { return nil }
            var n = 1
            for (k, r) in l.runs.enumerated() {
                let side = r.direction.perpendicular
                // Numbers sit on the side of the run the user picked (measured from the first run's centreline).
                let off: Double = k == 0 ? (t.head - r.start).dot(side) : (t.head - l.runs[0].start).dot(l.runs[0].direction.perpendicular)
                let clamped = max(-r.width / 2 * 0.8, min(r.width / 2 * 0.8, off))
                for i in 0..<max(r.risers - 1, 0) {
                    let p = r.start + r.direction * ((Double(i) + 0.5) * l.treadDepth) + side * clamped
                    prims.append(.text(GText(position: p, height: 0.002, string: "\(n)", rotation: readable(r.direction.angle + .pi / 2),
                                             alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
                    hit.append(.rectangle(Rect2(center: p, halfSize: Vec2(s * 0.0015, s * 0.0015))))
                    n += 1
                }
            }
        case .stairPath:
            guard let target, let l = StairGeometry.layout(target, model), !l.runs.isEmpty else { return nil }
            var pts: [Vec2] = []
            for r in l.runs {
                pts.append(r.start)
                pts.append(r.start + r.direction * (Double(max(r.risers - 1, 0)) * l.treadDepth))
            }
            let pathSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
            prims.append(.polyline(pts, closed: false, pathSt))
            let first = l.runs[0]
            prims.append(.arc(Arc2(center: pts[0], radius: s * 0.0012, startAngle: 0, sweep: Angle.twoPi), pathSt))
            if let lastRun = l.runs.last, pts.count >= 2 {
                prims += arrowhead(.openArrow, at: pts[pts.count - 1], direction: lastRun.direction, scale: s * 1.4, st: st)
            }
            prims.append(.text(GText(position: pts[0] - first.direction * (s * 0.004), height: 0.0022, string: "UP",
                                     rotation: readable(first.direction.angle), alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
            for q in zip(pts, pts.dropFirst()) {
                let seg = Segment2(q.0, q.1)
                let n = seg.length > 0 ? seg.direction.perpendicular * (s * 0.0012) : .zero
                hit.append(Polygon2([q.0 - n, q.1 - n, q.1 + n, q.0 + n]))
            }
        case .spanDirection:
            let a = t.angle ?? target.flatMap { spanAngle($0) } ?? 0
            let d = Vec2.fromAngle(a), n = d.perpendicular
            let half = s * 0.009, arrow = s * 0.0025
            let a0 = t.head - d * half, a1 = t.head + d * half
            prims.append(.polyline([a0, a1], closed: false, GStroke(weight: 2, color: st.color, halftone: st.halftone)))
            // Filled half arrows at both ends (one-way span).
            prims.append(.fill([Polygon2([a1, a1 - d * arrow + n * arrow * 0.45, a1 - d * arrow])], GFill(pattern: .solid, color: st.color, halftone: st.halftone)))
            prims.append(.fill([Polygon2([a0, a0 + d * arrow - n * arrow * 0.45, a0 + d * arrow])], GFill(pattern: .solid, color: st.color, halftone: st.halftone)))
            hit.append(Polygon2([a0 - n * arrow * 0.6, a1 - n * arrow * 0.6, a1 + n * arrow * 0.6, a0 + n * arrow * 0.6]))
        case .scaleBar:
            let bar = scaleBar(at: t.head, scale: s, model: model, st: st)
            prims += bar.prims
            hit.append(.rectangle(bar.bounds))
        }
        guard !prims.isEmpty else { return nil }
        let cat: Category = [.spanDirection, .stairPath, .scaleBar, .viewReference].contains(kind) ? e.category : .tags
        return GItem(elementID: e.id, category: cat, layer: .annotation, primitives: prims, targetViewID: targetView, hitPolygons: hit)
    }

    /// Span direction of a floor: along its longest boundary edge.
    static func spanAngle(_ floor: Element) -> Double? {
        guard let prof = try? floor.slab?.boundary.profile().get() else { return nil }
        return prof.outer.edges.max { $0.length < $1.length }?.direction.angle
    }

    /// A graphic scale: four alternating blocks totalling a round model length about 40 mm long on paper.
    static func scaleBar(at p: Vec2, scale s: Double, model: BIMModel, st: GStroke) -> (prims: [GPrimitive], bounds: Rect2) {
        let imperial = model.units.system == .imperial
        let unit = imperial ? 0.3048 : 1.0
        let target = 0.04 * s / unit
        let steps: [Double] = [0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
        let seg = steps.min { abs($0 * 4 - target) < abs($1 * 4 - target) } ?? 1
        let segLen = seg * unit
        let h = s * 0.0015
        var prims: [GPrimitive] = []
        let pen = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        for i in 0..<4 {
            let r = Rect2(min: p + Vec2(Double(i) * segLen, 0), max: p + Vec2(Double(i + 1) * segLen, h))
            if i % 2 == 0 { prims.append(.fill([.rectangle(r)], GFill(pattern: .solid, color: st.color, halftone: st.halftone))) }
            prims.append(.polyline(r.corners, closed: true, pen))
        }
        for i in 0...4 {
            let v = seg * Double(i)
            let txt = v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
            prims.append(.text(GText(position: p + Vec2(Double(i) * segLen, -s * 0.001), height: 0.0018, string: txt, alignment: .center,
                                     verticalAnchor: 1, color: st.color, halftone: st.halftone)))
        }
        let unitName = imperial ? (seg * 4 >= 1 ? "ft" : "ft") : "m"
        prims.append(.text(GText(position: p + Vec2(4 * segLen + s * 0.002, h / 2), height: 0.0018, string: unitName, alignment: .left,
                                 verticalAnchor: 0.5, color: st.color, halftone: st.halftone)))
        let bounds = Rect2(min: p - Vec2(s * 0.002, s * 0.004), max: p + Vec2(4 * segLen + s * 0.006, h + s * 0.001))
        return (prims, bounds)
    }
}
