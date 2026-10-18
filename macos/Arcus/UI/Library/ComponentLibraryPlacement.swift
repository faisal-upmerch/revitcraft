import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// W2-LIB: opening the component library and placing its items.
extension DocumentState {
    /// Opens the component library browser, optionally limited to some categories (for example
    /// `ComponentLibrary.siteCategories` or `ComponentLibrary.parkingCategories` for site and parking tools).
    func showComponentLibrary(categories: [Category] = []) {
        presented = .componentLibrary(categories)
    }

    /// Makes a library type available in the project, loading its family on first use. Returns the type element.
    @discardableResult
    func loadLibraryType(_ item: ComponentLibraryItem, typeName: String) -> ElementID? {
        if let t = ComponentLibraryLoader.loadedType(item, typeName: typeName, model) { return t }
        var created: ElementID?
        session.perform("Load \(item.name): \(typeName)") { tx in created = ComponentLibraryLoader.load(item, typeName: typeName, in: tx) }
        if created == nil { show("\(item.name) could not be loaded: \(session.lastError?.message ?? "unknown error")", error: true) }
        return created
    }

    /// Loads (if needed) a library type, makes it the current component type and starts the Component tool.
    @discardableResult
    func placeFromLibrary(_ item: ComponentLibraryItem, typeName: String, startTool: Bool = true) -> ElementID? {
        guard let tid = loadLibraryType(item, typeName: typeName) else { return nil }
        currentTypes[item.category] = tid
        currentTypes[.furniture] = tid
        for c in toolContexts.values { c.currentTypes = currentTypes }
        LibraryRecents.note(item.name)
        guard startTool else {
            show("Loaded \(item.name): \(typeName).")
            return tid
        }
        presented = nil
        let router = CommandRouter(state: self)
        if let reason = router.disabledReason(.component) {
            show("Loaded \(item.name): \(typeName). \(reason)")
        } else {
            router.run(.component)
        }
        toolChangedState()
        return tid
    }
}

/// Recently placed library families (per user, local only).
enum LibraryRecents {
    static let key = "ArcusComponentLibraryRecent"
    static var names: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func note(_ name: String) {
        var list = names.filter { $0 != name }
        list.insert(name, at: 0)
        UserDefaults.standard.set(Array(list.prefix(24)), forKey: key)
    }
}
