import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Room, area, colour fill and Tag All commands (WP6b), routed from `CommandRouter`.
extension CommandRouter {
    /// Availability for the room/area/colour fill commands; nil when the command can run.
    func roomAreaDisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .placeRoomsAutomatically:
            if !isPlan { return "Open a floor plan to place rooms." }
            if viewKind == .areaPlan { return "In area plans, use Place Areas Automatically." }
        case .placeAreasAutomatically:
            if viewKind != .areaPlan { return "Open an area plan (View ▸ Area Plan)." }
        case .area, .areaBoundary:
            if isPlan && viewKind != .areaPlan { return "Open an area plan (View ▸ Area Plan)." }
        case .colorFillLegend:
            if !(isPlan || viewKind == .section || viewKind == .detail) { return "Color fill legends go in plan and section views." }
        default:
            break
        }
        return nil
    }

    /// Places rooms (or areas) in every unoccupied enclosed region of the active plan's level.
    func placeAutomatically(areas: Bool) {
        let tool: RoomTool
        if let t = state.activeTool as? RoomTool, t.isArea == areas {
            tool = t
        } else if let c = ctx() {
            tool = RoomTool(ctx: c, isArea: areas)
        } else {
            return
        }
        var shown: String?
        let previous = tool.ctx.showMessage
        tool.ctx.showMessage = { shown = $0 }
        let count = tool.placeAutomatically()
        tool.ctx.showMessage = previous
        if let shown { state.show(shown, error: count == 0 && session.lastError != nil) }
        state.toolChangedState()
    }

    /// Starts the legend tool, or asks for a colour scheme first when the view has none.
    func colorFillLegendTool(_ c: ToolContext) -> (any InteractiveTool)? {
        guard let v = state.activeView else { return nil }
        if ColorFill.scheme(for: v, model) == nil {
            state.presented = .colorSchemes(v.id, placeLegend: true)
            return nil
        }
        return ColorFillLegendTool(ctx: c)
    }

    /// Element ids drawn in a view (what Tag All considers visible).
    func visibleElementIDs(_ v: ElementID) -> Set<ElementID> {
        Set(state.graphics.graphics(v)?.items.compactMap(\.elementID) ?? [])
    }
}
