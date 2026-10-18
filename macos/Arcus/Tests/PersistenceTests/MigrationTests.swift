import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// Expected content of the committed v1 fixture (written alongside it by the generator).
struct FixtureExpectation: Codable {
    var elements: [Element]
    var nextID: UInt64
    var revision: UInt64
    var projectParameters: [ParameterDefinition]
    var viewSheetSets: [ViewSheetSet]
    var referenceDrawings: [String: ReferenceDrawing]
    var documentID: UUID
}

@Suite("Schema migration")
struct MigrationTests {
    static var fixtureRoot: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appending(path: "v1") }

    /// Small but representative model for the v1 fixture (levels, types, walls, a hosted door, a room, a sheet set,
    /// project parameters, a reference drawing, design option, phases).
    static func fixtureModel() throws -> BIMModel {
        let tx = TransactionContext(model: BIMModel(), name: "Fixture")
        tx.create(.projectInfo, name: "Project Information", data: .projectInfo(ProjectInfoData(projectName: "Fixture House", units: .metric)),
                  ifcGUID: .deterministic("project"))
        let existing = tx.create(.phases, name: "Existing", data: .phase(PhaseData(order: 0)))
        let newC = tx.create(.phases, name: "New Construction", data: .phase(PhaseData(order: 1)))
        let l1 = tx.create(.levels, name: "Level 1", data: .level(LevelData(elevation: 0)))
        let l2 = tx.create(.levels, name: "Level 2", data: .level(LevelData(elevation: 3)))
        let brick = tx.create(.materials, name: "Brick", data: .material(MaterialData(materialClass: .masonry, color: RGBColor(hex: 0xA9573F), transparency: 0)))
        var td = TypeData(instanceCategory: .walls, systemFamily: .basicWall, familyName: "Basic Wall",
                          assembly: CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: brick, thickness: 0.2)]))
        td.params[ParameterID("type.function")] = .text("Exterior")
        let wt = tx.create(.elementTypes, name: "Brick 200", data: .type(td))
        let family = tx.create(.families, name: "Door - Single Flush", data: .family(StarterLibrary.singleDoor()))
        var dt = TypeData(instanceCategory: .doors, familyID: family, familyName: "Door - Single Flush")
        dt.params[ParameterID("width")] = .double(0.9)
        let doorType = tx.create(.elementTypes, name: "900 x 2100", data: .type(dt))
        let pts = [Vec2(0, 0), Vec2(8, 0), Vec2(8, 6), Vec2(0, 6)]
        var walls: [ElementID] = []
        for i in 0..<4 {
            walls.append(tx.create(.walls, data: .wall(WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)), typeID: wt, levelID: l1,
                                   ifcGUID: .deterministic("wall\(i)")) { $0.phaseCreated = existing })
        }
        tx.create(.doors, data: .insert(InsertData(location: Vec2(4, 0))), typeID: doorType, levelID: l1, hostID: walls[0], ifcGUID: .deterministic("door")) {
            $0.mark = "D1"; $0.phaseCreated = newC
        }
        tx.create(.rooms, name: "Living", data: .room(RoomData(point: Vec2(4, 3), number: "1")), levelID: l1, ifcGUID: .deterministic("room"))
        let opt = tx.create(.designOptions, name: "Option A", data: .designOption(DesignOptionData(setName: "Porch", isPrimary: true)))
        tx.update(walls[3]) { $0.designOptionID = opt; $0[param: .user("fire")] = .text("60 min") }
        var drawing = Sample.drawing(7)
        drawing.entities = Array(drawing.entities.prefix(12))
        tx.addReferenceDrawing(drawing)
        tx.setProjectParameters([ParameterDefinition(id: .user("fire"), name: "Fire Rating", type: .text, group: .identity, categories: [.walls, .doors])])
        tx.setViewSheetSets([ViewSheetSet(name: "Planning", members: [l1, l2])])
        return try tx.commit().model
    }

    /// Regenerates the committed fixture. Run with `ARCUS_WRITE_FIXTURES=1 swift test --filter MigrationTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ARCUS_WRITE_FIXTURES"] == "1"))
    func generateV1Fixture() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/v1")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = try Self.fixtureModel()
        let pkg = dir.appending(path: "Sample.arcus")
        try? FileManager.default.removeItem(at: pkg)
        let info = ArcusPackage.WriteInfo(documentID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!, appVersion: "0.9.0", build: "90",
                                           created: Date(timeIntervalSince1970: 1_735_689_600))
        try ArcusPackage.writeLegacyV1(model, to: pkg, info: info)
        let exp = FixtureExpectation(elements: model.allElements, nextID: model.nextID, revision: model.revision, projectParameters: model.projectParameters,
                                     viewSheetSets: model.viewSheetSets, referenceDrawings: model.referenceDrawings, documentID: info.documentID)
        let enc = StoredJSON.encoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try enc.encode(exp).write(to: dir.appending(path: "expected.json"))
    }

    func expectation() throws -> FixtureExpectation {
        try StoredJSON.decoder().decode(FixtureExpectation.self, from: Data(contentsOf: Self.fixtureRoot.appending(path: "expected.json")))
    }

    func fixtureCopy(_ tmp: TempDir) throws -> URL {
        let dest = tmp.file("Sample.arcus")
        try FileManager.default.copyItem(at: Self.fixtureRoot.appending(path: "Sample.arcus"), to: dest)
        return dest
    }

    @Test func v1FixtureIsReallyV1() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let m = try ArcusPackage.readManifest(url)
        #expect(m.schemaVersion == 1)
        #expect(m.minimumReaderVersion == 1)
        #expect(m.writerAppVersion == "0.9.0")
        let db = try SQLiteDatabase.openReadOnly(path: url.appending(path: "model.sqlite").path)
        #expect(try db.scalarInt("PRAGMA user_version") == 1)
        #expect(try !db.tableExists("relations"))
        #expect(try db.tableExists("drawings"))
        #expect(!FileManager.default.fileExists(atPath: url.appending(path: "assets").path))
    }

    @Test func v1FixtureMigratesExactly() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let exp = try expectation()
        let (model, manifest) = try ArcusPackage.read(from: url)
        #expect(manifest.documentID == exp.documentID)
        // Legacy per-element revision counters (1, 2, 3…) are re-stamped on load so they can't collide with the
        // process-unique cache stamps; everything else must migrate exactly.
        #expect(model.allElements.allSatisfy { $0.revision >= Element.legacyRevisionLimit })
        func unstamped(_ es: [Element]) -> [Element] { es.map { var e = $0; e.revision = 0; return e } }
        #expect(unstamped(model.allElements) == unstamped(exp.elements))
        #expect(model.nextID == exp.nextID)
        #expect(model.revision == exp.revision)
        #expect(model.projectParameters == exp.projectParameters)
        #expect(model.viewSheetSets == exp.viewSheetSets)
        #expect(model.referenceDrawings == exp.referenceDrawings)
        // Indexes are rebuilt: hosted door and room are queryable.
        let wall0 = model.elements(.walls).first!
        #expect(model.hosted(by: wall0.id).count == 1)
        #expect(model.elements(.rooms).first?.name == "Living")
        #expect(model.projectInfo.projectName == "Fixture House")
    }

    @Test func migratedDocumentSavesAsV2AndRoundTrips() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let (model, manifest) = try ArcusPackage.read(from: url)
        let out = tmp.file("Migrated.arcus")
        var info = Sample.info
        info.documentID = manifest.documentID
        info.created = manifest.created
        try ArcusPackage.write(model, to: out, info: info)
        let m2 = try ArcusPackage.readManifest(out)
        #expect(m2.schemaVersion == ArcusPackage.currentSchemaVersion)
        #expect(m2.documentID == manifest.documentID)
        #expect(abs(m2.created.timeIntervalSince(manifest.created)) < 0.001)
        Sample.expectEqual(model, try ArcusPackage.read(from: out).model)
        let r = ArcusPackage.verify(out)
        #expect(r.isHealthy, "\(r.problems)")
        // Drawings moved from the v1 table into compressed assets.
        #expect(m2.checksums.keys.contains { $0.hasPrefix("assets/") })
    }

    @Test func v1FixtureVerifies() throws {
        let tmp = TempDir()
        let url = try fixtureCopy(tmp)
        let r = ArcusPackage.verify(url)
        #expect(r.isHealthy, "\(r.problems)")
        #expect(r.recoveredElements == (try expectation()).elements.count)
    }

    @Test func freshlyWrittenV1ReadsLikeFixture() throws {
        // The legacy writer and the migration path agree for the rich model too.
        let tmp = TempDir()
        let model = try Sample.richModel()
        let url = tmp.file("Legacy.arcus")
        try ArcusPackage.writeLegacyV1(model, to: url, info: Sample.info)
        Sample.expectEqual(model, try ArcusPackage.read(from: url).model)
    }
}
