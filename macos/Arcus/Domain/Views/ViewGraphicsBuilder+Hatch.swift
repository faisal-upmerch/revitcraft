import Foundation
import ArcusGeometry

// W4-HATCH: cut and surface fills from project fill patterns. Order, lowest first: category default (poché or the
// material's procedural class hatch) → the material's Cut/Surface Pattern and colour → the type's Coarse Scale Fill
// (coarse only) → the view's resolved override (category → subcategory → filters → element, see VisibilityResolver).

extension ViewGraphicsBuilder {
    /// Parameter ids of the system-family type parameters (walls, floors, roofs, ceilings) and filled region types.
    public enum HatchParams {
        public static let coarseFillPattern = ParameterID("type.coarseFillPattern")
        public static let coarseFillColor = ParameterID("type.coarseFillColor")
        public static let regionFillPattern = ParameterID("region.fillPattern")
        public static let regionColor = ParameterID("region.color")
        public static let regionBackground = ParameterID("region.background")
        public static let regionLegacyPattern = ParameterID("region.pattern")
    }

    /// The project's fill pattern element data.
    func fillPattern(_ id: ElementID?) -> FillPatternData? { model[id]?.fillPattern }

    /// Cut fill for a category with the type's Coarse Scale Fill (coarse detail) and the material's cut pattern
    /// (medium/fine), then the view override. `detail` forces a detail level (per-layer fills are always fine).
    func cutFill(_ c: Category, materialID: ElementID?, _ o: GraphicOverride, type td: TypeData?, detail forced: DetailLevel? = nil) -> GFill? {
        let matID = materialID ?? ObjectStyles.material(c, objectStyles)
        let mat = model[matID]?.material
        let detail = forced ?? detailLevel(c)
        guard var f = ObjectStyles.cutFill(c, detail: detail, material: mat) else { return nil }
        if detail == .coarse {
            if let td, let pid = td.params[HatchParams.coarseFillPattern]?.refValue, let d = fillPattern(pid) {
                f = GFill(fillPattern: d, color: Self.hexColor(td.params[HatchParams.coarseFillColor]) ?? .black, background: d.isSolid ? nil : .white)
            }
        } else if let mat {
            if let d = fillPattern(mat.cutPatternID) {
                f = GFill(fillPattern: d, color: mat.cutPatternColor, background: d.isSolid ? nil : .white)
            } else {
                if mat.cutPatternID != nil { f.color = mat.cutPatternColor }
                upgradeProcedural(&f)
            }
        } else {
            upgradeProcedural(&f)
        }
        applyCutOverride(&f, o)
        return f
    }

    /// Cut fill for an element: its type supplies the Coarse Scale Fill.
    func cutFill(_ e: Element, materialID: ElementID?, _ o: GraphicOverride, detail: DetailLevel? = nil) -> GFill? {
        cutFill(e.category, materialID: materialID, o, type: model.typeData(of: e), detail: detail)
    }

    /// Surface pattern of a material seen in projection (floors in plan, ceilings in ceiling plans), with the view
    /// override on top. nil when neither the material nor the override draws a surface pattern.
    func surfaceFill(materialID: ElementID?, _ o: GraphicOverride) -> GFill? {
        var f: GFill?
        if let mat = model[materialID]?.material, let d = fillPattern(mat.surfacePatternID), !d.isSolid {
            f = GFill(fillPattern: d, color: mat.surfacePatternColor, transparency: o.transparency ?? 0, halftone: o.halftone ?? false)
        }
        if f == nil { f = surfaceFill(o) } else if var g = f { applySurfaceOverride(&g, o); f = g }
        return f
    }

    func upgradeProcedural(_ f: inout GFill) { Self.upgradeProcedural(&f, model) }
    func applyCutOverride(_ f: inout GFill, _ o: GraphicOverride) { Self.applyCutOverride(&f, o, model) }
    func applySurfaceOverride(_ f: inout GFill, _ o: GraphicOverride) { Self.applySurfaceOverride(&f, o, model) }
    func regionFill(_ td: TypeData?, _ o: GraphicOverride, halftone: Bool) -> GFill { Self.regionFill(td, o, halftone: halftone, model) }

    /// A procedural fill takes the line families of the project's standard pattern of the same name, so every renderer
    /// draws the same lines (the kind stays as the density fallback).
    static func upgradeProcedural(_ f: inout GFill, _ model: BIMModel) {
        guard f.hatch == nil, f.pattern != .solid, let e = FillPatternEdits.pattern(named: f.pattern.rawValue, model), let d = e.fillPattern else { return }
        f.setPattern(d)
    }

    /// Applies a view override's cut pattern and colour (a project pattern wins over a procedural kind).
    static func applyCutOverride(_ f: inout GFill, _ o: GraphicOverride, _ model: BIMModel) {
        if let id = o.cutPatternID, let d = model[id]?.fillPattern { f.setPattern(d); if f.background == nil, !d.isSolid { f.background = .white } }
        else if let p = o.cutPattern { f.setPattern(p); upgradeProcedural(&f, model) }
        if let col = o.cutPatternColor { f.color = col }
        f.halftone = o.halftone ?? false
        if let t = o.transparency { f.transparency = t }
    }

    static func applySurfaceOverride(_ f: inout GFill, _ o: GraphicOverride, _ model: BIMModel) {
        if let id = o.surfacePatternID, let d = model[id]?.fillPattern { f.setPattern(d) }
        else if let p = o.surfacePattern { f.setPattern(p); upgradeProcedural(&f, model) }
        if let col = o.surfaceColor { f.color = col }
        f.halftone = o.halftone ?? false
        if let t = o.transparency { f.transparency = t }
    }

    /// Fill of a filled region type: its Fill Pattern (project pattern, else the legacy procedural name), colour and
    /// optional background, with the element's surface override.
    public static func regionFill(_ td: TypeData?, _ o: GraphicOverride, halftone: Bool, _ model: BIMModel) -> GFill {
        let color = hexColor(td?.params[HatchParams.regionColor]) ?? .black
        let background = hexColor(td?.params[HatchParams.regionBackground]) ?? .white
        var f: GFill
        if let d = model[td?.params[HatchParams.regionFillPattern]?.refValue]?.fillPattern {
            f = GFill(fillPattern: d, color: color, background: d.isSolid ? nil : background, halftone: halftone)
        } else {
            let legacy = FillPatternKind(rawValue: td?.params[HatchParams.regionLegacyPattern]?.textValue ?? "") ?? .diagonalUp
            // Older types name a procedural kind; the project's standard pattern of that name gives it line families.
            if let e = FillPatternEdits.pattern(named: legacy.rawValue, model), let d = e.fillPattern {
                f = GFill(fillPattern: d, color: color, background: d.isSolid ? nil : background, halftone: halftone)
            } else {
                f = GFill(pattern: legacy, color: color, background: legacy == .solid ? nil : background, halftone: halftone)
            }
        }
        applySurfaceOverride(&f, o, model)
        f.halftone = halftone || (o.halftone ?? false)
        return f
    }

    /// "#RRGGBB" parameter text as a colour.
    static func hexColor(_ v: ParamValue?) -> RGBColor? {
        guard var s = v?.textValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
        return RGBColor(hex: n)
    }
}
