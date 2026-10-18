import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// Schema 3 adds ramps, solid joins, roof extrusions and floor/roof shape points. `Fixtures/v2/Sample.arcus` was
/// written by the last schema-2 build (walls, a floor, a footprint roof, a stair with hosted railings) and must open
/// with every new field at its default.
@Suite("Schema 3 migration")
struct SchemaV3Tests {
    static var fixtureRoot: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appending(path: "v2") }

    func fixtureCopy(_ tmp: TempDir) throws -> URL {
        let dest = tmp.file("Sample.arcus")
        try FileManager.default.copyItem(at: Self.fixtureRoot.appending(path: "Sample.arcus"), to: dest)
        return dest
    }

    @Test func schema2FixtureOpensWithDefaults() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let manifest = try ArcusPackage.readManifest(url)
        #expect(manifest.schemaVersion == 2 && manifest.minimumReaderVersion == 2)
        let (model, _) = try ArcusPackage.read(from: url)
        let exp = try StoredJSON.decoder().decode(FixtureExpectation.self, from: Data(contentsOf: Self.fixtureRoot.appending(path: "expected.json")))
        func unstamped(_ es: [Element]) -> [Element] { es.map { var e = $0; e.revision = 0; return e } }
        #expect(unstamped(model.allElements) == unstamped(exp.elements))
        #expect(!ArcusPackage.isNewerThanCurrent(manifest))

        let floor = try #require(model.elements(.floors).first?.slab)
        #expect(floor.shapePoints == nil)
        let roof = try #require(model.elements(.roofs).first?.roof)
        #expect(roof.extrusion == nil && roof.shapePoints == nil)
        #expect(roof.edgeSlopes.count == 4)
        #expect(model.elements(.ramps).isEmpty)
        #expect(model.elements(.constraints).isEmpty)
        // The old stair and its hosted railings still regenerate.
        let stair = try #require(model.elements(.stairs).first)
        #expect(StairGeometry.layout(stair, model) != nil)
        #expect(model.elements(.railings).allSatisfy { RailingGeometry.path($0, model).count >= 2 })
    }

    @Test func schema2DocumentSavesAsSchema3() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let (model, manifest) = try ArcusPackage.read(from: url)
        let out = tmp.file("Saved.arcus")
        var info = Sample.info
        info.documentID = manifest.documentID
        try ArcusPackage.write(model, to: out, info: info)
        let m2 = try ArcusPackage.readManifest(out)
        #expect(m2.schemaVersion == 3)
        #expect(m2.minimumReaderVersion == 3)
        Sample.expectEqual(model, try ArcusPackage.read(from: out).model)
        #expect(ArcusPackage.verify(out).isHealthy)
    }

    @Test func schema3DataRoundTripsAndOlderReadersAreTurnedAway() throws {
        let tmp = TempDir()
        let tx = TransactionContext(model: BIMModel(), name: "Schema 3")
        let l1 = tx.create(.levels, name: "Level 1", data: .level(LevelData(elevation: 0)))
        let l2 = tx.create(.levels, name: "Level 2", data: .level(LevelData(elevation: 1)))
        tx.create(.ramps, data: .ramp(RampData(path: [Vec2(0, 0), Vec2(12, 0)], width: 1.5, topLevelID: l2)), levelID: l1)
        let sq: [Curve2] = [Vec2(0, 0), Vec2(6, 0), Vec2(6, 6), Vec2(0, 6)].enumerated().map { i, p in
            .line(Segment2(p, [Vec2(6, 0), Vec2(6, 6), Vec2(0, 6), Vec2(0, 0)][i]))
        }
        var slab = SlabData(boundary: Sketch(loops: [sq]))
        slab.shapePoints = [ShapePoint(position: Vec2(3, 3), offset: -0.02)]
        let floor = tx.create(.floors, data: .slab(slab), levelID: l1)
        var roof = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
        roof.extrusion = RoofExtrusion(origin: .zero, direction: .unitX, profile: [.line(Segment2(Vec2(0, 0), Vec2(3, 1.5))), .line(Segment2(Vec2(3, 1.5), Vec2(6, 0)))],
                                       start: 0, end: 6)
        let r = tx.create(.roofs, data: .roof(roof), levelID: l2)
        tx.create(.constraints, data: .constraint(ConstraintData(kind: .join, references: [GeometryReference(r, .location), GeometryReference(floor, .location)])))
        let model = try tx.commit().model
        let url = tmp.file("S3.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, manifest) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        #expect(read.elements(.ramps).first?.ramp?.path.count == 2)
        #expect(read[floor]?.slab?.shapePoints?.first?.offset == -0.02)
        #expect(read[r]?.roof?.extrusion?.profile.count == 2)
        // A schema-2 reader is refused with the "newer format" error rather than a decoding failure.
        #expect(throws: PersistenceError.self) { try ArcusPackage.gate(manifest, url: url, reader: 2) }
    }
}
