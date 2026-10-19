import AppKit
import ArcusDomain
import ArcusApplication

// HOME: Home ▸ Family ▸ Create. The Family Editor edits a family for a project (`FamilyEditorModel.state`), so a family
// started from Home needs one. With a project open, the editor works for it (Load into Project loads there, as in the
// reference tool). With none, the editor gets a new untitled Imperial project that stays hidden; the first Load into
// Project loads the family into it and opens it, so Load into Project always means what it says. Save As writes an
// .arcusfamily file either way. Closing the editor without loading discards the hidden project.

@MainActor
enum HomeFamilyStart {
    /// Hidden projects waiting for a first Load into Project, by Family Editor window.
    private static var hosts: [ObjectIdentifier: Host] = [:]

    /// A hidden untitled project and the change handler that reveals it.
    private final class Host {
        let document: ArcusDocument
        var handler: UUID?
        var closeObserver: (any NSObjectProtocol)?
        init(document: ArcusDocument) { self.document = document }
    }

    /// The open project a new family is for: the active project's state, if its document is still open.
    static var openProject: DocumentState? {
        guard let s = AppDelegate.shared?.activeState, !s.isTornDown, let doc = s.document,
              NSDocumentController.shared.documents.contains(where: { $0 === doc }) else { return nil }
        return s
    }

    /// Opens the Family Editor on a new family of `category` named `name`.
    static func open(category: FamilyTemplate, name: String) {
        var family = FamilyTemplates.make(category)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        family.name = trimmed.isEmpty ? category.rawValue : trimmed
        open(family: family)
    }

    /// Opens the Family Editor on `family` for the open project, or for a hidden new one (FM8: File ▸ Open and Finder
    /// open .arcusfamily files this way, with `fileURL` for Save As).
    static func open(family: FamilyDefinition, fileURL: URL? = nil) {
        if let state = openProject {
            FamilyEditorWindowController.open(new: family, state: state)
            FamilyEditorWindowController.open.last?.model.fileURL = fileURL // FM8
            AppDelegate.shared?.closeHub()
            return
        }
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Untitled Project")
        let doc = ArcusDocument(model: model, displayName: nil)
        guard let state = doc.state else { return }
        FamilyEditorWindowController.open(new: family, state: state)
        guard let wc = FamilyEditorWindowController.open.last, wc.model.state === state, let window = wc.window else { return }
        wc.model.fileURL = fileURL // FM8
        let host = Host(document: doc)
        let key = ObjectIdentifier(window)
        host.handler = state.session.onChange { change in
            guard change.kind == .commit else { return }
            Task { @MainActor in reveal(key) } // after the load's transaction has finished installing
        }
        host.closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { discard(key) }
        }
        hosts[key] = host
        AppDelegate.shared?.closeHub()
    }

    /// The first Load into Project committed to the hidden project: open it as an ordinary untitled document.
    private static func reveal(_ key: ObjectIdentifier) {
        guard let host = hosts.removeValue(forKey: key) else { return }
        stopWatching(host)
        let doc = host.document
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        doc.updateChangeCount(.changeDone)
    }

    /// The editor closed before any Load into Project: drop the hidden project.
    private static func discard(_ key: ObjectIdentifier) {
        guard let host = hosts.removeValue(forKey: key) else { return }
        stopWatching(host)
        host.document.state?.tearDown()
    }

    private static func stopWatching(_ host: Host) {
        if let h = host.handler { host.document.session.removeChangeHandler(h) }
        if let o = host.closeObserver { NotificationCenter.default.removeObserver(o) }
        host.handler = nil
        host.closeObserver = nil
    }

    /// Number of hidden projects waiting for a Load into Project (QA and tests).
    static var pendingCount: Int { hosts.count }
}
