import SwiftUI
import ArcusDomain
import ArcusApplication

// COMP: the Component Library on the ribbon: Components (the dockable panel) on Create ▸ Model in Furniture
// documents and Insert ▸ Load from Library in projects; one-click hardware, Insert Assembly and Replace on the
// contextual Modify tab of doors, drawers, flaps, bays and placed components; Component BOM and Power Summary on
// Fabricate; Hardware Rules and Update Components on Manage.

extension RibbonContent {
    static var compModelItems: [RibbonItem] { [.large(.components, [.components, .componentBrowser])] }

    static var compFabricatePanels: [RibbonPanel] {
        [RibbonPanel(title: "Components", items: [.large(.componentBOM), .small(.componentPowerSummary), .small(.componentSaveSelection)], tint: furniture)]
    }

    static var compManagePanels: [RibbonPanel] {
        [RibbonPanel(title: "Components", items: [.large(.componentHardwareRules), .small(.componentUpdate), .small(.componentNewFamily)], tint: manage)]
    }

    /// One-click hardware for the selection (doors, drawers, flaps, bays, panels), Insert Assembly for one empty bay, and
    /// Replace for placed components.
    static func compSelectionItems(_ sel: [Element], _ m: BIMModel) -> [RibbonItem] {
        let actions = ComponentActions.available(for: sel.map(\.id), m)
        var items: [RibbonItem] = []
        let big: Set<ComponentAction> = [.handle, .hinges, .slides, .hangingRod]
        for a in actions { items.append(big.contains(a) ? .large(CommandCatalog.compCommand(a)) : .small(CommandCatalog.compCommand(a))) }
        if sel.count == 1, sel[0].furnitureBay != nil { items.append(.large(.componentAssembly)) }
        if sel.contains(where: { $0.category == .furnitureHardware && $0.params[FurnitureHardware.slotParam] == nil }) { items.append(.large(.componentReplace)) }
        return items
    }
}
