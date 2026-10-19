import AppKit
import ArcusDomain

// HOME: Home ▸ Furniture ▸ Create calls this. FM3 replaces the body with Furniture documents (Docs/FurnitureMode.md §3);
// keep the signature.

extension AppDelegate {
    /// Opens a new untitled Furniture document named `name` in `category` (`.furniture` or `.casework`), started from
    /// the library piece at `template`, or blank when `template` is nil.
    @MainActor
    func newFurniture(name: String, category: FamilyTemplate, template: URL?) {
        let alert = NSAlert()
        alert.messageText = "Furniture mode is coming in this build"
        alert.informativeText = "“\(name)” (\(category.rawValue)) will open as a Furniture document. Until then, start an Architectural Project or a Family."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
