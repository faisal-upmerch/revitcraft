import Foundation
import ArcusGeometry
import ArcusCalc

/// Installs the unit-aware standard content (materials, wall/floor/roof/ceiling types, door, window and column
/// families) into new projects, and loads what is missing into existing ones.
///
/// Imperial projects get imperial names and nominal sizes; metric projects get metric ones. In imperial projects the
/// base template's metric-named types are converted in place to their imperial equivalents, and
/// `ProjectTemplates.Ids` keeps the base keys pointing at them (so code that looks template content up by key works in
/// both systems) alongside keys for the new names.
public enum StandardContent {
    /// Called at the end of `ProjectTemplates.populate`.
    public static func populate(_ tx: TransactionContext, ids: inout ProjectTemplates.Ids, kind: ProjectTemplateKind, units: UnitsSettings) {
        let installer = Installer(tx: tx, ids: ids)
        let system = units.system
        for m in MaterialLibrary.newProjectSet { _ = installer.material(m.name) }
        if system == .imperial { installer.convertBaseToImperial(residential: kind == .residential) }
        for spec in BuildingTypesLibrary.assemblies(system) { installer.assembly(spec) }
        for entry in OpeningLibrary.doors(system) + OpeningLibrary.windows(system) {
            installer.family(entry, replaceTypes: system == .imperial)
        }
        for entry in ColumnLibrary.families(system) { installer.family(entry, replaceTypes: false) }
        if system == .imperial {
            installer.aliasImperialFamilyTypes()
            installer.useImperialSheetsAndScales()
        }
        ids = installer.ids
    }

    /// Adds the standard types for the model's unit system that the project doesn't have yet (by name), with the
    /// materials they use. Existing types, families and materials are never changed. Returns the number of types added.
    @discardableResult
    public static func loadMissing(into tx: TransactionContext) -> Int {
        let system = tx.model.units.system
        let before = tx.model.elements(.elementTypes).count
        let installer = Installer(tx: tx, ids: ProjectTemplates.Ids())
        for spec in BuildingTypesLibrary.assemblies(system) { installer.assembly(spec) }
        for entry in OpeningLibrary.doors(system) + OpeningLibrary.windows(system) + ColumnLibrary.families(system) {
            installer.family(entry, replaceTypes: false)
        }
        return tx.model.elements(.elementTypes).count - before
    }

    /// Adds library materials by name, skipping names the project already has. Returns the ids of the added materials.
    @discardableResult
    public static func addMaterials(_ names: [String], to tx: TransactionContext) -> [ElementID] {
        let installer = Installer(tx: tx, ids: ProjectTemplates.Ids())
        var added: [ElementID] = []
        for n in names where tx.model.material(named: n) == nil {
            if let id = installer.material(n) { added.append(id) }
        }
        return added
    }

    /// Base template type names (metric) → imperial replacement name and parameter values, for non-assembly system types.
    static let imperialSystemTypes: [(String, String, [String: Double])] = {
        let i = 0.0254
        return [
            ("Monolithic - 175 max riser", "Monolithic - 7\" max riser", ["stair.maxRiser": 7 * i, "stair.minTread": 11 * i, "stair.treadThickness": 1.5 * i, "stair.waist": 6 * i]),
            ("Residential - 190 max riser", "Residential - 7 3/4\" max riser", ["stair.maxRiser": 7.75 * i, "stair.minTread": 10 * i, "stair.treadThickness": 1.5 * i, "stair.waist": 6 * i]),
            ("Guard - 1100mm", "Guard - 42\"", ["railing.height": 42 * i, "railing.balusterSpacing": 4 * i, "railing.balusterSize": 0.75 * i, "railing.railSize": 2 * i]),
            ("Handrail - 900mm", "Handrail - 36\"", ["railing.height": 36 * i, "railing.balusterSpacing": 32 * i, "railing.balusterSize": 1.25 * i, "railing.railSize": 1.75 * i]),
            ("Concrete Column 400 x 400", "Concrete Column 16\" x 16\"", ["column.width": 16 * i, "column.depth": 16 * i]),
            ("Concrete Column Round 350", "Concrete Column Round 14\"", ["column.diameter": 14 * i]),
            ("Timber Post 150 x 150", "Wood Post 6x6", ["column.width": 5.5 * i, "column.depth": 5.5 * i]),
            ("Steel Column 200 x 200", "Steel Column 8\" x 8\"", ["column.width": 8 * i, "column.depth": 8 * i]),
            ("Steel Beam 200 x 400", "Steel Beam 8\" x 16\"", ["beam.width": 8 * i, "beam.depth": 16 * i]),
            ("Concrete Beam 300 x 500", "Concrete Beam 12\" x 20\"", ["beam.width": 12 * i, "beam.depth": 20 * i]),
            ("Glulam 140 x 360", "Glulam 5 1/2\" x 15\"", ["beam.width": 5.5 * i, "beam.depth": 15 * i]),
            ("2.5mm Arial", "3/32\" Arial", ["text.size": 3.0 / 32 * i]),
            ("3.5mm Arial", "1/8\" Arial", ["text.size": 0.125 * i]),
            ("5mm Arial Bold", "3/16\" Arial Bold", ["text.size": 3.0 / 16 * i]),
            ("Linear - 2.5mm Arial", "Linear - 3/32\" Arial", ["dimension.textSize": 3.0 / 32 * i]),
        ]
    }()

    /// Base template family types (metric) → the imperial type that takes their key in imperial projects.
    static let imperialFamilyTypes: [String: String] = [
        "Door - Single Flush: 900 x 2100": "Door - Single Flush: 36\" x 84\"",
        "Door - Single Flush: 820 x 2040": "Door - Single Flush: 32\" x 80\"",
        "Door - Single Flush: 1000 x 2100": "Door - Single Flush: 42\" x 84\"",
        "Door - Double Flush: 1800 x 2100": "Door - Double Flush: 72\" x 84\"",
        "Door - Double Flush: 1500 x 2100": "Door - Double Flush: 60\" x 84\"",
        "Window - Casement: 1200 x 1500": "Window - Casement: 48\" x 60\"",
        "Window - Casement: 600 x 1200": "Window - Casement: 24\" x 48\"",
        "Window - Casement: 1800 x 1500": "Window - Casement: 72\" x 60\"",
        "Window - Casement: 2400 x 2100 Glazed Wall": "Window - Casement: 96\" x 84\" Glazed Wall",
    ]

    final class Installer {
        let tx: TransactionContext
        var ids: ProjectTemplates.Ids
        var materials: [String: ElementID] = [:]
        var fillPatterns: [String: ElementID] = [:]

        init(tx: TransactionContext, ids: ProjectTemplates.Ids) {
            self.tx = tx
            self.ids = ids
            for m in tx.model.elements(.materials) where materials[m.name] == nil { materials[m.name] = m.id }
            for p in tx.model.elements(.fillPatterns) where fillPatterns[p.name] == nil { fillPatterns[p.name] = p.id }
        }

        /// The project material with this name, added from the library when missing (nil if the library doesn't have it).
        func material(_ name: String) -> ElementID? {
            if let id = materials[name] { return id }
            guard let lib = MaterialLibrary.named(name) else { return nil }
            let id = tx.create(.materials, name: name, data: .material(lib.materialData(fillPatterns: fillPatterns)))
            materials[name] = id
            ids.materials[name] = id
            return id
        }

        func resolved(_ spec: AssemblySpec) -> CompoundAssembly {
            CompoundAssembly(layers: spec.layers.map { AssemblyLayer(function: $0.function, materialID: material($0.material), thickness: $0.thickness) })
        }

        func existingType(_ name: String, _ category: Category) -> Element? {
            tx.model.elements(.elementTypes).first { $0.name == name && $0.typeData?.instanceCategory == category }
        }

        func record(_ spec: AssemblySpec, _ id: ElementID) {
            switch spec.category {
            case .walls: ids.wallTypes[spec.name] = id
            case .floors: ids.floorTypes[spec.name] = id
            case .roofs: ids.roofTypes[spec.name] = id
            case .ceilings: ids.ceilingTypes[spec.name] = id
            default: ids.systemTypes[spec.name] = id
            }
        }

        /// Creates a library assembly type unless a type of that name and category exists.
        func assembly(_ spec: AssemblySpec) {
            if let existing = existingType(spec.name, spec.category) { record(spec, existing.id); return }
            var td = TypeData(instanceCategory: spec.category, systemFamily: spec.systemFamily, familyName: spec.familyName, assembly: resolved(spec))
            if let fn = spec.function { td.params[ParameterID("type.function")] = .text(fn) }
            if spec.category == .walls {
                let n = tx.model.elements(.elementTypes).filter { $0.typeData?.instanceCategory == .walls }.count
                td.params[ParameterID("type.mark")] = .text(String(spec.name.prefix(1)) + "\(n + 1)")
            }
            if let fr = spec.fireRating { td.params[ParameterID("type.fireRating")] = .text(fr) }
            record(spec, tx.create(.elementTypes, name: spec.name, data: .type(td)))
        }

        /// Imperial projects: the base template's metric types become their imperial equivalents in place.
        func convertBaseToImperial(residential: Bool) {
            let specs = Dictionary(BuildingTypesLibrary.assemblies(.imperial).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            for (metricName, imperialName) in BuildingTypesLibrary.imperialEquivalents {
                guard let spec = specs[imperialName], let e = existingType(metricName, spec.category) else { continue }
                tx.update(e.id) { el in
                    el.name = imperialName
                    el.typeData?.assembly = resolved(spec)
                    if let fn = spec.function { el.typeData?.params[ParameterID("type.function")] = .text(fn) }
                    if let fr = spec.fireRating { el.typeData?.params[ParameterID("type.fireRating")] = .text(fr) }
                }
                record(spec, e.id)
            }
            for (metricName, imperialName, values) in StandardContent.imperialSystemTypes {
                guard let e = tx.model.elements(.elementTypes).first(where: { $0.name == metricName }) else { continue }
                tx.update(e.id) { el in
                    el.name = imperialName
                    for (k, v) in values { el.typeData?.params[ParameterID(k)] = .double(v) }
                }
                ids.systemTypes[imperialName] = e.id
            }
        }

        /// Next free numeric mark with a prefix ("D12") among the types of a category.
        func nextMark(_ prefix: String, _ category: Category) -> String {
            var highest = 0
            for t in tx.model.elements(.elementTypes) where t.typeData?.instanceCategory == category {
                guard let m = t.typeData?.params[ParameterID("type.mark")]?.textValue, m.hasPrefix(prefix), let n = Int(m.dropFirst(prefix.count)) else { continue }
                highest = max(highest, n)
            }
            return "\(prefix)\(highest + 1)"
        }

        /// Loads a library family (or updates the project family of that name): creates the types it lacks. With
        /// `replaceTypes`, the family's type list becomes the library's and project types the library doesn't have are
        /// removed (only used while building a new project, before anything is placed).
        func family(_ entry: OpeningLibrary.Entry, replaceTypes: Bool) {
            let lib = entry.family
            let category: Category = lib.template == .tag ? .tags : lib.template.category
            let fid: ElementID
            var def: FamilyDefinition
            var inherited: [ParameterID: ParamValue] = [:]
            if let existing = tx.model.family(named: lib.name), let current = existing.family {
                fid = existing.id
                def = current
                let types = tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
                // New types of an existing family take the materials its first type uses.
                if let first = types.first?.typeData {
                    for p in def.parameters { if case .elementRef = p.type, let v = first.params[Parameters.familyParamID(p.name)] { inherited[Parameters.familyParamID(p.name)] = v } }
                }
                if replaceTypes {
                    def.types = lib.types
                    for t in types where lib.type(named: t.name) == nil {
                        tx.delete(t.id)
                        ids.familyTypes.removeValue(forKey: "\(lib.name): \(t.name)")
                    }
                } else {
                    for t in lib.types where def.type(named: t.name) == nil { def.types.append(t) }
                }
                let updated = def
                tx.update(fid) { $0.family = updated }
            } else {
                def = lib
                fid = tx.create(.families, name: lib.name, data: .family(lib))
            }
            ids.families[lib.name] = fid
            let present = Set(tx.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }.map(\.name))
            for t in lib.types where !present.contains(t.name) {
                var params: [ParameterID: ParamValue] = [:]
                for (k, v) in t.values where def.parameter(named: k) != nil { params[Parameters.familyParamID(k)] = v }
                for (p, name) in entry.materials where def.parameter(named: p) != nil {
                    params[Parameters.familyParamID(p)] = inherited[Parameters.familyParamID(p)] ?? material(name).map { .ref($0) }
                }
                if lib.template == .column || lib.template == .structuralColumn, let m = entry.materials["Material"].flatMap(material) {
                    params[ParameterID("type.material")] = .ref(m)
                }
                if lib.template == .door { params[ParameterID("type.mark")] = .text(nextMark("D", category)) }
                if lib.template == .window { params[ParameterID("type.mark")] = .text(nextMark("W", category)) }
                if let fr = entry.fireRatings[t.name], !fr.isEmpty { params[ParameterID("type.fireRating")] = .text(fr) }
                let tid = tx.create(.elementTypes, name: t.name, data: .type(TypeData(instanceCategory: category, familyID: fid, familyName: lib.name, params: params)))
                ids.familyTypes["\(lib.name): \(t.name)"] = tid
            }
            for t in tx.model.elements(.elementTypes) where t.typeData?.familyID == fid { ids.familyTypes["\(lib.name): \(t.name)"] = t.id }
        }

        /// Imperial projects: the base template's metric family-type keys point at their imperial equivalents.
        func aliasImperialFamilyTypes() {
            for (metricKey, imperialKey) in StandardContent.imperialFamilyTypes where ids.familyTypes[metricKey] == nil {
                if let id = ids.familyTypes[imperialKey] { ids.familyTypes[metricKey] = id }
            }
        }

        /// Imperial projects: ARCH D sheets and imperial view scales (1:100 → 1/8" = 1'-0", 1:50 → 1/4" = 1'-0").
        func useImperialSheetsAndScales() {
            func imperial(_ s: Int) -> Int { s == 100 ? 96 : s == 50 ? 48 : s == 200 ? 192 : s == 20 ? 24 : s }
            for v in tx.model.elements(.views) {
                guard let s = v.view?.scale, imperial(s) != s else { continue }
                tx.update(v.id) { $0.view?.scale = imperial(s) }
            }
            for t in tx.model.elements(.viewTemplates) {
                guard let s = t.viewTemplate?.scale, imperial(s) != s else { continue }
                tx.update(t.id) { $0.viewTemplate?.scale = imperial(s) }
            }
            let archD = ids.titleBlocks["ARCH D Title Block"]
            for s in tx.model.elements(.sheets) where s.sheet?.paper != .archD {
                tx.update(s.id) { el in
                    el.sheet?.paper = .archD
                    if let archD { el.sheet?.titleBlockTypeID = archD }
                }
            }
        }
    }
}
