import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// MARK: - Model

/// Ribbon tabs, named the way users of mainstream BIM tools expect to find them.
enum RibbonTab: String, CaseIterable, Identifiable {
    case architecture = "Architecture", structure = "Structure", insert = "Insert", annotate = "Annotate", analyze = "Analyze"
    case massing = "Massing & Site", view = "View", manage = "Manage", modify = "Modify"
    var id: String { rawValue }
}

/// A ribbon button: large (icon over label) or small (icon beside label, stacked three high).
/// `variants` turn the button into a split button whose menu offers related tools.
struct RibbonItem: Hashable {
    /// `icon`: symbol only (title in the tooltip), packed three high — for dense panels such as Modify.
    enum Size { case large, small, icon }
    let id: CommandID
    var size: Size = .large
    var variants: [CommandID] = []
    /// Starts a new stacked column even when the previous one has room (keeps related small tools together).
    var breakBefore = false
    func newColumn() -> RibbonItem { var c = self; c.breakBefore = true; return c }
    static func large(_ id: CommandID, _ variants: [CommandID] = []) -> RibbonItem { RibbonItem(id: id, size: .large, variants: variants) }
    static func small(_ id: CommandID, _ variants: [CommandID] = []) -> RibbonItem { RibbonItem(id: id, size: .small, variants: variants) }
    static func icon(_ id: CommandID, _ variants: [CommandID] = []) -> RibbonItem { RibbonItem(id: id, size: .icon, variants: variants) }

    /// Ribbon captions are shorter than menu titles: a split button is named after its family
    /// ("Roof", "Stair") and long large-button captions break onto two lines at a word boundary.
    static func caption(_ id: CommandID, size: Size, split: Bool) -> String {
        if let c = f11Caption(id, size: size, split: split) { return c } // F11
        switch id {
        case .roofFootprint where split: return "Roof"
        case .structuralColumn where split: return "Column" // N2: as in RevitCraft's Build and Structure panels
        case .structuralWall where split: return "Wall"
        case .structuralFloor where split: return "Floor"
        case .joinGeometry where split: return "Allow/Disallow Join"
        case .activateViewport where split: return "Viewports"
        case .closeHiddenViews: return "Close Inactive"
        case .locationSettings where size == .large: return "Location"
        case .stairStraight where split: return "Stair"
        case .alignedDimension where split: return "Aligned"
        case .multiRebarAligned where split: return "Multi-\nRebar" // F34
        case .floorPlan where split: return "Plan\nViews"
        case .schedule where split: return "Schedules"
        case .duplicateView where split: return "Duplicate View"
        case .measureBetween where split: return "Measure"
        case .filledRegion where split: return "Region" // W2-ANNOT
        case .detailComponent where split: return "Component" // W2-ANNOT
        case .detailGroupPlace where split: return "Detail\nGroup" // W2-ANNOT
        case .placeModelGroup where split: return size == .large ? "Model\nGroup" : "Model Group" // F1
        case .keynoteElement where split: return "Keynote" // W2-ANNOT
        case .threeDView where split: return "3D\nView" // WP6a
        case .componentLibrary where size == .large: return "Component\nLibrary" // W2-LIB
        case .siteLibrary where size == .large: return "Site\nLibrary" // W2-LIB
        case .viewTemplatesManage where split: return size == .large ? "View\nTemplates" : "View Templates" // BL-VG
        case .userInterface where split: return "User\nInterface" // BL-VG
        case .foundationIsolated where split: return "Foundation" // BL-VG
        case .joinSolids where split: return "Join" // BL-VG
        case .cutGeometry where split: return "Cut" // BL-VG
        case .additionalSettings where split: return "Additional Settings" // BL-VG
        case .finishEditGroup: return "Finish"
        case .typeProperties: return size == .large ? "Type\nProperties" : "Type Properties"
        case .roomSeparator: return "Room Separator"
        case .areaBoundary: return "Area Boundary"
        case .placeDecal where split: return "Decal" // F67
        case .insertViewsFromFile where split: return size == .large ? "Insert\nfrom File" : "Insert from File" // F67
        case .loadAsGroup where size == .large: return "Load as\nGroup" // F67
        case .linkModel where size == .large: return "Link\nModel" // F67
        case .linkIFC where size == .large: return "Link\nIFC" // F67
        default: break
        }
        let title = CommandCatalog.info(id).title
        guard size == .large, title.count > 10, let space = title.firstIndex(of: " ") else { return title }
        // Break at the space nearest the middle so both lines stay short.
        let mid = title.index(title.startIndex, offsetBy: title.count / 2)
        let spaces = title.indices.filter { title[$0] == " " }
        let best = spaces.min { abs(title.distance(from: $0, to: mid)) < abs(title.distance(from: $1, to: mid)) } ?? space
        return title.replacingCharacters(in: best...best, with: "\n")
    }
}

/// A titled group of tools. `tint` colours the panel's icons (Golden Gate style coloured symbols).
struct RibbonPanel: Identifiable {
    var id: String { title }
    let title: String
    let items: [RibbonItem]
    var tint: Color = .accentColor
}

enum RibbonContent {
    static let build = Color(red: 0.20, green: 0.47, blue: 0.86)
    static let circulation = Color(red: 0.90, green: 0.52, blue: 0.14)
    static let rooms = Color(red: 0.20, green: 0.62, blue: 0.40)
    static let datum = Color(red: 0.55, green: 0.36, blue: 0.80)
    static let annotate = Color(red: 0.12, green: 0.60, blue: 0.66)
    static let modify = Color(red: 0.36, green: 0.40, blue: 0.47)
    static let view = Color(red: 0.42, green: 0.35, blue: 0.85)
    static let sheet = Color(red: 0.80, green: 0.36, blue: 0.40)
    static let site = Color(red: 0.42, green: 0.58, blue: 0.22)
    static let manage = Color(red: 0.45, green: 0.45, blue: 0.50)

    /// Every tab starts with Select, as in RevitCraft: Modify returns to selection mode from any tab.
    static let selectPanel = RibbonPanel(title: "Select", items: [.large(.modify)], tint: modify)

    /// N2: panel order and dropdowns follow RevitCraft (Select, Properties, Clipboard, Geometry, Modify, View, Measure,
    /// Create). The Modify grid reads as RevitCraft's three rows (Align Offset Mirror Mirror Split Pin / Move Copy Rotate
    /// Trim Array Unpin / Scale Trim Trim Delete); the ribbon packs icons in columns of three, so they are listed by column.
    static let modifyPanels: [RibbonPanel] = [
        RibbonPanel(title: "Clipboard", items: [.large(.paste, [.paste, .pasteAlignedSameLevel, .pasteAlignedSelectedLevels, .pasteAlignedCurrentView]),
                                                .icon(.cut), .icon(.copyClipboard), .icon(.matchType)], tint: modify),
        RibbonPanel(title: "Geometry", items: [.small(.joinSolids, [.joinSolids, .unjoinSolids, .switchJoinOrder]), .small(.cutGeometry, [.cutGeometry, .uncutGeometry]), // BL-VG
                                               .small(.demolish), .small(.joinGeometry, [.joinGeometry, .unjoinGeometry]).newColumn(), .small(.paint, [.paint, .removePaint])], tint: modify),
        RibbonPanel(title: "Modify", items: [.icon(.align), .icon(.move), .icon(.scale),
                                             .icon(.offset), .icon(.copy), .icon(.trimExtendSingle),
                                             .icon(.mirrorPickAxis), .icon(.rotate), .icon(.trimExtendMultiple),
                                             .icon(.mirrorDrawAxis), .icon(.trimExtendCorner), .icon(.delete),
                                             .icon(.split), .icon(.array), .icon(.pin).newColumn(), .icon(.unpin)], tint: modify),
        RibbonPanel(title: "View", items: [.icon(.hideInView), .icon(.temporaryIsolate), .icon(.temporaryHide),
                                           .icon(.overrideGraphicsElement), .icon(.selectionBox)], tint: view), // WP6a: override, selection box
        RibbonPanel(title: "Measure", items: [.large(.measureBetween, [.measureBetween, .measureAlong]), .large(.alignedDimension)], tint: modify),
        RibbonPanel(title: "Create", items: [.large(.createGroup), .small(.editGroup), .small(.ungroup), .small(.createSimilar)], tint: modify),
    ]

    static func panels(_ tab: RibbonTab) -> [RibbonPanel] {
        tab == .modify ? tabPanels(tab) : [selectPanel] + tabPanels(tab) // Modify has its own, fuller Select panel
    }

    /// The panels after Select. N2: panels, their order and the dropdowns follow RevitCraft's ribbon (crates/rc-app
    /// ribbon.rs). Tools Arcus has and RevitCraft lacks stay in the panel they belong to; RevitCraft tools Arcus does
    /// not have yet arrive with their feature milestones (Docs/RevitCraftPort.md). Draw shapes (rectangle, arc, pick
    /// lines, pick walls) are draw modes of the tools, not dropdown entries.
    /// F1: RevitCraft's Opening panel (Architecture and Structure): By Face, Shaft, Wall, Vertical, Dormer.
    static let openingItems: [RibbonItem] = [.small(.faceOpening), .large(.shaftOpening), .small(.wallOpening), .small(.verticalOpening), .small(.dormerOpening)]

    static func tabPanels(_ tab: RibbonTab) -> [RibbonPanel] {
        switch tab {
        case .modify:
            return [RibbonPanel(title: "Select", items: [.large(.modify), .small(.selectAll), .small(.filterSelection), .small(.selectAllInstancesInView)], tint: modify),
                    RibbonPanel(title: "Properties", items: [.large(.typeProperties), .large(.toggleProperties)], tint: modify)] + modifyPanels
        case .architecture:
            return [RibbonPanel(title: "Build", items: [.large(.wall, [.wall, .structuralWall, .wallSweep, .wallReveal, .curtainWall]), .large(.door), .large(.window),
                                                        .large(.component, [.component, .componentLibrary]), .large(.structuralColumn, [.structuralColumn, .column]),
                                                        .large(.roofFootprint, [.roofFootprint, .roofExtrusion, .roofSoffit]), .large(.ceiling),
                                                        .large(.floor, [.floor, .structuralFloor, .slabEdge]),
                                                        .small(.curtainGrid), .small(.mullion), .small(.curtainPanel)], tint: build),
                    RibbonPanel(title: "Circulation", items: [.large(.railing), .large(.ramp), .large(.stairStraight, [.stairStraight, .stairL, .stairU])], tint: circulation),
                    RibbonPanel(title: "Model", items: [.small(.modelText), .small(.modelLine), .small(.placeModelGroup, [.placeModelGroup, .createGroup])], tint: build), // F1
                    RibbonPanel(title: "Room & Area", items: [.large(.room, [.room, .placeRoomsAutomatically, .highlightBoundaries]), .small(.roomSeparator), .small(.roomTag, [.roomTag, .tagAll]),
                                                              .large(.area, [.area, .placeAreasAutomatically]), .small(.areaBoundary), .small(.areaTag), .small(.areaPlan),
                                                              .small(.colorSchemes).newColumn()], tint: rooms),
                    RibbonPanel(title: "Opening", items: openingItems, tint: build), // F1
                    RibbonPanel(title: "Datum", items: [.small(.level), .small(.grid)], tint: datum),
                    RibbonPanel(title: "Work Plane", items: [.small(.referencePlane)], tint: datum)]
        case .structure:
            return [RibbonPanel(title: "Structure", items: [.large(.beam), .large(.structuralWall, [.structuralWall, .wall]), .large(.structuralColumn),
                                                            .large(.structuralFloor, [.structuralFloor, .floor]), .large(.truss), .large(.brace), .large(.beamSystem)], tint: build), // BL-VG, F34
                    RibbonPanel(title: "Foundation", items: [.large(.foundationIsolated), .large(.foundationWall), .large(.foundationSlab)], tint: build), // BL-VG
                    RibbonPanel(title: "Reinforcement", items: [.large(.rebar), .small(.areaReinforcement), .small(.pathReinforcement), .small(.fabricArea),
                                                                .small(.fabricSheet).newColumn(), .small(.rebarCover), .small(.rebarCoupler, [.rebarCoupler, .couplerOnBarEnd, .couplerBetweenBars])], tint: build), // F34
                    RibbonPanel(title: "Model", items: [.large(.component, [.component, .componentLibrary]), .small(.modelText), .small(.modelLine),
                                                        .small(.placeModelGroup, [.placeModelGroup, .createGroup])], tint: build), // F1
                    RibbonPanel(title: "Opening", items: openingItems, tint: build), // F1
                    RibbonPanel(title: "Datum", items: [.small(.level), .small(.grid)], tint: datum),
                    RibbonPanel(title: "Work Plane", items: [.small(.referencePlane)], tint: datum)]
        case .insert:
            // F67: RevitCraft's Insert tab (ribbon.rs insert()): Link Model, Link IFC and Link CAD large, the other links stacked.
            return [RibbonPanel(title: "Manage", items: [.large(.manageLinks)], tint: build),
                    RibbonPanel(title: "Link", items: [.large(.linkModel), .large(.linkIFC), .large(.linkCAD), // BL-SCHED: one Link CAD with a format picker
                                                       .small(.linkTopography), .small(.dwfMarkup), .small(.placeDecal, [.placeDecal, .decalTypes]),
                                                       .small(.pointCloud), .small(.coordinationModel), .small(.linkPDF), .small(.linkImage)], tint: build),
                    RibbonPanel(title: "Import", items: [.large(.importCAD), .small(.importGbXML), .small(.importPDF), .small(.importImage),
                                                         .large(.importIFC), .large(.importRevit)], tint: build), // BL-SCHED
                    RibbonPanel(title: "Load from Library", items: [.large(.componentLibrary), .large(.loadFamily), .large(.loadAsGroup),
                                                                    .large(.insertViewsFromFile, [.insertViewsFromFile, .insert2DElementsFromFile]),
                                                                    .small(.reloadFamily), .small(.typeCatalog)], tint: build)] // W2-LIB
        case .annotate:
            // W2-ANNOT: organised like the reference tool's Annotate tab. MEP-only items (duct and pipe legends, space
            // tags) are left out: Arcus has no MEP systems.
            return [RibbonPanel(title: "Dimension", items: [.large(.alignedDimension), .small(.linearDimension), .small(.angularDimension), .small(.radialDimension),
                                                            .small(.diameterDimension), .small(.arcLengthDimension), .small(.spotElevation),
                                                            .small(.spotCoordinate), .small(.spotSlope)], tint: annotate),
                    RibbonPanel(title: "Detail", items: [.large(.detailLine), .large(.filledRegion, [.filledRegion, .maskingRegion]),
                                                         .large(.detailComponent, [.detailComponent, .repeatingDetailComponent, .legendComponent]),
                                                         .large(.revisionCloud), .large(.detailGroupPlace, [.detailGroupPlace, .detailGroupCreate]),
                                                         .large(.insulation)], tint: annotate),
                    RibbonPanel(title: "Text", items: [.large(.textNote), .small(.checkSpelling), .small(.findReplace)], tint: annotate),
                    RibbonPanel(title: "Tag", items: [.large(.tagByCategory), .large(.tagAll), .small(.beamAnnotations), .small(.multiCategoryTag), .small(.materialTag),
                                                      .small(.areaTag), .small(.roomTag), .small(.viewReference).newColumn(), .small(.treadNumber),
                                                      .large(.multiRebarAligned, [.multiRebarAligned, .multiRebarLinear]), // F34
                                                      .large(.keynoteElement, [.keynoteElement, .keynoteMaterial, .keynoteUser, .keynotingSettings])], tint: annotate), // F12: Keynoting Settings
                    RibbonPanel(title: "Color Fill", items: [.large(.colorFillLegend)], tint: annotate),
                    RibbonPanel(title: "Symbol", items: [.large(.symbol), .small(.spanDirection), .small(.beamSymbol), .small(.stairPath), // F34: RevitCraft's order
                                                         .small(.areaReinforcementSymbol).newColumn(), .small(.pathReinforcementSymbol), .small(.rebarSymbol),
                                                         .small(.fabricSymbol).newColumn(), .small(.northArrow), .small(.scaleBar)], tint: annotate)]
        case .analyze:
            // Spaces & Zones arrives with the Analyze milestone (F5).
            return [RibbonPanel(title: "Color Fill", items: [.large(.colorFillLegend)], tint: annotate),
                    RibbonPanel(title: "Reports & Schedules", items: [.large(.schedule, [.schedule, .materialTakeoff])], tint: view)]
        case .massing:
            // W2-DWG: Massing & Site panels.
            // BL-SITE: Toposolid is the primary site element; toposurfaces and building pads sit behind "Legacy".
            return [RibbonPanel(title: "Model Site", items: [.large(.toposolid, [.toposolid, .toposolidFromFile, .toposolidFromImport]),
                                                             .large(.siteComponent), .large(.parkingComponent), .large(.propertyLine), .large(.parkingLayout)], tint: site),
                    RibbonPanel(title: "Modify Site", items: [.small(.modifySubElements), .small(.subdivideToposolid), .small(.splitSurface), .small(.simplifySurface).newColumn(),
                                                              .small(.editSurface), .small(.excavateToposolid), .small(.gradedRegion).newColumn(), .small(.mergeSurfaces),
                                                              .small(.labelContours)], tint: site),
                    RibbonPanel(title: "Legacy", items: [.small(.toposurface, [.toposurface, .toposurfaceFromFile, .toposurfaceFromImport]), .small(.buildingPad),
                                                         .small(.subregion), .small(.generateToposolid).newColumn()], tint: site),
                    RibbonPanel(title: "Settings", items: [.small(.siteSettings)], tint: site)]
        case .view:
            return [RibbonPanel(title: "Graphics", items: [.large(.viewTemplatesManage, [.viewTemplatesManage, .viewTemplateCreate, .viewTemplateApplyProperties, .viewTemplateApply]), // BL-VG
                                                           .large(.visibilityGraphics), .small(.filtersDialog), .small(.thinLines), .small(.viewRange), .small(.revealHidden),
                                                           .small(.showProjectBasePoint), .small(.showSurveyPoint)], tint: view),
                    RibbonPanel(title: "Create", items: [.large(.threeDView, [.threeDView, .cameraView]), .large(.section), .large(.callout),
                                                         .large(.floorPlan, [.floorPlan, .ceilingPlan, .structuralPlan, .areaPlan]), .large(.elevation),
                                                         .small(.draftingView), .small(.duplicateView, [.duplicateView, .duplicateViewWithDetailing, .duplicateDependent]),
                                                         .small(.legend, [.legend, .keynoteLegend]), .large(.schedule, [.schedule, .materialTakeoff, .sheetList, .revisionSchedule]), .small(.scopeBox)], tint: view), // F12: Keynote Legend
                    RibbonPanel(title: "Sheet Composition", items: [.large(.newSheet), .small(.placeView), .small(.revisions), .small(.viewReference),
                                                                    .large(.activateViewport, [.activateViewport, .deactivateViewport])], tint: sheet),
                    RibbonPanel(title: "Windows", items: [.small(.closeHiddenViews), .small(.previousView),
                                                          .large(.userInterface, [.userInterface, .toggleProperties, .toggleNavigator, .toggleStatusBar, .toggleNavigationBar, .keyboardShortcuts])], tint: view)] // BL-VG
        case .manage:
            // Export and Print live in the File menu, as in RevitCraft.
            return [RibbonPanel(title: "Settings", items: [.large(.materials), .small(.objectStyles), .small(.snapSettings), .small(.projectInfo),
                                                           .small(.projectParameters), .small(.sharedParameters), .small(.globalParameters), .small(.purgeUnused), .small(.projectUnits), // F11: Global Parameters
                                                           .small(.structuralSettings), .small(.additionalSettings, [.additionalSettings, .lineStyles, .lineWeights, .linePatterns, .fillPatterns, .arrowheads, .temporaryDimensionSettings])], tint: manage), // BL-VG
                    // F11: Coordinates and Position, as RevitCraft's Project Location panel.
                    RibbonPanel(title: "Project Location", items: [.large(.locationSettings), .large(.specifyCoordinates, [.specifyCoordinates, .reportCoordinates]),
                                                                   .large(.relocateProject, [.relocateProject, .rotateTrueNorth, .mirrorProject, .rotateProjectNorth])], tint: manage),
                    RibbonPanel(title: "Design Options", items: [.large(.designOptions), .small(.addToSet), .small(.pickToEdit)], tint: manage), // F11: + the active option combo (Ribbon+F11.swift)
                    RibbonPanel(title: "Manage Project", items: [.large(.manageLinks), .large(.startingView), .small(.familyEditor)], tint: manage), // F11: Starting View
                    RibbonPanel(title: "Phasing", items: [.large(.phases)], tint: manage),
                    RibbonPanel(title: "Selection", items: [.small(.saveSelection), .small(.loadSelection), .small(.editSelection)], tint: manage), // F11
                    RibbonPanel(title: "Inquiry", items: [.small(.idsOfSelection), .small(.selectByID), .small(.warnings), .small(.modelHealth), .small(.diagnostics)], tint: manage)] // BL-VG
        }
    }

    /// Category-specific panel for a selection (the right-most panel of the contextual tab).
    static func selectionPanel(_ state: DocumentState) -> RibbonPanel? {
        let m = state.model
        let sel = state.session.selection.ids.compactMap { m[$0] }
        guard !sel.isEmpty else { return nil }
        var items: [RibbonItem] = []
        var title = "Modify"
        if sel.contains(where: { $0.wall != nil }) {
            title = "Modify Wall"
            // BL-SITE: wall tools moved to the Mode / Modify Wall / Wall Joins panels (RibbonContent.wallPanels).
        }
        if sel.contains(where: { $0.wall?.curtain != nil }) { items += [.small(.curtainGrid), .small(.mullion), .small(.curtainPanel)] } // WP3
        if sel.contains(where: { $0.insert != nil }) {
            title = sel.allSatisfy({ $0.insert != nil }) ? "Host" : title
            items += [.small(.flipFacing), .small(.flipHand), .large(.pickHost)]
        }
        if sel.count == 1, CommandRouter(state: state).editableSketch(sel[0]) { title = "Mode"; items.insert(.large(.editBoundary), at: 0) }
        if sel.contains(where: { $0.link != nil }) { title = "Link"; items += [.large(.reloadLink), .small(.unloadLink), .small(.convertLinkToDrafting)] }
        // WP1: dimensions
        if sel.count == 1, let d = sel[0].dimension, d.kind == .linear || d.kind == .aligned { title = "Witness Lines"; items += [.large(.editWitnessLines)] }
        if sel.contains(where: { $0.group != nil }) { title = "Group"; items += [.large(.editGroup), .small(.ungroup)] }
        if sel.contains(where: { ArrayOperations.arrayGroup(of: $0.id, m) != nil }) { title = "Array"; items += [.large(.arrayNumber)] }
        if state.session.editingGroupID != nil { items += [.large(.finishEditGroup)] }
        let wp4 = wp4SelectionItems(sel, m); if let t = wp4.title { title = t }; items += wp4.items
        let annot = annotSelectionItems(sel, m); if let t = annot.title { title = t }; items += annot.items // W2-ANNOT
        let site = siteSelectionItems(sel, m); if let t = site.title { title = t }; items += site.items // BL-SITE
        if sel.count == 1, Parameters.familyDefinition(for: sel[0], m) != nil { items += [.large(.familyEditor)] }
        return items.isEmpty ? nil : RibbonPanel(title: title, items: items, tint: build)
    }

    static func selectionTitle(_ state: DocumentState) -> String? {
        let sel = state.session.selection.ids.compactMap { state.model[$0] }
        guard !sel.isEmpty else { return nil }
        let cats = Set(sel.map(\.category))
        return cats.count == 1 ? cats.first!.displayName : "Multi-Select"
    }

    /// Draw-panel glyphs for tool draw modes.
    static func drawSymbol(_ mode: String) -> String {
        switch mode {
        case "Line": "line.diagonal"
        case "Rectangle": "rectangle"
        case "Arc": "point.topleft.down.to.point.bottomright.curvepath"
        case "Circle": "circle"
        case "Polygon": "hexagon"
        case "Pick Lines", "Pick Walls": "cursorarrow.rays"
        case "Inscribed Polygon": "hexagon" // WP3 wall draw modes
        case "Circumscribed Polygon": "hexagon.fill"
        case "Tangent Arc": "arrow.turn.up.right"
        case "Fillet Arc": "point.topleft.down.curvedto.point.bottomright.up"
        case "Start-End-Radius Arc": "point.topleft.down.to.point.bottomright.curvepath" // BL-CANVAS
        case "Center-ends Arc": "circle.bottomhalf.filled" // BL-CANVAS
        case "Tangent End Arc": "arrow.turn.up.right" // BL-CANVAS
        case "Spline": "point.bottomleft.forward.to.point.topright.scurvepath" // F1
        case "Ellipse": "oval" // F1
        case "Partial Ellipse": "oval.bottomhalf.filled" // F1
        default: "pencil.line"
        }
    }
}

// MARK: - Ribbon view

extension RibbonContent {
    /// "Modify | Place Wall", "Modify | Sketch Floor", "Modify | Walls" — or nil in plain Modify mode.
    @MainActor static func contextualTitle(_ state: DocumentState) -> String? {
        if let t = keysContextualTitle(state) { return t } // BL-KEYS: Modify tools keep "Modify | <Category>"; pre-selection
        if let t = state.activeTool as? SketchTool { return t.ribbonTitle(state.model) } // BL-CANVAS: "Modify | Create Floor Boundary"
        if let t = state.activeTool { return "\(t.isSketchMode ? "Modify | Sketch" : "Modify | Place") \(t.title)" }
        if let s = scheduleContextualTitle(state) { return s } // BL-SCHED
        return selectionTitle(state).map { "Modify | \($0)" }
    }
}

/// The ribbon's tabs, shown in the floating tab pill over the canvas (W4-WIRE): the task tabs, the contextual
/// "Modify | …" tab while a tool runs or elements are selected, and the minimize control. Double-clicking a tab
/// minimizes the panels (and back).
struct RibbonTabsBar: View {
    @Bindable var state: DocumentState
    var body: some View {
        let _ = state.toolRevision
        let _ = state.session.selection.ids
        let contextualTitle = RibbonContent.contextualTitle(state)
        let contextualShown = state.ribbonShowsContextual && contextualTitle != nil
        let compact = Self.fullWidth(contextual: contextualTitle) > state.ribbonTabsWidth
        HStack(spacing: 1) {
            if compact {
                // Too narrow for every tab: the task tabs collapse into one menu, the contextual tab stays a tab.
                Menu {
                    ForEach(RibbonTab.allCases) { t in
                        Button { pick(t) } label: {
                            if state.ribbonTab == t { Label(t.rawValue, systemImage: "checkmark") } else { Text(t.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.ribbonTab.rawValue).font(.system(size: 12, weight: contextualShown ? .medium : .semibold)).lineLimit(1).fixedSize() // W4-WIRE: the contextual tab truncates first
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(contextualShown ? Color.secondary : Color.primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(contextualShown ? 0 : 0.10)))
                    .contentShape(Capsule())
                } primaryAction: { pick(state.ribbonTab) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .accessibilityLabel("Ribbon tab: \(state.ribbonTab.rawValue)")
            } else {
                ForEach(RibbonTab.allCases) { t in
                    RibbonTabButton(title: t.rawValue, selected: state.ribbonTab == t && !contextualShown) { pick(t) }
                        doubleTap: { state.ribbonCollapsed.toggle() }
                }
            }
            if let contextualTitle {
                RibbonTabButton(title: contextualTitle, selected: contextualShown, contextual: true) {
                    state.ribbonShowsContextual = true
                    if state.ribbonCollapsed { state.ribbonCollapsed = false }
                } doubleTap: { state.ribbonCollapsed.toggle() }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Button { state.ribbonCollapsed.toggle() } label: {
                Image(systemName: state.ribbonCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(RibbonPressStyle())
            .modifier(HoverBackground(radius: 11))
            .foregroundStyle(.secondary)
            .help(state.ribbonCollapsed ? "Show the ribbon panels" : "Minimize the ribbon to tabs")
            .accessibilityLabel(state.ribbonCollapsed ? "Show ribbon panels" : "Minimize ribbon")
        }
        .padding(.horizontal, 3)
        .arcusAnimation(contextualTitle)
        .fixedSize(horizontal: !compact, vertical: true) // W4-WIRE: compact tabs truncate the contextual title in a narrow pill
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ribbon tabs")
    }

    func pick(_ t: RibbonTab) {
        state.ribbonTab = t; state.ribbonShowsContextual = false
        if state.ribbonCollapsed { state.ribbonCollapsed = false }
    }

    /// Width of the full tab row: each tab's title plus its padding, the contextual tab and the minimize control.
    static func fullWidth(contextual: String?) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width + 21 }
        return RibbonTab.allCases.reduce(0) { $0 + w($1.rawValue) } + (contextual.map(w) ?? 0) + 30
    }
}

/// The ribbon's panels for the chosen tab (or the contextual tab), as rounded groups on the floating ribbon strip.
struct RibbonView: View {
    @Bindable var state: DocumentState
    /// When a tool ends or the selection clears, either return to the previous tab (default) or stay on Modify.
    @AppStorage("ribbon.stayOnModify") private var stayOnModify = false

    var body: some View {
        let _ = state.toolRevision
        let _ = state.session.selection.ids
        let tool = state.activeTool
        let contextualShown = state.ribbonShowsContextual && RibbonContent.contextualTitle(state) != nil
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                if contextualShown {
                    scheduleOrContextualPanels(tool: tool) // BL-SCHED
                } else {
                    ForEach(RibbonContent.panels(state.ribbonTab)) { p in panelView(p) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .frame(height: Tokens.ribbonPanelHeight)
        .onChange(of: state.toolRevision) { _, _ in if state.activeTool != nil { state.ribbonShowsContextual = true } else { contextEnded() } }
        .onChange(of: state.session.selection.ids) { _, ids in if !ids.isEmpty { state.ribbonShowsContextual = true } else { contextEnded() } }
        .onChange(of: state.activeViewID) { _, _ in if RibbonContent.scheduleContextualTitle(state) != nil { state.ribbonShowsContextual = true } } // BL-SCHED
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ribbon")
    }

    private func contextEnded() {
        if stayOnModify && state.activeTool == nil && state.session.selection.isEmpty { state.ribbonTab = .modify }
    }

    @ViewBuilder func panelView(_ p: RibbonPanel, contextual: Bool = false) -> some View {
        if !contextual, p.title == "Design Options" { DesignOptionsRibbonPanel(panel: p, state: state) } // F11: with the active option combo
        else { RibbonPanelView(panel: p, state: state, contextual: contextual) }
    }

    @ViewBuilder func contextualPanels(tool: (any InteractiveTool)?) -> some View {
        panelView(RibbonPanel(title: "Select", items: [.large(.modify)], tint: RibbonContent.modify), contextual: true)
        panelView(RibbonPanel(title: "Properties", items: [.large(.typeProperties), .large(.toggleProperties)], tint: RibbonContent.modify), contextual: true)
        if let tool {
            if let mode = tool.options.first(where: { $0.id == "mode" }), case .choice(let modes) = mode.kind {
                DrawPanel(state: state, tool: tool, modes: modes, current: mode.value.textValue ?? "")
            }
            if tool.isSketchMode {
                ModePanel(state: state)
            }
            // The Level tool's plan-view options get their own panel (with Plan View Types); other tools' ribbon options
            // use the generic panel.
            if let level = tool as? LevelTool { LevelPlanViewsPanel(state: state, tool: level) } // BL-BROWSER
            else { RibbonToolOptionsPanel(state: state, tool: tool) } // BL-KEYS: 2026 arrangement of tool options
            if [.door, .window, .component].contains(tool.commandID) {
                panelView(RibbonPanel(title: "Mode", items: [.large(.loadFamily)] + (tool.commandID == .component ? [.large(.componentLibrary)] : []), tint: RibbonContent.build), contextual: true) // W2-LIB
            }
            if [.room, .area].contains(tool.commandID) {
                panelView(RibbonPanel(title: tool.commandID == .area ? "Area" : "Room",
                                      items: [.large(tool.commandID == .area ? .placeAreasAutomatically : .placeRoomsAutomatically)]
                                          + (tool.commandID == .room ? [.large(.highlightBoundaries)] : []) + [.small(.colorSchemes)], // F1: as RevitCraft's Room panel
                                      tint: RibbonContent.rooms), contextual: true)
            }
        } else {
            if state.keys.pendingCommand != nil { PreselectionPanel(state: state) } // BL-KEYS: Finish/Cancel while selecting
            let wallPanels = RibbonContent.wallPanels(state) // BL-SITE
            ForEach(wallPanels.isEmpty ? RibbonContent.modifyPanels : RibbonContent.compactModifyPanels) { p in panelView(p, contextual: true) } // BL-SITE
            ForEach(wallPanels) { p in panelView(p, contextual: true) } // BL-SITE
            if let p = RibbonContent.selectionPanel(state) { panelView(p, contextual: true) }
        }
    }
}

/// Press feedback for ribbon and toolbar controls: a slight dim and shrink while held.
struct RibbonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !AccessibilityPrefs.reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Hover highlight (and the "on" state) behind a ribbon control, as on native toolbar buttons.
struct HoverBackground: ViewModifier {
    var active = false
    var tint: Color = .accentColor
    var radius: CGFloat = 7
    @State private var hovering = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if active {
                    shape.fill(tint.opacity(0.18)).overlay(shape.strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
                } else if hovering {
                    shape.fill(Color.primary.opacity(0.075))
                }
            }
            .onHover { h in
                if AccessibilityPrefs.reduceMotion { hovering = h } else { withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
            }
    }
}

/// Ribbon geometry: every panel has the same content height; a large button fills it and three stacked rows fill it
/// exactly, so icons and labels line up across panels and nothing is clipped.
enum RibbonMetrics {
    static let rowHeight: CGFloat = 18
    static let rowSpacing: CGFloat = 2
    static let contentHeight: CGFloat = rowHeight * 3 + rowSpacing * 2
    static let largeIcon: CGFloat = 20
    static let smallIcon: CGFloat = 12.5
    static let titleHeight: CGFloat = 12
    static let columnSpacing: CGFloat = 4
}

/// A panel's rounded container with its title underneath.
struct PanelCard<Content: View>: View { // BL-KEYS: internal for Ribbon+Keys.swift
    let title: String
    var contextual = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 2) {
            content.frame(height: RibbonMetrics.contentHeight, alignment: .top)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(contextual ? Tokens.contextualTint.opacity(0.9) : Color.secondary)
                .lineLimit(1)
                .frame(height: RibbonMetrics.titleHeight)
        }
        .padding(.horizontal, 6).padding(.top, 5).padding(.bottom, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045))) // W4-SHELL: tint only, no border
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) panel")
    }
}

private struct RibbonTabButton: View {
    let title: String
    let selected: Bool
    var contextual = false
    let action: () -> Void
    var doubleTap: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .lineLimit(1).truncationMode(.tail).frame(minWidth: contextual ? 56 : 0) // W4-WIRE: a squeezed contextual tab still reads "Modi…"
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(contextual ? Tokens.contextualTint : (selected ? Color.primary : Color.secondary))
            .background {
                if selected {
                    Capsule().fill(contextual ? Tokens.contextualTint.opacity(0.18) : Color.primary.opacity(0.10))
                } else if hovering {
                    Capsule().fill(Color.primary.opacity(0.06))
                } else if contextual {
                    Capsule().strokeBorder(Tokens.contextualTint.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture(count: 2, perform: doubleTap)
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(title + " tab")
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { action() }
    }
}

/// A panel: large buttons side by side, small buttons stacked in columns of three, title underneath.
private struct RibbonPanelView: View {
    let panel: RibbonPanel
    let state: DocumentState
    var contextual = false
    var body: some View {
        PanelCard(title: panel.title, contextual: contextual) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                ForEach(columns.indices, id: \.self) { i in
                    let col = columns[i]
                    if col.count == 1, col[0].size == .large {
                        RibbonButton(item: col[0], state: state, tint: panel.tint)
                    } else if col.first?.size == .icon {
                        // Icon-only tools: a tidy grid, three rows high.
                        VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                            ForEach(col, id: \.self) { RibbonButton(item: $0, state: state, tint: panel.tint) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                            ForEach(col, id: \.self) { RibbonButton(item: $0, state: state, tint: panel.tint) }
                        }
                        .frame(height: RibbonMetrics.contentHeight, alignment: col.count < 3 ? .center : .top)
                    }
                }
            }
        }
    }

    /// Large items get their own column; consecutive small (or icon) items are packed three per column, so a dense
    /// icon panel such as Modify reads as a three-row grid. `breakBefore` starts a new column early.
    var columns: [[RibbonItem]] {
        var out: [[RibbonItem]] = []
        var smalls: [RibbonItem] = []
        func flush() { while !smalls.isEmpty { out.append(Array(smalls.prefix(3))); smalls.removeFirst(min(3, smalls.count)) } }
        for item in panel.items {
            if item.size == .large { flush(); out.append([item]) }
            else {
                if let last = smalls.last, last.size != item.size || item.breakBefore { flush() }
                smalls.append(item)
            }
        }
        flush()
        return out
    }
}

struct RibbonButton: View {
    let item: RibbonItem
    let state: DocumentState
    var tint: Color = .accentColor
    var body: some View {
        let info = CommandCatalog.info(item.id)
        let router = CommandRouter(state: state)
        let reason = router.disabledReason(item.id)
        let active = state.activeTool?.commandID == item.id || (item.variants.contains { state.activeTool?.commandID == $0 })
        let enabled = reason == nil
        Group {
            if item.variants.isEmpty {
                Button { router.run(item.id) } label: { label(info, enabled: enabled, menu: false) }
                    .buttonStyle(RibbonPressStyle())
            } else {
                Menu {
                    ForEach(item.variants, id: \.self) { v in
                        Button(CommandCatalog.info(v).title, systemImage: CommandCatalog.info(v).symbol) { router.run(v) }.disabled(router.disabledReason(v) != nil)
                    }
                } label: { label(info, enabled: enabled, menu: true) } primaryAction: { router.run(item.id) }
                    .menuStyle(.button).buttonStyle(RibbonPressStyle()).menuIndicator(.hidden)
            }
        }
        .modifier(HoverBackground(active: active, tint: tint, radius: item.size == .large ? 8 : 6))
        .help(tooltip(info, reason))
        .accessibilityLabel(info.title)
        .accessibilityHint(reason ?? info.help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder func label(_ info: CommandInfo, enabled: Bool, menu: Bool) -> some View {
        let fg: AnyShapeStyle = enabled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary)
        switch item.size {
        case .large:
            VStack(spacing: 2) {
                Image(systemName: info.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: RibbonMetrics.largeIcon, weight: .regular))
                    .foregroundStyle(fg)
                    .frame(width: 30, height: 26)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(RibbonItem.caption(item.id, size: .large, split: menu)).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                        .fixedSize()
                    if menu { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary) }
                }
                .foregroundStyle(Color.primary)
                .frame(height: 26, alignment: .top)
            }
            .frame(minWidth: 48, maxHeight: RibbonMetrics.contentHeight, alignment: .top)
            .padding(.horizontal, 5).padding(.top, 2)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        case .small:
            HStack(spacing: 6) {
                Image(systemName: info.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: RibbonMetrics.smallIcon))
                    .foregroundStyle(fg)
                    .frame(width: 16, height: 16)
                Text(RibbonItem.caption(item.id, size: .small, split: menu)).font(.system(size: 11)).lineLimit(1).fixedSize()
                    .foregroundStyle(Color.primary)
                if menu { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary) }
            }
            .frame(height: RibbonMetrics.rowHeight)
            .padding(.horizontal, 5)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        case .icon:
            Image(systemName: info.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: RibbonMetrics.smallIcon + 0.5))
                .foregroundStyle(fg)
                .frame(width: 26, height: RibbonMetrics.rowHeight)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
    }

    func tooltip(_ info: CommandInfo, _ reason: String?) -> String {
        var s = info.title
        if let sc = info.shortcut { s += "  \(sc)" }
        let aliases = KeyboardAliases.shared.aliases(for: item.id)
        if !aliases.isEmpty { s += "  (\(aliases.joined(separator: ", ")))" }
        s += "\n\(info.help)"
        if let reason { s += "\nUnavailable: \(reason)" }
        return s
    }
}

/// Draw panel: the active tool's drawing methods as toggle buttons.
private struct DrawPanel: View {
    let state: DocumentState
    let tool: any InteractiveTool
    let modes: [String]
    let current: String
    var body: some View {
        PanelCard(title: "Draw", contextual: true) {
            HStack(spacing: 2) {
                ForEach(modes, id: \.self) { m in
                    Button { tool.setOption("mode", .text(m)); state.toolChangedState() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: RibbonContent.drawSymbol(m)).font(.system(size: 17)).frame(width: 30, height: 26)
                                .foregroundStyle(RibbonContent.build)
                            // Two-word modes wrap at the space ("Circumscribed / Polygon"), never inside a word.
                            Text(m.count > 10 ? m.replacingOccurrences(of: " ", with: "\n", range: m.range(of: " ")) : m)
                                .font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).fixedSize().frame(height: 26, alignment: .top)
                        }
                        .frame(minWidth: 44, maxHeight: RibbonMetrics.contentHeight, alignment: .top)
                        .padding(.horizontal, 4).padding(.top, 2)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(RibbonPressStyle())
                    .modifier(HoverBackground(active: m == current, tint: RibbonContent.build, radius: 8))
                    .accessibilityLabel("Draw \(m)")
                    .accessibilityAddTraits(m == current ? .isSelected : [])
                }
            }
        }
    }
}

/// Mode panel in sketch mode: Finish (green check) and Cancel (red cross).
private struct ModePanel: View {
    let state: DocumentState
    var body: some View {
        PanelCard(title: "Mode", contextual: true) {
            HStack(spacing: 4) {
                modeButton("Finish Edit Mode", "checkmark", .green, .finishSketch)
                    .keyboardShortcut(.return, modifiers: [.command])
                modeButton("Cancel Edit Mode", "xmark", .red, .cancelSketch)
            }
        }
    }
    func modeButton(_ title: String, _ symbol: String, _ color: Color, _ id: CommandID) -> some View {
        Button { CommandRouter(state: state).run(id) } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(color).frame(width: 30, height: 26)
                Text(title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 64).frame(height: 26, alignment: .top)
            }
            .frame(maxHeight: RibbonMetrics.contentHeight, alignment: .top)
            .padding(.horizontal, 4).padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .modifier(HoverBackground(radius: 8))
        .accessibilityLabel(title)
    }
}

// MARK: - Options Bar

/// The Options Bar: the active tool's placement options (everything except the draw method, which lives in the
/// ribbon's Draw panel), as a floating glass bar over the top of the canvas. It takes no room when no tool runs.
struct OptionsBarView: View {
    @Bindable var state: DocumentState
    var body: some View {
        let _ = state.toolRevision
        if let tool = state.activeTool {
            let options = tool.options.filter { $0.id != "mode" && !ToolOptionPlacement.isOnRibbon($0, of: tool.commandID) } // BL-KEYS
            let row = HStack(spacing: 12) {
                Label(tool.isSketchMode ? "Sketch \(tool.title)" : tool.title, systemImage: tool.isSketchMode ? "pencil.and.outline" : "plus.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Tokens.contextualTint)
                if !options.isEmpty { Divider().frame(height: 16) }
                ForEach(options) { opt in OptionControl(state: state, tool: tool, option: opt) }
                WorkPlaneOption3D(state: state) // W2-3D
            }.fixedSize()
            ViewThatFits(in: .horizontal) { // W4-WIRE: the pill hugs its options; W4-AUDIT: narrow windows scroll them instead of overflowing
                row
                ScrollView(.horizontal, showsIndicators: false) { row }
            }
            .padding(.horizontal, 14)
            .frame(height: CGFloat(ShellMetrics.arcus.optionsHeight)) // W4-WIRE: the Options pill in the shell's third row
            .modifier(GlassPill(role: .options))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Options Bar")
        }
    }
}

struct OptionControl: View {
    let state: DocumentState
    let tool: any InteractiveTool
    let option: ToolOption
    @State private var text = ""
    var body: some View {
        HStack(spacing: 5) {
            Text(option.label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize() // W4-AUDIT: never wrap
            switch option.kind {
            case .bool:
                Toggle("", isOn: Binding(get: { option.value.boolValue ?? false }, set: { tool.setOption(option.id, .bool($0)); state.toolChangedState() }))
                    .toggleStyle(.checkbox).labelsHidden()
            case .choice(let options) where option.lineStyles != nil: // W2-ANNOT: line styles with pattern previews
                LineStyleMenu(styles: options.compactMap { n in option.lineStyles?[n].map { (n, $0) } }, current: option.value.textValue ?? "",
                              placeholder: "Line Style") { tool.setOption(option.id, .text($0)); state.toolChangedState() }
            case .choice(let options):
                Picker("", selection: Binding(get: { option.value.textValue ?? "" }, set: { tool.setOption(option.id, .text($0)); state.toolChangedState() })) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().controlSize(.small).fixedSize()
            case .length, .angle, .integer, .level:
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder).controlSize(.small).frame(width: 86)
                    .font(.system(size: 11).monospacedDigit())
                    .onAppear { text = display }
                    .onChange(of: option.value) { _, _ in text = display }
                    .onSubmit { apply() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.label)
    }
    var display: String {
        switch option.kind {
        case .angle: return String(format: "%.1f°", (option.value.doubleValue ?? 0) * 180 / .pi)
        case .integer: return "\(option.value.intValue ?? 0)"
        default: return Parameters.format(option.value, type: .length, model: state.model)
        }
    }
    func apply() {
        switch option.kind {
        case .angle:
            if let d = Double(text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)) { tool.setOption(option.id, .double(d * .pi / 180)) }
        case .integer:
            if let n = Int(text) { tool.setOption(option.id, .int(n)) }
        default:
            if let v = try? Parameters.parse(text, type: .length, model: state.model) { tool.setOption(option.id, v) }
            else { state.show("“\(text)” is not a valid length.", error: true) }
        }
        state.toolChangedState()
        text = display
    }
}
