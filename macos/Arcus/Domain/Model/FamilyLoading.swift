import Foundation

/// What happens to the project's type values when a family that is already in the project is loaded again.
public enum FamilyReloadMode: String, Sendable, CaseIterable {
    /// Types already in the project keep their parameter values; only new types take the family's values.
    case keepProjectValues
    /// Types already in the project take the family's parameter values for every parameter the family defines.
    case overwriteValues
}

/// Loads family definitions into a project.
public enum FamilyProjectLoader {
    /// Loads `family` as a new project family, or reloads it over the family element `existing`.
    ///
    /// Types missing from the project are created. Types already in the project keep their values unless `mode` is
    /// `.overwriteValues`; parameters they don't have yet take the family's values in either mode. Shared nested
    /// families are loaded as project families too (when not already present).
    /// Returns the family element id.
    @discardableResult
    public static func load(_ family: FamilyDefinition, replacing existing: ElementID?, mode: FamilyReloadMode = .keepProjectValues,
                            in tx: TransactionContext) -> ElementID {
        let fid: ElementID
        if let existing, tx.model[existing]?.family != nil {
            fid = existing
            tx.update(existing) { $0.family = family; $0.name = family.name }
        } else {
            fid = tx.create(.families, name: family.name, data: .family(family))
        }
        let category: Category = family.template == .tag ? .tags : family.template.category
        let existingTypes = tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        // BL-SITE: a renamed family's project types show the new name (type selector, browser, schedules, IFC).
        for e in existingTypes where e.typeData?.familyName != family.name { tx.update(e.id) { $0.typeData?.familyName = family.name } }
        for t in family.types {
            if let current = existingTypes.first(where: { $0.name == t.name }) {
                tx.update(current.id) { e in
                    for p in family.parameters where p.formula == nil {
                        let key = Parameters.familyParamID(p.name)
                        if mode == .overwriteValues {
                            if let v = t.values[p.name] { e.typeData?.params[key] = v } else { e.typeData?.params.removeValue(forKey: key) }
                        } else if e.typeData?.params[key] == nil, let v = t.values[p.name] {
                            e.typeData?.params[key] = v // BL-SITE: parameters new to the project type take the family's value
                        }
                    }
                }
            } else {
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in t.values { params[Parameters.familyParamID(k)] = v }
                tx.create(.elementTypes, name: t.name, data: .type(TypeData(instanceCategory: category, familyID: fid, familyName: family.name, params: params)))
            }
        }
        for nested in family.nestedFamilies where nested.isShared && tx.model.family(named: nested.name) == nil {
            load(nested, replacing: nil, in: tx)
        }
        return fid
    }
}
