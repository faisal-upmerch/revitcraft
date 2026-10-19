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
        case .modify: return tabPanels(.modify) + [familyEditorPanel]
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

    /// Forms: free shapes. The project's in-place form tool until the Furniture forms arrive.
    static let furnitureFormsPanel = RibbonPanel(title: "Forms", items: [.large(.modelInPlace)] + fm4FormItems, tint: build)

    static var furnitureModelPanel: RibbonPanel {
        RibbonPanel(title: "Model", items: [.large(.component, [.component, .componentLibrary])] + fm5ModelItems + [.small(.modelLine), .small(.modelText)], tint: build)
    }

    static let furnitureDatumPanel = RibbonPanel(title: "Datum", items: [.large(.referencePlane)], tint: datum)
    static let furnitureWorkPlaneItems: [RibbonItem] = [.large(.workPlaneSet), .small(.workPlaneShow), .small(.workPlaneViewer)]

    /// Load into Project, Load into Project and Close, Flex (on Create and Modify, as in the Family Editor).
    static let familyEditorPanel = RibbonPanel(title: "Family Editor", items: [.large(.furnitureLoadIntoProject), .large(.furnitureLoadAndClose), .small(.furnitureFlex)], tint: furniture)

    // MARK: Insert

    static var furnitureInsertPanels: [RibbonPanel] {
        [RibbonPanel(title: "Import", items: [.large(.importCAD), .large(.importImage)], tint: build),
         RibbonPanel(title: "Load from Library", items: [.large(.loadFamily)] + fm9InsertItems + [.large(.componentLibrary)], tint: build)]
    }

    // MARK: Fabricate

    static var furnitureFabricatePanels: [RibbonPanel] {
        fm6FabricatePanels + fm7FabricatePanels
            + [RibbonPanel(title: "Schedules", items: [.large(.materialTakeoff), .large(.schedule)], tint: view),
               RibbonPanel(title: "Export", items: [.large(.exportPDF), .small(.exportDXF), .small(.exportDWG), .small(.exportImage)], tint: sheet)]
    }

    // MARK: Manage

    static var furnitureManagePanels: [RibbonPanel] {
        [RibbonPanel(title: "Settings", items: [.large(.materials), .small(.objectStyles), .small(.projectUnits), .small(.projectInfo),
                                                .small(.snapSettings), .small(.purgeUnused),
                                                .small(.additionalSettings, [.additionalSettings, .lineStyles, .lineWeights, .linePatterns, .fillPatterns, .arrowheads, .temporaryDimensionSettings])], tint: manage)]
            + fm6ManagePanels + fm7ManagePanels
            + [RibbonPanel(title: "Inquiry", items: [.small(.warnings), .small(.selectByID), .small(.idsOfSelection)], tint: manage)]
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
    static var fm4CreatePanels: [RibbonPanel] { [] }

    // FM4 panels: Furniture forms (Extrusion, Blend, Revolve, Sweep, Swept Blend, Cushion, Void Forms) on Create ▸ Forms.
    static var fm4FormItems: [RibbonItem] { [] }

    // FM5 panels: Openings (Bay, Bay Divide, Door, Drawer, Flap) on Create, after Parts.
    static var fm5CreatePanels: [RibbonPanel] { [] }

    // FM5 panels: Hardware on Create ▸ Model, after Component.
    static var fm5ModelItems: [RibbonItem] { [] }

    // FM6 panels: Joint and Joint Rules on Fabricate.
    static var fm6FabricatePanels: [RibbonPanel] { [] }

    // FM6 panels: Joint Rules on Manage.
    static var fm6ManagePanels: [RibbonPanel] { [] }

    // FM7 panels: Part List, Hardware Schedule, Material Takeoff, Nesting, CNC Export, Check Parts on Fabricate.
    static var fm7FabricatePanels: [RibbonPanel] { [] }

    // FM7 panels: Stock Sheets and Hardware Catalog on Manage.
    static var fm7ManagePanels: [RibbonPanel] { [] }

    // FM9 panels: Load Furniture on Insert ▸ Load from Library.
    static var fm9InsertItems: [RibbonItem] { [] }
}
