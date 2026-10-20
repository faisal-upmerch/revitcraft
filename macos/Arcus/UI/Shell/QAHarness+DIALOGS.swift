import AppKit
import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusIFC

// DIALOGS: the dialog catalog (every `DialogKind` with representative data, used by the offscreen render test
// `DialogRenderTests` and by these QA captures), and QA captures of the ten dialogs from the owner's review (Design
// Options, Model Health, the Model Health report, New Family, Filter Selection, Paste Aligned to Selected Levels,
// Import IFC, Import Revit, Toposurface from Point File, Simplify Surface), light and dark, presented as real sheets.

/// One dialog of the catalog: a file-safe name, the dialog, and whether it opens on the Furniture document.
struct DialogCatalogEntry {
    let name: String
    let kind: DialogKind
    var furniture = false
    /// One of the ten dialogs the owner reviewed (QA captures them as sheets).
    var reviewed = false
}

extension QAHarness {
    /// Fixture files for the import dialogs: an IFC of `m`, a point file, a CSV, a one-page PDF, a PNG and a DXF.
    /// The Revit file is never written: its dialog must say truthfully that it can't be read.
    static func dialogFixtures(_ m: BIMModel, at dir: URL) -> [String: URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [String: URL] = [:]
        let ifc = dir.appendingPathComponent("Courtyard House.ifc")
        if !FileManager.default.fileExists(atPath: ifc.path) {
            var o = IFCExportOptions(); o.fileName = ifc.lastPathComponent
            if let (files, _) = try? IFCExporter.export(m, options: o), let f = files.first { try? f.data.write(to: ifc) }
        }
        urls["ifc"] = ifc
        let pts = dir.appendingPathComponent("Survey Points.csv")
        try? "x,y,z\n0,0,0\n60,0,1.2\n60,45,3.3\n0,45,1.8\n30,21,2.7\n12,33,2.1\n48,9,1.5\n".write(to: pts, atomically: true, encoding: .utf8)
        urls["points"] = pts
        let csv = dir.appendingPathComponent("Doors.csv")
        try? "Mark,Width,Height\n101,3' - 0\",7' - 0\"\n102,2' - 8\",7' - 0\"\n".write(to: csv, atomically: true, encoding: .utf8)
        urls["csv"] = csv
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        let pdf = dir.appendingPathComponent("Plan.pdf")
        try? page.dataWithPDF(inside: page.bounds).write(to: pdf)
        urls["pdf"] = pdf
        let png = dir.appendingPathComponent("Underlay.png")
        let img = NSImage(size: NSSize(width: 64, height: 48), flipped: false) { r in NSColor.systemTeal.setFill(); r.fill(); return true }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { try? rep.representation(using: .png, properties: [:])?.write(to: png) }
        urls["png"] = png
        let dxf = dir.appendingPathComponent("Site Plan.dxf")
        try? "0\nSECTION\n2\nENTITIES\n0\nLINE\n8\nA-WALL\n10\n0\n20\n0\n11\n120\n21\n0\n0\nENDSEC\n0\nEOF\n".write(to: dxf, atomically: true, encoding: .utf8)
        urls["dxf"] = dxf
        urls["rvt"] = dir.appendingPathComponent("Sample.rvt")
        urls["dwf"] = dir.appendingPathComponent("Markup.dwfx")
        urls["arcus"] = dir.appendingPathComponent("Library.arcus")
        return urls
    }

    /// Sample Model Health results (the render test and QA show the grouped list with them).
    static let sampleHealthWarnings: [ModelWarning] = [
        ModelWarning(.error, code: "room.unbounded", "Room 9 is not in a properly enclosed region.", elements: [ElementID(9)]),
        ModelWarning(.warning, code: "wall.overlap", "Walls 412 and 413 overlap. One of them may be ignored when Arcus finds room boundaries.", elements: [ElementID(412), ElementID(413)]),
        ModelWarning(.warning, code: "door.host", "Door 77 cuts outside its host wall.", elements: [ElementID(77)]),
        ModelWarning(.warning, code: "mark.duplicate", "Elements have duplicate Mark values (D-12).", elements: [ElementID(301), ElementID(302)]),
        ModelWarning(.info, code: "link.unloaded", "Link “Site Survey.dwg” is not loaded.", elements: [ElementID(55)]),
    ]

    /// Every dialog with data from `s` (a project) and `f` (a Furniture document).
    static func dialogCatalog(project s: DocumentState, furniture f: DocumentState, fixtures urls: [String: URL]) -> [DialogCatalogEntry] {
        let m = s.model
        var d: [DialogCatalogEntry] = []
        func add(_ name: String, _ kind: DialogKind, furniture: Bool = false, reviewed: Bool = false) {
            d.append(DialogCatalogEntry(name: name, kind: kind, furniture: furniture, reviewed: reviewed))
        }
        let plan = m.views.first { $0.view?.kind == .floorPlan } ?? m.views.first
        let threeD = m.views.first { $0.view?.kind == .threeD }
        let sheet = m.sheets.first
        let sched = m.schedules.first
        let type = m.elements(.doors).first.flatMap { m.type(of: $0) }
        let url = { (k: String) in urls[k] ?? URL(fileURLWithPath: "/tmp/\(k)") }
        // Reviewed by the owner.
        add("design-options", .designOptions, reviewed: true)
        add("model-health", .modelHealth, reviewed: true)
        add("model-health-report", .report("Model Health Report", "Checked \(m.count) elements.\n\n3 warnings:\n• Wall 412 is not joined to Wall 413.\n• Room 9 is not enclosed.\n• Door 77 overlaps Window 78."), reviewed: true)
        add("new-family", .newFamily, reviewed: true)
        add("filter-selection", .filterSelection, reviewed: true)
        add("paste-to-levels", .pasteToLevels, reviewed: true)
        add("import-ifc", .importIFC(url("ifc")), reviewed: true)
        add("import-revit", .importRevit(url("rvt")), reviewed: true)
        add("site-point-file", .site(.pointFile(url("points"))), reviewed: true)
        if let topo = m.elements(.topography).first { add("site-simplify", .site(.simplify(topo.id)), reviewed: true) }
        // Views and sheets.
        add("new-schedule", .newSchedule(.category))
        add("new-schedule-material-takeoff", .newSchedule(.materialTakeoff))
        if let sched {
            add("schedule-properties", .scheduleProperties(sched.id))
            for tab in 1...4 { add("schedule-properties-tab\(tab)", .schedulePropertiesTab(sched.id, tab: tab, fieldID: nil)) }
            add("csv-import", .csvImport(sched.id, url("csv")))
        }
        add("new-sheet", .newSheet)
        if let sheet {
            add("place-view", .placeView(sheet.id))
            add("sheet-title", .sheetTitle(sheet.id))
            add("title-block", .f810(.titleBlock(sheet.id)))
            add("guide-grid", .f810(.guideGrid(sheet.id)))
        }
        if let plan {
            add("visibility-graphics", .visibilityGraphics(plan.id))
            add("view-range", .viewRange(plan.id))
            add("rename", .rename(plan.id))
            add("override-graphics", .overrideGraphics(view: plan.id, elements: Array(m.elements(.walls).prefix(2).map(\.id))))
            add("tag-all", .tagAll(plan.id))
            add("color-schemes", .colorSchemes(plan.id, placeLegend: false))
            add("find-replace", .findReplace(plan.id))
            add("check-spelling", .checkSpelling(plan.id))
            for mode in [ViewTemplatesMode.manage, .assign, .applyProperties, .temporary] {
                add("view-templates-\(String(describing: mode).lowercased())", .viewTemplates(plan.id, mode))
            }
            add("work-plane", .f2(.workPlane(plan.id)))
        }
        if let threeD { add("rendering", .f810(.render(threeD.id))) }
        add("render-gallery", .f810(.renderGallery))
        add("new-view-floor-plan", .newView(.floorPlan))
        add("new-area-plan", .newAreaPlan)
        add("filters", .filters(nil))
        // Manage.
        if let type { add("type-properties", .typeProperties(type.id)) }
        add("project-info", .projectInfo)
        add("project-units", .projectUnits)
        add("project-parameters", .projectParameters)
        add("global-parameters", .f11(.globalParameters))
        add("materials", .materials)
        add("line-styles", .lineStyles)
        add("object-styles", .objectStyles)
        for tab in AdditionalSettingsTab.allCases { add("additional-settings-\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))", .additionalSettings(tab)) }
        add("phases", .phases)
        add("revisions", .revisions)
        add("location", .location)
        add("specify-coordinates", .f11(.specifyCoordinates(Vec3(12, 8, 0))))
        add("project-turn", .f11(.projectTurn(mirror: false)))
        add("selection-sets", .f11(.selectionSets(edit: true)))
        add("add-to-set", .f11(.addToSet))
        add("starting-view", .f11(.startingView))
        add("keynoting-settings", .f11(.keynotingSettings))
        add("structural-settings", .f34(.structuralSettings))
        add("rebar-cover", .f34(.rebarCover))
        add("warnings", .warnings)
        add("select-by-id", .selectByID)
        add("select-by-category", .selectByCategory)
        add("purge", .purge)
        add("snaps", .snaps)
        add("keyboard-shortcuts", .keyboardShortcuts)
        add("user-interface", .userInterface)
        add("model-in-place", .f5(.modelInPlace))
        add("connect-levels", .f2(.connectLevels(nil)))
        add("site-settings", .site(.settings))
        add("site-point-file-toposolid", .site(.pointFileToposolid(url("points"))))
        if let link = m.elements(.links).first { add("site-from-import", .site(.fromImport(link.id))) }
        // Schedules.
        if let sched {
            add("combine-parameters", .f11(.combineParameters(sched.id)))
            add("schedule-shading", .f11(.shading(sched.id, [])))
            add("schedule-borders", .f11(.borders(sched.id, [])))
            add("schedule-font", .f11(.font(sched.id, [])))
            add("split-and-place", .f11(.splitAndPlace(sched.id)))
        }
        // Exchange.
        add("export-pdf", .exportPDF)
        add("export-ifc", .exportIFC)
        add("export-dwg", .exportDWG)
        add("export-dwfx", .f11(.exportDWFx))
        add("print-setup", .f11(.printSetup))
        if let data = try? Data(contentsOf: url("pdf")) { add("print-preview", .f11(.printPreview(data, "A101 - Floor Plan"))) }
        add("import-dxf", .importCAD(url("dxf"), isLink: false, isDWG: false))
        add("link-dxf", .importCAD(url("dxf"), isLink: true, isDWG: false))
        add("dwg-unavailable", .dwgUnavailable)
        add("manage-links", .manageLinks)
        add("link-pdf", .linkPDF(url("pdf")))
        add("link-image", .linkImage(url("png")))
        add("import-pdf", .f67(.importPDF(url("pdf"))))
        add("point-cloud-link", .f67(.pointFile(url("points"), topography: true)))
        add("dwf-markup", .f67(.dwfMarkup(url("dwf"))))
        add("insert-views", .f67(.insertViews(url("arcus"))))
        add("insert-2d", .f67(.insert2D(url("arcus"))))
        add("transfer-standards", .f67(.transferStandards))
        add("decal-types", .f67(.decalTypes(placeAfter: false)))
        add("component-library", .componentLibrary([.doors]))
        add("report-ifc-import", .report("IFC Import Report", "Imported 412 elements from Courtyard House.ifc.\n\nCreated:\n• 96 walls\n• 41 doors\n• 38 windows\n• 12 floors\n\nSkipped:\n- 3 IfcFlowTerminal elements (not supported)\n\nAll levels matched by elevation."))
        // Furniture.
        add("furniture-family-types", .fm3(.familyTypes), furniture: true)
        add("furniture-category", .fm3(.category), furniture: true)
        add("furniture-flex-ok", .fm3(.flex([])), furniture: true)
        add("furniture-flex-problems", .fm3(.flex(["Type 24\" Wide: Door Width is less than 0.", "Type 36\" Wide: shelves overlap the top."])), furniture: true)
        add("furniture-load-into", .fm3(.loadInto(close: false)), furniture: true)
        add("furniture-joint-rules", .fm6(.jointRules), furniture: true)
        add("furniture-stock-sheets", .fm7(.stockSheets), furniture: true)
        add("furniture-hardware-catalog", .fm7(.hardwareCatalog), furniture: true)
        add("furniture-cnc-export", .fm7(.cncExport), furniture: true)
        add("furniture-check-parts", .fm7(.checkParts), furniture: true)
        if let v3 = f.model.views.first(where: { $0.view?.kind == .threeD }) { add("furniture-explode-parts", .fmg2(.explodeParts(v3.id)), furniture: true) } // FMG2
        add("furniture-save-template", .fm8(.saveTemplate), furniture: true)
        add("load-furniture", .fm8(.loadFurniture))
        d += compDialogCatalog(f) // COMP: Component Library dialogs (QAHarness+COMP.swift)
        return d
    }

    /// QA: the ten reviewed dialogs presented as sheets on the open project (light and dark: one call per appearance).
    static func dialogsScreenshots(_ s: DocumentState, _ w: NSWindow, suffix: String) async {
        let fixtures = dialogFixtures(s.model, at: outDir.appendingPathComponent("fixtures-dialogs", isDirectory: true))
        let furniture = DocumentState(session: DocumentSession(model: FurnitureSamples.baseCabinetModel() ?? BIMModel()))
        let saved = s.healthWarnings
        if s.healthWarnings.isEmpty { s.healthWarnings = sampleHealthWarnings }
        if let wall = s.model.elements(.walls).first { s.session.selection.select([wall.id] + s.model.elements(.doors).prefix(3).map(\.id)) }
        for entry in dialogCatalog(project: s, furniture: furniture, fixtures: fixtures) where entry.reviewed {
            s.presented = entry.kind
            await pause(900)
            if let sheet = w.attachedSheet { await shot(sheet, "dialogs-\(entry.name)-\(suffix)") } else { await shot(w, "dialogs-\(entry.name)-\(suffix)") }
            s.presented = nil
            await pause(400)
        }
        s.healthWarnings = saved
        s.session.selection.clear()
    }
}
