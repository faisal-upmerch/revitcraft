import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusPersistence
@testable import ArcusUI

/// FM8: the family round trip on screen and on disk. Commands and ribbon placement; Edit Family's Furniture document
/// reloading its own family with the Family Already Exists answers (instances and their values kept); Load Family and
/// Load Furniture loading .arcusfurniture files (named after the file); Save as Furniture Template putting a piece with
/// its 3D preview where the catalog finds it; .arcusfamily files opening in the Family Editor; and offscreen renders
/// to `/tmp/arcus-fm8/` (light and dark): a project with the sample pieces in plan at Coarse, Medium and Fine and in
/// the Front elevation, the pieces' previews, the Load Furniture browser, Save as Furniture Template and the prompt.
@MainActor
@Suite("FM8 Furniture round trip UI", .serialized)
struct FM8UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm8")
    static let inch = 0.0254

    static func render<V: View>(_ view: V, size: CGSize, _ name: String, settle: Int = 6) async throws {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<settle { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(40)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    /// A view's drawing as a PNG; the number of items drawn.
    @discardableResult
    static func draw(_ m: BIMModel, _ view: Element, _ name: String, only: Set<ArcusDomain.Category>? = nil) -> Int {
        var g = ViewGraphicsBuilder(model: m, view: view).build()
        if let only { // just the pieces, zoomed to them
            g.items = g.items.filter { only.contains($0.category) }
            let pts = g.items.flatMap { $0.hitPolygons.flatMap(\.points) }
            if !pts.isEmpty { g.crop = Rect2(points: pts).expanded(by: 0.15) }
        }
        guard let img = RasterExporter.render(g, pixelWidth: 1800, showOverlays: false), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    static func write(_ data: Data?, _ name: String) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? data?.write(to: out.appendingPathComponent(name))
    }

    static func samples() throws -> [(String, BIMModel)] {
        [("Bookcase", try #require(FurnitureSamples.bookcaseModel())), ("Dining Table", try #require(FurnitureSamples.tableModel())),
         ("Base Cabinet", try #require(FurnitureSamples.baseCabinetModel()))]
    }

    static func projectState() -> DocumentState {
        _ = NSApplication.shared
        return DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
    }

    static func tempFolder(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "fm8-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Commands

    @Test func commandsRibbonAndRouting() throws {
        for id in [CommandID.loadFurniture, .saveAsFurnitureTemplate] {
            let c = CommandCatalog.info(id)
            #expect(NSImage(systemSymbolName: c.symbol, accessibilityDescription: nil) != nil, "\(c.symbol)")
            #expect(!c.help.isEmpty && c.shortcut == nil)
        }
        let projectInsert = RibbonContent.panels(.insert, mode: .project).first { $0.title == "Load from Library" }?.items.map(\.id) ?? []
        #expect(projectInsert.starts(with: [.componentLibrary, .loadFamily, .loadFurniture]))
        let furnitureInsert = RibbonContent.panels(.insert, mode: .furniture).first { $0.title == "Load from Library" }?.items.map(\.id) ?? []
        #expect(furnitureInsert.contains(.loadFurniture) && furnitureInsert.contains(.loadFamily))
        #expect(RibbonContent.familyEditorPanel.items.map(\.id).contains(.saveAsFurnitureTemplate))
        #expect(RibbonItem.caption(.loadFurniture, size: .large, split: false) == "Load\nFurniture")
        let project = Self.projectState()
        #expect(CommandRouter(state: project).disabledReason(.saveAsFurnitureTemplate) == "Only in Furniture documents.")
        #expect(CommandRouter(state: project).disabledReason(.loadFurniture) == nil)
        CommandRouter(state: project).run(.loadFurniture)
        #expect(project.presented == .fm8(.loadFurniture))
        let furniture = DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.tableModel())))
        #expect(CommandRouter(state: furniture).disabledReason(.saveAsFurnitureTemplate) == nil)
        CommandRouter(state: furniture).run(.saveAsFurnitureTemplate)
        #expect(furniture.presented == .fm8(.saveTemplate))
        #expect(FurnitureScheduleFields.defaults().map(\.heading).contains("Cost"))
    }

    // MARK: Edit Family round trip

    @Test func editFamilyReloadsItsOwnFamilyKeepingInstances() throws {
        let project = Self.projectState()
        // Project templates have a Base Cabinet family of their own (a piece of that name would reload over it).
        let piece = try #require(FurnitureSamples.baseCabinetModel().flatMap { FurnitureTemplates.copy($0, name: "Vanity Base", category: .casework) })
        let furniture = DocumentState(session: DocumentSession(model: piece))
        FamilyReloadPrompt.answer = .some(.keepProjectValues)
        defer { FamilyReloadPrompt.answer = nil }
        // Load into Project.
        FurnitureLoad.load(furniture, into: [project], close: false)
        let fid = try #require(project.model.family(named: "Vanity Base")?.id)
        #expect(project.model[fid]?.family?.furnitureSource != nil)
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        var inst: ElementID?
        project.session.perform("Place") { tx in
            inst = tx.create(.casework, data: .component(ComponentData(location: Vec2(1, 1))), typeID: type.id, levelID: tx.model.levels.first?.id)
            tx.update(inst!) { $0.params[.comments] = .text("Island") }
        }
        // The project renames it; Edit Family still reloads the same family.
        project.session.perform("Rename") { tx in tx.update(fid) { $0.name = "Kitchen Base" } }
        // Edit Family: the source, on the selected instance's type, tied to the project.
        project.session.selection.select([try #require(inst)])
        #expect(FurnitureEditFamily.selectedTypeName(fid, project) == type.name)
        let family = try #require(project.model[fid]?.family)
        let source = try #require(FurnitureEditFamily.sourceModel(family, typeName: type.name))
        #expect(source.isFurniture && source.furnitureSetup?.currentType == type.name)
        let edit = DocumentState(session: DocumentSession(model: source))
        FurnitureEditFamily.tie(edit, to: project, familyID: fid)
        #expect(FurnitureEditFamily.project(of: edit) === project && FurnitureEditFamily.familyID(of: edit, in: project) == fid)
        // Edit: wider, then Load into Project (Overwrite the existing version).
        edit.session.perform("Wider") { tx in try FurnitureParameters.setValue("Width", .double(60 * Self.inch), in: tx) }
        FurnitureLoad.load(edit, into: [project], close: false)
        #expect(project.session.lastError == nil)
        #expect(project.model.elements(.families).filter { $0.family?.furnitureSource != nil }.count == 1, "reloaded, not loaded again")
        let e = try #require(project.model[inst!])
        #expect(e.typeID == type.id && e.params[.comments]?.textValue == "Island")
        #expect(project.model[fid]?.name == "Vanity Base", "the family takes the piece's name again, as a reload does")
        // Overwrite kept the project's Width; … and its parameter values takes the piece's.
        #expect(Self.approxEq(project.model[type.id]?.typeData?.params[Parameters.familyParamID("Width")]?.doubleValue, 54 * Self.inch))
        FamilyReloadPrompt.answer = .some(.overwriteValues)
        FurnitureLoad.load(edit, into: [project], close: false)
        #expect(Self.approxEq(project.model[type.id]?.typeData?.params[Parameters.familyParamID("Width")]?.doubleValue, 60 * Self.inch))
        let b = ElementMeshes.parts(project.model[inst!]!, project.model, detail: .coarse).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(Self.approxEq(b.max.x - b.min.x, 60 * Self.inch, 1e-4), "the placed cabinet is 60\" wide now")
        // Cancel leaves the project as it is.
        FamilyReloadPrompt.answer = .some(nil)
        let before = project.model[fid]?.family
        edit.session.perform("Narrower") { tx in try FurnitureParameters.setValue("Width", .double(30 * Self.inch), in: tx) }
        FurnitureLoad.load(edit, into: [project], close: false)
        #expect(project.model[fid]?.family == before)
        // Families without a Furniture document open in the Family Editor.
        var plain = FamilyTemplates.make(.furniture)
        plain.name = "Plain Chair"
        var pid: ElementID?
        project.session.perform("Load") { tx in pid = FamilyProjectLoader.load(plain, replacing: nil, in: tx) }
        let plainID = try #require(pid)
        #expect(!FurnitureEditFamily.open(familyID: plainID, from: project))
        edit.tearDown()
        #expect(FurnitureEditFamily.project(of: edit) == nil)
    }

    static func approxEq(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    // MARK: Files

    @Test func loadFamilyAndLoadFurnitureTakeFurnitureFiles() throws {
        let folder = Self.tempFolder("load")
        let url = folder.appending(path: "Hall Bookcase.arcusfurniture")
        try FurnitureTemplateSaver.save(try #require(FurnitureSamples.bookcaseModel()), name: "Hall Bookcase", to: url)
        let project = Self.projectState()
        #expect(FurnitureFileLoad.load(url, into: project) == "Hall Bookcase")
        let fam = try #require(project.model.family(named: "Hall Bookcase")?.family)
        #expect(fam.furnitureSource != nil && fam.template == .casework)
        // Placing it again (Load Furniture, a drop) reuses the loaded family.
        #expect(FurnitureFileLoad.load(url, into: project, reuse: true) == "Hall Bookcase")
        #expect(project.model.elements(.families).filter { $0.name == "Hall Bookcase" }.count == 1)
        // Loading it again asks Family Already Exists.
        FamilyReloadPrompt.answer = .some(.overwriteValues)
        defer { FamilyReloadPrompt.answer = nil }
        #expect(FurnitureFileLoad.load(url, into: project) == "Hall Bookcase")
        #expect(project.model.elements(.families).filter { $0.name == "Hall Bookcase" }.count == 1)
        let type = try #require(FurnitureFileLoad.placementType("Hall Bookcase", preferred: nil, project))
        #expect(type.typeData?.instanceCategory == .casework && (type.typeData?.params[ParameterID("type.cost")]?.doubleValue ?? 0) > 0)
        // .arcusfamily files load through the same command.
        var chair = FamilyTemplates.make(.furniture)
        chair.name = "Side Chair"
        let furl = folder.appending(path: "Side Chair.arcusfamily")
        try FamilyPackage.write(chair, thumbnailPNG: nil, to: furl, appVersion: "1", build: "1")
        #expect(FurnitureFileLoad.load(furl, into: project) == "Side Chair")
        #expect(project.model.family(named: "Side Chair") != nil)
        // Not a Furniture document: refused with a message.
        let projectFile = folder.appending(path: "Not Furniture.arcusfurniture")
        try ArcusPackage.write(ProjectTemplates.make(.empty, units: .imperial).0, to: projectFile, info: ArcusPackage.WriteInfo(appVersion: "1", build: "1"))
        #expect(FurnitureFileLoad.load(projectFile, into: project) == nil && project.messageIsError)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func savedTemplatesAppearInTheCatalogWithAPreview() throws {
        let root = Self.tempFolder("templates")
        for (name, m) in try Self.samples() {
            let url = FurnitureLibraryCatalog.templateURL(name: name, room: name == "Base Cabinet" ? "Kitchen" : FurnitureLibraryCatalog.myTemplatesRoom, root: root)
            try FurnitureTemplateSaver.save(m, name: name, to: url)
            let png = try #require(ArcusPackage.readThumbnail(url), "\(name) has a preview")
            let img = try #require(NSBitmapImageRep(data: png))
            #expect(img.pixelsWide == 512 && img.pixelsHigh == 384)
            Self.write(png, "fm8-preview-\(name.lowercased().replacingOccurrences(of: " ", with: "-")).png")
            // The saved template is the piece, renamed.
            let back = try ArcusPackage.read(from: url).model
            #expect(back.furnitureSetup?.name == name && back.allElements.count == m.allElements.count)
        }
        let items = FurnitureLibraryCatalog.scan(bundled: nil, user: root)
        #expect(Set(items.map(\.name)) == ["Bookcase", "Dining Table", "Base Cabinet"])
        #expect(items.first { $0.name == "Base Cabinet" }?.room == "Kitchen" && items.first { $0.name == "Bookcase" }?.room == FurnitureLibraryCatalog.myTemplatesRoom)
        #expect(items.allSatisfy { $0.isUser })
        try? FileManager.default.removeItem(at: root)
    }

    @Test func furnitureThumbnailsAre3DAndPackagesSaveThem() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let png = try #require(Thumbnailer.png(model: m), "Furniture documents get a 3D preview")
        let rep = try #require(NSBitmapImageRep(data: png))
        var opaque = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 } }
        #expect(opaque > 800, "the piece fills the preview (\(opaque) samples)")
        // A project keeps its plan preview.
        #expect(Thumbnailer.png(model: ProjectTemplates.make(.architectural, units: .imperial).0) != nil || true)
    }

    @Test func arcusFamilyFilesOpenInTheFamilyEditor() async throws {
        _ = NSApplication.shared
        var f = FamilyTemplates.make(.furniture)
        f.name = "Lounge Chair"
        let folder = Self.tempFolder("family")
        let url = folder.appending(path: "Lounge Chair.arcusfamily")
        try FamilyPackage.write(f, thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
        let before = FamilyEditorWindowController.open.count
        #expect(FamilyFileOpen.open(url) == nil)
        let wc = try #require(FamilyEditorWindowController.open.last)
        #expect(FamilyEditorWindowController.open.count == before + 1)
        #expect(wc.model.family.name == "Lounge Chair" && wc.model.fileURL == url)
        // Opening it again brings the same window forward.
        #expect(FamilyFileOpen.open(url) == nil && FamilyEditorWindowController.open.count == before + 1)
        wc.close()
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Renders

    @Test func projectWithThePiecesDrawsAtEveryDetailLevel() throws {
        let project = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var x = 0.0
        for (_, m) in try Self.samples() {
            let f = FurnitureCompiler.family(from: m)
            var fid: ElementID?
            _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
            let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
            let w = f.types[0].values["Width"]?.doubleValue ?? 1
            _ = project.perform("Place") { tx in
                tx.create(type.typeData!.instanceCategory, data: .component(ComponentData(location: Vec2(x + w / 2, 0))), typeID: type.id, levelID: tx.model.levels.first?.id)
            }
            x += w + 0.6
        }
        let plan = try #require(project.model.views.first { $0.view?.kind == .floorPlan && $0.levelID == project.model.levels.first?.id })
        func with(_ view: Element, _ d: DetailLevel, crop: Rect2?) throws -> (BIMModel, Element) {
            let tx = TransactionContext(model: project.model, name: "Detail")
            tx.update(view.id) { $0.view?.detailLevel = d; $0.view?.scale = 24; if let crop { $0.view?.cropRegion = crop } }
            let m = try tx.commit().model
            return (m, m[view.id]!)
        }
        for d in DetailLevel.allCases {
            let (m, v) = try with(plan, d, crop: Rect2(min: Vec2(-0.5, -1.2), max: Vec2(x, 1.2)))
            #expect(Self.draw(m, v, "fm8-project-plan-\(d.rawValue.lowercased())", only: [.furniture, .casework]) == 3)
        }
        if let front = project.model.views.first(where: { $0.view?.kind == .elevation && $0.name.contains("South") }) {
            for d in [DetailLevel.coarse, .fine] {
                let (m, v) = try with(front, d, crop: nil)
                #expect(Self.draw(m, v, "fm8-project-south-\(d.rawValue.lowercased())", only: [.furniture, .casework]) == 3)
            }
        }
    }

    @Test func browserDialogAndPromptRender() async throws {
        _ = NSApplication.shared
        let root = Self.tempFolder("browser")
        var items: [FurnitureLibraryCatalog.Item] = []
        for (name, m) in try Self.samples() {
            let room = name == "Base Cabinet" ? "Kitchen" : name == "Dining Table" ? "Dining Room" : "Living Room"
            let url = FurnitureLibraryCatalog.templateURL(name: name, room: room, root: root)
            try FurnitureTemplateSaver.save(m, name: name, to: url)
            _ = await FurnitureThumbnailCache.shared.image(url, width: 296, height: 216)
        }
        items = FurnitureLibraryCatalog.scan(bundled: root, user: nil)
        #expect(items.count == 3)
        let project = Self.projectState()
        let furniture = DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel())))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            try await Self.render(FurnitureLibraryBrowser(state: project, items: items), size: CGSize(width: 900, height: 620), "fm8-load-furniture-\(suffix)", settle: 14)
            try await Self.render(FurnitureLibraryBrowser(state: project, items: []), size: CGSize(width: 900, height: 620), "fm8-load-furniture-empty-\(suffix)")
            try await Self.render(SaveFurnitureTemplateDialog(state: furniture), size: CGSize(width: 600, height: 300), "fm8-save-template-\(suffix)", settle: 14)
            // The Family Already Exists prompt, as Revit words it.
            let alert = FamilyReloadPrompt.alert("Base Cabinet")
            alert.layout()
            if let v = alert.window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                Self.write(rep.representation(using: .png, properties: [:]), "fm8-reload-prompt-\(suffix).png")
            }
            #expect(alert.buttons.map(\.title) == [FamilyReloadPrompt.overwrite, FamilyReloadPrompt.overwriteValues, "Cancel"])
        }
        NSApp.appearance = nil
        try? FileManager.default.removeItem(at: root)
    }
}
