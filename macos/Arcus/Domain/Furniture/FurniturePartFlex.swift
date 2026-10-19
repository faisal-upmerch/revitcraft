import Foundation
import ArcusGeometry

// FMG1: parts that flex the way Revit-style sketches locked to reference planes do, where a single plane and offset per
// face isn't enough:
// - parts drawn at an angle (raked legs, struts, stringers, screen leaves): their ends follow planes, so their corners
//   are written as formulas of the ends when compiling (the line's direction and length change as the piece flexes);
// - rails kept at a share of the space between two bounds (EQ), such as the slats of a raked back;
// - Slats whose far side follows a plane: the layout (Fixed Distance or Fixed Number) is redone between the first slat
//   and the far side, in documents and in compiled families (where the count is a formula and extra slats show by it);
// - revolves whose axis and profile points are locked to planes.

public enum FurniturePartFlex {
    static func num(_ v: Double) -> String { FurnitureFormLocks.num(v) }

    // MARK: Plane formulas

    /// Each plane's position as a length formula of the family's parameters: its offset formula, or its position when
    /// it never moves (origin planes, planes no dimension places). Planes the dimension solver places are left out.
    static func planeFormulas(_ f: FamilyDefinition) -> [String: String] {
        let stable = FurnitureCompiler.stablePlanes(f)
        var out: [String: String] = [:]
        for p in f.referencePlanes {
            let o = p.offset.trimmingCharacters(in: .whitespaces)
            if let v = Double(o) {
                if stable.contains(p.name) { out[p.name] = "\(num(v)) m" }
            } else if !o.isEmpty {
                out[p.name] = o
            }
        }
        return out
    }

    // MARK: Angled parts

    /// The ends of a part's line on its sketch plane, with the planes they follow.
    struct LineEnds {
        var su: PartValue, sv: PartValue, eu: PartValue, ev: PartValue
        var start: Vec2 { Vec2(su.value, sv.value) }
        var end: Vec2 { Vec2(eu.value, ev.value) }
    }

    /// A corner of a part drawn at an angle: from its start (or end) `along` the line and `across` it (to its left), the
    /// end cut square, level (v constant) or plumb (u constant). Compiling with plane formulas writes the corner as a
    /// formula of the ends, so it follows them as the line turns and stretches.
    static func corner(_ l: LineEnds, atEnd: Bool, along: Double, across: Double, cut: RailEndCut = .perpendicular, _ ctx: PartSolidContext) -> (PartValue, PartValue) {
        let s = l.start, e = l.end
        let len = s.distance(to: e)
        guard len > Tolerance.length else { return (atEnd ? l.eu : l.su, atEnd ? l.ev : l.sv) }
        let d = (e - s) / len, n = d.perpendicular
        let base = (atEnd ? e : s) + d * along
        var cut = cut
        if cut == .horizontal && abs(d.y) < 1e-6 || cut == .vertical && abs(d.x) < 1e-6 { cut = .perpendicular }
        let p: Vec2 = switch cut {
        case .perpendicular: base + n * across
        case .horizontal: Vec2(base.x - across / d.y, base.y)
        case .vertical: Vec2(base.x, base.y + across / d.x)
        }
        guard let su = ctx.formula(l.su), let sv = ctx.formula(l.sv), let eu = ctx.formula(l.eu), let ev = ctx.formula(l.ev) else {
            return (PartValue(p.x), PartValue(p.y))
        }
        let du = "((\(eu)) - (\(su)))", dv = "((\(ev)) - (\(sv)))"
        let length = "sqrt(\(du) * \(du) + \(dv) * \(dv))"
        let pu = atEnd ? eu : su, pv = atEnd ? ev : sv
        let bu = abs(along) < 1e-12 ? "(\(pu))" : "(\(pu)) + \(du) * (\(num(along)) m) / \(length)"
        let bv = abs(along) < 1e-12 ? "(\(pv))" : "(\(pv)) + \(dv) * (\(num(along)) m) / \(length)"
        let a = "(\(num(across)) m)"
        let (fu, fv): (String, String)
        if abs(across) < 1e-12 { (fu, fv) = (bu, bv) } else {
            switch cut {
            case .perpendicular: (fu, fv) = ("\(bu) - \(dv) * \(a) / \(length)", "\(bv) + \(du) * \(a) / \(length)")
            case .horizontal: (fu, fv) = ("\(bu) - \(a) * \(length) / \(dv)", bv)
            case .vertical: (fu, fv) = (bu, "\(bv) + \(a) * \(length) / \(du)")
            }
        }
        return (PartValue(p.x, formula: fu), PartValue(p.y, formula: fv))
    }

    /// The outline of a part drawn at an angle: its start and end across the line at `a` and `b` (to its left), each end
    /// extended along the line and cut as given.
    static func outline(_ l: LineEnds, a: Double, b: Double, extensions: (Double, Double) = (0, 0), cuts: (RailEndCut, RailEndCut) = (.perpendicular, .perpendicular),
                        _ ctx: PartSolidContext) -> [(PartValue, PartValue)] {
        [corner(l, atEnd: false, along: -extensions.0, across: a, cut: cuts.0, ctx), corner(l, atEnd: true, along: extensions.1, across: a, cut: cuts.1, ctx),
         corner(l, atEnd: true, along: extensions.1, across: b, cut: cuts.1, ctx), corner(l, atEnd: false, along: -extensions.0, across: b, cut: cuts.0, ctx)]
    }

    /// A polygon of bound corners on `plane` extruded along its normal (counterclockwise in its sketch).
    static func prism(_ name: String, plane: FamilySketchPlane, _ pts: [(PartValue, PartValue)], w: (PartValue, PartValue), _ ctx: PartSolidContext) -> FamilySolid {
        let (w0, w1) = FurniturePartSolids.range(w.0, w.1)
        var pts = pts
        if Polygon2(pts.map { Vec2($0.0.value, $0.1.value) }).signedArea < 0 { pts.reverse() }
        var s = FamilySolid(name: name, profile: .polygon(pts.map { ctx.point($0.0, $0.1) }), zMin: ctx.bound(w0), zMax: ctx.bound(w1))
        if plane != .xy { s.workPlane = plane }
        return s
    }

    // MARK: Rails: EQ and slats

    /// A rail coordinate: its bound, or when it is kept by EQ, a formula of the EQ's bounds (compiling).
    static func railValue(_ e: Element, _ r: RailData, _ key: String, _ value: Double, _ ctx: PartSolidContext) -> PartValue {
        var v = PartValue(value, r.bounds[key])
        guard let q = r.eq?[key], q.count > 0, ctx.planeFormulas != nil else { return v }
        func f(_ b: FurnitureBound) -> String? {
            if case .value(let x) = b { return "\(num(x)) m" }
            return ctx.formula(PartValue(0, b))
        }
        guard let lo = f(q.low), let hi = f(q.high) else { return v }
        v.formula = "(\(lo)) + ((\(hi)) - (\(lo))) * \(q.index) / \(q.count)"
        return v
    }

    /// One slat of a Slats rail: its offset across the line from the first slat (now), the formula of its line across
    /// (compiling, when the far side follows a plane) and the yes/no parameter that shows it.
    struct Slat { var offset: Double; var across: String?; var visibility: String? }

    /// The slats of a rail (one, unshifted, for a plain rail). Compiling a Slats rail whose first line and far side
    /// follow planes writes each slat's line as a formula: Fixed Number spreads the slats evenly between them; Fixed
    /// Distance keeps the spacing and centres the slats, with the count as a formula and the slats beyond it hidden.
    static func slats(_ e: Element, _ r: RailData, _ ctx: PartSolidContext) -> [Slat] {
        guard let layout = r.slats else { return [Slat(offset: 0, across: nil, visibility: nil)] }
        let numeric = layout.offsets.map { Slat(offset: $0, across: nil, visibility: nil) }
        guard ctx.planeFormulas != nil, let f = FurniturePartSolids.linearFrame(r.plane, r.start, r.end), r.bounds["far"] != nil else { return numeric }
        let key = f.lineAlongU ? "start.v" : "start.u"
        let line = railValue(e, r, key, f.lineAlongU ? r.start.y : r.start.x, ctx)
        let far = PartValue((f.lineAlongU ? r.start.y : r.start.x) + f.across * layout.extent, r.bounds["far"])
        guard let s = ctx.formula(line), let fs = ctx.formula(far) else { return numeric }
        let sign = f.across > 0 ? "+" : "-"
        let extent = f.across > 0 ? "((\(fs)) - (\(s)))" : "((\(s)) - (\(fs)))"
        switch layout.rule {
        case .fixedNumber:
            let n = max(1, layout.number)
            return numeric.enumerated().map { k, sl in
                Slat(offset: sl.offset, across: n == 1 ? "(\(s)) + ((\(fs)) - (\(s))) / 2" : "(\(s)) + ((\(fs)) - (\(s))) * \(k) / \(n - 1)", visibility: nil)
            }
        case .maximumSpacing:
            guard layout.spacing > 1e-6 else { return numeric }
            let mark = e.mark.isEmpty ? "Slats \(e.id.raw)" : e.mark
            let count = "\(mark) Slat Count"
            ctx.addParameter(FamilyParameter(name: count, type: .integer, group: .other,
                                             formula: "max(roundup(\(extent) / (\(num(layout.spacing)) m) - 0.000000001), 1) + 1"))
            let now = numeric.count
            let most = min(120, max(now + 4, Int(Double(now) * 1.6) + 1))
            return (0..<most).map { k in
                var vis: String?
                if k > 1 {
                    vis = "\(mark) Slat \(k + 1)"
                    ctx.addParameter(FamilyParameter(name: vis!, type: .bool, group: .other, formula: "\(count) > \(k)"))
                }
                let offset = k < now ? numeric[k].offset : layout.extent
                return Slat(offset: offset, across: "(\(s)) + ((\(fs)) - (\(s))) * min(\(k) / (\(count) - 1), 1)", visibility: vis)
            }
        case .fixedDistance:
            guard layout.spacing > 1e-6 else { return numeric }
            let mark = e.mark.isEmpty ? "Slats \(e.id.raw)" : e.mark
            let count = "\(mark) Slat Count"
            let sp = "\(num(layout.spacing)) m"
            ctx.addParameter(FamilyParameter(name: count, type: .integer, group: .other, formula: "max(rounddown(\(extent) / (\(sp)) + 0.000000001) + 1, 1)"))
            let now = numeric.count
            let most = min(120, max(now + 4, Int(Double(now) * 1.6) + 1))
            return (0..<most).map { k in
                var vis: String?
                if k > 0 {
                    vis = "\(mark) Slat \(k + 1)"
                    ctx.addParameter(FamilyParameter(name: vis!, type: .bool, group: .other, formula: "\(count) > \(k)"))
                }
                let offset = k < now ? numeric[k].offset : (numeric.first?.offset ?? 0) + layout.spacing * Double(k)
                return Slat(offset: offset, across: "(\(s)) \(sign) (((\(extent)) - (\(sp)) * (\(count) - 1)) / 2 + \(num(layout.spacing * Double(k))) m)", visibility: vis)
            }
        }
    }

    /// The far side of a Slats rail (the last slat's line), across its line; nil for rails that aren't slats along an axis.
    static func slatsFar(_ r: RailData) -> (axis: FamilyAxis, value: Double)? {
        guard let layout = r.slats, let f = FurniturePartSolids.linearFrame(r.plane, r.start, r.end) else { return nil }
        return (f.crossAxis, (f.lineAlongU ? r.start.y : r.start.x) + f.across * layout.extent)
    }

    /// Sets the far side of a Slats rail: the extent from its first slat's line.
    static func setSlatsFar(_ v: Double, _ r: inout RailData) {
        guard r.slats != nil, let f = FurniturePartSolids.linearFrame(r.plane, r.start, r.end) else { return }
        r.slats?.extent = max(0, (v - (f.lineAlongU ? r.start.y : r.start.x)) * f.across)
    }

    /// Binds a new Slats rail's first line and far side to what the region's two sides lie on (a plane, or the face of a
    /// part that follows one), half a slat in from each side, so the layout follows them as the piece flexes.
    static func bindSlats(_ r: inout RailData, near: Double, farSide: Double, slatWidth w: Double, in tx: TransactionContext) {
        guard let f = FurniturePartSolids.linearFrame(r.plane, r.start, r.end) else { return }
        let binder = FurniturePartBinder(tx.model, excluding: ElementID(UInt64.max), boxes: FurniturePartBinder.boxes(tx.model))
        let key = f.lineAlongU ? ["start.v", "end.v"] : ["start.u", "end.u"]
        if case .plane(let n, let o)? = binder.bound(near, along: f.crossAxis) {
            for k in key { r.bounds[k] = .plane(n, offset: o + f.across * w / 2) }
        }
        if case .plane(let n, let o)? = binder.bound(farSide, along: f.crossAxis) {
            r.bounds["far"] = .plane(n, offset: o - f.across * w / 2)
        }
    }

    // MARK: Revolves

    /// The axis along which a revolve's profile radii are measured (the sketch plane's horizontal axis).
    static func radialAxis(_ f: FurnitureFormData) -> FamilyAxis { f.plane == .yz ? .y : .x }

    /// A revolve's plane-bindable coordinates (none when it follows a lock, or isn't a revolve).
    static func revolveCoordinates(_ f: FurnitureFormData) -> [PartCoordinate] {
        guard f.kind == .revolve, f.lock == nil, let axis = f.axis else { return [] }
        let ra = radialAxis(f)
        let a = ra == .x ? axis.x : axis.y
        var out = [PartCoordinate(key: "axis.x", axis: .x, value: axis.x), PartCoordinate(key: "axis.y", axis: .y, value: axis.y),
                   PartCoordinate(key: "w0", axis: .z, value: f.w0)]
        for (i, p) in f.profile.enumerated() {
            out.append(PartCoordinate(key: "p\(i).r", axis: ra, value: a + p.x))
            out.append(PartCoordinate(key: "p\(i).h", axis: .z, value: f.w0 + p.y))
        }
        return out
    }

    /// Sets one coordinate of a revolve (profile points keep their place when the axis or base moves only through their
    /// own bounds).
    static func setRevolve(_ key: String, _ v: Double, _ f: inout FurnitureFormData) {
        guard f.kind == .revolve, var axis = f.axis else { return }
        switch key {
        case "axis.x": axis.x = v; f.axis = axis
        case "axis.y": axis.y = v; f.axis = axis
        case "w0": f.w0 = v; f.w1 = v
        default:
            let parts = key.split(separator: ".")
            guard parts.count == 2, let i = Int(parts[0].dropFirst()), f.profile.indices.contains(i) else { return }
            if parts[1] == "r" { f.profile[i].x = max(0, v - (radialAxis(f) == .x ? axis.x : axis.y)) } else { f.profile[i].y = v - f.w0 }
        }
    }

    /// A revolve whose sketch is bound to planes, written with formulas of the planes (compiling); nil otherwise.
    static func revolveSolid(_ name: String, _ f: FurnitureFormData, _ ctx: PartSolidContext) -> FamilySolid? {
        guard f.kind == .revolve, f.lock == nil, let b = f.bounds, !b.isEmpty, ctx.planeFormulas != nil, let axis = f.axis else { return nil }
        let ra = radialAxis(f)
        let a = ra == .x ? axis.x : axis.y
        func fm(_ key: String, _ v: Double) -> String? { ctx.formula(PartValue(v, b[key])) }
        guard let ax = fm("axis.x", axis.x), let ay = fm("axis.y", axis.y), let w0 = fm("w0", f.w0) else { return nil }
        let radial = ra == .x ? ax : ay
        var pts: [FamilyPoint] = []
        for (i, p) in f.profile.enumerated() {
            guard let r = fm("p\(i).r", a + p.x), let h = fm("p\(i).h", f.w0 + p.y) else { return nil }
            pts.append(FamilyPoint(.expr("(\(r)) - (\(radial))"), .expr("(\(h)) - (\(w0))")))
        }
        return FamilySolid(name: name, profile: .revolve(FamilyRevolve(profile: pts, axis: FamilyPoint(.expr(ax), .expr(ay)),
                                                                         startDegrees: num(f.startAngle * 180 / .pi), endDegrees: num(f.endAngle * 180 / .pi))),
                           zMin: .expr(w0), zMax: .expr(w0), isVoid: f.isVoid)
    }

    // MARK: Regeneration

    /// After the parts follow their planes: EQ rails take their share of the space between their bounds.
    static func regenerate(_ tx: TransactionContext, _ r: FurnitureBoundResolver) {
        for e in tx.model.elements(.furnitureRails) {
            guard let d = e.furnitureRail, let eq = d.eq, !eq.isEmpty else { continue }
            var el = e
            for key in eq.keys.sorted() {
                guard let q = eq[key], q.count > 0, let lo = r.resolve(q.low), let hi = r.resolve(q.high) else { continue }
                FurniturePartCoordinates.set(key, lo + (hi - lo) * Double(q.index) / Double(q.count), in: &el)
            }
            var b = FurniturePartBounds.bounds(of: el)
            for key in eq.keys { b[key] = nil }
            FurniturePartBounds.setBounds(b, of: &el)
            if el != e { let data = el.data; tx.propagate(e.id) { $0.data = data } }
        }
    }
}
