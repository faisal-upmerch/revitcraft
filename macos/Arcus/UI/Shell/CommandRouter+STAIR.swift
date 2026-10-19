import AppKit
import ArcusDomain
import ArcusApplication

// STAIR: routing for the stairs batch: Stair (Create Stair), its Components, Draw and Tools commands while it runs,
// the stair railing's Edit Path and Reset Railing, and the Shaft tool's Pick Stair.

extension CommandRouter {
    /// Commands that act on the running Create Stair tool.
    static let stairToolCommands: Set<CommandID> = [
        .stairComponentRun, .stairComponentLanding, .stairComponentSupport, .stairRunStraight, .stairRunFullStepSpiral, .stairRunCenterEndsSpiral,
        .stairRunLWinder, .stairRunUWinder, .stairRunSketch, .stairLandingPickRuns, .stairLandingSketch, .stairSupportPickEdges,
        .stairSketchBoundary, .stairSketchRiser, .stairSketchPath, .stairRailingSettings, .stairFlip,
    ]

    var stairTool: StairTool? { state.activeTool as? StairTool }

    /// The selected railing hosted on a stair, if exactly one is selected.
    var selectedStairRailing: Element? {
        guard selection.count == 1, let e = model[selection[0]], let r = e.railing, r.followsHost, model[e.hostID]?.stair != nil else { return nil }
        return e
    }

    /// Why one of this batch's commands can't run now, or nil.
    func stairDisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .stair:
            return state.activeView?.view?.kind.isPlan == true ? nil : "Open a plan view to create a stair."
        case _ where Self.stairToolCommands.contains(id):
            guard let t = stairTool else { return "Available while creating or editing a stair." }
            if [.stairSketchBoundary, .stairSketchRiser, .stairSketchPath].contains(id), t.runSketch == nil { return "Choose Run ▸ Create Sketch first." }
            return nil
        case .stairRailingEditPath, .stairRailingReset:
            guard let r = selectedStairRailing else { return "Select one railing on a stair." }
            if id == .stairRailingReset, r.railing?.editedHostPath == nil { return "The railing already follows the stair's edge." }
            return state.activeView?.view?.kind.isPlan == true ? nil : "Open a plan view."
        case .shaftPickStair:
            guard state.activeTool is ShaftOpeningTool else { return "Available while sketching a shaft." }
            return model.elements(.stairs).isEmpty ? "The project has no stairs." : nil
        default:
            return nil
        }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func stairMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .stair: return StairTool(ctx: c)
        case .stairRailingEditPath:
            guard let r = selectedStairRailing else { return nil }
            return StairRailingPathTool(ctx: c, railingID: r.id)
        default: return nil
        }
    }

    /// Runs one of this batch's commands; true when handled.
    func stairPerform(_ id: CommandID) -> Bool {
        if let t = stairTool, Self.stairToolCommands.contains(id) {
            switch id {
            case .stairComponentRun: t.choose(.run)
            case .stairComponentLanding: t.choose(.landing)
            case .stairComponentSupport: t.choose(.support)
            case .stairRunStraight: t.choose(StairTool.RunMode.straight)
            case .stairRunFullStepSpiral: t.choose(StairTool.RunMode.fullStepSpiral)
            case .stairRunCenterEndsSpiral: t.choose(StairTool.RunMode.centerEndsSpiral)
            case .stairRunLWinder: t.choose(StairTool.RunMode.lWinder)
            case .stairRunUWinder: t.choose(StairTool.RunMode.uWinder)
            case .stairRunSketch: t.choose(StairTool.RunMode.sketch)
            case .stairLandingPickRuns: t.choose(StairTool.LandingMode.pickTwoRuns)
            case .stairLandingSketch: t.choose(StairTool.LandingMode.sketch)
            case .stairSupportPickEdges: t.choose(.support)
            case .stairSketchBoundary: t.choose(StairTool.SketchLine.boundary)
            case .stairSketchRiser: t.choose(StairTool.SketchLine.riser)
            case .stairSketchPath: t.choose(StairTool.SketchLine.path)
            case .stairRailingSettings: StairRailingDialog.present(state: state, tool: t)
            case .stairFlip: t.flip()
            default: break
            }
            state.toolChangedState()
            return true
        }
        switch id {
        case .stairRailingReset:
            guard let r = selectedStairRailing else { return true }
            session.perform("Reset Railing") { tx in tx.update(r.id) { $0.railing?.editedHostPath = nil } }
            return true
        case .shaftPickStair:
            if let t = state.activeTool as? ShaftOpeningTool { t.pickingStair = true; state.toolChangedState() }
            return true
        default:
            return false
        }
    }
}
