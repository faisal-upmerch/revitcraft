import AppKit
import ArcusDomain
import ArcusApplication

// F810: View, sheets and presentation: hidden lines, cut profile, walkthrough, title blocks, windows, render. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// Commands drawn in plan views.
    static let f810PlanTools: Set<CommandID> = [.cutProfile, .framingElevation, .calloutSketch, .walkthrough, .matchline]
    static let f810WalkthroughCommands: Set<CommandID> = [.walkthroughPreviousFrame, .walkthroughNextFrame, .walkthroughPlay, .walkthroughExport]

    /// The tool for one of this batch's commands, or nil.
    func f810MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .showHiddenLines: return HiddenLinesTool(ctx: c, show: true)
        case .removeHiddenLines: return HiddenLinesTool(ctx: c, show: false)
        case .cutProfile:
            // A selected wall cut in the view goes straight to the sketch, as picking it would.
            if selection.count == 1, let w = model[selection[0]], w.wall != nil, let v = model[c.viewID],
               !WallGeometry.planCut(w, atZ: CutProfiles.cutZ(v, model), model).isEmpty {
                return f810CutProfileSketch(c, wall: w.id)
            }
            let t = CutProfileTool(ctx: c)
            let state = state
            t.onPicked = { wall in
                state.session.selection.clear()
                state.setTool(CommandRouter(state: state).f810CutProfileSketch(c, wall: wall))
            }
            return t
        case .framingElevation: return FramingElevationTool(ctx: c)
        case .calloutSketch:
            let t = SketchTool(ctx: c, target: .callout, commandID: .calloutSketch)
            t.drawMode = .line
            return t
        case .walkthrough:
            let t = WalkthroughTool(ctx: c)
            let state = state
            t.onCreated = { id in state.open(id) }
            return t
        case .matchline: return MatchlineTool(ctx: c)
        default: return nil
        }
    }

    /// The cut profile sketch of `wall` (lines by default, as RevitCraft starts it).
    func f810CutProfileSketch(_ c: ToolContext, wall: ElementID) -> SketchTool {
        let t = SketchTool(ctx: c, target: .f810(.cutProfile(wall: wall)), commandID: .cutProfile)
        t.drawMode = .line
        return t
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f810Perform(_ id: CommandID) -> Bool {
        switch id {
        case .finishWalkthrough:
            guard let t = state.activeTool as? WalkthroughTool else { return false }
            _ = t.finish()
            state.toolChangedState()
        case .walkthroughPreviousFrame, .walkthroughNextFrame:
            guard let v = state.activeViewID, let w = model[v]?.view?.walkthrough else { return false }
            WalkthroughPlayer.stop(state)
            let target = w.frame + (id == .walkthroughNextFrame ? 1 : -1)
            var shown = w.frame
            session.perform(id == .walkthroughNextFrame ? "Next Frame" : "Previous Frame") { tx in shown = try Walkthroughs.setFrame(target, of: v, tx) }
            state.show("Frame \(shown) of \(w.frames)")
        case .walkthroughPlay: WalkthroughPlayer.toggle(state)
        case .walkthroughExport: WalkthroughExport(state: state).run()
        case .titleBlock: if let s = f810ActiveSheet { state.presented = .f810(.titleBlock(s)) }
        case .guideGrid: if let s = f810ActiveSheet { state.presented = .f810(.guideGrid(s)) }
        case .switchWindows: F810WindowMenus.switchWindows(state)
        case .tabViews:
            state.tileViews = false
        case .tileViews:
            state.tileViews = true
            state.show("Tiled \(state.openViews.count) views. Click a view to make it active; Tab Views (TW) returns to tabs.")
        case .canvasTheme: F810WindowMenus.canvasTheme(state)
        case .navigationWheel: NavigationWheel.toggle(state)
        case .render: if let v = state.activeViewID { state.presented = .f810(.render(v)) }
        case .renderGallery: state.presented = .f810(.renderGallery)
        case .exportOBJ: OBJExportAction(state: state).run()
        case .duplicateView, .duplicateViewWithDetailing:
            // RevitCraft's Duplicate View on a sheet duplicates the sheet.
            guard let s = state.activeViewID, model[s]?.sheet != nil else { return false }
            var created: ElementID?
            session.perform("Duplicate Sheet") { tx in created = try SheetDuplication.duplicate(s, withDetailing: id == .duplicateViewWithDetailing, in: tx) }
            if let created { state.open(created) }
        default: return false
        }
        return true
    }

    /// The open sheet (the one an activated viewport belongs to counts too).
    var f810ActiveSheet: ElementID? {
        guard let v = state.activeViewID, model[v]?.sheet != nil else { return nil }
        return v
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f810DisabledReason(_ id: CommandID) -> String? {
        if Self.f810PlanTools.contains(id) && !isPlan { return "Open a plan view to use this tool." }
        switch id {
        case .showHiddenLines, .removeHiddenLines:
            if !(isPlan || (viewKind?.isVerticalCut ?? false)) { return "Open a plan, section or elevation." }
        case .finishWalkthrough:
            guard let t = state.activeTool as? WalkthroughTool else { return "Start a walkthrough first (View ▸ 3D View ▸ Walkthrough)." }
            if t.points.count < 2 { return "Click at least two points along the walkthrough path." }
        case _ where Self.f810WalkthroughCommands.contains(id):
            if state.activeView?.view?.walkthrough == nil { return "Open a walkthrough view." }
            if id == .walkthroughExport, !(state.canvases[state.activeViewID ?? ElementID(0)] is Viewport3DHost) { return "Open the walkthrough view first." }
        case .titleBlock, .guideGrid:
            if f810ActiveSheet == nil { return "Open a sheet." }
            if state.editingViewID != state.activeViewID { return "Deactivate the viewport first." }
        case .tileViews:
            if state.openViews.count < 2 { return "Open two or more views to tile them." }
        case .render:
            if state.activeView?.view?.kind != .threeD { return "Rendering works in a 3D view." }
        case .navigationWheel:
            if state.activeView == nil || state.activeView?.schedule != nil { return "Open a view, sheet or 3D view." }
        default: break
        }
        return nil
    }
}
