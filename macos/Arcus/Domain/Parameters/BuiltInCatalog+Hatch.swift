import Foundation
import ArcusGeometry

// W4-HATCH: fill pattern parameters — material Cut/Surface Pattern and colours, the Coarse Scale Fill Pattern/Color
// type parameters of system families, and the Fill Pattern / Color / Background of filled region types.

extension BuiltInCatalog {
    static func patternRef(_ key: String, _ name: String, _ group: ParameterGroup, tooltip: String? = nil,
                           get: @escaping @Sendable (Element) -> ElementID?, set: @escaping @Sendable (inout Element, ElementID?) -> Void) -> P {
        P(key, name, .elementRef(.fillPatterns), group, tooltip: tooltip ?? "",
          get: { e, _ in .ref(get(e)) },
          set: { e, v, ctx in
              if let r = v.refValue, ctx.model[r]?.fillPattern == nil { throw ParameterError("Not a fill pattern.") }
              set(&e, v.refValue)
          })
    }
    static func hexColorParam(_ key: String, _ name: String, _ group: ParameterGroup, allowEmpty: Bool = false,
                              get: @escaping @Sendable (Element) -> String, set: @escaping @Sendable (inout Element, String) -> Void) -> P {
        P(key, name, .text, group, tooltip: "Hex color such as #333333.",
          get: { e, _ in .text(get(e)) },
          set: { e, v, _ in
              var s = (v.textValue ?? v.description).trimmingCharacters(in: .whitespaces)
              if s.isEmpty, allowEmpty { set(&e, ""); return }
              if s.hasPrefix("#") { s.removeFirst() }
              guard s.count == 6, UInt32(s, radix: 16) != nil else { throw ParameterError("Use a hex color like #333333.") }
              set(&e, "#" + s.uppercased())
          })
    }

    static let materialCutPattern = patternRef("material.cutPattern", "Cut Pattern", .graphics,
                                               tooltip: "Fill pattern drawn where the material is cut in plans and sections (medium and fine detail).",
                                               get: { $0.material?.cutPatternID }, set: { e, id in e.material?.cutPatternID = id })
    static let materialCutPatternColor = hexColorParam("material.cutPatternColor", "Cut Pattern Color", .graphics,
                                                       get: { $0.material?.cutPatternColor.hexString ?? "" },
                                                       set: { e, s in e.material?.cutPatternColor = RGBColor(hex: UInt32(s.dropFirst(), radix: 16) ?? 0) })
    static let materialSurfacePattern = patternRef("material.surfacePattern", "Surface Pattern", .graphics,
                                                   tooltip: "Fill pattern drawn on the material's visible surfaces (floors and ceilings in plan).",
                                                   get: { $0.material?.surfacePatternID }, set: { e, id in e.material?.surfacePatternID = id })
    static let materialSurfacePatternColor = hexColorParam("material.surfacePatternColor", "Surface Pattern Color", .graphics,
                                                           get: { $0.material?.surfacePatternColor.hexString ?? "" },
                                                           set: { e, s in e.material?.surfacePatternColor = RGBColor(hex: UInt32(s.dropFirst(), radix: 16) ?? 0) })
    static let materialHatchParams: [P] = [materialCutPattern, materialCutPatternColor, materialSurfacePattern, materialSurfacePatternColor]

    static let typeCoarseFillPattern = patternRef("type.coarseFillPattern", "Coarse Scale Fill Pattern", .graphics,
                                                  tooltip: "Fill drawn where this type is cut at Coarse detail (default: solid poché).",
                                                  get: { $0.typeData?.params[ParameterID("type.coarseFillPattern")]?.refValue },
                                                  set: { e, id in e.typeData?.params[ParameterID("type.coarseFillPattern")] = id.map { .ref($0) } })
    static let typeCoarseFillColor = hexColorParam("type.coarseFillColor", "Coarse Scale Fill Color", .graphics, allowEmpty: true,
                                                   get: { $0.typeData?.params[ParameterID("type.coarseFillColor")]?.textValue ?? "" },
                                                   set: { e, s in e.typeData?.params[ParameterID("type.coarseFillColor")] = s.isEmpty ? nil : .text(s) })
    static let typeCoarseFillParams: [P] = [typeCoarseFillPattern, typeCoarseFillColor]

    static let regionFillPattern = patternRef("region.fillPattern", "Fill Pattern", .graphics,
                                              get: { $0.typeData?.params[ParameterID("region.fillPattern")]?.refValue },
                                              set: { e, id in
                                                  e.typeData?.params[ParameterID("region.fillPattern")] = id.map { .ref($0) }
                                                  if id != nil { e.typeData?.params[ParameterID("region.pattern")] = nil }
                                              })
    static let regionColor = hexColorParam("region.color", "Color", .graphics,
                                           get: { $0.typeData?.params[ParameterID("region.color")]?.textValue ?? "#000000" },
                                           set: { e, s in e.typeData?.params[ParameterID("region.color")] = .text(s) })
    static let regionBackground = hexColorParam("region.background", "Background", .graphics, allowEmpty: true,
                                                get: { $0.typeData?.params[ParameterID("region.background")]?.textValue ?? "" },
                                                set: { e, s in e.typeData?.params[ParameterID("region.background")] = s.isEmpty ? nil : .text(s) })
    static let regionTypeParams: [P] = [regionFillPattern, regionColor, regionBackground]
}
