import AppKit
import ArcusDomain
import ArcusApplication

// FM8: Edit Family on a piece loaded from Furniture mode (Docs/FurnitureMode.md §3, "Load into Project and Edit
// Family"). As in Revit, Edit Family (Modify ▸ Edit Family, the Project Browser's Edit, double-click) opens the
// family's source document: here the Furniture document the family was compiled from (`furnitureSource`), in Furniture
// mode, not the Family Editor. The document stays tied to the project and family it came from, so its Load into
// Project reloads that family (keeping the placed instances) with the "Family Already Exists" prompt.

@MainActor
enum FurnitureEditFamily {
    /// A Furniture document opened by Edit Family: the project and family it reloads.
    final class Link {
        weak var project: DocumentState?
        weak var furniture: DocumentState?
        let familyID: ElementID
        init(project: DocumentState, furniture: DocumentState, familyID: ElementID) {
            self.project = project; self.furniture = furniture; self.familyID = familyID
        }
        var isLive: Bool { furniture.map { !$0.isTornDown } == true && project.map { !$0.isTornDown } == true }
    }

    private static var links: [Link] = []

    /// The live link of a Furniture document opened by Edit Family.
    static func link(of furniture: DocumentState) -> Link? {
        links.removeAll { !$0.isLive }
        return links.first { $0.furniture === furniture }
    }

    /// The project a Furniture document was opened from by Edit Family, while both are open.
    static func project(of furniture: DocumentState) -> DocumentState? { link(of: furniture)?.project }

    /// The family a Furniture document reloads in `project`: the one it was opened from, while it's still a family there.
    static func familyID(of furniture: DocumentState, in project: DocumentState) -> ElementID? {
        guard let l = link(of: furniture), l.project === project, project.model[l.familyID]?.family != nil else { return nil }
        return l.familyID
    }

    /// Edit Family for `familyID` of `state`: a family compiled from a Furniture document opens that document in
    /// Furniture mode (on the selected instance's type) and returns true; any other family returns false (the caller
    /// opens the Family Editor).
    @discardableResult
    static func open(familyID: ElementID, from state: DocumentState) -> Bool {
        guard let family = state.model[familyID]?.family, family.furnitureSource != nil else { return false }
        if let open = links.first(where: { $0.isLive && $0.project === state && $0.familyID == familyID })?.furniture {
            open.window?.makeKeyAndOrderFront(nil)
            return true
        }
        guard let model = sourceModel(family, typeName: selectedTypeName(familyID, state)) else {
            state.show("“\(family.name)” has no readable Furniture document; it opens in the Family Editor.", error: true)
            return false
        }
        let doc = ArcusDocument(model: model, displayName: family.name)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        if let furniture = doc.state {
            links.append(Link(project: state, furniture: furniture, familyID: familyID))
            furniture.show("Editing “\(family.name)” from “\(state.documentName)”. Load into Project updates it there.")
        }
        return true
    }

    /// The family's Furniture document, on `typeName` when the document has that type.
    static func sourceModel(_ family: FamilyDefinition, typeName: String?) -> BIMModel? {
        guard let m = FurnitureCompiler.source(of: family) else { return nil }
        guard let typeName, m.furnitureSetup?.currentType != typeName, m.furnitureSetup?.family.type(named: typeName) != nil else { return m }
        let tx = TransactionContext(model: m, name: "Type")
        guard (try? FurnitureParameters.setCurrentType(typeName, in: tx)) != nil, let c = try? tx.commit() else { return m }
        return c.model
    }

    /// The type of the selected instance or type of the family, if any.
    static func selectedTypeName(_ familyID: ElementID, _ state: DocumentState) -> String? {
        for id in state.session.selection.ids {
            guard let e = state.model[id] else { continue }
            let t = e.typeData != nil ? e : state.model.type(of: e)
            if let t, t.typeData?.familyID == familyID { return t.name }
        }
        return nil
    }
}

/// Revit's "Family Already Exists" prompt, shown when a family that is already in the project is loaded again.
@MainActor
enum FamilyReloadPrompt {
    /// Tests and QA answer the prompt instead of the user (nil shows it).
    static var answer: FamilyReloadMode?? = nil

    static let title = "Family Already Exists"
    static func message(_ name: String) -> String {
        "You are trying to load the family “\(name)”, which already exists in this project. What do you want to do?"
    }
    static let overwrite = "Overwrite the existing version"
    static let overwriteValues = "Overwrite the existing version and its parameter values"

    /// The alert, ready to run (QA shows it without running it).
    static func alert(_ name: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message(name)
        alert.addButton(withTitle: overwrite)
        alert.addButton(withTitle: overwriteValues)
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// What to do with the project's type values: keep them (Overwrite the existing version), take the family's
    /// (… and its parameter values), or nil to cancel.
    static func ask(_ name: String) -> FamilyReloadMode? {
        if let answer { return answer }
        switch alert(name).runModal() {
        case .alertFirstButtonReturn: return .keepProjectValues
        case .alertSecondButtonReturn: return .overwriteValues
        default: return nil
        }
    }
}
