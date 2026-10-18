import Foundation
import ArcusGeometry

/// Derived wall geometry: faces, joins, footprint and openings.
public struct WallFrame: Sendable {
    public var id: ElementID
    public var location: Curve2
    public var assembly: CompoundAssembly
    public var thickness: Double
    /// Signed offsets from the location curve (left positive) of the exterior and interior finish faces.
    public var exteriorOffset: Double
    public var interiorOffset: Double
    public var baseZ: Double
    public var topZ: Double
    public var flipped: Bool

    /// Offset of a layer boundary measured from the exterior face (0 … thickness), as a signed offset from the location curve.
    public func offset(fromExterior d: Double) -> Double {
        flipped ? exteriorOffset + d : exteriorOffset - d
    }
    public var exteriorFace: Curve2 { location.offset(by: exteriorOffset) }
    public var interiorFace: Curve2 { location.offset(by: interiorOffset) }
    public var leftOffset: Double { max(exteriorOffset, interiorOffset) }
    public var rightOffset: Double { min(exteriorOffset, interiorOffset) }
    public var centerOffset: Double { (exteriorOffset + interiorOffset) / 2 }
    public var height: Double { topZ - baseZ }
    public var length: Double { location.length }
    public var isStraight: Bool { location.asSegment != nil }
}

/// A join at one end of a wall.
public struct WallEndJoin: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case free, corner, tee }
    public var kind: Kind
    /// Corner points replacing the right and left face ends (plan), and the join point.
    public var rightCorner: Vec2
    public var leftCorner: Vec2
    public var center: Vec2
    public var others: [ElementID]
}

public struct WallOpening: Sendable, Hashable {
    public var insertID: ElementID
    /// Distance along the location curve (meters from start).
    public var s0: Double
    public var s1: Double
    /// Absolute elevations.
    public var z0: Double
    public var z1: Double
}

public enum WallGeometry {
    // MARK: Frame

    public static func assembly(for wall: Element, _ model: BIMModel) -> CompoundAssembly {
        assembly(ofType: model.typeData(of: wall), model: model)
    }

    /// The layers a wall of this type is built from (a 200 mm generic layer when the type has none). F2: a stacked type
    /// reports its thickest part's layers (with `model` to look the parts up).
    public static func assembly(ofType td: TypeData?, model: BIMModel? = nil) -> CompoundAssembly {
        if let s = td?.stack, let model { return StackedWalls.nominalAssembly(s, model) } // F2
        if let c = td?.curtain {
            // Curtain walls: one nominal layer as deep as the mullions, so joins, footprints and rooms see a real thickness.
            return CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: c.mullionMaterialID, thickness: c.nominalThickness)])
        }
        if let a = td?.assembly, a.validate() == nil { return a }
        return CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: nil, thickness: 0.2)])
    }

    public static func frame(_ e: Element, _ model: BIMModel) -> WallFrame? {
        guard let w = e.wall else { return nil }
        let a = assembly(for: e, model)
        let t = a.totalThickness
        let pos: Double // location line position measured from the exterior face
        switch w.locationLine {
        case .wallCenterline: pos = t / 2
        case .coreCenterline: pos = a.exteriorToCore + a.coreThickness / 2
        case .finishFaceExterior: pos = 0
        case .finishFaceInterior: pos = t
        case .coreFaceExterior: pos = a.exteriorToCore
        case .coreFaceInterior: pos = a.exteriorToCore + a.coreThickness
        }
        // Exterior is on the left of the location direction unless flipped.
        let ext = w.flipped ? -pos : pos
        let int = w.flipped ? (t - pos) : -(t - pos)
        let base = model.baseElevation(of: e)
        let top = model.topElevation(base: base, topLevelID: w.topLevelID, topOffset: w.topOffset, unconnectedHeight: w.unconnectedHeight)
        return WallFrame(id: e.id, location: w.location, assembly: a, thickness: t, exteriorOffset: ext, interiorOffset: int,
                         baseZ: base, topZ: max(top, base + Tolerance.shortCurve), flipped: w.flipped)
    }

    // MARK: Joins

    /// Walls that could join with `e`: same level range overlap, joins allowed, endpoints or curves within reach.
    public static func joinCandidates(_ e: Element, _ model: BIMModel) -> [Element] {
        guard let w = e.wall else { return [] }
        // Curtain walls butt against other walls; they never mitre or tee-join.
        if CurtainWallGeometry.isCurtain(e, model) { return [] }
        let reach = 0.05 + (assembly(for: e, model).totalThickness)
        let box = w.location.bounds.expanded(by: reach)
        let f = frame(e, model)
        return model.elements(.walls, intersecting: box).filter { o in
            guard o.id != e.id, let ow = o.wall, ow.location.bounds.intersects(box) else { return false }
            guard o.designOptionID == e.designOptionID else { return false }
            guard !CurtainWallGeometry.isCurtain(o, model) else { return false }
            guard let of = frame(o, model), let f else { return false }
            return of.baseZ < f.topZ - Tolerance.length && f.baseZ < of.topZ - Tolerance.length
        }
    }

    /// Where a wall end placed at `p` should really go to join an existing wall.
    ///
    /// Snapping to what is visible (a face corner or an end face) leaves the new wall's location line short of the
    /// other wall's location line, so no corner join forms. Like mainstream BIM tools, an end that lands inside another
    /// wall at its end (on the wall itself, within one thickness of its location end or on the corner beyond it) moves onto that location end, so the two walls
    /// meet and clean up. Ends inside a wall's middle already form tee joins and are left alone.
    public static func joinEndpoint(near p: Vec2, levelID: ElementID?, excluding: Set<ElementID> = [], _ model: BIMModel) -> Vec2? {
        let box = Rect2(center: p, halfSize: Vec2(1.5, 1.5))
        var best: (Vec2, Double)?
        for o in model.elements(.walls, intersecting: box) where !excluding.contains(o.id) && o.levelID == levelID {
            guard let ow = o.wall, let f = frame(o, model), !CurtainWallGeometry.isCurtain(o, model) else { continue }
            guard case .line(let seg) = f.location else { continue }
            let half = max(abs(f.exteriorOffset), abs(f.interiorOffset), f.thickness / 2)
            let tol = Tolerance.length * 10 // 0.1 mm: on the wall's outline counts as inside
            let u = (seg.end - seg.start).normalized, n = Vec2(-u.y, u.x)
            for (end, inward, allowed) in [(seg.start, u, ow.allowJoinAtStart), (seg.end, -u, ow.allowJoinAtEnd)] where allowed {
                // On the wall at its end: from the corner-join extension (half a thickness past the end) to one thickness in.
                let r = p - end
                let along = r.dot(inward), across = abs(r.dot(n))
                guard along >= -half - tol, along <= half * 2 + tol, across <= half + tol else { continue }
                let d = p.distance(to: end)
                if d > Tolerance.length, d < (best?.1 ?? .infinity) { best = (end, d) }
            }
        }
        return best?.0
    }

    /// Computes the join at the start (atEnd = false) or end of a wall.
    public static func endJoin(_ e: Element, atEnd: Bool, _ model: BIMModel, candidates: [Element]? = nil) -> WallEndJoin {
        guard let f = frame(e, model), let w = e.wall else {
            return WallEndJoin(kind: .free, rightCorner: .zero, leftCorner: .zero, center: .zero, others: [])
        }
        let p = atEnd ? f.location.end : f.location.start
        // Outgoing direction (away from the joint into the wall).
        let tangent = atEnd ? -f.location.tangent(at: 1) : f.location.tangent(at: 0)
        let free = freeEnd(f, atEnd: atEnd)
        let allowed = atEnd ? w.allowJoinAtEnd : w.allowJoinAtStart
        guard allowed else { return free }
        let tol = Tolerance.length * 100 // 1 mm joint capture
        let cands = candidates ?? joinCandidates(e, model)

        // Endpoint (corner / multi-way) joins.
        struct Arm { var id: ElementID; var frame: WallFrame; var atEnd: Bool; var dir: Vec2 }
        var arms: [Arm] = [Arm(id: e.id, frame: f, atEnd: atEnd, dir: tangent)]
        let midZ = (f.baseZ + f.topZ) / 2 // F2: a stacked neighbour joins with its part at this wall's height
        for o in cands.map({ StackedWalls.part(of: $0, atZ: midZ, model) }) {
            guard let of = frame(o, model), let ow = o.wall else { continue }
            if of.location.start.isAlmostEqual(p, tolerance: tol), ow.allowJoinAtStart {
                arms.append(Arm(id: o.id, frame: of, atEnd: false, dir: of.location.tangent(at: 0)))
            } else if of.location.end.isAlmostEqual(p, tolerance: tol), ow.allowJoinAtEnd {
                arms.append(Arm(id: o.id, frame: of, atEnd: true, dir: -of.location.tangent(at: 1)))
            }
        }
        if arms.count >= 2 {
            // Sort arms counter-clockwise by outgoing angle, deterministic by id for ties.
            let sorted = arms.sorted { (Angle.normalize($0.dir.angle), $0.id) < (Angle.normalize($1.dir.angle), $1.id) }
            guard let i = sorted.firstIndex(where: { $0.id == e.id }) else { return free }
            let next = sorted[(i + 1) % sorted.count]
            let prev = sorted[(i + sorted.count - 1) % sorted.count]
            // Face lines as seen along each arm's outgoing direction.
            func leftLine(_ a: Arm) -> Segment2 { faceLine(a.frame, atEnd: a.atEnd, left: true) }
            func rightLine(_ a: Arm) -> Segment2 { faceLine(a.frame, atEnd: a.atEnd, left: false) }
            let me = sorted[i]
            let halfT = f.thickness
            func corner(_ a: Segment2, _ b: Segment2, fallback: Vec2) -> Vec2 {
                guard let hit = a.lineIntersection(b) else { return fallback }
                // Very acute joins: clamp to avoid spikes.
                if hit.point.distance(to: p) > 6 * max(halfT, 0.05) { return fallback }
                return hit.point
            }
            let leftC = next.id == me.id ? free.leftCorner : corner(leftLine(me), rightLine(next), fallback: free.leftCorner)
            let rightC = prev.id == me.id ? free.rightCorner : corner(rightLine(me), leftLine(prev), fallback: free.rightCorner)
            return WallEndJoin(kind: .corner, rightCorner: rightC, leftCorner: leftC, center: p,
                               others: arms.map(\.id).filter { $0 != e.id }.sorted())
        }

        // Tee joins: endpoint lies on another wall's location curve interior.
        guard f.isStraight else { return free }
        for o in cands.map({ StackedWalls.part(of: $0, atZ: midZ, model) }) {
            guard let of = frame(o, model) else { continue }
            let d = of.location.distance(to: p)
            // The joint must be within the other wall's thickness, and not near its ends.
            guard d <= max(abs(of.exteriorOffset), abs(of.interiorOffset)) + tol else { continue }
            let q = of.location.closestPoint(to: p)
            guard q.distance(to: of.location.start) > tol, q.distance(to: of.location.end) > tol else { continue }
            // Pick the face of the through-wall that faces this wall.
            let side = (p + tangent * 0.01)
            let leftFace = of.location.offset(by: of.leftOffset)
            let rightFace = of.location.offset(by: of.rightOffset)
            let face = leftFace.distance(to: side) < rightFace.distance(to: side) ? leftFace : rightFace
            guard let faceSeg = face.asSegment else { continue }
            let l = faceLine(f, atEnd: atEnd, left: true), r = faceLine(f, atEnd: atEnd, left: false)
            guard let lh = l.lineIntersection(faceSeg), let rh = r.lineIntersection(faceSeg) else { continue }
            return WallEndJoin(kind: .tee, rightCorner: rh.point, leftCorner: lh.point, center: p, others: [o.id])
        }
        return free
    }

    /// Face line of a wall at one end, oriented along the outgoing direction; "left" relative to outgoing direction.
    static func faceLine(_ f: WallFrame, atEnd: Bool, left: Bool) -> Segment2 {
        // For the start end, outgoing == location direction: left face = leftOffset.
        // For the end, outgoing is reversed: left relative to outgoing is the location's right.
        let useLeftOfLocation = atEnd ? !left : left
        let off = useLeftOfLocation ? f.leftOffset : f.rightOffset
        let curve = f.location.offset(by: off)
        let seg: Segment2
        switch curve {
        case .line(let s): seg = s
        case .arc(let a):
            let t = atEnd ? 1.0 : 0.0
            let pt = a.point(at: t), tg = a.tangent(at: t)
            seg = Segment2(pt, pt + tg)
        }
        return atEnd ? seg.reversed : seg
    }

    static func freeEnd(_ f: WallFrame, atEnd: Bool) -> WallEndJoin {
        let t = atEnd ? 1.0 : 0.0
        let p = f.location.point(at: t)
        let n = f.location.normal(at: t)
        let l = p + n * f.leftOffset, r = p + n * f.rightOffset
        // Relative to the outgoing direction, left/right swap at the end.
        return atEnd ? WallEndJoin(kind: .free, rightCorner: l, leftCorner: r, center: p, others: [])
                     : WallEndJoin(kind: .free, rightCorner: r, leftCorner: l, center: p, others: [])
    }

    // MARK: Footprint

    /// Plan footprint with cleaned-up joins (full wall, ignoring openings).
    public static func footprint(_ e: Element, _ model: BIMModel) -> Polygon2? {
        guard let f = frame(e, model) else { return nil }
        let cands = joinCandidates(e, model)
        let sj = endJoin(e, atEnd: false, model, candidates: cands)
        let ej = endJoin(e, atEnd: true, model, candidates: cands)
        return footprint(f, start: sj, end: ej)
    }

    static func footprint(_ f: WallFrame, start sj: WallEndJoin, end ej: WallEndJoin) -> Polygon2? {
        var pts: [Vec2] = []
        switch f.location {
        case .line:
            // Start: outgoing = location dir. right corner is on right face, left corner on left face.
            pts.append(sj.rightCorner)
            if sj.kind == .corner, !onSegment(sj.center, sj.rightCorner, sj.leftCorner) { pts.append(sj.center) }
            pts.append(sj.leftCorner)
            // End: relative to outgoing (reversed), left corner lies on the location's right face.
            pts.append(ej.rightCorner)
            if ej.kind == .corner, !onSegment(ej.center, ej.rightCorner, ej.leftCorner) { pts.append(ej.center) }
            pts.append(ej.leftCorner)
        case .arc(let a):
            let left = f.location.offset(by: f.leftOffset).asArc ?? a
            let right = f.location.offset(by: f.rightOffset).asArc ?? a
            let rp = right.tessellate(chordTolerance: 0.003)
            let lp = left.tessellate(chordTolerance: 0.003)
            pts.append(contentsOf: rp)
            pts.append(contentsOf: lp.reversed())
        }
        let poly = Polygon2(pts).simplified()
        guard !poly.isDegenerate else { return nil }
        return poly.counterClockwise
    }

    private static func onSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Bool {
        Segment2(a, b).distance(to: p) <= Tolerance.length * 10
    }

    // MARK: Openings

    public static func openings(_ e: Element, _ model: BIMModel) -> [WallOpening] {
        guard let f = frame(e, model) else { return [] }
        var out: [WallOpening] = []
        for ins in model.hosted(by: e.id) where ins.insert != nil {
            guard let (s0, s1, z0, z1) = InsertGeometry.openingInHost(ins, host: f, model) else { continue }
            let a = max(0, min(s0, s1)), b = min(f.length, max(s0, s1))
            let lo = max(f.baseZ, z0), hi = min(f.topZ, z1)
            guard b - a > Tolerance.shortCurve, hi - lo > Tolerance.shortCurve else { continue }
            out.append(WallOpening(insertID: ins.id, s0: a, s1: b, z0: lo, z1: hi))
        }
        // Wall openings (rectangular cuts drawn in elevation or section), positioned relative to the host.
        for op in model.hosted(by: e.id) {
            guard let wo = op.opening?.wallOpening else { continue }
            let a = max(0, min(wo.start, wo.end)), b = min(f.length, max(wo.start, wo.end))
            let lo = max(f.baseZ, f.baseZ + min(wo.bottom, wo.top)), hi = min(f.topZ, f.baseZ + max(wo.bottom, wo.top))
            guard b - a > Tolerance.shortCurve, hi - lo > Tolerance.shortCurve else { continue }
            out.append(WallOpening(insertID: op.id, s0: a, s1: b, z0: lo, z1: hi))
        }
        return out.sorted { ($0.s0, $0.insertID) < ($1.s0, $1.insertID) }
    }

    /// Distance along the location curve of a plan point.
    public static func station(of p: Vec2, on c: Curve2) -> Double {
        switch c {
        case .line(let s): return s.parameter(of: p) * s.length
        case .arc(let a):
            let ang = (p - a.center).angle
            var rel = a.sweep >= 0 ? Angle.normalize(ang - a.startAngle) : Angle.normalize(a.startAngle - ang)
            if rel > abs(a.sweep) + (Angle.twoPi - abs(a.sweep)) / 2 { rel -= Angle.twoPi }
            return rel * a.radius
        }
    }
    public static func point(atStation s: Double, on c: Curve2) -> Vec2 {
        let L = c.length
        return c.point(at: L > 0 ? s / L : 0)
    }

    // MARK: Plan cut

    /// Footprint pieces cut at elevation z (openings spanning z removed).
    public static func planCut(_ e: Element, atZ z: Double, _ model: BIMModel) -> [Polygon2] {
        guard let f = frame(e, model), z > f.baseZ - Tolerance.length, z < f.topZ + Tolerance.length,
              let fp = footprint(e, model) else { return [] }
        let ops = openings(e, model).filter { $0.z0 <= z && $0.z1 >= z }
        guard !ops.isEmpty else { return [fp] }
        guard case .line(let seg) = f.location else {
            // Arc walls: remove openings as angular gaps.
            return arcPieces(f, fp: fp, gaps: ops.map { ($0.s0, $0.s1) })
        }
        var pieces: [Polygon2] = []
        let dir = seg.direction, nrm = seg.normal
        var cursor = -Double.greatestFiniteMagnitude
        for o in ops.sorted(by: { $0.s0 < $1.s0 }) + [WallOpening(insertID: e.id, s0: .greatestFiniteMagnitude, s1: .greatestFiniteMagnitude, z0: 0, z1: 0)] {
            let a = cursor, b = o.s0
            if b > a + Tolerance.shortCurve {
                if let piece = clip(fp, origin: seg.start, dir: dir, nrm: nrm, from: a, to: b) { pieces.append(piece) }
            }
            cursor = max(cursor, o.s1)
        }
        return pieces
    }

    /// Clips a polygon to the slab between stations a and b along a line (Sutherland–Hodgman, two half-planes).
    static func clip(_ poly: Polygon2, origin: Vec2, dir: Vec2, nrm: Vec2, from a: Double, to b: Double) -> Polygon2? {
        func station(_ p: Vec2) -> Double { (p - origin).dot(dir) }
        func clipHalf(_ pts: [Vec2], keep: (Double) -> Bool, bound: Double) -> [Vec2] {
            guard !pts.isEmpty else { return [] }
            var out: [Vec2] = []
            for i in 0..<pts.count {
                let p = pts[i], q = pts[(i + 1) % pts.count]
                let sp = station(p), sq = station(q)
                let ip = keep(sp), iq = keep(sq)
                if ip { out.append(p) }
                if ip != iq {
                    let t = (bound - sp) / (sq - sp)
                    out.append(p.lerp(to: q, t: t))
                }
            }
            return out
        }
        var pts = poly.points
        if a > -Double.greatestFiniteMagnitude / 2 { pts = clipHalf(pts, keep: { $0 >= a }, bound: a) }
        if b < Double.greatestFiniteMagnitude / 2 { pts = clipHalf(pts, keep: { $0 <= b }, bound: b) }
        let r = Polygon2(pts).simplified()
        return r.isDegenerate ? nil : r
    }

    static func arcPieces(_ f: WallFrame, fp: Polygon2, gaps: [(Double, Double)]) -> [Polygon2] {
        guard let arc = f.location.asArc else { return [fp] }
        var out: [Polygon2] = []
        var cursor = 0.0
        for g in gaps.sorted(by: { $0.0 < $1.0 }) + [(f.length, f.length)] {
            if g.0 - cursor > Tolerance.shortCurve {
                let t0 = cursor / f.length, t1 = g.0 / f.length
                let sub = Arc2(center: arc.center, radius: arc.radius, startAngle: arc.startAngle + arc.sweep * t0, sweep: arc.sweep * (t1 - t0))
                let l = Curve2.arc(sub).offset(by: f.leftOffset).tessellate(chordTolerance: 0.003)
                let r = Curve2.arc(sub).offset(by: f.rightOffset).tessellate(chordTolerance: 0.003)
                let p = Polygon2(r + l.reversed()).simplified()
                if !p.isDegenerate { out.append(p.counterClockwise) }
            }
            cursor = max(cursor, g.1)
        }
        return out
    }

    // MARK: Solid

    /// Closed solid of the wall with openings cut and joins cleaned (straight walls); arc walls use radial ends.
    public static func solid(_ e: Element, _ model: BIMModel) -> Mesh {
        guard let f = frame(e, model), let w = e.wall else { return .empty }
        let ops = openings(e, model)
        let topProfile = topProfile(e, f, model)
        switch f.location {
        case .line(let seg):
            let cands = joinCandidates(e, model)
            let sj = endJoin(e, atEnd: false, model, candidates: cands)
            let ej = endJoin(e, atEnd: true, model, candidates: cands)
            return straightSolid(f, seg: seg, start: sj, end: ej, openings: ops, top: topProfile, slant: w.slantAngle,
                                 reveals: WallReveals.cuts(e, f, model)) // F1: Wall: Reveal grooves
        case .arc:
            return arcSolid(f, openings: ops)
        }
    }

    /// Elevation profile (s, z) outer loop: rectangle, edited profile, or attached top following roofs/floors.
    static func topProfile(_ e: Element, _ f: WallFrame, _ model: BIMModel) -> Polygon2 {
        let L = f.length
        if let p = e.wall?.profile, !p.isDegenerate {
            return Polygon2(p.points.map { Vec2($0.x, $0.y + f.baseZ) }).counterClockwise
        }
        guard let w = e.wall, !w.attachedTopIDs.isEmpty else {
            return Polygon2([Vec2(0, f.baseZ), Vec2(L, f.baseZ), Vec2(L, f.topZ), Vec2(0, f.topZ)])
        }
        // Sample the underside of attached roofs/floors along the centerline.
        let n = max(2, min(200, Int(L / 0.1)))
        var top: [Vec2] = []
        let centerCurve = f.location.offset(by: f.centerOffset)
        for i in 0...n {
            let s = L * Double(i) / Double(n)
            let p = centerCurve.point(at: Double(i) / Double(n))
            var z = f.topZ
            for id in w.attachedTopIDs {
                guard let host = model[id] else { continue }
                if let under = AttachmentQueries.undersideZ(host, at: p, model) { z = min(z, under) }
            }
            top.append(Vec2(s, max(z, f.baseZ + Tolerance.shortCurve)))
        }
        return Polygon2([Vec2(0, f.baseZ), Vec2(L, f.baseZ)] + top.reversed()).simplified().counterClockwise
    }

    /// Straight wall solid: the elevation profile (with openings as holes) is extruded across the wall in two halves
    /// (right face → joint center line → left face). End vertices are remapped onto the join corners so that
    /// mitered, tee and multi-way joins meet without gaps.
    static func straightSolid(_ f: WallFrame, seg: Segment2, start sj: WallEndJoin, end ej: WallEndJoin,
                              openings: [WallOpening], top: Polygon2, slant: Double, reveals: [WallRevealCut] = []) -> Mesh {
        let L = f.length
        let profiles = elevationProfiles(outline: top, openings: openings)
        let dir = seg.direction, nrm = seg.normal
        // Local frame: X along wall (s), Y = up (z), Z = -normal so that extrusion depth goes from left to right.
        // Build in a local space (s, z, t) then map to world: world = start + dir*s + nrm*t, height z.
        let right = f.rightOffset, left = f.leftOffset
        let mid = (sj.kind == .free && ej.kind == .free) ? nil : Optional((right + left) / 2)
        var halves: [(Double, Double)] = []
        if let m = mid { halves = [(right, m), (m, left)] } else { halves = [(right, left)] }

        func stationAndOffset(_ p: Vec2) -> (s: Double, t: Double) { ((p - seg.start).dot(dir), (p - seg.start).dot(nrm)) }
        // End cap geometry as (s at t) piecewise-linear through right corner, center, left corner.
        func capStation(_ j: WallEndJoin, atEnd: Bool, t: Double) -> Double {
            // For the start, rightCorner is on the right face; for the end, rightCorner (outgoing frame) is on the left face.
            let a = stationAndOffset(atEnd ? j.leftCorner : j.rightCorner)   // right-face point (t = right)
            let b = stationAndOffset(atEnd ? j.rightCorner : j.leftCorner)   // left-face point (t = left)
            let c = stationAndOffset(j.center)
            let useKink = j.kind == .corner && abs(c.t - a.t) > Tolerance.length && abs(b.t - c.t) > Tolerance.length
            if useKink {
                if t <= c.t { return a.s + (c.s - a.s) * (t - a.t) / (c.t - a.t) }
                return c.s + (b.s - c.s) * (t - c.t) / (b.t - c.t)
            }
            guard abs(b.t - a.t) > Tolerance.length else { return a.s }
            return a.s + (b.s - a.s) * (t - a.t) / (b.t - a.t)
        }

        var mesh = Mesh()
        let slantTan = tan(slant)
        // F1: reveals split the thickness further at their groove bottoms; a slice's profile loses the grooves that
        // reach it, and the faces a groove exposes between slices are added.
        let slices = reveals.isEmpty ? halves.map { (t0: $0.0, t1: $0.1, cuts: [WallRevealCut]()) }
            : WallReveals.slices(right: right, left: left, breaks: mid.map { [$0] } ?? [], cuts: reveals)
        for (k, slice) in slices.enumerated() {
            let (t0, t1) = (slice.t0, slice.t1)
            // Extrude profile in plane (s, z) from t0 to t1. The frame's local +Z is dir × up = −normal,
            // so a negative depth moves toward +t.
            let frame = simd_frame(sOrigin: seg.start, dir: dir, nrm: nrm, t: t0)
            var part = Mesh()
            for profile in WallReveals.profiles(profiles, minus: slice.cuts) { part.append(MeshBuilder.extrude(profile, frame: frame, depth: -(t1 - t0))) }
            if !reveals.isEmpty { // F1
                if k > 0 {
                    part = removeFaces(part, onPlaneT: t0, seg: seg, nrm: nrm)
                    for (p, up) in WallReveals.exposedFaces(profiles, lower: slices[k - 1].cuts, upper: slice.cuts) { part.append(WallReveals.face(p, t: t0, seg: seg, positive: up)) }
                }
                if k < slices.count - 1 { part = removeFaces(part, onPlaneT: t1, seg: seg, nrm: nrm) }
            }
            // Remap vertices at the ends and apply slant.
            for i in part.positions.indices {
                let p = part.positions[i]
                let (s, t) = stationAndOffset(p.xy)
                var ns = s
                if abs(s) <= Tolerance.length * 10 { ns = capStation(sj, atEnd: false, t: t) }
                else if abs(s - L) <= Tolerance.length * 10 { ns = capStation(ej, atEnd: true, t: t) }
                var nt = t
                if slant != 0 { nt += (p.z - f.baseZ) * slantTan * (f.flipped ? -1 : 1) }
                let wp = seg.start + dir * ns + nrm * nt
                part.positions[i] = Vec3(wp.x, wp.y, p.z)
            }
            // Remove the internal faces at the half boundary.
            if mid != nil, reveals.isEmpty { part = removeFaces(part, onPlaneT: mid!, seg: seg, nrm: nrm) }
            mesh.append(part)
        }
        recomputeFlatNormals(&mesh)
        return mesh
    }

    /// The wall's elevation profile(s) with openings removed. Openings strictly inside the outline become holes; an
    /// opening that touches or crosses the outline (a door at the wall base, a notch at the top) or overlaps another
    /// opening is subtracted with a polygon boolean so the extruded solid stays closed and manifold.
    static func elevationProfiles(outline: Polygon2, openings: [WallOpening]) -> [Profile2] {
        let rects = openings.map { Rect2(min: Vec2($0.s0, $0.z0), max: Vec2($0.s1, $0.z1)) }.filter { $0.width > Tolerance.length && $0.height > Tolerance.length }
        guard !rects.isEmpty else { return [Profile2(outer: outline)] }
        let margin = Tolerance.length * 20
        func strictlyInside(_ r: Rect2) -> Bool {
            let e = Rect2(min: r.min - Vec2(margin, margin), max: r.max + Vec2(margin, margin))
            return [e.min, Vec2(e.max.x, e.min.y), e.max, Vec2(e.min.x, e.max.y)].allSatisfy { outline.contains($0, onBoundary: false) }
        }
        func overlaps(_ i: Int) -> Bool {
            rects.indices.contains { j in
                j != i && rects[i].min.x < rects[j].max.x + margin && rects[j].min.x < rects[i].max.x + margin
                    && rects[i].min.y < rects[j].max.y + margin && rects[j].min.y < rects[i].max.y + margin
            }
        }
        var holes: [Polygon2] = [], cutters: [Profile2] = []
        for (i, r) in rects.enumerated() {
            let poly = Polygon2([r.min, Vec2(r.min.x, r.max.y), r.max, Vec2(r.max.x, r.min.y)])
            if strictlyInside(r) && !overlaps(i) { holes.append(poly) } else { cutters.append(Profile2(outer: poly)) }
        }
        let base = Profile2(outer: outline, holes: holes)
        guard !cutters.isEmpty else { return [base] }
        let result = PolygonBoolean.difference([base], cutters)
        return result.isEmpty ? [base] : result
    }

    /// Local frame whose XY plane is the wall's elevation plane at offset t: X = dir (s), Y = up (z), Z = normal (t).
    static func simd_frame(sOrigin: Vec2, dir: Vec2, nrm: Vec2, t: Double) -> Transform3 {
        let o = sOrigin + nrm * t
        return .frame(origin: Vec3(o.x, o.y, 0), xAxis: Vec3(dir.x, dir.y, 0), yAxis: .unitZ)
    }

    static func removeFaces(_ m: Mesh, onPlaneT t: Double, seg: Segment2, nrm: Vec2) -> Mesh {
        func tOf(_ p: Vec3) -> Double { (p.xy - seg.start).dot(nrm) }
        var out = m
        var idx: [UInt32] = []
        for i in stride(from: 0, to: m.indices.count, by: 3) {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            let on = [a, b, c].allSatisfy { abs(tOf($0) - t) <= Tolerance.length * 10 }
            if !on { idx.append(contentsOf: m.indices[i..<(i + 3)]) }
        }
        var edges: [UInt32] = []
        for i in stride(from: 0, to: m.featureEdges.count, by: 2) {
            let a = m.positions[Int(m.featureEdges[i])], b = m.positions[Int(m.featureEdges[i + 1])]
            if !(abs(tOf(a) - t) <= Tolerance.length * 10 && abs(tOf(b) - t) <= Tolerance.length * 10) {
                edges.append(contentsOf: m.featureEdges[i..<(i + 2)])
            }
        }
        out.indices = idx
        out.featureEdges = edges
        return out
    }

    static func recomputeFlatNormals(_ m: inout Mesh) {
        if m.normals.count != m.positions.count { m.normals = Array(repeating: .unitZ, count: m.positions.count) }
        for i in stride(from: 0, to: m.indices.count, by: 3) {
            let ia = Int(m.indices[i]), ib = Int(m.indices[i + 1]), ic = Int(m.indices[i + 2])
            let n = (m.positions[ib] - m.positions[ia]).cross(m.positions[ic] - m.positions[ia]).normalized
            if n.lengthSquared > 0 { m.normals[ia] = n; m.normals[ib] = n; m.normals[ic] = n }
        }
    }

    /// Arc wall solid: vertical extrusion of angular pieces between openings, split by opening height bands.
    static func arcSolid(_ f: WallFrame, openings: [WallOpening]) -> Mesh {
        guard let arc = f.location.asArc else { return .empty }
        var breaks = Set<Double>([0, f.length])
        for o in openings { breaks.insert(o.s0); breaks.insert(o.s1) }
        let stations = breaks.sorted()
        var mesh = Mesh()
        for i in 0..<(stations.count - 1) {
            let a = stations[i], b = stations[i + 1]
            guard b - a > Tolerance.shortCurve else { continue }
            let mid = (a + b) / 2
            var bands = [(f.baseZ, f.topZ)]
            for o in openings where o.s0 <= mid && o.s1 >= mid {
                bands = bands.flatMap { band -> [(Double, Double)] in
                    var r: [(Double, Double)] = []
                    if o.z0 > band.0 + Tolerance.length { r.append((band.0, min(band.1, o.z0))) }
                    if o.z1 < band.1 - Tolerance.length { r.append((max(band.0, o.z1), band.1)) }
                    return r.isEmpty && (o.z0 > band.1 || o.z1 < band.0) ? [band] : r
                }
            }
            let t0 = a / f.length, t1 = b / f.length
            let sub = Arc2(center: arc.center, radius: arc.radius, startAngle: arc.startAngle + arc.sweep * t0, sweep: arc.sweep * (t1 - t0))
            let l = Curve2.arc(sub).offset(by: f.leftOffset).tessellate(chordTolerance: 0.003)
            let r = Curve2.arc(sub).offset(by: f.rightOffset).tessellate(chordTolerance: 0.003)
            let poly = Polygon2(r + l.reversed()).simplified()
            guard !poly.isDegenerate else { continue }
            for band in bands where band.1 - band.0 > Tolerance.shortCurve {
                mesh.append(MeshBuilder.extrude(Profile2(outer: poly), bottom: band.0, top: band.1))
            }
        }
        return mesh
    }

    // MARK: Wrapping

    /// Where wrapping layers of a compound wall turn around a free end or an insert jamb (straight walls, in plan).
    public struct WrapReturn: Sendable, Hashable {
        /// Station of the wrapped face (the jamb or the wall end).
        public var station: Double
        /// +1 when the wall's material lies at larger stations than `station`, −1 when it lies at smaller ones.
        public var inward: Double
        /// True when the exterior layers wrap, false for the interior layers.
        public var fromExterior: Bool
        /// Depths (from the wrapping face) of the boundaries of the wrapping layers, ascending; the last is their total.
        public var depths: [Double]
        /// Depth (from the wrapping face) the returned layers reach across the wall.
        public var reach: Double
        /// Index of the first wrapping layer counted from the wrapping face.
        public var layers: [Int]
    }

    /// Wrap returns of a straight wall at elevation `z` (inserts whose opening spans `z`, and free ends), following the
    /// type's Wrapping at Inserts / Wrapping at Ends settings and each layer's Wraps flag.
    public static func wrapReturns(_ e: Element, atZ z: Double, _ model: BIMModel) -> [WrapReturn] {
        guard let f = frame(e, model), f.isStraight, !CurtainWallGeometry.isCurtain(e, model) else { return [] }
        let a = f.assembly
        guard a.layers.count > 1, a.wrappingAtInserts != .doNotWrap || a.wrappingAtEnds != .doNotWrap else { return [] }
        let core = a.safeCore
        func sides(_ p: WrappingPreference) -> [Bool] {
            switch p {
            case .doNotWrap: []
            case .exterior: [true]
            case .interior: [false]
            case .both: [true, false]
            }
        }
        /// Wrapping layers counted from one face (contiguous layers marked Wraps, outside the core).
        func wrapping(_ exterior: Bool, both: Bool) -> (depths: [Double], layers: [Int], reach: Double)? {
            var idx: [Int] = []
            if exterior {
                var i = 0
                while i < core.lowerBound, a.layers[i].wraps { idx.append(i); i += 1 }
            } else {
                var i = a.layers.count - 1
                while i >= core.upperBound, a.layers[i].wraps { idx.append(i); i -= 1 }
            }
            var acc = 0.0, depths: [Double] = []
            for i in idx { acc += a.layers[i].thickness; depths.append(acc) }
            guard acc > Tolerance.length else { return nil }
            let toCore = exterior ? a.exteriorToCore : a.totalThickness - a.exteriorToCore - a.coreThickness
            let reach = both ? toCore + a.coreThickness / 2 : toCore + a.coreThickness
            return (depths, idx, max(reach, acc))
        }
        var faces: [(Double, Double, WrappingPreference)] = []
        if a.wrappingAtInserts != .doNotWrap {
            for o in openings(e, model) where model[o.insertID]?.insert != nil && o.z0 <= z && o.z1 >= z {
                faces.append((o.s0, -1, a.wrappingAtInserts))
                faces.append((o.s1, 1, a.wrappingAtInserts))
            }
        }
        if a.wrappingAtEnds != .doNotWrap {
            let cands = joinCandidates(e, model)
            if endJoin(e, atEnd: false, model, candidates: cands).kind == .free { faces.append((0, 1, a.wrappingAtEnds)) }
            if endJoin(e, atEnd: true, model, candidates: cands).kind == .free { faces.append((f.length, -1, a.wrappingAtEnds)) }
        }
        var out: [WrapReturn] = []
        for (station, inward, pref) in faces {
            for ext in sides(pref) {
                guard let w = wrapping(ext, both: pref == .both) else { continue }
                out.append(WrapReturn(station: station, inward: inward, fromExterior: ext, depths: w.depths, reach: w.reach, layers: w.layers))
            }
        }
        return out
    }

    /// Plan layer boundary lines of a straight wall with wrapping applied at `z`: boundaries of wrapping layers turn
    /// across the wall at each wrapped face, and other boundaries within the returned layers' reach stop short of it.
    /// Falls back to `layerBoundaryCurves` when nothing wraps.
    public static func layerBoundaryCurves(_ e: Element, _ f: WallFrame, atZ z: Double, _ model: BIMModel) -> [Curve2] {
        let returns = wrapReturns(e, atZ: z, model)
        guard !returns.isEmpty, let seg = f.location.asSegment else { return layerBoundaryCurves(f) }
        let T = f.thickness
        let L = f.length
        let ext = f.thickness * 4 + 1
        let tol = Tolerance.length * 10
        func line(_ s0: Double, _ s1: Double, depthFromExterior d: Double) -> Curve2 {
            let o = f.offset(fromExterior: d)
            return .line(Segment2(seg.point(at: s0 / L), seg.point(at: s1 / L)).offset(by: o))
        }
        func across(_ s: Double, _ d0: Double, _ d1: Double) -> Curve2 {
            let p = seg.point(at: s / L)
            return .line(Segment2(p + seg.normal * f.offset(fromExterior: d0), p + seg.normal * f.offset(fromExterior: d1)))
        }
        var out: [Curve2] = []
        let boundaries = Array(f.assembly.boundaries.dropFirst().dropLast())
        for b in boundaries {
            var removed: [(Double, Double)] = []
            for r in returns {
                let dd = r.fromExterior ? b : T - b
                if r.depths.dropLast().contains(where: { abs($0 - dd) <= tol }) || abs(r.depths.last! - dd) <= tol {
                    removed.append((min(r.station, r.station + r.inward * dd), max(r.station, r.station + r.inward * dd)))
                    let st = r.station + r.inward * dd
                    out.append(across(st, b, r.fromExterior ? r.reach : T - r.reach))
                } else if dd < r.reach - tol {
                    let tw = r.depths.last!
                    removed.append((min(r.station, r.station + r.inward * tw), max(r.station, r.station + r.inward * tw)))
                }
            }
            // Remaining intervals of the full-length boundary.
            var intervals = [(-ext, L + ext)]
            for (r0, r1) in removed {
                intervals = intervals.flatMap { iv -> [(Double, Double)] in
                    guard r1 > iv.0, r0 < iv.1 else { return [iv] }
                    return [(iv.0, r0), (r1, iv.1)].filter { $0.1 - $0.0 > tol }
                }
            }
            for iv in intervals { out.append(line(max(iv.0, -ext), min(iv.1, L + ext), depthFromExterior: b)) }
        }
        // Closing lines where the returned layers stop, unless a layer boundary already runs there.
        for r in returns {
            let reachFromExterior = r.fromExterior ? r.reach : T - r.reach
            guard reachFromExterior > tol, reachFromExterior < T - tol else { continue }
            let s0 = r.station, s1 = r.station + r.inward * r.depths.last!
            if !boundaries.contains(where: { abs($0 - reachFromExterior) <= tol }) {
                out.append(line(min(s0, s1), max(s0, s1), depthFromExterior: reachFromExterior))
            }
        }
        return out
    }

    /// Plan regions of the returned legs of wrapping layers (layer index → polygon), for layer fills at fine detail.
    public static func wrapRegions(_ e: Element, _ f: WallFrame, atZ z: Double, _ model: BIMModel) -> [(layer: Int, polygon: Polygon2)] {
        guard let seg = f.location.asSegment else { return [] }
        let T = f.thickness, L = f.length
        var out: [(Int, Polygon2)] = []
        for r in wrapReturns(e, atZ: z, model) {
            var prev = 0.0
            for (k, d) in r.depths.enumerated() {
                let sA = r.station + r.inward * prev, sB = r.station + r.inward * d
                let dA = r.fromExterior ? d : T - d, dB = r.fromExterior ? r.reach : T - r.reach
                let pA = seg.point(at: sA / L), pB = seg.point(at: sB / L)
                let oA = seg.normal * f.offset(fromExterior: dA), oB = seg.normal * f.offset(fromExterior: dB)
                let poly = Polygon2([pA + oA, pB + oA, pB + oB, pA + oB])
                if !poly.isDegenerate { out.append((r.layers[k], poly.counterClockwise)) }
                prev = d
            }
        }
        return out
    }

    // MARK: Layer lines for fine detail

    /// Layer boundary curves (plan) between the finish faces, clipped to the wall's cut pieces by the caller.
    public static func layerBoundaryCurves(_ f: WallFrame) -> [Curve2] {
        let b = f.assembly.boundaries
        guard b.count > 2 else { return [] }
        return b.dropFirst().dropLast().map { f.location.offset(by: f.offset(fromExterior: $0)) }
    }
}
