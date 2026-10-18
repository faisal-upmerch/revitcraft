import AppKit
import ArcusDomain
import ArcusApplication

// F2: Architecture B: stacked walls, multi-segment grids, work planes, multistory stairs, roof tools, slanted columns. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    static let f2ColumnModes: Set<CommandID> = [.verticalColumn, .slantedColumn, .columnsAtGrids, .columnsAtColumns]

    /// The tool for one of this batch's commands, or nil.
    func f2MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .stackedWall:
            return stackedWallTool(c)
        case .gridMultiSegment:
            return GridSketchTool(ctx: c)
        case .editBoundary:
            // A multi-segment grid edits its path in sketch mode.
            guard selection.count == 1, let g = model[selection[0]]?.grid, g.isMultiSegment else { return nil }
            return GridSketchTool(ctx: c, editing: selection[0])
        case .structuralColumn:
            return StructuralColumnTool(ctx: c)
        case _ where Self.f2ColumnModes.contains(id):
            // A running column tool switches mode (f2Perform); otherwise the tool starts in that mode.
            guard !(state.activeTool is StructuralColumnTool) else { return nil }
            let t = StructuralColumnTool(ctx: c)
            setColumnMode(id, t)
            return t
        default:
            return nil
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f2Perform(_ id: CommandID) -> Bool {
        switch id {
        case .workPlaneSet:
            guard let v = state.editingViewID else { return true }
            state.presented = .f2(.workPlane(v))
        case .workPlaneShow:
            guard let v = state.editingViewID else { return true }
            WorkPlanes.toggleShown(v, in: session)
            state.active3DTools?.refresh()
        case .workPlaneViewer:
            guard let v = state.editingViewID, let view = model[v] else { return true }
            let plane = WorkPlanes.current(view, model) ?? (view.view?.kind == .threeD ? state.active3DTools?.workPlaneLevel.map { .level($0) } : nil)
            guard let plane else { state.show("This view's work plane is its own plane. Use Set to choose a level or a reference plane."); return true }
            WorkPlaneViewer.open(state, viewID: v, plane: plane)
        case .connectLevels:
            let stair = selection.count == 1 && model[selection[0]]?.stair != nil ? selection[0] : nil
            state.presented = .f2(.connectLevels(stair))
        case .sketchBoundaryLine, .slopeArrow, .alignEaves, .adjustHeight, .adjustOverhang:
            guard let t = state.activeTool as? SketchTool else { return true }
            switch id {
            case .sketchBoundaryLine: t.drawBoundaryLines()
            case .slopeArrow: t.drawSlopeArrow()
            case .alignEaves: t.alignEaves()
            case .adjustHeight: t.setEaveAdjustment(.height)
            default: t.setEaveAdjustment(.overhang)
            }
            state.toolChangedState()
        case _ where Self.f2ColumnModes.contains(id):
            guard let t = state.activeTool as? StructuralColumnTool else { return true }
            setColumnMode(id, t)
            state.toolChangedState()
        case .multipleFinish:
            _ = (state.activeTool as? StructuralColumnTool)?.finish()
            state.toolChangedState()
        case .multipleCancel:
            (state.activeTool as? StructuralColumnTool)?.cancelMultiple()
            state.toolChangedState()
        default:
            return false
        }
        return true
    }

    func setColumnMode(_ id: CommandID, _ t: StructuralColumnTool) {
        switch id {
        case .verticalColumn: t.placeVertical()
        case .slantedColumn: t.placeSlanted()
        case .columnsAtGrids: t.pickMultiple(.atGrids)
        default: t.pickMultiple(.atColumns)
        }
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f2DisabledReason(_ id: CommandID) -> String? {
        let sketch = state.activeTool as? SketchTool
        switch id {
        case .stackedWall:
            return isPlan || viewKind == .threeD ? nil : "Open a plan or 3D view to draw walls."
        case .gridMultiSegment:
            return isPlan ? nil : "Open a plan view to sketch grids."
        case .workPlaneSet, .workPlaneShow, .workPlaneViewer:
            guard let k = viewKind, k.isPlan || k.isVerticalCut || k == .threeD else { return "Open a plan, section, elevation or 3D view." }
            return nil
        case .connectLevels:
            if state.activeTool is StairTool { return nil }
            return selection.count == 1 && model[selection[0]]?.stair != nil ? nil : "Select one stair, or start placing a stair."
        case .sketchBoundaryLine, .slopeArrow:
            guard let s = sketch, [.floor, .ceiling, .roof].contains(s.target) else { return "Available while sketching a floor, ceiling or roof." }
            return nil
        case .alignEaves:
            return sketch?.target == .roof ? nil : "Available while sketching a roof footprint."
        case .adjustHeight, .adjustOverhang:
            guard sketch?.target == .roof else { return "Available while sketching a roof footprint." }
            return sketch?.isAligningEaves == true ? nil : "Available in Align Eaves mode."
        case _ where Self.f2ColumnModes.contains(id):
            return state.activeTool is StructuralColumnTool || isPlan ? nil : "Open a plan view to place columns."
        case .multipleFinish, .multipleCancel:
            return (state.activeTool as? StructuralColumnTool)?.multiple != nil ? nil : "Pick At Grids or At Columns first."
        default:
            return nil
        }
    }

    /// The Wall tool with a stacked wall type selected, adding the starter stacked type to projects without one.
    func stackedWallTool(_ c: ToolContext) -> (any InteractiveTool)? {
        if !model.types(for: .walls).contains(where: { $0.typeData?.stack != nil }) {
            let metric = model.units.system != .imperial
            session.perform("Add Stacked Wall Type") { tx in StackedWallDefaults.populate(tx, metric: metric) }
            if let e = session.lastError { state.show(e.message, error: true); return nil }
        }
        let stacked = model.types(for: .walls).filter { $0.typeData?.stack != nil }
        guard let type = state.currentTypes[.walls].flatMap({ id in stacked.first { $0.id == id } }) ?? stacked.first else {
            state.show("Add a basic wall type first: a stacked wall is made of basic wall types.", error: true); return nil
        }
        state.currentTypes[.walls] = type.id
        for tc in state.toolContexts.values { tc.currentTypes = state.currentTypes }
        c.currentTypes = state.currentTypes
        return WallTool(ctx: c, mode: .line, commandID: .stackedWall)
    }
}
