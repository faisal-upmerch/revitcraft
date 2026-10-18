import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// BL-SITE (ARCUS-070): toposolids, sub-divisions, their layered types and earthwork survive a save and reopen.
@Suite("Toposolids persist")
struct ToposolidPersistenceTests {
    @Test func toposolidSubDivisionAndTypesRoundTrip() throws {
        let tmp = TempDir()
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Site")
        let pts = (0...8).flatMap { i in (0...8).map { j in Vec3(Double(i), Double(j), 0.05 * Double(i * j)) } }
        let (solid, _) = try ToposolidOperations.create(points: pts, name: "Existing Ground", in: tx)
        let sub = try ToposolidOperations.subdivide(solid, boundary: .rectangle(Rect2(min: Vec2(1, 1), max: Vec2(4, 3))), height: -0.15, in: tx)
        let sketched = try ToposolidOperations.create(outline: Polygon2([Vec2(10, 0), Vec2(16, 0), Vec2(16, 4), Vec2(13, 6), Vec2(10, 4)]), elevation: 1.2, in: tx)
        var model = try tx.commit().model
        let tx2 = TransactionContext(model: model, name: "Edit")
        tx2.update(solid) { $0.topography?.solid?.cutVolume = 12.5; $0.topography?.solid?.fillVolume = 3.25 }
        model = try tx2.commit().model

        let url = tmp.file("Site.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, _) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        let s = try #require(read[solid])
        #expect(s.isToposolid && s.topography?.points.count == pts.count && s.topography?.solid?.cutVolume == 12.5 && s.topography?.solid?.fillVolume == 3.25)
        #expect(read[sub]?.isToposolidSubdivision == true && read[sub]?.hostID == solid && read[sub]?.topography?.solid?.subdivisionHeight == -0.15)
        #expect(read[sketched]?.topography?.solid?.outline?.count == 5)
        let type = try #require(read[s.typeID]?.typeData)
        #expect(type.systemFamily == .toposolid && type.assembly?.layers.map(\.isVariable) == [false, true])
        #expect(ToposolidTypes.types(read, subdivision: true).count == 1)
        // Derived geometry is identical after reopening.
        for id in [solid, sub, sketched] {
            let a = ElementMeshes.parts(model[id]!, model).reduce(0) { $0 + $1.mesh.signedVolume }
            let b = ElementMeshes.parts(read[id]!, read).reduce(0) { $0 + $1.mesh.signedVolume }
            #expect(a > 0 && abs(a - b) < 1e-9)
        }
    }

    @Test func legacyToposurfacesStillDecode() throws {
        // A toposurface written before toposolids existed has no "solid" key.
        let json = #"{"points":[{"x":0,"y":0,"z":1},{"x":5,"y":0,"z":1},{"x":0,"y":5,"z":2}],"materialID":null}"#
        let t = try JSONDecoder().decode(TopographyData.self, from: Data(json.utf8))
        #expect(t.solid == nil && t.points.count == 3)
    }
}
