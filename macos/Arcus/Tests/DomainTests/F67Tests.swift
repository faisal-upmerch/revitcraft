import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// F67: the Insert tab: linked models, point clouds, linked topography, DWF markups, decals, gbXML rooms, Load as
/// Group, Insert from File and Transfer Project Standards.
@Suite("F67 Insert")
@MainActor
struct F67Tests {
    func build(_ m: BIMModel, _ view: ElementID) -> ViewGraphics { ViewGraphicsBuilder(model: m, view: m[view]!).build() }

    /// A host project linking the 10 × 8 box of another project.
    func linkedHost() throws -> (host: BIMModel, link: ElementID, ids: ProjectTemplates.Ids, src: Fx.Box) {
        let src = try Fx.box()
        var (host, ids) = Fx.template()
        let (parts, count) = LinkedGeometry.content(of: src.model)
        var link: ElementID!
        try Fx.commit(&host) { tx in
            link = try InsertOperations.addLinkedModel(.arcus, source: ExternalFileRef(path: "/tmp/Box.arcus"), parts: parts, elementCount: count, in: tx)
        }
        return (host, link, ids, src)
    }

    @Test func packedMeshRoundTrips() {
        let m = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(1, 2, 3)))
        let back = PackedMesh(m).mesh
        #expect(back.positions.count == m.positions.count && back.indices == m.indices && back.featureEdges == m.featureEdges)
        #expect(abs(back.signedVolume - m.signedVolume) < 1e-5)
        #expect(PackedMesh(Mesh()).mesh.isEmpty)
    }

    @Test func linkModelShowsInPlanSectionAnd3D() throws {
        let (host, link, ids, _) = try linkedHost()
        let l = try #require(host[link]?.linkedModel)
        #expect(host[link]?.category == .linkedModels && l.elementCount == 4 && l.parts.allSatisfy { $0.category == .walls })
        #expect(Parameters.value(ParameterID("f67.count"), of: host[link]!, host) == .int(4))
        // Plans: the linked walls are cut at the host view's cut plane.
        let plan = build(host, ids.planViews[ids.levels[0]]!)
        let cut = plan.items.filter { $0.elementID == link && $0.layer == .cut }
        #expect(!cut.isEmpty)
        let cutBounds = cut.reduce(Rect2.empty) { $0.union($1.bounds) }
        #expect(cutBounds.min.x < 0 && cutBounds.max.x > 10 && cutBounds.max.y > 8)
        // Sections cut the link with the host's elements.
        var m = host
        var sid: ElementID!
        try Fx.commit(&m) { tx in
            var v = ViewData(kind: .section)
            v.planeOrigin = Vec3(5, 4, 0); v.viewDirection = Vec2(0, 1); v.farClip = 10
            sid = tx.create(.views, name: "Section A", data: .view(v))
        }
        #expect(build(m, sid).items.contains { $0.elementID == link && $0.layer == .cut })
        // 3D: one coloured part per linked wall.
        let parts = ElementMeshes.parts(host[link]!, host)
        #expect(parts.count == l.parts.count && parts.allSatisfy { $0.color != nil && !$0.mesh.isEmpty })
        // Unloaded links are not drawn.
        try Fx.commit(&m) { tx in InsertOperations.setLoaded(link, false, in: tx) }
        #expect(!build(m, ids.planViews[ids.levels[0]]!).items.contains { $0.elementID == link })
    }

    @Test func linkMovesAsAWholeAndReloads() throws {
        var (host, link, _, src) = try linkedHost()
        let before = ElementMeshes.bounds(host[link]!, host)
        try Fx.commit(&host) { tx in tx.update(link) { ElementTransform.apply(.translation(Vec2(20, 0)), to: &$0) } }
        let after = ElementMeshes.bounds(host[link]!, host)
        #expect(abs(after.min.x - before.min.x - 20) < 1e-4)
        // A reload swaps the content and keeps the placement.
        var changed = src.model
        try Fx.commit(&changed) { tx in tx.delete(src.walls[0]) }
        let (parts, count) = LinkedGeometry.content(of: changed)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try Fx.commit(&host) { tx in try InsertOperations.reloadLinkedModel(link, parts: parts, elementCount: count, sourceModified: date, in: tx) }
        let l = try #require(host[link]?.linkedModel)
        #expect(l.elementCount == 3 && l.source.sourceModified == date && l.placement == .translation(Vec2(20, 0)))
    }

    @Test func emptyProjectsCannotBeLinked() throws {
        var (host, _) = Fx.template()
        let tx = TransactionContext(model: host, name: "Link")
        #expect(throws: InsertError.self) { try InsertOperations.addLinkedModel(.arcus, source: ExternalFileRef(path: "/tmp/E.arcus"), parts: [], elementCount: 0, in: tx) }
        host = try tx.commit().model
        #expect(host.elements(.linkedModels).isEmpty)
    }

    @Test func coordinationModelsAreOnlyIn3D() throws {
        var (host, ids) = Fx.template()
        let mesh = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(2, 2, 5)))
        var id: ElementID!
        try Fx.commit(&host) { tx in
            id = try InsertOperations.addLinkedModel(.obj, source: ExternalFileRef(path: "/tmp/site.obj"), parts: LinkedGeometry.content(ofMesh: [("Tower", mesh)]), elementCount: 1, in: tx)
        }
        #expect(host[id]?.category == .coordinationModels)
        #expect(!build(host, ids.planViews[ids.levels[0]]!).items.contains { $0.elementID == id })
        #expect(ElementMeshes.hasModelGeometry(host[id]!) && !ElementMeshes.parts(host[id]!, host).isEmpty)
    }

    @Test func pointCloudsDrawAsDotsInThePlanRangeAndIn3D() throws {
        var (host, ids) = Fx.template()
        var pts: [(Vec3, (UInt8, UInt8, UInt8))] = []
        for i in 0..<50 { pts.append((Vec3(Double(i) * 0.1, 0, 0.5), (200, 10, 10))) }
        for i in 0..<20 { pts.append((Vec3(Double(i) * 0.1, 1, 9), (10, 10, 200))) } // above the cut plane
        var id: ElementID!
        try Fx.commit(&host) { tx in
            id = try InsertOperations.addPointCloud(PointSet(points: pts, sourceCount: 70, hasColor: true, unitScale: 1), source: ExternalFileRef(path: "/tmp/scan.xyz"), in: tx)
        }
        let pc = try #require(host[id]?.pointCloud)
        #expect(pc.points.count == 70 && pc.points.points.first?.position == Vec3(0, 0, 0.5))
        let plan = build(host, ids.planViews[ids.levels[0]]!)
        let item = try #require(plan.items.first { $0.elementID == id })
        let dots = item.primitives.reduce(0) { n, p in if case .fill(let polys, _) = p { return n + polys.count }; return n }
        #expect(dots == 50, "only points between the view range bottom and the cut plane")
        let parts = ElementMeshes.parts(host[id]!, host)
        #expect(parts.count == 2 && parts.reduce(0) { $0 + $1.mesh.positions.count } == 70 * 4)
    }

    @Test func linkTopographyReloadsItsPoints() throws {
        var (m, _) = Fx.template()
        let grid = (0...4).flatMap { i in (0...4).map { j in (Vec3(Double(i) * 5, Double(j) * 5, Double(i)), (UInt8(0), UInt8(0), UInt8(0))) } }
        var id: ElementID!
        let src = ExternalFileRef(path: "/tmp/survey.xyz")
        try Fx.commit(&m) { tx in id = try InsertOperations.linkTopography(PointSet(points: grid, sourceCount: 25, hasColor: false, unitScale: 0.001), source: src, in: tx).0 }
        let e = try #require(m[id])
        #expect(e.isToposolid && TopographyLink.isLinked(e) && TopographyLink.source(of: e)?.path == src.path && TopographyLink.unitScale(of: e) == 0.001)
        #expect(InsertOperations.linkElements(m).map(\.id) == [id])
        let raised = grid.map { (Vec3($0.0.x, $0.0.y, $0.0.z + 2), $0.1) }
        try Fx.commit(&m) { tx in try InsertOperations.reloadTopography(id, PointSet(points: raised, sourceCount: 25, hasColor: false, unitScale: 0.001), sourceModified: Date(), in: tx) }
        #expect(m[id]?.topography?.points.map(\.z).min() == 2)
        #expect(TopographyLink.isLinked(m[id]!))
    }

    @Test func dwfMarkupsGoOnSheetsAndReloadByPage() throws {
        var (m, _) = Fx.template()
        var sheet: ElementID!, mk: ElementID!
        let page = DWFPage(name: "F101 - Plans", size: Vec2(0.841, 0.594),
                           polylines: [MarkupData.Polyline(points: [Vec2(0.1, 0.1), Vec2(0.3, 0.1), Vec2(0.3, 0.2)], color: RGBColor(1, 0, 0))],
                           texts: [MarkupData.Text(position: Vec2(0.1, 0.25), string: "Check this", height: 0.004)])
        try Fx.commit(&m) { tx in
            sheet = tx.create(.sheets, name: "Markup Target", data: .sheet(SheetData(number: "F101")))
            #expect(InsertOperations.matchingSheet(for: page.name, in: tx.model) == sheet)
            mk = try InsertOperations.addMarkup(page, onSheet: sheet, source: ExternalFileRef(path: "/tmp/set.dwfx"), in: tx)
        }
        #expect(m[mk]?.ownerViewID == sheet && m[mk]?.category == .dwfMarkups)
        let g = SheetGraphicsBuilder(model: m, sheet: m[sheet]!).build()
        let item = try #require(g.items.first { $0.elementID == mk })
        #expect(item.primitives.contains { if case .text(let t) = $0 { t.string == "Check this" } else { false } })
        var changed = page
        changed.texts = [MarkupData.Text(position: Vec2(0.1, 0.25), string: "Fixed", height: 0.004)]
        try Fx.commit(&m) { tx in try InsertOperations.reloadMarkup(mk, pages: [changed], sourceModified: nil, in: tx) }
        #expect(m[mk]?.markup?.texts.first?.string == "Fixed")
        let tx = TransactionContext(model: m, name: "x")
        #expect(throws: InsertError.self) { try InsertOperations.reloadMarkup(mk, pages: [DWFPage(name: "Other", size: .zero)], sourceModified: nil, in: tx) }
    }

    @Test func decalsSitOnWallFacesAndShowTheirImageInRealistic() throws {
        var b = try Fx.box()
        var type: ElementID!, decal: ElementID!
        // A 2 × 1 image: red then blue.
        var t = DecalTypeData(image: Data([1]), imageName: "sign.png", pixelWidth: 2, pixelHeight: 1)
        t.swatch = DecalSwatch(columns: 2, rows: 1, rgba: Data([255, 0, 0, 255, 0, 0, 255, 255]))
        let planID = b.plan.id, wall = b.walls[0]
        try Fx.commit(&b.model) { tx in
            type = InsertOperations.createDecalType("Sign", t, in: tx)
            // Outside the south wall (y = 0): the face at y = -0.1.
            let (c, n) = try #require(InsertOperations.decalFace(host: tx.model[wall]!, at: Vec2(5, -1), view: tx.model[planID]?.view, model: tx.model))
            #expect(abs(c.y + 0.1) < 1e-9 && n == Vec3(0, -1, 0) && abs(c.z - (tx.model[planID]?.view?.viewRange.cutOffset ?? 0)) < 1e-9)
            decal = try InsertOperations.placeDecal(type, host: wall, center: c, normal: n, in: tx)
        }
        let d = try #require(b.model[decal]?.decal)
        #expect(abs(d.width - 1) < 1e-9 && abs(d.height - 0.5) < 1e-9 && b.model[decal]?.hostID == b.walls[0])
        let parts = ElementMeshes.parts(b.model[decal]!, b.model)
        #expect(parts.filter { $0.styles.shows(realistic: false) }.count == 1, "the outline in shaded styles")
        let image = parts.filter { $0.styles == .realisticOnly }
        #expect(image.count == 2 && image.contains { ($0.color?.r ?? 0) > 0.8 } && image.contains { ($0.color?.b ?? 0) > 0.8 })
        // The plan shows the decal as a line along the face; moving the wall carries it; deleting the wall deletes it.
        #expect(build(b.model, b.plan.id).items.contains { $0.elementID == decal })
        #expect(ElementOperations.dependentsToCarry([b.walls[0]], b.model, viewID: nil).contains(decal))
        // Width and Height are instance properties.
        try Fx.commit(&b.model) { tx in try Parameters.set(ParameterID("f67.decal.width"), to: .double(2), on: decal, in: tx) }
        #expect(b.model[decal]?.decal?.width == 2 && Parameters.value(ParameterID("f67.decal.type"), of: b.model[decal]!, b.model) == .text("Sign"))
        try Fx.commit(&b.model) { tx in tx.delete(wall) }
        #expect(b.model[decal] == nil)
    }

    @Test func decalsInElevationsFaceTheViewer() throws {
        let b = try Fx.box()
        var v = ViewData(kind: .elevation)
        v.planeOrigin = Vec3(5, -5, 0); v.viewDirection = Vec2(0, 1)
        let (c, n) = try #require(InsertOperations.decalFace(host: b.model[b.walls[0]]!, at: Vec2(2, 1.2), view: v, model: b.model))
        #expect(abs(c.x - 7) < 1e-9 && abs(c.y + 0.1) < 1e-9 && abs(c.z - 1.2) < 1e-9 && n == Vec3(0, -1, 0))
    }

    @Test func gbXMLSpacesBecomeBoundedRooms() throws {
        var (m, ids) = Fx.template()
        let a = GbXMLSpace(name: "Office", number: "sp1", floor: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 3), Vec2(0, 3)], bottom: 0, top: 2.7)
        let c = GbXMLSpace(name: "Store", number: "sp2", floor: [Vec2(4, 0), Vec2(6, 0), Vec2(6, 3), Vec2(4, 3)], bottom: 0, top: 2.7)
        var rooms: [ElementID] = []
        try Fx.commit(&m) { tx in rooms = try InsertOperations.importGbXML([a, c], in: tx) }
        #expect(rooms.count == 2)
        #expect(m.elements(.roomSeparationLines).count == 7, "the shared edge is drawn once")
        let office = try #require(m[rooms[0]])
        #expect(office.name == "Office" && office.levelID == ids.levels[0])
        #expect(abs((RoomGeometry.boundary(office, m).profile?.area ?? 0) - 12) < 1e-6)
        #expect(abs(RoomGeometry.height(office, m) - 2.7) < 1e-9)
    }

    @Test func loadAsGroupBringsTheModelAcross() throws {
        let src = try Fx.box()
        var (host, _) = Fx.template()
        var gid: ElementID!
        try Fx.commit(&host) { tx in gid = try InsertFromFile.loadAsGroup(src.model, name: "Box", in: tx).group }
        let g = try #require(host[gid]?.group)
        #expect(host[gid]?.category == .modelGroups && g.groupTypeName == "Box" && g.origin == .zero)
        #expect(g.members.count == 4 && g.members.allSatisfy { host[$0]?.wall != nil && host[$0]?.groupID == gid })
        // A second load gets its own group name.
        try Fx.commit(&host) { tx in gid = try InsertFromFile.loadAsGroup(src.model, name: "Box", in: tx).group }
        #expect(host[gid]?.group?.groupTypeName == "Box 2")
    }

    /// A source project with a drafting view holding two detail lines and a text note.
    func sourceWithDraftingView() throws -> (BIMModel, ElementID) {
        var (src, _) = Fx.template()
        var view: ElementID!
        try Fx.commit(&src) { tx in
            view = tx.create(.views, name: "Typical Detail", data: .view(ViewData(kind: .drafting)))
            tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(0, 0), Vec2(1, 0))))), ownerViewID: view)
            tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(1, 0), Vec2(1, 1))))), ownerViewID: view)
            tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(0, 1), text: "Flashing")), typeID: tx.model.types(for: .textNotes).first?.id, ownerViewID: view)
        }
        return (src, view)
    }

    @Test func insertViewsCopiesDraftingViewsWithTheirContent() throws {
        let (src, view) = try sourceWithDraftingView()
        #expect(InsertFromFile.insertableViews(src).contains { $0.id == view })
        var (host, _) = Fx.template()
        var made: [ElementID] = []
        try Fx.commit(&host) { tx in made = try InsertFromFile.insertViews([view], from: src, in: tx).views }
        let v = try #require(made.first.flatMap { host[$0] })
        #expect(v.name == "Typical Detail" && v.view?.kind == .drafting)
        let owned = host.owned(byView: v.id)
        #expect(owned.filter { $0.category == .detailLines }.count == 2 && owned.contains { $0.textNote?.text == "Flashing" })
        try Fx.commit(&host) { tx in made = try InsertFromFile.insertViews([view], from: src, in: tx).views }
        #expect(host[made[0]]?.name == "Typical Detail (2)")
    }

    @Test func insert2DElementsGoIntoTheCurrentView() throws {
        let (src, view) = try sourceWithDraftingView()
        var (host, _) = Fx.template()
        var target: ElementID!
        try Fx.commit(&host) { tx in
            target = tx.create(.views, name: "Mine", data: .view(ViewData(kind: .drafting)))
        }
        try Fx.commit(&host) { tx in try InsertFromFile.insert2DElements(from: view, of: src, into: target, in: tx) }
        #expect(host.owned(byView: target).count == 3)
        #expect(InsertFromFile.viewsWith2DElements(src).map(\.id) == [view])
    }

    @Test func transferProjectStandardsCopiesTypesAndKeepsOrOverwritesMatches() throws {
        var (src, ids) = Fx.template()
        let generic = try #require(ids.wallTypes[Fx.generic])
        try Fx.commit(&src) { tx in
            let m = tx.create(.materials, name: "F67 Copper", data: .material(MaterialData(materialClass: .metal, color: RGBColor(0.7, 0.4, 0.2))))
            var td = try #require(tx.model[generic]?.typeData)
            if var a = td.assembly { a.layers = a.layers.map { var l = $0; l.materialID = m; return l }; td.assembly = a }
            tx.create(.elementTypes, name: "F67 Copper Wall", data: .type(td))
            tx.update(generic) { $0.params[.comments] = .text("from source") }
        }
        let items = ProjectStandards.items(in: src)
        #expect(items.contains { $0.id == "type.walls" && $0.title == "Wall Types" } && items.contains { $0.id == "materials" })
        var (host, hostIDs) = Fx.template()
        let chosen: Set<String> = ["type.walls", "materials"]
        let dups = ProjectStandards.duplicates(chosen, from: src, into: host)
        #expect(dups.contains { $0.hasSuffix(Fx.generic) } && !dups.contains { $0.hasSuffix("F67 Copper Wall") })
        var report = ProjectStandards.Report()
        try Fx.commit(&host) { tx in report = ProjectStandards.transfer(chosen, from: src, overwrite: false, in: tx) }
        let copper = try #require(host.type(category: .walls, name: "F67 Copper Wall"))
        let mat = try #require(copper.typeData?.assembly?.layers.first?.materialID)
        #expect(host[mat]?.name == "F67 Copper", "layer materials resolve to the destination's copy")
        #expect(report.added.contains { $0.hasSuffix("F67 Copper Wall") } && report.kept.contains { $0.hasSuffix(Fx.generic) })
        #expect(host[hostIDs.wallTypes[Fx.generic]!]?.params[.comments] == nil, "New Only keeps the existing type")
        try Fx.commit(&host) { tx in report = ProjectStandards.transfer(chosen, from: src, overwrite: true, in: tx) }
        #expect(host[hostIDs.wallTypes[Fx.generic]!]?.params[.comments] == .text("from source"))
        #expect(host.elements(.elementTypes).filter { $0.name == "F67 Copper Wall" }.count == 1, "overwriting doesn't duplicate")
    }

    @Test func importedImagesKeepTheirPicture() throws {
        var (m, ids) = Fx.template()
        var id: ElementID!
        try Fx.commit(&m) { tx in
            id = try InsertOperations.importImage(Data([0x89, 0x50]), name: "photo.png", pixelSize: (100, 50), metersPerPixel: 0.01,
                                                 viewID: ids.planViews[ids.levels[0]], levelID: nil, in: tx)
        }
        let l = try #require(m[id]?.link)
        #expect(!l.isLinked && l.embeddedData == Data([0x89, 0x50]) && l.format == .image)
        #expect(abs(l.placement.apply(Vec2(100, 50)).x - 1) < 1e-12)
    }
}
