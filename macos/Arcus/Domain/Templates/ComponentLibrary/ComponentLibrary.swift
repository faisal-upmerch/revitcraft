import Foundation
import ArcusGeometry
import ArcusCalc

/// Where a library item is typical. `global` items suit any region.
public enum LibraryRegion: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case global = "Global", usa = "USA", uk = "UK", europe = "Europe", india = "India", asia = "Asia"
    public var id: String { rawValue }
    public var displayName: String { self == .global ? "Global" : rawValue }
}

/// The measurement system a type's name and sizes are written in.
public enum LibrarySizeSystem: String, Codable, Sendable, Hashable {
    /// Millimeters / meters ("1600 x 2000").
    case metric
    /// Feet and inches ("60\" x 80\"").
    case imperial
    /// Named without units ("Adult", "Compact"): offered in every project.
    case neutral

    public func suits(_ system: UnitSystem) -> Bool {
        switch self {
        case .neutral: true
        case .metric: system == .metric
        case .imperial: system == .imperial
        }
    }
}

/// A project material a library family uses by default (created by name when the family is first loaded).
public struct ComponentMaterial: Hashable, Sendable {
    public var name: String
    public var materialClass: MaterialClass
    public var color: RGBColor
    public var transparency: Double
    public var data: MaterialData { MaterialData(materialClass: materialClass, color: color, transparency: transparency, description: "Component library default") }
}

/// One size of a library family.
public struct ComponentLibraryType: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var regions: [LibraryRegion]
    public var system: LibrarySizeSystem
    /// Nominal overall size in meters.
    public var width: Double
    public var depth: Double
    public var height: Double
}

/// A family in the built-in component library, with the metadata the library browser shows.
///
/// Items are plain data: nothing is added to a project until one of its types is placed or loaded
/// (`ComponentLibraryLoader`), and then only that family with the chosen type.
public struct ComponentLibraryItem: Sendable, Identifiable, Hashable {
    public var id: String { family.name }
    public var name: String { family.name }
    /// The family with every library type.
    public let family: FamilyDefinition
    public let category: Category
    /// Browser group within the category ("Living", "Bedroom", "Kitchen", "Trees", …).
    public let group: String
    public let regions: [LibraryRegion]
    public let keywords: [String]
    public let types: [ComponentLibraryType]
    /// Material parameter name → default material.
    public let materials: [String: ComponentMaterial]
    public var summary: String { family.description }

    public static func == (a: ComponentLibraryItem, b: ComponentLibraryItem) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// True when the item suits `region` (global items suit every region).
    public func isAvailable(in region: LibraryRegion?) -> Bool {
        guard let region, region != .global else { return true }
        return regions.contains(region) || regions.contains(.global)
    }

    /// Types offered for a project: the ones sized in its unit system (plus unit-neutral ones) and, when a region is
    /// chosen, typical of that region. Falls back to every type rather than offering none.
    public func types(for system: UnitSystem, region: LibraryRegion? = nil, showAll: Bool = false) -> [ComponentLibraryType] {
        guard !showAll else { return types }
        var list = types.filter { $0.system.suits(system) }
        if list.isEmpty { list = types }
        if let region, region != .global {
            let regional = list.filter { $0.regions.contains(region) || $0.regions.contains(.global) }
            if !regional.isEmpty { list = regional }
        }
        return list
    }

    /// The type the browser selects first for a project.
    public func defaultType(for system: UnitSystem, region: LibraryRegion? = nil) -> ComponentLibraryType {
        let list = types(for: system, region: region)
        return list.count > 1 ? list[list.count / 2 - (list.count % 2 == 0 ? 1 : 0)] : list.first ?? types[0]
    }

    /// Case-insensitive match on the name, category, group, keywords, regions and type names; every word must match.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return true }
        let hay = searchText
        return words.allSatisfy { hay.contains($0) }
    }

    var searchText: String {
        ([name, category.displayName, category.singularName, group, summary] + keywords + regions.map(\.rawValue) + types.map(\.name))
            .joined(separator: " ").lowercased()
    }
}

/// The built-in, original component library: furniture, casework, fixtures, lighting, equipment, planting,
/// entourage, site and parking families from several regions, with sizes in metric and imperial.
public enum ComponentLibrary {
    /// Every item, in browser order (by category, then group, then name).
    public static let items: [ComponentLibraryItem] = {
        let all = LibraryContent.all()
        let order = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) })
        return all.sorted { a, b in
            let ca = order[a.category] ?? 99, cb = order[b.category] ?? 99
            if ca != cb { return ca < cb }
            if a.group != b.group { return (groupOrder[a.group] ?? 99, a.group) < (groupOrder[b.group] ?? 99, b.group) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }()

    private static let byName: [String: ComponentLibraryItem] = Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    /// Library categories in browser order.
    public static let categories: [Category] = [
        .furniture, .casework, .specialtyEquipment, .plumbingFixtures, .lightingFixtures, .electricalFixtures, .mechanicalEquipment,
        .planting, .entourage, .site, .parking,
    ]
    /// Categories shown by the site entry points (Massing & Site).
    public static let siteCategories: [Category] = [.planting, .entourage, .site, .parking]
    /// Categories shown by parking entry points.
    public static let parkingCategories: [Category] = [.parking]

    static let groupOrder: [String: Int] = Dictionary(uniqueKeysWithValues: [
        "Living", "Dining", "Bedroom", "Kids", "Storage", "Office", "Hospitality", "Education", "Healthcare",
        "Kitchen", "Bath Vanities", "Appliances", "Laundry", "Electronics", "Bath Accessories", "Toilet Partitions",
        "Toilets", "Urinals", "Lavatories", "Baths & Showers", "Sinks", "Drains",
        "Recessed", "Ceiling", "Pendants", "Wall", "Linear & Track", "Lamps", "Exterior",
        "Power & Charging", "Air Conditioning", "Fans", "Heating & Hot Water",
        "Trees", "Palms", "Shrubs & Grasses", "Indoor Plants", "People", "Vehicles", "Bicycles",
        "Site Furniture", "Planters", "Utilities", "Signage", "Stalls", "Markings", "Signs", "Equipment",
    ].enumerated().map { ($1, $0) })

    public static func item(named name: String) -> ComponentLibraryItem? { byName[name] }

    /// Items in the given categories (all items when `categories` is empty) — the API site and parking tools use to
    /// open the browser on their own content.
    public static func items(in categories: [Category]) -> [ComponentLibraryItem] {
        categories.isEmpty ? items : items.filter { categories.contains($0.category) }
    }

    /// Items matching a search, optionally limited to categories, a group and a region.
    public static func search(_ query: String, categories: [Category] = [], group: String? = nil, region: LibraryRegion? = nil) -> [ComponentLibraryItem] {
        items(in: categories).filter { ($0.group == group || group == nil) && $0.isAvailable(in: region) && $0.matches(query) }
    }

    /// Groups of a category in browser order.
    public static func groups(in category: Category) -> [String] {
        var out: [String] = []
        for i in items where i.category == category && !out.contains(i.group) { out.append(i.group) }
        return out
    }

    public static var typeCount: Int { items.reduce(0) { $0 + $1.types.count } }
}
