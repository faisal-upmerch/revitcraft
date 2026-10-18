import Foundation

// BL-KEYS: the Undo/Redo history lists behind the toolbar drop-downs.

/// The names of the undoable and redoable steps of a document, newest first, kept in step with its `UndoManager`.
/// One entry per undo group (what one ⌘Z undoes), named with the group's action name. Picking an entry in the Undo
/// drop-down undoes it and everything after it (`undo(through:)`).
@MainActor
public final class UndoHistory {
    public private(set) var undoNames: [String] = []
    public private(set) var redoNames: [String] = []
    public let undoManager: UndoManager
    private var tokens: [any NSObjectProtocol] = []

    public init(undoManager: UndoManager) {
        self.undoManager = undoManager
        let nc = NotificationCenter.default
        tokens.append(nc.addObserver(forName: .NSUndoManagerDidCloseUndoGroup, object: undoManager, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.groupClosed() }
        })
        tokens.append(nc.addObserver(forName: .NSUndoManagerDidUndoChange, object: undoManager, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.didUndo() }
        })
        tokens.append(nc.addObserver(forName: .NSUndoManagerDidRedoChange, object: undoManager, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.didRedo() }
        })
    }

    isolated deinit { for t in tokens { NotificationCenter.default.removeObserver(t) } }

    private func groupClosed() {
        // Groups closed while undoing or redoing hold the inverse registrations; nested groups belong to their parent.
        guard !undoManager.isUndoing, !undoManager.isRedoing, undoManager.groupingLevel == 0 else { return }
        undoNames.insert(undoManager.undoActionName.isEmpty ? "Change" : undoManager.undoActionName, at: 0)
        redoNames.removeAll()
        trim()
    }

    private func didUndo() {
        guard !undoNames.isEmpty else { return }
        redoNames.insert(undoNames.removeFirst(), at: 0)
    }

    private func didRedo() {
        guard !redoNames.isEmpty else { return }
        undoNames.insert(redoNames.removeFirst(), at: 0)
        trim()
    }

    private func trim() {
        let limit = undoManager.levelsOfUndo > 0 ? undoManager.levelsOfUndo : 200
        if undoNames.count > limit { undoNames.removeLast(undoNames.count - limit) }
        // The manager may hold fewer steps than recorded (e.g. after it dropped old ones).
        if !undoManager.canUndo { undoNames.removeAll() }
        if !undoManager.canRedo { redoNames.removeAll() }
    }

    /// Forgets everything (the document's history was cleared, e.g. on revert).
    public func reset() { undoNames.removeAll(); redoNames.removeAll() }

    /// Undoes the newest `index + 1` steps (index 0 = the last step).
    public func undo(through index: Int) {
        for _ in 0...max(index, 0) where undoManager.canUndo { undoManager.undo() }
    }

    /// Redoes the next `index + 1` undone steps.
    public func redo(through index: Int) {
        for _ in 0...max(index, 0) where undoManager.canRedo { undoManager.redo() }
    }
}
