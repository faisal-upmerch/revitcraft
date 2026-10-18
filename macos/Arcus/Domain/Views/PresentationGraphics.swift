import Foundation
import ArcusGeometry

// F810: 2D graphics of the View tab features: sketched crop boundaries (callouts of any shape), Show Hidden Lines,
// cut profiles, matchlines and walkthrough paths in plans.

extension ViewGraphicsBuilder {
    /// The view's sketched crop boundary (counter-clockwise), when it has one.
    var f810CropShape: Polygon2? {
        guard let s = data.cropShape, s.count >= 3 else { return nil }
        let p = Polygon2(s)
        return p.isDegenerate ? nil : p.counterClockwise
    }

    /// The crop outline drawn when the crop region is visible: the sketched boundary, else the rectangle.
    func f810CropOutline(_ region: Rect2) -> [Vec2] { f810CropShape?.points ?? region.corners }

    /// Model content clipped to the sketched crop boundary (annotations keep the rectangular annotation crop).
    func f810ClipToCropShape(_ items: [GItem]) -> [GItem] {
        guard data.cropActive, let shape = f810CropShape else { return items }
        let chord = paper(0.0002)
        return items.compactMap { item in
            if item.layer == .annotation || item.layer == .overlay { return item }
            guard shape.bounds.intersects(item.bounds) || item.bounds.isEmpty else { return nil }
            var copy = item
            copy.primitives = item.primitives.flatMap { Self.clipPrimitive($0, to: shape, chord: chord) }
            copy.bounds = GItem.computeBounds(copy.primitives, hit: [])
            return copy.primitives.isEmpty ? nil : copy
        }
    }

    /// Clips a primitive to a polygon: lines keep their inside parts, fills are intersected, texts are kept when their
    /// anchor is inside.
    public static func clipPrimitive(_ p: GPrimitive, to shape: Polygon2, chord: Double = 0.01) -> [GPrimitive] {
        switch p {
        case .polyline(let pts, let closed, let st):
            let runs = PresentationGeometry.split(pts, closed: closed, by: [shape]).inside
            return runs.map { .polyline($0, closed: false, st) }
        case .arc(let a, let st):
            return clipPrimitive(.polyline(a.tessellate(chordTolerance: chord), closed: false, st), to: shape, chord: chord)
        case .fill(let polys, let f):
            let clip = [Profile2(outer: shape)]
            let out = polys.flatMap { poly -> [Polygon2] in
                guard poly.count >= 3 else { return [] }
                return PolygonBoolean.intersection([Profile2(outer: poly.counterClockwise)], clip).flatMap(\.loops)
            }
            return out.isEmpty ? [] : [.fill(out, f)]
        case .text(let t):
            return shape.contains(t.position) ? [p] : []
        }
    }

    /// Plans: matchlines, walkthrough paths and Show Hidden Lines; sections and elevations: Show Hidden Lines.
    func f810Graphics(_ items: [GItem]) -> [GItem] {
        var items = items
        if data.kind.isPlan {
            items += f810Matchlines()
            items += f810WalkthroughPaths()
            items = f810PlanHiddenLines(items)
        } else if data.kind.isVerticalCut {
            items += f810VerticalHiddenLines()
        }
        return items
    }

    // MARK: Matchlines

    public static let matchlineStroke = GStroke(weight: 6, color: RGBColor(80.0 / 255, 0, 120.0 / 255), pattern: .dashDot)

    func f810Matchlines() -> [GItem] {
        model.elements(.matchlines).compactMap { e -> GItem? in
            guard let m = e.matchline, let o = resolver.resolve(e) else { return nil }
            var st = Self.matchlineStroke
            if let w = o.projectionLineWeight { st.weight = w }
            if let c = o.projectionLineColor { st.color = c }
            if let p = o.projectionLinePattern { st.pattern = p }
            st.halftone = o.halftone ?? false
            let n = m.segment.direction.perpendicular * paper(0.0015)
            let hit = Polygon2([m.start - n, m.end - n, m.end + n, m.start + n])
            return GItem(elementID: e.id, category: .matchlines, layer: .model, primitives: [.polyline([m.start, m.end], closed: false, st)], hitPolygons: [hit])
        }
    }

    // MARK: Walkthrough paths

    /// Walkthroughs whose path lies on this plan's level show their path, with the current frame's camera.
    func f810WalkthroughPaths() -> [GItem] {
        guard resolver.categoryShown(.cameras), let level = view.levelID else { return [] }
        let st = GStroke(weight: 1, color: RGBColor(0.15, 0.35, 0.75))
        var items: [GItem] = []
        for v in model.views {
            guard let vd = v.view, let w = vd.walkthrough, w.path.count >= 2 else { continue }
            guard CameraViews.level(forEyeZ: w.path[0].z, model) == level || v.levelID == level else { continue }
            let pts = w.path.map(\.xy)
            var prims: [GPrimitive] = [.polyline(pts, closed: false, st)]
            let r = paper(0.0012)
            for q in pts { prims.append(.arc(Arc2(center: q, radius: r, startAngle: 0, sweep: Angle.twoPi), st)) }
            let (eye, target) = w.camera(frame: w.frame)
            let d = (target.xy - eye.xy)
            if d.length > 1e-9 {
                let f = d.normalized, s = f.perpendicular * paper(0.002)
                let tip = eye.xy + f * paper(0.004)
                prims.append(.fill([Polygon2([tip, eye.xy + s, eye.xy - s])], GFill(pattern: .solid, color: st.color)))
            }
            let hits = zip(pts, pts.dropFirst()).map { a, b -> Polygon2 in
                let n = (b - a).normalized.perpendicular * paper(0.0015)
                return Polygon2([a - n, b - n, b + n, a + n])
            }
            items.append(GItem(elementID: v.id, category: .cameras, layer: .annotation, primitives: prims, targetViewID: v.id, hitPolygons: hits))
        }
        return items
    }

    // MARK: Show Hidden Lines

    /// The Show Hidden Lines pairs of this view whose elements are both shown.
    var f810HiddenLinePairs: [HiddenLinePair] {
        (data.hiddenLines ?? []).filter { p in
            guard let a = model[p.obscuring], let b = model[p.hidden] else { return false }
            return resolver.resolve(a) != nil && resolver.resolve(b) != nil
        }
    }

    /// Plans: the parts of a hidden element's lines inside its obscuring element's outline are drawn dashed, on top
    /// of the obscuring element (as RevitCraft's `dash_inside`).
    func f810PlanHiddenLines(_ items: [GItem]) -> [GItem] {
        let pairs = f810HiddenLinePairs
        guard !pairs.isEmpty else { return items }
        var items = items
        var extra: [GItem] = []
        let chord = paper(0.0002)
        for pair in pairs {
            let obscurers = items.filter { $0.elementID == pair.obscuring && $0.layer != .annotation && $0.layer != .overlay }
            let polys = obscurers.flatMap { o -> [Polygon2] in
                let hits = o.hitPolygons.filter { $0.count >= 3 && !$0.isDegenerate }
                if !hits.isEmpty { return hits }
                return o.primitives.flatMap { p -> [Polygon2] in if case .fill(let ps, _) = p { return ps.filter { $0.count >= 3 } }; return [] }
            }
            guard !polys.isEmpty else { continue }
            let layer = obscurers.map(\.layer).max() ?? .model
            for i in items.indices where items[i].elementID == pair.hidden && items[i].layer != .annotation && items[i].layer != .overlay {
                var kept: [GPrimitive] = [], dashed: [GPrimitive] = []
                for p in items[i].primitives {
                    let (pts, closed, st): ([Vec2], Bool, GStroke)
                    switch p {
                    case .polyline(let q, let c, let s): (pts, closed, st) = (q, c, s)
                    case .arc(let a, let s): (pts, closed, st) = (a.tessellate(chordTolerance: chord), false, s)
                    default: kept.append(p); continue
                    }
                    let parts = PresentationGeometry.split(pts, closed: closed, by: polys)
                    guard !parts.inside.isEmpty else { kept.append(p); continue }
                    kept += parts.outside.map { .polyline($0, closed: false, st) }
                    var hs = st; hs.pattern = .hidden
                    dashed += parts.inside.map { .polyline($0, closed: false, hs) }
                }
                guard !dashed.isEmpty else { continue }
                items[i].primitives = kept
                extra.append(GItem(elementID: pair.hidden, category: items[i].category, layer: max(layer, items[i].layer), primitives: dashed, hitPolygons: []))
            }
        }
        return items + extra
    }

    /// Sections and elevations: the edges of a hidden element that its obscuring element hides from view are drawn
    /// dashed (hidden-line pass of the element alone minus the pass with its obscurer).
    func f810VerticalHiddenLines() -> [GItem] {
        let pairs = f810HiddenLinePairs
        guard !pairs.isEmpty, let fr = VerticalGraphics.frame(data) else { return [] }
        let isSection = data.kind != .elevation
        let proj = ViewProjection(origin: Vec3(fr.origin.x, fr.origin.y, 0), right: Vec3(fr.right.x, fr.right.y, 0), up: .unitZ,
                                  near: isSection ? 0.0005 : 0, far: data.farClip)
        func mesh(_ e: Element) -> Mesh {
            var m = Mesh()
            for p in GeometryCache.shared.parts(e, model, detail: detailLevel(e.category)) where p.isVisible(lookingAlong: fr.forward) { m.append(p.mesh) }
            return m
        }
        var items: [GItem] = []
        for pair in pairs {
            guard let h = model[pair.hidden], let o = model[pair.obscuring], let ho = resolver.resolve(h) else { continue }
            let hm = mesh(h), om = mesh(o)
            guard !hm.isEmpty, !om.isEmpty else { continue }
            let alone = HiddenLineRenderer.render([HLRInput(tag: 0, mesh: hm)], projection: proj, clip: data.cropRegion, isCancelled: isCancelled)
            let shown = HiddenLineRenderer.render([HLRInput(tag: 0, mesh: hm), HLRInput(tag: 1, mesh: om)], projection: proj, clip: data.cropRegion,
                                                  isCancelled: isCancelled).filter { $0.tag == 0 }.map(\.segment)
            let hidden = PresentationGeometry.subtract(alone.map(\.segment), shown, tolerance: paper(0.0001))
            guard !hidden.isEmpty else { continue }
            var st = stroke(h.category, cut: false, ho)
            st.pattern = .hidden
            items.append(GItem(elementID: h.id, category: h.category, layer: .model, primitives: hidden.map { .polyline([$0.start, $0.end], closed: false, st) }, hitPolygons: []))
        }
        return items
    }
}

// MARK: - Cut profiles in plans

extension PlanGraphics {
    /// The wall's cut pieces reshaped by this view's cut profiles (RevitCraft unions or subtracts each region).
    func f810CutProfiles(_ w: Element, _ pieces: [Polygon2]) -> [Polygon2] {
        let profiles = model.owned(byView: builder.view.id).filter { $0.hostID == w.id }.compactMap(\.cutProfile).filter { $0.region.count >= 3 }
        guard !profiles.isEmpty, !pieces.isEmpty else { return pieces }
        var shape = pieces.filter { $0.count >= 3 }.map { Profile2(outer: $0.counterClockwise) }
        for cp in profiles {
            let r = [Profile2(outer: Polygon2(cp.region).counterClockwise)]
            shape = cp.adds ? PolygonBoolean.union(shape + r) : PolygonBoolean.difference(shape, r)
        }
        return shape.map(\.outer).filter { !$0.isDegenerate }
    }
}

// MARK: - Geometry helpers

/// Polyline splitting and segment subtraction used by the crop shape and Show Hidden Lines.
public enum PresentationGeometry {
    /// Splits a polyline into its runs inside and outside the union of `polys` (boundary counts as inside).
    public static func split(_ pts: [Vec2], closed: Bool, by polys: [Polygon2]) -> (inside: [[Vec2]], outside: [[Vec2]]) {
        let n = closed ? pts.count : pts.count - 1
        guard n > 0 else { return ([], []) }
        let bounds = polys.reduce(Rect2.empty) { $0.union($1.bounds) }
        var inside: [[Vec2]] = [], outside: [[Vec2]] = []
        var run: [Vec2] = []
        var runInside: Bool?
        func flush() {
            if run.count >= 2, let i = runInside { if i { inside.append(run) } else { outside.append(run) } }
            run = []; runInside = nil
        }
        for k in 0..<n {
            let s = Segment2(pts[k], pts[(k + 1) % pts.count])
            guard s.length > 1e-12 else { continue }
            var ts: [Double] = [0, 1]
            if bounds.intersects(Rect2(points: [s.start, s.end])) {
                for p in polys {
                    for e in p.edges {
                        if let h = s.lineIntersection(e), h.t > 1e-9, h.t < 1 - 1e-9, h.u >= -1e-9, h.u <= 1 + 1e-9 { ts.append(h.t) }
                    }
                }
            }
            ts.sort()
            for j in 0..<(ts.count - 1) where ts[j + 1] - ts[j] > 1e-9 {
                let a = s.point(at: ts[j]), b = s.point(at: ts[j + 1])
                let mid = s.point(at: (ts[j] + ts[j + 1]) / 2)
                let isIn = polys.contains { $0.contains(mid) }
                if runInside != isIn || run.last.map({ !$0.isAlmostEqual(a) }) ?? true {
                    flush()
                    run = [a]; runInside = isIn
                }
                run.append(b)
            }
        }
        flush()
        return (inside, outside)
    }

    /// The parts of `segments` not covered by any collinear segment of `cover`.
    public static func subtract(_ segments: [Segment2], _ cover: [Segment2], tolerance: Double) -> [Segment2] {
        var out: [Segment2] = []
        for s in segments {
            let len = s.length
            guard len > tolerance else { continue }
            let d = s.direction
            var covered: [(Double, Double)] = []
            for c in cover {
                guard abs(d.cross(c.direction)) < 1e-4, s.distanceToLine(c.start) < tolerance, s.distanceToLine(c.end) < tolerance else { continue }
                let t0 = (c.start - s.start).dot(d) / len, t1 = (c.end - s.start).dot(d) / len
                let lo = max(0, min(t0, t1)), hi = min(1, max(t0, t1))
                if hi > lo { covered.append((lo, hi)) }
            }
            covered.sort { $0.0 < $1.0 }
            var t = 0.0
            let eps = tolerance / len
            for (lo, hi) in covered {
                if lo > t + eps { out.append(Segment2(s.point(at: t), s.point(at: lo))) }
                t = max(t, hi)
            }
            if t < 1 - eps { out.append(Segment2(s.point(at: t), s.end)) }
        }
        return out
    }
}

extension Segment2 {
    /// Distance from `p` to the infinite line through the segment.
    func distanceToLine(_ p: Vec2) -> Double {
        let v = end - start
        let l = v.length
        guard l > 1e-12 else { return p.distance(to: start) }
        return abs(v.cross(p - start)) / l
    }
}
