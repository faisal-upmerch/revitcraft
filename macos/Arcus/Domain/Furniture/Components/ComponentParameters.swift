import Foundation
import ArcusGeometry

// COMP: Properties of placed components and their types, grouped as the owner asked (Identity, Dimensions,
// Placement, Materials, Constraints, Manufacturing, Data) in Revit's own group names: Identity Data, Dimensions,
// Constraints (placement on the host), Materials and Finishes, Construction (mounting) and Other (data). The family's
// own parameters come from the family as for any component; these are the placement and library ones.

enum ComponentParameters {
    typealias P = BuiltInParameter
    typealias K = ComponentInstanceKeys

    static func err(_ s: String) -> ParameterError { ParameterError(s) }
    static func setting(_ e: Element) -> ComponentSettings? { ComponentSettings(e) }

    static let face = P("comp.face", "Host Face", .choice(ComponentFace.allCases.filter { $0 != .any }.map(\.rawValue)), .constraints,
                        tooltip: "The face of the host it's on.",
                        get: { e, _ in e.params[K.face] },
                        set: { e, v, _ in
                            guard let f = v.textValue.flatMap(ComponentFace.init(rawValue:)) else { throw err("Choose a face.") }
                            e.params[K.face] = .text(f.rawValue)
                        })
    static let alignment = P("comp.align", "Alignment", .choice(ComponentAlignment.allCases.map(\.rawValue)), .constraints,
                             tooltip: "Where it sits on the face; the offsets are measured from there.",
                             get: { e, _ in e.params[K.alignment] },
                             set: { e, v, _ in
                                 guard let a = v.textValue.flatMap(ComponentAlignment.init(rawValue:)) else { throw err("Choose an alignment.") }
                                 e.params[K.alignment] = .text(a.rawValue)
                             })
    static func length(_ key: ParameterID, _ name: String, _ tip: String) -> P {
        P(key.key, name, .length, .constraints, tooltip: tip, get: { e, _ in e.params[key] ?? .double(0) },
          set: { e, v, _ in
              guard let d = v.doubleValue, d.isFinite else { throw err("“\(name)” needs a length.") }
              e.params[key] = .double(d)
          })
    }
    static let offsetX = length(K.offsetX, "Offset X", "Along the face, from the aligned edge (or the centre).")
    static let offsetY = length(K.offsetY, "Offset Y", "Up the face, from the aligned edge (or the centre).")
    static let offsetZ = length(K.offsetZ, "Offset from Face", "Out of the face.")
    static let rotation = P("comp.rotation", "Rotation on Face", .angle, .constraints, get: { e, _ in e.params[K.rotation] ?? .double(0) },
                            set: { e, v, _ in
                                guard let d = v.doubleValue, d.isFinite else { throw err("Rotation needs an angle.") }
                                e.params[K.rotation] = .double(d)
                            })
    static let follows = P("comp.follows", "Follow Host", .bool, .constraints, tooltip: "Moves and resizes with its host.",
                           get: { e, _ in e.params[K.follows] ?? .bool(true) }, set: { e, v, _ in e.params[K.follows] = .bool(v.boolValue ?? true) })
    static let setCount = P("comp.count", "Count in Set", .integer, .constraints, tooltip: "Instances in this set (0 = by the hardware rules).",
                            get: { e, _ in e.params[K.count] ?? .int(0) },
                            set: { e, v, _ in
                                guard let n = v.intValue, (0...12).contains(n) else { throw err("Count in Set is 0 to 12.") }
                                e.params[K.count] = .int(n)
                            })
    static let hostName = P("comp.hostName", "Host", .text, .constraints, tooltip: "What it's mounted on.",
                            get: { e, ctx in
                                guard let h = ctx.model[e.hostID] else { return .text("Level") }
                                return .text(h.mark.isEmpty ? h.category.singularName : "\(h.category.singularName) \(h.mark)")
                            })
    static let category = P("comp.category", "Component Category", .text, .identity,
                            get: { e, ctx in ComponentDocument.definition(of: e, ctx.model).map { .text("\($0.category.code) \($0.category.title)") } })
    static let subcategory = P("comp.subcategory", "Subcategory", .text, .identity,
                               get: { e, ctx in ComponentDocument.definition(of: e, ctx.model).map { .text($0.subcategory) } })
    static let drilling = P("comp.drilling", "Mounting", .text, .construction, tooltip: "The holes and cutouts it machines in its host.",
                            get: { e, ctx in
                                guard let d = ComponentDocument.definition(of: e, ctx.model) else { return nil }
                                let n = d.mounting.count
                                return .text(n == 0 ? "None" : "\(n) \(n == 1 ? "operation" : "operations")")
                            })
    static let power = P("comp.power", "Power", .text, .other,
                         get: { e, ctx in
                             guard let p = ComponentFabrication.power(ctx.model).first(where: { $0.elementID == e.id }) else { return nil }
                             return .text(String(format: "%.1f W, %@", p.watts, p.supply))
                         })

    /// Instance Properties of a placed component.
    static func instance(_ e: Element) -> [P] {
        guard e.category == .furnitureHardware, e.params[FurnitureHardware.slotParam] == nil, e.params[ComponentKit.definitionParam] != nil else { return [] }
        var list: [P] = [category, subcategory]
        if e.params[K.face] != nil {
            list += [hostName, face, alignment, offsetX, offsetY, offsetZ, rotation, follows]
            if e.params[K.group] != nil { list.append(setCount) }
        }
        return list + [drilling, power]
    }

    static let sku = P("type.sku", "SKU", .text, .identity, get: { e, _ in .text(e.typeData?.params[ComponentKit.skuParam]?.textValue ?? "") },
                       set: { e, v, _ in let s = v.textValue ?? ""; e.typeData?.params[ComponentKit.skuParam] = s.isEmpty ? nil : .text(s) })
    static let version = P("comp.version", "Library Version", .integer, .identity, get: { e, _ in e.typeData?.params[ComponentKit.versionParam] })

    /// Type Properties of component types: the identity data with SKU after Model, and the library version.
    static func type(_ identity: [P]) -> [P] {
        var out = identity
        let at = (out.firstIndex { $0.id.key == "type.model" } ?? out.count - 1) + 1
        out.insert(sku, at: min(at, out.count))
        out.append(version)
        return out
    }
}
