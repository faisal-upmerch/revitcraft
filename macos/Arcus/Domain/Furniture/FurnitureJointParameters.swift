import Foundation
import ArcusGeometry

// FM6: Properties of joints the user set (Joint, Runs Through and the type's parameters) and the parts' Cut Size
// (length × width as cut: with groove depths, tenons and the joints' trims), which the Cut Size Tag and the Part List
// read.

enum FurnitureJointParameters {
    typealias P = BuiltInParameter

    static func joint(_ e: Element, _ m: BIMModel) -> FurnitureJoint? {
        guard let d = e.furnitureJoint, d.isPair else { return nil }
        return JointSolver.solve(m).joint(JointKey(d.parts[0], d.parts[1]))
    }

    static func mark(_ id: ElementID?, _ m: BIMModel) -> String {
        guard let e = m[id] else { return "" }
        return e.mark.isEmpty ? "\(e.category.singularName) \(e.id.raw)" : e.mark
    }

    // MARK: Parts

    static let cutSize = P("furniture.part.cutSize", "Cut Size", .text, .dimensions,
                           tooltip: "Width × length the part is cut to: with what runs into grooves, tenons, and the trims of its joints.",
                           get: { e, ctx in .text(FurnitureJoints.cutSizeText(e.id, ctx.model)) })
    static let cutLength = P("furniture.part.cutLength", "Cut Length", .length, .dimensions,
                             get: { e, ctx in FurnitureJoints.cutSize(of: e.id, in: ctx.model).map { .double($0.length) } })
    static let cutWidth = P("furniture.part.cutWidth", "Cut Width", .length, .dimensions,
                            get: { e, ctx in FurnitureJoints.cutSize(of: e.id, in: ctx.model).map { .double($0.width) } })

    /// Parameters FM6 adds to parts.
    static func part(_ e: Element) -> [P] {
        switch e.data {
        case .furniturePanel, .furnitureShelf, .furnitureLeg, .furnitureRail: [cutSize, cutLength, cutWidth]
        default: []
        }
    }

    // MARK: Joints

    static let typeChoices = JointType.allCases.map(\.rawValue)

    static let jointType = P("furniture.joint.type", "Joint", .choice(typeChoices), .construction,
                             tooltip: "How the parts are joined. Joint Rules gives the type until you set one.",
                             get: { e, ctx in joint(e, ctx.model).map { .text($0.type.rawValue) } ?? e.furnitureJoint?.type.map { .text($0.rawValue) } },
                             set: { e, v, ctx in
                                 guard let t = JointType(rawValue: v.textValue ?? "") else { throw ParameterError("Choose a joint type.") }
                                 if t == .miter, let j = joint(e, ctx.model), !j.isCorner { throw ParameterError("Only parts meeting at a corner can be mitred.") }
                                 if e.furnitureJoint?.type != t { e.furnitureJoint?.parameters = nil }
                                 e.furnitureJoint?.type = t
                             })
    static let ruleType = P("furniture.joint.rule", "By Rule", .text, .construction, tooltip: "The joint Joint Rules gives this pair.",
                            get: { e, ctx in joint(e, ctx.model).map { .text("\($0.pair.rawValue): \($0.ruleType.rawValue)") } })
    static let through = P("furniture.joint.through", "Runs Through", .text, .construction,
                           tooltip: "The part that runs through; the other is trimmed to it. Use the Joint tool's Previous and Next to swap them at a corner.",
                           get: { e, ctx in joint(e, ctx.model).map { .text(mark($0.throughID, ctx.model)) } })
    static let parts = P("furniture.joint.parts", "Parts", .text, .identity,
                         get: { e, ctx in e.furnitureJoint.map { d in .text(d.parts.map { mark($0, ctx.model) }.joined(separator: ", ")) } })

    static func value(_ k: JointParameterKey) -> P {
        let type: ParamType = k.isCount ? .integer : k.isAngle ? .angle : .length
        return P("furniture.joint.\(k)", k.rawValue, type, .dimensions,
                 get: { e, ctx in
                     guard let j = joint(e, ctx.model), let v = j.parameters.value(k) else { return k.isCount ? .int(0) : nil }
                     return k.isCount ? .int(Int(v)) : .double(v)
                 },
                 set: { e, v, _ in
                     var p = e.furnitureJoint?.parameters ?? JointParameters()
                     if k.isCount { p.count = max(0, v.intValue ?? Int(v.doubleValue ?? 0)) }
                     else {
                         guard let d = v.doubleValue, d >= 0 else { throw ParameterError("“\(k.rawValue)” needs a positive value.") }
                         p.set(k, d)
                     }
                     e.furnitureJoint?.parameters = p
                 },
                 locked: { e, ctx in
                     guard let j = joint(e, ctx.model) else { return "The parts no longer join." }
                     return j.type.parameterKeys.contains(k) ? nil : "\(j.type.rawValue) joints don't use \(k.rawValue)."
                 })
    }
    static let values: [P] = JointParameterKey.allCases.map(value)

    static func instance(for e: Element) -> [P] {
        guard let d = e.furnitureJoint else { return [] }
        guard d.isPair else { return [parts, BuiltInCatalog.comments] }
        return [jointType, ruleType, through] + values + [parts, BuiltInCatalog.comments]
    }

    static var all: [P] { [cutSize, cutLength, cutWidth, jointType, ruleType, through, parts] + values }
}
