import Foundation
import ArcusGeometry

/// View-specific annotation graphics and markers for other views.
struct AnnotationGraphics {
    let builder: ViewGraphicsBuilder
    var model: BIMModel { builder.model }
    var view: Element { builder.view }
    func paper(_ p: Double) -> Double { builder.paper(p) }

    func build() -> [GItem] {
        var items: [GItem] = []
        for e in model.owned(byView: view.id) {
            guard let o = builder.resolver.resolve(e) else { continue }
            if let item = AnnotationRenderer.item(e, o, model: model, scale: builder.scale, builder: builder) { items.append(item) }
        }
        if builder.data.kind.isPlan { items += markers() }
        return items
    }

    // MARK: View markers

    func markers() -> [GItem] {
        var items: [GItem] = []
        let lvZ = model.elevation(ofLevel: view.levelID)
        for v in model.views where v.id != view.id {
            guard let vd = v.view else { continue }
            switch vd.kind {
            case .section, .detail:
                guard vd.parentViewID == nil || vd.parentViewID == view.id, let fr = VerticalGraphics.frame(vd) else { continue }
                let crop = vd.cropRegion ?? Rect2(min: Vec2(-5, lvZ - 1), max: Vec2(5, lvZ + 10))
                if crop.max.y < lvZ || crop.min.y > lvZ + 20 { continue }
                if builder.resolver.temp.hiddenCategories.contains(.sectionMarks) || builder.resolver.vg.hiddenCategories.contains(.sectionMarks) { continue }
                items.append(sectionMark(v, vd, fr, crop))
            case .elevation:
                guard let fr = VerticalGraphics.frame(vd) else { continue }
                if builder.resolver.vg.hiddenCategories.contains(.elevationMarks) || builder.resolver.temp.hiddenCategories.contains(.elevationMarks) { continue }
                items.append(elevationMark(v, vd, fr))
            default:
                if vd.parentViewID == view.id, let crop = vd.cropRegion, vd.kind.isPlan { items.append(callout(v, crop)) }
            }
        }
        return items
    }

    func refLabels(_ v: Element) -> (detail: String, sheet: String) {
        let vp = model.viewports(showing: v.id).first
        let sheet = vp.flatMap { model[$0.ownerViewID]?.sheet?.number } ?? ""
        return (vp?.viewport?.detailNumber ?? "", sheet)
    }

    func sectionMark(_ v: Element, _ vd: ViewData, _ fr: VerticalGraphics.Frame, _ crop: Rect2) -> GItem {
        let st = GStroke(weight: 2, color: .black)
        let a = fr.origin.xy + fr.right * crop.min.x
        let b = fr.origin.xy + fr.right * crop.max.x
        let r = paper(0.0045)
        let (detail, sheet) = refLabels(v)
        var prims: [GPrimitive] = []
        let segLen = paper(0.008)
        let dir = (b - a).normalized
        // Broken section line: heavy ends, thin middle.
        prims.append(.polyline([a, a + dir * segLen], closed: false, st))
        prims.append(.polyline([b - dir * segLen, b], closed: false, st))
        prims.append(.polyline([a + dir * segLen, b - dir * segLen], closed: false, GStroke(weight: 1, pattern: .center)))
        // Head at a: circle with detail/sheet, arrow toward view direction.
        let c = a - dir * r
        prims.append(.fill([Polygon2([c + fr.forward * r * 1.9, c + dir * r * 0.9, c - dir * r * 0.9])], GFill(pattern: .solid, color: .black)))
        prims.append(.fill([Polygon2(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: r * 0.01).dropLast())], .mask))
        prims.append(.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 1)))
        prims.append(.polyline([c - dir * r, c + dir * r], closed: false, GStroke(weight: 1)))
        prims.append(.text(GText(position: c + Vec2(0, r * 0.45), height: 0.0022, string: detail.isEmpty ? "–" : detail, alignment: .center, verticalAnchor: 0.5)))
        prims.append(.text(GText(position: c - Vec2(0, r * 0.45), height: 0.0018, string: sheet.isEmpty ? "–" : sheet, alignment: .center, verticalAnchor: 0.5)))
        // Tail at b.
        let ct = b + dir * paper(0.002)
        prims.append(.polyline([ct, ct + fr.forward * paper(0.004)], closed: false, st))
        let hit = Polygon2([a - fr.forward * paper(0.003), b - fr.forward * paper(0.003), b + fr.forward * paper(0.003), a + fr.forward * paper(0.003)])
        return GItem(elementID: v.id, category: .sectionMarks, layer: .annotation, primitives: prims, targetViewID: v.id,
                     hitPolygons: [hit, Polygon2(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: r * 0.05).dropLast())])
    }

    func elevationMark(_ v: Element, _ vd: ViewData, _ fr: VerticalGraphics.Frame) -> GItem {
        let r = paper(0.005)
        let c = vd.markerPosition ?? (fr.origin.xy - fr.forward * paper(0.012))
        let (detail, sheet) = refLabels(v)
        var prims: [GPrimitive] = []
        let tip = c + fr.forward * r * 1.7
        let side = fr.right * r * 1.05
        prims.append(.fill([Polygon2([tip, c + side, c - side])], GFill(pattern: .solid, color: .black)))
        prims.append(.fill([Polygon2(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: r * 0.01).dropLast())], .mask))
        prims.append(.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 2)))
        prims.append(.text(GText(position: c + Vec2(0, r * 0.35), height: 0.0022, string: detail.isEmpty ? "–" : detail, alignment: .center, verticalAnchor: 0.5)))
        prims.append(.text(GText(position: c - Vec2(0, r * 0.45), height: 0.0016, string: sheet.isEmpty ? "–" : sheet, alignment: .center, verticalAnchor: 0.5)))
        return GItem(elementID: v.id, category: .elevationMarks, layer: .annotation, primitives: prims, targetViewID: v.id,
                     hitPolygons: [.rectangle(Rect2(center: c, halfSize: Vec2(r * 1.8, r * 1.8)))])
    }

    func callout(_ v: Element, _ crop: Rect2) -> GItem {
        let st = GStroke(weight: 2)
        let (detail, sheet) = refLabels(v)
        let r = paper(0.004)
        let c = Vec2(crop.max.x + r * 1.5, crop.max.y + r * 1.5)
        var prims: [GPrimitive] = [.polyline(crop.corners, closed: true, st)]
        prims.append(.polyline([Vec2(crop.max.x, crop.max.y), c - Vec2(r, r) * 0.7], closed: false, GStroke(weight: 1)))
        prims.append(.arc(Arc2(center: c, radius: r, startAngle: 0, sweep: Angle.twoPi), GStroke(weight: 1)))
        prims.append(.text(GText(position: c + Vec2(0, r * 0.4), height: 0.0018, string: detail.isEmpty ? "–" : detail, alignment: .center, verticalAnchor: 0.5)))
        prims.append(.text(GText(position: c - Vec2(0, r * 0.45), height: 0.0014, string: sheet.isEmpty ? "–" : sheet, alignment: .center, verticalAnchor: 0.5)))
        return GItem(elementID: v.id, category: .callouts, layer: .annotation, primitives: prims, targetViewID: v.id,
                     hitPolygons: [.rectangle(crop.expanded(by: paper(0.002)))])
    }
}

/// Renders individual annotation elements (shared by views and sheets; sheets use scale 1).
public enum AnnotationRenderer {
    public static func item(_ e: Element, _ o: GraphicOverride, model: BIMModel, scale: Int, builder: ViewGraphicsBuilder?) -> GItem? {
        let s = Double(scale)
        func p(_ v: Double) -> Double { v * s }
        let os = ObjectStyles.effective(e.category, builder?.objectStyles ?? model.projectInfo.objectStyles) // BL-VG: project Object Styles
        let st = GStroke(weight: o.projectionLineWeight ?? os.projectionWeight,
                         color: o.projectionLineColor ?? os.color,
                         pattern: o.projectionLinePattern ?? .solid, halftone: o.halftone ?? false)
        // Sections and elevations place annotations in (u, z); plans, drafting views and sheets in plan coordinates.
        let view = builder?.view ?? model[e.ownerViewID]
        switch e.data {
        case .dimension(let d):
            let prims = dimension(e, d, model: model, scale: s, st: st, view: view)
            guard !prims.isEmpty else { return nil }
            return GItem(elementID: e.id, category: .dimensions, layer: .annotation, primitives: prims, hitPolygons: textHits(prims, scale: s))
        case .tag(let t):
            return tagItem(e, t, model: model, scale: s, st: st, view: view)
        case .textNote(let n):
            return textNote(e, n, model: model, scale: s, st: st)
        case .spot(let sp):
            let prims = spot(e, sp, model: model, scale: s, st: st, view: view)
            return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims, hitPolygons: textHits(prims, scale: s))
        case .filledRegion(let f):
            guard case .success(let prof) = f.boundary.profile() else { return nil }
            let style = model.typeData(of: e)
            var prims: [GPrimitive] = []
            if f.isMasking {
                prims.append(.fill(prof.loops, .mask))
            } else {
                prims.append(.fill(prof.loops, ViewGraphicsBuilder.regionFill(style, o, halftone: st.halftone, model))) // W4-HATCH: project fill patterns
                prims += prof.loops.map { .polyline($0.points, closed: true, st) }
            }
            return GItem(elementID: e.id, category: e.category, layer: f.isMasking ? .masking : .fills, primitives: prims, hitPolygons: prof.loops)
        case .modelLine(let l):
            // The line style, with any view override (by category, filter or element) on top.
            var ls = LineStyles.stroke(l.styleID, model, fallback: st)
            if let w = o.projectionLineWeight { ls.weight = w }
            if let c = o.projectionLineColor { ls.color = c }
            if let pt = o.projectionLinePattern { ls.pattern = pt }
            let prim: GPrimitive
            switch l.curve {
            case .line(let sg): prim = .polyline([sg.start, sg.end], closed: false, ls)
            case .arc(let a): prim = .arc(a, ls)
            }
            return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: [prim])
        case .detailComponent(let d) where d.legendTypeID != nil:
            return legendComponent(e, d, model: model, st: st)
        case .detailComponent(let d) where d.repeatEnd != nil:
            return repeatingDetail(e, d, model: model, st: st)
        case .detailComponent(let d):
            guard let ev = FamilyInstanceGeometry.evaluate(e, model) else { return nil }
            let isSymbol = e.category == .genericAnnotations
            var t = Transform2.translation(d.location) * Transform2.rotation(d.rotation)
            if d.mirrored { t = t * Transform2.scale(-1, 1) }
            if isSymbol { t = t * Transform2.scale(s, s) }
            var prims: [GPrimitive] = []
            for f in ev.fills { prims.append(.fill([f.polygon.transformed(t)], f.isMasking ? .mask : GFill(pattern: f.pattern, color: st.color, halftone: st.halftone))) }
            for l in ev.annotationLines + ev.planLines {
                let lst = GStroke(weight: l.weight, color: st.color, halftone: st.halftone)
                switch l.curve.transformed(t) {
                case .line(let sg): prims.append(.polyline([sg.start, sg.end], closed: false, lst))
                case .arc(let a): prims.append(.arc(a, lst))
                }
            }
            for lb in ev.labels {
                let text = lb.parameterName.flatMap { name in Parameters.id(named: name, for: e, model).flatMap { Parameters.value($0, of: e, model) }?.description } ?? lb.staticText
                prims.append(.text(GText(position: t.apply(lb.position), height: lb.height, string: text, rotation: d.rotation, alignment: lb.alignment, verticalAnchor: 0.5, bold: lb.bold, color: st.color)))
            }
            return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims)
        case .revisionCloud(let c):
            let visibility = model[c.revisionID]?.revisionData?.visibility ?? .cloudAndTag
            guard visibility == .cloudAndTag else { return nil }
            let cst = GStroke(weight: 2, color: ObjectStyles.style(.revisionClouds).color, halftone: st.halftone)
            return GItem(elementID: e.id, category: .revisionClouds, layer: .annotation,
                         primitives: cloud(c.outline, arcLength: p(0.012), st: cst), hitPolygons: [c.outline])
        case .insulation(let ins):
            return GItem(elementID: e.id, category: .insulation, layer: .annotation, primitives: insulation(ins, st: st))
        case .referencePlane:
            return nil
        case .colorFillLegend(let l):
            return colorFillLegend(e, l, model: model, scale: s, st: st)
        case .structuralSymbol(let sym): // F34
            return StructuralSymbolGraphics.item(e, sym, model: model, scale: s, st: st)
        default:
            return nil
        }
    }

    // MARK: Dimensions

    static func dimension(_ e: Element, _ d: DimensionData, model: BIMModel, scale s: Double, st: GStroke, view: Element? = nil) -> [GPrimitive] {
        if d.kind == .linear || d.kind == .aligned { return linearDimension(e, d, model: model, scale: s, st: st, view: view) }
        var prims: [GPrimitive] = []
        let style = DimensionStyle.resolve(e, model)
        let textH = style.textSize
        let dimSt = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        switch d.kind {
        case .radial, .diameter, .arcLength:
            guard let r = d.references.first, let el = model[r.elementID] else { return [] }
            let arc: Arc2?
            switch el.data {
            case .wall(let w): arc = w.location.asArc
            case .grid(let g): arc = g.curve.asArc
            case .modelLine(let l): arc = l.curve.asArc
            default: arc = nil
            }
            guard let a = arc else { return [] }
            let dir = (d.linePoint - a.center).normalized
            let onArc = a.center + dir * a.radius
            let value: Double
            let label: String
            switch d.kind {
            case .radial: value = a.radius; label = "R "
            case .diameter: value = a.radius * 2; label = "⌀ "
            default: value = a.length; label = ""
            }
            let from = d.kind == .diameter ? a.center - dir * a.radius : a.center
            let txt = d.textOverride ?? (d.prefix + label + Parameters.format(.double(value), type: .length, model: model) + d.suffix)
            if d.kind == .arcLength {
                // Arc length: a concentric arc through the line point, witness lines to the arc ends, ticks at the ends.
                let r = max(a.radius * 0.05, d.linePoint.distance(to: a.center))
                let da = Arc2(center: a.center, radius: r, startAngle: a.startAngle, sweep: a.sweep)
                prims.append(.arc(da, dimSt))
                let gap = s * style.witnessGap, ext = s * style.witnessExtension
                for (src, q) in [(a.start, da.start), (a.end, da.end)] where src.distance(to: q) > gap * 1.5 {
                    let wd = (q - src).normalized
                    prims.append(.polyline([src + wd * gap, q + wd * ext], closed: false, dimSt))
                }
                prims += dimensionTick(style.tick, at: da.start, direction: da.tangent(at: 0), outward: [-da.tangent(at: 0)], scale: s, st: st)
                prims += dimensionTick(style.tick, at: da.end, direction: da.tangent(at: 1), outward: [da.tangent(at: 1)], scale: s, st: st)
                let out = (da.mid - a.center).normalized
                prims.append(.text(GText(position: da.mid + out * (s * style.textOffset), height: textH, string: txt,
                                         rotation: readable(da.tangent(at: 0.5).angle), alignment: .center, color: st.color, halftone: st.halftone)))
                return prims
            }
            prims.append(.polyline([from, onArc], closed: false, dimSt))
            prims += arrowHead(at: onArc, direction: dir, scale: s, st: dimSt)
            if d.kind == .diameter { prims += arrowHead(at: from, direction: -dir, scale: s, st: dimSt) }
            let up = Vec2.fromAngle(readable(dir.angle)).perpendicular
            prims.append(.text(GText(position: (from + onArc) * 0.5 + up * (s * style.textOffset), height: textH, string: txt,
                                     rotation: readable(dir.angle), alignment: .center, color: st.color, halftone: st.halftone)))
            return prims
        case .angular:
            guard d.references.count >= 2, let r0 = AnnotationGeometry.resolve(d.references[0], model, view: view),
                  let r1 = AnnotationGeometry.resolve(d.references[1], model, view: view),
                  let d0 = r0.direction, let d1 = r1.direction,
                  let hit = Segment2(r0.point, r0.point + d0).lineIntersection(Segment2(r1.point, r1.point + d1)) else { return [] }
            let c = hit.point
            let rad = d.linePoint.distance(to: c)
            var a0 = d0.angle, a1 = d1.angle
            // Choose the pair of rays bracketing the line point.
            let pa = (d.linePoint - c).angle
            for cand0 in [a0, a0 + .pi] { for cand1 in [a1, a1 + .pi] {
                let sweep = Angle.normalize(cand1 - cand0)
                if sweep < .pi, Angle.normalize(pa - cand0) <= sweep { a0 = cand0; a1 = cand1 }
            } }
            let sweep = Angle.normalize(a1 - a0)
            let arc = Arc2(center: c, radius: rad, startAngle: a0, sweep: sweep)
            prims.append(.arc(arc, dimSt))
            prims += dimensionTick(style.tick, at: arc.start, direction: arc.tangent(at: 0), outward: [-arc.tangent(at: 0)], scale: s, st: st)
            prims += dimensionTick(style.tick, at: arc.end, direction: arc.tangent(at: 1), outward: [arc.tangent(at: 1)], scale: s, st: st)
            let txt = d.textOverride ?? String(format: "%@%.2f°%@", d.prefix, Angle.degrees(sweep), d.suffix)
            prims.append(.text(GText(position: arc.mid + (arc.mid - c).normalized * s * 0.0015, height: textH, string: txt,
                                     rotation: readable(arc.tangent(at: 0.5).angle), alignment: .center, color: st.color, halftone: st.halftone)))
            return prims
        case .linear, .aligned:
            return []
        }
    }

    /// Picking areas around the texts of a dimension or spot (clicking a value selects its annotation).
    static func textHits(_ prims: [GPrimitive], scale s: Double) -> [Polygon2] {
        prims.compactMap { p -> Polygon2? in
            guard case .text(let t) = p, !t.string.isEmpty else { return nil }
            let size = TextMetrics.blockSize(t.string, height: t.height) * s
            let u = Vec2.fromAngle(t.rotation), v = u.perpendicular
            let x0: Double = t.alignment == .left ? 0 : t.alignment == .center ? -size.x / 2 : -size.x
            let y1 = size.y * (1 - t.verticalAnchor), y0 = y1 - size.y
            let m = t.height * s * 0.3
            return Polygon2([t.position + u * (x0 - m) + v * (y0 - m), t.position + u * (x0 + size.x + m) + v * (y0 - m),
                             t.position + u * (x0 + size.x + m) + v * (y1 + m), t.position + u * (x0 - m) + v * (y1 + m)])
        }
    }

    static func readable(_ a: Double) -> Double {
        var r = Angle.normalizeSigned(a)
        if r > .pi / 2 + 1e-6 { r -= .pi } else if r <= -.pi / 2 + 1e-6 { r += .pi }
        return r
    }

    static func tick(at p: Vec2, direction n: Vec2, scale s: Double, st: GStroke) -> [GPrimitive] {
        let d = (n + n.perpendicular).normalized * (s * 0.0012)
        return [.polyline([p - d, p + d], closed: false, st)]
    }

    static func arrowHead(at p: Vec2, direction d: Vec2, scale s: Double, st: GStroke) -> [GPrimitive] {
        let a = s * 0.0025
        let n = d.perpendicular
        return [.fill([Polygon2([p, p - d * a + n * a * 0.3, p - d * a - n * a * 0.3])], GFill(pattern: .solid, color: st.color, halftone: st.halftone))]
    }

    static func arrowLeader(from a: Vec2, to b: Vec2, scale s: Double, st: GStroke) -> [GPrimitive] {
        let d = (b - a).normalized
        return [.polyline([a, b], closed: false, GStroke(weight: 1, color: st.color, halftone: st.halftone))] + arrowHead(at: b, direction: d, scale: s, st: st)
    }

    // MARK: Tags

    static func tagValue(_ name: String, of target: Element, _ model: BIMModel) -> String {
        guard let d = Parameters.descriptor(named: name, for: target, model) else { return "?" }
        let s = Parameters.format(Parameters.value(d.id, of: target, model), type: d.type, model: model)
        return s.isEmpty ? "?" : s
    }

    static func tag(_ e: Element, _ t: TagData, model: BIMModel, scale s: Double, st: GStroke, view: Element? = nil) -> [GPrimitive] {
        guard let target = model[t.taggedID] else { return [] }
        var prims: [GPrimitive] = []
        let rot = t.orientation == .vertical ? Double.pi / 2 : 0
        let transform = Transform2.translation(t.head) * Transform2.rotation(rot) * Transform2.scale(s, s)
        if let fam = Parameters.familyDefinition(for: e, model) {
            let ev = FamilyEvaluator.evaluate(Parameters.effectiveFamily(fam, for: e, model), typeName: "project", units: model.units)
            for f in ev.fills { prims.append(.fill([f.polygon.transformed(transform)], f.isMasking ? .mask : GFill(pattern: f.pattern, color: st.color, halftone: st.halftone))) }
            for l in ev.annotationLines {
                let lst = GStroke(weight: l.weight, color: st.color, halftone: st.halftone)
                switch l.curve.transformed(transform) {
                case .line(let sg): prims.append(.polyline([sg.start, sg.end], closed: false, lst))
                case .arc(let a): prims.append(.arc(a, lst))
                }
            }
            for lb in ev.labels {
                let text = lb.parameterName.map { tagValue($0, of: target, model) } ?? lb.staticText
                prims.append(.text(GText(position: transform.apply(lb.position), height: lb.height, string: text, rotation: rot,
                                         alignment: lb.alignment, verticalAnchor: 0.5, bold: lb.bold, color: st.color, halftone: st.halftone)))
            }
        } else {
            // No tag family: the mark (or the room name and number, or the type name) as plain text.
            let typeName = model.type(of: target)?.name ?? "?"
            let txt = target.category == .rooms || target.category == .areas ? "\(target.name)\n\(target.room?.number ?? "")"
                : (target.mark.isEmpty ? (target.category == .structuralFraming ? typeName : "?") : target.mark)
            prims.append(.text(GText(position: t.head, height: 0.0025, string: txt, rotation: rot, alignment: .center, verticalAnchor: 0.5,
                                     color: st.color, halftone: st.halftone)))
        }
        return prims
    }

    public static func leaderAnchor(_ e: Element, _ model: BIMModel) -> Vec2? {
        switch e.data {
        case .insert: return InsertGeometry.placement(e, model)?.plan.apply(.zero)
        case .wall(let w): return w.location.midpoint
        case .room(let r): return r.point
        case .component(let c): return c.location
        case .column(let c): return c.location
        default: return nil
        }
    }

    // MARK: Spots

    static func spot(_ e: Element, _ sp: SpotData, model: BIMModel, scale s: Double, st: GStroke, view: Element?) -> [GPrimitive] {
        spot(SpotGeometry.live(sp, model, view: view), model: model, scale: s, st: st)
    }

    static func spot(_ sp: SpotData, model: BIMModel, scale s: Double, st: GStroke) -> [GPrimitive] {
        let info = model.projectInfo
        var prims: [GPrimitive] = [.polyline([sp.point, sp.leaderHead], closed: false, GStroke(weight: 1, color: st.color, halftone: st.halftone))]
        let a = s * 0.0015
        prims.append(.polyline([sp.point - Vec2(a, a), sp.point + Vec2(a, a)], closed: false, st))
        prims.append(.polyline([sp.point - Vec2(a, -a), sp.point + Vec2(a, -a)], closed: false, st))
        let text: String
        switch sp.kind {
        case .elevation:
            text = Parameters.format(.double(sp.elevation - info.projectBasePoint.z), type: .length, model: model)
            let tri = sp.leaderHead
            prims.append(.polyline([tri, tri + Vec2(-a, a * 1.4), tri + Vec2(a, a * 1.4)], closed: true, st))
        case .coordinate:
            let e = sp.point.x - info.surveyPoint.x + info.surveyEasting
            let n = sp.point.y - info.surveyPoint.y + info.surveyNorthing
            text = "N " + Parameters.format(.double(n), type: .length, model: model) + "\nE " + Parameters.format(.double(e), type: .length, model: model)
        case .slope:
            text = Parameters.format(.double(sp.slope), type: .slope, model: model)
            let d = Vec2.fromAngle(sp.slopeDirection)
            prims += arrowLeader(from: sp.leaderHead - d * s * 0.006, to: sp.leaderHead + d * s * 0.006, scale: s, st: st)
        }
        prims.append(.text(GText(position: sp.leaderHead + Vec2(a * 1.5, a * 1.6), height: 0.0022, string: text, color: st.color, halftone: st.halftone)))
        return prims
    }

    // MARK: Clouds & insulation

    public static func cloud(_ outline: Polygon2, arcLength: Double, st: GStroke) -> [GPrimitive] {
        var prims: [GPrimitive] = []
        let poly = outline.counterClockwise
        for edge in poly.edges {
            let n = max(1, Int((edge.length / max(arcLength, 1e-6)).rounded()))
            for i in 0..<n {
                let a = edge.point(at: Double(i) / Double(n)), b = edge.point(at: Double(i + 1) / Double(n))
                let mid = a.midpoint(b)
                let r = a.distance(to: b) / 2
                guard r > 0 else { continue }
                let start = (a - mid).angle
                // Bulge outward (to the right of a CCW edge).
                prims.append(.arc(Arc2(center: mid, radius: r, startAngle: start, sweep: -.pi), st))
            }
        }
        return prims
    }

    static func insulation(_ ins: InsulationData, st: GStroke) -> [GPrimitive] {
        let seg = ins.line
        let len = seg.length
        guard len > 0, ins.width > 0 else { return [] }
        let w = ins.width
        let n = seg.normal
        let d = seg.direction
        var pts: [Vec2] = []
        let step = w / 2
        var s = 0.0
        var up = true
        while s <= len {
            pts.append(seg.start + d * s + n * (up ? w / 2 : -w / 2))
            up.toggle()
            s += step
        }
        return [.polyline(pts, closed: false, GStroke(weight: 1, color: st.color, halftone: st.halftone)),
                .polyline([seg.start + n * (w / 2), seg.end + n * (w / 2)], closed: false, GStroke(weight: 1, color: st.color, pattern: .hidden, halftone: st.halftone)),
                .polyline([seg.start - n * (w / 2), seg.end - n * (w / 2)], closed: false, GStroke(weight: 1, color: st.color, pattern: .hidden, halftone: st.halftone))]
    }
}
