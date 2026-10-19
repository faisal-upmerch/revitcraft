import AppKit
import ArcusDomain
import ArcusApplication

// FM3: helpers for new Furniture documents and the Project Browser's Parameters and Types rows in Furniture documents.

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
