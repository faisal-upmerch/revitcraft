import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// F67: links (Arcus projects, point clouds, linked topography, DWF markups), decals and imported pictures survive a
/// save and reopen, and an .arcus file read back links with the same content.
@Suite("F67 Insert persistence")
@MainActor
struct F67PersistenceTests {
    @Test func linksDecalsAndImportsRoundTrip() throws {
        let tmp = TempDir()
        // The project to link: a box of walls, saved to disk and read back as a link would read it.
        let (s0, sids) = ProjectTemplates.make(.architectural, units: .metric)
        let stx = TransactionContext(model: s0, name: "Box")
        let pts = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 4), Vec2(0, 4)]
        for i in 0..<4 {
            stx.create(.walls, data: .wall(WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: sids.levels[1])),
                       typeID: sids.wallTypes.values.sorted().first, levelID: sids.levels[0])
        }
        let srcModel = try stx.commit().model
        let srcURL = tmp.file("Linked.arcus")
        try ArcusPackage.write(srcModel, to: srcURL, info: Sample.info)
        let (readSrc, _) = try ArcusPackage.read(from: srcURL)
        let (parts, count) = LinkedGeometry.content(of: readSrc)
        #expect(count == 4 && parts.count == LinkedGeometry.content(of: srcModel).parts.count)

        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Insert")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let link = try InsertOperations.addLinkedModel(.arcus, source: ExternalFileRef(path: srcURL.path, sourceModified: modified), parts: parts, elementCount: count, in: tx)
        tx.update(link) { ElementTransform.apply(.translation(Vec2(3, 1)), to: &$0) }
        let cloud = try InsertOperations.addPointCloud(PointSet(points: [(Vec3(1, 2, 3), (10, 20, 30)), (Vec3(4, 5, 6), (40, 50, 60))], sourceCount: 2, hasColor: true, unitScale: 1),
                                                       source: ExternalFileRef(path: "/tmp/scan.pts"), in: tx)
        let grid = (0...3).flatMap { i in (0...3).map { j in (Vec3(Double(i), Double(j), 0.2 * Double(i)), (UInt8(0), UInt8(0), UInt8(0))) } }
        let topo = try InsertOperations.linkTopography(PointSet(points: grid, sourceCount: 16, hasColor: false, unitScale: 0.3048), source: ExternalFileRef(path: "/tmp/survey.csv", sourceModified: modified), in: tx).0
        let sheet = tx.create(.sheets, name: "Markups", data: .sheet(SheetData(number: "F67-1")))
        let markup = try InsertOperations.addMarkup(DWFPage(name: "F67-1", size: Vec2(0.42, 0.297), polylines: [MarkupData.Polyline(points: [.zero, Vec2(0.1, 0.1)], color: RGBColor(1, 0, 0))],
                                                            texts: [MarkupData.Text(position: Vec2(0.05, 0.05), string: "Note", height: 0.003)],
                                                            pictures: [MarkupData.Picture(bounds: Rect2(min: .zero, max: Vec2(0.05, 0.05)), image: Data([1, 2, 3]))]),
                                                    onSheet: sheet, source: ExternalFileRef(path: "/tmp/set.dwfx"), in: tx)
        var dt = DecalTypeData(image: Data([0x89, 0x50, 0x4e, 0x47]), imageName: "logo.png", pixelWidth: 4, pixelHeight: 2)
        dt.brightness = 1.5; dt.cutout = true; dt.finish = .gloss; dt.luminance = "LCD screen"
        dt.swatch = DecalSwatch(columns: 1, rows: 1, rgba: Data([10, 20, 30, 255]))
        let type = InsertOperations.createDecalType("Logo", dt, in: tx)
        let wall = try #require(tx.model.elements(.walls).first?.id ?? (tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(5, 0))), topLevelID: ids.levels[1])),
                                                                                 typeID: ids.wallTypes.values.sorted().first, levelID: ids.levels[0])))
        let decal = try InsertOperations.placeDecal(type, host: wall, center: Vec3(1, -0.1, 1.2), normal: Vec3(0, -1, 0), in: tx)
        let image = try InsertOperations.importImage(Data([9, 8, 7]), name: "photo.png", pixelSize: (10, 10), metersPerPixel: 0.1,
                                                     viewID: ids.planViews[ids.levels[0]], levelID: nil, in: tx)
        let model = try tx.commit().model

        let url = tmp.file("Host.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, _) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        let l = try #require(read[link]?.linkedModel)
        #expect(l.source.path == srcURL.path && l.source.sourceModified == modified && l.placement == .translation(Vec2(3, 1)) && l.elementCount == 4)
        #expect(ElementMeshes.parts(read[link]!, read).reduce(0) { $0 + $1.mesh.triangleCount } == ElementMeshes.parts(model[link]!, model).reduce(0) { $0 + $1.mesh.triangleCount })
        #expect(read[cloud]?.pointCloud?.points.points.last?.position == Vec3(4, 5, 6))
        let t = try #require(read[topo])
        #expect(TopographyLink.isLinked(t) && TopographyLink.unitScale(of: t) == 0.3048 && TopographyLink.source(of: t)?.sourceModified == modified)
        #expect(read[markup]?.markup?.pictures.first?.image == Data([1, 2, 3]) && read[markup]?.ownerViewID == sheet)
        let rt = try #require(read[type]?.decalType)
        #expect(rt.brightness == 1.5 && rt.cutout && rt.finish == .gloss && rt.swatch?.rgba == Data([10, 20, 30, 255]) && rt.image.count == 4)
        #expect(read[decal]?.decal?.decalTypeID == type && read[decal]?.hostID == wall)
        #expect(read[image]?.link?.embeddedData == Data([9, 8, 7]))
        #expect(InsertOperations.linkElements(read).map(\.id) == [link, cloud, markup, topo].sorted())
    }

    @Test func olderLinksDecodeWithoutEmbeddedData() throws {
        let json = #"{"format":"PDF","isLinked":true,"sourcePath":"/a.pdf","sourceName":"a.pdf","contentKey":"","placement":{"a":1,"b":0,"c":0,"d":1,"tx":0,"ty":0},"elevationOffset":0,"layers":[],"isLoaded":true,"opacity":1,"drawBehindModel":true}"#
        let l = try JSONDecoder().decode(LinkData.self, from: Data(json.utf8))
        #expect(l.embeddedData == nil && l.sourceName == "a.pdf")
    }
}
