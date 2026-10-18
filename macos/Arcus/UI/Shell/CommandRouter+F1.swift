import AppKit
import ArcusDomain
import ArcusApplication

// F1: Architecture A: Model Text, Wall: Reveal, openings, Place Model Group, spline and ellipse modes. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f1MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .modelText:
            return ModelTextTool(ctx: c) // asks for the text (Edit Text), then places it
        case .wallReveal:
            return WallRevealTool(ctx: c)
        case .placeModelGroup:
            return ModelGroupTool(ctx: c)
        case .verticalOpening, .faceOpening, .dormerOpening:
            let kind: HostedOpeningKind = id == .verticalOpening ? .vertical : id == .faceOpening ? .byFace : .dormer
            // A single selected host starts the sketch on it, as when it is picked.
            return HostedOpeningTool(ctx: c, kind: kind, host: selection.count == 1 ? selection.first : nil)
        default:
            return nil
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f1Perform(_ id: CommandID) -> Bool { false }

    /// Why one of this batch's commands can't run now, or nil.
    func f1DisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .modelText:
            return isPlan ? nil : "Open a plan view to place model text."
        case .placeModelGroup:
            guard !ModelGroups.typeNames(model).isEmpty else { return "The project has no model groups. Select elements and use Create Group first." }
            return isPlan ? nil : "Open a plan view to place a model group."
        case .wallReveal:
            // In 3D views the work-plane check follows (Viewport3DTools).
            return viewKind == .threeD || viewKind?.isVerticalCut == true ? nil : "Reveals are placed in 3D, elevation and section views."
        case .verticalOpening, .faceOpening:
            guard isPlan else { return "Open a plan view to sketch the opening." }
            return model.elements([.floors, .ceilings, .roofs]).contains { HostedOpenings.canHost($0, kind: .vertical) } ? nil : "The project has no floors, ceilings or roofs to cut."
        case .dormerOpening:
            guard isPlan else { return "Open a plan view to sketch the opening." }
            return model.elements(.roofs).contains { HostedOpenings.canHost($0, kind: .dormer) } ? nil : "The project has no footprint roofs to cut."
        default:
            return nil
        }
    }
}
