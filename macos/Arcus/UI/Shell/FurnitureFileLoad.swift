import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// FM8: projects load Furniture documents directly (Docs/FurnitureMode.md §3): Insert ▸ Load Family accepts
// `.arcusfurniture` files beside `.arcusfamily` and compiles them on load; Insert ▸ Load Furniture and a drop from
// Finder load a piece and start placing it, as the Component Library does. A piece loaded from a file is named after
// the file, as a family is.

@MainActor
enum FurnitureFileLoad {
    /// Insert ▸ Load Family: choose families or Furniture documents and load them (asking Family Already Exists for
    /// ones that are already in the project). Nothing is placed, as in Revit.
    static func chooseAndLoad(_ state: DocumentState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusFamily, .arcusFurniture]
        panel.allowsMultipleSelection = true
        panel.message = "Choose families (.arcusfamily) or furniture pieces (.arcusfurniture). RFA families come in through Insert ▸ Import Revit Model."
        panel.prompt = "Open"
        if let root = FurnitureLibraryCatalog.userRoot, FileManager.default.fileExists(atPath: root.path) { panel.directoryURL = root }
        guard panel.runModal() == .OK else { return }
        var loaded: [String] = []
        for url in panel.urls { if let name = load(url, into: state) { loaded.append(name) } }
        if !loaded.isEmpty { state.show(loaded.count == 1 ? "Loaded “\(loaded[0])”." : "Loaded \(loaded.count) families.") }
    }

    /// The Furniture document at `url`, named after the file (nil with a message when it can't be read or isn't one).
    static func furnitureModel(_ url: URL, _ state: DocumentState?) -> BIMModel? {
        do {
            let m = try ArcusPackage.read(from: url).model
            guard let named = FurnitureTemplates.copy(m, name: url.deletingPathExtension().lastPathComponent, category: m.furnitureSetup?.category ?? .furniture) else {
                state?.show("“\(url.lastPathComponent)” is not a Furniture document.", error: true)
                return nil
            }
            return named
        } catch {
            state?.show("Couldn't open “\(url.lastPathComponent)”: \(error.localizedDescription)", error: true)
            return nil
        }
    }

    /// Loads one file (family or Furniture document) into `state`. With `reuse`, a family of the same name that is
    /// already in the project is used as it is (library placement); otherwise Family Already Exists asks. Returns the
    /// family's name, or nil when nothing was loaded.
    @discardableResult
    static func load(_ url: URL, into state: DocumentState, reuse: Bool = false) -> String? {
        if url.pathExtension.lowercased() == FamilyPackage.fileExtension {
            do {
                let (fam, _, _) = try FamilyPackage.read(from: url)
                let existing = state.model.family(named: fam.name)?.id
                if existing != nil && reuse { return fam.name }
                var mode = FamilyReloadMode.keepProjectValues
                if existing != nil { guard let m = FamilyReloadPrompt.ask(fam.name) else { return nil }; mode = m }
                FamilyLoader(state: state).load(fam, replacing: existing, mode: mode)
                return state.session.lastError == nil ? fam.name : nil
            } catch {
                state.show("Couldn't load \(url.lastPathComponent): \(error.localizedDescription)", error: true)
                return nil
            }
        }
        guard let source = furnitureModel(url, state) else { return nil }
        return load(source, into: state, reuse: reuse)
    }

    /// Compiles a Furniture document and loads it into `state`. Returns the family's name, or nil.
    @discardableResult
    static func load(_ source: BIMModel, into state: DocumentState, reuse: Bool = false) -> String? {
        let problems = FurnitureParameters.flex(source)
        let family = FurnitureCompiler.family(from: source)
        let existing = state.model.family(named: family.name)?.id
        if existing != nil && reuse { return family.name }
        var mode = FamilyReloadMode.keepProjectValues
        if existing != nil { guard let m = FamilyReloadPrompt.ask(family.name) else { return nil }; mode = m }
        state.session.perform(existing == nil ? "Load Family" : "Reload Family") { tx in
            FurnitureLoading.load(family, from: source, replacing: existing, mode: mode, in: tx)
        }
        if let e = state.session.lastError { state.show("Couldn't load “\(family.name)”: \(e.message)", error: true); return nil }
        if !problems.isEmpty { state.show("“\(family.name)” has \(problems.count) flex problem(s): \(problems[0])", error: true) }
        return family.name
    }

    /// The type to place for a loaded family: the piece's current type, else its first type.
    static func placementType(_ familyName: String, preferred: String?, _ state: DocumentState) -> Element? {
        guard let fid = state.model.family(named: familyName)?.id else { return nil }
        let types = state.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        return types.first { $0.name == preferred } ?? types.min { $0.id < $1.id }
    }

    /// Loads a piece (or family) if needed and starts the Component tool with its type (Load Furniture, drops).
    /// Returns true when placement started.
    @discardableResult
    static func place(_ url: URL, in state: DocumentState) -> Bool {
        let preferred: String?
        let name: String?
        if url.pathExtension.lowercased() == FurnitureLibraryCatalog.fileExtension {
            guard let source = furnitureModel(url, state) else { return false }
            preferred = source.furnitureSetup?.currentType
            name = load(source, into: state, reuse: true)
        } else {
            preferred = nil
            name = load(url, into: state, reuse: true)
        }
        guard let name, let type = placementType(name, preferred: preferred, state), let cat = type.typeData?.instanceCategory else { return false }
        state.currentTypes[cat] = type.id
        state.currentTypes[.furniture] = type.id
        for c in state.toolContexts.values { c.currentTypes = state.currentTypes }
        state.presented = nil
        let router = CommandRouter(state: state)
        if let reason = router.disabledReason(.component) {
            state.show("Loaded “\(name)”. \(reason)")
            return false
        }
        router.run(.component)
        state.toolChangedState()
        state.show("Click to place “\(name)”. Space rotates.")
        return true
    }
}

// MARK: - Drops from Finder

extension Canvas2DView {
    /// FM8: furniture pieces and families dragged from Finder onto a plan, elevation or 3D-less view.
    func fm8DroppedFiles(_ sender: any NSDraggingInfo) -> [URL] {
        guard state.model[viewID]?.sheet == nil else { return [] }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { [FurnitureLibraryCatalog.fileExtension, FamilyPackage.fileExtension].contains($0.pathExtension.lowercased()) }
    }

    /// The drag operation for dropped furniture files, or nil when the drag isn't one (other handlers decide).
    func fm8DragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation? {
        fm8DroppedFiles(sender).isEmpty ? nil : .copy
    }

    /// Loads the first dropped file and starts placing it where it was dropped; nil when the drag isn't one.
    func fm8PerformDrop(_ sender: any NSDraggingInfo) -> Bool? {
        guard let url = fm8DroppedFiles(sender).first else { return nil }
        state.open(viewID)
        guard FurnitureFileLoad.place(url, in: state) else { return false }
        let p = toView(convert(sender.draggingLocation, from: nil))
        state.activeTool?.pointerMoved(ToolInput(point: p, rawPoint: p))
        needsDisplay = true
        window?.makeFirstResponder(self)
        return true
    }
}
