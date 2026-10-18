import Foundation
import ArcusGeometry

public enum DatumGraphics {
    public static let bubbleRadius = 0.004   // paper meters
    static let bubbleText = 0.0032

    static func bubble(at c: Vec2, label: String, builder: ViewGraphicsBuilder, st: GStroke) -> [GPrimitive] {
        let r = builder.paper(bubbleRadius)
        return [
            .fill([Polygon2(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: r * 0.01).dropLast())], .mask),
            .arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 1, color: st.color, halftone: st.halftone)),
            .text(GText(position: c, height: bubbleText, string: label, alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)),
        ]
    }

    static func gridPlan(_ g: Element, _ gd: GridData, builder: ViewGraphicsBuilder, _ o: GraphicOverride) -> GItem {
        if gd.isMultiSegment { return multiSegmentGridPlan(g, gd, builder: builder, o) } // F2
        let st = builder.stroke(.grids, cut: false, o)
        var prims: [GPrimitive] = []
        let r = builder.paper(bubbleRadius)
        let ext = gd.extent(in: builder.view.id)
        switch gd.curve(in: builder.view.id) {
        case .line(let s):
            let d = s.direction
            let k = builder.paper(0.006)
            // I4: as in RevitCraft (`grid_graphics`), the bubble hangs beyond the grid's end, so the end (and its grip)
            // stays clear of it. An elbow jogs it aside: back along the grid, across by the offset, then out to the bubble.
            func end(_ p: Vec2, out: Vec2, show: Bool, elbow: Vec2?) -> Vec2 {
                guard show, let o = elbow else { return p }
                prims.append(.polyline([p - out * (k * 2), p - out * k + o, p + o], closed: false, st))
                return p - out * (k * 2)
            }
            let a = end(s.start, out: -d, show: gd.bubbleAtStart, elbow: ext?.elbowStart)
            let b = end(s.end, out: d, show: gd.bubbleAtEnd, elbow: ext?.elbowEnd)
            prims.append(.polyline([a, b], closed: false, st))
            if gd.bubbleAtStart { prims += bubble(at: s.start + (ext?.elbowStart ?? .zero) - d * r, label: g.name, builder: builder, st: st) }
            if gd.bubbleAtEnd { prims += bubble(at: s.end + (ext?.elbowEnd ?? .zero) + d * r, label: g.name, builder: builder, st: st) }
        case .arc(let a):
            prims.append(.arc(a, st))
            if gd.bubbleAtStart { prims += bubble(at: a.start, label: g.name, builder: builder, st: st) }
            if gd.bubbleAtEnd { prims += bubble(at: a.end, label: g.name, builder: builder, st: st) }
        }
        return GItem(elementID: g.id, category: .grids, layer: .annotation, primitives: prims)
    }

    static func shift(_ p: GPrimitive, by v: Vec2) -> GPrimitive {
        if v == .zero { return p }
        switch p {
        case .polyline(let pts, let c, let s): return .polyline(pts.map { $0 + v }, closed: c, s)
        case .arc(var a, let s): a.center = a.center + v; return .arc(a, s)
        case .fill(let polys, let f): return .fill(polys.map { Polygon2($0.points.map { $0 + v }) }, f)
        case .text(var t): t.position = t.position + v; return .text(t)
        }
    }

    /// Level line in an elevation/section: horizontal line across the view with a target symbol and labels.
    static func levelVertical(_ l: Element, _ ld: LevelData, from u0: Double, to u1: Double, builder: ViewGraphicsBuilder, _ o: GraphicOverride) -> GItem {
        let st = builder.stroke(.levels, cut: false, o)
        let z = ld.elevation
        let s = ld.extentStart ?? u0, e = ld.extentEnd ?? u1
        var prims: [GPrimitive] = [.polyline([Vec2(s, z), Vec2(e, z)], closed: false, st)]
        let r = builder.paper(0.0025)
        func head(_ x: Double, left: Bool) {
            let c = Vec2(x, z)
            prims.append(.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 1, color: st.color, halftone: st.halftone)))
            prims.append(.fill([Polygon2([c, c + Vec2(r, 0), c + Vec2(0, r)]), Polygon2([c, c - Vec2(r, 0), c - Vec2(0, r)])], GFill(pattern: .solid, color: st.color, halftone: st.halftone)))
            let tx = left ? x - builder.paper(0.004) : x + builder.paper(0.004)
            let elev = QuantityFormatterBridge.length(z, builder.model)
            prims.append(.text(GText(position: Vec2(tx, z + builder.paper(0.0012)), height: 0.0025, string: l.name, alignment: left ? .right : .left, color: st.color, halftone: st.halftone)))
            prims.append(.text(GText(position: Vec2(tx, z - builder.paper(0.0038)), height: 0.002, string: elev, alignment: left ? .right : .left, color: st.color, halftone: st.halftone)))
        }
        if ld.showBubbleEnd { head(e, left: false) }
        if ld.showBubbleStart { head(s, left: true) }
        return GItem(elementID: l.id, category: .levels, layer: .annotation, primitives: prims)
    }

    static func gridVertical(_ g: Element, at u: Double, z0: Double, z1: Double, builder: ViewGraphicsBuilder, _ o: GraphicOverride) -> GItem {
        let st = builder.stroke(.grids, cut: false, o)
        let r = builder.paper(bubbleRadius)
        var prims: [GPrimitive] = [.polyline([Vec2(u, z0), Vec2(u, z1)], closed: false, st)]
        prims += bubble(at: Vec2(u, z1 + r), label: g.name, builder: builder, st: st)
        return GItem(elementID: g.id, category: .grids, layer: .annotation, primitives: prims)
    }
}

/// Formatting bridge so Domain view code can format lengths with project units.
enum QuantityFormatterBridge {
    static func length(_ v: Double, _ model: BIMModel) -> String {
        Parameters.format(.double(v), type: .length, model: model)
    }
}

enum LinkGraphics {
    static func item(_ l: Element, _ ld: LinkData, _ d: ReferenceDrawing, builder: ViewGraphicsBuilder, _ o: GraphicOverride, layer: GItem.Layer) -> GItem {
        var prims: [GPrimitive] = []
        let hiddenLayers: Set<String> = Set(ld.layers.filter { !$0.visible }.map(\.name))
            .union(builder.resolver.vg.hiddenLinkLayers[l.id] ?? [])
        let halftoneLayers = Set(ld.layers.filter(\.halftone).map(\.name))
        let t = ld.placement
        let halftoneAll = (o.halftone ?? false) || ld.opacity < 0.6
        func style(_ s: ReferenceDrawing.Style) -> GStroke? {
            guard s.layer >= 0, s.layer < d.layers.count else { return GStroke(weight: 1) }
            let layer = d.layers[s.layer]
            if hiddenLayers.contains(layer.name) || !layer.isOn || layer.isFrozen { return nil }
            let color = o.projectionLineColor ?? s.color ?? layer.color
            let lw = s.lineWeight ?? layer.lineWeight
            let weight = lw.map { w in LineWeights.base.firstIndex { $0 >= w - 0.001 }.map { $0 + 1 } ?? 1 } ?? 1
            return GStroke(weight: weight, color: color.luminance > 0.92 ? .black : color, halftone: halftoneAll || halftoneLayers.contains(layer.name))
        }
        var count = 0
        for e in d.flattened() {
            count += 1
            if count > 400_000 { break }
            guard let st = style(e.style) else { continue }
            switch e.transformed(t) {
            case .line(let s, _): prims.append(.polyline([s.start, s.end], closed: false, st))
            case .polyline(let p, let c, _): prims.append(.polyline(p, closed: c, st))
            case .arc(let a, _): prims.append(.arc(a, st))
            case .text(let p, let h, let r, let s, let al, _):
                prims.append(.text(GText(position: p, height: h / Double(builder.scale), string: s, rotation: r, alignment: al, color: st.color, halftone: st.halftone)))
            case .hatch(let loops, let solid, _):
                let polys = loops.map { Polygon2($0) }.filter { !$0.isDegenerate }
                prims.append(.fill(polys, GFill(pattern: solid ? .solid : .diagonalUp, color: st.color, transparency: solid ? 0.3 : 0, halftone: st.halftone)))
            case .point(let p, _):
                let s = builder.paper(0.0005)
                prims.append(.polyline([p - Vec2(s, 0), p + Vec2(s, 0)], closed: false, st))
            case .face3D(let pts, _): prims.append(.polyline(pts.map(\.xy), closed: true, st))
            case .proxy(let r, _, _): prims.append(.polyline(r.corners, closed: true, GStroke(weight: 1, color: RGBColor(0.8, 0.4, 0.1), pattern: .dash)))
            case .imageRef(_, let c, _): prims.append(.polyline(c, closed: true, GStroke(weight: 1, color: .gray, pattern: .dash)))
            case .insert: break
            }
        }
        let bounds = Rect2(points: d.extents.corners.map(t.apply))
        return GItem(elementID: l.id, category: .importedCAD, layer: layer, primitives: prims, hitPolygons: [.rectangle(bounds)])
    }
}
