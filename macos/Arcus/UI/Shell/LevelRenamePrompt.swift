import AppKit
import ArcusDomain
import ArcusApplication

/// After a level is renamed (Properties, Rename dialog, Project Browser or on the canvas), offers to rename the plan
/// views named after it, the way BIM users expect.
@MainActor
enum LevelRenamePrompt {
    static func install(on state: DocumentState) {
        state.session.onChange { [weak state] change in
            guard let state, change.kind == .commit else { return }
            let renames = LevelRename.renamedLevels(in: change.record)
            guard !renames.isEmpty else { return }
            Task { @MainActor [weak state] in
                guard let state else { return }
                await ask(state, renames)
            }
        }
    }

    static func ask(_ state: DocumentState, _ renames: [LevelRename.Rename]) async {
        for r in renames {
            let views = LevelRename.correspondingViews(r, state.model)
            guard !views.isEmpty, let window = await readyWindow(state) else { continue }
            let alert = NSAlert()
            alert.messageText = "Rename views of “\(r.newName)”?"
            let names = views.compactMap { state.model[$0.viewID] }.map { "\($0.view?.kind.rawValue ?? "View"): \($0.name)" }
            alert.informativeText = "These views are still named after “\(r.oldName)”:\n\n" + names.joined(separator: "\n")
                + "\n\nRename them to match the level?"
            alert.addButton(withTitle: "Rename Views")
            alert.addButton(withTitle: "Keep Names")
            let response = await alert.beginSheetModal(for: window)
            guard response == .alertFirstButtonReturn else { continue }
            let current = LevelRename.correspondingViews(r, state.model)
            state.session.perform(current.count == 1 ? "Rename View" : "Rename Views") { tx in
                for v in current { tx.update(v.viewID) { $0.name = v.newName } }
            }
            state.updateWindowSubtitle()
        }
    }

    /// The document window once no other sheet (such as the closing Rename dialog) is attached.
    private static func readyWindow(_ state: DocumentState) async -> NSWindow? {
        for _ in 0..<40 {
            guard let w = state.window else { return nil }
            if w.attachedSheet == nil { return w }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
