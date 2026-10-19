import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusCanvasMetal
import ArcusApplication
import ArcusPersistence
import ArcusOutput
import ArcusIFC
import ArcusCAD
import ArcusServices
import ArcusViewport3D

/// In-app scripted UI test and visual QA harness.
///
///   Arcus --qa workflow --qa-out <dir> [--qa-quit]
///   Arcus --qa screenshots --qa-out <dir> [--qa-quit]
///   Arcus --qa all --qa-out <dir> --qa-quit
///
/// The workflow scenario drives the real tools (pointer input into the same state machines the canvas uses),
/// commands, dialogs' underlying actions, exporters and persistence, and records pass/fail per step in
/// `results.json`. The screenshots scenario captures the running windows (light/dark, minimum and spacious sizes).
@MainActor
enum QAHarness {
    struct StepResult: Codable { var name: String; var passed: Bool; var detail: String; var seconds: Double }
    static var results: [StepResult] = []
    static var outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ArcusQA")

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--qa"), i + 1 < args.count else { return }
        let scenario = args[i + 1]
        // QA runs in the background: canvases must render even when other windows cover this one, so captures are real.
        MetalCanvasView.drawsWhenOccluded = true
        if let o = args.firstIndex(of: "--qa-out"), o + 1 < args.count { outDir = URL(fileURLWithPath: args[o + 1]) }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        Task {
            if scenario == "workflow" || scenario == "all" { await workflow() }
            if scenario == "screenshots" || scenario == "all" { await screenshots() }
            if scenario == "interact" || scenario == "all" { await interaction() }
            writeResults()
            if args.contains("--qa-quit") {
                for d in NSDocumentController.shared.documents { d.updateChangeCount(.changeCleared); d.close() }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Helpers

    static func step(_ name: String, _ body: () async throws -> String) async {
        // Return to the run loop so each step is its own undo group (as separate user events would be).
        await pause(30)
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let detail = try await body()
            results.append(StepResult(name: name, passed: true, detail: detail, seconds: CFAbsoluteTimeGetCurrent() - t0))
        } catch {
            results.append(StepResult(name: name, passed: false, detail: "\(error)", seconds: CFAbsoluteTimeGetCurrent() - t0))
        }
    }

    struct QAError: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }
    static func check(_ c: Bool, _ msg: String) throws { if !c { throw QAError(msg) } }

    static func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    static func waitForGraphics(_ state: DocumentState, _ view: ElementID, timeout: Double = 20) async -> ViewGraphics? {
        let t0 = CFAbsoluteTimeGetCurrent()
        if state.graphics.graphics(view) == nil { state.graphics.request(view) }
        while CFAbsoluteTimeGetCurrent() - t0 < timeout {
            if let g = state.graphics.graphics(view), g.modelRevision == state.model.revision, !state.graphics.isBuilding { return g }
            await pause(50)
        }
        return state.graphics.graphics(view)
    }

    static func activeState() async -> DocumentState? {
        for _ in 0..<100 {
            if let s = (NSDocumentController.shared.currentDocument as? ArcusDocument)?.state ?? (NSDocumentController.shared.documents.last as? ArcusDocument)?.state { return s }
            await pause(100)
        }
        return nil
    }

    static func input(_ p: Vec2, hit: ElementID? = nil) -> ToolInput {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        i.hitCandidates = hit.map { [$0] } ?? []
        return i
    }

    static func click(_ tool: any InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        tool.pointerMoved(input(p, hit: hit))
        tool.pointerDown(input(p, hit: hit))
    }

    static func view(_ s: DocumentState, kind: ViewKind, level: String? = nil, name: String? = nil) -> Element? {
        s.model.views.first { v in
            v.view?.kind == kind && (level == nil || s.model[v.levelID]?.name == level) && (name == nil || v.name == name) && v.view?.parentViewID == nil
        }
    }

    // MARK: Workflow

    static func workflow() async {
        let appDelegate = AppDelegate.shared!
        await step("Create project from Architectural template") {
            appDelegate.newProject(template: .architectural, units: .metric, name: "QA Project")
            guard let s = await activeState() else { throw QAError("No document window") }
            try check(s.model.levels.count == 3, "Expected 3 levels, got \(s.model.levels.count)")
            return "\(s.model.count) template elements"
        }
        guard let s = await activeState() else { return }
        s.window?.setContentSize(NSSize(width: 1500, height: 940))
        let l1 = view(s, kind: .floorPlan, level: "Level 1")!
        s.open(l1.id)
        let router = CommandRouter(state: s)
        func tool(_ id: CommandID) -> (any InteractiveTool)? { router.makeTool(id) }

        await step("Draw walls (rectangle) in plan") {
            let t = WallTool(ctx: s.toolContext(for: l1.id), mode: .rectangle)
            click(t, Vec2(0, 0)); click(t, Vec2(12, 8))
            let walls = s.model.elements(.walls)
            try check(walls.count == 4, "Expected 4 walls, got \(walls.count)")
            return "4 walls, joined corners"
        }
        let walls = s.model.elements(.walls)
        let south = walls.first { abs(($0.wall?.location.midpoint.y ?? 1)) < 1e-6 }!
        let east = walls.first { abs(($0.wall?.location.midpoint.x ?? 0) - 12) < 1e-6 }!
        await step("Place hosted door and window") {
            s.graphics.request(l1.id)
            _ = await waitForGraphics(s, l1.id)
            let d = InsertTool(ctx: s.toolContext(for: l1.id), category: .doors)
            d.pointerMoved(input(Vec2(6, 0.3), hit: south.id)); d.pointerDown(input(Vec2(6, 0.3), hit: south.id))
            let w = InsertTool(ctx: s.toolContext(for: l1.id), category: .windows)
            w.pointerMoved(input(Vec2(11.7, 4), hit: east.id)); w.pointerDown(input(Vec2(11.7, 4), hit: east.id))
            try check(s.model.elements(.doors).count == 1 && s.model.elements(.windows).count == 1, "Door/window not placed: \(s.session.lastError?.message ?? "")")
            try check(WallGeometry.openings(s.model[south.id]!, s.model).count == 1, "Door does not cut its host")
            return "door + window with host cuts and tags"
        }
        await step("Floor from picked walls (sketch mode)") {
            let f = SketchTool(ctx: s.toolContext(for: l1.id), target: .floor, commandID: .floorPickWalls)
            f.pointerDown(input(Vec2(6, 4)))
            try check(f.finish(), "Sketch did not finish: \(s.session.lastError?.message ?? "")")
            try check(s.model.elements(.floors).count == 1, "No floor")
            return "floor area \(Parameters.format(Parameters.value(ParameterID("q.area"), of: s.model.elements(.floors)[0], s.model), type: .area, model: s.model))"
        }
        await step("Room, column, component, stair with railings") {
            click(RoomTool(ctx: s.toolContext(for: l1.id)), Vec2(6, 4))
            click(ComponentTool(ctx: s.toolContext(for: l1.id), category: .columns, commandID: .column), Vec2(3, 3))
            click(ComponentTool(ctx: s.toolContext(for: l1.id), category: .furniture, commandID: .component), Vec2(4, 6))
            let st = StairTool(ctx: s.toolContext(for: l1.id), shape: .straight)
            click(st, Vec2(9.5, 1)); click(st, Vec2(9.5, 6))
            try check(st.finish(), "Create Stair did not finish") // STAIR: sketch mode
            let room = s.model.elements(.rooms).first
            try check(room.map { RoomGeometry.boundary($0, s.model).state == .bounded } ?? false, "Room not bounded")
            try check(s.model.elements(.stairs).count == 1 && s.model.elements(.railings).count == 2, "Stair/railings missing")
            try check(s.model.elements(.columns).count == 1 && s.model.elements(.furniture).count == 1, "Column/component missing")
            return "room area \(Parameters.format(Parameters.value(ParameterID("q.area"), of: room!, s.model), type: .area, model: s.model))"
        }
        await step("Beam and grid") {
            let b = LineTool(ctx: s.toolContext(for: l1.id), kind: .beam, commandID: .beam)
            click(b, Vec2(0, 4)); click(b, Vec2(12, 4))
            let g = LineTool(ctx: s.toolContext(for: l1.id), kind: .grid, commandID: .grid)
            click(g, Vec2(0, -3)); click(g, Vec2(0, 11))
            try check(s.model.elements(.structuralFraming).count == 1 && s.model.elements(.grids).count == 1, "Beam/grid missing")
            return "beam + grid 1"
        }
        await step("Roof by footprint on Level 2 and ceiling in RCP") {
            let l2 = view(s, kind: .floorPlan, level: "Level 2")!
            s.open(l2.id)
            let r = SketchTool(ctx: s.toolContext(for: l2.id), target: .roof, commandID: .roofFootprint)
            r.drawMode = .rectangle
            click(r, Vec2(-0.6, -0.6)); click(r, Vec2(12.6, 8.6))
            try check(r.finish(), "Roof sketch failed: \(s.session.lastError?.message ?? "")")
            let rcp = view(s, kind: .ceilingPlan, level: "Level 1")!
            s.open(rcp.id)
            let c = SketchTool(ctx: s.toolContext(for: rcp.id), target: .ceiling, commandID: .ceiling)
            c.drawMode = .rectangle
            click(c, Vec2(0.2, 0.2)); click(c, Vec2(11.8, 7.8))
            try check(c.finish(), "Ceiling sketch failed")
            try check(s.model.elements(.roofs).count == 1 && s.model.elements(.ceilings).count == 1, "Roof/ceiling missing")
            return "hip roof + ceiling"
        }
        await step("Add a level from an elevation") {
            let south = view(s, kind: .elevation, name: "South")!
            s.open(south.id)
            let t = LevelTool(ctx: s.toolContext(for: south.id))
            click(t, Vec2(-15, 11.5)); click(t, Vec2(15, 11.5))
            try check(s.model.levels.count == 4, "Level not added")
            try check(s.model.views.contains { $0.view?.kind == .floorPlan && s.model[$0.levelID]?.level?.elevation == 11.5 }, "Plan view for new level not created")
            return "Level 4 at 11.5 m with plan and RCP"
        }
        s.open(l1.id)
        await step("Instance and type parameters, undo/redo") {
            let w = s.model.elements(.walls).first!
            s.session.setParameter(ParameterID("wall.topOffset"), text: "300", on: [w.id], type: .length, name: "Top Offset")
            try check(abs((s.model[w.id]?.wall?.topOffset ?? 0) - 0.3) < 1e-9, "Top offset not applied")
            guard let door = s.model.elements(.doors).first else { throw QAError("No door") }
            await pause(30)
            @MainActor func width() -> Double { s.model[door.id].flatMap { InsertGeometry.openingSize($0, s.model)?.width } ?? -1 }
            let original = width()
            s.session.setParameter(Parameters.familyParamID("Width"), text: "1000", on: [door.id], type: .length, name: "Width")
            try check(abs(width() - 1.1) < 1e-6, "Type width not applied (\(width()))")
            await pause(30)
            let undoName = s.session.undoManager.undoActionName
            s.session.undoManager.undo()
            let t = s.model[door.id].flatMap { s.model.type(of: $0) }
            try check(abs(width() - original) < 1e-6, "Undo “\(undoName)” failed (\(width())); type \(t?.name ?? "?") width param \(t?.typeData?.params[Parameters.familyParamID("Width")]?.description ?? "?")")
            s.session.undoManager.redo()
            try check(abs(width() - 1.1) < 1e-6, "Redo failed (\(width()))")
            return String(format: "wall top offset; door type width %.2f → 1.10 → undo %.2f → redo 1.10", original, original)
        }
        await step("Dimension, tags, text, revision cloud") {
            let d = DimensionTool(ctx: s.toolContext(for: l1.id), kind: .aligned)
            let west = s.model.elements(.walls).first { abs(($0.wall?.location.midpoint.x ?? 1)) < 1e-6 }!
            d.pointerDown(input(Vec2(0, 4), hit: west.id))
            d.pointerDown(input(Vec2(12, 4), hit: east.id))
            d.pointerDown(input(Vec2(6, -3)))
            s.session.perform("Tag All") { tx in
                let types = Dictionary(uniqueKeysWithValues: Category.taggable.compactMap { c in TagTool.defaultTagType(for: c, tx.model).map { (c, $0) } })
                TagAll.run(TagAllOptions(tagTypes: types), view: l1.id, visible: router.visibleElementIDs(l1.id), scale: l1.view?.scale ?? 100, in: tx)
            }
            s.session.perform("Text") { tx in tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(0, -5), text: "QA NOTE")), ownerViewID: l1.id) }
            let rev = s.model.revisions.first!.id
            s.session.perform("Cloud") { tx in tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: .rectangle(Rect2(min: Vec2(5, -1), max: Vec2(7, 1))), revisionID: rev)), ownerViewID: l1.id) }
            try check(s.model.elements(.dimensions).count == 1, "Dimension missing")
            let measured = DimensionQueries.measure(s.model.elements(.dimensions)[0], s.model).first ?? 0
            return String(format: "dimension %.3f m; %d tags", measured, s.model.elements(.tags).count)
        }
        await step("Keyboard element stepping (] / [) for VoiceOver users") {
            s.open(l1.id)
            _ = await waitForGraphics(s, l1.id)
            guard let canvas = s.canvases[l1.id] as? Canvas2DView else { throw QAError("Plan canvas not found") }
            s.session.selection.clear()
            canvas.stepSelection(1)
            guard let first = s.session.selection.single else { throw QAError("] selected nothing") }
            canvas.stepSelection(1)
            guard let second = s.session.selection.single, second != first else { throw QAError("] did not advance") }
            canvas.stepSelection(-1)
            try check(s.session.selection.single == first, "[ did not go back")
            let actions = canvas.accessibilityCustomActions()?.map(\.name) ?? []
            try check(actions.contains("Select next element") && actions.contains("Delete selection"), "Missing VoiceOver actions: \(actions)")
            s.session.selection.clear()
            return "stepped \(s.model[first]?.category.singularName ?? "?") → \(s.model[second]?.category.singularName ?? "?") → back; \(actions.count) VoiceOver actions"
        }
        await step("Section view generated from model") {
            let t = SectionTool(ctx: s.toolContext(for: l1.id))
            click(t, Vec2(-2, 4)); click(t, Vec2(14, 4))
            guard let sec = s.model.views.first(where: { $0.view?.kind == .section }) else { throw QAError("No section view") }
            s.open(sec.id)
            let g = await waitForGraphics(s, sec.id)
            try check(g?.items.contains { $0.category == .walls && $0.layer == .cut } ?? false, "Section has no cut walls")
            return "\(g?.items.count ?? 0) items"
        }
        await step("Schedules update live") {
            let sched = s.model.schedules.first { $0.name == "Door Schedule" }!
            s.open(sched.id)
            let t = ScheduleEngine.compute(sched, s.model)
            try check(t.elementCount == 1, "Door schedule has \(t.elementCount) rows")
            let rooms = ScheduleEngine.compute(s.model.schedules.first { $0.name == "Room Schedule" }!, s.model)
            try check(rooms.elementCount == 1, "Room schedule empty")
            return "doors \(t.elementCount), rooms \(rooms.elementCount)"
        }
        await step("Sheet with plan and schedule viewports") {
            let sheet = s.model.sheets.first!
            s.session.perform("Place") { tx in
                tx.create(.viewports, data: .viewport(ViewportData(viewID: l1.id, center: Vec2(0.3, 0.3), detailNumber: "1")), ownerViewID: sheet.id)
                tx.create(.viewports, data: .viewport(ViewportData(viewID: s.model.schedules.first { $0.name == "Door Schedule" }!.id, center: Vec2(0.65, 0.45), detailNumber: "2")), ownerViewID: sheet.id)
            }
            s.open(sheet.id)
            let g = await waitForGraphics(s, sheet.id)
            try check(g?.items.contains { $0.category == .viewports } ?? false, "Sheet has no viewports")
            return "sheet \(sheet.sheet?.number ?? "")"
        }
        let exportDir = outDir.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        await step("Export vector PDF set") {
            var job = PDFExportJob(items: s.model.sheets.map { PDFExportItem(elementID: $0.id, kind: .sheet) } + [PDFExportItem(elementID: l1.id, kind: .view)], outputDirectory: exportDir)
            job.combinedFileName = "QA Set.pdf"
            job.overwrite = .replace
            let r = try await PDFExporter.export(s.model, job: job)
            try check(r.pageCount == s.model.sheets.count + 1 && r.rasterPages == 0, "PDF pages \(r.pageCount), raster \(r.rasterPages)")
            return "\(r.pageCount) vector pages in \(String(format: "%.2f", r.elapsed)) s"
        }
        await step("Export IFC4 and IFC2x3") {
            var o = IFCExportOptions()
            o.fileName = "QA.ifc"
            let (files, rep) = try IFCExporter.export(s.model, options: o)
            for f in files { try f.data.write(to: exportDir.appendingPathComponent(f.name)) }
            o.schema = .ifc2x3; o.fileName = "QA-2x3.ifc"
            let (files2, _) = try IFCExporter.export(s.model, options: o)
            for f in files2 { try f.data.write(to: exportDir.appendingPathComponent(f.name)) }
            try check(rep.exportedElements > 10, "Too few IFC elements")
            // Round trip into a fresh project.
            let (fresh, _) = ProjectTemplates.make(.architectural, units: .metric)
            let tx = TransactionContext(model: fresh, name: "Import")
            let ir = try IFCImporter.importFile(files[0].data, fileName: files[0].name, into: tx)
            let m2 = try tx.commit().model
            try check(m2.elements(.walls).count >= 4, "IFC round trip lost walls")
            return "exported \(rep.exportedElements); re-imported \(ir.nativeCounts.values.reduce(0, +)) native elements"
        }
        await step("Export schedule CSV and view DXF") {
            let table = ScheduleEngine.compute(s.model.schedules.first { $0.name == "Door Schedule" }!, s.model)
            try ScheduleCSV.export(table).write(to: exportDir.appendingPathComponent("Doors.csv"))
            let g = await waitForGraphics(s, l1.id)
            try DXFWriter.write(g!, units: .millimeters).write(to: exportDir.appendingPathComponent("Level 1.dxf"))
            return "CSV + DXF"
        }
        await step("Link DXF, reload, convert to detail lines (source untouched)") {
            let dxfURL = exportDir.appendingPathComponent("Level 1.dxf")
            let before = try Data(contentsOf: dxfURL)
            var o = CADImportOptions()
            o.isLink = true
            o.levelID = s.model.levels.first?.id
            let prepared = try await CADLinkService.prepare(url: dxfURL, bookmark: nil, options: o, projectSurveyOrigin: .zero)
            var linkID: ElementID?
            s.session.perform("Link DXF") { tx in linkID = try CADLinkService.place(prepared: prepared, in: tx).0 }
            guard let linkID else { throw QAError("Link failed: \(s.session.lastError?.message ?? "")") }
            s.session.perform("Reload") { tx in _ = try CADLinkService.reload(linkElementID: linkID, from: dxfURL, in: tx, progress: { _ in }, isCancelled: { false }) }
            var converted = 0
            s.session.perform("Convert") { tx in converted = try CADConverter.convert(linkElement: linkID, layers: nil, target: .detailLines(viewID: l1.id), in: tx) }
            try check(converted > 0, "Nothing converted")
            try check(try Data(contentsOf: dxfURL) == before, "Source DXF was modified")
            return "\(prepared.report.converted) entities linked; \(converted) converted"
        }
        await step("DWG import reports licensing truthfully") {
            let p = DWGProviders.current
            if p.isAvailable { return "DWG available: \(p.sdkName)" } // DWG: the bundled engines, an installed converter or the ODA SDK
            try check((p.unavailableReason ?? "").contains("ODA"), "Unavailable reason does not mention the ODA SDK")
            return p.unavailableReason ?? ""
        }
        await step("Save, close and reopen") {
            let url = outDir.appendingPathComponent("QA Project.arcus")
            try? FileManager.default.removeItem(at: url)
            let info = AppVersionInfo.current.writeInfo(documentID: UUID())
            try ArcusPackage.write(s.model, to: url, info: info)
            let (m2, manifest) = try ArcusPackage.read(from: url)
            try check(m2.count == s.model.count, "Element count changed: \(m2.count) vs \(s.model.count)")
            try check(ArcusPackage.verify(url).isHealthy, "Integrity check failed")
            return "\(m2.count) elements, schema \(manifest.schemaVersion)"
        }
        await step("Open Recent menu lists projects") {
            let url = outDir.appendingPathComponent("QA Project.arcus")
            let dc = NSDocumentController.shared
            let hadRecents = !dc.recentDocumentURLs.isEmpty
            dc.noteNewRecentDocumentURL(url)
            defer { if !hadRecents { dc.clearRecentDocuments(nil) } }
            guard let file = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "File" })?.submenu else { throw QAError("No File menu") }
            file.delegate?.menuNeedsUpdate?(file)   // what AppKit does when the File menu opens
            guard let recent = file.items.first(where: { $0.title == "Open Recent" })?.submenu else { throw QAError("No Open Recent menu") }
            let titles = recent.items.map(\.title)
            try check(titles.contains { $0.contains("QA Project") }, "Open Recent shows \(titles)")
            return "\(titles.count) items: \(titles.joined(separator: ", "))"
        }
        await step("3D coordination view") {
            router.run(.threeDView)
            await pause(1500)
            guard let host = s.canvases[s.activeViewID ?? ElementID(0)] as? Viewport3DHost else { throw QAError("3D host missing") }
            if let img = host.viewport.snapshot(size: CGSize(width: 1200, height: 800)) { save(img, "workflow-3d") }
            return "\(host.viewport.statistics.triangles) triangles"
        }
    }

    // MARK: Screenshots

    static func screenshots() async {
        let dir = outDir.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            await pause(300)
            AppDelegate.shared?.showOnboarding()
            await pause(700)
            if let w = NSApp.windows.first(where: { $0.contentViewController is NSHostingController<OnboardingView> }) { await shot(w, "onboarding-\(suffix)"); w.close() }
            AppDelegate.shared?.showHub(tab: .recent)
            await pause(700)
            if let w = NSApp.windows.first(where: { $0.title == "Home" && $0.contentViewController is NSHostingController<ProjectHubView> }) { await shot(w, "hub-\(suffix)") }
            await homeScreenshots(suffix) // HOME: each Start card, Recent and its filter, default and minimum size
            _ = await auditAppWindowCaptures(suffix: suffix) // W4-AUDIT: Settings (all sections) and the hub's New tab
            await step("Open Courtyard House (\(suffix))") {
                let t0 = CFAbsoluteTimeGetCurrent()
                AppDelegate.shared?.openSample()
                var s: DocumentState?
                for _ in 0..<200 {
                    s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state
                    if s?.model.elements(.rooms).count ?? 0 > 100 { break }
                    await pause(50)
                }
                guard let s else { throw QAError("Sample did not open") }
                let elapsed = CFAbsoluteTimeGetCurrent() - t0
                await pause(1500)
                footprints["Courtyard House open (\(suffix))"] = footprintMB()
                return String(format: "%d elements opened in %.2f s; footprint %.0f MB", s.model.count, elapsed, footprintMB())
            }
            guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, let w = s.window else { continue }
            for (size, label) in [(NSSize(width: 980, height: 640), "min"), (NSSize(width: 1680, height: 1040), "spacious")] {
                w.setContentSize(size)
                w.center()
                let plan = view(s, kind: .floorPlan, level: "Ground Floor")!
                s.open(plan.id)
                _ = await waitForGraphics(s, plan.id)
                await pause(600)
                await shot(w, "plan-\(label)-\(suffix)")
                // Selected wall with properties.
                if let wall = s.model.elements(.walls).first(where: { $0.levelID == plan.levelID }) {
                    s.session.selection.select([wall.id])
                    await pause(500)
                    await shot(w, "wall-selected-\(label)-\(suffix)")
                    s.session.selection.clear()
                }
            }
            w.setContentSize(NSSize(width: 1600, height: 1000))
            let plan = view(s, kind: .floorPlan, level: "Ground Floor")!
            s.open(plan.id)
            // Sketch mode.
            let router = CommandRouter(state: s)
            router.run(.floor)
            if let t = s.activeTool { click(t, Vec2(60, 0)); click(t, Vec2(70, 0)); t.pointerMoved(input(Vec2(70, 8))) }
            await pause(500)
            await shot(w, "sketch-mode-\(suffix)")
            s.activeTool?.cancelSketch(); s.cancelTool()
            // Wall tool with temporary dimensions.
            router.run(.wall)
            if let t = s.activeTool { click(t, Vec2(56, 2)); t.pointerMoved(input(Vec2(60.5, 2))) }
            await pause(400)
            await shot(w, "wall-tool-\(suffix)")
            s.cancelTool()
            await shellScreenshots(s, w, suffix: suffix) // W4-SHELL: floating sidebar, collapsed, narrow, inspector
            if let sched = s.model.schedules.first(where: { $0.name == "Door Schedule" }) { s.open(sched.id); await pause(900); await shot(w, "schedule-\(suffix)") }
            if let sheet = s.model.sheets.first(where: { $0.sheet?.number == "A101" }) {
                s.open(sheet.id)
                _ = await waitForGraphics(s, sheet.id, timeout: 40)
                await pause(800)
                await shot(w, "sheet-\(suffix)")
            }
            if let sec = view(s, kind: .section, name: "Section 1") { s.open(sec.id); _ = await waitForGraphics(s, sec.id); await pause(500); await shot(w, "section-\(suffix)") }
            if let el = view(s, kind: .elevation, name: "South") { s.open(el.id); _ = await waitForGraphics(s, el.id); await pause(500); await shot(w, "elevation-\(suffix)") }
            router.run(.threeDView)
            await pause(2000)
            await shot(w, "3d-window-\(suffix)")
            if let host = s.canvases[s.activeViewID ?? ElementID(0)] as? Viewport3DHost, let img = host.viewport.snapshot(size: CGSize(width: 1400, height: 900)) { save(img, "3d-\(suffix)") }
            if suffix == "light", let host = s.canvases[s.activeViewID ?? ElementID(0)] as? Viewport3DHost {
                recordFrameTimes(host, label: "Courtyard House 3D")
            }
            s.open(plan.id)
            var dialogs: [(DialogKind, String)] = [(.exportIFC, "export-ifc-dialog"), (.dwgUnavailable, "dwg-unavailable"), (.modelHealth, "model-health"),
                                                   (.exportPDF, "export-pdf-dialog"), (.visibilityGraphics(plan.id), "visibility-graphics-dialog"),
                                                   (.materials, "materials-dialog"), (.keyboardShortcuts, "keyboard-shortcuts-dialog"), (.projectUnits, "project-units-dialog")]
            if let sched = s.model.schedules.first(where: { $0.name == "Door Schedule" }) { dialogs.append((.scheduleProperties(sched.id), "schedule-properties-dialog")) }
            if let wt = s.model.types(for: .walls).first(where: { $0.typeData?.assembly != nil }) { dialogs.append((.typeProperties(wt.id), "type-properties-dialog")) }
            dialogs.append((.componentLibrary([]), "component-library"))
            dialogs.append((.lineStyles, "line-styles-dialog"))
            for (kind, name) in dialogs {
                s.presented = kind
                await pause(800)
                if let sheetWin = w.attachedSheet { await shot(sheetWin, "\(name)-\(suffix)") } else { await shot(w, "\(name)-\(suffix)") }
                s.presented = nil
                await pause(600)
            }
            await familyEditorScreenshots(s, suffix) // W4-FAMED
            await furnitureScreenshots(suffix) // FM3: a new Furniture document
            await fm4Screenshots(suffix) // FM4: Furniture parts (bookcase, table, part tools)
            await fm5Screenshots(suffix) // FM5: bays, doors, drawers and hardware (base cabinet, Modify | Doors)
            await fm6Screenshots(suffix) // FM6: joints (sections at Fine, Joint tool markers, Joint Rules)
            await stairScreenshots(s, w, suffix: suffix) // STAIR: Create Stair, every kind on both levels, section, 3D
            await fm7Screenshots(suffix) // FM7: Part List, Hardware Schedule, Cost, Nesting, sheets F101–F104, fabrication dialogs
            await fm8Screenshots(suffix) // FM8: pieces in a project at Coarse/Fine, Load Furniture, Edit Family, the reload prompt
            await auditCaptures(s, w, plan: plan.id, suffix: suffix) // W4-AUDIT: every remaining dialog, workspaces × widths, Family Editor
            s.commandSearchVisible = true
            await pause(500)
            await shot(w, "command-search-\(suffix)")
            s.commandSearchVisible = false
            s.show("Couldn't place the door: the wall is too short for this door.", error: true)
            await pause(400)
            await shot(w, "error-toast-\(suffix)")
            s.document?.updateChangeCount(.changeCleared)
            closed.append(WeakState(value: s))
            s.document?.close()
            await pause(500)
        }
        NSApp.appearance = nil
        await step("20,000-element stress model in the app") {
            let model = await Task.detached(priority: .userInitiated) { CourtyardHouse.stress(count: 20_000) }.value
            let t0 = CFAbsoluteTimeGetCurrent()
            AppDelegate.shared?.openModel(model, name: "Stress 20k")
            guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state else { throw QAError("Stress model did not open") }
            guard let plan = s.model.views.first(where: { $0.view?.kind == .floorPlan }) else { throw QAError("No plan") }
            s.open(plan.id)
            _ = await waitForGraphics(s, plan.id, timeout: 60)
            let openToPlan = CFAbsoluteTimeGetCurrent() - t0
            metrics["stress plan build (s)"] = s.graphics.lastBuildSeconds[plan.id] ?? -1
            metrics["stress open to plan shown (s)"] = openToPlan
            var detail = String(format: "%d elements; plan shown %.2f s after open (build %.2f s)", s.model.count, openToPlan, s.graphics.lastBuildSeconds[plan.id] ?? -1)
            if let v3 = s.model.views.first(where: { $0.view?.kind == .threeD }) {
                s.open(v3.id)
                for _ in 0..<200 { if (s.canvases[v3.id] as? Viewport3DHost)?.viewport.statistics.triangles ?? 0 > 0 { break }; await pause(50) }
                if let host = s.canvases[v3.id] as? Viewport3DHost {
                    let r = recordFrameTimes(host, label: "Stress 20k 3D")
                    detail += String(format: "; 3D %d triangles, GPU median %.2f ms, CPU encode median %.2f ms", host.viewport.statistics.triangles, r.gpu, r.cpu)
                }
            }
            await pause(500)
            footprints["stress 20k open"] = footprintMB()
            detail += String(format: "; footprint %.0f MB", footprintMB())
            s.document?.updateChangeCount(.changeCleared)
            closed.append(WeakState(value: s))
            s.document?.close()
            await pause(500)
            return detail
        }
        await step("Closed documents are released") {
            // As after a real close, another window (the hub) becomes key; AppKit/SwiftUI drop their references to
            // the last key window's views then.
            AppDelegate.shared?.showHub(tab: .recent)
            await pause(2000)
            let alive = closed.compactMap(\.value)
            let holdingData = alive.filter { !$0.isTornDown || $0.model.count > 0 }
            footprints["after closing documents"] = footprintMB()
            try check(holdingData.isEmpty, "\(holdingData.count) closed document(s) still hold project data")
            return String(format: "%d closed; %d freed, %d empty shell(s) still referenced by framework caches; footprint %.0f MB",
                          closed.count, closed.count - alive.count, alive.count, footprintMB())
        }
    }
    struct WeakState { weak var value: DocumentState? }
    static var metrics: [String: Double] = [:]

    /// Renders 120 offscreen frames while orbiting and records median/p95 GPU and CPU-encode times (ms).
    @discardableResult
    static func recordFrameTimes(_ host: Viewport3DHost, label: String) -> (gpu: Double, cpu: Double) {
        let r = host.viewport.measureFrameTimes(frames: 120)
        func pct(_ v: [Double], _ p: Double) -> Double { let s = v.sorted(); return s.isEmpty ? -1 : s[min(s.count - 1, Int(Double(s.count) * p))] }
        metrics["\(label) GPU median (ms)"] = pct(r.gpu, 0.5); metrics["\(label) GPU p95 (ms)"] = pct(r.gpu, 0.95)
        metrics["\(label) CPU encode median (ms)"] = pct(r.cpu, 0.5); metrics["\(label) triangles"] = Double(host.viewport.statistics.triangles)
        return (pct(r.gpu, 0.5), pct(r.cpu, 0.5))
    }
    static var closed: [WeakState] = []

    // MARK: Capture

    /// Announces a capture point on stdout (an external watcher may screencapture the window), waits, then
    /// writes an in-process snapshot as a fallback.
    static func shot(_ w: NSWindow, _ name: String) async {
        w.displayIfNeeded()
        print("QA-CAPTURE \(w.windowNumber) \(name)")
        fflush(stdout)
        await pause(1300)
        capture(w, name + "-inprocess")
    }

    static func capture(_ w: NSWindow, _ name: String) {
        guard let view = w.contentView?.superview ?? w.contentView else { return }
        let rect = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        // Metal canvases don't appear in cacheDisplay: paint each canvas's composited frame over its place in the window.
        if let g = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            var canvases: [Canvas2DView] = []
            func collect(_ v: NSView) { if let c = v as? Canvas2DView, !c.isHiddenOrHasHiddenAncestor { canvases.append(c) } else { v.subviews.forEach(collect) } }
            collect(view)
            var docks: [NSRect] = [] // W4-SHELL: the docks float over the canvas; keep them visible in the composite
            func collectDocks(_ v: NSView) { if let d = v as? GlassShieldView, !d.isHiddenOrHasHiddenAncestor { docks.append(d.convert(d.bounds, to: view)) } else { v.subviews.forEach(collectDocks) } } // W4-WIRE: every glass shield
            collectDocks(view)
            for c in canvases {
                guard let snap = c.renderedSnapshot() else { continue }
                let r = c.convert(c.bounds, to: view)
                NSGraphicsContext.saveGraphicsState()
                let clip = NSBezierPath(rect: r)
                clip.windingRule = .evenOdd
                for d in docks where d.intersects(r) { clip.appendRect(d.intersection(r)) }
                clip.addClip()
                snap.draw(in: r)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outDir.appendingPathComponent("screenshots/\(name).png"))
        }
    }

    static func save(_ img: CGImage, _ name: String) {
        let rep = NSBitmapImageRep(cgImage: img)
        try? FileManager.default.createDirectory(at: outDir.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: outDir.appendingPathComponent("screenshots/\(name).png")) }
    }

    /// Physical footprint of the process (Activity Monitor's "Memory"), in MB.
    static var footprints: [String: Double] = [:]
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func writeResults() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Summary: Codable { var passed: Int; var failed: Int; var steps: [StepResult]; var timings: [String: Double]; var footprintMB: [String: Double]; var metrics: [String: Double] }
        var timings: [String: Double] = [:]
        for t in DiagnosticsLog.shared.recentTimings { timings[t.name] = max(timings[t.name] ?? 0, t.seconds) }
        footprints["at exit"] = footprintMB()
        let summary = Summary(passed: results.filter(\.passed).count, failed: results.filter { !$0.passed }.count, steps: results, timings: timings,
                              footprintMB: footprints, metrics: metrics)
        try? enc.encode(summary).write(to: outDir.appendingPathComponent("results.json"))
    }
}
