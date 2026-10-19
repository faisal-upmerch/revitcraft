import AppKit
import ArcusApplication

/// Builds the application menu bar from the command catalog. Items route through the responder chain
/// (`performArcusCommand:`) to the active document window, or to the app delegate for app-level commands.
@MainActor
enum MainMenuBuilder {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        let file = submenu("File", fileItems())
        file.submenu?.delegate = RecentDocumentsMenu.shared
        main.addItem(file)
        main.addItem(submenu("Edit", editItems()))
        main.addItem(submenu("View", viewItems()))
        CameraMenus.addNavigationItems(to: main.items.last?.submenu) // W2-CAM
        // The menu bar follows the ribbon tabs: Architecture, Structure, Furniture, Insert, Annotate, (View above), Manage.
        let byFace = submenu("Model by Face", commands([.curtainSystemByFace, .roofByFace, .wallByFace, .floorByFace])) // F5
        let architecture = submenu("Architecture", commands([.wall, .stackedWall, .wallRectangle, .wallArc, .wallPickLines, .curtainWall, .wallSweep, .wallReveal, nil, .door, .window, .component, .modelInPlace, .column, nil, // F1: Wall: Reveal; F2: Stacked; F5: In-place
                                                      .floor, .floorPickWalls, .ceiling, .roofFootprint, .roofPickWalls, .roofExtrusion, nil,
                                                      .stairStraight, .stairL, .stairU, .connectLevels, .ramp, .railing, nil, .room, .roomSeparator, .area, .areaBoundary, .placeRoomsAutomatically, .highlightBoundaries, .placeAreasAutomatically, .colorSchemes, .space, .spaceSeparator, nil, // F5: spaces
                                                      .modelText, .modelLine, .placeModelGroup, nil, .faceOpening, .shaftOpening, .wallOpening, .verticalOpening, .dormerOpening, nil, // F1
                                                      .level, .grid, .gridMultiSegment, .referencePlane, .workPlaneSet, .workPlaneShow, .workPlaneViewer, nil, // F2
                                                      .showMass, .inPlaceMass, nil, .toposurface, .buildingPad, .propertyLine]) + [byFace]) // F5
        main.addItem(architecture)
        main.addItem(submenu("Structure", commands([.structuralColumn, .verticalColumn, .slantedColumn, .columnsAtGrids, .columnsAtColumns, .beam, // F2 .structuralWall, .structuralFloor, .truss, .brace, .beamSystem, nil,
                                                    .foundationIsolated, .foundationWall, .foundationSlab, nil, // F34
                                                    .rebar, .areaReinforcement, .pathReinforcement, .fabricArea, .fabricSheet, .rebarCover, .couplerOnBarEnd, .couplerBetweenBars])))
        main.addItem(furnitureMenu()) // FM4: Furniture mode
        main.addItem(submenu("Insert", commands([.linkModel, .linkIFC, .linkCAD, .linkTopography, .dwfMarkup, .placeDecal, .decalTypes, .pointCloud, .coordinationModel, .linkPDF, .linkImage, nil, // F67
                                                 .manageLinks, .reloadLink, .unloadLink, .convertLinkToDrafting, nil,
                                                 .importCAD, .importGbXML, .importPDF, .importImage, .importIFC, .importRevit, nil,
                                                 .loadFamily, .loadFurniture, .loadAsGroup, .insertViewsFromFile, .insert2DElementsFromFile, .reloadFamily, .typeCatalog, .componentLibrary, .siteLibrary])))
        main.addItem(submenu("Annotate", commands([.alignedDimension, .linearDimension, .angularDimension, .radialDimension, .diameterDimension, .arcLengthDimension, nil,
                                                   .spotElevation, .spotCoordinate, .spotSlope, nil, .detailLine, .filledRegion, .maskingRegion, .detailComponent, .insulation, nil,
                                                   .textNote, .tagByCategory, .tagAll, .roomTag, .spaceTag, .colorFillLegend, // F5 .symbol, .northArrow, nil, .revisionCloud, nil,
                                                   .beamSymbol, .areaReinforcementSymbol, .pathReinforcementSymbol, .rebarSymbol, .fabricSymbol, .multiRebarAligned, .multiRebarLinear, nil, .keynotingSettings]))) // F34, F12
        main.items.last?.submenu.map { m in for i in annotMenuAdditions() { m.addItem(i) } } // W2-ANNOT
        main.addItem(submenu("Manage", commands([.projectInfo, .projectUnits, .projectParameters, .materials, .objectStyles, .lineStyles, .additionalSettings, .structuralSettings, .snapSettings, .locationSettings, nil, // BL-VG; F34
                                                 .globalParameters, .transferProjectStandards, nil, // F11, F67
                                                 .specifyCoordinates, .reportCoordinates, .relocateProject, .rotateTrueNorth, .rotateProjectNorth, .mirrorProject, nil, // F11
                                                 .phases, .designOptions, .addToSet, .pickToEdit, nil, .startingView, .decalTypes, .familyEditor, .newFamily, .loadStandardTypes, nil,
                                                 .feFamilyTypes, .feFamilyCategory, .feLoadIntoProject, .feLoadAndClose, .feDefault3D, .feFlexTest, .feSaveFamilyAs, nil, // F1415: Family Editor
                                                 .furnitureFamilyTypes, .furnitureCategory, .furnitureFlex, .furnitureLoadIntoProject, .furnitureLoadAndClose, nil, // FM3: Furniture documents
                                                 .saveSelection, .loadSelection, .editSelection, nil,
                                                 .warnings, .selectByID, .idsOfSelection, .modelHealth, .purgeUnused, .diagnostics, nil, .keyboardShortcuts]))) // BL-VG: warnings, select by ID
        let window = submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
        ] + commands([.toggleNavigator, .toggleProperties, .workspaceBIMFamiliar, .workspaceMacSpacious, .resetWorkspace, .canvasTheme, nil, .previousView, .closeHiddenViews, .switchWindows, .tabViews, .tileViews]) + viewTabMenuItems() + [ // BL-BROWSER; F810
            .separator(),
            NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""),
        ])
        NSApp.windowsMenu = window.submenu
        main.addItem(window)
        let help = submenu("Help", commands([.onboarding, .keyboardShortcuts, .commandSearch]))
        NSApp.helpMenu = help.submenu
        main.addItem(help)
        return main
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        for i in items { m.addItem(i) }
        item.submenu = m
        return item
    }

    static func command(_ id: CommandID) -> NSMenuItem {
        let info = CommandCatalog.info(id)
        let i = NSMenuItem(title: info.title, action: #selector(AppDelegate.performArcusCommand(_:)), keyEquivalent: "")
        i.representedObject = id.rawValue
        i.image = NSImage(systemSymbolName: info.symbol, accessibilityDescription: nil)
        i.toolTip = info.help
        if let (key, mods) = keyEquivalent(info.shortcut) { i.keyEquivalent = key; i.keyEquivalentModifierMask = mods }
        return i
    }

    static func commands(_ ids: [CommandID?]) -> [NSMenuItem] { ids.map { $0.map(command) ?? .separator() } }

    /// Parses "⌘S", "⇧⌘S", "⌥⌘P", "⌘0", "F2" style shortcuts.
    static func keyEquivalent(_ s: String?) -> (String, NSEvent.ModifierFlags)? {
        guard let s, !s.isEmpty, s != "⎋⎋", s != "↩", s != "⌫" else { return nil }
        if s == "F2" { return (String(UnicodeScalar(NSF2FunctionKey)!), []) }
        var mods: NSEvent.ModifierFlags = []
        var key = ""
        for ch in s {
            switch ch {
            case "⌘": mods.insert(.command)
            case "⇧": mods.insert(.shift)
            case "⌥": mods.insert(.option)
            case "⌃": mods.insert(.control)
            case "−": key = "-"
            default: key.append(ch)
            }
        }
        guard !key.isEmpty else { return nil }
        return (key.lowercased(), mods)
    }

    static func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let m = NSMenu(title: "Arcus")
        m.addItem(command(.about))
        m.addItem(.separator())
        m.addItem(command(.preferences))
        m.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        m.addItem(services)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Hide Arcus", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        m.addItem(others)
        m.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit Arcus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = m
        return item
    }

    static func fileItems() -> [NSMenuItem] {
        let open = NSMenuItem(title: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recent.submenu = RecentDocumentsMenu.makeMenu()
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let save = NSMenuItem(title: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let dup = NSMenuItem(title: "Duplicate", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "s")
        dup.keyEquivalentModifierMask = [.command, .shift]
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift, .option]
        let revert = NSMenuItem(title: "Revert To Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        // F13: File ▸ Export grouped as RevitCraft does (CAD Formats, DWF/DWFx, PDF, IFC, Family Types, gbXML, Images, Reports).
        let cad = submenu("CAD Formats", commands([.exportDWG, .exportDXF, .exportOBJ, .exportSTL])) // DWG: DWG first, as Revit lists it
        let frames = command(.walkthroughExport); frames.title = "Walkthrough…" // F810: the command's own title is just "Export"
        let images = submenu("Images and Animations", commands([.exportImage]) + [frames])
        let reports = submenu("Reports", commands([.exportScheduleCSV, .exportRoomAreaReport]))
        let export = submenu("Export", [cad] + commands([.exportDWFx, .exportPDF, .exportIFC, .exportFamilyTypes, .exportGbXML]) + [images, reports])
        let importMenu = submenu("Import", commands([.importCAD, .importIFC, .importRevit, .importScheduleCSV])) // BL-SCHED
        let pageSetup = command(.printSetup) // F13: Print Setup (paper, zoom, hidden items) replaces the generic Page Setup
        pageSetup.keyEquivalent = "p"; pageSetup.keyEquivalentModifierMask = [.command, .shift]
        return [command(.home), newMenu(), open, recent, .separator(), close, save, dup, saveAs, command(.saveAsTemplate), command(.saveAsFurnitureTemplate), revert, command(.exportRecoveryCopy), .separator(), // BL-SCHED: New ▸
                importMenu, export, .separator(), pageSetup, command(.printPreview), command(.print)]
    }

    static func editItems() -> [NSMenuItem] {
        let undo = NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteAligned = submenu("Paste Aligned", commands([.pasteAlignedSameLevel, .pasteAlignedSelectedLevels, .pasteAlignedCurrentView]))
        // No key equivalent: the canvas handles ⌫ itself so text fields keep normal deletion.
        let delete = NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        let selectAll = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return [undo, redo, .separator(), cut, copy, paste, pasteAligned, delete, selectAll, .separator()]
            + commands([.selectAllInstancesInView, .selectAllInstancesInProject, .selectByCategory, .filterSelection, .selectJoinedElements, nil, // F11
                        .move, .copy, .rotate, .mirrorPickAxis, .mirrorDrawAxis, .array, .align, .offset, nil,
                        .trimExtendCorner, .trimExtendSingle, .trimExtendMultiple, .split, .matchType, nil,
                        .pin, .unpin, .createGroup, .ungroup, .editGroup, .finishEditGroup, nil, .commandSearch])
    }

    static func viewItems() -> [NSMenuItem] {
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        let temp = submenu("Temporary Hide/Isolate", commands([.temporaryHide, .temporaryHideCategory, .temporaryIsolate, .temporaryIsolateCategory, .resetTemporary]))
        let styles = submenu("Visual Style", commands([.visualStyleWireframe, .visualStyleHidden, .visualStyleShaded, .visualStyleConsistent, .visualStyleTransparent]))
        let detail = submenu("Detail Level", commands([.detailCoarse, .detailMedium, .detailFine]))
        // Sent to the app delegate, which forwards to the key document window: SwiftUI hosting views in the sidebar
        // answer `toggleSidebar:` themselves (for their own split views) and would swallow it when a field there has focus.
        let sidebar = NSMenuItem(title: "Show/Hide Sidebar", action: #selector(AppDelegate.toggleDocumentSidebar(_:)), keyEquivalent: "s") // W4-SHELL
        sidebar.keyEquivalentModifierMask = [.command, .option]
        sidebar.target = AppDelegate.shared
        let graphics = submenu("Graphics", commands([.showHiddenLines, .removeHiddenLines, .cutProfile])) // F810
        let presentation = submenu("Presentation", commands([.render, .renderGallery])) // F810
        let create = submenu("Create", commands([.floorPlan, .ceilingPlan, .structuralPlan, .areaPlan, nil, .section, .elevation, .framingElevation, .callout, .calloutSketch, .draftingView, .legend, .keynoteLegend, .threeDView, .walkthrough, nil, // F810
                                                 .schedule, .materialTakeoff, .sheetList, .revisionSchedule, nil,
                                                 .duplicateView, .duplicateViewWithDetailing, .duplicateDependent, .renameView]))
        let sheets = submenu("Sheet Composition", commands([.newSheet, .placeView, .titleBlock, nil, .revisions, .guideGrid, .matchline])) // F810
        return [graphics, presentation, create, sheets, .separator()] + commands([.navigationWheel, nil]) + commands([.zoomExtents, .zoomIn, .zoomOut, .zoomOutTwice, .zoomRegion, .zoomSheetSize, nil, .previousPanZoom, .nextPanZoom, nil, .thinLines, .visibilityGraphics, .viewRange, .cropView, .toggleCropVisible, .sectionBox, .saveOrientation]) +
            [detail, styles, .separator(), temp] + commands([.revealHidden, .hideInView, .unhideInView, nil, .toggleNavigator, .toggleProperties]) + [sidebar, .separator(), fullScreen] // W4-SHELL
    }
}

/// Fills File ▸ Open Recent from `NSDocumentController.recentDocumentURLs` each time the menu opens (public API only).
@MainActor
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    /// A freshly built Open Recent submenu.
    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        shared.fill(menu)
        return menu
    }

    /// Delegate of the File menu: rebuilds the Open Recent submenu every time File opens, so the list is current
    /// and entirely ours (AppKit takes over a recents submenu it recognises, and only fills it during live tracking).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.title == "Open Recent" }) else { return }
        item.submenu = RecentDocumentsMenu.makeMenu()
    }

    func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            item.toolTip = url.path
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        // Own action (not clearRecentDocuments:) so AppKit does not take over this menu's delegate.
        let clear = NSMenuItem(title: "Clear Menu", action: urls.isEmpty ? nil : #selector(clearRecents(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc func clearRecents(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(sender) }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
