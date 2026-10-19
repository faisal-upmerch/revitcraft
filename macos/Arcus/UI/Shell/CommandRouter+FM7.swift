import AppKit
import ArcusDomain
import ArcusApplication

// FM7: routing for Furniture fabrication (Docs/FurnitureMode.md §3 "Fabrication outputs"). The schedule commands open
// the piece's schedule (made first in documents from before FM7); Nesting makes the Nesting views and opens the first;
// Shop Drawings updates sheets F101–F104 and opens F101; the rest open their dialogs.

extension CommandRouter {
    static let fm7IDs: Set<CommandID> = [.furniturePartList, .furnitureHardwareSchedule, .furnitureMaterialTakeoff, .furnitureEdgeBanding, .furnitureCost,
                                         .furnitureStockSheets, .furnitureHardwareCatalog, .furnitureNesting, .furnitureCNCExport, .furnitureCheckParts,
                                         .furnitureShopDrawings]

    /// Why one of this batch's commands can't run now, or nil.
    func fm7DisabledReason(_ id: CommandID) -> String? {
        guard Self.fm7IDs.contains(id) else { return nil }
        guard state.mode == .furniture else { return "Only in Furniture documents." }
        switch id {
        case .furnitureCNCExport, .furnitureCheckParts:
            return FurnitureFabrication.parts(model).isEmpty ? "Draw parts first." : nil
        default:
            return nil
        }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fm7MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }

    /// Runs one of this batch's commands; true when handled.
    func fm7Perform(_ id: CommandID) -> Bool {
        switch id {
        case .furniturePartList: fm7OpenSchedule(.partList, name: FurnitureShopDrawings.partListName)
        case .furnitureHardwareSchedule: fm7OpenSchedule(.hardwareSchedule, name: FurnitureShopDrawings.hardwareName)
        case .furnitureMaterialTakeoff: fm7OpenSchedule(.materialTakeoff, name: FurnitureShopDrawings.takeoffName)
        case .furnitureEdgeBanding: fm7OpenSchedule(.edgeBanding, name: FurnitureShopDrawings.bandingName)
        case .furnitureCost: fm7OpenSchedule(.costSummary, name: FurnitureShopDrawings.costName)
        case .furnitureStockSheets: state.presented = .fm7(.stockSheets)
        case .furnitureHardwareCatalog: state.presented = .fm7(.hardwareCatalog)
        case .furnitureCNCExport: state.presented = .fm7(.cncExport)
        case .furnitureCheckParts: state.presented = .fm7(.checkParts)
        case .furnitureNesting:
            var views: [ElementID] = []
            session.perform("Nesting") { tx in views = FurnitureShopDrawings.updateNesting(in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); return true }
            let groups = FurnitureFabrication.nesting(model)
            guard !groups.isEmpty else { state.show("No sheet parts to nest. Parts of materials priced per sheet are nested."); return true }
            let ids = views.isEmpty ? FurnitureNestingViews.views(model).map(\.id) : views
            let current = state.activeViewID.flatMap { model[$0]?.view?.kind } == .nesting ? state.activeViewID : nil
            if let open = current ?? ids.first { state.open(open) }
            let sheets = groups.reduce(0) { $0 + $1.result.sheets.count }
            let over = groups.reduce(0) { $0 + $1.result.oversize.count }
            state.show("Nesting: \(groups.count) \(groups.count == 1 ? "material" : "materials"), \(sheets) \(sheets == 1 ? "sheet" : "sheets")"
                       + (over > 0 ? ", \(over) too large for the stock (Check Parts)." : "."))
        case .furnitureShopDrawings:
            session.perform("Shop Drawings") { tx in FurnitureShopDrawings.update(in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); return true }
            if let f101 = model.sheets.first(where: { $0.sheet?.number == FurnitureShopDrawings.shopDrawing }) { state.open(f101.id) }
        default:
            return false
        }
        return true
    }

    /// Opens the piece's schedule of `kind`, making the fabrication schedules and sheets first when missing.
    func fm7OpenSchedule(_ kind: ScheduleKind, name: String) {
        func find() -> Element? { model.elements(.schedules).first { $0.schedule?.kind == kind && (kind != .materialTakeoff || $0.name == name) } }
        if find() == nil {
            session.perform("Fabrication Schedules") { tx in FurnitureShopDrawings.ensureStandard(in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); return }
        }
        if let s = find() { state.open(s.id) }
    }
}
