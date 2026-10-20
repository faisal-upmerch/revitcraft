import Foundation
import ArcusGeometry

// COMP: the user's own components, kept apart from the built-ins (which are read-only: duplicate one to customise
// it). Each is a `.arcuscomponent` file (the definition as JSON) in the user library folder. They come from Duplicate
// (a variant of a built-in), Save Selection as Component (Furniture mode) and the Family Editor's Furniture Hardware /
// Component template.

public enum ComponentUserLibrary {
    public static let fileExtension = "arcuscomponent"

    /// The user library folder (Application Support/Arcus/Components).
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Arcus/Components", isDirectory: true)
    }

    /// Every readable component file in a folder, by name (unreadable files are skipped).
    public static func load(from dir: URL = defaultDirectory) -> [ComponentDefinition] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == fileExtension }.compactMap { u in
            guard let data = try? Data(contentsOf: u), var d = try? JSONDecoder().decode(ComponentDefinition.self, from: data) else { return nil }
            d.isUserComponent = true
            return d
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func url(_ d: ComponentDefinition, _ dir: URL) -> URL {
        let safe = d.id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "-" }.joined()
        return dir.appendingPathComponent("\(safe).\(fileExtension)")
    }

    /// Writes a user component (atomically).
    public static func save(_ d: ComponentDefinition, to dir: URL = defaultDirectory) throws {
        var x = d
        x.isUserComponent = true
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(x).write(to: url(x, dir), options: .atomic)
    }

    /// Removes a user component's file (documents that use it keep their copy).
    public static func remove(_ d: ComponentDefinition, from dir: URL = defaultDirectory) throws {
        let u = url(d, dir)
        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
    }

    /// A user copy of a component to customise: a new id and family name, marked as a variant of the original.
    public static func duplicate(_ d: ComponentDefinition, name: String? = nil, existing: [String] = []) -> ComponentDefinition {
        var x = d
        var n = name ?? "\(d.name) (Custom)"
        var k = 2
        while existing.contains(n) { n = "\(name ?? d.name + " (Custom)") \(k)"; k += 1 }
        x.family.name = n
        x.family.furnitureSource = d.family.furnitureSource
        x.id = "user.\(UUID().uuidString.lowercased())"
        x.variantOf = d.variantOf ?? d.id
        x.isUserComponent = true
        x.version = 1
        x.renamedTypes = [:]
        x.presets = d.presets.map { var p = $0; p.definitionID = x.id; return p }
        return x
    }

    /// Save Selection as Component: the selected parts, fronts and their hardware compiled into a component family
    /// (plan frame, placed on the level or on a part), with the piece's Width/Depth/Height and types.
    public static func fromSelection(_ ids: [ElementID], in m: BIMModel, name: String, category: ComponentCategory, subcategory: String,
                                     tags: [String] = []) throws(TransactionError) -> ComponentDefinition {
        // A component family made in the Family Editor (New Component) and loaded: saved as it is, face-based.
        if ids.count == 1, let e = m[ids[0]], e.category == .furnitureHardware, !e.isType, ComponentDocument.definition(of: e, m) == nil,
           let tid = e.typeID, let fid = m[tid]?.typeData?.familyID, var fam = m[fid]?.family {
            fam.name = name
            var b = ComponentBuilder(wrapping: fam, category, subcategory, id: "user.\(UUID().uuidString.lowercased())", frame: .face)
            b.definition.tags = tags.isEmpty ? ComponentSearchIndex.tokens(name).filter { $0.count > 2 } : tags
            b.definition.isUserComponent = true
            b.host(ComponentHostKind.fronts + ComponentHostKind.carcass, faces: [.front, .inside, .top], align: .center)
            return b.build()
        }
        guard m.isFurniture else { throw TransactionError("Save Selection as Component works in Furniture documents.") }
        let picked = Set(ids)
        let kinds: Set<Category> = [.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureForms, .furnitureFronts, .furnitureHardware,
                                    .furnitureBays, .furnitureBaySeparators]
        guard ids.contains(where: { m[$0].map { kinds.contains($0.category) } ?? false }) else { throw TransactionError("Select parts, fronts or hardware.") }
        // Keep the selection, the bays of selected fronts and everything hosted by what's kept.
        var keep = picked
        for id in picked { if let e = m[id], e.furnitureFront != nil, let b = e.hostID { keep.insert(b) } }
        var changed = true
        while changed {
            changed = false
            for e in kinds.flatMap({ m.elements($0) }) where !keep.contains(e.id) && (e.hostID.map(keep.contains) ?? false) {
                keep.insert(e.id); changed = true
            }
        }
        let tx = TransactionContext(model: m, name: "Save Selection as Component")
        for e in kinds.flatMap({ tx.model.elements($0) }) where !e.isType && !keep.contains(e.id) {
            if tx.model[e.id] != nil { tx.delete(e.id) }
        }
        let trimmed: BIMModel
        do { trimmed = try tx.commit().model } catch { throw error }
        var fam = FurnitureCompiler.family(from: trimmed)
        fam.name = name
        fam.template = .furnitureHardware
        fam.manufacturer = "Generic"
        fam.description = "\(name) (saved from a selection)."
        var b = ComponentBuilder(wrapping: fam, category, subcategory, id: "user.\(UUID().uuidString.lowercased())", frame: .plan)
        b.definition.tags = tags.isEmpty ? ComponentSearchIndex.tokens(name).filter { $0.count > 2 } : tags
        b.definition.isUserComponent = true
        b.host([.floor, .top, .shelf, .bottom], faces: [.top], align: .center)
        if b.definition.types.isEmpty {
            b.definition.types = [ComponentType(name: name, values: [:], cost: 0, model: "", sku: "", description: fam.description)]
        }
        let cost = FurnitureFabrication.hardware(trimmed).reduce(0) { $0 + $1.totalCost }
        for k in b.definition.types.indices {
            b.definition.types[k].cost = (cost * 100).rounded() / 100
            b.definition.types[k].model = "USER-\(k + 1)"
            b.definition.types[k].sku = "USER-\(k + 1)"
        }
        b.visibleAt = [.coarse, .medium, .fine]
        return b.build()
    }

    /// The Family Editor's Furniture Hardware / Component template: a face-based family with Length/Width/Projection,
    /// a finish slot and a box, ready for the user's own forms, parameters and types.
    public static func template(name: String = "Component") -> ComponentDefinition {
        var b = ComponentBuilder(name, .decorative, "Custom", "A custom component.", id: "user.\(UUID().uuidString.lowercased())")
        b.tags("custom")
        b.length("Length", ComponentKit.inch(4)); b.length("Width", ComponentKit.inch(1)); b.length("Projection", ComponentKit.inch(1))
        b.material("Finish Material", .steel)
        b.host(ComponentHostKind.fronts + ComponentHostKind.carcass, faces: [.front, .inside, .top], align: .center)
        b.box("Body", x: ("-Length / 2", "Length / 2"), y: ("-Width / 2", "Width / 2"), z: (CX.zero, "Projection"))
        b.type("Standard", cost: 0, model: "USER-1")
        var d = b.build()
        d.isUserComponent = true
        return d
    }
}
