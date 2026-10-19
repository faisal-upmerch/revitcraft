import AppKit
import ArcusDomain
import ArcusApplication

// FM3: File ▸ New ▸ Furniture… (until Home's Furniture card offers the library) and the Project Browser's Parameters
// and Types rows in Furniture documents.

extension AppDelegate {
    /// Asks for the piece's name and category, then opens a new Furniture document.
    @MainActor
    func showNewFurniture() {
        let alert = NSAlert()
        alert.messageText = "New Furniture"
        alert.informativeText = "A custom piece with parameters, cut lists and shop drawings. Imperial."
        let name = NSTextField(string: "Furniture")
        name.frame = NSRect(x: 0, y: 30, width: 260, height: 24)
        let category = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        category.addItems(withTitles: [FamilyTemplate.furniture.rawValue, FamilyTemplate.casework.rawValue])
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        box.addSubview(name)
        box.addSubview(category)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        newFurniture(name: name.stringValue, category: category.indexOfSelectedItem == 1 ? .casework : .furniture, template: nil)
    }
}

extension NSAlert {
    /// A warning about a Furniture template that couldn't be used (the blank template opens instead).
    @MainActor
    static func furnitureProblem(_ text: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = text
        a.informativeText = "A blank piece opens instead."
        a.runModal()
    }
}

extension ProjectBrowserController {
    /// Double-click on a Furniture document's Types row makes it the current type; on a Parameters row opens Family
    /// Types. False for every other node.
    func fm3Activate(_ node: BrowserNode) -> Bool {
        guard let state, state.mode == .furniture else { return false }
        if node.id.hasPrefix(FurnitureBrowserTree.typePrefix) {
            let name = String(node.id.dropFirst(FurnitureBrowserTree.typePrefix.count))
            state.session.perform("Change Type") { tx in try FurnitureParameters.setCurrentType(name, in: tx) }
            return true
        }
        if node.id.hasPrefix(FurnitureBrowserTree.parameterPrefix) {
            state.presented = .fm3(.familyTypes)
            return true
        }
        return false
    }
}
