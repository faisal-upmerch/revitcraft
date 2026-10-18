import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Walls, curtain walls and openings (WP3): availability and tool creation.
extension CommandRouter {
    static let wp3Commands: Set<CommandID> = [.curtainWall, .curtainGrid, .mullion, .curtainPanel, .wallOpening, .shaftOpening]

    func wp3DisabledReason(_ id: CommandID) -> String? {
        guard Self.wp3Commands.contains(id) else { return nil }
        switch id {
        case .curtainWall, .shaftOpening:
            return isPlan ? nil : "Open a plan view to use this tool."
        case .wallOpening:
            return (viewKind?.isVerticalCut ?? false) ? nil : "Open an elevation or section that shows the wall."
        case .curtainGrid, .mullion, .curtainPanel:
            guard isPlan || (viewKind?.isVerticalCut ?? false) else { return "Open a plan, elevation or section." }
            return model.elements(.walls).contains { CurtainWallGeometry.isCurtain($0, model) } ? nil : "The project has no curtain walls yet."
        default:
            return nil
        }
    }

    /// Starts the WP3 tool for `id`.
    func runWP3Tool(_ id: CommandID) {
        guard let c = ctx() else { return }
        let tool: (any InteractiveTool)?
        switch id {
        case .curtainWall:
            tool = curtainWallTool(c)
        case .curtainGrid: tool = CurtainGridTool(ctx: c)
        case .mullion: tool = MullionTool(ctx: c)
        case .curtainPanel:
            if state.currentTypes[.curtainPanels] == nil, let first = model.types(for: .curtainPanels).first {
                state.currentTypes[.curtainPanels] = first.id
                c.currentTypes[.curtainPanels] = first.id
            }
            tool = CurtainPanelTool(ctx: c)
        case .wallOpening: tool = WallOpeningTool(ctx: c)
        case .shaftOpening: tool = ShaftOpeningTool(ctx: c)
        default: tool = nil
        }
        if let tool { state.setTool(tool) }
    }

    /// The Wall tool with a curtain wall type selected, adding the starter curtain types to projects without any.
    func curtainWallTool(_ c: ToolContext) -> (any InteractiveTool)? {
        if !model.types(for: .walls).contains(where: { $0.typeData?.curtain != nil }) {
            session.perform("Add Curtain Wall Types") { tx in CurtainWallDefaults.populate(tx) }
            if let e = session.lastError { state.show(e.message, error: true); return nil }
        }
        let curtainTypes = model.types(for: .walls).filter { $0.typeData?.curtain != nil }
        let chosen = state.currentTypes[.walls].flatMap { id in curtainTypes.first { $0.id == id } } ?? curtainTypes.first { $0.name == "Storefront" } ?? curtainTypes.first
        guard let type = chosen else { return nil }
        state.currentTypes[.walls] = type.id
        for tc in state.toolContexts.values { tc.currentTypes = state.currentTypes }
        c.currentTypes = state.currentTypes
        return WallTool(ctx: c, mode: .line, commandID: .curtainWall)
    }
}
