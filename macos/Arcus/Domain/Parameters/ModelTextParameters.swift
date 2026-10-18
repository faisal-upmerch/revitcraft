import Foundation
import ArcusGeometry

/// F1: instance parameters of Model Text, named and grouped as RevitCraft's (`crates/rc-core/src/params.rs`):
/// Work Plane, Elevation, Text, Horizontal Align, Material, Depth, Text Size; plus Text Font.
enum ModelTextParameters {
    typealias P = BuiltInParameter

    private static func edit(_ e: inout Element, _ f: (inout ModelTextData) -> Void) {
        guard var t = e.modelText else { return }
        f(&t)
        e.data = .modelText(t)
    }
    private static func positive(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“\(name)” needs a number.") }
        guard d > Tolerance.length else { throw ParameterError("\(name) must be greater than zero.") }
        return d
    }

    static let workPlane = P("modelText.workPlane", "Work Plane", .text, .constraints,
                             get: { e, ctx in e.modelText.map { .text("\($0.upright ? "Vertical" : "Level") : \(ctx.model[e.levelID]?.name ?? "")") } })
    static let elevation = P("modelText.elevation", "Elevation", .length, .constraints, tooltip: "Height of the text's work plane above its level.",
                             get: { e, _ in e.modelText.map { .double($0.offset) } },
                             set: { e, v, _ in
                                 guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“Elevation” needs a number.") }
                                 edit(&e) { $0.offset = d }
                             })
    static let text = P("modelText.text", "Text", .text, .graphics,
                        get: { e, _ in e.modelText.map { .text($0.text) } },
                        set: { e, v, _ in
                            let s = v.textValue ?? v.description
                            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ParameterError("Model text cannot be empty.") }
                            edit(&e) { $0.text = s }
                        })
    static let align = P("modelText.align", "Horizontal Align", .choice(ModelTextData.Alignment.allCases.map(\.rawValue)), .graphics,
                         get: { e, _ in e.modelText.map { .text($0.alignment.rawValue) } },
                         set: { e, v, _ in
                             guard let a = ModelTextData.Alignment(rawValue: v.textValue ?? v.description) else { throw ParameterError("Choose Left, Center or Right.") }
                             edit(&e) { $0.alignment = a }
                         })
    static let font = P("modelText.font", "Text Font", .text, .graphics, tooltip: "The font the glyphs come from (Arial by default).",
                        get: { e, _ in e.modelText.map { .text($0.fontName) } },
                        set: { e, v, _ in
                            let s = (v.textValue ?? v.description).trimmingCharacters(in: .whitespaces)
                            edit(&e) { $0.fontName = s.isEmpty ? ModelTextData.defaultFont : s }
                        })
    static let material = P("modelText.material", "Material", .elementRef(.materials), .materials,
                            get: { e, _ in e.modelText.map { .ref($0.materialID) } },
                            set: { e, v, ctx in
                                let id = v.refValue
                                if let id, ctx.model[id]?.material == nil { throw ParameterError("The chosen element is not a material.") }
                                edit(&e) { $0.materialID = id }
                            })
    static let depth = P("modelText.depth", "Depth", .length, .dimensions,
                         get: { e, _ in e.modelText.map { .double($0.depth) } },
                         set: { e, v, _ in let d = try positive(v, "Depth"); edit(&e) { $0.depth = d } })
    static let size = P("modelText.size", "Text Size", .length, .dimensions, tooltip: "Height of the capital letters.",
                        get: { e, _ in e.modelText.map { .double($0.size) } },
                        set: { e, v, _ in let d = try positive(v, "Text size"); edit(&e) { $0.size = d } })

    static let instance: [P] = [workPlane, elevation, text, align, font, material, depth, size]
}
