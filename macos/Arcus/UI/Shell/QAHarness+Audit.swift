import AppKit
import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusOutput
import ArcusIFC
import ArcusCAD
import ArcusServices

// W4-AUDIT: UI audit captures for the screenshots scenario.
//
// The base scenario captures a dozen dialogs and the main window at two sizes. The audit adds every remaining
// `DialogKind` with representative data (fixture files are written under `<out>/fixtures`), the Settings window at
// three scroll positions so every section is visible, both hub tabs, the Family Editor for a hosted family and a tag,
// and the main window in both workspaces at 980, 1280 and 1920 pt. Everything runs for light and dark once each.
extension QAHarness {
    /// Widths the product owner reviews the shell at; heights keep a 16:10-ish aspect and are clamped to the screen.
    static let auditWidths: [CGFloat] = [980, 1280, 1920]

    /// Captures all audit states for the open Courtyard House document. `suffix` is "light" or "dark".
    static func auditCaptures(_ s: DocumentState, _ w: NSWindow, plan: ElementID, suffix: String) async {
        var captured = 0
        await step("UI audit captures (\(suffix))") {
            captured += await auditWorkspaceCaptures(s, w, plan: plan, suffix: suffix)
            s.open(plan)
            w.setContentSize(NSSize(width: 1500, height: 940))
            w.center()
            await pause(300)
            let dialogs = await auditDialogs(s, plan: plan)
            for (kind, name) in dialogs {
                s.presented = kind
                await pause(600)
                if let sheetWin = w.attachedSheet { await shot(sheetWin, "\(name)-\(suffix)") } else { await shot(w, "\(name)-\(suffix)") }
                s.presented = nil
                await pause(350)
                captured += 1
            }
            s.session.selection.clear()
            captured += await auditFamilyEditorCaptures(s, suffix: suffix)
            return "\(captured) captures (\(dialogs.count) dialogs)"
        }
    }

    /// Main window in each workspace at each audit width: the plan alone, and a wall selected (Properties filled).
    static func auditWorkspaceCaptures(_ s: DocumentState, _ w: NSWindow, plan: ElementID, suffix: String) async -> Int {
        let original = s.workspace
        var n = 0
        let screen = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1728, height: 1080)
        for ws in Workspace.allCases {
            s.workspace = ws
            await pause(400)
            let tag = ws == .bimFamiliar ? "familiar" : "spacious"
            for width in auditWidths {
                let height = min(screen.height - 20, (width * 0.6).rounded())
                w.setContentSize(NSSize(width: width, height: height))
                w.setFrameTopLeftPoint(NSPoint(x: screen.minX, y: screen.maxY))
                s.open(plan)
                _ = await waitForGraphics(s, plan)
                await pause(500)
                let label = "\(Int(width))"
                await shot(w, "audit-\(tag)-plan-\(label)-\(suffix)")
                n += 1
                if let wall = s.model.elements(.walls).first(where: { $0.levelID == s.model[plan]?.levelID }) {
                    s.session.selection.select([wall.id])
                    await pause(400)
                    await shot(w, "audit-\(tag)-wall-\(label)-\(suffix)")
                    n += 1
                    s.session.selection.clear()
                }
                // The Wall tool's Options Bar and contextual tab at this width.
                let router = CommandRouter(state: s)
                router.run(.wall)
                await pause(400)
                await shot(w, "audit-\(tag)-walltool-\(label)-\(suffix)")
                n += 1
                s.cancelTool()
            }
        }
        s.workspace = original
        await pause(300)
        return n
    }

    /// Every `DialogKind` not already captured by the base scenario, with data from the open project.
    static func auditDialogs(_ s: DocumentState, plan: ElementID) async -> [(DialogKind, String)] {
        let m = s.model
        let fx = outDir.appendingPathComponent("fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: fx, withIntermediateDirectories: true)
        // Fixture files: a DXF and a PDF of the plan, an IFC of the model, a CSV of the door schedule, an image and a point file.
        let dxfURL = fx.appendingPathComponent("Plan.dxf"), ifcURL = fx.appendingPathComponent("Model.ifc"), csvURL = fx.appendingPathComponent("Doors.csv")
        let pdfURL = fx.appendingPathComponent("Plan.pdf"), pngURL = fx.appendingPathComponent("Underlay.png"), ptsURL = fx.appendingPathComponent("Points.csv")
        if let g = await waitForGraphics(s, plan) {
            try? DXFWriter.write(g, units: .millimeters).write(to: dxfURL)
        }
        if !FileManager.default.fileExists(atPath: ifcURL.path) {
            var o = IFCExportOptions(); o.fileName = "Model.ifc"
            if let (files, _) = try? IFCExporter.export(m, options: o), let f = files.first { try? f.data.write(to: ifcURL) }
        }
        if let sched = m.schedules.first(where: { $0.name == "Door Schedule" }) {
            try? ScheduleCSV.export(ScheduleEngine.compute(sched, m)).write(to: csvURL)
        }
        if !FileManager.default.fileExists(atPath: pdfURL.path) {
            var job = PDFExportJob(items: [PDFExportItem(elementID: plan, kind: .view)], outputDirectory: fx)
            job.combinedFileName = "Plan.pdf"; job.overwrite = .replace
            _ = try? await PDFExporter.export(m, job: job)
        }
        if let c = s.canvases[plan] as? Canvas2DView, let rep = c.renderedSnapshot(), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: pngURL)
        }
        try? "x,y,z\n0,0,0\n20,0,0.4\n20,15,1.1\n0,15,0.6\n10,7,0.9\n".write(to: ptsURL, atomically: true, encoding: .utf8)
        let rvtURL = fx.appendingPathComponent("Sample.rvt") // never created: the dialog must say truthfully that it can't be read

        var d: [(DialogKind, String)] = []
        let sheet = m.sheets.first(where: { $0.sheet?.number == "A101" }) ?? m.sheets.first
        let sched = m.schedules.first(where: { $0.name == "Door Schedule" }) ?? m.schedules.first
        let walls = m.elements(.walls).filter { $0.levelID == m[plan]?.levelID }.prefix(3).map(\.id)
        // Project Browser and views.
        d.append((.newSheet, "new-sheet-dialog"))
        if let sheet { d.append((.placeView(sheet.id), "place-view-dialog")); d.append((.sheetTitle(sheet.id), "sheet-title-dialog")) }
        d.append((.viewRange(plan), "view-range-dialog"))
        d.append((.rename(plan), "rename-dialog"))
        // The only kinds the router presents this dialog for.
        for kind in [ViewKind.floorPlan, .ceilingPlan, .structuralPlan] { d.append((.newView(kind), "new-view-\(kind.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-dialog")) }
        d.append((.newAreaPlan, "new-area-plan-dialog"))
        d.append((.overrideGraphics(view: plan, elements: walls), "override-graphics-dialog"))
        d.append((.tagAll(plan), "tag-all-dialog"))
        d.append((.colorSchemes(plan, placeLegend: false), "color-schemes-dialog"))
        d.append((.colorSchemes(plan, placeLegend: true), "color-schemes-legend-dialog"))
        d.append((.filters(nil), "filters-dialog"))
        for mode in [ViewTemplatesMode.manage, .assign, .applyProperties, .temporary] {
            d.append((.viewTemplates(plan, mode), "view-templates-\(String(describing: mode).lowercased())-dialog"))
        }
        d.append((.objectStyles, "object-styles-dialog"))
        d.append((.warnings, "warnings-dialog"))
        d.append((.selectByID, "select-by-id-dialog"))
        for tab in AdditionalSettingsTab.allCases { d.append((.additionalSettings(tab), "additional-settings-\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-dialog")) }
        d.append((.userInterface, "user-interface-dialog"))
        d.append((.findReplace(plan), "find-replace-dialog"))
        d.append((.checkSpelling(plan), "check-spelling-dialog"))
        // Schedules.
        for kind in [ScheduleKind.category, .multiCategory, .materialTakeoff, .sheetList] { d.append((.newSchedule(kind), "new-schedule-\(kind.rawValue.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-"))-dialog")) }
        if let sched {
            for tab in 1...4 { d.append((.schedulePropertiesTab(sched.id, tab: tab, fieldID: nil), "schedule-properties-tab\(tab)-dialog")) }
            d.append((.csvImport(sched.id, csvURL), "csv-import-dialog"))
        }
        // Manage.
        d.append((.projectInfo, "project-info-dialog"))
        d.append((.projectParameters, "project-parameters-dialog"))
        d.append((.phases, "phases-dialog"))
        d.append((.designOptions, "design-options-dialog"))
        d.append((.revisions, "revisions-dialog"))
        d.append((.location, "location-dialog"))
        d.append((.snaps, "snaps-dialog"))
        d.append((.manageLinks, "manage-links-dialog"))
        d.append((.purge, "purge-dialog"))
        d.append((.newFamily, "new-family-dialog"))
        d.append((.report("Model Health Report", "Checked \(m.count) elements.\n\n3 warnings:\n• Wall 412 is not joined to Wall 413.\n• Room 9 is not enclosed.\n• Door 77 overlaps Window 78."), "report-dialog"))
        if let door = m.elements(.doors).first, let t = m.type(of: door) { d.append((.typeProperties(t.id), "type-properties-family-dialog")) }
        d.append((.componentLibrary([.doors]), "component-library-doors"))
        // Selection.
        d.append((.selectByCategory, "select-by-category-dialog"))
        d.append((.filterSelection, "filter-selection-dialog"))
        d.append((.pasteToLevels, "paste-to-levels-dialog"))
        // Exchange.
        d.append((.importCAD(dxfURL, isLink: false, isDWG: false), "import-dxf-dialog"))
        d.append((.importCAD(dxfURL, isLink: true, isDWG: false), "link-dxf-dialog"))
        d.append((.importCAD(fx.appendingPathComponent("Site.dwg"), isLink: false, isDWG: true), "import-dwg-dialog"))
        d.append((.importIFC(ifcURL), "import-ifc-dialog"))
        d.append((.linkPDF(pdfURL), "link-pdf-dialog"))
        d.append((.linkImage(pngURL), "link-image-dialog"))
        d.append((.importRevit(rvtURL), "import-revit-dialog"))
        // Site.
        d.append((.site(.settings), "site-settings-dialog"))
        d.append((.site(.pointFile(ptsURL)), "site-point-file-dialog"))
        d.append((.site(.pointFileToposolid(ptsURL)), "site-point-file-toposolid-dialog"))
        if let topo = m.elements(.topography).first { d.append((.site(.simplify(topo.id)), "site-simplify-dialog")) }
        if let link = m.elements(.links).first { d.append((.site(.fromImport(link.id)), "site-from-import-dialog")) }
        // Dialogs that need a selection: the filter dialog and Paste to Levels read it when they open.
        s.session.selection.select(Array(walls))
        return d
    }

    /// The Family Editor for the first door's family (hosted, with forms) and for a tag family (labels).
    static func auditFamilyEditorCaptures(_ s: DocumentState, suffix: String) async -> Int {
        var n = 0
        var families: [(ElementID, String)] = []
        if let door = s.model.elements(.doors).first, let fam = (door.typeData ?? s.model.typeData(of: door))?.familyID { families.append((fam, "door")) }
        if let tag = s.model.elements(.tags).first, let fam = (tag.typeData ?? s.model.typeData(of: tag))?.familyID { families.append((fam, "tag")) }
        for (fam, label) in families {
            FamilyEditorWindowController.open(familyID: fam, state: s)
            await pause(900)
            if let wc = FamilyEditorWindowController.open.last, let w = wc.window {
                await shot(w, "family-editor-\(label)-\(suffix)")
                n += 1
                w.close()
                await pause(300)
            }
        }
        return n
    }

    /// The Settings window scrolled to the top, middle and bottom (every section appears in one of the three), and the
    /// hub's New tab (the base scenario captures Recent).
    static func auditAppWindowCaptures(suffix: String) async -> Int {
        var n = 0
        AppDelegate.shared?.showSettings()
        await pause(700)
        if let w = NSApp.windows.first(where: { $0.title == "Arcus Settings" }) {
            var scroll: NSScrollView?
            func find(_ v: NSView) { if let sv = v as? NSScrollView, scroll == nil { scroll = sv } else { v.subviews.forEach(find) } }
            if let cv = w.contentView { find(cv) }
            let positions: [(Double, String)] = [(0, "top"), (0.5, "middle"), (1, "bottom")]
            for (f, label) in positions {
                if let sv = scroll, let doc = sv.documentView {
                    let maxY = max(0, doc.bounds.height - sv.contentView.bounds.height)
                    let y = doc.isFlipped ? maxY * f : maxY * (1 - f)
                    sv.contentView.scroll(to: NSPoint(x: 0, y: y))
                    sv.reflectScrolledClipView(sv.contentView)
                    await pause(250)
                }
                await shot(w, "settings-\(label)-\(suffix)")
                n += 1
                if scroll == nil { break }
            }
            w.close()
        }
        let hub = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        hub.titlebarAppearsTransparent = true
        hub.title = "Arcus"
        hub.isReleasedWhenClosed = false
        hub.contentViewController = NSHostingController(rootView: ProjectHubView(initialTab: .new))
        hub.center()
        hub.orderFront(nil)
        await pause(700)
        await shot(hub, "hub-new-\(suffix)")
        n += 1
        hub.close()
        return n
    }
}
