import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// COMP: the Components panel's state. One per document window (search, category, filters, selection, preview); the
// user's favorites, recently used components, recent searches and saved presets are shared by every window and kept in
// the user defaults; the user library (custom components) is read from its folder and becomes part of the catalog.

/// Where the panel shows its results.
enum ComponentSection: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", recent = "Recent", mine = "My Components"
    var id: String { rawValue }
}

enum ComponentSort: String, CaseIterable, Identifiable {
    case relevance = "Relevance", name = "Name", category = "Category", cost = "Cost"
    var id: String { rawValue }
}

nonisolated enum ComponentPreviewMode: String, CaseIterable, Identifiable, Sendable {
    case threeD = "3D", plan = "2D"
    var id: String { rawValue }
}

/// Preview camera presets.
nonisolated enum ComponentPreviewView: String, CaseIterable, Identifiable, Sendable {
    case iso = "Iso", front = "Front", side = "Side", top = "Top"
    var id: String { rawValue }
    var angles: (yaw: Double, pitch: Double) {
        switch self {
        case .iso: (ShadedFamilyRendererAngles.yaw, ShadedFamilyRendererAngles.pitch)
        case .front: (0, 0.0001)
        case .side: (-Double.pi / 2, 0.0001)
        case .top: (0, Double.pi / 2 - 0.0001)
        }
    }
}

nonisolated enum ShadedFamilyRendererAngles {
    static let yaw = -35.0 * Double.pi / 180
    static let pitch = 27.0 * Double.pi / 180
}

/// Settings shared by every window, persisted in the user defaults.
@MainActor
@Observable
final class ComponentLibraryStore {
    static let shared = ComponentLibraryStore()

    private(set) var favorites: [String]
    private(set) var recentlyUsed: [String]
    private(set) var recentSearches: ComponentRecentSearches
    private(set) var userPresets: [ComponentPreset]
    private(set) var userComponents: [ComponentDefinition] = []
    /// Bumped when the catalog changes (user library edits), so search indexes rebuild.
    private(set) var catalogRevision = 0
    @ObservationIgnored private var cachedIndex: (Int, ComponentSearchIndex)?
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var directory: URL

    init(defaults: UserDefaults = .standard, directory: URL = ComponentUserLibrary.defaultDirectory, loadUser: Bool = true) {
        self.defaults = defaults
        self.directory = directory
        favorites = defaults.stringArray(forKey: "comp.favorites") ?? []
        recentlyUsed = defaults.stringArray(forKey: "comp.recentlyUsed") ?? []
        recentSearches = ComponentRecentSearches(defaults.stringArray(forKey: "comp.recentSearches") ?? [])
        if let d = defaults.data(forKey: "comp.presets"), let p = try? JSONDecoder().decode([ComponentPreset].self, from: d) { userPresets = p } else { userPresets = [] }
        if loadUser { reloadUserLibrary() }
    }

    var catalog: ComponentCatalog { ComponentCatalog(builtIn: ComponentLibrary.furniture, user: userComponents) }

    var index: ComponentSearchIndex {
        if let c = cachedIndex, c.0 == catalogRevision { return c.1 }
        let i = ComponentSearchIndex(catalog.all)
        cachedIndex = (catalogRevision, i)
        return i
    }

    func reloadUserLibrary() {
        userComponents = ComponentUserLibrary.load(from: directory)
        ComponentCatalog.current = catalog
        catalogRevision += 1
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if let k = favorites.firstIndex(of: id) { favorites.remove(at: k) } else { favorites.insert(id, at: 0) }
        defaults.set(favorites, forKey: "comp.favorites")
    }

    func used(_ id: String) {
        recentlyUsed.removeAll { $0 == id }
        recentlyUsed.insert(id, at: 0)
        if recentlyUsed.count > 24 { recentlyUsed.removeLast(recentlyUsed.count - 24) }
        defaults.set(recentlyUsed, forKey: "comp.recentlyUsed")
    }

    func searched(_ q: String) {
        recentSearches.add(q)
        defaults.set(recentSearches.items, forKey: "comp.recentSearches")
    }

    func presets(for d: ComponentDefinition) -> [ComponentPreset] { d.presets + userPresets.filter { $0.definitionID == d.id } }

    func savePreset(_ p: ComponentPreset) {
        userPresets.removeAll { $0.id == p.id }
        userPresets.append(p)
        if let d = try? JSONEncoder().encode(userPresets) { defaults.set(d, forKey: "comp.presets") }
    }

    func addUserComponent(_ d: ComponentDefinition) throws {
        try ComponentUserLibrary.save(d, to: directory)
        reloadUserLibrary()
    }

    func removeUserComponent(_ d: ComponentDefinition) throws {
        try ComponentUserLibrary.remove(d, from: directory)
        reloadUserLibrary()
    }
}

/// One document window's panel state.
@MainActor
@Observable
final class ComponentPanelModel {
    private static var models: [ObjectIdentifier: ComponentPanelModel] = [:]

    /// The panel model of a document window.
    static func of(_ state: DocumentState) -> ComponentPanelModel {
        let k = ObjectIdentifier(state)
        if let m = models[k] { return m }
        let m = ComponentPanelModel()
        models[k] = m
        return m
    }
    static func forget(_ state: DocumentState) { models.removeValue(forKey: ObjectIdentifier(state)) }

    /// Docked in the window (the Components button toggles it).
    var isShown = false
    var query = ""
    var section: ComponentSection = .all
    var category: ComponentCategory?
    var subcategory: String?
    var host: ComponentHostKind?
    var material: String?
    var sort: ComponentSort = .relevance
    var gridView = true
    var selectedID: String?
    var typeName: String?
    var presetName: String?
    var previewMode: ComponentPreviewMode = .threeD
    var previewView: ComponentPreviewView = .iso
    var yaw = ShadedFamilyRendererAngles.yaw
    var pitch = ShadedFamilyRendererAngles.pitch
    var zoom = 1.0
    var pan = CGSize.zero

    let store: ComponentLibraryStore
    init(store: ComponentLibraryStore = .shared) { self.store = store }

    var filter: ComponentSearchFilter {
        ComponentSearchFilter(category: category, subcategory: subcategory, host: host, material: material, userOnly: section == .mine)
    }

    /// The results for the current search, section, filters and sort.
    var results: [ComponentSearchResult] {
        var r = store.index.search(query, filter: filter)
        switch section {
        case .favorites: r = r.filter { store.isFavorite($0.definition.id) }
        case .recent:
            let order = Dictionary(uniqueKeysWithValues: store.recentlyUsed.enumerated().map { ($1, $0) })
            r = r.filter { order[$0.definition.id] != nil }.sorted { order[$0.definition.id]! < order[$1.definition.id]! }
            return r
        default: break
        }
        switch sort {
        case .relevance: if query.isEmpty { r.sort { ($0.definition.category, $0.definition.name) < ($1.definition.category, $1.definition.name) } }
        case .name: r.sort { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending }
        case .category: r.sort { ($0.definition.category.rawValue, $0.definition.subcategory, $0.definition.name) < ($1.definition.category.rawValue, $1.definition.subcategory, $1.definition.name) }
        case .cost: r.sort { ($0.definition.defaultType?.cost ?? 0) < ($1.definition.defaultType?.cost ?? 0) }
        }
        return r
    }

    /// Subcategories of the chosen category.
    var subcategories: [String] {
        guard let c = category else { return [] }
        var out: [String] = []
        for d in store.catalog.all where d.category == c && !out.contains(d.subcategory) { out.append(d.subcategory) }
        return out.sorted()
    }

    func count(_ c: ComponentCategory) -> Int { store.catalog.all.filter { $0.category == c }.count }

    var selected: ComponentDefinition? { selectedID.flatMap { store.catalog.definition(id: $0) } }
    var selectedType: String? { typeName ?? selected?.defaultType?.name }

    func select(_ r: ComponentSearchResult) {
        selectedID = r.definition.id
        typeName = r.typeName ?? r.definition.defaultType?.name
        presetName = nil
    }

    func select(id: String, type: String? = nil) {
        selectedID = id
        typeName = type ?? store.catalog.definition(id: id)?.defaultType?.name
        presetName = nil
    }

    func setPreview(_ v: ComponentPreviewView) {
        previewView = v
        (yaw, pitch) = v.angles
        zoom = 1; pan = .zero
    }
    func fit() { zoom = 1; pan = .zero }

    /// Instance values of the chosen preset.
    var presetValues: [String: ParamValue] {
        guard let d = selected, let n = presetName, let p = store.presets(for: d).first(where: { $0.name == n }) else { return [:] }
        return p.values
    }
}
