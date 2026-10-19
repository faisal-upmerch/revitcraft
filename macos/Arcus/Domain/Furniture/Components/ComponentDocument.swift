import Foundation
import ArcusGeometry

// COMP: components in a document, as Revit loads families. The first use of a component loads its family (every
// standard type, like Load Family) into the Furniture Hardware category; the family element and its types carry the
// definition id and version, and each type its cost, manufacturer, model, SKU and description (Identity Data). A
// document whose family is older than the library's definition is offered an upgrade (Reload, keeping the project's
// values); a family whose definition is gone (a deleted user component) keeps working as an ordinary family.

/// The components a document can use: the built-in library plus the user's own library. The app sets `current` when
/// the user library loads or changes; domain code (regeneration, upgrades, search) reads it.
public struct ComponentCatalog: Sendable {
    public var builtIn: [ComponentDefinition]
    public var user: [ComponentDefinition]
    public init(builtIn: [ComponentDefinition] = ComponentLibrary.furniture, user: [ComponentDefinition] = []) {
        self.builtIn = builtIn; self.user = user
    }
    public var all: [ComponentDefinition] { builtIn + user }
    public func definition(id: String) -> ComponentDefinition? { user.first { $0.id == id } ?? builtIn.first { $0.id == id } }
    public func definition(named n: String) -> ComponentDefinition? { user.first { $0.name == n } ?? builtIn.first { $0.name == n } }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = ComponentCatalog()
    /// The catalog in use (built-ins until the app adds the user library).
    public static var current: ComponentCatalog {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

public enum ComponentDocument {
    /// The family element of a component in the document: the one stamped with its id, else one with its name.
    public static func loadedFamily(_ d: ComponentDefinition, _ m: BIMModel) -> ElementID? {
        let fams = m.elements(.families)
        return (fams.first { $0.params[ComponentKit.definitionParam]?.textValue == d.id } ?? fams.first { $0.name == d.name && $0.family != nil })?.id
    }

    /// The type element of a component type in the document (nil when not loaded).
    public static func loadedType(_ d: ComponentDefinition, typeName: String, _ m: BIMModel) -> ElementID? {
        guard let fid = loadedFamily(d, m) else { return nil }
        return m.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == typeName }?.id
    }

    /// The definition id of an instance, type or family element (nil for families that aren't components).
    public static func definitionID(of e: Element, _ m: BIMModel) -> String? {
        if let id = e.params[ComponentKit.definitionParam]?.textValue { return id }
        let type = e.isType ? e : m.type(of: e)
        if let id = type?.typeData?.params[ComponentKit.definitionParam]?.textValue { return id }
        if let fid = type?.typeData?.familyID, let id = m[fid]?.params[ComponentKit.definitionParam]?.textValue { return id }
        if let name = type?.typeData?.familyName, let d = ComponentCatalog.current.definition(named: name) { return d.id }
        return nil
    }

    /// The definition of an element (from the current catalog).
    public static func definition(of e: Element, _ m: BIMModel, catalog: ComponentCatalog = .current) -> ComponentDefinition? {
        guard let id = definitionID(of: e, m) else { return nil }
        if let d = catalog.definition(id: id) { return d }
        // Not in the library (a deleted user component, a file from another Mac): the copy stored with the family.
        let type = e.isType ? e : m.type(of: e)
        let fam = (e.family != nil ? e : nil) ?? type?.typeData.flatMap { m[$0.familyID] }
        guard let fam, let def = fam.family, let json = fam.params[ComponentKit.metaParam]?.textValue, let data = json.data(using: .utf8),
              var d = try? JSONDecoder().decode(ComponentDefinition.self, from: data) else { return nil }
        d.family = def
        return d
    }

    /// The library data stored with a loaded family (the definition without its family).
    static func meta(_ d: ComponentDefinition) -> String {
        var x = d
        x.family = FamilyDefinition(name: d.name, template: d.family.template)
        x.family.description = d.description
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(x)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Loads a component (Load Family): its family with every type, identity data and default materials; idempotent.
    /// Returns the type element of `typeName` (nil = the default type).
    @discardableResult
    public static func load(_ d: ComponentDefinition, typeName: String? = nil, in tx: TransactionContext) -> ElementID? {
        let wanted = typeName ?? d.defaultType?.name ?? ""
        if let fid = loadedFamily(d, tx.model) {
            if let t = loadedType(d, typeName: wanted, tx.model) { return t }
            // A type the document doesn't have yet (deleted, or new in the library): add it.
            if var def = tx.model[fid]?.family, let lt = d.family.type(named: wanted) {
                def.types.append(lt)
                FamilyProjectLoader.load(def, replacing: fid, mode: .keepProjectValues, in: tx)
                stamp(d, family: fid, in: tx)
            }
            return loadedType(d, typeName: wanted, tx.model) ?? firstType(fid, tx.model)
        }
        let fid = FamilyProjectLoader.load(d.family, replacing: nil, in: tx)
        stamp(d, family: fid, in: tx)
        return loadedType(d, typeName: wanted, tx.model) ?? firstType(fid, tx.model)
    }

    static func firstType(_ fid: ElementID, _ m: BIMModel) -> ElementID? {
        m.elements(.elementTypes).filter { $0.typeData?.familyID == fid }.min { $0.id < $1.id }?.id
    }

    /// Writes the definition id and version on the family and its types, and each new type's identity data and materials.
    static func stamp(_ d: ComponentDefinition, family fid: ElementID, in tx: TransactionContext) {
        tx.update(fid) { e in
            e.params[ComponentKit.definitionParam] = .text(d.id)
            e.params[ComponentKit.versionParam] = .int(d.version)
            e.params[ComponentKit.metaParam] = .text(meta(d))
        }
        var materials: [String: ElementID] = [:]
        for slot in d.materials { materials[slot.name] = material(slot.finish, in: tx) }
        for t in tx.model.elements(.elementTypes) where t.typeData?.familyID == fid {
            let spec = d.type(named: t.name)
            tx.update(t.id) { e in
                guard var td = e.typeData else { return }
                let fresh = td.params[ComponentKit.definitionParam] == nil
                td.params[ComponentKit.definitionParam] = .text(d.id)
                td.params[ComponentKit.versionParam] = .int(d.version)
                if let k = d.hardwareKind { td.params[FurnitureHardware.kindParam] = .text(k.rawValue) }
                if fresh, let spec {
                    td.params[ParameterID("type.cost")] = .double(spec.cost)
                    td.params[ParameterID("type.manufacturer")] = .text(spec.manufacturer)
                    td.params[ParameterID("type.model")] = .text(spec.model)
                    td.params[ParameterID("type.description")] = .text(spec.description)
                    td.params[ComponentKit.skuParam] = .text(spec.sku)
                }
                for (slot, mid) in materials where td.params[Parameters.familyParamID(slot)]?.refValue == nil {
                    td.params[Parameters.familyParamID(slot)] = .ref(mid)
                }
                e.typeData = td
            }
        }
    }

    /// A document material for a finish: the one with its name, else a new one.
    public static func material(_ f: ComponentFinish, in tx: TransactionContext) -> ElementID {
        if let e = tx.model.materials.first(where: { $0.name.caseInsensitiveCompare(f.name) == .orderedSame }) { return e.id }
        let data = MaterialLibrary.named(f.name)?.materialData() ?? f.data
        return tx.create(.materials, name: f.name, data: .material(data))
    }

    // MARK: Versions

    /// A loaded component family and the library definition it came from.
    public struct LoadedComponent: Sendable, Hashable {
        public var familyID: ElementID
        public var definitionID: String
        public var loadedVersion: Int
        /// nil when the definition is gone from the library (the family keeps working as it is).
        public var libraryVersion: Int?
        public var isOutdated: Bool { libraryVersion.map { $0 > loadedVersion } ?? false }
        public var isMissing: Bool { libraryVersion == nil }
    }

    /// Every component family in the document with its versions.
    public static func loaded(_ m: BIMModel, catalog: ComponentCatalog = .current) -> [LoadedComponent] {
        m.elements(.families).sorted { $0.id < $1.id }.compactMap { f in
            guard let id = f.params[ComponentKit.definitionParam]?.textValue else { return nil }
            return LoadedComponent(familyID: f.id, definitionID: id, loadedVersion: f.params[ComponentKit.versionParam]?.intValue ?? 1,
                                   libraryVersion: catalog.definition(id: id)?.version)
        }
    }

    /// Reloads a component family from its newer definition (Reload Family, keeping the document's values). Types the
    /// definition renamed are renamed first, so their instances keep them.
    public static func upgrade(_ fid: ElementID, to d: ComponentDefinition, in tx: TransactionContext) {
        for t in tx.model.elements(.elementTypes) where t.typeData?.familyID == fid {
            if let new = d.renamedTypes[t.name], !tx.model.elements(.elementTypes).contains(where: { $0.typeData?.familyID == fid && $0.name == new }) {
                tx.update(t.id) { $0.name = new }
            }
        }
        FamilyProjectLoader.load(d.family, replacing: fid, mode: .keepProjectValues, in: tx)
        stamp(d, family: fid, in: tx)
    }

    /// Upgrades every outdated component family; returns how many.
    @discardableResult
    public static func upgradeAll(in tx: TransactionContext, catalog: ComponentCatalog = .current) -> Int {
        var n = 0
        for l in loaded(tx.model, catalog: catalog) where l.isOutdated {
            guard let d = catalog.definition(id: l.definitionID) else { continue }
            upgrade(l.familyID, to: d, in: tx)
            n += 1
        }
        return n
    }
}
