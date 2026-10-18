import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// WP6a view and sheet commands: Selection Box, element graphic overrides, viewport activation, cameras, scope boxes,
/// grid Pick Lines and the project base point / survey point display.
@MainActor
struct ViewCommands {
    let state: DocumentState
    var router: CommandRouter { CommandRouter(state: state) }
    var model: BIMModel { state.model }
    var selection: [ElementID] { state.session.selection.ids }

    func perform(_ id: CommandID) {
        switch id {
        case .selectionBox: selectionBox()
        case .overrideGraphicsElement:
            guard let v = state.editingViewID else { return }
            state.presented = .overrideGraphics(view: v, elements: selection)
        case .activateViewport: activateViewport()
        case .deactivateViewport: sheetCanvas?.deactivateViewport()
        case .cameraView:
            guard let c = router.ctx() else { return }
            let t = CameraTool(ctx: c)
            t.onCreated = { [state] v in state.open(v) }
            state.setTool(t)
        case .scopeBox:
            guard let c = router.ctx() else { return }
            state.setTool(ScopeBoxTool(ctx: c))
        case .gridPickLines:
            guard let c = router.ctx() else { return }
            let t = LineTool(ctx: c, kind: .grid, commandID: .gridPickLines)
            t.pickLines = true
            state.setTool(t)
        case .showProjectBasePoint: toggleCategory(.projectBasePoint)
        case .showSurveyPoint: toggleCategory(.surveyPoint)
        default: break
        }
    }

    // MARK: Selection Box

    /// Fits a section box around the selection in the active 3D view, or in the default 3D view (created if needed).
    func selectionBox() {
        guard let box = SelectionBox.box(for: selection, model) else {
            state.show("Select model elements to fit a section box around.", error: true); return
        }
        let active = state.editingViewID.flatMap { model[$0] }
        var target = active?.view?.kind == .threeD ? active?.id : nil
        if target == nil {
            target = model.views.first(where: { $0.view?.kind == .threeD && $0.name == "{3D}" })?.id
        }
        var created: ElementID?
        state.session.perform("Selection Box") { tx in
            if let t = target {
                tx.update(t) { e in if var d = e.view { SelectionBox.apply(box, to: &d); e.view = d } }
            } else {
                var d = ViewData(kind: .threeD)
                d.camera = .defaultIsometric
                d.phaseID = tx.model.latestPhase?.id
                SelectionBox.apply(box, to: &d)
                created = tx.create(.views, name: "{3D}", data: .view(d))
            }
        }
        guard let v = target ?? created else { return }
        state.open(v)
        if let host = state.canvases[v] as? Viewport3DHost {
            host.viewport.sectionBox = box
            host.viewport.zoom(to: box, animated: !AccessibilityPrefs.reduceMotion)
        }
    }

    // MARK: Viewports

    var sheetCanvas: Canvas2DView? {
        guard let v = state.activeViewID, model[v]?.sheet != nil else { return nil }
        return state.canvases[v] as? Canvas2DView
    }

    /// Activates the selected viewport, or the only viewport on the sheet.
    func activateViewport() {
        guard let canvas = sheetCanvas, let sheet = state.activeViewID else { return }
        let viewports = model.owned(byView: sheet).filter { vp in vp.viewport.map { model[$0.viewID]?.view != nil } ?? false }
        let chosen = selection.first { id in viewports.contains { $0.id == id } } ?? (viewports.count == 1 ? viewports.first?.id : nil)
        guard let vp = chosen else { state.show("Select the viewport to activate (or double-click it).", error: true); return }
        canvas.activateViewport(vp)
    }

    // MARK: Project base point and survey point

    func toggleCategory(_ c: Category) {
        guard let v = state.editingViewID, let vd = model[v]?.view else { return }
        let on = !vd.visibility.isCategoryVisible(c)
        state.session.perform(on ? "Show \(c.displayName)" : "Hide \(c.displayName)") { tx in
            tx.update(v) { e in e.view?.visibility.setCategoryVisible(c, on) }
        }
        if let t = vd.templateID, model[t]?.viewTemplate?.visibility != nil {
            state.show("The view template “\(model[t]?.name ?? "")” controls visibility in this view; change it there.", error: true)
        } else {
            state.show(on ? "\(c.displayName) shown in this view." : "\(c.displayName) hidden in this view.")
        }
    }
}

extension CommandRouter {
    /// Availability of the WP6a commands.
    func wp6aDisabledReason(_ id: CommandID) -> String? {
        let editing = state.editingViewID.flatMap { model[$0] }
        switch id {
        case .selectionBox:
            // Cheap test (the ribbon asks on every redraw); the box itself is computed when the command runs.
            if !selection.contains(where: { id in model[id].map { ($0.category.isModel && $0.ownerViewID == nil) || $0.group != nil } ?? false }) {
                return "Select model elements first."
            }
        case .overrideGraphicsElement:
            if selection.isEmpty { return "Select elements first." }
            if editing?.view == nil { return "Graphic overrides apply to elements in a view; activate the viewport first." }
        case .activateViewport:
            guard let sheet = state.activeViewID, model[sheet]?.sheet != nil else { return "Open a sheet with a placed view." }
            if state.activeViewportEditor != nil { return "A view is already active; deactivate it first." }
            if !model.owned(byView: sheet).contains(where: { $0.viewport.map { model[$0.viewID]?.view != nil } ?? false }) { return "This sheet has no placed views." }
        case .deactivateViewport:
            if state.activeViewportEditor == nil { return "No view is activated on a sheet." }
        case .cameraView, .scopeBox, .gridPickLines:
            if !isPlan { return "Open a plan view to use this tool." }
        case .showProjectBasePoint, .showSurveyPoint:
            if !isPlan { return "The base point and survey point are shown in plan views." }
        default: break
        }
        return nil
    }
}

// MARK: - Context menu items

// BL-KEYS: the WP6a items (Activate/Deactivate View, Selection Box) are part of the menus in ContextMenus+Keys.swift.
