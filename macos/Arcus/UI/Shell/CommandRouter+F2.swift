import AppKit
import ArcusDomain
import ArcusApplication

// F2: Architecture B: stacked walls, multi-segment grids, work planes, multistory stairs, roof tools, slanted columns. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The tool for one of this batch's commands, or nil.
    func f2MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .stackedWall:
            return stackedWallTool(c)
        default:
            return nil
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f2Perform(_ id: CommandID) -> Bool {
        switch id {
        default:
            return false
        }
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f2DisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .stackedWall:
            return isPlan || viewKind == .threeD ? nil : "Open a plan or 3D view to draw walls."
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
