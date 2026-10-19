import Foundation
import ArcusGeometry

// COMPA: geometry helpers for Group A (handles, locks, hinges, drawer systems, sliding doors). Every Group A solid is
// written once in a local frame tied to how the item mounts (a along it, b across it, c out of its mounting face) and
// emitted once per family frame: the face or plan frame (a, b, c = X, Y, Z), or FM5's legacy frames, where each
// orientation (handles Horizontal / Upright / On Lid, hinges Side / Top / Bottom / Back Edge) is a copy shown by its
// Yes/No parameter, so fronts keep placing and machining them as they do FM5's families.

/// A local frame: the family axis and sign of each local axis, and the Yes/No parameter that shows its solids.
struct FrameA: Sendable {
    var a: (FamilyAxis, Double)
    var b: (FamilyAxis, Double)
    var c: (FamilyAxis, Double)
    var visibility: String?

    var axes: [(FamilyAxis, Double)] { [a, b, c] }

    /// Face and plan frames: a, b, c are X, Y, Z.
    static let identity = FrameA(a: (.x, 1), b: (.y, 1), c: (.z, 1), visibility: nil)
    /// FM5 handles: across a front (a: +X, b: +Z, c: -Y toward the viewer), standing up, or on a lid's top face.
    static let front: [FrameA] = [FrameA(a: (.x, 1), b: (.z, 1), c: (.y, -1), visibility: "Horizontal"),
                                  FrameA(a: (.z, 1), b: (.x, 1), c: (.y, -1), visibility: "Upright"),
                                  FrameA(a: (.x, 1), b: (.y, 1), c: (.z, 1), visibility: "On Lid")]
    /// FM5 hinges: a from the hinge edge into the opening, b along the edge, c behind the front, on a side edge, the top
    /// edge of a lift-up flap, the bottom edge of a drop-down flap, or the back edge of a lid.
    static let hinge: [FrameA] = [FrameA(a: (.x, 1), b: (.z, 1), c: (.y, 1), visibility: "Side Edge"),
                                  FrameA(a: (.z, -1), b: (.x, 1), c: (.y, 1), visibility: "Top Edge"),
                                  FrameA(a: (.z, 1), b: (.x, 1), c: (.y, 1), visibility: "Bottom Edge"),
                                  FrameA(a: (.y, -1), b: (.x, 1), c: (.z, -1), visibility: "Back Edge")]

    /// A local expression on family axis `ax` (negated when the local axis runs against it).
    static func fam(_ e: String, _ sign: Double) -> String { sign > 0 ? e : "-(\(e))" }

    /// A range along a local axis, written along its family axis.
    static func range(_ r: (String, String), _ sign: Double) -> (String, String) { sign > 0 ? r : ("-(\(r.1))", "-(\(r.0))") }

    /// The sketch plane whose normal is `axis`.
    static func plane(normal axis: FamilyAxis) -> FamilySketchPlane {
        switch axis {
        case .z: .xy
        case .y: .xz
        case .x: .yz
        }
    }

    /// Maps a point given on the two local axes other than `along` (in a, b, c order) to the (u, v) of the sketch plane
    /// normal to `along`'s family axis.
    func uv(_ p: (String, String), along k: Int) -> FamilyPoint {
        let others = [0, 1, 2].filter { $0 != k }
        let ax = axes
        var coord: [FamilyAxis: String] = [:]
        coord[ax[others[0]].0] = Self.fam(p.0, ax[others[0]].1)
        coord[ax[others[1]].0] = Self.fam(p.1, ax[others[1]].1)
        let pl = Self.plane(normal: ax[k].0)
        return FamilyPoint(coord[pl.axes.u] ?? CX.zero, coord[pl.axes.v] ?? CX.zero)
    }
}

/// Local point lists (on two local axes) for profiles and paths.
enum PtsA {
    /// A rectangle centred at `c`, `w` × `h`.
    static func rect(_ c: (String, String) = (CX.zero, CX.zero), _ w: String, _ h: String) -> [(String, String)] {
        let x = "(\(w)) / 2", y = "(\(h)) / 2"
        return [("\(c.0) - \(x)", "\(c.1) - \(y)"), ("\(c.0) + \(x)", "\(c.1) - \(y)"), ("\(c.0) + \(x)", "\(c.1) + \(y)"), ("\(c.0) - \(x)", "\(c.1) + \(y)")]
    }

    /// A rectangle from two corners.
    static func box(_ u: (String, String), _ v: (String, String)) -> [(String, String)] {
        [(u.0, v.0), (u.1, v.0), (u.1, v.1), (u.0, v.1)]
    }

    /// A rounded rectangle (radius `r` ≤ half the shorter side; equal to it gives a stadium).
    static func rounded(_ c: (String, String) = (CX.zero, CX.zero), _ w: String, _ h: String, _ r: String, segments: Int = 6) -> [(String, String)] {
        let x = "(\(w)) / 2", y = "(\(h)) / 2", rr = "(\(r))"
        let corners: [(String, String, Double)] = [("\(c.0) + \(x) - \(rr)", "\(c.1) - \(y) + \(rr)", -90), ("\(c.0) + \(x) - \(rr)", "\(c.1) + \(y) - \(rr)", 0),
                                                   ("\(c.0) - \(x) + \(rr)", "\(c.1) + \(y) - \(rr)", 90), ("\(c.0) - \(x) + \(rr)", "\(c.1) - \(y) + \(rr)", 180)]
        var out: [(String, String)] = []
        for (ux, uy, a0) in corners {
            for k in 0...segments {
                let a = (a0 + 90 * Double(k) / Double(segments)) * .pi / 180
                out.append(("\(ux) + \(rr) * \(LX.num(cos(a)))", "\(uy) + \(rr) * \(LX.num(sin(a)))"))
            }
        }
        return out
    }

    /// A circle polygon.
    static func circle(_ c: (String, String) = (CX.zero, CX.zero), _ r: String, segments: Int = 20) -> [(String, String)] {
        (0..<segments).map { k in
            let a = Double(k) / Double(segments) * 2 * .pi
            return ("\(c.0) + (\(r)) * \(LX.num(cos(a)))", "\(c.1) + (\(r)) * \(LX.num(sin(a)))")
        }
    }

    /// An ellipse polygon, `rx` × `ry` radii.
    static func ellipse(_ c: (String, String) = (CX.zero, CX.zero), _ rx: String, _ ry: String, segments: Int = 24) -> [(String, String)] {
        (0..<segments).map { k in
            let a = Double(k) / Double(segments) * 2 * .pi
            return ("\(c.0) + (\(rx)) * \(LX.num(cos(a)))", "\(c.1) + (\(ry)) * \(LX.num(sin(a)))")
        }
    }

    /// A regular polygon (faceted knobs), first vertex at `start` degrees.
    static func polygon(_ c: (String, String) = (CX.zero, CX.zero), _ r: String, sides: Int, start: Double = 0) -> [(String, String)] {
        (0..<sides).map { k in
            let a = (start + 360 * Double(k) / Double(sides)) * .pi / 180
            return ("\(c.0) + (\(r)) * \(LX.num(cos(a)))", "\(c.1) + (\(r)) * \(LX.num(sin(a)))")
        }
    }

    /// An open arc path.
    static func arc(_ c: (String, String), _ r: String, from a0: Double, sweep: Double, segments: Int = 12) -> [(String, String)] {
        (0...segments).map { k in
            let a = (a0 + sweep * Double(k) / Double(segments)) * .pi / 180
            return ("\(c.0) + (\(r)) * \(LX.num(cos(a)))", "\(c.1) + (\(r)) * \(LX.num(sin(a)))")
        }
    }

    /// A revolve profile from fractions of a radius and a height: (r × fr, base + h × fh).
    static func turned(_ r: String, _ h: String, base: String = CX.zero, _ f: [(Double, Double)]) -> [(String, String)] {
        f.map { ("(\(r)) * \(LX.num($0.0))", "\(base) + (\(h)) * \(LX.num($0.1))") }
    }

    /// A ring (torus) section for revolves: a circle of radius `t` centred `R` from the axis, at height `h`.
    static func ring(_ R: String, _ t: String, at h: String, segments: Int = 14) -> [(String, String)] {
        circle((R, h), t, segments: segments)
    }
}

/// Writes Group A geometry: local solids emitted once per frame.
struct ShapeA {
    var b: ComponentBuilder
    var frames: [FrameA]
    /// The component's own Yes/No visibility for the solids added next (face and plan frames only).
    var visibility: String?

    init(_ b: ComponentBuilder, frames: [FrameA] = [.identity]) {
        self.b = b
        self.frames = frames
    }

    /// Detail levels of the solids added next.
    var levels: Set<DetailLevel> {
        get { b.visibleAt }
        set { b.visibleAt = newValue }
    }

    /// Material slot of the solids added next (nil: the first slot).
    mutating func using(_ slot: String?) { b.using(slot) }

    /// Runs `body` once per frame; returns the ids of the solids it added.
    @discardableResult
    private mutating func each(_ body: (inout ComponentBuilder, FrameA) -> Void) -> [String] {
        let own = visibility
        let before = b.definition.family.solids.count
        for fr in frames {
            b.visibility = fr.visibility ?? own
            body(&b, fr)
        }
        b.visibility = own
        return b.definition.family.solids[before...].map(\.id)
    }

    /// Makes each void (one per frame) cut only the matching solid of `solids`.
    mutating func cut(_ voids: [String], from solids: [String]) {
        for (v, s) in zip(voids, solids) {
            if let k = b.definition.family.solids.firstIndex(where: { $0.id == v }) { b.definition.family.solids[k].cuts = [s] }
        }
    }

    private static func label(_ name: String, _ fr: FrameA, _ n: Int) -> String { n > 1 ? "\(name) (\(fr.visibility ?? ""))" : name }

    /// A box from local ranges.
    @discardableResult
    mutating func box(_ name: String, a: (String, String), b bb: (String, String), c: (String, String), void: Bool = false) -> [String] {
        let n = frames.count
        return each { b, fr in
            var r: [FamilyAxis: (String, String)] = [:]
            r[fr.a.0] = FrameA.range(a, fr.a.1)
            r[fr.b.0] = FrameA.range(bb, fr.b.1)
            r[fr.c.0] = FrameA.range(c, fr.c.1)
            guard let x = r[.x], let y = r[.y], let z = r[.z] else { return }
            b.box(Self.label(name, fr, n), x: x, y: y, z: z, void: void)
        }
    }

    /// A cylinder along local axis `along` (0 = a, 1 = b, 2 = c), centred at `center` on the other two (a, b, c order).
    @discardableResult
    mutating func cylinder(_ name: String, along k: Int, center: (String, String) = (CX.zero, CX.zero), radius: String, range: (String, String), void: Bool = false,
                           segments: Int = 24) -> [String] {
        // A polygon prism rather than a circle profile: small radii stay round (circles tessellate by a fixed chord).
        prism(name, along: k, profile: PtsA.circle(center, radius, segments: segments), range: range, void: void)
    }

    /// A prism: a closed profile on the two local axes other than `along`, extruded along it.
    @discardableResult
    mutating func prism(_ name: String, along k: Int, profile: [(String, String)], range: (String, String), void: Bool = false) -> [String] {
        let n = frames.count
        return each { b, fr in
            let (w, s) = fr.axes[k]
            let r = FrameA.range(range, s)
            b.extrusion(Self.label(name, fr, n), profile: profile.map { fr.uv($0, along: k) }, plane: FrameA.plane(normal: w), from: r.0, to: r.1, void: void)
        }
    }

    /// A revolve about local axis `along` through `center` (on the other two axes): profile (r, h), h measured along
    /// the local axis from 0 (put the base in the profile's h).
    @discardableResult
    mutating func revolve(_ name: String, along k: Int, center: (String, String) = (CX.zero, CX.zero), profile: [(String, String)],
                          from start: Double = 0, to end: Double = 360) -> [String] {
        let n = frames.count
        return each { b, fr in
            let (w, s) = fr.axes[k]
            let p = fr.uv(center, along: k)
            guard case .expr(let u) = p.x, case .expr(let v) = p.y else { return }
            let prof = profile.map { FamilyPoint($0.0, FrameA.fam($0.1, s)) }
            b.revolve(Self.label(name, fr, n), profile: prof, plane: FrameA.plane(normal: w), axis: (u, v), startDegrees: LX.num(start), endDegrees: LX.num(end))
        }
    }

    /// A loft along local axis `along` from a bottom loop at `range.0` to a top loop at `range.1` (loops on the other two
    /// axes, with the same number of points).
    @discardableResult
    mutating func blend(_ name: String, along k: Int, bottom: [(String, String)], top: [(String, String)], range: (String, String)) -> [String] {
        let n = frames.count
        return each { b, fr in
            let (w, s) = fr.axes[k]
            let lo = bottom.map { fr.uv($0, along: k) }, hi = top.map { fr.uv($0, along: k) }
            let r = FrameA.range(range, s)
            b.blend(Self.label(name, fr, n), bottom: s > 0 ? lo : hi, top: s > 0 ? hi : lo, plane: FrameA.plane(normal: w), from: r.0, to: r.1)
        }
    }

    /// A sweep: an open path on the plane of local axes (i, j) (in i, j order) at `at` along the third axis, carrying a
    /// closed profile whose x is to the left of the path and y along the third axis. Keep profiles symmetric in x.
    @discardableResult
    mutating func sweep(_ name: String, plane i: Int, _ j: Int, path: [(String, String)], profile: [(String, String)], at: String = CX.zero) -> [String] {
        let k = 3 - i - j
        let n = frames.count
        return each { b, fr in
            let (w, s) = fr.axes[k]
            // Path points on (i, j): give `uv` its (a, b, c)-ordered pair.
            let pts = path.map { p in fr.uv(i < j ? p : (p.1, p.0), along: k) }
            let prof = profile.map { FamilyPoint($0.0, FrameA.fam($0.1, s)) }
            b.sweep(Self.label(name, fr, n), path: pts, profile: prof, plane: FrameA.plane(normal: w), at: FrameA.fam(at, s))
        }
    }

    /// A round rod along an open path on local plane (i, j), radius `r`.
    @discardableResult
    mutating func rod(_ name: String, plane i: Int, _ j: Int, path: [(String, String)], radius r: String, at: String = CX.zero) -> [String] {
        sweep(name, plane: i, j, path: path, profile: PtsA.circle((CX.zero, CX.zero), r, segments: 16), at: at)
    }

    /// Adds solids shown only when the type's Yes/No `flag` is on (`when: false`: only when it's off), combined with
    /// each frame's own visibility through formula parameters ("Horizontal Disc Profile" = and(Horizontal, Disc Profile)).
    mutating func variant(_ flag: String, when on: Bool = true, _ body: (inout ShapeA) -> Void) {
        let saved = frames, own = visibility
        let cond = on ? flag : "not(\(flag))"
        let tag = on ? flag : "No \(flag)"
        if frames.allSatisfy({ $0.visibility == nil }) {
            if !on { b.flag(tag, false, formula: cond) }
            visibility = tag
        } else {
            frames = saved.map { fr in
                var f = fr
                if let v = fr.visibility {
                    f.visibility = "\(v) \(tag)"
                    b.flag("\(v) \(tag)", false, formula: "and(\(v), \(cond))")
                }
                return f
            }
        }
        body(&self)
        frames = saved
        visibility = own
    }

    func build() -> ComponentDefinition { b.build() }
}

// MARK: Shared family pieces

extension ShapeA {
    /// FM5's handle orientation flags (fronts set Vertical and On Lid).
    static func frontFlags(_ b: inout ComponentBuilder) {
        b.flag("Vertical", false)
        b.flag("On Lid", false)
        b.flag("Horizontal", false, formula: "and(not(Vertical), not(On Lid))")
        b.flag("Upright", false, formula: "and(Vertical, not(On Lid))")
    }

    /// FM5's hinge orientation flags (fronts set Top, Bottom and Back Edge).
    static func hingeFlags(_ b: inout ComponentBuilder) {
        b.flag("Top Edge", false)
        b.flag("Bottom Edge", false)
        b.flag("Back Edge", false)
        b.flag("Side Edge", false, formula: "not(or(Top Edge, Bottom Edge, Back Edge))")
    }

    /// Countersunk screw heads (Fine): small discs on the local c face at the given (a, b) points.
    mutating func screws(_ name: String, at pts: [(String, String)], c: String, diameter: String = CX.mm(8), outward: Bool = true) {
        let saved = levels
        levels = [.fine]
        for (k, p) in pts.enumerated() {
            cylinder("\(name) \(k + 1)", along: 2, center: p, radius: "(\(diameter)) / 2", range: outward ? (c, "\(c) + 0.0008 m") : ("\(c) - 0.0008 m", c))
        }
        levels = saved
    }
}

// MARK: Defaults

/// Group A's trade numbers.
enum TradeA {
    static func mm(_ v: Double) -> Double { v / 1000 }
    static func inch(_ v: Double) -> Double { v * 0.0254 }
    /// "128 mm" / "5\"" style size words for aliases.
    static func mmWord(_ v: Double) -> String { "\(LX.num(v)) mm" }
    static func inchWord(_ mmValue: Double) -> String {
        let i = mmValue / 25.4
        let eighths = (i * 8).rounded()
        let whole = Int(eighths / 8), rest = Int(eighths) % 8
        guard rest != 0 else { return "\(whole)\"" }
        var n = rest, d = 8
        while n % 2 == 0 { n /= 2; d /= 2 }
        return whole == 0 ? "\(n)/\(d)\"" : "\(whole) \(n)/\(d)\""
    }
    /// The aliases of a millimetre size: "128 mm", "128mm", and its inch equivalent.
    static func sizeAliases(_ v: Double) -> [String] { ["\(LX.num(v)) mm", "\(LX.num(v))mm", inchWord(v)] }
}
