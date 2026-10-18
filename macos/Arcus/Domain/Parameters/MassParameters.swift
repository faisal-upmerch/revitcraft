import Foundation
import ArcusGeometry

/// F5: instance parameters of a conceptual mass, named and grouped as RevitCraft's (`crates/rc-core/src/params.rs`
/// `ElementKind::Mass`): Level, Base Offset, Height, Gross Floor Area, Gross Surface Area, Gross Volume, Name; plus the
/// Arcus blend controls (Form, Top Inset).
enum MassParameters {
    typealias P = BuiltInParameter

    private static func edit(_ e: inout Element, _ f: (inout MassData) -> Void) {
        guard var m = e.mass else { return }
        f(&m)
        e.data = .mass(m)
    }
    private static func number(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        return d
    }

    static let baseOffset = P("mass.baseOffset", "Base Offset", .length, .constraints,
                              get: { e, _ in e.mass.map { .double($0.baseOffset) } },
                              set: { e, v, _ in let d = try number(v, "Base Offset"); edit(&e) { $0.baseOffset = d } })
    static let height = P("mass.height", "Height", .length, .dimensions,
                          get: { e, _ in e.mass.map { .double($0.height) } },
                          set: { e, v, _ in
                              let d = try number(v, "Height")
                              guard d > Tolerance.length else { throw ParameterError("Height must be greater than zero.") }
                              guard var m = e.mass else { return }
                              m.height = d
                              if m.isBlend, MassGeometry.topLoop(m) == nil { throw ParameterError("The top inset leaves no top face.") }
                              e.data = .mass(m)
                          })
    static let form = P("mass.form", "Form", .text, .dimensions, tooltip: "Extrusion, or Blend when the top is inset from the footprint.",
                        get: { e, _ in e.mass.map { .text($0.formName) } })
    static let topInset = P("mass.topInset", "Top Inset", .length, .dimensions,
                            tooltip: "How far the top face lies inside the footprint. Zero makes an extrusion; more makes a blend that tapers.",
                            get: { e, _ in e.mass.map { .double($0.topInset ?? 0) } },
                            set: { e, v, _ in
                                let d = try number(v, "Top Inset")
                                guard d >= 0 else { throw ParameterError("Top Inset can't be negative.") }
                                guard var m = e.mass else { return }
                                m.topInset = d > Tolerance.length ? d : nil
                                if m.isBlend, MassGeometry.topLoop(m) == nil { throw ParameterError("That inset leaves no top face. Use a smaller value.") }
                                e.data = .mass(m)
                            })
    static let grossFloorArea = P("mass.grossFloorArea", "Gross Floor Area", .area, .dimensions,
                                  tooltip: "The mass's area at every level that cuts it (its mass floors).",
                                  get: { e, ctx in e.mass == nil ? nil : .double(MassGeometry.grossFloorArea(e, ctx.model)) })
    static let grossSurfaceArea = BuiltInCatalog.q("mass.grossSurfaceArea", "Gross Surface Area", .area) { $0.area }
    static let grossVolume = BuiltInCatalog.q("mass.grossVolume", "Gross Volume", .volume) { $0.volume }

    static let instance: [P] = [BuiltInCatalog.levelParam, baseOffset, height, form, topInset, grossFloorArea, grossSurfaceArea, grossVolume]
}
