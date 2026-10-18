import AppKit
import ArcusDomain
import ArcusApplication

// F34: Structure and reinforcement: truss, brace, beam system, structural settings, rebar, area/path/fabric reinforcement. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    static let f34PlanTools: Set<CommandID> = [.truss, .brace, .beamSystem, .rebar, .rebarCoupler, .couplerOnBarEnd, .couplerBetweenBars,
                                               .beamSymbol, .areaReinforcementSymbol, .pathReinforcementSymbol, .rebarSymbol, .fabricSymbol,
                                               .multiRebarAligned, .multiRebarLinear]
    /// Reinforcement sketched on floors in plans or on walls in sections and elevations.
    static let f34HostTools: Set<CommandID> = [.areaReinforcement, .pathReinforcement, .fabricArea, .fabricSheet]

    /// The tool for one of this batch's commands, or nil.
    func f34MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        // A single selected floor or wall becomes the host of Area, Path and Fabric Area.
        let host = selection.count == 1 ? selection[0] : nil
        f34EnsureTypes(id)
        switch id {
        case .editBoundary:
            // Beam systems and floor reinforcement edit their boundary in sketch mode.
            guard let h = host, let e = model[h], let target = F34SketchTarget.editing(e) else { return nil }
            let t = SketchTool(ctx: c, target: .f34(target), commandID: .editBoundary, editing: h)
            t.drawMode = .line
            return t
        case .truss: return TrussBraceTool(ctx: c, kind: .truss)
        case .brace: return TrussBraceTool(ctx: c, kind: .brace)
        case .beamSystem:
            let t = SketchTool(ctx: c, target: .f34(.beamSystem), commandID: .beamSystem)
            t.drawMode = .line
            return t
        case .rebar: return RebarTool(ctx: c)
        case .areaReinforcement: return ReinforcementSketchTool(ctx: c, kind: .area, host: host)
        case .pathReinforcement: return ReinforcementSketchTool(ctx: c, kind: .path, host: host)
        case .fabricArea: return ReinforcementSketchTool(ctx: c, kind: .fabricArea, host: host)
        case .fabricSheet: return FabricSheetTool(ctx: c)
        case .rebarCoupler: return RebarCouplerTool(ctx: c)
        case .couplerOnBarEnd, .couplerBetweenBars:
            // With the coupler tool running these switch its placement (f34Perform).
            if state.activeTool is RebarCouplerTool { return nil }
            return RebarCouplerTool(ctx: c, between: id == .couplerBetweenBars)
        case .beamSymbol: return StructuralSymbolTool(ctx: c, kind: .beamSystem, commandID: id)
        case .areaReinforcementSymbol: return StructuralSymbolTool(ctx: c, kind: .areaReinforcement, commandID: id)
        case .pathReinforcementSymbol: return StructuralSymbolTool(ctx: c, kind: .pathReinforcement, commandID: id)
        case .rebarSymbol: return StructuralSymbolTool(ctx: c, kind: .rebar, commandID: id)
        case .fabricSymbol: return StructuralSymbolTool(ctx: c, kind: .fabric, commandID: id)
        case .multiRebarAligned: return StructuralSymbolTool(ctx: c, kind: .multiRebarAligned, commandID: id)
        case .multiRebarLinear: return StructuralSymbolTool(ctx: c, kind: .multiRebarLinear, commandID: id)
        default: return nil
        }
    }

    /// The bar and fabric sheet types are made when a reinforcement tool first starts, as in RevitCraft, so the type
    /// selector lists them.
    func f34EnsureTypes(_ id: CommandID) {
        if [.rebar, .areaReinforcement, .pathReinforcement].contains(id), model.types(for: .structuralRebar).isEmpty {
            session.perform("Rebar Types") { tx in Reinforcement.ensureBarTypes(in: tx) }
        }
        if [.fabricArea, .fabricSheet].contains(id), model.types(for: .fabricReinforcement).isEmpty {
            session.perform("Fabric Sheet Types") { tx in Reinforcement.ensureFabricType(in: tx) }
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f34Perform(_ id: CommandID) -> Bool {
        switch id {
        case .structuralSettings: state.presented = .f34(.structuralSettings)
        case .rebarCover: state.presented = .f34(.rebarCover)
        case .couplerOnBarEnd, .couplerBetweenBars:
            guard let t = state.activeTool as? RebarCouplerTool else { return false }
            t.setOption("placement", .text(RebarCouplerTool.placements[id == .couplerBetweenBars ? 1 : 0]))
            state.toolChangedState()
        default: return false
        }
        return true
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f34DisabledReason(_ id: CommandID) -> String? {
        if Self.f34PlanTools.contains(id) && !isPlan { return "Open a plan view to use this tool." }
        if Self.f34HostTools.contains(id) && !isPlan && !(viewKind?.isVerticalCut ?? false) { return "Open a plan, section or elevation to place reinforcement." }
        return nil
    }
}
