import Foundation
import ArcusGeometry

// COMP: the registry of built-in Furniture components: FM5's 17 hardware families (ComponentLibrary+FM5.swift) and
// the four category groups (ComponentLibrary+A/B/C/D.swift). A group definition with the same family name as an FM5
// family replaces it (an upgrade keeps the FM5 parameters and types, so existing files keep working).

extension ComponentLibrary {
    /// Every built-in Furniture component, by category then subcategory then name; ids are unique.
    public static let furniture: [ComponentDefinition] = buildFurniture()

    private static let furnitureByID: [String: ComponentDefinition] = Dictionary(furniture.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let furnitureByName: [String: ComponentDefinition] = Dictionary(furniture.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    /// A built-in component by id.
    public static func component(id: String) -> ComponentDefinition? { furnitureByID[id] }
    /// A built-in component by family name.
    public static func component(named name: String) -> ComponentDefinition? { furnitureByName[name] }

    /// The group definitions, before merging (for the category agents' tests).
    static var groupDefinitions: [ComponentDefinition] { groupA + groupB + groupC + groupD }

    static func buildFurniture() -> [ComponentDefinition] {
        var byName: [String: ComponentDefinition] = [:]
        var order: [String] = []
        for d in fm5Components + groupDefinitions {
            if byName[d.name] == nil { order.append(d.name) }
            if let old = byName[d.name] {
                byName[d.name] = merged(upgrade: d, over: old)
            } else {
                byName[d.name] = d
            }
        }
        var seen: Set<String> = []
        var out: [ComponentDefinition] = []
        for n in order {
            guard var d = byName[n] else { continue }
            // Ids stay unique even if two groups pick the same slug.
            var id = d.id, k = 2
            while seen.contains(id) { id = "\(d.id)-\(k)"; k += 1 }
            d.id = id
            seen.insert(id)
            out.append(d)
        }
        return out.sorted { a, b in
            if a.category != b.category { return a.category < b.category }
            if a.subcategory != b.subcategory { return a.subcategory.localizedStandardCompare(b.subcategory) == .orderedAscending }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// An upgraded FM5 family: the group's definition, keeping every FM5 type it dropped and the FM5 id.
    static func merged(upgrade d: ComponentDefinition, over old: ComponentDefinition) -> ComponentDefinition {
        var out = d
        out.id = old.id
        for t in old.types where out.type(named: t.name) == nil {
            out.types.append(t)
            out.family.types.append(FamilyTypeDefinition(name: t.name, values: t.values))
        }
        out.tags = Array(NSOrderedSet(array: old.tags + d.tags)) as? [String] ?? d.tags
        out.aliases = Array(NSOrderedSet(array: old.aliases + d.aliases)) as? [String] ?? d.aliases
        out.hardwareKind = d.hardwareKind ?? old.hardwareKind
        return out
    }
}
