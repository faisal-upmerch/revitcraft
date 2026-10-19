import AppKit
import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-KEYS: per-document keyboard state (typed aliases, the Modify pre-selection flow, undo history) and the app-wide
// rule that no alias, tool shortcut, Select All or Finish runs while a text control has the keyboard.

/// Keyboard state of one document window. Lives on `DocumentState.keys`.
@MainActor
@Observable
final class KeyboardSession {
    /// The partly typed alias ("Z" while typing ZE), echoed in the status bar; nil when the buffer is empty.
    var aliasTyped: String?
    /// A Modify command run with nothing selected: the user selects elements, then Return or Finish continues.
    var pendingCommand: CommandID?
    @ObservationIgnored var matcher = AliasMatcher()
    @ObservationIgnored var flushTask: Task<Void, Never>?
    @ObservationIgnored var undoHistory: UndoHistory?

    /// Status bar text that takes precedence over the tool prompt.
    var statusOverride: String? {
        if let a = aliasTyped { return "Shortcut: \(a)…" }
        if let c = pendingCommand {
            return "\(CommandCatalog.info(c).title): select elements (click, window or ⌘-click), then press Return or click Finish. Esc cancels."
        }
        return nil
    }
}

extension DocumentState {
    // MARK: Typed aliases

    /// Feeds a letter or digit typed on a canvas (2D or 3D) into the shared alias buffer and runs what it completes.
    func feedAlias(_ ch: Character) {
        let out = keys.matcher.feed(ch, at: ProcessInfo.processInfo.systemUptime, in: KeyboardAliases.shared.aliases)
        applyAlias(out)
        keys.flushTask?.cancel()
        guard keys.matcher.echo != nil else { return }
        keys.flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AliasMatcher.timeout + 0.05))
            guard !Task.isCancelled, let self else { return }
            self.applyAlias(self.keys.matcher.flush(at: ProcessInfo.processInfo.systemUptime, in: KeyboardAliases.shared.aliases))
        }
    }

    private func applyAlias(_ out: AliasMatcher.Outcome) {
        if keys.aliasTyped != out.echo { keys.aliasTyped = out.echo }
        for c in out.commands { CommandRouter(state: self).run(c) }
    }

    /// Esc first drops a partly typed alias, then a Modify command waiting for its selection. True when it did either.
    func keysEscape() -> Bool {
        if keys.matcher.cancel() { keys.aliasTyped = nil; keys.flushTask?.cancel(); return true }
        if keys.pendingCommand != nil { cancelPreselection(); return true }
        return false
    }

    // MARK: Modify pre-selection

    /// Starts the pre-selection flow when a selection command runs with nothing selected. False when not applicable.
    func beginPreselection(_ id: CommandID) -> Bool {
        guard ToolLifecycle.preselectionCommands.contains(id), session.selection.isEmpty else { return false }
        cancelTool()
        keys.pendingCommand = id
        ribbonShowsContextual = true
        toolChangedState()
        return true
    }

    /// Return or Finish: continues the waiting command with the selection.
    func finishPreselection() {
        guard let id = keys.pendingCommand else { return }
        guard !session.selection.isEmpty else {
            show("\(CommandCatalog.info(id).title): select elements first, then press Return or click Finish.")
            return
        }
        keys.pendingCommand = nil
        toolChangedState()
        CommandRouter(state: self).run(id)
    }

    func cancelPreselection() {
        keys.pendingCommand = nil
        toolChangedState()
    }

    // MARK: Repeat, delete, flip

    /// Repeat [last command] (Return in Modify, the RC alias and the context menus).
    func repeatLastCommand() {
        guard let id = ToolLifecycle.lastRepeatable(recentCommands) else { show("There is no command to repeat yet."); return }
        CommandRouter(state: self).run(id)
    }

    /// Deletes the selection and says why pinned elements were kept (the session records it without a model change).
    func deleteSelection() {
        let ids = session.selection.ids
        guard !ids.isEmpty else { return }
        session.delete(ids)
        if let e = session.lastError { show(e.message, error: true); session.clearError() }
        else if let w = session.lastWarnings.first(where: { $0.code == "delete.pinned" }) { show(w.message) }
    }

    /// Space in Modify: flips the selected doors and windows (facing) and walls (orientation). False when none.
    func flipSelectionWithSpace() -> Bool {
        let sel = session.selection.ids.compactMap { model[$0] }
        let inserts = sel.filter { $0.insert != nil }.map(\.id)
        let walls = sel.filter { $0.wall != nil }.map(\.id)
        let doors = sel.filter { $0.furnitureFront?.kind == .door }.map(\.id) // FM5: Space flips a cabinet door's hinge side
        if inserts.isEmpty, walls.isEmpty, !doors.isEmpty {
            session.perform("Flip Hinge") { tx in for id in doors { tx.update(id) { $0.furnitureFront?.hingeFlipped.toggle() } } }
            return true
        }
        guard !inserts.isEmpty || !walls.isEmpty else { return false }
        session.perform(inserts.isEmpty ? "Flip Wall" : "Flip Facing") { tx in
            for id in inserts { tx.update(id) { $0.insert?.facingFlipped.toggle() } }
            for id in walls { tx.update(id) { $0.wall?.flipped.toggle() } }
        }
        return true
    }

    // MARK: Undo history

    /// The document's undo/redo step names (created with the window's toolbar, so it sees every step).
    var undoHistory: UndoHistory {
        if let h = keys.undoHistory { return h }
        let h = UndoHistory(undoManager: session.undoManager)
        keys.undoHistory = h
        session.onChange { [weak h] change in if change.kind == .replace { h?.reset() } }
        return h
    }
}

// MARK: - Text input focus

/// The app-wide rule for text input: while a text field, search field, inline editor or dialog text control has the
/// keyboard, keys never run typed aliases, tool shortcuts, ⌘A Select All (elements) or Return-as-Finish.
///
/// AppKit text fields and SwiftUI `TextField`s both edit through a field editor (an `NSTextView`) that becomes first
/// responder, so checking the responder covers them. Inline editors that are on screen but may not have received focus
/// (a Project Browser rename field) register with `inlineTextEditing(_:id:focus:)`; while one is registered the canvas
/// ignores keys and hands the keyboard to the editor instead.
@MainActor
enum TextInputFocus {
    private struct Editor { weak var window: NSWindow?; var anyWindow: Bool; var focus: (() -> Void)? }
    private static var editors: [AnyHashable: Editor] = [:]

    /// True for the field editor of a text field (AppKit or SwiftUI), editable text views and text fields.
    static func isTextResponder(_ r: NSResponder?) -> Bool {
        switch r {
        case let t as NSText: return t.isEditable || t.isFieldEditor
        case let f as NSTextField: return f.isEditable
        default: return false
        }
    }

    /// Whether text is being edited in `window`, a sheet on it, the key window, or an inline editor registered for it.
    static func isEditingText(in window: NSWindow?) -> Bool {
        var windows: [NSWindow] = []
        if let window {
            windows.append(window)
            if let sheet = window.attachedSheet { windows.append(sheet) }
            windows += window.childWindows ?? []
        }
        if let key = NSApp.keyWindow { windows.append(key) }
        if windows.contains(where: { isTextResponder($0.firstResponder) }) { return true }
        return hasInlineEditor(in: window)
    }

    static func hasInlineEditor(in window: NSWindow?) -> Bool {
        editors.values.contains { $0.anyWindow || ($0.window != nil && $0.window === window) }
    }

    /// Registers an open inline editor. `window` nil: applies to whichever window has the keyboard.
    static func begin(_ id: AnyHashable, window: NSWindow? = nil, focus: (() -> Void)? = nil) {
        editors[id] = Editor(window: window, anyWindow: window == nil, focus: focus)
    }

    static func end(_ id: AnyHashable) { editors.removeValue(forKey: id) }

    /// Hands the keyboard to a registered inline editor of `window`. Returns true when there was one.
    @discardableResult
    static func focusInlineEditor(in window: NSWindow?) -> Bool {
        guard let e = editors.values.first(where: { $0.anyWindow || $0.window === window }) else { return false }
        e.focus?()
        return true
    }

    /// Edit ▸ Select All reaching the document window (no text field had it): with an inline editor open, focus the
    /// editor instead of selecting elements. Returns true when the caller must not select elements.
    static func redirectSelectAll(in window: NSWindow?) -> Bool {
        if let r = window?.firstResponder, isTextResponder(r) { (r as? NSText)?.selectAll(nil); return true }
        return focusInlineEditor(in: window)
    }
}

extension View {
    /// Marks an inline text editor (e.g. a rename field) as open while `active`, so canvas keys never run aliases,
    /// shortcuts, Select All or Finish meanwhile; `focus` is called to give the editor the keyboard when a key arrives
    /// elsewhere (typically sets a `@FocusState`).
    func inlineTextEditing(_ active: Bool, id: AnyHashable, focus: @escaping () -> Void = {}) -> some View {
        modifier(InlineTextEditingModifier(active: active, id: id, focus: focus))
    }
}

private struct InlineTextEditingModifier: ViewModifier {
    let active: Bool
    let id: AnyHashable
    let focus: () -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, a in
                if a { TextInputFocus.begin(id, focus: focus) } else { TextInputFocus.end(id) }
            }
            .onDisappear { TextInputFocus.end(id) }
    }
}
