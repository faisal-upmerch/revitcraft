import AppKit
import ArcusApplication

// BL-SCHED: File ▸ New lists only editors that exist: projects (template hub) and families in the Family Editor
// (any category template, title blocks and generic annotation symbols).
extension MainMenuBuilder {
    static func newMenu() -> NSMenuItem {
        let items: [(CommandID, String)] = [(.newProject, "Project…"), (.newFurniture, "Furniture…"), (.newFamily, "Family…"), (.newTitleBlock, "Title Block…"), (.newAnnotationSymbol, "Annotation Symbol…")]
        return submenu("New", items.map { id, title in
            let i = command(id)
            i.title = title
            return i
        })
    }
}
