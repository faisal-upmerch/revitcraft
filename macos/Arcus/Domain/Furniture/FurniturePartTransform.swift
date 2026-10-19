import Foundation
import ArcusGeometry

// FM4: Move, Copy, Rotate, Mirror and Array for furniture parts. Plan transforms move parts drawn in plan freely; parts
// drawn in an elevation keep to their plane, so they take quarter turns and mirrors square to the piece (other angles
// move them only). In elevations and sections, Move and Copy move parts in the view's plane (`translate`).

public enum FurniturePartTransform {
    /// A plan transform's action on one axis-aligned sketch plane: the new plane, and how (u, w) map (u' = su·u + ou or
    /// from w, etc.). nil when the transform isn't square to the axes.
    struct AxisMap {
        /// World x' and y' from x and y: x' = ax·(x or y) + tx…
        var swap: Bool
        var sx: Double, sy: Double
        var tx: Double, ty: Double
        /// Maps a world plan point.
        func apply(_ p: Vec2) -> Vec2 { swap ? Vec2(sx * p.y + tx, sy * p.x + ty) : Vec2(sx * p.x + tx, sy * p.y + ty) }
    }

    static func axisMap(_ t: Transform2) -> AxisMap? {
        let eps = 1e-9
        if abs(t.b) < eps && abs(t.c) < eps && abs(abs(t.a) - 1) < eps && abs(abs(t.d) - 1) < eps {
            return AxisMap(swap: false, sx: t.a.sign == .minus ? -1 : 1, sy: t.d.sign == .minus ? -1 : 1, tx: t.tx, ty: t.ty)
        }
        if abs(t.a) < eps && abs(t.d) < eps && abs(abs(t.b) - 1) < eps && abs(abs(t.c) - 1) < eps {
            return AxisMap(swap: true, sx: t.b.sign == .minus ? -1 : 1, sy: t.c.sign == .minus ? -1 : 1, tx: t.tx, ty: t.ty)
        }
        return nil
    }

    /// A linear part on an elevation plane under a plan transform: new plane, line and w-range, whether the line now
    /// runs the other way in its plane (the outside face flips) and whether the w-range reversed (base and top swap).
    static func elevation(_ plane: FamilySketchPlane, start: Vec2, end: Vec2, w: (Double, Double), _ t: Transform2)
        -> (plane: FamilySketchPlane, start: Vec2, end: Vec2, w: (Double, Double), flip: Bool, swapW: Bool)? {
        guard let m = axisMap(t) else {
            // Not square to the piece: moved by the transform's translation of the part's middle only.
            let mid = plane == .xz ? Vec2((start.x + end.x) / 2, (w.0 + w.1) / 2) : Vec2((w.0 + w.1) / 2, (start.x + end.x) / 2)
            let d = t.apply(mid) - mid
            let (du, dw) = plane == .xz ? (d.x, d.y) : (d.y, d.x)
            return (plane, Vec2(start.x + du, start.y), Vec2(end.x + du, end.y), (w.0 + dw, w.1 + dw), false, false)
        }
        // (new plane, u scale, u shift, w scale, w shift) per the table of square plan transforms.
        let (np, su, ou, sw, ow): (FamilySketchPlane, Double, Double, Double, Double)
        switch (plane, m.swap) {
        case (.xz, false): (np, su, ou, sw, ow) = (.xz, m.sx, m.tx, m.sy, m.ty)
        case (.xz, true): (np, su, ou, sw, ow) = (.yz, m.sy, m.ty, m.sx, m.tx)
        case (.yz, false): (np, su, ou, sw, ow) = (.yz, m.sy, m.ty, m.sx, m.tx)
        default: (np, su, ou, sw, ow) = (.xz, m.sx, m.tx, m.sy, m.ty)
        }
        let w0 = sw * w.0 + ow, w1 = sw * w.1 + ow
        return (np, Vec2(su * start.x + ou, start.y), Vec2(su * end.x + ou, end.y), (min(w0, w1), max(w0, w1)), su < 0, sw < 0)
    }

    /// Applies a plan transform. Returns true when handled (always for parts).
    public static func apply(_ t: Transform2, to e: inout Element) -> Bool {
        let mirror = t.isMirroring
        let rot = t.rotationAngle
        switch e.data {
        case .furniturePanel(var p):
            if p.plane == .xy {
                p.start = t.apply(p.start); p.end = t.apply(p.end)
                if mirror {
                    p.flipped.toggle()
                    let L = p.length
                    p.profile = p.profile.map { $0.map { Vec2(L - $0.x, $0.y) }.reversed() }
                    p.openings = p.openings?.map { PanelOpening(s0: L - $0.s1, s1: L - $0.s0, t0: $0.t0, t1: $0.t1) }
                }
            } else if let r = elevation(p.plane, start: p.start, end: p.end, w: (p.base, p.top), t) {
                if r.plane != p.plane { p.bounds = [:] }
                p.plane = r.plane; p.start = r.start; p.end = r.end; p.base = r.w.0; p.top = r.w.1
                if r.flip { p.flipped.toggle() }
                if r.swapW { let b = p.bounds["base"]; p.bounds["base"] = p.bounds["top"]; p.bounds["top"] = b }
            }
            e.data = .furniturePanel(p)
        case .furnitureShelf(var s):
            var pts = s.boundary.map(t.apply)
            var b = s.bounds
            if mirror {
                pts.reverse()
                let n = pts.count
                var nb: [String: FurnitureBound] = [:]
                for (k, v) in b {
                    let parts = k.split(separator: ".")
                    if parts.count == 2, let i = Int(parts[0].dropFirst()) { nb["p\(n - 1 - i).\(parts[1])"] = v } else { nb[k] = v }
                }
                b = nb
            }
            s.boundary = pts
            s.bounds = b
            if let a = s.spanAngle { s.spanAngle = t.applyVector(Vec2.fromAngle(a)).angle }
            e.data = .furnitureShelf(s)
        case .furnitureLeg(var l):
            l.location = t.apply(l.location)
            l.rotation = mirror ? Angle.normalize(-l.rotation + rot) : l.rotation + rot
            e.data = .furnitureLeg(l)
        case .furnitureRail(var r):
            if r.plane == .xy {
                r.start = t.apply(r.start); r.end = t.apply(r.end)
                // Slats lie to the line's left: a mirror would put them on its right, so the line runs the other way.
                if mirror, r.slats != nil {
                    swap(&r.start, &r.end)
                    let sb = r.bounds; r.bounds["start.u"] = sb["end.u"]; r.bounds["start.v"] = sb["end.v"]; r.bounds["end.u"] = sb["start.u"]; r.bounds["end.v"] = sb["start.v"]
                }
            } else {
                if let res = elevation(r.plane, start: r.start, end: r.end, w: (r.w, r.w), t) {
                    if res.plane != r.plane { r.bounds = [:] }
                    r.plane = res.plane; r.start = res.start; r.end = res.end; r.w = (res.w.0 + res.w.1) / 2
                }
            }
            e.data = .furnitureRail(r)
        case .furnitureEdgeProfile(var ep):
            ep.edge = transformEdge(ep.edge, t)
            e.data = .furnitureEdgeProfile(ep)
        case .furnitureForm(var f):
            if f.plane == .xy || f.kind != .extrusion {
                func loop(_ p: [Vec2]) -> [Vec2] { let q = p.map(t.apply); return mirror ? q.reversed() : q }
                if f.kind == .revolve || f.kind == .sweep || f.kind == .sweptBlend {
                    // Profiles are in their own (radius, height) or (left, up) coordinates: only the axis or path moves.
                    f.axis = f.axis.map(t.apply)
                    f.path = f.path.map { $0.map(t.apply) }
                    if mirror, f.path != nil { f.profile = f.profile.map { Vec2(-$0.x, $0.y) }.reversed(); f.endProfile = f.endProfile.map { $0.map { Vec2(-$0.x, $0.y) }.reversed() } }
                } else {
                    f.profile = loop(f.profile)
                    f.holes = f.holes.map(loop)
                    f.topProfile = f.topProfile.map(loop)
                }
                if var c = f.cushion { c.center = t.apply(c.center); c.rotation += rot; f.cushion = c }
            } else if let r = elevation(f.plane, start: .zero, end: Vec2(1, 0), w: (f.w0, f.w1), t) {
                // An extrusion sketched on an elevation plane: moved along the plane (and across it).
                let du = r.start.x
                f.profile = f.profile.map { Vec2($0.x + du, $0.y) }
                f.holes = f.holes.map { $0.map { Vec2($0.x + du, $0.y) } }
                f.w0 = r.w.0; f.w1 = r.w.1
            }
            e.data = .furnitureForm(f)
        default:
            return false
        }
        return true
    }

    /// The same edge after a plan transform square to the axes (other angles keep it).
    static func transformEdge(_ edge: PartEdge, _ t: Transform2) -> PartEdge {
        guard let m = axisMap(t) else { return edge }
        // Each plan axis maps to an axis and a sign.
        func mapAxis(_ a: FamilyAxis) -> (FamilyAxis, Double) {
            switch a {
            case .x: m.swap ? (.y, m.sy) : (.x, m.sx)
            case .y: m.swap ? (.x, m.sx) : (.y, m.sy)
            case .z: (.z, 1)
            }
        }
        let (a1, a2) = edge.across
        let (n1, s1) = mapAxis(a1), (n2, s2) = mapAxis(a2)
        let max1 = s1 > 0 ? edge.firstAtMax : !edge.firstAtMax, max2 = s2 > 0 ? edge.secondAtMax : !edge.secondAtMax
        let axis = mapAxis(edge.axis).0
        // Re-order to the new axis's cross axes (x, y, z order).
        var sides: [FamilyAxis: Bool] = [n1: max1, n2: max2]
        let probe = PartEdge(axis: axis, firstAtMax: false, secondAtMax: false).across
        sides[probe.0] = sides[probe.0] ?? false
        return PartEdge(axis: axis, firstAtMax: sides[probe.0] ?? false, secondAtMax: sides[probe.1] ?? false)
    }

    /// Moves a part in 3D (Move and Copy in elevations and sections).
    public static func translate(_ e: inout Element, by d: Vec3) {
        func inPlane(_ plane: FamilySketchPlane) -> (du: Double, dv: Double, dw: Double) {
            switch plane {
            case .xy: (d.x, d.y, d.z)
            case .xz: (d.x, d.z, d.y)
            case .yz: (d.y, d.z, d.x)
            }
        }
        switch e.data {
        case .furniturePanel(var p):
            let (du, dv, dw) = inPlane(p.plane)
            p.start = p.start + Vec2(du, dv); p.end = p.end + Vec2(du, dv); p.base += dw; p.top += dw
            e.data = .furniturePanel(p)
        case .furnitureRail(var r):
            let (du, dv, dw) = inPlane(r.plane)
            r.start = r.start + Vec2(du, dv); r.end = r.end + Vec2(du, dv); r.w += dw
            e.data = .furnitureRail(r)
        case .furnitureShelf(var s):
            s.boundary = s.boundary.map { $0 + d.xy }; s.elevation += d.z
            e.data = .furnitureShelf(s)
        case .furnitureLeg(var l):
            l.location = l.location + d.xy; l.base += d.z; l.top += d.z
            e.data = .furnitureLeg(l)
        case .furnitureForm(var f):
            if f.plane == .xy || f.kind != .extrusion {
                let mv = { (p: Vec2) in p + d.xy }
                if f.kind == .revolve || f.kind == .sweep || f.kind == .sweptBlend { f.axis = f.axis.map(mv); f.path = f.path.map { $0.map(mv) } }
                else { f.profile = f.profile.map(mv); f.holes = f.holes.map { $0.map(mv) }; f.topProfile = f.topProfile.map { $0.map(mv) } }
                if var c = f.cushion { c.center = c.center + d.xy; f.cushion = c }
                f.w0 += d.z; f.w1 += d.z
            } else {
                let (du, dv, dw) = inPlane(f.plane)
                f.profile = f.profile.map { $0 + Vec2(du, dv) }; f.holes = f.holes.map { $0.map { $0 + Vec2(du, dv) } }
                f.w0 += dw; f.w1 += dw
            }
            e.data = .furnitureForm(f)
        default: break
        }
    }

    /// The 3D move a vertical view's (u, z) translation means: along the view's right vector, and up.
    public static func viewTranslation(_ t: Transform2, view: ViewData?) -> Vec3? {
        guard let v = view, v.kind.isVerticalCut, let r = v.rightVector, abs(t.a - 1) < 1e-9, abs(t.d - 1) < 1e-9, abs(t.b) < 1e-9, abs(t.c) < 1e-9 else { return nil }
        return Vec3(r * t.tx, z: t.ty)
    }
}
