import Foundation

// FMG4: Associate Family Parameter, as in a Revit-style Family Editor: the small button beside a property in
// Properties ties it to a family parameter of a compatible type, so each family type sets it (Leaf Count of a door
// to an Integer or Yes/No parameter; Visible of a part or a front to a Yes/No parameter, as an optional cushion or
// shelf is). An associated property is greyed in Properties and shows the parameter; the compiled family carries the
// association (Leaf Count variants, solids shown by the parameter).

public enum FurnitureAssociations {
    /// The Visible property of parts and fronts (stored in the element's parameters; nil = visible).
    public static let visible = ParameterID("furniture.visible")
    /// The family parameter a part's or front's Visible follows.
    public static let visibleParameter = ParameterID("furniture.visibleParameter")

    /// Visible: "Yes" shows the element in the loaded family; associate it with a Yes/No parameter to show it by type.
    public static let visibleProperty = BuiltInParameter(
        visible.key, "Visible", .bool, .graphics,
        tooltip: "Shown in the loaded family. Associate it with a Yes/No family parameter to show it by type.",
        get: { e, _ in .bool(e.params[visible]?.boolValue ?? true) },
        set: { e, v, _ in e.params[visible] = (v.boolValue ?? true) ? nil : .bool(false) },
        locked: { e, _ in e.params[visibleParameter]?.textValue.map { "Set by the family parameter “\($0)”." } })

    /// True for the elements that have Visible (parts and fronts of a Furniture document).
    public static func hasVisible(_ e: Element) -> Bool {
        e.category.isFurniturePart || e.category == .furnitureFronts
    }

    /// The family parameter types a property can be associated with, or nil when it can't be.
    public static func compatibleTypes(_ property: ParameterID, _ e: Element) -> [ParamType]? {
        if property == FurnitureFrontParameters.leafCount.id, e.furnitureFront?.kind == .door { return [.integer, .bool] }
        if property == visible, hasVisible(e) { return [.bool] }
        return nil
    }

    /// The family parameter a property follows, if any.
    public static func association(_ property: ParameterID, _ e: Element) -> String? {
        if property == FurnitureFrontParameters.leafCount.id { return e.furnitureFront?.leafCountParameter }
        if property == visible { return e.params[visibleParameter]?.textValue }
        return nil
    }

    /// The document's family parameters a property can follow, by name.
    public static func compatibleParameters(_ property: ParameterID, _ e: Element, _ m: BIMModel) -> [FamilyParameter] {
        guard let types = compatibleTypes(property, e) else { return [] }
        return (m.furnitureSetup?.family.parameters ?? []).filter { types.contains($0.type) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Associates a property of the elements with a family parameter (nil removes the association). `newParameter`,
    /// when given, is added to the family first (the dialog's New Parameter), its value Yes / 1 in every type unless
    /// set.
    public static func associate(_ ids: [ElementID], _ property: ParameterID, with parameter: String?, adding newParameter: FamilyParameter? = nil,
                                 in tx: TransactionContext) throws(TransactionError) {
        guard let first = ids.compactMap({ tx.model[$0] }).first, let types = compatibleTypes(property, first) else {
            throw TransactionError("This property can't be associated with a family parameter.")
        }
        if let p = newParameter {
            guard types.contains(p.type) else { throw TransactionError("“\(p.name)” must be \(types.map(\.displayName).joined(separator: " or ")).") }
            guard FamilyEditing.isValidName(p.name) else { throw TransactionError("“\(p.name)” isn't a valid parameter name.") }
            guard tx.model.furnitureSetup?.family.parameter(named: p.name) == nil else {
                throw TransactionError("There is already a parameter named “\(p.name)”.", resolution: "Pick it in the list, or use another name.")
            }
            try FurnitureParameters.edit(tx) { s in
                s.family.parameters.append(p)
                let value: ParamValue = p.type == .bool ? .bool(true) : .int(1)
                for i in s.family.types.indices where s.family.types[i].values[p.name] == nil { s.family.types[i].values[p.name] = value }
            }
        }
        if let parameter {
            guard let fp = tx.model.furnitureSetup?.family.parameter(named: parameter), types.contains(fp.type) else {
                throw TransactionError("“\(parameter)” isn't a \(types.map(\.displayName).joined(separator: " or ")) family parameter.", resolution: "Add it in Family Types, then associate it.")
            }
        }
        if property == FurnitureFrontParameters.leafCount.id {
            try FurnitureFronts.associateLeafCount(ids, with: parameter, in: tx)
            return
        }
        for id in ids where tx.model[id].map(hasVisible) == true {
            tx.update(id) { $0.params[visibleParameter] = parameter.map { .text($0) } }
        }
    }

    /// Whether an element shows in the compiled family now (Visible unchecked and not associated: never), and the
    /// yes/no parameter that shows it.
    static func compiledVisibility(_ e: Element) -> (shown: Bool, parameter: String?) {
        if let p = e.params[visibleParameter]?.textValue { return (true, p) }
        return (e.params[visible]?.boolValue ?? true, nil)
    }

    /// A solid's visibility parameter once the element's own is added: the element's, or both (a yes/no parameter
    /// "<a> and <b>" added to the family, as the slats past a count and an optional part need).
    static func combined(_ existing: String?, _ own: String?, into f: inout FamilyDefinition) -> String? {
        guard let own else { return existing }
        guard let existing, existing != own else { return own }
        let name = "\(own) and \(existing)"
        if f.parameter(named: name) == nil {
            f.parameters.append(FamilyParameter(name: name, type: .bool, group: .other, formula: "and(\(own), \(existing))"))
        }
        return name
    }

    /// Applies the elements' Visible to the solids and nested shapes a compile wrote for them (`from` onwards).
    static func apply(_ e: Element, solidsFrom s0: Int, nestedFrom n0: Int, to f: inout FamilyDefinition) {
        let v = compiledVisibility(e)
        guard v.parameter != nil || !v.shown else { return }
        if !v.shown {
            f.solids.removeSubrange(s0..<f.solids.count)
            f.nestedInstances.removeSubrange(n0..<f.nestedInstances.count)
            return
        }
        for i in s0..<f.solids.count { f.solids[i].visibilityParameter = combined(f.solids[i].visibilityParameter, v.parameter, into: &f) }
        for i in n0..<f.nestedInstances.count { f.nestedInstances[i].visibilityParameter = combined(f.nestedInstances[i].visibilityParameter, v.parameter, into: &f) }
    }
}
