import AppKit
import ArcusDomain
import ArcusApplication

// FM3: Load into Project from a Furniture window (Docs/FurnitureMode.md §3). As in the Family Editor: the piece is
// flexed first, compiled into a family and loaded (or reloaded) into an open project; with several projects open a
// Load into Projects dialog picks them. The project comes forward placing the new type, as after a family load.

@MainActor
enum FurnitureLoad {
    /// Open Architectural projects, front-most first.
    static func openProjects() -> [DocumentState] {
        let docs = NSDocumentController.shared.documents.compactMap { $0 as? ArcusDocument }
        let ordered = NSApp.orderedWindows.compactMap { w in docs.first { $0.windowControllers.contains { $0.window === w } } }
        return (ordered + docs.filter { !ordered.contains($0) }).compactMap(\.state).filter { $0.mode == .project && !$0.isTornDown }
    }

    /// Load into Project (and Close): one open project loads directly, several ask which.
    static func run(_ state: DocumentState, close: Bool) {
        guard state.mode == .furniture else { return }
        let problems = FurnitureParameters.flex(state.model)
        if !problems.isEmpty {
            state.show("Fix the flex problems before loading into a project.", error: true)
            state.presented = .fm3(.flex(problems))
            return
        }
        let projects = openProjects()
        switch projects.count {
        case 0: state.show("Open a project to load “\(state.model.furnitureSetup?.name ?? "this piece")” into.", error: true)
        case 1: load(state, into: projects, close: close)
        default: state.presented = .fm3(.loadInto(close: close))
        }
    }

    /// Compiles the piece and loads it into each target; the last target comes forward placing the new type.
    static func load(_ state: DocumentState, into targets: [DocumentState], close: Bool) {
        guard !targets.isEmpty else { return }
        let source = state.model
        let family = FurnitureCompiler.family(from: source)
        var placed: DocumentState?
        for target in targets {
            let existing = target.model.family(named: family.name)?.id
            var mode = FamilyReloadMode.keepProjectValues
            if existing != nil {
                guard let m = askReloadMode(family.name, project: target.documentName) else { continue }
                mode = m
            }
            var fid: ElementID?
            target.session.perform(existing == nil ? "Load Family" : "Reload Family") { tx in
                fid = FurnitureLoading.load(family, from: source, replacing: existing, mode: mode, in: tx)
            }
            if let e = target.session.lastError { state.show("Couldn't load into “\(target.documentName)”: \(e.message)", error: true); continue }
            let type = target.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == source.furnitureSetup?.currentType }
                ?? target.model.elements(.elementTypes).first { $0.typeData?.familyID == fid }
            if let type, let cat = type.typeData?.instanceCategory { target.currentTypes[cat] = type.id }
            target.show(existing == nil ? "Loaded “\(family.name)” from Furniture." : "Reloaded “\(family.name)” from Furniture.")
            placed = target
        }
        guard let placed else { return }
        placed.window?.makeKeyAndOrderFront(nil)
        // Place an instance, as Revit does after Load into Project (plans only; elsewhere the type is ready to place).
        if CommandRouter(state: placed).disabledReason(.component) == nil { CommandRouter(state: placed).run(.component) }
        if close { state.window?.performClose(nil) }
    }

    /// What to do with the project's type values when the piece is already loaded (nil = cancel).
    static func askReloadMode(_ name: String, project: String) -> FamilyReloadMode? {
        let alert = NSAlert()
        alert.messageText = "“\(name)” is already in “\(project)”."
        alert.informativeText = "Its geometry and parameters will be replaced by this version. Types that exist in both can keep the values set in the project, or take the values of this piece."
        alert.addButton(withTitle: "Keep Project Values")
        alert.addButton(withTitle: "Use Furniture Values")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepProjectValues
        case .alertSecondButtonReturn: return .overwriteValues
        default: return nil
        }
    }
}
