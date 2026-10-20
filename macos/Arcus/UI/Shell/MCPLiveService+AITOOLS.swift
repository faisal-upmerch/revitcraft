import AppKit
import ArcusDomain
import ArcusApplication
import ArcusMCP

// AITOOLS: the live host's window features for the tool layer (Docs/MCP.md §2): the front document's active view,
// opening views, zooming, and running any command through the document's CommandRouter like its menu item. The Family
// Editor's family comes from the assistant's adapter (ArcusToolbox.familyHostProvider).

extension AppDocumentHost: DocumentUIHost {
    var state: DocumentState? { target?.state }

    var activeViewID: ElementID? { state?.activeViewID }

    func activateView(_ id: ElementID) -> Bool {
        guard let s = state, let e = s.model[id], e.view != nil || e.sheet != nil || e.schedule != nil else { return false }
        s.open(id)
        return s.activeViewID == id
    }

    func zoom(to ids: [ElementID]?) {
        guard let s = state, let v = s.activeViewID else { return }
        if let canvas = s.canvases[v] as? Canvas2DView {
            if let ids, !ids.isEmpty {
                s.session.selection.select(ids)
                canvas.zoomToSelection()
            } else { canvas.zoomToFit() }
        } else if let v3 = s.canvases[v] as? Viewport3DHost {
            if let ids, !ids.isEmpty { s.session.selection.select(ids); CommandRouter(state: s).run(.view3DFrameSelected) } else { v3.zoomExtents() }
        }
    }

    func commandDisabledReason(_ id: CommandID) -> String? {
        guard let s = state else { return "No document is open." }
        return CommandRouter(state: s).disabledReason(id)
    }

    func runCommand(_ id: CommandID) -> CommandOutcome {
        guard let s = state else { return .unavailable("No document is open.") }
        let router = CommandRouter(state: s)
        if let reason = router.disabledReason(id) { return .unavailable(reason) }
        let before = s.session.changeCounter
        router.run(id)
        if let tool = s.activeTool, tool.commandID == id { return .startedTool(CommandCatalog.info(id).title) }
        if let presented = s.presented { return .done("Opened \(String(describing: presented).split(separator: "(").first ?? "a dialog") for the user.") }
        return .done(s.session.changeCounter != before ? "\(CommandCatalog.info(id).title) changed the model." : "\(CommandCatalog.info(id).title) ran.")
    }

    var familyHost: (any FamilyEditingHost)? { nil }
}
