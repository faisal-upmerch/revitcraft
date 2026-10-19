import Foundation
import ArcusGeometry

// FMG2: joints for every part. FM6 joined only parts that are single plane-bounded boxes; this file gives the solver the
// other shapes:
//   - shaped sheets: panels with Edit Profile or Openings, and shelves or tops sketched with more than four sides. The
//     solver works on their box, but a part only joins a shaped part where it meets its actual outline (a shelf at
//     the cut-away part of a shaped side doesn't join it), and trims clip (or stretch) the outline itself;
//   - round rails: a cylinder along the rail, trimmed at its ends; mortise and tenon and housed joints make a round
//     tenon or socket in the part it runs into (a drilled hole, not a pocket);
//   - slats: each slat is its own piece of one part; the slats share their ends, so a joint trims every slat and makes
//     its tenon, dowels or groove once per slat. The pair kind is Slat – Frame (Joint Rules).

/// A point on a shaped part's face plane: (u, v) of the sketch plane across its thickness, with the planes they follow.
public struct PartPoint: Sendable {
    public var u: PartValue
    public var v: PartValue
    public init(_ u: PartValue, _ v: PartValue) { self.u = u; self.v = v }
    subscript(_ k: Int) -> PartValue {
        get { k == 0 ? u : v }
        set { if k == 0 { u = newValue } else { v = newValue } }
    }
    var vec: Vec2 { Vec2(u.value, v.value) }
}

/// What a joined part looks like beyond its box.
public enum JointShape: Sendable {
    /// A box (its box is the part).
    case box
    /// A cylinder along `axis` filling its box across (round rails).
    case round(axis: FamilyAxis)
    /// A sheet with an outline on the plane across `normal` (its thickness): Edit Profile, Openings, shaped shelves.
    /// The openings are cut through it (numbers, in the same plane's (u, v)).
    case profile(normal: FamilyAxis, outline: [PartPoint], openings: [[Vec2]])

    public var isBox: Bool { if case .box = self { return true }; return false }
}

extension JointPart {
    /// Slats: the axis they run along (their ends are the only places they join).
    var slatAxis: FamilyAxis? {
        guard let p = pieces?.first else { return nil }
        return FamilyAxis.allCases.max { p.ext($0) < p.ext($1) }
    }
}

/// A round tenon or socket along `axis`: a circle centred at (`cu`, `cv`) on the plane across the axis, from `lo` to `hi`.
struct JRound: Sendable {
    var axis: FamilyAxis
    var cu: PartValue
    var cv: PartValue
    var radius: Double
    var lo: PartValue
    var hi: PartValue
}

extension JointSolver {
    // MARK: Shaped parts

    /// A part that isn't a single box: a shaped panel or shelf, a round rail, slats.
    static func shapedPart(_ e: Element, _ m: BIMModel) -> JointPart? {
        switch e.data {
        case .furniturePanel(let p) where p.profile != nil || !(p.openings ?? []).isEmpty: return profiledPanel(e, p, m)
        case .furnitureShelf(let s) where s.boundary.count >= 3: return shapedShelf(e, s, m)
        case .furnitureRail: return railPart(e, m)
        default: return nil
        }
    }

    /// A coordinate written with numbers (`numeric`) and with planes (`fb`, in `ctx`): its value and the plane it follows.
    static func boundValue(_ numeric: FamilyBound, _ fb: FamilyBound, _ ctx: PartSolidContext) -> PartValue {
        let v: Double = { if case .expr(let x) = numeric { return Double(x) ?? 0 }; return 0 }()
        guard case .plane(let n) = fb else { return PartValue(v) }
        if let h = ctx.helpers[n] { return PartValue(v, plane: h.plane, offset: h.offset) }
        return PartValue(v, plane: n, offset: 0)
    }

    /// The numbers and the planes of a box or circle solid: lo and hi per axis, and the shape.
    static func ranges(_ num: FamilySolid, _ sym: FamilySolid, _ ctx: PartSolidContext) -> (lo: [PartValue], hi: [PartValue], round: Bool)? {
        func value(_ numeric: FamilyBound, _ fb: FamilyBound) -> PartValue { boundValue(numeric, fb, ctx) }
        let plane = num.workPlane ?? .xy
        var lo = [PartValue(0), PartValue(0), PartValue(0)], hi = lo
        var round = false
        switch (num.profile, sym.profile) {
        case (.rectangle(let nx0, let nx1, let ny0, let ny1), .rectangle(let bx0, let bx1, let by0, let by1)):
            lo[plane.axes.u.idx] = value(nx0, bx0); hi[plane.axes.u.idx] = value(nx1, bx1)
            lo[plane.axes.v.idx] = value(ny0, by0); hi[plane.axes.v.idx] = value(ny1, by1)
        case (.circle(let nc, let nr), .circle(let bc, _)):
            let r = Double(nr) ?? 0
            let cu = value(nc.x, bc.x), cv = value(nc.y, bc.y)
            lo[plane.axes.u.idx] = cu.shifted(-r); hi[plane.axes.u.idx] = cu.shifted(r)
            lo[plane.axes.v.idx] = cv.shifted(-r); hi[plane.axes.v.idx] = cv.shifted(r)
            round = true
        default:
            return nil
        }
        lo[plane.axes.w.idx] = value(num.zMin, sym.zMin); hi[plane.axes.w.idx] = value(num.zMax, sym.zMax)
        return (lo, hi, round)
    }

    /// The part's solids written with numbers and with planes (main solids only), and the context of the second.
    static func numberedAndBound(_ e: Element, _ m: BIMModel) -> (num: PartSolids, sym: PartSolids, ctx: PartSolidContext) {
        let num = FurniturePartSolids.rawSolids(e, m, PartSolidContext(symbolic: false))
        let ctx = PartSolidContext(symbolic: true, knownPlanes: Set(FurniturePlanes.positionsByName(m).keys))
        return (num, FurniturePartSolids.rawSolids(e, m, ctx), ctx)
    }

    /// Round rails and slats: one piece per solid.
    static func railPart(_ e: Element, _ m: BIMModel) -> JointPart? {
        let (num, sym, ctx) = numberedAndBound(e, m)
        let a = num.solids.filter { !$0.isVoid }, b = sym.solids.filter { !$0.isVoid }
        guard !a.isEmpty, a.count == b.count, num.placed.isEmpty else { return nil }
        var pieces: [JBox] = [], round = false
        for (x, y) in zip(a, b) {
            guard let r = ranges(x, y, ctx) else { return nil }
            pieces.append(JBox(lo: r.lo, hi: r.hi))
            round = r.round
        }
        let lo = (0..<3).map { k in pieces.map { $0.lo[k] }.min { $0.value < $1.value }! }
        let hi = (0..<3).map { k in pieces.map { $0.hi[k] }.max { $0.value < $1.value }! }
        var jp = JointPart(id: e.id, role: .rail, lo: lo, hi: hi, reshapeable: true)
        if round {
            // The cylinder runs along the solid's extrusion (its work plane's normal).
            jp.shape = .round(axis: (a[0].workPlane ?? .xy).axes.w)
        }
        if pieces.count > 1 { jp.pieces = pieces }
        return jp
    }

    /// A panel with Edit Profile or Openings: its outline on the face plane, extruded through the thickness.
    static func profiledPanel(_ e: Element, _ p: PanelData, _ m: BIMModel) -> JointPart? {
        let (num, sym, ctx) = numberedAndBound(e, m)
        let a = num.solids.filter { !$0.isVoid }, b = sym.solids.filter { !$0.isVoid }
        guard a.count == 1, b.count == 1, num.placed.isEmpty, case .polygon(let pts) = a[0].profile else { return nil }
        let face = a[0].workPlane ?? .xy
        let (u, v, w) = face.axes
        // The same panel drawn as a rectangle gives the planes its faces follow.
        var plain = e
        var q = p
        q.profile = nil; q.openings = nil
        plain.data = .furniturePanel(q)
        let rect = FurniturePartSolids.partBox(plain, m)
        func pv(_ x: Double, _ axis: FamilyAxis) -> PartValue {
            guard let r = rect?.range(axis) else { return PartValue(x) }
            if abs(x - r.0.value) < 1e-7 { return r.0 }
            if abs(x - r.1.value) < 1e-7 { return r.1 }
            return PartValue(x)
        }
        func number(_ fb: FamilyBound) -> Double { if case .expr(let x) = fb { return Double(x) ?? 0 }; return 0 }
        let outline = pts.map { PartPoint(pv(number($0.x), u), pv(number($0.y), v)) }
        let openings: [[Vec2]] = num.solids.filter(\.isVoid).compactMap { s in
            guard case .polygon(let op) = s.profile else { return nil }
            return op.map { Vec2(number($0.x), number($0.y)) }
        }
        return profilePart(e.id, outline: outline, openings: openings, normal: w, u: u, v: v,
                           w: (boundValue(a[0].zMin, b[0].zMin, ctx), boundValue(a[0].zMax, b[0].zMax, ctx)))
    }

    /// A shelf or top sketched with more (or other) than four square sides.
    static func shapedShelf(_ e: Element, _ s: ShelfData, _ m: BIMModel) -> JointPart? {
        guard FurniturePartSolids.partBox(e, m) == nil else { return nil }
        let t = FurniturePartTypes.values(of: e, m).thickness
        guard t > Tolerance.length else { return nil }
        let b = FurniturePartBounds.bounds(of: e)
        var outline = s.boundary.enumerated().map { i, p in PartPoint(PartValue(p.x, b["p\(i).x"]), PartValue(p.y, b["p\(i).y"])) }
        if Polygon2(s.boundary).signedArea < 0 { outline.reverse() }
        let top = PartValue(s.elevation, b["z"])
        return profilePart(e.id, outline: outline, openings: [], normal: .z, u: .x, v: .y, w: (top.shifted(-t), top))
    }

    static func profilePart(_ id: ElementID, outline: [PartPoint], openings: [[Vec2]], normal: FamilyAxis, u: FamilyAxis, v: FamilyAxis,
                            w: (PartValue, PartValue)) -> JointPart? {
        guard outline.count >= 3 else { return nil }
        var lo = [PartValue(0), PartValue(0), PartValue(0)], hi = lo
        for (k, a) in [(0, u), (1, v)] {
            lo[a.idx] = outline.map { $0[k] }.min { $0.value < $1.value }!
            hi[a.idx] = outline.map { $0[k] }.max { $0.value < $1.value }!
        }
        (lo[normal.idx], hi[normal.idx]) = w.0.value <= w.1.value ? w : (w.1, w.0)
        var jp = JointPart(id: id, role: .side, lo: lo, hi: hi, reshapeable: true)
        jp.shape = .profile(normal: normal, outline: outline, openings: openings)
        return jp
    }

    // MARK: Contact

    /// Some piece of `p` touches or overlaps some piece of `q` on every axis, with an area of contact.
    static func piecesMeet(_ p: JointPart, _ q: JointPart) -> Bool {
        guard p.pieces != nil || q.pieces != nil else { return true }
        let ps = p.pieces ?? [JBox(lo: p.lo, hi: p.hi)], qs = q.pieces ?? [JBox(lo: q.lo, hi: q.hi)]
        for a in ps {
            for b in qs {
                let o = FamilyAxis.allCases.map { min(a.h($0), b.h($0)) - max(a.l($0), b.l($0)) }
                if o.allSatisfy({ $0 >= -eps }) && o.filter({ $0 > eps }).count >= 2 { return true }
            }
        }
        return false
    }

    /// Where `o` meets the face of shaped part `t` that lies across `axis`: the contact rectangle on `t`'s face plane
    /// clipped to its outline (minus its openings). nil when `t` isn't shaped there (no change); an empty rectangle when
    /// they don't meet.
    static func profileContact(through t: JointPart, other o: JointPart, axis: FamilyAxis) -> Rect2? {
        guard case .profile(let normal, let outline, let openings) = t.shape, normal == axis else { return nil }
        let plane = FamilySketchPlane.normal(normal)
        let (u, v, _) = plane.axes
        let rect = Rect2(min: Vec2(max(t.l(u), o.l(u)), max(t.l(v), o.l(v))), max: Vec2(min(t.h(u), o.h(u)), min(t.h(v), o.h(v))))
        guard rect.width > eps, rect.height > eps, let clipped = Polygon2(outline.map(\.vec)).clipped(to: rect) else { return .empty }
        var area = clipped.area
        for op in openings { area -= Polygon2(op).clipped(to: rect)?.area ?? 0 }
        return area > 1e-8 ? clipped.bounds : .empty
    }

    // MARK: Reshaping

    /// A piece of a part whose box went from `old` to `new`: faces on the old box's faces follow it; the rest are
    /// clamped into the new box.
    static func reshape(_ piece: JBox, from old: [PartValue], _ oldHi: [PartValue], to new: JBox) -> JBox {
        var b = piece
        for k in 0..<3 {
            if abs(piece.lo[k].value - old[k].value) < 1e-7 { b.lo[k] = new.lo[k] } else if piece.lo[k].value < new.lo[k].value { b.lo[k] = new.lo[k] }
            if abs(piece.hi[k].value - oldHi[k].value) < 1e-7 { b.hi[k] = new.hi[k] } else if piece.hi[k].value > new.hi[k].value { b.hi[k] = new.hi[k] }
        }
        return b
    }

    /// An outline on axes (`u`, `v`) of a part whose box went from (`lo`, `hi`) to `new`: clipped where a face moved
    /// in, stretched (the points on the old face move with it) where it moved out.
    static func reshape(_ outline: [PartPoint], u: FamilyAxis, v: FamilyAxis, from lo: [PartValue], _ hi: [PartValue], to new: JBox) -> [PartPoint] {
        var pts = outline
        for (k, a) in [(0, u), (1, v)] {
            for atMax in [false, true] {
                let old = atMax ? hi[a.idx] : lo[a.idx], to = atMax ? new.hi[a.idx] : new.lo[a.idx]
                let inward = atMax ? to.value < old.value - 1e-9 : to.value > old.value + 1e-9
                let outward = atMax ? to.value > old.value + 1e-9 : to.value < old.value - 1e-9
                if outward {
                    for i in pts.indices where abs(pts[i][k].value - old.value) < 1e-7 { pts[i][k] = to }
                } else if inward {
                    pts = clip(pts, k, to, keepAbove: !atMax)
                }
            }
        }
        return pts
    }

    /// Sutherland–Hodgman clip of an outline at coordinate `k` = `c`, keeping the side above (or below) it.
    static func clip(_ pts: [PartPoint], _ k: Int, _ c: PartValue, keepAbove: Bool) -> [PartPoint] {
        guard !pts.isEmpty else { return pts }
        let o = 1 - k
        func inside(_ p: PartPoint) -> Bool { keepAbove ? p[k].value >= c.value - 1e-12 : p[k].value <= c.value + 1e-12 }
        var out: [PartPoint] = []
        var prev = pts[pts.count - 1]
        for cur in pts {
            let ci = inside(cur), pi = inside(prev)
            if ci != pi {
                let t = (c.value - prev[k].value) / (cur[k].value - prev[k].value)
                var q = prev
                q[k] = c
                let same = abs(prev[o].value - cur[o].value) < 1e-12 && prev[o].plane == cur[o].plane
                q[o] = same ? prev[o] : PartValue(prev[o].value + t * (cur[o].value - prev[o].value))
                out.append(q)
            }
            if ci { out.append(cur) }
            prev = cur
        }
        // Drop repeated points.
        var clean: [PartPoint] = []
        for p in out where clean.last.map({ $0.vec.distance(to: p.vec) > 1e-9 }) ?? true { clean.append(p) }
        if clean.count > 1, let f = clean.first, let l = clean.last, f.vec.distance(to: l.vec) <= 1e-9 { clean.removeLast() }
        return clean
    }

    // MARK: Solids

    /// The main solid of a joined part with its final box: a box, a cylinder, or its (reshaped) outline.
    static func shapedSolid(_ name: String, _ part: JointPart, _ b: JBox, outline: [PartPoint]?, _ ctx: PartSolidContext) -> FamilySolid? {
        switch part.shape {
        case .box:
            return nil
        case .round(let axis):
            let r = min(b.ext(axis.others.0), b.ext(axis.others.1)) / 2
            let plane = FamilySketchPlane.normal(axis)
            let (u, v, _) = plane.axes
            return roundSolid(name, JRound(axis: axis, cu: b.lo[u.idx].shifted(r), cv: b.lo[v.idx].shifted(r), radius: r, lo: b.lo[axis.idx], hi: b.hi[axis.idx]), ctx)
        case .profile(let normal, _, _):
            guard let outline, outline.count >= 3 else { return nil }
            let plane = FamilySketchPlane.normal(normal)
            var pts = outline
            if Polygon2(pts.map(\.vec)).signedArea < 0 { pts.reverse() }
            var s = FamilySolid(name: name, profile: .polygon(pts.map { ctx.point($0.u, $0.v) }), zMin: ctx.bound(b.lo[normal.idx]), zMax: ctx.bound(b.hi[normal.idx]))
            if plane != .xy { s.workPlane = plane }
            return s
        }
    }

    /// A cylinder solid (round rails, round tenons and sockets).
    static func roundSolid(_ name: String, _ r: JRound, _ ctx: PartSolidContext, void isVoid: Bool = false) -> FamilySolid {
        let plane = FamilySketchPlane.normal(r.axis)
        var s = FamilySolid(name: name, profile: .circle(center: ctx.point(r.cu, r.cv), radius: PartSolidContext.number(r.radius)),
                            zMin: ctx.bound(FurniturePartSolids.range(r.lo, r.hi).0), zMax: ctx.bound(FurniturePartSolids.range(r.lo, r.hi).1), isVoid: isVoid)
        if plane != .xy { s.workPlane = plane }
        return s
    }
}
