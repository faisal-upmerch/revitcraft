import Foundation

/// Loads component library families into a project on demand.
///
/// Projects never embed the library: a family is added the first time one of its types is placed or loaded, and
/// then with only the types actually used. Loading another type of an already loaded family adds just that type.
public enum ComponentLibraryLoader {
    /// The project family element for a library item, if it has been loaded.
    public static func loadedFamily(_ item: ComponentLibraryItem, _ model: BIMModel) -> ElementID? {
        model.elements(.families).first { $0.name == item.family.name && $0.family != nil }?.id
    }

    /// The project type element for a library type, if it has been loaded.
    public static func loadedType(_ item: ComponentLibraryItem, typeName: String, _ model: BIMModel) -> ElementID? {
        guard let fid = loadedFamily(item, model) else { return nil }
        return model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == typeName }?.id
    }

    /// Names of the item's types already in the project.
    public static func loadedTypeNames(_ item: ComponentLibraryItem, _ model: BIMModel) -> Set<String> {
        guard let fid = loadedFamily(item, model) else { return [] }
        return Set(model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }.map(\.name))
    }

    /// Makes `typeName` of `item` available in the project and returns its type element. Adds the family on first
    /// use (with only this type), or adds the type to the family already loaded. Material parameters default to
    /// project materials of the same name, created when missing.
    @discardableResult
    public static func load(_ item: ComponentLibraryItem, typeName: String, in tx: TransactionContext) -> ElementID? {
        guard let libType = item.family.type(named: typeName) else { return nil }
        if let existing = loadedType(item, typeName: typeName, tx.model) { return existing }
        let fid: ElementID
        if let current = loadedFamily(item, tx.model), var def = tx.model[current]?.family {
            if def.type(named: typeName) == nil { def.types.append(libType) }
            fid = FamilyProjectLoader.load(def, replacing: current, mode: .keepProjectValues, in: tx)
        } else {
            var def = item.family
            def.types = [libType]
            fid = FamilyProjectLoader.load(def, replacing: nil, in: tx)
        }
        guard let tid = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyID == fid && $0.name == typeName })?.id else { return nil }
        var refs: [ParameterID: ParamValue] = [:]
        for (param, lm) in item.materials.sorted(by: { $0.key < $1.key }) {
            refs[Parameters.familyParamID(param)] = .ref(material(lm, in: tx))
        }
        tx.update(tid) { e in
            for (k, v) in refs where e.typeData?.params[k] == nil { e.typeData?.params[k] = v }
        }
        return tid
    }

    /// A project material with the library material's name, created when missing (from the material library's
    /// entry of that name when there is one, so it gets its description and cut pattern).
    static func material(_ m: ComponentMaterial, in tx: TransactionContext) -> ElementID {
        if let e = tx.model.materials.first(where: { $0.name.caseInsensitiveCompare(m.name) == .orderedSame }) { return e.id }
        let data = MaterialLibrary.named(m.name)?.materialData() ?? m.data
        return tx.create(.materials, name: m.name, data: .material(data))
    }
}
