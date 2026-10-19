import SwiftUI
import ArcusDomain
import ArcusApplication

// FM3: the Furniture mode ribbon (Docs/FurnitureMode.md §3, "Mode in the shell"): Create, Insert, Annotate,
// Fabricate, View, Manage and Modify. Insert, Annotate, View and Manage reuse the main app's panels where they make
// sense, without the Architecture-only tools.
//
// Later milestones add their panels in the marked slots below (one declaration each, so batches don't edit the same
// lines): FM4 parts, FM5 openings and hardware, FM6 joints, FM7 fabrication, FM9 the furniture library.

extension RibbonTab {
    /// The tabs of a mode, in order.
    static func tabs(for kind: DocumentKind) -> [RibbonTab] { FurnitureShell.ribbonTabs(kind).compactMap(RibbonTab.init(rawValue:)) }
    /// The tab a window of the mode opens on (Architecture, or Create).
    static func defaultTab(for kind: DocumentKind) -> RibbonTab { RibbonTab(rawValue: FurnitureShell.defaultTab(kind)) ?? .architecture }
}

extension RibbonContent {
    static let furniture = Color(red: 0.72, green: 0.47, blue: 0.24)

    /// The panels of a Furniture document's tab (after Select).
    static func furnitureTabPanels(_ tab: RibbonTab) -> [RibbonPanel] {
        switch tab {
        case .create: return furnitureCreatePanels
        case .insert: return furnitureInsertPanels
        case .annotate: return withoutArchitecture(tabPanels(.annotate))
        case .fabricate: return furnitureFabricatePanels
        case .view: return withoutArchitecture(tabPanels(.view))
        case .manage: return furnitureManagePanels
        case .modify: return fm6ModifyPanels(tabPanels(.modify)) + [familyEditorPanel] // FM6: Joint on Modify ▸ Geometry
        default: return withoutArchitecture(tabPanels(tab))
        }
    }

    /// The Family Editor panel on the contextual Modify tab of Furniture documents (none in projects).
    static func furnitureContextualPanels(_ state: DocumentState) -> [RibbonPanel] {
        state.mode == .furniture && state.activeTool == nil ? [familyEditorPanel] : []
    }

    // MARK: Create

    static var furnitureCreatePanels: [RibbonPanel] {
        [furniturePropertiesPanel] + fm4CreatePanels + fm5CreatePanels
            + [furnitureFormsPanel, furnitureModelPanel, furnitureDatumPanel, RibbonPanel(title: "Work Plane", items: furnitureWorkPlaneItems, tint: datum), familyEditorPanel]
    }

    static let furniturePropertiesPanel = RibbonPanel(title: "Properties", items: [.large(.furnitureFamilyTypes), .large(.furnitureCategory), .small(.toggleProperties)], tint: furniture)

    /// Forms: free shapes (FM4: Extrusion, Blend, Revolve, Sweep, Swept Blend, Cushion, Void Forms).
    static let furnitureFormsPanel = RibbonPanel(title: "Forms", items: fm4FormItems, tint: build)

    static var furnitureModelPanel: RibbonPanel {
        RibbonPanel(title: "Model", items: [.large(.component, [.component, .componentLibrary])] + compModelItems + fm5ModelItems + [.small(.modelLine), .small(.modelText)], tint: build) // COMP: Components
    }

    static let furnitureDatumPanel = RibbonPanel(title: "Datum", items: [.large(.referencePlane)], tint: datum)
    static let furnitureWorkPlaneItems: [RibbonItem] = [.large(.workPlaneSet), .small(.workPlaneShow), .small(.workPlaneViewer)]

    /// Load into Project, Load into Project and Close, Flex (on Create and Modify, as in the Family Editor).
    static let familyEditorPanel = RibbonPanel(title: "Family Editor", items: [.large(.furnitureLoadIntoProject), .large(.furnitureLoadAndClose), .small(.furnitureFlex),
                                                                             .small(.saveAsFurnitureTemplate)], tint: furniture) // FM8: Save as Furniture Template

    // MARK: Insert

    static var furnitureInsertPanels: [RibbonPanel] {
        [RibbonPanel(title: "Import", items: [.large(.importCAD), .large(.importImage)], tint: build),
         RibbonPanel(title: "Load from Library", items: [.large(.loadFamily)] + fm9InsertItems + [.large(.componentLibrary)], tint: build)]
    }

    // MARK: Fabricate

    static var furnitureFabricatePanels: [RibbonPanel] {
        fm6FabricatePanels + fm7FabricatePanels + compFabricatePanels // COMP: Component BOM, Power Summary
            + [RibbonPanel(title: "Schedules", items: [.large(.schedule)], tint: view), // FM7: Material Takeoff opens the piece's takeoff (Part List panel)
               RibbonPanel(title: "Export", items: [.large(.exportPDF), .small(.exportDXF), .small(.exportDWG), .small(.exportImage)], tint: sheet)]
    }

    // MARK: Manage

    static var furnitureManagePanels: [RibbonPanel] {
        [RibbonPanel(title: "Settings", items: [.large(.materials), .small(.objectStyles), .small(.projectUnits), .small(.projectInfo),
                                                .small(.snapSettings), .small(.purgeUnused),
                                                .small(.additionalSettings, [.additionalSettings, .lineStyles, .lineWeights, .linePatterns, .fillPatterns, .arrowheads, .temporaryDimensionSettings])], tint: manage)]
            + fm6ManagePanels + fm7ManagePanels + compManagePanels // COMP: Hardware Rules, Update Components
            + [RibbonPanel(title: "Inquiry", items: [.small(.warnings), .small(.selectByID), .small(.idsOfSelection)], tint: manage),
               RibbonPanel(title: "Add-Ins", items: [.large(.designWithClaude)], tint: manage)] // MCP: Design with Claude
    }

    /// Panels without the tools a furniture piece has no use for (walls, rooms, site, structure…); empty panels go.
    static func withoutArchitecture(_ panels: [RibbonPanel]) -> [RibbonPanel] {
        let blocked = FurnitureShell.architectureOnly
        return panels.compactMap { p in
            let items = p.items.compactMap { item -> RibbonItem? in
                guard !blocked.contains(item.id) else { return nil }
                var i = item
                i.variants = item.variants.filter { !blocked.contains($0) }
                return i
            }
            return items.isEmpty ? nil : RibbonPanel(title: p.title, items: items, tint: p.tint)
        }
    }

    // MARK: Slots for later milestones

    // FM4 panels: Parts (Panel, Shelf, Top, Back, Divider, Leg, Rail, Plinth, Edge Profile) on Create, after Properties.
    static var fm4CreatePanels: [RibbonPanel] {
        [RibbonPanel(title: "Parts", items: [.large(.furniturePanel), .large(.furnitureShelf), .large(.furnitureTop),
                                             .small(.furnitureBack), .small(.furnitureDivider), .small(.furniturePlinth),
                                             .large(.furnitureLeg, [.furnitureLeg, .furnitureLegsAtCorners]), .large(.furnitureRail, [.furnitureRail, .furnitureSlats]),
                                             .large(.furnitureEdgeProfile, [.furnitureEdgeProfile, .furnitureGroove])], tint: furniture)]
    }

    // FM4 panels: Furniture forms (Extrusion, Blend, Revolve, Sweep, Swept Blend, Cushion, Void Forms) on Create ▸ Forms.
    static var fm4FormItems: [RibbonItem] {
        [.large(.furnitureExtrusion), .large(.furnitureBlend), .large(.furnitureRevolve), .small(.furnitureSweep), .small(.furnitureSweptBlend), .small(.furnitureCushion),
         .large(.furnitureVoidExtrusion, [.furnitureVoidExtrusion, .furnitureVoidBlend, .furnitureVoidRevolve, .furnitureVoidSweep, .furnitureVoidSweptBlend])]
    }

    // FM4 panels: the contextual Modify | Panels, Legs… panel (Edit Profile, Opening, Attach Top/Base, Detach, Flip).
    static func fm4SelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        let parts = sel.filter { $0.category.isFurniturePart }
        guard !parts.isEmpty else { return (nil, []) }
        var items: [RibbonItem] = []
        if parts.contains(where: { $0.furniturePanel != nil }) {
            items += [.large(.furnitureEditProfile), .small(.furnitureResetProfile), .small(.furniturePanelOpening), .small(.furnitureFlipPanel)]
        }
        if parts.contains(where: { $0.furniturePanel?.plane == .xy || $0.furnitureLeg != nil }) { items += [.large(.furnitureAttach), .small(.furnitureDetach)] }
        if parts.count == 1, parts[0].furnitureShelf != nil { items += [.large(.furnitureLegsAtCorners)] }
        let title = parts.allSatisfy({ $0.furniturePanel != nil }) ? "Modify Panel" : parts.allSatisfy({ $0.furnitureLeg != nil }) ? "Modify Leg" : "Modify Part"
        return items.isEmpty ? (nil, []) : (title, items)
    }

    // FM5 panels: Openings (Bay, Bay Divide, Door, Drawer, Flap) on Create, after Parts.
    static var fm5CreatePanels: [RibbonPanel] {
        [RibbonPanel(title: "Openings", items: [.large(.furnitureBay), .small(.furnitureBaySeparator), .small(.furnitureBayDivide), .small(.furnitureBayTag),
                                                .large(.furnitureDoor), .large(.furnitureDrawer), .large(.furnitureFlap)], tint: furniture)]
    }

    // FM5 panels: Hardware on Create ▸ Model, after Component.
    static var fm5ModelItems: [RibbonItem] { [.large(.furnitureHardware)] }

    // FM5 panels: the contextual Modify | Doors, Drawers, Flaps and Bays panel.
    static func fm5SelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        let fronts = sel.filter { $0.furnitureFront != nil }, bays = sel.filter { $0.furnitureBay != nil }
        if !fronts.isEmpty {
            var items: [RibbonItem] = []
            if fronts.contains(where: { $0.furnitureFront?.kind == .door }) { items.append(.large(.furnitureFlipHinge)) }
            items += [.large(.furniturePickNewHost), .small(.furnitureSelectHardware)]
            let kinds = Set(fronts.compactMap { $0.furnitureFront?.kind })
            return (kinds.count == 1 ? "Modify \(kinds.first!.rawValue)" : "Modify Front", items)
        }
        if !bays.isEmpty {
            var items: [RibbonItem] = [.large(.furnitureBayDivide)]
            if bays.contains(where: { $0.furnitureBay?.division != nil }) { items.append(.small(.furnitureRemoveDivide)) }
            items.append(.small(.furnitureBayTag))
            return ("Modify Bay", items)
        }
        return (nil, [])
    }

    /// FM5: the contextual tab's name for selected fronts, as Revit names it by category: Doors, Drawers, Flaps.
    static func fm5SelectionTitle(_ sel: [Element]) -> String? {
        guard !sel.isEmpty, sel.allSatisfy({ $0.furnitureFront != nil }) else { return nil }
        let kinds = Set(sel.compactMap { $0.furnitureFront?.kind })
        guard kinds.count == 1, let k = kinds.first else { return "Doors and Drawers" }
        return k.rawValue + "s"
    }

    // FM6 panels: Joint and Joint Rules on Fabricate.
    static var fm6FabricatePanels: [RibbonPanel] {
        [RibbonPanel(title: "Joints", items: [.large(.furnitureJoint), .large(.furnitureJointRules), .small(.furnitureAllowJoin), .small(.furnitureDisallowJoin)], tint: furniture)]
    }

    // FM6 panels: Joint Rules on Manage.
    static var fm6ManagePanels: [RibbonPanel] { [RibbonPanel(title: "Joints", items: [.large(.furnitureJointRules)], tint: manage)] }

    /// FM6: Modify ▸ Geometry in Furniture documents has Joint and Allow/Disallow Join for parts where projects have the
    /// walls' Allow/Disallow Join (as Wall Joins sits there in Revit).
    static func fm6ModifyPanels(_ panels: [RibbonPanel]) -> [RibbonPanel] {
        panels.map { p in
            guard p.title == "Geometry" else { return p }
            var items = p.items.filter { $0.id != .joinGeometry }
            items.insert(.large(.furnitureJoint), at: 0)
            items.append(.small(.furnitureAllowJoin, [.furnitureAllowJoin, .furnitureDisallowJoin]))
            return RibbonPanel(title: p.title, items: items, tint: p.tint)
        }
    }

    /// FM6: the contextual tab's joint items for selected parts.
    static func fm6SelectionItems(_ sel: [Element]) -> [RibbonItem] {
        sel.contains(where: { $0.category.isFurniturePart && $0.furnitureEdgeProfile == nil && $0.furnitureForm == nil })
            ? [.large(.furnitureJoint), .small(.furnitureAllowJoin), .small(.furnitureDisallowJoin)] : []
    }

    /// FM6: the contextual Modify | Joints tab's panel while the Joint tool runs.
    static func fm6ToolPanels(_ tool: any InteractiveTool) -> [RibbonPanel] {
        tool is FurnitureJointTool ? [RibbonPanel(title: "Joints", items: [.large(.furnitureJointRules)], tint: furniture)] : []
    }

    // FM7 panels: Part List, Hardware Schedule, Material Takeoff, Nesting, CNC Export, Check Parts on Fabricate.
    static var fm7FabricatePanels: [RibbonPanel] {
        [RibbonPanel(title: "Part List", items: [.large(.furniturePartList), .large(.furnitureHardwareSchedule), .small(.furnitureMaterialTakeoff),
                                                 .small(.furnitureEdgeBanding), .small(.furnitureCost)], tint: view),
         RibbonPanel(title: "Nesting", items: [.large(.furnitureNesting), .large(.furnitureStockSheets)], tint: furniture),
         RibbonPanel(title: "Output", items: [.large(.furnitureCNCExport), .large(.furnitureShopDrawings), .large(.furnitureExplodeParts), .large(.furnitureCheckParts)], tint: sheet)]
    }

    // FM7 panels: Stock Sheets and Hardware Catalog on Manage.
    static var fm7ManagePanels: [RibbonPanel] {
        [RibbonPanel(title: "Fabrication", items: [.large(.furnitureStockSheets), .large(.furnitureHardwareCatalog), .small(.furnitureCheckParts)], tint: manage)]
    }

    // FM9 panels: Load Furniture on Insert ▸ Load from Library.
    static var fm9InsertItems: [RibbonItem] { [.large(.loadFurniture)] } // FM8: the Load Furniture command (FM9 fills the library)
}
