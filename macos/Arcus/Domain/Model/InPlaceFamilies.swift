import Foundation
import ArcusGeometry

// F5: Architecture ▸ Component ▸ Model In-Place (RevitCraft rc-app dialogs `in_place_dialog`, family_editor.rs
// `new_family(…, in_place)` and `load`). An in-place family is a project-owned family made for one element: it is
// modelled in the Family Editor and, when first loaded, gets its single instance at the project origin on its level.

public enum InPlaceFamilies {
    /// Marks a project family as in-place (a parameter on its family element, kept by later reloads).
    public static let marker = ParameterID("inPlaceFamily")

    /// The categories an in-place family can have, in RevitCraft's order: Casework, Columns, Furniture, Generic Models,
    /// Plumbing Fixtures, Specialty Equipment.
    public static let templates: [FamilyTemplate] = [.casework, .column, .furniture, .genericModel, .plumbingFixture, .specialtyEquipment]

    /// An empty family of `template`: the origin's reference planes and one type named after the family, ready for
    /// forms (RevitCraft `family_def::empty_template`).
    public static func definition(name: String, template: FamilyTemplate) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: template)
        f.referencePlanes = [
            FamilyReferencePlane(name: "Center (Left/Right)", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
            FamilyReferencePlane(name: "Center (Front/Back)", axis: .y, offset: "0", strength: .centerFrontBack, definesOrigin: true),
            FamilyReferencePlane(name: "Ref. Level", axis: .z, offset: "0", strength: .bottom, definesOrigin: true),
        ]
        f.types = [FamilyTypeDefinition(name: name, values: [:])]
        f.description = "In-place family"
        return f
    }

    /// `base`, or "base 2", "base 3"… when a family of that name exists ("Family1", "Family2"… for the default).
    public static func uniqueName(_ base: String, _ model: BIMModel) -> String {
        let names = Set(model.elements(.families).map(\.name))
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        if !names.contains(trimmed) { return trimmed }
        var n = 2
        let stem = trimmed.hasSuffix("1") && trimmed.count > 1 ? String(trimmed.dropLast()) : trimmed + " "
        while names.contains("\(stem)\(n)") { n += 1 }
        return "\(stem)\(n)"
    }

    /// The default name of a new in-place family: Family1, Family2…
    public static func defaultName(_ model: BIMModel) -> String { uniqueName("Family1", model) }

    public static func isInPlace(_ family: Element?) -> Bool { family?.params[marker]?.boolValue == true }

    /// The project family's instances.
    public static func instances(of familyID: ElementID, _ model: BIMModel) -> [Element] {
        model.elements(.elementTypes).filter { $0.typeData?.familyID == familyID }.flatMap { model.instances(ofType: $0.id) }
    }

    /// Marks a loaded family as in-place and places its single instance at the project origin on `level`, as RevitCraft
    /// does when the in-place family is finished. Returns the instance.
    @discardableResult
    public static func place(familyID: ElementID, level: ElementID?, in tx: TransactionContext) throws -> ElementID {
        guard let fam = tx.model[familyID], let def = fam.family else { throw TransactionError("The in-place family is not in the project.") }
        guard let type = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyID == familyID }) else {
            throw TransactionError("The in-place family has no type.")
        }
        if let existing = instances(of: familyID, tx.model).first { return existing.id }
        tx.update(familyID) { $0.params[marker] = .bool(true) }
        let category = def.template.category
        let data: ElementData = def.template == .column ? .column(ColumnData(location: .zero)) : .component(ComponentData(location: .zero))
        return tx.create(category, name: def.name, data: data, typeID: type.id, levelID: level)
    }
}
