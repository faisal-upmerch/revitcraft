import Foundation
import ArcusGeometry

// FM4: every part as family solids. The same description serves the display (numbers: the part's current geometry,
// evaluated by `FamilyEvaluator` into meshes) and Load into Project (bounds name the reference planes the part follows,
// so the compiled family flexes like the document). Shapes that aren't plane-bounded boxes (round and turned legs,
// hairpins, edge profiles) are local families placed at a bound point, nested when compiling.

/// A coordinate of a part and the plane it follows.
public struct PartValue: Hashable, Sendable {
    public var value: Double
    /// The reference plane (or helper plane) the coordinate follows, and its offset from it.
    public var plane: String?
    public var offset: Double

    /// FMG1: the coordinate as a length formula of the piece's parameters, when it follows planes in a way a single plane
    /// can't express (an angled part's corner, an EQ slat, a revolve's profile point). Compiling writes it as an
    /// expression; nil = the plane and offset above.
    public var formula: String? = nil

    public init(_ value: Double, plane: String? = nil, offset: Double = 0) { self.value = value; self.plane = plane; self.offset = offset }

    /// The coordinate of `bound` at `value` (bounds to a fixed value don't follow a plane).
    public init(_ value: Double, _ bound: FurnitureBound?) {
        self.value = value
        if case .plane(let n, let o)? = bound { plane = n; offset = o } else { plane = nil; offset = 0 }
    }

    /// FMG1: a coordinate given by a formula (and its value now).
    public init(_ value: Double, formula: String?) { self.value = value; plane = nil; offset = 0; self.formula = formula }

    public func shifted(_ d: Double) -> PartValue {
        var p = PartValue(value + d, plane: plane, offset: offset + d)
        p.formula = formula.map { abs(d) < 1e-12 ? $0 : "(\($0)) \(FurnitureCompiler.lengthTerm(d))" } // FMG1
        return p
    }
}

/// How solids are written: with numbers (display) or bound to planes (compile). Collects the helper planes a compile
/// needs: a plane at a fixed distance from a named plane (kept there by a locked dimension, as in a family).
public final class PartSolidContext {
    public let symbolic: Bool
    /// Helper plane name → (the plane it follows, its offset).
    public private(set) var helpers: [String: (plane: String, offset: Double)] = [:]
    /// Planes that may be named directly (the document's furniture planes and the compile's own planes).
    public var knownPlanes: Set<String>

    /// FMG1: each plane's position as a length formula of the parameters (planes that never move as a number), set by
    /// the compiler; nil = coordinates are written only as planes and offsets (display, joints).
    public var planeFormulas: [String: String]?
    /// FMG1: parameters the parts need in the compiled family (slat counts and their visibility).
    public internal(set) var parameters: [FamilyParameter] = []

    public init(symbolic: Bool, knownPlanes: Set<String> = []) { self.symbolic = symbolic; self.knownPlanes = knownPlanes }
    /// FMG3: the frame of the bay whose front is being written (boxes and prisms are given in it); nil = the model's.
    public var frame: BayFrame?
    /// FMG3: a plane's offset formula in the family being compiled, for coordinates that follow a sum of planes (a
    /// canted face's): written as formulas.
    public var planeFormula: ((String) -> String?)?
    /// FMG3: compiling a canted front: its face's front corners (see CantAnchors).
    public var cantAnchors: CantAnchors?

    /// FMG1: a coordinate as a length formula, when compiling with plane formulas and its plane has one.
    public func formula(_ v: PartValue) -> String? {
        guard symbolic, let formulas = planeFormulas else { return nil }
        if let f = v.formula { return f }
        guard let p = v.plane else { return "\(FurnitureFormLocks.num(v.value)) m" }
        guard let f = formulas[p] else { return nil }
        return abs(v.offset) < 1e-12 ? "(\(f))" : "(\(f)) \(FurnitureCompiler.lengthTerm(v.offset))"
    }

    /// FMG1: adds a parameter the compiled family needs (once per name).
    func addParameter(_ p: FamilyParameter) { if !parameters.contains(where: { $0.name == p.name }) { parameters.append(p) } }

    static func number(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let r = (v * 1e9).rounded() / 1e9
        return r == 0 ? "0" : String(r)
    }

    /// The family bound of a coordinate.
    public func bound(_ v: PartValue) -> FamilyBound {
        if symbolic, let f = v.formula { return .expr(f) } // FMG1
        if symbolic, PlaneTerms.isSum(v.plane), let p = v.plane, let f = planeFormula, let e = PlaneTerms.expression(p, offset: v.offset, f) { return .expr(e) } // FMG3
        guard symbolic, let p = v.plane, knownPlanes.contains(p) else { return .expr(Self.number(v.value)) }
        if abs(v.offset) < 1e-7 { return .plane(p) }
        let o = (v.offset * 1e6).rounded() / 1e6
        let name = "\(p) \(o >= 0 ? "+" : "-") \(String(format: "%.6f", abs(o)))"
        if helpers[name] == nil { helpers[name] = (p, o) }
        return .plane(name)
    }

    public func expr(_ v: Double) -> FamilyBound { .expr(Self.number(v)) }
    func point(_ x: PartValue, _ y: PartValue) -> FamilyPoint { FamilyPoint(bound(x), bound(y)) }
    func point(_ p: Vec2) -> FamilyPoint { FamilyPoint(expr(p.x), expr(p.y)) }
}

/// A local shape placed in the document: evaluated in place for display, nested when compiling.
public struct PlacedLocalFamily: Sendable {
    public var family: FamilyDefinition
    public var x: PartValue
    public var y: PartValue
    public var z: PartValue
    /// Degrees about Z.
    public var rotation: Double
    public var mirrored: Bool
    /// The local family's length parameter ("Length") and its span in the document, when it has one.
    public var span: (start: PartValue, end: PartValue)?
    public var material: ElementID?
}

/// A part's solids: direct solids and placed local families.
public struct PartSolids: Sendable {
    public var solids: [FamilySolid] = []
    public var placed: [PlacedLocalFamily] = []
    /// Material per solid id (display).
    public var materials: [String: ElementID] = [:]
    public init() {}
}

public enum FurniturePartSolids {
    static let inch = 0.0254

    // MARK: Values

    static func pv(_ e: Element, _ value: Double, _ key: String) -> PartValue {
        PartValue(value, FurniturePartBounds.bounds(of: e)[key])
    }

    /// The part's solids (none for elements that aren't parts), with its joints applied (FM6: trims, miters, and the
    /// tongues, tenons, grooves and mortises shown at Fine).
    public static func solids(_ e: Element, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        FurnitureJoints.applyJoints(rawSolids(e, m, ctx), e, m, ctx) // FM6
    }

    /// The part's solids as drawn, before joints.
    static func rawSolids(_ e: Element, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        switch e.data {
        case .furniturePanel(let p): return panel(e, p, m, ctx)
        case .furnitureShelf(let s): return shelf(e, s, m, ctx)
        case .furnitureLeg(let l): return leg(e, l, m, ctx)
        case .furnitureRail(let r): return rail(e, r, m, ctx)
        case .furnitureEdgeProfile: return edgeProfile(e, m, ctx)
        case .furnitureForm(let f): return FurnitureForms.solids(e, f, m, ctx)
        default: return PartSolids()
        }
    }

    // MARK: Panels

    /// Offsets of a panel's two faces from its location line, across it (toward its left in sketch coordinates):
    /// (outside face, inside face).
    public static func faceOffsets(_ p: PanelData, thickness t: Double) -> (outside: Double, inside: Double) {
        let (o, i): (Double, Double)
        switch p.locationLine {
        case .centerline: (o, i) = (t / 2, -t / 2)
        case .faceOutside: (o, i) = (0, -t)
        case .faceInside: (o, i) = (t, 0)
        }
        return p.flipped ? (-o, -i) : (o, i)
    }

    /// The world axes of a linear part's line, its cross direction and its extrusion, when the line runs along an axis.
    /// `along` is +1 when the line runs toward +axis; `across` is the sign of the left normal on the cross axis.
    public struct LinearFrame: Sendable {
        public var plane: FamilySketchPlane
        public var lineAxis: FamilyAxis
        public var crossAxis: FamilyAxis
        public var along: Double
        public var across: Double
        public var lineAlongU: Bool
    }

    public static func linearFrame(_ plane: FamilySketchPlane, _ s: Vec2, _ e: Vec2) -> LinearFrame? {
        let d = e - s
        guard d.length > Tolerance.length else { return nil }
        let a = plane.axes
        if abs(d.y) <= 1e-7 * max(1, d.length) {
            let along: Double = d.x > 0 ? 1 : -1
            return LinearFrame(plane: plane, lineAxis: a.u, crossAxis: a.v, along: along, across: along, lineAlongU: true)
        }
        if abs(d.x) <= 1e-7 * max(1, d.length) {
            let along: Double = d.y > 0 ? 1 : -1
            // Left normal of (0, ±1) is (∓1, 0).
            return LinearFrame(plane: plane, lineAxis: a.v, crossAxis: a.u, along: along, across: -along, lineAlongU: false)
        }
        return nil
    }

    static func range(_ a: PartValue, _ b: PartValue) -> (PartValue, PartValue) { a.value <= b.value ? (a, b) : (b, a) }

    /// A box on `plane`: rectangle (u, v) extruded along the plane's normal (w).
    static func box(_ name: String, plane: FamilySketchPlane, u: (PartValue, PartValue), v: (PartValue, PartValue), w: (PartValue, PartValue),
                    _ ctx: PartSolidContext, void isVoid: Bool = false) -> FamilySolid {
        if let fr = ctx.frame, !fr.isIdentity { // FMG3: a front on a turned face, given in its bay's frame
            var c: [FamilyAxis: (PartValue, PartValue)] = [:]
            c[plane.axes.u] = u; c[plane.axes.v] = v; c[plane.axes.w] = w
            return fr.solid(name, x: c[.x] ?? u, y: c[.y] ?? v, z: c[.z] ?? w, ctx, void: isVoid)
        }
        let (u0, u1) = range(u.0, u.1), (v0, v1) = range(v.0, v.1), (w0, w1) = range(w.0, w.1)
        var s = FamilySolid(name: name, profile: .rectangle(xMin: ctx.bound(u0), xMax: ctx.bound(u1), yMin: ctx.bound(v0), yMax: ctx.bound(v1)),
                            zMin: ctx.bound(w0), zMax: ctx.bound(w1), materialParameter: nil, isVoid: isVoid)
        if plane != .xy { s.workPlane = plane }
        return s
    }

    /// A polygon on `plane` (numbers) extruded along its normal.
    static func prism(_ name: String, plane: FamilySketchPlane, _ pts: [Vec2], w: (PartValue, PartValue), _ ctx: PartSolidContext, void isVoid: Bool = false) -> FamilySolid {
        if let fr = ctx.frame, !fr.isIdentity { return fr.prism(name, plane: plane, pts, w: w, ctx, void: isVoid) } // FMG3
        let (w0, w1) = range(w.0, w.1)
        let poly = Polygon2(pts).counterClockwise
        var s = FamilySolid(name: name, profile: .polygon(poly.points.map(ctx.point)), zMin: ctx.bound(w0), zMax: ctx.bound(w1), isVoid: isVoid)
        if plane != .xy { s.workPlane = plane }
        return s
    }

    /// World coordinate values on each axis → the sketch (u, v) of `plane`.
    static func uv(_ plane: FamilySketchPlane, _ c: [FamilyAxis: Double]) -> Vec2 { Vec2(c[plane.axes.u] ?? 0, c[plane.axes.v] ?? 0) }

    static func panel(_ e: Element, _ p: PanelData, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        let tv = FurniturePartTypes.values(of: e, m)
        let t = tv.thickness
        let (fo, fi) = faceOffsets(p, thickness: t)
        let w = (attachedValue(e, m, "base", p.base), attachedValue(e, m, "top", p.top)) // FM8: attached ends follow their shelf
        guard p.top - p.base > Tolerance.length, p.length > Tolerance.length, t > Tolerance.length else { return out }
        let name = e.mark.isEmpty ? "Panel" : e.mark
        let su = pv(e, p.start.x, "start.u"), sv = pv(e, p.start.y, "start.v"), eu = pv(e, p.end.x, "end.u"), ev = pv(e, p.end.y, "end.v")
        let openings = p.openings ?? []
        if let f = linearFrame(p.plane, p.start, p.end) {
            let across0 = (f.lineAlongU ? sv : su).shifted(f.across * fo), across1 = (f.lineAlongU ? sv : su).shifted(f.across * fi)
            let along = f.lineAlongU ? (su, eu) : (sv, ev)
            if p.profile == nil && openings.isEmpty {
                let s = f.lineAlongU ? box(name, plane: p.plane, u: along, v: (across0, across1), w: w, ctx)
                                     : box(name, plane: p.plane, u: (across0, across1), v: along, w: w, ctx)
                out.solids.append(s)
            } else {
                // Edit Profile and Openings: the face outline, extruded through the thickness.
                let face = FamilySketchPlane.normal(f.crossAxis)
                let wAxis = p.plane.axes.w
                func world(_ st: Vec2) -> Vec2 {
                    uv(face, [f.lineAxis: p.start.x * (f.lineAlongU ? 1 : 0) + p.start.y * (f.lineAlongU ? 0 : 1) + st.x * f.along, wAxis: p.base + st.y])
                }
                let outline = p.profile ?? [Vec2(0, 0), Vec2(p.length, 0), Vec2(p.length, p.height), Vec2(0, p.height)]
                out.solids.append(prism(name, plane: face, outline.map(world), w: (across0, across1), ctx))
                for (k, o) in openings.enumerated() {
                    let pts = [Vec2(o.s0, o.t0), Vec2(o.s1, o.t0), Vec2(o.s1, o.t1), Vec2(o.s0, o.t1)].map(world)
                    let margin = 0.001
                    let lo = min(across0.value, across1.value) - margin, hi = max(across0.value, across1.value) + margin
                    out.solids.append(prism("\(name) Opening \(k + 1)", plane: face, pts, w: (PartValue(lo), PartValue(hi)), ctx, void: true))
                }
            }
        } else {
            // A line at an angle: the outline in the sketch plane. FMG1: its corners follow the planes its ends follow.
            let ends = FurniturePartFlex.LineEnds(su: su, sv: sv, eu: eu, ev: ev)
            out.solids.append(FurniturePartFlex.prism(name, plane: p.plane, FurniturePartFlex.outline(ends, a: fo, b: fi, ctx), w: w, ctx))
        }
        for s in out.solids where !s.isVoid { out.materials[s.id] = tv.material }
        return out
    }

    // MARK: Shelves

    static func shelf(_ e: Element, _ s: ShelfData, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        let tv = FurniturePartTypes.values(of: e, m)
        guard s.boundary.count >= 3, tv.thickness > Tolerance.length else { return out }
        let b = FurniturePartBounds.bounds(of: e)
        let pts = s.boundary.enumerated().map { i, p in FamilyPoint(ctx.bound(PartValue(p.x, b["p\(i).x"])), ctx.bound(PartValue(p.y, b["p\(i).y"]))) }
        let top = PartValue(s.elevation, b["z"])
        var solid = FamilySolid(name: e.mark.isEmpty ? s.role.rawValue : e.mark, profile: .polygon(pts), zMin: ctx.bound(top.shifted(-tv.thickness)), zMax: ctx.bound(top))
        if Polygon2(s.boundary).signedArea < 0 { solid.profile = .polygon(pts.reversed()) }
        out.solids.append(solid)
        out.materials[solid.id] = tv.material
        // A top's edge shape runs round its top edges (rectangular tops).
        if s.role == .top, tv.topEdge != .square, let host = partBox(e, m) {
            let shape: EdgeProfileShape = switch tv.topEdge { case .roundOver: .roundOver; case .chamfer: .chamfer; case .bullnose: .bullnose; case .ogee: .ogee; case .square: .roundOver }
            let size = tv.topEdge == .bullnose ? tv.thickness : min(tv.thickness * 0.6, 0.5 * inch)
            for edge in [PartEdge(axis: .x, firstAtMax: false, secondAtMax: true), PartEdge(axis: .x, firstAtMax: true, secondAtMax: true),
                         PartEdge(axis: .y, firstAtMax: false, secondAtMax: true), PartEdge(axis: .y, firstAtMax: true, secondAtMax: true)] {
                if let v = edgeVoid(name: "Top Edge", host: host, edge: edge, shape: shape, size: size, depth: 0, offset: 0, inSecondFace: false, ctx: ctx) {
                    out.placed.append(v)
                }
            }
        }
        return out
    }

    // MARK: Rails

    /// A rail's cross offsets (in-plane, across its line) and its extent across the sketch plane.
    static func railSection(_ r: RailData, width W: Double, height H: Double) -> (a: Double, b: Double, w0: Double, w1: Double) {
        // FMG1: y Justification puts the section to the left or right of the line in its sketch.
        func across(_ size: Double) -> (Double, Double) {
            switch r.yJustification ?? .center { case .left: (0, size); case .center: (-size / 2, size / 2); case .right: (-size, 0) }
        }
        if r.plane == .xy {
            let (z0, z1): (Double, Double) = switch r.justification { case .top: (r.w - H, r.w); case .center: (r.w - H / 2, r.w + H / 2); case .bottom: (r.w, r.w + H) }
            let (a, b) = across(W)
            return (a, b, z0, z1)
        }
        // Drawn in an elevation: Z justification applies to lines that run across the view (horizontal).
        let d = r.end - r.start
        let horizontal = abs(d.y) <= 1e-7 * max(1, d.length)
        var (a, b) = across(H)
        if horizontal {
            // The left normal of a horizontal line points up (+v) when it runs toward +u.
            let up: Double = d.x > 0 ? 1 : -1
            switch r.justification {
            case .top: (a, b) = up > 0 ? (-H, 0) : (0, H)
            case .bottom: (a, b) = up > 0 ? (0, H) : (-H, 0)
            case .center: break
            }
        }
        return (a, b, r.w - W / 2, r.w + W / 2)
    }

    static func rail(_ e: Element, _ r: RailData, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        let tv = FurniturePartTypes.values(of: e, m)
        let W = tv.width, H = tv.depth
        guard r.start.distance(to: r.end) > Tolerance.length, W > Tolerance.length, H > Tolerance.length else { return out }
        let sec = railSection(r, width: W, height: H)
        let base = e.mark.isEmpty ? "Rail" : e.mark
        let slats = FurniturePartFlex.slats(e, r, ctx) // FMG1: slats laid out between the first line and the far side
        func rv(_ key: String, _ v: Double) -> PartValue { FurniturePartFlex.railValue(e, r, key, v, ctx) } // FMG1: EQ coordinates
        let wb = rv("w", r.w)
        let wv = (wb.shiftedTo(sec.w0, from: r.w), wb.shiftedTo(sec.w1, from: r.w))
        let su = rv("start.u", r.start.x), sv = rv("start.v", r.start.y), eu = rv("end.u", r.end.x), ev = rv("end.v", r.end.y)
        for (k, slat) in slats.enumerated() {
            let off = slat.offset
            let name = slats.count == 1 ? base : "\(base) Slat \(k + 1)"
            let before = out.solids.count
            defer { for i in before..<out.solids.count { out.solids[i].visibilityParameter = slat.visibility } }
            if let f = linearFrame(r.plane, r.start, r.end) {
                var acrossBase = (f.lineAlongU ? sv : su).shifted(f.across * off)
                if let a = slat.across { acrossBase.formula = a }
                let along = f.lineAlongU ? (su.shifted(-f.along * r.startExtension), eu.shifted(f.along * r.endExtension))
                                         : (sv.shifted(-f.along * r.startExtension), ev.shifted(f.along * r.endExtension))
                if tv.railProfile == .round {
                    // A round rail: a circle on the plane across its line, extruded along it.
                    let cross = FamilySketchPlane.normal(f.lineAxis)
                    let mid = (sec.a + sec.b) / 2
                    let cAcross = acrossBase.shifted(f.across * mid), cW = wb.shiftedTo((sec.w0 + sec.w1) / 2, from: r.w)
                    let cu = cross.axes.u == f.crossAxis ? cAcross : cW, cvv = cross.axes.u == f.crossAxis ? cW : cAcross
                    var s = FamilySolid(name: name, profile: .circle(center: ctx.point(cu, cvv), radius: PartSolidContext.number(W / 2)),
                                        zMin: ctx.bound(range(along.0, along.1).0), zMax: ctx.bound(range(along.0, along.1).1))
                    s.workPlane = cross == .xy ? nil : cross
                    out.solids.append(s)
                } else {
                    let a0 = acrossBase.shifted(f.across * sec.a), a1 = acrossBase.shifted(f.across * sec.b)
                    out.solids.append(f.lineAlongU ? box(name, plane: r.plane, u: along, v: (a0, a1), w: wv, ctx)
                                                   : box(name, plane: r.plane, u: (a0, a1), v: along, w: wv, ctx))
                }
            } else {
                // FMG1: a rail at an angle follows the planes its ends follow, cut square, level or plumb at each end.
                let ends = FurniturePartFlex.LineEnds(su: su, sv: sv, eu: eu, ev: ev)
                let cuts = r.plane == .xy ? (RailEndCut.perpendicular, RailEndCut.perpendicular) : (r.startCut ?? .perpendicular, r.endCut ?? .perpendicular)
                let pts = FurniturePartFlex.outline(ends, a: off + sec.a, b: off + sec.b, extensions: (r.startExtension, r.endExtension), cuts: cuts, ctx)
                out.solids.append(FurniturePartFlex.prism(name, plane: r.plane, pts, w: wv, ctx))
            }
        }
        for s in out.solids { out.materials[s.id] = tv.material }
        return out
    }

    // MARK: Legs

    static func leg(_ e: Element, _ l: LegData, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        let tv = FurniturePartTypes.values(of: e, m)
        guard l.height > Tolerance.length else { return out }
        let x = pv(e, l.location.x, "x"), y = pv(e, l.location.y, "y"), z0 = pv(e, l.base, "base"), z1 = attachedValue(e, m, "top", l.top) // FM8
        let w = tv.width, d = tv.depth
        // A square, untapered leg square to the piece is a box on the planes; every other shape is a local family.
        if tv.legShape == .square, tv.taper <= Tolerance.length, abs(Angle.normalize(l.rotation).truncatingRemainder(dividingBy: .pi / 2)) < 1e-9 {
            let quarter = abs((l.rotation / (.pi / 2)).rounded()).truncatingRemainder(dividingBy: 2) == 1
            let (hw, hd) = quarter ? (d / 2, w / 2) : (w / 2, d / 2)
            let s = box(e.mark.isEmpty ? "Leg" : e.mark, plane: .xy, u: (x.shifted(-hw), x.shifted(hw)), v: (y.shifted(-hd), y.shifted(hd)), w: (z0, z1), ctx)
            out.solids.append(s)
            out.materials[s.id] = tv.material
            return out
        }
        let fam = FurnitureLegShapes.family(tv, height: l.height)
        out.placed.append(PlacedLocalFamily(family: fam, x: x, y: y, z: z0, rotation: l.rotation * 180 / .pi, mirrored: false, span: (z0, z1), material: tv.material))
        return out
    }

    // MARK: Edge profiles

    /// The axis-aligned box of a part (panels, rectangular shelves and rails, square legs): min and max per axis.
    public struct PartBox: Sendable {
        public var x: (PartValue, PartValue)
        public var y: (PartValue, PartValue)
        public var z: (PartValue, PartValue)
        func range(_ a: FamilyAxis) -> (PartValue, PartValue) { switch a { case .x: x; case .y: y; case .z: z } }
        public var box: Box3 { Box3(min: Vec3(x.0.value, y.0.value, z.0.value), max: Vec3(x.1.value, y.1.value, z.1.value)) }
    }

    /// The part's box with the planes its faces follow, when the part is a single axis-aligned box.
    public static func partBox(_ e: Element, _ m: BIMModel) -> PartBox? {
        if case .furnitureShelf(let s) = e.data {
            guard s.boundary.count == 4 else { return nil }
            let r = Rect2(points: s.boundary)
            func on(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-7 }
            guard s.boundary.allSatisfy({ on($0.x, r.min.x) || on($0.x, r.max.x) }), s.boundary.allSatisfy({ on($0.y, r.min.y) || on($0.y, r.max.y) }) else { return nil }
            let b = FurniturePartBounds.bounds(of: e)
            func corner(_ cond: (Vec2) -> Bool, _ key: String) -> PartValue? {
                guard let i = s.boundary.firstIndex(where: cond) else { return nil }
                return PartValue(key == "x" ? s.boundary[i].x : s.boundary[i].y, b["p\(i).\(key)"])
            }
            let t = FurniturePartTypes.values(of: e, m).thickness
            guard let x0 = corner({ on($0.x, r.min.x) }, "x"), let x1 = corner({ on($0.x, r.max.x) }, "x"),
                  let y0 = corner({ on($0.y, r.min.y) }, "y"), let y1 = corner({ on($0.y, r.max.y) }, "y") else { return nil }
            let top = PartValue(s.elevation, b["z"])
            return PartBox(x: (x0, x1), y: (y0, y1), z: (top.shifted(-t), top))
        }
        // The single box solid, written once with numbers and once with planes: together they give each face's value
        // and the plane it follows.
        let num = rawSolids(e, m, PartSolidContext(symbolic: false)) // FM6: the box as drawn (joints are solved from it)
        let sym = PartSolidContext(symbolic: true, knownPlanes: Set(FurniturePlanes.positionsByName(m).keys))
        let bound = rawSolids(e, m, sym)
        let a = num.solids.filter { !$0.isVoid }, b = bound.solids.filter { !$0.isVoid }
        guard a.count == 1, b.count == 1, num.placed.isEmpty, case .rectangle(let nx0, let nx1, let ny0, let ny1) = a[0].profile,
              case .rectangle(let bx0, let bx1, let by0, let by1) = b[0].profile else { return nil }
        func value(_ numeric: FamilyBound, _ fb: FamilyBound) -> PartValue {
            let v: Double = { if case .expr(let x) = numeric { return Double(x) ?? 0 }; return 0 }()
            guard case .plane(let n) = fb else { return PartValue(v) }
            if let h = sym.helpers[n] { return PartValue(v, plane: h.plane, offset: h.offset) }
            return PartValue(v, plane: n, offset: 0)
        }
        let plane = a[0].workPlane ?? .xy
        var r: [FamilyAxis: (PartValue, PartValue)] = [:]
        r[plane.axes.u] = (value(nx0, bx0), value(nx1, bx1))
        r[plane.axes.v] = (value(ny0, by0), value(ny1, by1))
        r[plane.axes.w] = (value(a[0].zMin, b[0].zMin), value(a[0].zMax, b[0].zMax))
        guard let rx = r[.x], let ry = r[.y], let rz = r[.z] else { return nil }
        return PartBox(x: rx, y: ry, z: rz)
    }

    static func edgeProfile(_ e: Element, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        guard let ep = e.furnitureEdgeProfile, let host = m[e.hostID], let hb = partBox(host, m) else { return out }
        let tv = FurniturePartTypes.values(of: e, m)
        if let v = edgeVoid(name: e.mark.isEmpty ? tv.profileShape.rawValue : e.mark, host: hb, edge: ep.edge, shape: tv.profileShape, size: tv.size,
                            depth: tv.grooveDepth, offset: ep.offset, inSecondFace: ep.inSecondFace, ctx: ctx, setbacks: (ep.startSetback, ep.endSetback)) {
            out.placed.append(v)
        }
        return out
    }

    /// The void along a box edge: a local family (corner at its origin, the edge along local X) placed at the corner.
    static func edgeVoid(name: String, host: PartBox, edge: PartEdge, shape: EdgeProfileShape, size: Double, depth: Double, offset: Double,
                         inSecondFace: Bool, ctx: PartSolidContext, setbacks: (Double, Double) = (0, 0)) -> PlacedLocalFamily? {
        let (a1, a2) = edge.across
        let r1 = host.range(a1), r2 = host.range(a2), ra = host.range(edge.axis)
        let c1 = edge.firstAtMax ? r1.1 : r1.0, c2 = edge.secondAtMax ? r2.1 : r2.0
        let s1: Double = edge.firstAtMax ? -1 : 1, s2: Double = edge.secondAtMax ? -1 : 1
        let t1 = r1.1.value - r1.0.value, t2 = r2.1.value - r2.0.value
        let len = ra.1.value - ra.0.value - setbacks.0 - setbacks.1
        guard len > Tolerance.length, size > Tolerance.length else { return nil }
        // Inward profile (a along a1 from the corner, b along a2), material at a, b ≥ 0.
        let inward = EdgeProfileShapes.voidProfile(shape, size: size, depth: depth, offset: offset, inSecondFace: inSecondFace, thickness1: t1, thickness2: t2)
        guard inward.count >= 3 else { return nil }
        let fam = EdgeProfileShapes.family(name: name, edgeAxis: edge.axis, signs: (s1, s2), profile: inward, length: len)
        // The local family's origin is the corner, at the edge's low end.
        var origin: [FamilyAxis: PartValue] = [a1: c1, a2: c2]
        origin[edge.axis] = ra.0.shifted(setbacks.0)
        guard let ox = origin[.x], let oy = origin[.y], let oz = origin[.z] else { return nil }
        return PlacedLocalFamily(family: fam, x: ox, y: oy, z: oz, rotation: 0, mirrored: false,
                                 span: (ra.0.shifted(setbacks.0), ra.1.shifted(-setbacks.1)), material: nil)
    }
}

extension PartValue {
    /// A coordinate `to` derived from a bound coordinate at `from` (shifts the offset by the difference).
    func shiftedTo(_ to: Double, from: Double) -> PartValue { var p = shifted(to - from); p.value = to; return p } // FMG1: keeps a formula
}

// MARK: - Bounds access

/// The plane bindings of any part.
public enum FurniturePartBounds {
    public static func bounds(of e: Element) -> [String: FurnitureBound] {
        switch e.data {
        case .furniturePanel(let p): p.bounds
        case .furnitureShelf(let s): s.bounds
        case .furnitureLeg(let l): l.bounds
        case .furnitureRail(let r): r.bounds
        case .furnitureForm(let f): f.bounds ?? [:] // FMG1: revolves locked to planes
        default: [:]
        }
    }

    public static func setBounds(_ b: [String: FurnitureBound], of e: inout Element) {
        switch e.data {
        case .furniturePanel(var p): p.bounds = b; e.data = .furniturePanel(p)
        case .furnitureShelf(var s): s.bounds = b; e.data = .furnitureShelf(s)
        case .furnitureLeg(var l): l.bounds = b; e.data = .furnitureLeg(l)
        case .furnitureRail(var r): r.bounds = b; e.data = .furnitureRail(r)
        case .furnitureForm(var f): f.bounds = b.isEmpty ? nil : b; e.data = .furnitureForm(f) // FMG1
        default: break
        }
    }
}
