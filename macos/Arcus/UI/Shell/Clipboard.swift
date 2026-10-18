import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// The app-wide element clipboard. One clipboard serves every open project, so a selection copied in one project
/// can be pasted into another.
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()
    private(set) var payload: ClipboardPayload?
    /// The session the payload was copied from (weak: the project may be closed; the payload keeps its snapshot).
    private(set) weak var sourceSession: DocumentSession?

    func set(_ payload: ClipboardPayload, from session: DocumentSession) {
        self.payload = payload
        sourceSession = session
    }
}

// MARK: - Clipboard commands

@MainActor
struct Clipboard {
    let state: DocumentState
    enum PasteMode { case cursor, samePlace, currentView, levels([ElementID]) }

    func copy() {
        let view = state.activeViewID
        guard let payload = ClipboardPayload.capture(state.session.selection.ids, from: state.model, viewID: view, levelID: state.activeView?.levelID) else {
            state.show("Nothing that can be copied is selected."); return
        }
        ClipboardStore.shared.set(payload, from: state.session)
        state.show("Copied \(payload.elements.count) element(s).")
    }

    /// Pasting into the project the elements came from copies them in place (keeping every reference); pasting into
    /// another project goes through `ProjectTransfer`, which matches types and levels by name.
    var isSameProject: Bool {
        guard let payload = ClipboardStore.shared.payload, ClipboardStore.shared.sourceSession === state.session else { return false }
        // After a revert the supporting data may be gone; then treat the payload like one from another project.
        return payload.context.keys.allSatisfy { state.model[$0] != nil }
    }

    func paste(mode: PasteMode) {
        guard let payload = ClipboardStore.shared.payload else { return }
        if isSameProject { pasteInPlace(payload, mode: mode) } else { pasteFromOtherProject(payload, mode: mode) }
    }

    /// Offset that centres the pasted elements on the cursor (Paste), else zero.
    func cursorOffset(_ payload: ClipboardPayload, mode: PasteMode, boundsModel m: BIMModel) -> Vec2 {
        guard case .cursor = mode, let cursor = state.cursorPoint else { return .zero }
        let b = payload.elements.reduce(Rect2.empty) { $0.union(ElementMeshes.bounds($1, m).xy) }
        return b.isEmpty ? .zero : cursor - b.center
    }

    private func pasteInPlace(_ payload: ClipboardPayload, mode: PasteMode) {
        let m = state.model
        let view = state.activeViewID
        let offset = cursorOffset(payload, mode: mode, boundsModel: m)
        var pasted: [ElementID] = []
        state.session.perform("Paste") { tx in
            let levels: [ElementID?]
            if case .levels(let ls) = mode { levels = ls } else { levels = [nil] }
            for target in levels {
                // Temporarily ensure sources exist (they may have been deleted): insert missing ones, copy, then remove.
                var temp: [ElementID] = []
                for e in payload.elements where tx.model[e.id] == nil { tx.insertPreservingID(e); temp.append(e.id) }
                let targetView: ElementID? = {
                    if case .currentView = mode { return view }
                    return nil
                }()
                let map = ElementOperations.copy(payload.elements.map(\.id), by: .translation(offset), in: tx, viewID: payload.sourceViewID,
                                                 targetLevel: target, targetView: targetView)
                pasted += map.values
                for t in temp { tx.delete(t) }
            }
        }
        if !pasted.isEmpty { state.session.selection.select(pasted) }
    }

    private func pasteFromOtherProject(_ payload: ClipboardPayload, mode: PasteMode) {
        // Bounds are measured in a scratch model holding the copied elements and their types.
        let all = payload.elements + Array(payload.context.values)
        let scratch = BIMModel(elements: all, nextID: (all.map(\.id.raw).max() ?? 0) + 1)
        let offset = cursorOffset(payload, mode: mode, boundsModel: scratch)
        // View-specific elements (tags, dimensions, detail items) always go to the active 2D view.
        let view = state.activeView.flatMap { $0.sheet != nil || ($0.view.map { $0.kind != .threeD } ?? false) ? $0.id : nil }
        let fallback = state.activeView?.levelID ?? state.model.levels.first?.id
        var reports: [PasteReport] = []
        state.session.perform("Paste from Another Project") { tx in
            if case .levels(let ls) = mode {
                for l in ls { reports.append(ProjectTransfer.paste(payload, into: tx, transform: .translation(offset), targetView: view, fallbackLevel: l, baseLevel: l)) }
            } else {
                reports.append(ProjectTransfer.paste(payload, into: tx, transform: .translation(offset), targetView: view, fallbackLevel: fallback))
            }
        }
        if let err = state.session.lastError { state.show(err.message, error: true); return }
        guard var report = reports.first else { return }
        for r in reports.dropFirst() { report.pasted += r.pasted }
        if !report.pasted.isEmpty { state.session.selection.select(report.pasted.filter { state.model[$0] != nil }) }
        if report.duplicateTypes.isEmpty && report.skipped.isEmpty {
            state.show(report.summary)
        } else {
            state.presented = .report("Paste from Another Project", report.summary)
        }
    }
}
