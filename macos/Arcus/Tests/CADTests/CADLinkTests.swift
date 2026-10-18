import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

@Suite("CAD links and native conversion")
struct CADLinkTests {
    struct Placed {
        var model: BIMModel
        var ids: ProjectTemplates.Ids
        var link: ElementID
        var report: CADImportReport
    }

    func place(_ url: URL, _ configure: (inout CADImportOptions) -> Void = { _ in }, model: BIMModel? = nil) throws -> Placed {
        let (m0, ids) = templateModel()
        var o = CADImportOptions()
        o.isLink = true
        configure(&o)
        let tx = TransactionContext(model: model ?? m0, name: "Link CAD")
        let (id, report) = try CADLinkService.place(url: url, bookmark: Data([1, 2, 3]), options: o, projectSurveyOrigin: .zero, in: tx,
                                                    progress: { _ in }, isCancelled: { false })
        let r = try tx.commit()
        return Placed(model: r.model, ids: ids, link: id, report: report)
    }

    @Test func placeCreatesLinkElementWithContent() throws {
        let p = try place(Fx.url("ac1015_imperial_layouts.dxf"))
        let e = try #require(p.model[p.link])
        #expect(e.category == .importedCAD)
        let ld = try #require(e.link)
        #expect(ld.format == .dxf && ld.isLinked && ld.isLoaded)
        #expect(ld.bookmark == Data([1, 2, 3]))
        #expect(ld.sourceName == "ac1015_imperial_layouts.dxf")
        #expect(ld.sourcePath == Fx.url("ac1015_imperial_layouts.dxf").path)
        #expect(p.model.referenceDrawings[ld.contentKey] != nil)
        #expect(Set(ld.layers.map(\.name)).isSuperset(of: ["A-WALL", "A-ANNO"]))
        #expect(ld.lastLoaded != nil && ld.sourceModified != nil)
        #expect(p.report.fileName == "ac1015_imperial_layouts.dxf")
        #expect(p.report.format == "DXF")
        #expect(p.report.peakMemoryBytes > 0)
        #expect(p.report.missingImages == ["photos\\site.jpg"])
        #expect(p.report.elapsed > 0)
    }

    @Test func placeOnLevelAndCurrentViewOnly() throws {
        let (m0, ids) = templateModel()
        let level = ids.levels[0]
        let view = try #require(ids.planViews[level])
        let tx = TransactionContext(model: m0, name: "Import")
        var o = CADImportOptions()
        o.levelID = level
        o.currentViewOnly = view
        let (id, _) = try CADLinkService.place(url: Fx.url("r12_plan.dxf"), bookmark: nil, options: o, projectSurveyOrigin: .zero, in: tx,
                                               progress: { _ in }, isCancelled: { false })
        let m = try tx.commit().model
        #expect(m[id]?.levelID == level)
        #expect(m[id]?.ownerViewID == view)
        #expect(m[id]?.link?.isLinked == false)
        // The plan view displays it.
        let g = ViewGraphicsBuilder(model: m, view: m[view]!).build()
        #expect(g.items.contains { $0.elementID == id && !$0.primitives.isEmpty })
    }

    @Test func placeRejectsMissingLevel() throws {
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Import")
        var o = CADImportOptions()
        o.levelID = ElementID(999_999)
        #expect(throws: CADError.self) {
            try CADLinkService.place(url: Fx.url("r12_plan.dxf"), bookmark: nil, options: o, projectSurveyOrigin: .zero, in: tx,
                                     progress: { _ in }, isCancelled: { false })
        }
    }

    @Test func sharedCoordinatesUseProjectSurveyPoint() throws {
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Import")
        var o = CADImportOptions()
        o.positioning = .sharedCoordinates(easting: 512300, northing: 4234500, rotation: 0)
        let (id, _) = try CADLinkService.place(url: Fx.url("ac1032_unicode_survey.dxf"), bookmark: nil, options: o, projectSurveyOrigin: Vec2(100, 50),
                                               in: tx, progress: { _ in }, isCancelled: { false })
        let m = try tx.commit().model
        let ld = try #require(m[id]?.link)
        let d = try #require(m.referenceDrawings[ld.contentKey])
        guard case .line(let s, _)? = d.entities.first(where: { $0.style.handle == "A1" }) else { Issue.record("line missing"); return }
        #expect(approx(ld.placement.apply(s.start), Vec2(145.678, 117.891), 1e-9))
    }

    @Test func reloadPreservesLayerStatesPlacementAndKeepsOldContent() throws {
        let dir = try Fx.tempCopy(["ac1015_imperial_layouts.dxf"])
        let url = dir.appendingPathComponent("ac1015_imperial_layouts.dxf")
        let p = try place(url)
        // User hides A-WALL and halftones A-ANNO, and moves the link.
        let tx1 = TransactionContext(model: p.model, name: "Layers")
        tx1.update(p.link) { e in
            guard var ld = e.link else { return }
            ld.layers = ld.layers.map { l in LinkLayerState(name: l.name, visible: l.name != "A-WALL", halftone: l.name == "A-ANNO") }
            ld.placement = .translation(Vec2(5, 5)) * ld.placement
            e.link = ld
        }
        let m1 = try tx1.commit().model
        let before = try #require(m1[p.link]?.link)
        // The source changes: a new layer and entity appear.
        var text = try String(contentsOf: url, encoding: .utf8)
        let marker = "  0\r\nENDSEC\r\n  0\r\nSECTION\r\n  2\r\nOBJECTS"
        #expect(text.contains(marker))
        text = text.replacingOccurrences(of: marker, with: "  0\r\nLINE\r\n  5\r\n200\r\n  8\r\nNEW-LAYER\r\n 10\r\n0\r\n 20\r\n0\r\n 11\r\n10\r\n 21\r\n10\r\n" + marker)
        try text.write(to: url, atomically: true, encoding: .utf8)

        let tx2 = TransactionContext(model: m1, name: "Reload")
        let report = try CADLinkService.reload(linkElementID: p.link, from: url, in: tx2, progress: { _ in }, isCancelled: { false })
        let m2 = try tx2.commit().model
        let after = try #require(m2[p.link]?.link)
        #expect(after.contentKey != before.contentKey)
        #expect(m2.referenceDrawings[before.contentKey] != nil) // old content kept for undo
        #expect(after.placement == before.placement)
        #expect(after.layers.first { $0.name == "A-WALL" }?.visible == false)
        #expect(after.layers.first { $0.name == "A-ANNO" }?.halftone == true)
        #expect(after.layers.first { $0.name == "NEW-LAYER" }?.visible == true)
        #expect(report.entityCountsByType["LINE"] == 3) // model line, new line, line in the "Sheet A" layout
        // Geometry unchanged by reload stays in the same place.
        let d1 = m1.referenceDrawings[before.contentKey]!, d2 = m2.referenceDrawings[after.contentKey]!
        func wallEnd(_ d: ReferenceDrawing) -> Vec2? {
            if case .line(let s, _)? = d.entities.first(where: { $0.style.handle == "101" }) { return s.end }
            return nil
        }
        #expect(approx(before.placement.apply(wallEnd(d1)!), after.placement.apply(wallEnd(d2)!), 1e-12))
    }

    @Test func reloadOfImportIsRejected() throws {
        let p = try place(Fx.url("r12_plan.dxf")) { $0.isLink = false }
        let tx = TransactionContext(model: p.model, name: "Reload")
        #expect(throws: CADError.self) {
            try CADLinkService.reload(linkElementID: p.link, from: Fx.url("r12_plan.dxf"), in: tx, progress: { _ in }, isCancelled: { false })
        }
    }

    @Test func unloadAndRemove() throws {
        let p = try place(Fx.url("r12_plan.dxf"))
        let tx = TransactionContext(model: p.model, name: "Unload")
        CADLinkService.unload(p.link, in: tx)
        let m1 = try tx.commit().model
        #expect(m1[p.link]?.link?.isLoaded == false)
        let key = m1[p.link]!.link!.contentKey
        let tx2 = TransactionContext(model: m1, name: "Remove")
        CADLinkService.remove(p.link, in: tx2)
        let r = try tx2.commit()
        #expect(r.model[p.link] == nil)
        #expect(r.model.referenceDrawings[key] != nil)
        // Undo restores it.
        let undone = r.model.applying(r.record.inverse)
        #expect(undone[p.link]?.link?.contentKey == key)
    }

    @Test func placeIsOneUndoableStep() throws {
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Link")
        let (id, _) = try CADLinkService.place(url: Fx.url("r12_plan.dxf"), bookmark: nil, options: CADImportOptions(), projectSurveyOrigin: .zero,
                                               in: tx, progress: { _ in }, isCancelled: { false })
        let r = try tx.commit()
        #expect(r.record.changes.count == 1)
        #expect(r.record.addedDrawings.count == 1)
        #expect(r.model.applying(r.record.inverse)[id] == nil)
    }

    @Test func cancellationStopsPlacement() throws {
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Link")
        #expect(throws: CancellationError.self) {
            try CADLinkService.place(url: Fx.url("ac1027_blocks_annotation.dxf"), bookmark: nil, options: CADImportOptions(), projectSurveyOrigin: .zero,
                                     in: tx, progress: { _ in }, isCancelled: { true })
        }
        #expect(!tx.hasChanges)
    }

    @Test func prepareRunsOffTheMainActor() async throws {
        let prepared = try await CADLinkService.prepare(url: Fx.url("ac1027_blocks_annotation.dxf"), bookmark: nil, options: CADImportOptions(),
                                                        projectSurveyOrigin: .zero)
        #expect(!prepared.drawing.entities.isEmpty)
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Link")
        let (id, report) = try CADLinkService.place(prepared: prepared, in: tx)
        let m = try tx.commit().model
        #expect(m[id]?.link?.contentKey == prepared.drawing.contentKey)
        #expect(report.fileName == "ac1027_blocks_annotation.dxf")
    }

    @Test func dwgWithoutSDKReportsTruthfulReason() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-dwg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("plan.dwg")
        try Data("AC1032 not really a drawing".utf8).write(to: url)
        let (m0, _) = templateModel()
        let tx = TransactionContext(model: m0, name: "Link")
        do {
            _ = try CADLinkService.place(url: url, bookmark: nil, options: CADImportOptions(), projectSurveyOrigin: .zero, in: tx,
                                         progress: { _ in }, isCancelled: { false })
            Issue.record("expected an error")
        } catch let e as CADError {
            #expect(e.message.contains("ODA Drawings SDK"))
        }
    }

    @Test func sourceFileIsNeverModified() throws {
        let url = Fx.url("ac1027_blocks_annotation.dxf")
        let bytes = try Data(contentsOf: url)
        let mod = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let p = try place(url)
        let view = p.ids.planViews[p.ids.levels[0]]!
        let tx = TransactionContext(model: p.model, name: "Convert")
        _ = try CADConverter.convert(linkElement: p.link, layers: nil, target: .detailLines(viewID: view), in: tx)
        _ = try tx.commit()
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == mod)
    }

    // MARK: Native conversion

    @Test func convertToDetailLinesKeepsArcs() throws {
        let p = try place(Fx.url("ac1015_imperial_layouts.dxf"))
        let view = p.ids.planViews[p.ids.levels[0]]!
        let tx = TransactionContext(model: p.model, name: "Convert")
        let n = try CADConverter.convert(linkElement: p.link, layers: ["A-WALL"], target: .detailLines(viewID: view), in: tx)
        let m = try tx.commit().model
        let lines = m.elements(.detailLines)
        #expect(n == lines.count)
        #expect(n == 6) // 4 room-outline segments (one arc) + dashed line + arc
        #expect(lines.allSatisfy { $0.ownerViewID == view && $0.source?.format == "DXF" && $0.source?.layer == "A-WALL" })
        let arcs = lines.compactMap { $0.modelLine?.curve.asArc }
        #expect(arcs.count == 2)
        let outlineArc = try #require(lines.first { $0.source?.originalID == "100" && $0.modelLine?.curve.asArc != nil }?.modelLine?.curve.asArc)
        #expect(approx(outlineArc.radius, 48 * 0.0254, 1e-9))
        // Converted geometry sits where the link displays it.
        let wall = try #require(lines.first { $0.source?.originalID == "101" }?.modelLine?.curve)
        #expect(approx(wall.end, Vec2(120 * 0.0254, 60 * 0.0254), 1e-9))
    }

    @Test func convertToModelLinesOnLevel() throws {
        let p = try place(Fx.url("r12_plan.dxf"))
        let level = p.ids.levels[0]
        let tx = TransactionContext(model: p.model, name: "Convert")
        let n = try CADConverter.convert(linkElement: p.link, layers: ["WALLS"], target: .modelLines(levelID: level, category: .roomSeparationLines), in: tx)
        let m = try tx.commit().model
        let lines = m.elements(.roomSeparationLines)
        #expect(n == lines.count && n > 0)
        #expect(lines.allSatisfy { $0.levelID == level && $0.ownerViewID == nil })
        let tx2 = TransactionContext(model: m, name: "Convert")
        #expect(throws: CADError.self) {
            try CADConverter.convert(linkElement: p.link, layers: nil, target: .modelLines(levelID: level, category: .walls), in: tx2)
        }
    }

    @Test func convertTextsToTextNotes() throws {
        let p = try place(Fx.url("ac1015_imperial_layouts.dxf"))
        let view = p.ids.planViews[p.ids.levels[0]]!
        let tx = TransactionContext(model: p.model, name: "Convert")
        let n = try CADConverter.convert(linkElement: p.link, layers: nil, target: .textNotes(viewID: view), in: tx)
        let m = try tx.commit().model
        let notes = m.elements(.textNotes)
        #expect(n == notes.count && n == 1)
        #expect(notes.first?.textNote?.text == "LIVING")
        #expect(notes.first?.ownerViewID == view)
        #expect(notes.first?.typeID != nil)
    }

    @Test func convertClosedBoundariesAndHatchesToFilledRegions() throws {
        let p = try place(Fx.url("ac1027_blocks_annotation.dxf"))
        let view = p.ids.planViews[p.ids.levels[0]]!
        let tx = TransactionContext(model: p.model, name: "Convert")
        let n = try CADConverter.convert(linkElement: p.link, layers: ["A-HATCH"], target: .filledRegions(viewID: view), in: tx)
        let m = try tx.commit().model
        let regions = m.elements(.filledRegions)
        #expect(n == 2 && regions.count == 2)
        for r in regions {
            let fr = try #require(r.filledRegion)
            guard case .success(let prof) = fr.boundary.profile() else { Issue.record("invalid region"); continue }
            #expect(prof.outer.area > 1)
        }
        // A closed bulged polyline becomes a region that keeps its arc.
        let q = try place(Fx.url("ac1015_imperial_layouts.dxf"))
        let v2 = q.ids.planViews[q.ids.levels[0]]!
        let tx2 = TransactionContext(model: q.model, name: "Convert")
        _ = try CADConverter.convert(linkElement: q.link, layers: ["A-WALL"], target: .filledRegions(viewID: v2), in: tx2)
        let m2 = try tx2.commit().model
        let outline = try #require(m2.elements(.filledRegions).first { $0.source?.originalID == "100" })
        #expect(outline.filledRegion!.boundary.allCurves.contains { $0.asArc != nil })
    }

    @Test func convertRejectsNonLinksAndMissingViews() throws {
        let p = try place(Fx.url("r12_plan.dxf"))
        let tx = TransactionContext(model: p.model, name: "Convert")
        #expect(throws: CADError.self) {
            try CADConverter.convert(linkElement: p.ids.levels[0], layers: nil, target: .detailLines(viewID: p.ids.levels[0]), in: tx)
        }
        #expect(throws: CADError.self) {
            try CADConverter.convert(linkElement: p.link, layers: nil, target: .detailLines(viewID: ElementID(987_654)), in: tx)
        }
    }

    // MARK: Dependencies and xrefs

    @Test func dependencyScanFlagsFoundMissingAndOutside() throws {
        let parent = Fx.url("xref_project/parent.dxf")
        let doc = try DXFReader.read(try Data(contentsOf: parent), fileName: "parent.dxf")
        let deps = CADDependencies.scan(doc, parentURL: parent)
        func status(_ n: String) -> CADDependency.Status? { deps.first { $0.name == n }?.status }
        #expect(status("SITE") == .found)
        #expect(deps.first { $0.name == "SITE" }?.resolvedURL?.lastPathComponent == "site_plan.dxf")
        #expect(status("SURVEY") == .missing)
        #expect(status("EVIL") == .outsideParentFolder)
        #expect(status("ABS") == .outsideParentFolder)
        #expect(deps.first { $0.name == "EVIL" }?.resolvedURL == nil)
        #expect(status("aerial.png") == .found)
        #expect(status("missing.jpg") == .missing)
        #expect(deps.first { $0.kind == .font }?.name == "romans.shx")
        #expect(deps.first { $0.kind == .font }?.status == .missing)
    }

    @Test func userResolvedDependenciesOverrideTheScan() throws {
        let parent = Fx.url("xref_project/parent.dxf")
        let doc = try DXFReader.read(try Data(contentsOf: parent), fileName: "parent.dxf")
        let chosen = Fx.url("xref_project/xrefs/site_plan.dxf")
        let deps = CADDependencies.scan(doc, parentURL: parent, userResolved: ["EVIL": chosen])
        #expect(deps.first { $0.name == "EVIL" }?.status == .found)
        #expect(deps.first { $0.name == "EVIL" }?.resolvedURL == chosen)
    }

    @Test func pathResolutionNeverEscapesTheFolder() {
        let folder = Fx.url("xref_project")
        #expect(CADDependencies.resolve("../r12_plan.dxf", in: folder).status == .outsideParentFolder)
        #expect(CADDependencies.resolve("xrefs/../../r12_plan.dxf", in: folder).status == .outsideParentFolder)
        #expect(CADDependencies.resolve("C:\\Projects\\site.dxf", in: folder).status == .outsideParentFolder)
        #expect(CADDependencies.resolve("\\\\server\\share\\a.dxf", in: folder).status == .outsideParentFolder)
        #expect(CADDependencies.resolve("xrefs/./site_plan.dxf", in: folder).status == .found)
        #expect(CADDependencies.resolve(folder.appendingPathComponent("parent.dxf").path, in: folder).status == .found)
        #expect(CADDependencies.resolve("", in: folder).status == .missing)
    }

    @Test func symlinksPointingOutsideTheFolderAreNotFollowed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-link-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-outside-\(UUID().uuidString).dxf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("0\nEOF\n".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("linked.dxf"), withDestinationURL: outside)
        try Data("0\nEOF\n".utf8).write(to: dir.appendingPathComponent("inside.dxf"))
        #expect(CADDependencies.resolve("linked.dxf", in: dir).status == .outsideParentFolder)
        #expect(CADDependencies.resolve("inside.dxf", in: dir).status == .found)
    }

    @Test func xrefsInsideTheFolderAreLoadedAndOthersReported() throws {
        let p = try place(Fx.url("xref_project/parent.dxf"))
        #expect(Set(p.report.missingXrefs) == ["SURVEY", "EVIL", "ABS"])
        #expect(p.report.missingImages == ["images/missing.jpg"])
        #expect(p.report.missingFonts == ["romans.shx"])
        #expect(p.report.warnings.contains { $0.contains("outside the drawing's folder") })
        let ld = try #require(p.model[p.link]?.link)
        let d = try #require(p.model.referenceDrawings[ld.contentKey])
        #expect(d.blocks["SITE|*Model"] != nil)
        #expect(d.layers.contains { $0.name == "SITE|C-TOPO" })
        let flat = d.flattened()
        #expect(flat.contains { if case .text(_, _, _, let s, _, _) = $0 { return s == "SITE PLAN" }; return false })
        // Child in meters inside a millimeter parent: the 100 m site polyline stays 100 m.
        let site = flat.compactMap { e -> Rect2? in if case .polyline(let pts, _, let st) = e, st.handle == "30" { return Rect2(points: pts) }; return nil }
        #expect(approx(try #require(site.first).width, 100, 1e-9))
    }

    @Test func circularXrefsAreDetected() throws {
        let p = try place(Fx.url("xref_project/loop_a.dxf"))
        #expect(p.report.warnings.contains { $0.contains("circular reference") })
    }
}
