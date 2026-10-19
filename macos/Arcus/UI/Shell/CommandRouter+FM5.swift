import AppKit
import ArcusDomain
import ArcusApplication

// FM5: routing for bays, fronts and hardware (Docs/FurnitureMode.md §6). Every FM5 command works only in Furniture
// documents; each tool says which views it works in, as Revit's do (bays and fronts in the Front/Back elevation, or in
// plan for top-access bays).

extension CommandRouter {
    static let fm5IDs: Set<CommandID> = [
        .furnitureBay, .furnitureBaySeparator, .furnitureBayDivide, .furnitureBayTag, .furnitureDoor, .furnitureDrawer, .furnitureFlap, .furnitureHardware,
        .furnitureFlipHinge, .furniturePickNewHost, .furnitureSelectHardware, .furnitureRemoveDivide,
    ]

    var fm5Map: FurnitureSketchMap? { FurnitureSketchMap.of(model[state.editingViewID]?.view) }
    var fm5SelectedFronts: [Element] { selection.compactMap { model[$0] }.filter { $0.furnitureFront != nil } }
    var fm5SelectedBays: [Element] { selection.compactMap { model[$0] }.filter { $0.furnitureBay != nil } }

    /// Why one of this batch's commands can't run now, or nil.
    func fm5DisabledReason(_ id: CommandID) -> String? {
        guard Self.fm5IDs.contains(id) else { return nil }
        guard state.mode == .furniture else { return "Only in Furniture documents." }
        let plane = fm5Map?.plane
        let openingView = plane == .xz || plane == .xy
        switch id {
        case .furnitureBay, .furnitureBaySeparator, .furnitureBayDivide, .furnitureBayTag, .furnitureDoor, .furnitureFlap, .furniturePickNewHost:
            if id == .furniturePickNewHost, fm5SelectedFronts.count != 1 { return "Select one door, drawer or flap." }
            return openingView ? nil : "Open the Front or Back elevation (or a plan, for top-access bays)."
        case .furnitureDrawer:
            return plane == .xz ? nil : "Open the Front or Back elevation."
        case .furnitureHardware:
            return plane == .xz || plane == .xy ? nil : "Open a plan or the Front/Back elevation."
        case .furnitureFlipHinge:
            return fm5SelectedFronts.contains { $0.furnitureFront?.kind == .door } ? nil : "Select doors."
        case .furnitureSelectHardware:
            return fm5SelectedFronts.isEmpty ? "Select doors, drawers or flaps." : nil
        case .furnitureRemoveDivide:
            return fm5SelectedBays.contains { $0.furnitureBay?.division != nil } ? nil : "Select a divided bay."
        default:
            return nil
        }
    }

    /// The standard front types and hardware in documents made before they existed, and the type a front tool starts with.
    func fm5PrepareTypes(_ kind: FrontKind?, _ c: ToolContext) {
        if model.types(for: .furnitureFronts).isEmpty || model.types(for: .furnitureHardware).isEmpty {
            session.perform("Load Doors, Drawers and Hardware") { tx in FurnitureFrontTypes.ensureStandard(in: tx) }
        }
        guard let kind else {
            if state.currentTypes[.furnitureHardware] == nil, let t = FurnitureHardware.types(.handle, model).first?.id { state.currentTypes[.furnitureHardware] = t }
            c.currentTypes[.furnitureHardware] = state.currentTypes[.furnitureHardware]
            return
        }
        if let t = state.currentTypes[.furnitureFronts], model[t]?.typeData?.familyName == kind.rawValue { c.currentTypes[.furnitureFronts] = t; return }
        if let t = FurnitureFrontTypes.firstType(kind, model) { state.currentTypes[.furnitureFronts] = t; c.currentTypes[.furnitureFronts] = t }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fm5MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard Self.fm5IDs.contains(id) else { return nil }
        switch id {
        case .furnitureBay: fm5PrepareTypes(nil, c); return FurnitureBayTool(ctx: c)
        case .furnitureBaySeparator: return FurnitureBaySeparatorTool(ctx: c)
        case .furnitureBayDivide: return FurnitureBayDivideTool(ctx: c, bay: fm5SelectedBays.first?.id)
        case .furnitureBayTag: return FurniturePickBayTool(ctx: c, purpose: .tag)
        case .furnitureDoor: fm5PrepareTypes(.door, c); return FurnitureFrontTool(ctx: c, kind: .door)
        case .furnitureDrawer: fm5PrepareTypes(.drawer, c); return FurnitureFrontTool(ctx: c, kind: .drawer)
        case .furnitureFlap: fm5PrepareTypes(.flap, c); return FurnitureFrontTool(ctx: c, kind: .flap)
        case .furnitureHardware: fm5PrepareTypes(nil, c); return FurnitureHardwareTool(ctx: c)
        case .furniturePickNewHost: return FurniturePickBayTool(ctx: c, purpose: .newHost(fm5SelectedFronts.map(\.id)))
        default: return nil
        }
    }

    /// Runs one of this batch's commands; true when handled.
    func fm5Perform(_ id: CommandID) -> Bool {
        switch id {
        case .furnitureFlipHinge:
            let doors = fm5SelectedFronts.filter { $0.furnitureFront?.kind == .door }.map(\.id)
            session.perform("Flip Hinge") { tx in for d in doors { tx.update(d) { $0.furnitureFront?.hingeFlipped.toggle() } } }
        case .furnitureSelectHardware:
            let ids = fm5SelectedFronts.flatMap { f in model.hosted(by: f.id).filter { $0.category == .furnitureHardware }.map(\.id) }
            if ids.isEmpty { state.show("These fronts have no hardware.", error: false) } else { session.selection.select(ids) }
            return true
        case .furnitureRemoveDivide:
            let bays = fm5SelectedBays.filter { $0.furnitureBay?.division != nil }.map(\.id)
            session.perform("Remove Bay Divide") { tx in for b in bays { try FurnitureBays.divide(b, nil, in: tx) } }
        default:
            return false
        }
        if let e = session.lastError { state.show(e.message, error: true) }
        return true
    }
}

/// FM5: the category a tool's Type Selector shows.
func fm5PropertiesCategory(_ cmd: CommandID) -> Category? {
    switch cmd {
    case .furnitureDoor, .furnitureDrawer, .furnitureFlap: .furnitureFronts
    case .furnitureHardware: .furnitureHardware
    default: nil
    }
}
