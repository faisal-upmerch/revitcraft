import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// S3D2: 3D drawing tools on any work plane (Work Plane ▸ Set to a reference plane, a named plane or a picked face).
// Model lines, model text, reference planes and components draw on the 3D view's work plane with snapping and
// tracking in it, and keep it as their sketch plane. Walls, floors and the other level-based tools stay on the level,
// as in Revit.

extension CommandRouter {
    /// Commands whose elements can sit on any work plane.
    static let s3d2SketchCommands: Set<CommandID> = [.modelLine, .referencePlane, .modelText, .component]

    /// In a 3D view model text runs on the work plane like model lines (it is level-based in plan views only).
    func s3d2DisabledReason(_ id: CommandID) -> String?? {
        guard viewKind == .threeD, state.activeViewportEditor == nil, id == .modelText else { return nil }
        guard let tools = state.active3DTools, tools.activeSketchPlane != nil || tools.workPlaneLevel != nil else {
            return .some("Add a floor plan for a level, or set a work plane, to place model text in 3D.")
        }
        return .some(nil)
    }

    /// The tool for a work-plane command in a 3D view whose work plane is not a level: its context draws on that plane.
    func s3d2MakeTool(_ id: CommandID) -> (any InteractiveTool)? {
        guard viewKind == .threeD, state.activeViewportEditor == nil, Self.s3d2SketchCommands.contains(id),
              let tools = state.active3DTools, let sp = tools.activeSketchPlane, let base = tools.context() else { return nil }
        // A context of its own: the plan context stays as it is for plan views.
        let c = ToolContext(session: session, viewID: base.viewID)
        c.currentTypes = state.currentTypes
        c.snapSettings = base.snapSettings
        c.showMessage = base.showMessage
        c.requestText = base.requestText
        c.requestConfirmation = base.requestConfirmation
        c.toolFinished = base.toolFinished
        c.presentError = base.presentError
        c.pixel = base.pixel
        c.sketchPlane = sp
        switch id {
        case .modelLine: return LineTool(ctx: c, kind: .model, commandID: .modelLine)
        case .referencePlane: return LineTool(ctx: c, kind: .referencePlane, commandID: .referencePlane)
        case .modelText: return ModelTextTool(ctx: c)
        case .component: return ComponentTool(ctx: c, category: componentCategory(), commandID: .component)
        default: return nil
        }
    }
}
