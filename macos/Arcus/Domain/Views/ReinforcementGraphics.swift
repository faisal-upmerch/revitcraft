import Foundation
import ArcusGeometry

// F34: 2D graphics of reinforcement and beam systems in plans (RevitCraft plan.rs), on their wall in sections and
// elevations (section.rs wall_reinforcement), and the structural symbols of Annotate ▸ Symbol (plan.rs host_symbol).

extension PlanGraphics {
    /// Floor-hosted reinforcement of this level, couplers on its rebar sets and the level's beam systems.
    func f34Items(_ byCategory: [Category: [(Element, GraphicOverride)]]) -> [GItem] {
        var items: [GItem] = []
        for c in Category.f34Structural {
            for (e, o) in byCategory[c] ?? [] {
                if let item = ReinforcementGraphics.planItem(e, o, model: model, level: levelID, builder: builder) { items.append(item) }
            }
        }
        return items
    }

    /// Structural Settings: beams are drawn cut back at their ends by the symbolic beam/truss cutback.
    func f34CutBack(_ outline: Polygon2?, _ e: Element) -> Polygon2? {
        guard let outline, let seg = e.beam?.curve.asSegment else { return outline }
        let k = model.structuralSettings.beamCutback * Double(builder.scale)
        guard k > 0, seg.length > 4 * k else { return outline }
        let d = seg.direction
        return Polygon2(outline.points.map { q in
            let t = (q - seg.start).dot(d)
            return t < seg.length / 2 ? q + d * k : q - d * k
        })
    }
}

extension VerticalGraphics {
    /// Wall-hosted area, path and fabric reinforcement on walls this view looks straight at.
    func f34Items(_ fr: Frame) -> [GItem] {
        var items: [GItem] = []
        for c in [Category.areaReinforcement, .pathReinforcement, .fabricAreas, .fabricReinforcement] {
            for e in model.elements(c) where Reinforcement.isWallHosted(model, e.hostID) {
                guard let o = builder.resolver.resolve(e), let w = Reinforcement.wallFrame(model, e.hostID), abs(w.direction.dot(fr.right)) > 0.999 else { continue }
                let depth = (w.origin - fr.origin.xy).dot(fr.forward)
                guard depth >= -w.thickness, depth <= data.farClip else { continue }
                func uv(_ q: Vec2) -> Vec2 { fr.uv(Vec3(w.origin + w.direction * q.x, z: w.base + q.y)) }
                if let item = ReinforcementGraphics.faceItem(e, o, model: model, map: uv, builder: builder) { items.append(item) }
            }
        }
        return items
    }
}

enum ReinforcementGraphics {
    static func dashed(_ st: GStroke) -> GStroke { GStroke(weight: 1, color: st.color, pattern: .dash, halftone: st.halftone) }
    static func thin(_ st: GStroke) -> GStroke { GStroke(weight: 1, color: st.color, pattern: .solid, halftone: st.halftone) }

    /// The plan item of one element, or nil when it is not on this level (or is wall-hosted).
    static func planItem(_ e: Element, _ o: GraphicOverride, model m: BIMModel, level: ElementID?, builder: ViewGraphicsBuilder) -> GItem? {
        let st = builder.stroke(e.category, cut: false, o)
        if let b = e.beamSystem {
            guard e.levelID == level else { return nil }
            let faint = GStroke(weight: 1, color: o.projectionLineColor ?? RGBColor(0.63, 0.63, 0.63), pattern: .dash, halftone: st.halftone)
            return GItem(elementID: e.id, category: e.category, layer: .model, primitives: [.polyline(b.boundary, closed: true, faint)])
        }
        // Couplers sit with their rebar set's host.
        let hostID = e.rebarCoupler != nil ? m[e.hostID]?.hostID : e.hostID
        guard let host = m[hostID], host.slab != nil, host.levelID == level else { return nil }
        var prims: [GPrimitive] = []
        let bar = GStroke(weight: max(st.weight, 3), color: st.color, pattern: st.pattern, halftone: st.halftone)
        switch e.data {
        case .rebar:
            for b in Reinforcement.rebarBars(e, m) { prims.append(.polyline([b.start.xy, b.end.xy], closed: false, bar)) }
        case .areaReinforcement(let a):
            prims.append(.polyline(a.boundary, closed: true, dashed(st)))
        case .pathReinforcement(let p):
            prims.append(.polyline(p.path, closed: false, st))
            for strip in Reinforcement.pathRegions(e, m) { prims.append(.polyline(strip.points, closed: true, dashed(st))) }
        case .fabricArea(let a):
            prims.append(.polyline(a.boundary, closed: true, dashed(st)))
            for s in Reinforcement.fabricAreaSheets(e, m) { prims.append(.polyline(s.points, closed: true, thin(st))) }
        case .fabricSheet:
            let r = Reinforcement.sheetOutline(e, m)
            guard r.count == 4 else { return nil }
            prims.append(.polyline(r, closed: true, thin(st)))
            prims.append(.polyline([r[0], r[2]], closed: false, thin(st)))
        case .rebarCoupler:
            for (q, ax, d) in Reinforcement.couplerPoints(e, m) {
                let u = ax.xy.normalized * (2 * d), v = ax.xy.normalized.perpendicular * (0.8 * d), c = q.xy
                prims.append(.polyline([c - u - v, c + u - v, c + u + v, c - u + v], closed: true, bar))
            }
        default:
            return nil
        }
        guard !prims.isEmpty else { return nil }
        return GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims)
    }

    /// Wall-hosted reinforcement drawn on its wall: boundaries dashed, paths solid, sheets with their outline, tags.
    static func faceItem(_ e: Element, _ o: GraphicOverride, model m: BIMModel, map: (Vec2) -> Vec2, builder: ViewGraphicsBuilder) -> GItem? {
        let st = builder.stroke(e.category, cut: false, o)
        var prims: [GPrimitive] = []
        func text(_ at: Vec2, _ s: String) -> GPrimitive { .text(GText(position: at, height: 0.002, string: s, alignment: .center, verticalAnchor: 0.5, color: st.color, halftone: st.halftone)) }
        switch e.data {
        case .areaReinforcement(let a):
            prims.append(.polyline(a.boundary.map(map), closed: true, dashed(st)))
            prims.append(text(map(Polygon2(a.boundary).centroid), Reinforcement.areaTag(e, m)))
        case .pathReinforcement(let p):
            prims.append(.polyline(p.path.map(map), closed: false, st))
            let strips = Reinforcement.pathRegions(e, m)
            for s in strips { prims.append(.polyline(s.points.map(map), closed: true, dashed(st))) }
            if let s = strips.first { prims.append(text(map(s.centroid), Reinforcement.pathTag(e, m))) }
        case .fabricArea(let a):
            prims.append(.polyline(a.boundary.map(map), closed: true, dashed(st)))
            for s in Reinforcement.fabricAreaSheets(e, m) { prims.append(.polyline(s.points.map(map), closed: true, thin(st))) }
        case .fabricSheet:
            let r = Reinforcement.sheetOutline(e, m).map(map)
            guard r.count == 4 else { return nil }
            prims += [.polyline(r, closed: true, thin(st)), .polyline([r[0], r[2]], closed: false, thin(st))]
        default:
            return nil
        }
        return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: prims)
    }
}

// MARK: - Symbols

/// Annotate ▸ Symbol and Multi-Rebar annotations, drawn at paper size (scale `s`).
enum StructuralSymbolGraphics {
    static func item(_ e: Element, _ sym: StructuralSymbolData, model m: BIMModel, scale s: Double, st: GStroke) -> GItem? {
        guard let host = m[e.hostID], sym.kind.fits(host) else { return nil }
        let p = primitives(sym, host: host, model: m, scale: s, st: st)
        guard !p.isEmpty else { return nil }
        return GItem(elementID: e.id, category: e.category, layer: .annotation, primitives: p,
                     hitPolygons: AnnotationRenderer.textHits(p, scale: s) + lineHits(p, scale: s))
    }

    /// Thin boxes around the symbol's lines, so the symbol can be picked by them as well as by its text.
    static func lineHits(_ prims: [GPrimitive], scale s: Double) -> [Polygon2] {
        let r = 0.0012 * s
        return prims.flatMap { p -> [Polygon2] in
            guard case .polyline(let pts, _, _) = p, pts.count >= 2 else { return [] }
            return (0..<(pts.count - 1)).compactMap { i in
                let a = pts[i], b = pts[i + 1]
                guard a.distance(to: b) > 1e-9 else { return nil }
                let d = (b - a).normalized * r, n = d.perpendicular
                return Polygon2([a - d - n, b + d - n, b + d + n, a - d + n])
            }
        }
    }

    static func primitives(_ sym: StructuralSymbolData, host: Element, model m: BIMModel, scale s: Double, st: GStroke) -> [GPrimitive] {
        let line = GStroke(weight: 1, color: st.color, pattern: .solid, halftone: st.halftone)
        let fill = GFill(pattern: .solid, color: st.color, halftone: st.halftone)
        func text(_ at: Vec2, _ str: String, align: TextAlignment = .center, rotation: Double = 0) -> GPrimitive {
            .text(GText(position: at, height: 0.002, string: str, rotation: rotation, alignment: align, verticalAnchor: 0.5, color: st.color, halftone: st.halftone))
        }
        func tri(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> GPrimitive { .fill([Polygon2([a, b, c])], fill) }
        let at = sym.position
        var out: [GPrimitive] = []

        /// A span line with ticks at both ends and a label above it.
        func tickSpan(_ dir: Vec2, half: Double, _ label: String) {
            let n = dir.perpendicular, a = at - dir * half, b = at + dir * half
            out.append(.polyline([a, b], closed: false, line))
            let t = (dir + n).normalized * (1.3e-3 * s)
            for q in [a, b] { out.append(.polyline([q - t, q + t], closed: false, GStroke(weight: 2, color: st.color, halftone: st.halftone))) }
            out.append(text(at + n * (2e-3 * s), label, rotation: readable(dir)))
        }
        /// A span arrow with filled half-heads at both ends and a label above it (beam systems and beams).
        func spanArrow(_ dir: Vec2, _ label: String) {
            let n = dir.perpendicular, half = 0.010 * s, head = 0.0035 * s, wing = 0.0016 * s
            let a = at - dir * half, b = at + dir * half
            out.append(.polyline([a, b], closed: false, line))
            out.append(tri(b, b - dir * head + n * wing, b - dir * head))
            out.append(tri(a, a + dir * head - n * wing, a + dir * head))
            out.append(text(at + n * (2.2e-3 * s), label, rotation: readable(dir)))
        }

        switch (sym.kind, host.data) {
        case (.areaReinforcement, .areaReinforcement(let a)):
            // A double arrow along the major direction and the tag.
            let dir = a.major.lengthSquared > 1e-12 ? a.major.normalized : .unitX, n = dir.perpendicular
            let half = 0.008 * s, head = 0.002 * s
            let s0 = at - dir * half, s1 = at + dir * half
            out.append(.polyline([s0, s1], closed: false, line))
            for (tip, back) in [(s1, -dir), (s0, dir)] { out.append(tri(tip, tip + back * head + n * head * 0.4, tip + back * head - n * head * 0.4)) }
            out.append(text(at - n * (2.5e-3 * s), Reinforcement.areaTag(host, m), rotation: readable(dir)))
        case (.pathReinforcement, .pathReinforcement(let r)) where r.path.count >= 2:
            // A bar's extent from the path with an arrow, and the tag.
            let dir = (r.path[1] - r.path[0]).normalized, n = dir.perpendicular * Reinforcement.pathSide(host, m)
            let s0 = at, s1 = at + n * r.length, head = 0.002 * s
            out.append(.polyline([s0, s1], closed: false, line))
            out.append(tri(s1, s1 - n * head + dir * head * 0.4, s1 - n * head - dir * head * 0.4))
            out.append(.polyline([s0 - dir * head * 0.6, s0 + dir * head * 0.6], closed: false, line))
            out.append(text((s0 + s1) / 2 + dir * (2.5e-3 * s), Reinforcement.pathTag(host, m), rotation: readable(n)))
        case (.fabric, .fabricArea(let a)):
            tickSpan(a.major.lengthSquared > 1e-12 ? a.major.normalized : .unitX, half: 0.008 * s, m[a.fabricTypeID]?.name ?? "")
        case (.fabric, .fabricSheet(let f)):
            tickSpan(.fromAngle(f.angle), half: 0.008 * s, m[host.typeID]?.name ?? "")
        case (.rebar, .rebar(let r)):
            // Across the set, as wide as its bars are spread.
            let across = (r.end - r.start).normalized.perpendicular
            tickSpan(across, half: max(r.spacing * Double(max(1, r.count) - 1) / 2, 0.004 * s), Reinforcement.rebarTag(host, m))
        case (.multiRebarAligned, .rebar(let r)), (.multiRebarLinear, .rebar(let r)):
            out += multiRebar(sym, host: host, r, model: m, scale: s, line: line, text: text)
        case (.beamSystem, .beamSystem(let b)):
            spanArrow(b.direction.lengthSquared > 1e-12 ? b.direction.normalized : .unitX, "\(m[b.beamTypeID]?.name ?? "") @ \(Reinforcement.length(b.spacing, m))")
        case (.beamSystem, .beam(let b)):
            guard let seg = b.curve.asSegment else { return [] }
            spanArrow(seg.direction, m.type(of: host)?.name ?? "")
        default:
            break
        }
        return out
    }

    /// A dimension string through a rebar set's bars (across the set, or horizontal/vertical, whichever is nearer),
    /// extension lines to each bar and the set's tag beyond its end.
    static func multiRebar(_ sym: StructuralSymbolData, host: Element, _ r: RebarData, model m: BIMModel, scale s: Double, line: GStroke,
                           text: (Vec2, String, TextAlignment, Double) -> GPrimitive) -> [GPrimitive] {
        let along = (r.end - r.start).normalized, across = along.perpendicular
        let dir: Vec2 = sym.kind == .multiRebarLinear ? (abs(across.x) >= abs(across.y) ? .unitX : .unitY) : across
        guard abs(dir.cross(along)) > 1e-6 else { return [] }
        let o = sym.position, len = r.start.distance(to: r.end)
        // Where each bar's line crosses the dimension line: (point on the bar, foot on the line).
        let feet: [(Vec2, Vec2)] = (0..<max(1, r.count)).map { k in
            let b = r.start + across * (r.spacing * Double(k))
            let t = (o - b).cross(dir) / along.cross(dir)
            return (b + along * min(max(t, 0), len), b + along * t)
        }
        let n = dir.perpendicular, gap = 1.5e-3 * s, ext = 2e-3 * s
        var out: [GPrimitive] = []
        for (bar, foot) in feet {
            let v = (foot - bar).normalized
            if bar.distance(to: foot) > gap { out.append(.polyline([bar + v * gap, foot + v * ext], closed: false, line)) }
            let t = (dir + n).normalized * (1.3e-3 * s)
            out.append(.polyline([foot - t, foot + t], closed: false, GStroke(weight: 2, color: line.color, halftone: line.halftone)))
        }
        let first = feet[0].1, last = feet[feet.count - 1].1
        out.append(.polyline([first - dir * ext, last + dir * ext], closed: false, line))
        let span = first.distance(to: last)
        if span > 0 { out.append(text((first + last) / 2 + n * (1.5e-3 * s), Reinforcement.length(span, m), .center, readable(dir))) }
        let hi = (last - first).dot(dir) >= 0 ? last : first
        out.append(text(hi + dir * (4e-3 * s), Reinforcement.rebarTag(host, m), .left, 0))
        return out
    }

    /// A text angle along `d` that never reads upside down.
    static func readable(_ d: Vec2) -> Double {
        var a = d.angle
        if a > .pi / 2 + 1e-9 { a -= .pi } else if a <= -.pi / 2 + 1e-9 { a += .pi }
        return a
    }
}

extension Reinforcement {
    /// Whether `view` (a section or elevation) looks straight at the wall `host`.
    public static func viewFacesWall(_ view: ViewData, _ host: ElementID?, _ m: BIMModel) -> Bool {
        guard let fr = VerticalGraphics.frame(view), let w = wallFrame(m, host) else { return false }
        return abs(w.direction.dot(fr.right)) > 0.999
    }

    /// A point of a section or elevation (u, z) in the face coordinates of a wall the view looks straight at.
    public static func wallFacePoint(_ p: Vec2, view: ViewData, host: ElementID?, _ m: BIMModel) -> Vec2? {
        guard let fr = VerticalGraphics.frame(view), let w = wallFrame(m, host), abs(w.direction.dot(fr.right)) > 0.999 else { return nil }
        let plan = fr.origin.xy + fr.right * p.x
        return Vec2((plan - w.origin).dot(w.direction), p.y - w.base)
    }

    /// The floor (or foundation slab) of `level` under a plan point, topmost first.
    public static func floor(at p: Vec2, level: ElementID?, _ m: BIMModel) -> Element? {
        m.elements(.floors).filter { $0.levelID == level && $0.slab != nil }.reversed().first { SlabGeometry.profile($0)?.contains(p) == true }
    }
}
