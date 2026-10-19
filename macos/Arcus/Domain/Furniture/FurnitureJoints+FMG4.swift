import Foundation
import ArcusGeometry

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
