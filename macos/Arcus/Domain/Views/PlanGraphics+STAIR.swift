import Foundation
import ArcusGeometry

// STAIR: stairs (and their railings) in plan as on a Revit-style CD set.
// - On the plan the stair starts from (the plan's cut plane passes through it): everything below the cut plane is
//   solid; the cut mark (the stair type's Cut Mark Type: double zigzag by default) crosses the run where the nosing line
//   reaches the cut plane, slanted across the run; everything beyond it draws with the "<Above>" subcategories, dashed.
//   The stair path starts with a circle at the first riser, runs up the middle of the runs and through the landings,
//   and ends with an arrowhead at the cut mark; Up Text ("UP") by its start.
// - On the plan of the level the stair arrives at, the whole stair shows below in projection, with its path from the
//   top (circle at the last riser) down to the arrowhead at the first riser, and Down Text ("DN") by the top. Where an
//   upper storey of the stair (multistory) or another stair rises from this level over it, only the part beyond the
//   rising stair's cut mark shows, as Revit draws stacked stairs.

/// Plan subcategories of stairs and railings (Visibility/Graphics and Object Styles).
public enum StairSubcategory {
    public static let outlines = "Outlines"
    public static let nosingLines = "Nosing Lines"
    public static let cutMarks = "Cut Marks"
    public static let stairPath = "Stair Path"
    public static let supports = "Supports"
    public static let above = "<Above> "
    public static let stairs: [String] = [outlines, nosingLines, cutMarks, stairPath, supports].flatMap { [$0, above + $0] }
    public static let topRails = "Top Rails"
    public static let balusters = "Balusters"
    public static let railings: [String] = [topRails, balusters].flatMap { [$0, above + $0] }
}

/// Which side of a stair's cut mark a plan point is on.
enum StairZone { case below, gap, above }

/// A stair as one plan sees it: cut by the plan (with or without a cut mark) or arriving from below.
struct StairPlanView {
    enum Relation { case cut, arrival }
    let layout: StairLayout
    let relation: Relation
    /// The run the cut plane crosses and the cut mark across it: a point on the walk line, the mark's direction, the
    /// normal toward the part above, and the gap between the two lines of a double mark.
    struct Cut { var run: Int; var point: Vec2; var along: Vec2; var normal: Vec2; var gap: Double; var width: Double; var station: Double }
    let cut: Cut?
    let cutZ: Double

    init?(_ l: StairLayout, levelZ: Double, cutZ: Double, depthZ: Double, paper: (Double) -> Double) {
        layout = l
        self.cutZ = cutZ
        if l.baseZ <= cutZ + 0.01, l.topZ > levelZ + 0.05 {
            relation = .cut
            cut = l.topZ > cutZ ? Self.cutMark(l, cutZ: cutZ, paper: paper) : nil
        } else if l.topZ <= cutZ + 0.01, l.topZ >= depthZ - 0.05, l.baseZ < levelZ - 0.01 {
            relation = .arrival
            cut = nil
        } else {
            return nil
        }
    }

    /// Where the nosing line reaches the cut plane.
    static func cutMark(_ l: StairLayout, cutZ: Double, paper: (Double) -> Double) -> Cut? {
        guard let i = l.runs.indices.first(where: { l.runs[$0].topZ > cutZ + 1e-9 }) else { return nil }
        let r = l.runs[i]
        let rl = r.riserLines
        guard !rl.isEmpty else { return nil }
        var s = rl[0].station
        if cutZ > rl[0].z1 {
            s = rl.last!.station
            for (a, b) in zip(rl, rl.dropFirst()) where cutZ <= b.z1 {
                s = a.station + (b.station - a.station) * (cutZ - a.z1) / max(b.z1 - a.z1, 1e-9)
                break
            }
        }
        let p = r.walkPoint(s)
        // Travel direction there, and the mark slanted 30° off the riser direction.
        let d0 = r.walkPoint(min(s + 0.01, r.walkLength)) - r.walkPoint(max(s - 0.01, 0))
        let t = d0.length > 1e-9 ? d0.normalized : r.direction
        let u = -t.perpendicular // left → right across the run
        let along = (u * cos(Double.pi / 6) + t * sin(Double.pi / 6)).normalized
        let gap = l.type.cutMark == .doubleZigzag ? paper(0.002) : 0
        return Cut(run: i, point: p, along: along, normal: t, gap: gap, width: r.width, station: s)
    }

    func zone(_ p: Vec2) -> StairZone {
        guard let c = cut else { return .below }
        // Far from the mark along the run (the other legs of a winder, the rest of a spiral) the walk distance decides;
        // near it, the side of the slanted mark.
        let s = Self.station(of: p, on: layout.runs[c.run])
        if s < c.station - c.width * 0.6 { return .below }
        if s > c.station + c.width * 0.6 { return .above }
        let n = c.along.perpendicular * (c.along.perpendicular.dot(c.normal) >= 0 ? 1 : -1)
        let d = (p - c.point).dot(n)
        if d < -c.gap / 2 - 1e-9 { return .below }
        if d > c.gap / 2 + 1e-9 { return .above }
        return .gap
    }

    /// Walk distance along a run of the walk-line point nearest `p`.
    static func station(of p: Vec2, on r: StairLayout.Run) -> Double {
        guard r.walk.count >= 2 else { return 0 }
        var best = (Double.infinity, 0.0)
        for i in 0..<(r.walk.count - 1) {
            let seg = Segment2(r.walk[i], r.walk[i + 1])
            let t = seg.isDegenerate ? 0 : max(0, min(1, seg.parameter(of: p)))
            let d = seg.point(at: t).distance(to: p)
            if d < best.0 - 1e-9 { best = (d, r.walkStations[i] + (r.walkStations[i + 1] - r.walkStations[i]) * t) }
        }
        return best.1
    }

    /// Zone of a whole run or landing that isn't the cut one.
    func runZone(_ index: Int) -> StairZone? {
        guard let c = cut else { return .below }
        if index == c.run { return nil }
        return index < c.run ? .below : .above
    }
    func landingZone(_ land: StairLayout.Landing) -> StairZone { cut == nil || land.z < cutZ - 1e-9 ? .below : .above }

    /// Zone of a plan point by the part of the stair it lies on (or nearest to).
    func zoneAt(_ p: Vec2) -> StairZone {
        guard cut != nil else { return .below }
        var best = (Double.infinity, StairZone.below)
        for (i, r) in layout.runs.enumerated() {
            let o = r.outline
            let d = o.contains(p) ? 0 : o.distanceToBoundary(p)
            if d < best.0 - 1e-9 { best = (d, runZone(i) ?? zone(p)) }
        }
        for land in layout.landings {
            let d = land.polygon.contains(p) ? 0 : land.polygon.distanceToBoundary(p)
            if d < best.0 - 1e-9 { best = (d, landingZone(land)) }
        }
        return best.1
    }

    /// Splits a polyline into pieces by zone: of run `run` when given, else by where each piece lies.
    func split(_ pts: [Vec2], run: Int?, zone fixed: StairZone? = nil) -> [([Vec2], StairZone)] {
        if let fixed { return [(pts, fixed)] }
        if let run, let z = runZone(run) { return [(pts, z)] }
        guard let c = cut, pts.count >= 2 else { return [(pts, .below)] }
        let onCutRun = run != nil
        let n = c.along.perpendicular * (c.along.perpendicular.dot(c.normal) >= 0 ? 1 : -1)
        var out: [([Vec2], StairZone)] = []
        func push(_ a: Vec2, _ b: Vec2) {
            guard a.distance(to: b) > 1e-9 else { return }
            let z = onCutRun ? zone(a.midpoint(b)) : zoneAt(a.midpoint(b))
            if let last = out.last, last.1 == z, last.0.last?.isAlmostEqual(a) == true { out[out.count - 1].0.append(b) } else { out.append(([a, b], z)) }
        }
        for (a, b) in zip(pts, pts.dropFirst()) {
            // Cut the segment at both mark lines.
            var ts: [Double] = [0, 1]
            for off in [-c.gap / 2, c.gap / 2] {
                let da = (a - c.point).dot(n) - off, db = (b - c.point).dot(n) - off
                if (da < 0) != (db < 0), abs(da - db) > 1e-12 { ts.append(da / (da - db)) }
            }
            ts.sort()
            for (t0, t1) in zip(ts, ts.dropFirst()) { push(a.lerp(to: b, t: t0), a.lerp(to: b, t: t1)) }
        }
        return out
    }

    /// The region of the stair below its cut mark (what a stair rising from this plan hides of the one below).
    var belowRegion: [Polygon2] {
        guard relation == .cut else { return [] }
        var out: [Polygon2] = []
        for (i, r) in layout.runs.enumerated() {
            switch runZone(i) {
            case .below?: out.append(r.outline)
            case .some: break
            case nil:
                guard let c = cut else { continue }
                let n = c.along.perpendicular * (c.along.perpendicular.dot(c.normal) >= 0 ? 1 : -1)
                // Clip the run outline to the half-plane behind the mark.
                var pts: [Vec2] = []
                let o = r.outline.points
                for k in o.indices {
                    let a = o[k], b = o[(k + 1) % o.count]
                    let da = (a - c.point).dot(n) + c.gap / 2, db = (b - c.point).dot(n) + c.gap / 2
                    if da <= 0 { pts.append(a) }
                    if (da < 0) != (db < 0), abs(da - db) > 1e-12 { pts.append(a.lerp(to: b, t: da / (da - db))) }
                }
                if pts.count >= 3 { out.append(Polygon2(pts)) }
            }
        }
        out += layout.landings.filter { landingZone($0) == .below }.map(\.polygon)
        return out
    }

    /// The stair path through the whole stair (StairGeometry.walkPath).
    var walkPath: [Vec2] { StairGeometry.walkPath(layout) }
}

extension PlanGraphics {
    /// Plan symbols of stairs (every storey of a multistory stair).
    func stairItems(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        let views = stairViews(list)
        let masks = views.flatMap { $0.view.relation == .cut ? $0.view.belowRegion : [] }
        for v in views {
            items.append(stairSymbol(v.element, v.storey, v.view, v.override, masks: v.view.relation == .arrival ? masks : []))
        }
        return items
    }

    /// The stair storeys this plan shows, with how it sees each.
    func stairViews(_ list: [(Element, GraphicOverride)]) -> [(element: Element, storey: Element, view: StairPlanView, override: GraphicOverride)] {
        var out: [(Element, Element, StairPlanView, GraphicOverride)] = []
        for (e, o) in list {
            for s in MultistoryStairs.storeys(of: e, model) ?? [e] {
                guard let l = StairGeometry.layout(s, model),
                      let v = StairPlanView(l, levelZ: levelZ, cutZ: cutZ, depthZ: depthZ, paper: { builder.paper($0) }) else { continue }
                out.append((e, s, v, o))
            }
        }
        return out.map { (element: $0.0, storey: $0.1, view: $0.2, override: $0.3) }
    }

    /// The override of a stair or railing subcategory in this view (nil: hidden).
    func subOverride(_ e: Element, _ o: GraphicOverride, _ key: String) -> GraphicOverride? {
        let vg = builder.resolver.vg
        guard vg.hiddenSubcategories?.isEmpty == false || vg.subcategoryOverrides?.isEmpty == false else { return o }
        return builder.resolver.resolve(e, subcategory: key)
    }

    func stairStroke(_ e: Element, _ o: GraphicOverride, _ sub: String, zone: StairZone, weightBoost: Int = 0) -> GStroke? {
        let key = zone == .above ? StairSubcategory.above + sub : sub
        guard let so = subOverride(e, o, key) else { return nil }
        var st = builder.stroke(e.category, cut: false, so, subcategory: key)
        if zone == .above {
            if st.pattern == LinePatternKind.solid && so.projectionLinePattern == nil { st.pattern = LinePatternKind.hidden }
        } else {
            st.weight += weightBoost
        }
        return st
    }

    /// Removes the parts of a polyline inside any of `masks`.
    func outside(_ pts: [Vec2], _ masks: [Polygon2]) -> [[Vec2]] {
        guard !masks.isEmpty, pts.count >= 2 else { return [pts] }
        var out: [[Vec2]] = []
        for (a, b) in zip(pts, pts.dropFirst()) {
            var ts: [Double] = [0, 1]
            let seg = Segment2(a, b)
            for m in masks { for edge in m.edges { if let x = seg.lineIntersection(edge), x.t > 1e-9, x.t < 1 - 1e-9, x.u >= -1e-9, x.u <= 1 + 1e-9 { ts.append(x.t) } } }
            ts.sort()
            for (t0, t1) in zip(ts, ts.dropFirst()) where t1 - t0 > 1e-9 {
                let m = seg.point(at: (t0 + t1) / 2)
                guard !masks.contains(where: { $0.contains(m, onBoundary: false) }) else { continue }
                let p0 = seg.point(at: t0), p1 = seg.point(at: t1)
                if let last = out.last?.last, last.isAlmostEqual(p0) { out[out.count - 1].append(p1) } else { out.append([p0, p1]) }
            }
        }
        return out
    }

    func stairSymbol(_ e: Element, _ storey: Element, _ v: StairPlanView, _ o: GraphicOverride, masks: [Polygon2]) -> GItem {
        let l = v.layout
        var prims: [GPrimitive] = []
        func draw(_ pts: [Vec2], run: Int?, zone: StairZone? = nil, _ sub: String, boost: Int = 0) {
            for (piece, z) in v.split(pts, run: run, zone: zone) where z != .gap {
                guard let st = stairStroke(e, o, sub, zone: v.relation == .arrival ? .below : z, weightBoost: boost) else { continue }
                for part in outside(piece, masks) where part.count >= 2 { prims.append(.polyline(part, closed: false, st)) }
            }
        }
        let nose = l.type.run.nosingLength
        for (i, r) in l.runs.enumerated() {
            draw(r.left.map(\.point), run: i, StairSubcategory.outlines, boost: 1)
            draw(r.right.map(\.point), run: i, StairSubcategory.outlines, boost: 1)
            // A landing's outline already draws the run ends it joins.
            if !l.landings.contains(where: { $0.afterRun == r.index - 1 }) { draw([r.startEdge.start, r.startEdge.end], run: i, StairSubcategory.nosingLines) }
            if !l.landings.contains(where: { $0.afterRun == r.index }) { draw([r.endEdge.start, r.endEdge.end], run: i, StairSubcategory.outlines) }
            for (k, t) in r.treads.enumerated() where k > 0 {
                // The tread's front edge (its nosing, toward the step below) as seen from above.
                let f = nose > 1e-6 ? t.front.offset(by: -nose) : t.front
                let line = Segment2(f.start, f.end)
                draw([line.start, line.end], run: i, StairSubcategory.nosingLines)
            }
        }
        for land in l.landings {
            draw(land.polygon.points + [land.polygon.points[0]], run: nil, zone: v.landingZone(land), StairSubcategory.outlines, boost: 1)
        }
        for s in l.supports {
            for f in s.faces where f.count >= 2 { draw(f, run: s.run, StairSubcategory.supports) }
        }
        if let c = v.cut, v.relation == .cut { prims += cutMarkPrimitives(e, o, c, type: l.type.cutMark) }
        prims += stairPathPrimitives(e, storey, v, o, masks: masks)
        let hit = l.runs.map(\.outline) + l.landings.map(\.polygon)
        return GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: hit)
    }

    /// The cut mark: one or two slanted lines across the cut run, each with a zigzag in the middle.
    func cutMarkPrimitives(_ e: Element, _ o: GraphicOverride, _ c: StairPlanView.Cut, type: StairCutMarkType) -> [GPrimitive] {
        guard let st = stairStroke(e, o, StairSubcategory.cutMarks, zone: .below) else { return [] }
        let n = c.along.perpendicular * (c.along.perpendicular.dot(c.normal) >= 0 ? 1 : -1)
        let cross = abs(c.along.dot(-c.normal.perpendicular))
        let half = c.width / 2 / max(cross, 0.3) + builder.paper(0.0015)
        let offsets: [Double] = type == .doubleZigzag ? [-c.gap / 2, c.gap / 2] : [0]
        var out: [GPrimitive] = []
        for off in offsets {
            let m = c.point + n * off
            let a = m - c.along * half, b = m + c.along * half
            if type == .straight {
                out.append(.polyline([a, b], closed: false, st))
                continue
            }
            let z = builder.paper(0.0014), w = builder.paper(0.0010)
            out.append(.polyline([a, m - c.along * w, m - c.along * (w * 0.35) + n * z, m + c.along * (w * 0.35) - n * z, m + c.along * w, b],
                                 closed: false, st))
        }
        return out
    }

    /// The stair path with its start circle and arrowhead, and the Up or Down text.
    func stairPathPrimitives(_ e: Element, _ storey: Element, _ v: StairPlanView, _ o: GraphicOverride, masks: [Polygon2]) -> [GPrimitive] {
        guard let sd = storey.stair, let st = stairStroke(e, o, StairSubcategory.stairPath, zone: .below) else { return [] }
        // A Stair Path annotation placed in this view draws the path instead (Annotate ▸ Stair Path).
        if model.tags(of: e.id).contains(where: { $0.ownerViewID == builder.view.id && $0.tag?.kind == .stairPath }) { return [] }
        var path = v.walkPath
        guard path.count >= 2 else { return [] }
        // Show Up Arrow in All Views: the arrival plan shows the stair going up too.
        let down = v.relation == .arrival && !(sd.upArrowInAllViews ?? false)
        if down {
            guard sd.downArrow ?? true || sd.downLabel ?? true else { return [] }
            path.reverse()
        } else {
            guard sd.upArrow ?? true || sd.upLabel ?? true else { return [] }
            if let c = v.cut { path = Self.trim(path, before: c.point, by: c.gap / 2 + builder.paper(0.0015)) }
        }
        var out: [GPrimitive] = []
        let showArrow = down ? sd.downArrow ?? true : sd.upArrow ?? true
        let showLabel = down ? sd.downLabel ?? true : sd.upLabel ?? true
        if showArrow, path.count >= 2 {
            // Where a stair rising from this plan hides the end, the arrow stops where the hidden part begins.
            let visible = outside(path, masks).filter { $0.count >= 2 }
            for part in visible { out.append(.polyline(part, closed: false, st)) }
            let r = builder.paper(0.001)
            let p0 = path[0]
            if !masks.contains(where: { $0.contains(p0, onBoundary: false) }) {
                out.append(.arc(Arc2(center: p0, radius: r, startAngle: 0, sweep: 2 * .pi), st))
            }
            let tip = masks.isEmpty ? path : (visible.first ?? path)
            let end = tip[tip.count - 1], prev = tip[tip.count - 2]
            let d = (end - prev).normalized, n = d.perpendicular
            let a = builder.paper(0.0028)
            out.append(.fill([Polygon2([end, end - d * a + n * a * 0.3, end - d * a - n * a * 0.3])],
                             GFill(pattern: .solid, color: st.color, halftone: st.halftone)))
        }
        if showLabel {
            let d0 = (path[1] - path[0]).normalized
            let text = down ? (sd.downText ?? "DN") : (sd.upText ?? "UP")
            out.append(.text(GText(position: path[0] - d0 * builder.paper(0.0035), height: 0.0025, string: text,
                                   rotation: AnnotationRenderer.readable(d0.angle + .pi / 2), alignment: .center, verticalAnchor: 0.5,
                                   color: st.color, halftone: st.halftone)))
        }
        return out
    }

    /// A polyline cut short `by` before the point on it nearest `p`.
    static func trim(_ pts: [Vec2], before p: Vec2, by gap: Double) -> [Vec2] {
        var best = (Double.infinity, 0, Vec2.zero)
        for i in 0..<(pts.count - 1) {
            let q = Segment2(pts[i], pts[i + 1]).closestPoint(to: p)
            let d = q.distance(to: p)
            if d < best.0 { best = (d, i, q) }
        }
        var out = Array(pts[0...best.1]) + [best.2]
        // Walk back `gap`.
        var remaining = gap
        while out.count >= 2 {
            let a = out[out.count - 2], b = out[out.count - 1]
            let len = a.distance(to: b)
            if len > remaining { out[out.count - 1] = b + (a - b).normalized * remaining; break }
            remaining -= len
            out.removeLast()
        }
        return out
    }

    // MARK: Railings on stairs

    /// A railing hosted on a stair: its top rail as two lines (and balusters at Fine), split at the stair's cut mark
    /// like the stair (beyond it with the "<Above>" subcategories), on every storey this plan shows.
    func stairRailingItem(_ e: Element, _ o: GraphicOverride, host: Element) -> GItem? {
        let t = RailingTypeInfo.of(e, model)
        let views = stairViews([(host, o)])
        let masks = views.flatMap { $0.view.relation == .cut ? $0.view.belowRegion : [] }
        var prims: [GPrimitive] = []
        var hits: [Polygon2] = []
        for v in views {
            guard let rl = StairRailings.layout(e, stair: v.storey, model) else { continue }
            let mask = v.view.relation == .arrival ? masks : []
            let pts = rl.top.map(\.xy)
            let half = max(t.railSize / 2, builder.paper(0.0004))
            for side in [-half, half] {
                let line = StairGeometry.offset(pts, by: side)
                for (piece, z) in railSplit(line, v.view) where z != .gap {
                    let key = (z == .above && v.view.relation == .cut ? StairSubcategory.above : "") + StairSubcategory.topRails
                    guard let so = subOverride(e, o, key) else { continue }
                    var st = builder.stroke(.railings, cut: false, so, subcategory: key)
                    if z == .above, v.view.relation == .cut, st.pattern == LinePatternKind.solid, so.projectionLinePattern == nil { st.pattern = LinePatternKind.hidden }
                    for part in outside(piece, mask) where part.count >= 2 { prims.append(.polyline(part, closed: false, st)) }
                }
            }
            if builder.detailLevel(.railings) == .fine, let so = subOverride(e, o, StairSubcategory.balusters) {
                let st = builder.stroke(.railings, cut: false, so, subcategory: StairSubcategory.balusters)
                let b = t.balusterSize / 2
                for bal in rl.balusters where (v.view.relation == .arrival || v.view.zoneAt(bal.point) == .below) && !mask.contains(where: { $0.contains(bal.point) }) {
                    prims.append(.polyline([bal.point + Vec2(-b, -b), bal.point + Vec2(b, -b), bal.point + Vec2(b, b), bal.point + Vec2(-b, b)], closed: true, st))
                }
            }
            if pts.count >= 2 {
                hits.append(Polygon2(StairGeometry.offset(pts, by: 0.05) + StairGeometry.offset(pts, by: -0.05).reversed()))
            }
        }
        guard !prims.isEmpty else { return nil }
        return GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: hits)
    }

    /// Splits a rail line by the stair's cut mark, by the part of the stair each piece runs along.
    func railSplit(_ pts: [Vec2], _ v: StairPlanView) -> [([Vec2], StairZone)] {
        guard v.relation == .cut, v.cut != nil else { return [(pts, .below)] }
        return v.split(pts, run: nil)
    }
}
