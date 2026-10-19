import SwiftUI
import ArcusDomain
import ArcusApplication

// STAIR: the ribbon of Create Stair / Edit Stairs ("Modify | Create Stair"): Components (Run, Landing, Support), the
// Draw gallery of the current component (Straight, Full-Step Spiral, Center-Ends Spiral, L-Shape Winder, U-Shape
// Winder, Create Sketch / Pick Two Runs, Create Sketch / Pick Edges; Boundary, Riser, Stair Path while sketching a run),
// Tools (Railing, Flip); and the Edit Path and Reset Railing buttons of a selected stair railing.

extension RibbonItem {
    /// Ribbon captions of this batch.
    static func stairCaption(_ id: CommandID, size: Size) -> String? {
        switch id {
        case .stairRunFullStepSpiral where size == .large: return "Full-Step\nSpiral"
        case .stairRunCenterEndsSpiral where size == .large: return "Center-Ends\nSpiral"
        case .stairRunLWinder where size == .large: return "L-Shape\nWinder"
        case .stairRunUWinder where size == .large: return "U-Shape\nWinder"
        case .stairRunSketch, .stairLandingSketch: return size == .large ? "Create\nSketch" : "Create Sketch"
        case .stairLandingPickRuns where size == .large: return "Pick Two\nRuns"
        case .stairSupportPickEdges where size == .large: return "Pick\nEdges"
        case .stairSketchPath where size == .large: return "Stair\nPath"
        case .stairRailingEditPath where size == .large: return "Edit\nPath"
        case .stairRailingReset where size == .large: return "Reset\nRailing"
        default: return nil
        }
    }
}

extension RibbonContent {
    /// "Modify | Create Stair" / "Modify | Edit Stairs" while the stair tool runs; "Modify | Railing Path" in Edit Path.
    @MainActor static func stairContextualTitle(_ state: DocumentState) -> String? {
        if let t = state.activeTool as? StairTool { return t.editingID == nil ? "Modify | Create Stair" : "Modify | Edit Stairs" }
        if state.activeTool is StairRailingPathTool { return "Modify | Railings > Edit Path" }
        return nil
    }

    /// Components, Draw and Tools panels of the stair tool.
    @MainActor static func stairToolPanels(_ tool: any InteractiveTool) -> [RibbonPanel] {
        guard let t = tool as? StairTool else {
            if tool is ShaftOpeningTool { return [RibbonPanel(title: "Pick", items: [.large(.shaftPickStair)], tint: build)] }
            return []
        }
        var out = [RibbonPanel(title: "Components", items: [.large(.stairComponentRun), .large(.stairComponentLanding), .large(.stairComponentSupport)], tint: circulation)]
        let draw: [CommandID]
        if t.runSketch != nil { draw = [.stairSketchBoundary, .stairSketchRiser, .stairSketchPath] }
        else {
            switch t.component {
            case .run: draw = [.stairRunStraight, .stairRunFullStepSpiral, .stairRunCenterEndsSpiral, .stairRunLWinder, .stairRunUWinder, .stairRunSketch]
            case .landing: draw = [.stairLandingPickRuns, .stairLandingSketch]
            case .support: draw = [.stairSupportPickEdges]
            }
        }
        out.append(RibbonPanel(title: "Draw", items: draw.map { .large($0) }, tint: build))
        out.append(RibbonPanel(title: "Tools", items: [.large(.stairRailingSettings), .large(.stairFlip)], tint: circulation))
        return out
    }

    /// The on state of the stair tool's buttons (nil: not a stair tool button).
    @MainActor static func stairIsActive(_ id: CommandID, _ state: DocumentState) -> Bool? {
        guard let t = state.activeTool as? StairTool else { return nil }
        let drawing = !t.modifying
        switch id {
        case .stairComponentRun: return t.component == .run
        case .stairComponentLanding: return t.component == .landing
        case .stairComponentSupport, .stairSupportPickEdges: return t.component == .support && drawing
        case .stairRunStraight: return drawing && t.component == .run && t.runSketch == nil && t.runMode == .straight
        case .stairRunFullStepSpiral: return drawing && t.component == .run && t.runMode == .fullStepSpiral
        case .stairRunCenterEndsSpiral: return drawing && t.component == .run && t.runMode == .centerEndsSpiral
        case .stairRunLWinder: return drawing && t.component == .run && t.runMode == .lWinder
        case .stairRunUWinder: return drawing && t.component == .run && t.runMode == .uWinder
        case .stairRunSketch: return t.runSketch != nil
        case .stairLandingPickRuns: return drawing && t.component == .landing && t.landingMode == .pickTwoRuns
        case .stairLandingSketch: return drawing && t.component == .landing && t.landingMode == .sketch
        case .stairSketchBoundary: return t.runSketch != nil && t.sketchLine == .boundary
        case .stairSketchRiser: return t.runSketch != nil && t.sketchLine == .riser
        case .stairSketchPath: return t.runSketch != nil && t.sketchLine == .path
        case .stair, .editStair: return true
        default: return nil
        }
    }

    /// A selected railing on a stair: Edit Path and Reset Railing.
    static func stairSelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        guard sel.count == 1, let r = sel[0].railing, r.followsHost, m[sel[0].hostID]?.stair != nil else { return (nil, []) }
        return ("Mode", [.large(.stairRailingEditPath), .large(.stairRailingReset)])
    }
}
