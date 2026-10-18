import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Builds and caches 2D display lists per view off the main actor. Stale results are never published: every
/// build carries a generation number and is dropped if a newer build started.
@MainActor
final class GraphicsStore {
    weak var state: DocumentState?
    private struct Entry {
        var graphics: ViewGraphics?
        var stale = true
        var generation = 0
        var task: Task<Void, Never>?
        var building = false
    }
    private var entries: [ElementID: Entry] = [:]
    private var listeners: [ElementID: [UUID: (ViewGraphics) -> Void]] = [:]
    /// Last build duration per view (seconds) for diagnostics.
    private(set) var lastBuildSeconds: [ElementID: Double] = [:]

    func graphics(_ viewID: ElementID) -> ViewGraphics? { entries[viewID]?.graphics }

    @discardableResult
    func listen(_ viewID: ElementID, _ handler: @escaping (ViewGraphics) -> Void) -> UUID {
        let id = UUID()
        listeners[viewID, default: [:]][id] = handler
        if let g = entries[viewID]?.graphics { handler(g) }
        if entries[viewID]?.graphics == nil || entries[viewID]?.stale != false { request(viewID) }
        return id
    }
    func unlisten(_ viewID: ElementID, _ id: UUID) { listeners[viewID]?.removeValue(forKey: id) }

    func drop(_ viewID: ElementID) {
        entries[viewID]?.task?.cancel()
        entries.removeValue(forKey: viewID)
    }

    /// Marks views stale after a model change; rebuilds views that have listeners (open canvases).
    func invalidate(_ change: ModelChange) {
        for id in Array(entries.keys) {
            entries[id]?.stale = true
        }
        for (id, ls) in listeners where !ls.isEmpty { request(id) }
    }

    func invalidateView(_ viewID: ElementID) {
        entries[viewID]?.stale = true
        // Sheets showing this view must refresh too.
        if let model = state?.model {
            for vp in model.viewports(showing: viewID) { if let s = vp.ownerViewID { entries[s]?.stale = true; if listeners[s]?.isEmpty == false { request(s) } } }
        }
        if listeners[viewID]?.isEmpty == false { request(viewID) }
    }

    func request(_ viewID: ElementID) {
        guard let state, let view = state.model[viewID] else { return }
        var e = entries[viewID] ?? Entry()
        e.generation += 1
        e.task?.cancel()
        let gen = e.generation
        let model = state.model
        let temp = state.session.temporaryVisibility(for: viewID) // F5: with Show Mass
        let placed: [ElementID: ViewGraphics] = view.sheet != nil ? cachedPlacedGraphics(sheet: viewID, model) : [:]
        let cancelBox = CancelBox()
        e.building = true
        e.task = Task { [weak self] in
            let t0 = CFAbsoluteTimeGetCurrent()
            let interval = Signpost.begin("view build")
            let g: ViewGraphics? = await Task.detached(priority: .userInitiated) { () -> ViewGraphics? in
                if view.sheet != nil {
                    let builder = SheetGraphicsBuilder(model: model, sheet: view) { v in
                        if let hit = placed[v.id], hit.modelRevision == model.revision { return hit }
                        return ViewGraphicsBuilder(model: model, view: v, isCancelled: { cancelBox.cancelled }).build()
                    }
                    return builder.build()
                }
                guard view.view != nil else { return nil }
                return ViewGraphicsBuilder(model: model, view: view, temporary: temp, isCancelled: { cancelBox.cancelled }).build()
            }.value
            guard let self, !Task.isCancelled else { cancelBox.cancelled = true; Signpost.end(interval, completed: false); return }
            guard self.entries[viewID]?.generation == gen, let g else { Signpost.end(interval, completed: false); return }
            self.entries[viewID]?.graphics = g
            self.entries[viewID]?.stale = false
            self.entries[viewID]?.building = false
            self.lastBuildSeconds[viewID] = CFAbsoluteTimeGetCurrent() - t0
            Signpost.end(interval)
            for h in self.listeners[viewID]?.values.map({ $0 }) ?? [] { h(g) }
        }
        entries[viewID] = e
    }

    var isBuilding: Bool { entries.values.contains { $0.building } }

    private func cachedPlacedGraphics(sheet: ElementID, _ model: BIMModel) -> [ElementID: ViewGraphics] {
        var out: [ElementID: ViewGraphics] = [:]
        for vp in model.owned(byView: sheet) {
            guard let v = vp.viewport?.viewID, let g = entries[v]?.graphics, entries[v]?.stale == false else { continue }
            out[v] = g
        }
        return out
    }
}
