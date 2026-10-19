import Foundation
import ArcusGeometry

// FM9: forms that follow the piece's reference planes, as a Revit-style form whose sketch lines are locked to planes
// (padlocks) does. A form keeps its sketch as drawn, with the positions its planes had then; its solids are moved or
// stretched to the planes' current positions for display, and written as formulas of the planes when compiling, so a
// sofa's cushions, arms and back follow Width, Depth and Height in Flex and in projects.

/// How a form follows two planes along one axis.
public struct FormAxisLock: Hashable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        /// Moves with the low plane (Left, Front, Bottom): an arm against the left side.
        case low = "Low"
        /// Moves with the high plane (Right, Back, Top).
        case high = "High"
        /// Stretches between the planes keeping its corners: each point moves with the nearer end of the form, and the
        /// ends keep their share of the space between the planes (a cushion, a seat deck).
        case stretch = "Stretch"
        /// Scales every point between the planes (proportional, corners included).
        case scale = "Scale"
        /// Each end follows its own plane: the low half of the form moves with the low plane, the high half with the
        /// high plane (a back that runs from the seat to the Top).
        case span = "Span"
    }
    public var mode: Mode
    public var lowPlane: String
    public var highPlane: String
    /// The planes' positions when the form was drawn.
    public var low0: Double
    public var high0: Double
    public init(_ mode: Mode, low: String, high: String, low0: Double, high0: Double) {
        self.mode = mode; lowPlane = low; highPlane = high; self.low0 = low0; self.high0 = high0
    }
}

/// A form's locks along x, y and z (nil = it doesn't follow planes along that axis).
public struct FormLock: Hashable, Codable, Sendable {
    public var x: FormAxisLock?
    public var y: FormAxisLock?
    public var z: FormAxisLock?
    /// FMG1: a revolve's profile follows the lock too: its radii as points across the axis on x, its heights on z (a
    /// basket that grows with Width and Height). nil = only its axis and base follow.
    public var profile: Bool? = nil
    public init(x: FormAxisLock? = nil, y: FormAxisLock? = nil, z: FormAxisLock? = nil) { self.x = x; self.y = y; self.z = z }

    public subscript(_ a: FamilyAxis) -> FormAxisLock? {
        switch a { case .x: x; case .y: y; case .z: z }
    }

    /// Locks to the framing planes (Left/Right, Front/Back, Bottom/Top) at their positions in `m`.
    public static func framing(_ m: BIMModel, x: FormAxisLock.Mode? = nil, y: FormAxisLock.Mode? = nil, z: FormAxisLock.Mode? = nil) -> FormLock {
        let p = FurniturePlanes.positionsByName(m)
        func lock(_ mode: FormAxisLock.Mode?, _ lo: String, _ hi: String) -> FormAxisLock? {
            guard let mode, let a = p[lo], let b = p[hi], b - a > Tolerance.length else { return nil }
            return FormAxisLock(mode, low: lo, high: hi, low0: a, high0: b)
        }
        return FormLock(x: lock(x, "Left", "Right"), y: lock(y, "Front", "Back"), z: lock(z, "Bottom", "Top"))
    }
}

public enum FurnitureFormLocks {
    /// The form's solids moved to the planes' current positions (numbers), or written as formulas of the planes
    /// (compiling). Solids of a form without a lock are returned as they are.
    static func apply(_ lock: FormLock?, to solids: [FamilySolid], _ m: BIMModel, _ ctx: PartSolidContext) -> [FamilySolid] {
        guard let lock, lock.x != nil || lock.y != nil || lock.z != nil else { return solids }
        // The form's extent along each axis, as drawn.
        var lo: [FamilyAxis: Double] = [:], hi: [FamilyAxis: Double] = [:]
        let profile = lock.profile == true // FMG1
        for s in solids { visit(s, profile: profile) { axis, v in lo[axis] = min(lo[axis] ?? v, v); hi[axis] = max(hi[axis] ?? v, v) } }
        let positions = FurniturePlanes.positionsByName(m)
        let formulas = planeFormulas(m)
        func mapped(_ axis: FamilyAxis, _ v: Double) -> FamilyBound {
            guard let l = lock[axis], let a = lo[axis], let b = hi[axis] else { return .expr(PartSolidContext.number(v)) }
            let p0 = positions[l.lowPlane] ?? l.low0, p1 = positions[l.highPlane] ?? l.high0
            let span0 = l.high0 - l.low0
            let k = abs(span0) > Tolerance.length ? (p1 - p0) / span0 : 1
            if !ctx.symbolic {
                switch l.mode {
                case .low: return .expr(PartSolidContext.number(v + p0 - l.low0))
                case .high: return .expr(PartSolidContext.number(v + p1 - l.high0))
                case .scale: return .expr(PartSolidContext.number(p0 + (v - l.low0) * k))
                case .stretch:
                    let end = v <= (a + b) / 2 ? a : b
                    return .expr(PartSolidContext.number(p0 + (end - l.low0) * k + (v - end)))
                case .span:
                    return .expr(PartSolidContext.number(v <= (a + b) / 2 ? v + p0 - l.low0 : v + p1 - l.high0))
                }
            }
            let fl = formulas[l.lowPlane] ?? "\(num(l.low0)) m", fh = formulas[l.highPlane] ?? "\(num(l.high0)) m"
            func share(_ x: Double) -> String { num(abs(span0) > Tolerance.length ? (x - l.low0) / span0 : 0) }
            func term(_ d: Double) -> String { "\(d < 0 ? "-" : "+") \(num(abs(d))) m" }
            switch l.mode {
            case .low: return .expr("(\(fl)) \(term(v - l.low0))")
            case .high: return .expr("(\(fh)) \(term(v - l.high0))")
            case .scale: return .expr("(\(fl)) + ((\(fh)) - (\(fl))) * \(share(v))")
            case .stretch:
                let end = v <= (a + b) / 2 ? a : b
                return .expr("(\(fl)) + ((\(fh)) - (\(fl))) * \(share(end)) \(term(v - end))")
            case .span:
                return .expr(v <= (a + b) / 2 ? "(\(fl)) \(term(v - l.low0))" : "(\(fh)) \(term(v - l.high0))")
            }
        }
        return solids.map { map($0, profile: profile, mapped) }
    }

    /// The reference planes a locked form follows (its meshes change when they move).
    public static func inputs(of e: Element, _ m: BIMModel) -> Set<ElementID> {
        guard let lock = e.furnitureForm?.lock else { return [] }
        let names = Set([lock.x, lock.y, lock.z].compactMap { $0 }.flatMap { [$0.lowPlane, $0.highPlane] })
        return Set(FurniturePlanes.names(m).filter { names.contains($0.value) }.map(\.key))
    }

    /// Each plane's offset formula by name (planes without one are left out: their position is a number).
    static func planeFormulas(_ m: BIMModel) -> [String: String] {
        let names = FurniturePlanes.names(m)
        var out: [String: String] = [:]
        for p in FurniturePlanes.all(m) {
            guard let n = names[p.id], let f = p.referencePlane?.furniture?.offsetFormula?.trimmingCharacters(in: .whitespaces), !f.isEmpty else { continue }
            out[n] = f
        }
        return out
    }

    /// A number for a formula: fixed-point (formulas don't read exponents), to 1e-9.
    static func num(_ v: Double) -> String {
        guard v.isFinite, abs(v) >= 5e-10 else { return "0" }
        var s = String(format: "%.9f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func number(_ b: FamilyBound) -> Double? {
        if case .expr(let s) = b { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// The world axis of each coordinate a solid places (profiles measured from a path or an axis are skipped, except a
    /// revolve's when `profile` is set: FMG1).
    static func visit(_ s: FamilySolid, profile: Bool = false, _ f: (FamilyAxis, Double) -> Void) {
        let axes = (s.workPlane ?? .xy).axes
        func pt(_ p: FamilyPoint, _ u: FamilyAxis, _ v: FamilyAxis) { if let x = number(p.x) { f(u, x) }; if let y = number(p.y) { f(v, y) } }
        switch s.profile {
        case .rectangle(let x0, let x1, let y0, let y1):
            for b in [x0, x1] { if let v = number(b) { f(axes.u, v) } }
            for b in [y0, y1] { if let v = number(b) { f(axes.v, v) } }
        case .polygon(let pts): pts.forEach { pt($0, axes.u, axes.v) }
        case .circle(let c, _): pt(c, axes.u, axes.v)
        case .blend(let b): (b.bottom + b.top).forEach { pt($0, .x, .y) }
        case .revolve(let r):
            pt(r.axis, .x, .y)
            // FMG1: the profile's points across the axis (on x) and their heights.
            if profile, let ax = number(r.axis.x), let z0 = number(s.zMin) {
                for p in r.profile { if let x = number(p.x) { f(.x, ax + x) }; if let y = number(p.y) { f(.z, z0 + y) } }
            }
        case .sweep(let sw): sw.path.forEach { pt($0, axes.u, axes.v) } // FMG1: paths on any work plane
        }
        for b in [s.zMin, s.zMax] { if let v = number(b) { f(axes.w, v) } }
    }

    /// The solid with every placed coordinate mapped (FMG1: with a revolve's profile when `profile` is set).
    static func map(_ s: FamilySolid, profile: Bool = false, _ m: (FamilyAxis, Double) -> FamilyBound) -> FamilySolid {
        var out = s
        let axes = (s.workPlane ?? .xy).axes
        func b(_ x: FamilyBound, _ a: FamilyAxis) -> FamilyBound { number(x).map { m(a, $0) } ?? x }
        func pt(_ p: FamilyPoint, _ u: FamilyAxis, _ v: FamilyAxis) -> FamilyPoint { FamilyPoint(b(p.x, u), b(p.y, v)) }
        switch s.profile {
        case .rectangle(let x0, let x1, let y0, let y1):
            out.profile = .rectangle(xMin: b(x0, axes.u), xMax: b(x1, axes.u), yMin: b(y0, axes.v), yMax: b(y1, axes.v))
        case .polygon(let pts): out.profile = .polygon(pts.map { pt($0, axes.u, axes.v) })
        case .circle(let c, let r): out.profile = .circle(center: pt(c, axes.u, axes.v), radius: r)
        case .blend(let bl): out.profile = .blend(FamilyBlend(bottom: bl.bottom.map { pt($0, .x, .y) }, top: bl.top.map { pt($0, .x, .y) }))
        case .revolve(var r):
            // FMG1: each profile point maps as the point it places (radius across the axis, height above the base), less
            // the mapped axis and base.
            if profile, let ax = number(r.axis.x), let z0 = number(s.zMin) {
                let axis = b(r.axis.x, .x), base = b(s.zMin, .z)
                func diff(_ a: FamilyBound, _ c: FamilyBound) -> FamilyBound {
                    if let x = number(a), let y = number(c) { return .expr(PartSolidContext.number(x - y)) }
                    return .expr("(\(expression(a))) - (\(expression(c)))")
                }
                r.profile = r.profile.map { p in
                    guard let x = number(p.x), let y = number(p.y) else { return p }
                    return FamilyPoint(diff(m(.x, ax + x), axis), diff(m(.z, z0 + y), base))
                }
            }
            r.axis = pt(r.axis, .x, .y); out.profile = .revolve(r)
        case .sweep(var sw): sw.path = sw.path.map { pt($0, axes.u, axes.v) }; out.profile = .sweep(sw) // FMG1: any work plane
        }
        out.zMin = b(s.zMin, axes.w)
        out.zMax = b(s.zMax, axes.w)
        return out
    }

    /// FMG1: a bound as a length expression (formulas as written, numbers in metres).
    static func expression(_ b: FamilyBound) -> String {
        switch b {
        case .expr(let e): Double(e.trimmingCharacters(in: .whitespaces)).map { "\(num($0)) m" } ?? e
        case .plane(let n): n
        }
    }
}
