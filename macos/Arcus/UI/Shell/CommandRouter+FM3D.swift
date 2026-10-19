import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM3D: Furniture tools in 3D views. In a Furniture document's 3D view every Parts, Openings and Forms tool runs on the
// view's work plane: its context is the plan or elevation that sees the plane (FurniturePlacement3D), so it makes the
// same elements as in 2D. Tools that pick follow the face under the pointer. Edit Profile, Edit Boundary, Blend's Edit
// Top/Base and Edit Sketch open on the plane of what they edit. Also: View ▸ 3D Design, and Edit Sketch of extrusions.

extension CommandRouter {
    /// The Furniture tools that run in 3D views.
    static let fm3dToolIDs: Set<CommandID> = fm4IDs.union(fm5IDs).union([.furnitureBlendEditTop, .furnitureBlendEditBase, .furnitureEditSketch])

    /// A Furniture document's 3D view is active (not an activated viewport on a sheet).
    var fm3dIn3D: Bool { state.mode == .furniture && viewKind == .threeD && state.activeViewportEditor == nil && state.activeViewID != nil }

    /// The 3D view's work plane when one is set (Work Plane ▸ Set, a picked face or plane).
    func fm3dWorkPlane() -> (frame: WorkPlaneFrame, ref: WorkPlaneRef)? {
        guard let v = state.activeViewID, let w = model[v]?.view?.workPlane, WorkPlanes.isValid(w, model), let f = WorkPlanes.frame(w, model) else { return nil }
        return (f, w)
    }

    var fm3dSelectedShelf: Element? { selection.count == 1 ? model[selection[0]].flatMap { $0.furnitureShelf != nil ? $0 : nil } : nil }
    var fm3dSelectedExtrusion: Element? {
        guard selection.count == 1, let e = model[selection[0]], e.furnitureForm?.kind == .extrusion else { return nil }
        return e
    }

    /// Where a command's tool draws in the 3D view: on what it edits, else on the work plane (or the tool's default).
    func fm3dPlacement(_ id: CommandID) -> FurniturePlacement3D? {
        let m = model
        switch id {
        case .editBoundary:
            guard let s = fm3dSelectedShelf, let host = FurniturePlacements.planHost(m) else { return nil }
            return FurniturePlacements.placement(host: host, through: Vec3(0, 0, s.furnitureShelf?.elevation ?? 0), normal: .unitZ, m)
        case .furnitureEditProfile:
            return fm4SelectedPanels.first.flatMap { FurniturePlacements.panelFace($0, m) }
        case .furniturePanelOpening where fm4SelectedPanels.count == 1:
            return FurniturePlacements.panelFace(fm4SelectedPanels[0], m)
        case .furnitureBlendEditTop, .furnitureBlendEditBase:
            guard fmg1SelectedBlend != nil, let host = FurniturePlacements.planHost(m) else { return nil }
            return FurniturePlacements.placement(host: host, through: Vec3(0, 0, m.elevation(ofLevel: m.levels.first?.id)), normal: .unitZ, m)
        case .furnitureEditSketch:
            return fm3dSelectedExtrusion.flatMap { FurnitureFormEdit.placement($0, m) }
        default:
            guard let need = FurniturePlacements.need(id) else { return nil }
            let level = state.active3DTools?.workPlaneLevel ?? m.levels.first?.id
            let z = m.elevation(ofLevel: level)
            if let w = fm3dWorkPlane() { return FurniturePlacements.resolve(need, workPlane: w.frame, reference: w.ref, level: z, m) }
            let lf = WorkPlaneFrame(origin: Vec3(0, 0, z), u: .unitX, v: .unitY)
            return FurniturePlacements.resolve(need, workPlane: lf, reference: level.map { .level($0) }, level: z, m)
        }
    }

    /// The context of a Furniture tool on a 3D placement: the host view's, drawing on the placement's plane.
    func fm3dContext(_ p: FurniturePlacement3D) -> ToolContext {
        let base = state.toolContext(for: p.hostViewID)
        let c = ToolContext(session: session, viewID: p.hostViewID)
        c.currentTypes = state.currentTypes
        c.snapSettings = base.snapSettings
        c.showMessage = base.showMessage
        c.requestText = base.requestText
        c.requestConfirmation = base.requestConfirmation
        c.toolFinished = base.toolFinished
        c.presentError = base.presentError
        c.pixel = state.active3DTools?.context()?.pixel ?? 0.001
        c.furniture3D = p
        c.sketchPlane = p.host
        return c
    }

    /// The tool a command makes on a context (the Furniture batches' own tool factories).
    func fm3dTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        if id == .furnitureEditSketch, let e = fm3dSelectedExtrusion { return FurnitureFormEdit.tool(c, e) }
        return fm4MakeTool(id, c) ?? fm5MakeTool(id, c) ?? fmg1MakeTool(id, c)
    }

    /// FM3D: availability in a Furniture document's 3D view: `.some(nil)` runs, `.some(reason)` is disabled, nil defers
    /// to the other checks.
    func fm3dDisabledReason3D(_ id: CommandID) -> String?? {
        guard fm3dIn3D else { return nil }
        if id == .editBoundary {
            guard fm3dSelectedShelf != nil else { return nil }
            return .some(fm3dPlacement(id) == nil ? "Add a floor plan to edit the boundary in 3D." : nil)
        }
        guard Self.fm3dToolIDs.contains(id) else { return nil }
        switch id {
        case .furnitureEditProfile:
            guard fm4SelectedPanels.count == 1, selection.count == 1 else { return .some("Select one panel.") }
            guard fm4SelectedPanels[0].furniturePanel?.plane == .xy else { return .some("Edit the profile of a panel drawn in plan.") }
            return .some(fm3dPlacement(id) == nil ? "Add an elevation that looks at the panel's face." : nil)
        case .furnitureAttach, .furniturePickNewHost:
            if let r = fm4DisabledReason(id) ?? fm5DisabledReason(id), r.hasPrefix("Select") { return .some(r) }
        case .furnitureBlendEditTop, .furnitureBlendEditBase:
            if fmg1BlendSketch != nil { return nil } // switching the running sketch: as in 2D
            guard fmg1SelectedBlend != nil else { return .some("Sketch or select a blend.") }
        case .furnitureEditSketch:
            guard fm3dSelectedExtrusion != nil else { return .some("Select one extrusion.") }
        default:
            // Commands without a tool (Flip, Reset Profile, Detach…) act on the selection, in any view.
            guard FurniturePlacements.need(id) != nil else { return nil }
        }
        return .some(fm3dPlacement(id) == nil ? "Add a floor plan and the Front, Back, Left and Right elevations to draw this in 3D." : nil)
    }

    /// FM3D: the tool for a Furniture command in a 3D view, on its placement; the tool takes a set work plane (a
    /// reference plane or a face) as its placement plane.
    func fm3dMakeTool3D(_ id: CommandID) -> (any InteractiveTool)? {
        guard fm3dIn3D, Self.fm3dToolIDs.contains(id) || (id == .editBoundary && fm3dSelectedShelf != nil) else { return nil }
        if (id == .furnitureBlendEditTop || id == .furnitureBlendEditBase), fmg1BlendSketch != nil { return nil }
        guard let p = fm3dPlacement(id), let tool = fm3dTool(id, fm3dContext(p)) else { return nil }
        if let w = fm3dWorkPlane(), Self.fm3dAdopts(w.ref) { (tool as? any FurnitureTool3D)?.fm3dAdopt(p) }
        return tool
    }

    /// Work planes a tool takes as its placement plane: reference planes and faces (a level is every tool's default).
    static func fm3dAdopts(_ w: WorkPlaneRef) -> Bool { if case .level = w { return false }; return true }

    /// Restarts a running Furniture tool on another placement (the face under the pointer, a new work plane), keeping
    /// its Options Bar values; `adopt` makes the tool take the placement as its plane.
    func fm3dRestart(_ old: any InteractiveTool, on p: FurniturePlacement3D, adopt: Bool = false) {
        guard let t = fm3dTool(old.commandID, fm3dContext(p)) else { return }
        for o in old.options where o.kind != .button { t.setOption(o.id, o.value) }
        if adopt { (t as? any FurnitureTool3D)?.fm3dAdopt(p) }
        state.setTool(t)
    }

    /// Restarts the running tool after the view's work plane changed (Options Bar ▸ Placement Plane).
    func fm3dWorkPlaneChanged() {
        guard let tool = state.activeTool, let p = fm3dPlacement(tool.commandID) else { return }
        let adopt = fm3dWorkPlane().map { Self.fm3dAdopts($0.ref) } ?? false
        fm3dRestart(tool, on: p, adopt: adopt)
    }

    // MARK: Batch hooks

    /// Why one of this batch's commands can't run now, or nil.
    func fm3dDisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .furniture3DDesign:
            return state.mode == .furniture ? nil : "Only in Furniture documents."
        case .furnitureEditSketch:
            guard state.mode == .furniture else { return "Only in Furniture documents." }
            guard let e = fm3dSelectedExtrusion else { return "Select one extrusion." }
            if fm3dIn3D { return nil }
            guard let map = fm4Map, map.plane == e.furnitureForm?.plane else { return "Open a view that sees the extrusion's sketch plane, or a 3D view." }
            return nil
        default: return nil
        }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fm3dMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard id == .furnitureEditSketch, let e = fm3dSelectedExtrusion else { return nil }
        return FurnitureFormEdit.tool(c, e)
    }

    /// Runs one of this batch's commands; true when handled.
    func fm3dPerform(_ id: CommandID) -> Bool {
        guard id == .furniture3DDesign else { return false }
        if let v = FurnitureDesignView.open(in: session) { state.open(v) }
        return true
    }
}
