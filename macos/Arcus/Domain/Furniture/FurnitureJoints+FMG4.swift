import Foundation
import ArcusGeometry
import ArcusCalc

// FMG4: joints keep the formulas a part's faces follow in a compiled family. The joint solver works on the document's
// boxes (each face a plane and an offset), so a part whose faces follow formulas there (FMG1: the slats of a Slats part
// spread between their first slat and far side, EQ rails, angled parts) lost them when its joints reshaped it: the
// slats stayed at their document offsets from the first plane while the piece flexed. Faces of the reshaped boxes, and
// of the tenons and mortises cut round them, are bound back to those formulas.

/// The faces of a part's solids that follow formulas (compiling): per solid, its range on each axis now, and the
/// formula of each end when it has one.
struct FormulaFaces: Sendable {
    struct Face: Sendable {
        var lo: Double, hi: Double
        var loFormula: String?, hiFormula: String?
    }
    /// Per solid: axis → face range.
    var solids: [[FamilyAxis: Face]] = []

    var isEmpty: Bool { solids.isEmpty }

    /// The formula faces of `raw` (written with `ctx`), measured against the same solids written with numbers.
    init(_ raw: PartSolids, _ e: Element, _ m: BIMModel, _ ctx: PartSolidContext) {
        guard ctx.symbolic, ctx.planeFormulas != nil, ctx.frame?.isIdentity ?? true else { return }
        let symbolic = raw.solids.filter { !$0.isVoid }
        guard symbolic.contains(where: Self.hasFormula) else { return }
        let numeric = Dictionary(FurniturePartSolids.rawSolids(e, m, PartSolidContext(symbolic: false)).solids.filter { !$0.isVoid }.map { ($0.name, $0) },
                                 uniquingKeysWith: { a, _ in a })
        for s in symbolic {
            guard let n = numeric[s.name], let faces = Self.faces(s, n) else { continue }
            solids.append(faces)
        }
    }

    static func hasFormula(_ s: FamilySolid) -> Bool {
        guard case .rectangle(let a, let b, let c, let d) = s.profile else { return false }
        return [a, b, c, d, s.zMin, s.zMax].contains { if case .expr(let f) = $0 { return Double(f) == nil } else { return false } }
    }

    /// A box solid's faces per model axis: numbers from `n`, formulas from `s`.
    static func faces(_ s: FamilySolid, _ n: FamilySolid) -> [FamilyAxis: Face]? {
        guard case .rectangle(let x0, let x1, let y0, let y1) = s.profile, case .rectangle(let nx0, let nx1, let ny0, let ny1) = n.profile,
              let a = value(nx0), let b = value(nx1), let c = value(ny0), let d = value(ny1), let e = value(n.zMin), let f = value(n.zMax) else { return nil }
        let axes = (s.workPlane ?? .xy).axes
        func formula(_ b: FamilyBound) -> String? { if case .expr(let f) = b, Double(f) == nil { return f } else { return nil } }
        var out: [FamilyAxis: Face] = [:]
        out[axes.u] = Face(lo: min(a, b), hi: max(a, b), loFormula: formula(a <= b ? x0 : x1), hiFormula: formula(a <= b ? x1 : x0))
        out[axes.v] = Face(lo: min(c, d), hi: max(c, d), loFormula: formula(c <= d ? y0 : y1), hiFormula: formula(c <= d ? y1 : y0))
        out[axes.w] = Face(lo: min(e, f), hi: max(e, f), loFormula: formula(e <= f ? s.zMin : s.zMax), hiFormula: formula(e <= f ? s.zMax : s.zMin))
        return out
    }

    static func value(_ b: FamilyBound) -> Double? { if case .expr(let f) = b { return Double(f) } else { return nil } }

    /// A coordinate on `axis` bound to the formula it lies on: a solid's face formula when it is that face, or the
    /// formula of the face below it plus the distance when it lies inside a solid whose other two ranges `box` overlaps.
    func rebind(_ v: PartValue, _ axis: FamilyAxis, near box: JBox? = nil) -> PartValue {
        guard v.formula == nil else { return v }
        let eps = 1e-7
        for s in solids {
            guard let f = s[axis] else { continue }
            if let lf = f.loFormula, abs(v.value - f.lo) < eps { return PartValue(v.value, formula: lf) }
            if let hf = f.hiFormula, abs(v.value - f.hi) < eps { return PartValue(v.value, formula: hf) }
        }
        guard let box else { return v }
        for s in solids {
            guard let f = s[axis], let lf = f.loFormula, v.value > f.lo - eps, v.value < f.hi + eps, Self.near(box, s, except: axis) else { continue }
            let d = v.value - f.lo
            return PartValue(v.value, formula: abs(d) < 1e-12 ? lf : "(\(lf)) \(FurnitureCompiler.lengthTerm(d))")
        }
        return v
    }

    /// True when `box`'s ranges on the two other axes lie within an inch of the solid's (a tenon on its end, a mortise
    /// cut for it).
    static func near(_ box: JBox, _ s: [FamilyAxis: Face], except axis: FamilyAxis) -> Bool {
        let reach = 0.0254 * 2
        for a in FamilyAxis.allCases where a != axis {
            guard let f = s[a] else { return false }
            if box.l(a) > f.hi + reach || box.h(a) < f.lo - reach { return false }
        }
        return true
    }

    /// A box with every face bound back to the formulas it lies on; `inside` also binds faces that lie inside a solid.
    func rebind(_ b: JBox, inside: Bool) -> JBox {
        guard !isEmpty else { return b }
        var out = b
        for a in FamilyAxis.allCases {
            let ref = inside ? b : nil
            out.lo[a.idx] = rebind(b.lo[a.idx], a, near: ref)
            out.hi[a.idx] = rebind(b.hi[a.idx], a, near: ref)
        }
        return out
    }
}

extension PartSolidContext {
    /// FMG4: the formula faces of every part of the model that has some (compiling), found once per compile, so a
    /// part's mortises follow the slats whose tenons they hold.
    func formulaFaces(_ m: BIMModel) -> [ElementID: FormulaFaces] {
        if let c = formulaFacesCache { return c }
        var out: [ElementID: FormulaFaces] = [:]
        for e in m.elements(.furnitureRails) where e.furnitureRail?.slats != nil || e.furnitureRail?.eq != nil {
            let f = FormulaFaces(FurniturePartSolids.rawSolids(e, m, self), e, m, self)
            if !f.isEmpty { out[e.id] = f }
        }
        formulaFacesCache = out
        return out
    }
}

// MARK: - Turned legs

/// FMG4: stretchers and rails that join a turned leg below its pommel: as a turner leaves a square block on a turned leg
/// where a stretcher joins, the leg gets a square block round the joint (the turned body is cut away there, so only
/// boxes are cut, never the revolve: compiling stays fast) and the mortises are cut in it at Fine.
enum TurnedLegJoints {
    static let margin = 0.5 * 0.0254

    /// The turned leg's local family with blocks and mortises for `voids` (model boxes) below its pommel; the leg family
    /// unchanged when none are.
    static func cut(_ p: PlacedLocalFamily, voids: [JBox], width w: Double) -> PlacedLocalFamily {
        var fam = p.family
        guard let h = fam.types.first?.values["Height"]?.doubleValue, h > Tolerance.length, let body = fam.nestedFamilies.first,
              let pommel = fam.solids.first(where: { $0.name == "Pommel" }) else { return p }
        let neck = h * FurnitureLegShapes.pommelStart
        let rot = -p.rotation * .pi / 180
        func local(_ q: Vec2) -> Vec2 {
            let d = q - Vec2(p.x.value, p.y.value)
            return Vec2(d.x * cos(rot) - d.y * sin(rot), d.x * sin(rot) + d.y * cos(rot))
        }
        // Each void in the leg's frame (z from its foot).
        let boxes: [(rect: Rect2, z0: Double, z1: Double)] = voids.map { b in
            let corners = [Vec2(b.l(.x), b.l(.y)), Vec2(b.h(.x), b.l(.y)), Vec2(b.h(.x), b.h(.y)), Vec2(b.l(.x), b.h(.y))].map(local)
            return (Rect2(points: corners), b.l(.z) - p.z.value, b.h(.z) - p.z.value)
        }
        // Blocks: the voids below the neck, merged where they overlap, a margin round each.
        var bands: [(Double, Double)] = []
        for b in boxes.filter({ $0.z0 < neck - 1e-6 }).sorted(by: { $0.z0 < $1.z0 }) {
            let lo = max(0, b.z0 - margin), hi = min(neck, b.z1 + margin)
            if let last = bands.last, lo <= last.1 { bands[bands.count - 1].1 = max(last.1, hi) } else { bands.append((lo, hi)) }
        }
        let n = PartSolidContext.number
        func share(_ z: Double) -> String { "Height * \(n(z / h))" }
        var cutIDs = [pommel.id]
        for (k, band) in bands.enumerated() {
            var s = FamilySolid(name: "Block \(k + 1)", profile: .rectangle(xMin: .expr(n(-w / 2)), xMax: .expr(n(w / 2)), yMin: .expr(n(-w / 2)), yMax: .expr(n(w / 2))),
                                zMin: .expr(share(band.0)), zMax: .expr(share(band.1)), materialParameter: "Material")
            s.id = "block-\(k + 1)"
            fam.solids.append(s)
            cutIDs.append(s.id)
        }
        // The turned body between the blocks: its profile clipped to each band left (shares of the body's height). When
        // it can't be read the body stays whole (the blocks overlap it), never losing the mortises.
        if !bands.isEmpty, let split = splitBody(body, height: neck, keeping: bands) {
            fam.nestedFamilies = [split]
            for i in fam.nestedInstances.indices where fam.nestedInstances[i].familyName == body.name { fam.nestedInstances[i].familyName = split.name }
        }
        // The mortises, cut in the pommel and the blocks at Fine.
        for (k, v) in boxes.enumerated() {
            var s = FamilySolid(name: "Joint Cut \(k + 1)", profile: .rectangle(xMin: .expr(n(v.rect.min.x)), xMax: .expr(n(v.rect.max.x)), yMin: .expr(n(v.rect.min.y)), yMax: .expr(n(v.rect.max.y))),
                                zMin: .expr(share(v.z0)), zMax: .expr(share(v.z1)), isVoid: true)
            s.visibleAt = [.fine]
            s.cuts = cutIDs
            fam.solids.append(s)
        }
        fam.name = "\(fam.name) Joined " + boxes.map { "\(n($0.rect.min.x)),\(n($0.rect.min.y)),\(n($0.z0))" }.joined(separator: ";")
        var q = p
        q.family = fam
        return q
    }

    /// LEGFIX: one point of a turned body's profile: its radius and height as shares of the body's Height (at the body's
    /// height now), with the formulas it was written with (VIS: bead points are a share plus a length, so beads stay
    /// round as the leg flexes).
    struct ProfilePoint {
        var r: Double, t: Double
        var x: FamilyBound, y: FamilyBound
    }

    /// The turned body `body` (height `hb`) as the parts of it outside `bands` (leg z ranges below the neck), or nil when
    /// its profile can't be read. Points kept keep their formulas; the points cut at a band are shares of Height, so
    /// they stay on the blocks' faces as the leg flexes.
    static func splitBody(_ body: FamilyDefinition, height hb: Double, keeping bands: [(Double, Double)]) -> FamilyDefinition? {
        guard hb > Tolerance.length, case .revolve(let rev)? = body.solids.first?.profile else { return nil }
        func eval(_ b: FamilyBound) -> Double? {
            guard case .expr(let src) = b else { return nil }
            if let v = Double(src) { return v }
            guard let f = try? Formula(src, knownNames: ["Height"]),
                  let v = try? f.evaluate(units: .metric, { $0 == "Height" ? .quantity(hb, .length) : nil }) else { return nil }
            return v.quantityValue
        }
        let prof = rev.profile.compactMap { pt -> ProfilePoint? in
            guard let r = eval(pt.x), let z = eval(pt.y) else { return nil }
            return ProfilePoint(r: r, t: z / hb, x: pt.x, y: pt.y)
        }
        guard prof.count == rev.profile.count, prof.count >= 3 else { return nil }
        let n = PartSolidContext.number
        var keep: [(Double, Double)] = []
        var t0 = 0.0
        for band in bands { keep.append((t0, band.0 / hb)); t0 = band.1 / hb }
        keep.append((t0, 1))
        var b = body
        b.solids = keep.enumerated().compactMap { k, r in
            guard r.1 - r.0 > 1e-6 else { return nil }
            let clipped = clip(prof, r.0, r.1)
            guard clipped.count >= 3 else { return nil }
            var s = FamilySolid(name: "Turned Body \(k + 1)", profile: .revolve(FamilyRevolve(profile: clipped.map { FamilyPoint($0.x, $0.y) })),
                                zMin: .expr("0"), zMax: .expr("Height"), materialParameter: "Material")
            s.id = "body-\(k + 1)"
            return s
        }
        guard !b.solids.isEmpty else { return nil }
        b.name = "\(body.name) Blocked \(bands.map { "\(n($0.0 / hb))-\(n($0.1 / hb))" }.joined(separator: ","))"
        return b
    }

    /// A closed profile clipped to t0 ≤ t ≤ t1 (Sutherland–Hodgman on the two heights); the points made at a cut are
    /// shares of Height.
    static func clip(_ poly: [ProfilePoint], _ t0: Double, _ t1: Double) -> [ProfilePoint] {
        let n = PartSolidContext.number
        func cut(_ pts: [ProfilePoint], keep: (ProfilePoint) -> Bool, at t: Double) -> [ProfilePoint] {
            guard !pts.isEmpty else { return [] }
            var out: [ProfilePoint] = []
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                let ka = keep(a), kb = keep(b)
                if ka { out.append(a) }
                if ka != kb, abs(b.t - a.t) > 1e-12 {
                    let r = a.r + (b.r - a.r) * (t - a.t) / (b.t - a.t)
                    out.append(ProfilePoint(r: r, t: t, x: .expr(n(r)), y: .expr("Height * \(n(t))")))
                }
            }
            return out
        }
        return cut(cut(poly, keep: { $0.t >= t0 - 1e-12 }, at: t0), keep: { $0.t <= t1 + 1e-12 }, at: t1)
    }
}
