import AppKit
import ArcusDomain
import ArcusPersistence

// FM3: new Furniture documents (Home ▸ Furniture, File ▸ New ▸ Furniture…).

extension AppDelegate {
    /// Opens a new untitled Furniture document named `name` in `category` (Furniture or Casework): the blank template,
    /// or a copy of the Furniture document at `template` (a library piece or a saved piece). It saves as
    /// `.arcusfurniture`.
    @MainActor
    func newFurniture(name: String, category: FamilyTemplate, template: URL?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = trimmed.isEmpty ? "Furniture" : trimmed
        var model: BIMModel?
        if let template {
            do {
                model = FurnitureTemplates.copy(try ArcusPackage.read(from: template).model, name: n, category: category)
                if model == nil { NSAlert.furnitureProblem("“\(template.lastPathComponent)” is not a Furniture document.") }
            } catch {
                NSAlert.furnitureProblem("Couldn't open “\(template.lastPathComponent)”: \(error.localizedDescription)")
            }
        }
        let doc = ArcusDocument(model: model ?? FurnitureTemplates.blank(category: category, name: n), displayName: n)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        closeHub()
    }
}
