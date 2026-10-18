import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusRevit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    static func url(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Imports into `model` and commits.
    static func importAndCommit(_ data: Data, into model: BIMModel = BIMModel(), options: ExchangeImportOptions = .init()) throws -> (BIMModel, ExchangeImportReport) {
        let tx = TransactionContext(model: model, name: "Import Revit")
        let report = try ArcusExchangeImporter.import(data: data, into: tx, options: options)
        let committed = try tx.commit()
        return (committed.model, report)
    }

    static func project() throws -> (BIMModel, ExchangeImportReport) { try importAndCommit(try data("small-project.arcusx")) }
}

func near(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

@Suite("Arcus Exchange import — project")
struct ExchangeProjectImportTests {
    @Test func createsNativeElements() throws {
        let (m, r) = try Fixture.project()
        #expect(r.documentKind == .project)
        #expect(r.schemaVersion == "1.0")
        #expect(r.created("levels") == 2)
        #expect(r.created("views") == 2)
        #expect(r.created("grids") == 2)
        #expect(r.created("materials") == 9)
        #expect(r.created("walls") == 4)
        #expect(r.created("floors") == 1)
        #expect(r.created("roofs") == 1)
        #expect(r.created("doors") == 1)
        #expect(r.created("windows") == 1)
        #expect(r.created("rooms") == 1)
        #expect(r.created("columns") == 1)
        #expect(r.created("components") == 1)
        #expect(r.created("families") == 4)
        #expect(r.referenceMeshes == ["Walls": 1, "Furniture": 1, "Planting": 1])
        #expect(r.familyDefinitions.count == 4)

        #expect(m.levels.map(\.name) == ["Level 1", "Level 2"])
        #expect(m.elements(.walls).count == 4)
        #expect(m.elements(.doors).count == 1)
        #expect(m.elements(.windows).count == 1)
        #expect(m.elements(.ifcReference).count == 3)
        #expect(m.views.filter { $0.view?.kind == .floorPlan }.count == 2)
        #expect(m.projectInfo.projectName == "Small House")
        #expect(m.projectInfo.projectNumber == "2026-017")
        #expect(near(m.projectInfo.latitude, 51.5))
    }

    @Test func wallsAndTypes() throws {
        let (m, r) = try Fixture.project()
        let w1 = try #require(m[r.elementMap["W1"]])
        let wd = try #require(w1.wall)
        #expect(wd.location == .line(Segment2(Vec2(0, 0), Vec2(0, 8))))
        #expect(wd.topLevelID == r.elementMap["L2"])
        #expect(wd.structural)
        #expect(w1.mark == "W-01")
        let type = try #require(m.typeData(of: w1))
        #expect(type.systemFamily == .basicWall)
        let a = try #require(type.assembly)
        #expect(a.layers.map(\.function) == [.finish1, .thermal, .membrane, .structure, .finish2])
        #expect(near(a.totalThickness, 0.3625))
        #expect(a.coreStart == 3 && a.coreEnd == 4)
        #expect(a.wrappingAtInserts == .exterior)
        #expect(m[a.layers[0].materialID]?.name == "Brick, Common Red")
        #expect(type.params[ParameterID("type.function")] == .text("Exterior"))
        #expect(type.params[ParameterID("type.mark")] == .text("W1"))
        #expect(m[r.elementMap["W3"]]?.wall?.locationLine == .finishFaceExterior)
        #expect(m[r.elementMap["W4"]]?.comments == "South facade")
        let frame = try #require(WallGeometry.frame(w1, m))
        #expect(near(frame.baseZ, 0) && near(frame.topZ, 3))
        // The interior type keeps its single core layer (given by flag).
        let interior = try #require(m[r.elementMap["wt-int"]]?.typeData?.assembly)
        #expect(interior.coreStart == 1 && interior.coreEnd == 2)
        // Curtain wall became labelled reference geometry.
        let cw = try #require(m.elements(.ifcReference).first { $0.referenceGeometry?.ifcType == "Revit: Walls" })
        #expect(cw.referenceGeometry?.properties["Reason"] == "curtain or stacked wall")
        #expect(r.hasWarning("type.wallKind"))
    }

    @Test func slabsRoofsRoomsColumns() throws {
        let (m, r) = try Fixture.project()
        let floor = try #require(m[r.elementMap["F1"]])
        #expect(floor.slab?.structural == true)
        let fa = try #require(m.typeData(of: floor)?.assembly)
        #expect(near(fa.totalThickness, 0.3))
        let roof = try #require(m[r.elementMap["R1"]]?.roof)
        #expect(roof.edgeSlopes.count == 4)
        #expect(roof.edgeSlopes.allSatisfy { near($0, 0.5235987756) })
        #expect(roof.overhang == 0.5)
        let room = try #require(m[r.elementMap["RM1"]])
        #expect(room.name == "Living")
        #expect(room.room?.number == "101")
        #expect(room.room?.upperLimitLevelID == nil)
        #expect(room.params[ParameterID("room.department")] == .text("Residential"))
        let col = try #require(m[r.elementMap["C1"]])
        #expect(col.category == .structuralColumns)
        #expect(m.typeParam(col, ParameterID("column.width")) == .double(0.4))
        #expect(col.column?.topLevelID == r.elementMap["L2"])
        let table = try #require(m[r.elementMap["T1"]]?.component)
        #expect(near(table.rotation, .pi / 2))
        #expect(!table.mirrored)
        #expect(table.location == Vec2(7, 5))
        let tree = try #require(m[r.elementMap["ME1"]])
        #expect(tree.category == .ifcReference)
        #expect(tree.referenceGeometry?.ifcType == "Revit: Planting")
        #expect(tree.referenceGeometry?.properties["Species"] == "Oak")
        #expect(tree.name == "Tree (reference)")
        #expect(tree.levelID == r.elementMap["L1"])
    }

    @Test func doorsAndWindows() throws {
        let (m, r) = try Fixture.project()
        let door = try #require(m[r.elementMap["D1"]])
        #expect(door.hostID == r.elementMap["W4"])
        #expect(door.mark == "101")
        #expect(door.params[Parameters.familyParamID("Leaf Label")] == .text("Entrance"))
        #expect(door.params[Parameters.familyParamID("Unknown Parameter")] == nil)
        let ins = try #require(door.insert)
        #expect(!ins.facingFlipped && !ins.handFlipped)
        #expect(near(ins.sillHeight, 0))
        let size = try #require(InsertGeometry.openingSize(door, m))
        #expect(near(size.width, 1.015) && near(size.height, 2.184))
        // Type values and materials land on the project type.
        let doorType = try #require(m.type(of: door))
        #expect(doorType.name == "0915 x 2134mm")
        #expect(doorType.typeData?.params[ParameterID("type.mark")] == .text("D1"))
        #expect(m[doorType.typeData?.params[Parameters.familyParamID("Panel Material")]?.refValue]?.name == "Oak Flooring")
        // Fixed material on the frame solid became a material parameter.
        #expect(doorType.typeData?.params.keys.contains { $0.key.hasPrefix("family:Material: ") } == true)
        #expect(!InsertGeometry.meshParts(door, m).isEmpty)

        let window = try #require(m[r.elementMap["WN1"]])
        let wi = try #require(window.insert)
        #expect(wi.facingFlipped && wi.handFlipped)
        #expect(near(wi.sillHeight, 0.9))
        let ws = try #require(InsertGeometry.openingSize(window, m))
        #expect(near(ws.width, 0.915) && near(ws.height, 1.22))
    }

    @Test func importedElementsStayEditable() throws {
        let (m0, r) = try Fixture.project()
        let door = try #require(r.elementMap["D1"])
        let doorType = try #require(r.elementMap["door-0915"])
        // Change the door type's Width: the opening follows.
        var tx = TransactionContext(model: m0, name: "Widen door")
        tx.update(doorType) { $0.typeData?.params[Parameters.familyParamID("Width")] = .double(1.2) }
        let m1 = try tx.commit().model
        let door1 = try #require(m1[door])
        let s1 = try #require(InsertGeometry.openingSize(door1, m1))
        #expect(near(s1.width, 1.3))
        // Swap to the other imported type.
        tx = TransactionContext(model: m1, name: "Swap door type")
        tx.update(door) { $0.typeID = r.elementMap["door-0813"] }
        let m2 = try tx.commit().model
        let door2 = try #require(m2[door])
        #expect(near(InsertGeometry.openingSize(door2, m2)?.width, 0.913))
        // Walls are native: change the type and move the wall.
        let w1 = try #require(r.elementMap["W1"])
        tx = TransactionContext(model: m2, name: "Edit wall")
        tx.update(w1) {
            $0.typeID = r.elementMap["wt-int"]
            $0.wall?.location = .line(Segment2(Vec2(0, 0), Vec2(0, 9)))
        }
        let m3 = try tx.commit().model
        let wall3 = try #require(m3[w1])
        let f = try #require(WallGeometry.frame(wall3, m3))
        #expect(near(f.thickness, 0.138))
        #expect(near(f.length, 9))
        // Room number is an ordinary parameter.
        tx = TransactionContext(model: m3, name: "Renumber")
        tx.update(try #require(r.elementMap["RM1"])) { $0.room?.number = "102" }
        #expect(try tx.commit().model[r.elementMap["RM1"]]?.room?.number == "102")
    }

    @Test func identityComesFromRevitUniqueIds() throws {
        let (m, r) = try Fixture.project()
        #expect(m[r.elementMap["W1"]]?.ifcGUID == IFCGUID.deterministic("revit-uniqueid:sh-wall-1"))
        #expect(m[r.elementMap["D1"]]?.ifcGUID == ExchangeImportSession.guid(forUniqueId: "sh-door-1"))
        #expect(m[r.elementMap["W1"]]?.source?.originalID == "sh-wall-1")
        #expect(m[r.elementMap["W1"]]?.source?.fileName == "Small House.rvt")
        // Same GUIDs in an unrelated model.
        let (m2, r2) = try Fixture.project()
        for key in ["W1", "W2", "D1", "WN1", "F1", "R1", "RM1", "L1", "fam-door", "door-0915"] {
            #expect(m[r.elementMap[key]]?.ifcGUID == m2[r2.elementMap[key]]?.ifcGUID, "\(key)")
        }
        // All GUIDs are valid and unique.
        let guids = m.allElements.map(\.ifcGUID.value)
        #expect(Set(guids).count == guids.count)
        #expect(m.allElements.allSatisfy { $0.ifcGUID.isValid })
    }

    @Test func reimportUpdatesInPlace() throws {
        let data = try Fixture.data("small-project.arcusx")
        let (m1, r1) = try Fixture.importAndCommit(data)
        // Move a wall in the "new export" and import again.
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"start\": [10, 8], \"end\": [10, 0]", with: "\"start\": [10, 8.5], \"end\": [10, 0]")
        let (m2, r2) = try Fixture.importAndCommit(Data(json.utf8), into: m1)
        #expect(m2.count == m1.count)
        #expect(r2.created.isEmpty, "created: \(r2.created)")
        #expect(r2.updated["walls"] == 4)
        #expect(r2.updated["doors"] == 1)
        #expect(r2.updated["families"] == 4)
        #expect(r2.elementMap["W1"] == r1.elementMap["W1"])
        #expect(r2.elementMap["D1"] == r1.elementMap["D1"])
        #expect(m2[r1.elementMap["W3"]]?.wall?.location.start == Vec2(10, 8.5))
        #expect(m2.levels.map(\.name) == ["Level 1", "Level 2"])

        // Keep policy leaves existing elements alone.
        var keep = ExchangeImportOptions()
        keep.existingElements = .keep
        let (m3, r3) = try Fixture.importAndCommit(data, into: m2, options: keep)
        #expect(m3.count == m2.count)
        #expect(r3.kept["walls"] == 4)
        #expect(m3[r1.elementMap["W3"]]?.wall?.location.start == Vec2(10, 8.5))

        // Duplicate policy creates new elements with new GlobalIds.
        var dup = ExchangeImportOptions()
        dup.existingElements = .duplicate
        let (m4, r4) = try Fixture.importAndCommit(data, into: m3, options: dup)
        #expect(r4.created("walls") == 4)
        #expect(m4.elements(.walls).count == 8)
        #expect(Set(m4.allElements.map(\.ifcGUID.value)).count == m4.count)
        #expect(m4.levels.count == 2, "levels with the same name and elevation are merged")
    }

    @Test func importsIntoATemplateProject() throws {
        let (template, _) = ProjectTemplates.make(.architectural, units: .metric, projectName: "Target")
        let (m, r) = try Fixture.importAndCommit(try Fixture.data("small-project.arcusx"), into: template)
        // "Level 1" at 0 m exists in the template and is reused; "Level 2" (4 m in the template) clashes and is renamed.
        #expect(r.kept["levels"] == 1)
        #expect(m.level(named: "Level 2 (Revit)") != nil)
        #expect(r.hasWarning("level.renamed"))
        #expect(m.elements(.walls).count == 4)
        #expect(m.projectInfo.projectName == "Small House")
    }

    @Test func unitsAreAppliedOnlyWhenAsked() throws {
        var o = ExchangeImportOptions()
        #expect(try Fixture.importAndCommit(try Fixture.data("small-project.arcusx"), options: o).0.units.system == .metric)
        o.applyUnits = true
        #expect(try Fixture.importAndCommit(try Fixture.data("small-project.arcusx"), options: o).0.units.system == .imperial)
    }
}

@Suite("Arcus Exchange import — robustness")
struct ExchangeRobustnessTests {
    static func doc(_ body: String, version: String = "1.0") -> Data {
        Data("""
        {"format": "arcus-exchange", "schemaVersion": "\(version)", "documentKind": "project", \(body)}
        """.utf8)
    }

    @Test func rejectsNewerMajorVersion() {
        let tx = TransactionContext(model: BIMModel(), name: "x")
        do {
            _ = try ArcusExchangeImporter.import(data: Self.doc("\"walls\": []", version: "2.0"), into: tx)
            Issue.record("expected an error")
        } catch {
            #expect(error == .unsupportedSchemaVersion(found: "2.0", supported: "1.0"))
            #expect(error.description.contains("newer than this version of Arcus"))
        }
        #expect(!tx.hasChanges)
    }

    @Test func versionAndFormatChecks() throws {
        func err(_ d: Data) -> ExchangeImportError? {
            do { _ = try ArcusExchangeImporter.decode(d); return nil } catch { return error }
        }
        #expect(err(Data("{\"schemaVersion\": \"1.0\"}".utf8)) == .notArcusExchange)
        #expect(err(Data("{\"format\": \"arcus-exchange\"}".utf8)) == .missingSchemaVersion)
        #expect(err(Data("{\"format\": \"arcus-exchange\", \"schemaVersion\": \"one\"}".utf8)) == .invalidSchemaVersion("one"))
        #expect(err(Data("{\"format\": \"arcus-exchange\", \"schemaVersion\": 1}".utf8)) == .invalidSchemaVersion("(not text)"))
        #expect(err(Data("{\"format\": \"arcus-exchange\", \"schemaVersion\": \"0.9\"}".utf8)) == .invalidSchemaVersion("0.9"))
        #expect(err(Data("{\"format\": \"arcus-exchange\", \"schemaVersion\": \"1.0\", \"documentKind\": \"drawing\"}".utf8)) == .unknownDocumentKind("drawing"))
        if case .notJSON? = err(Data("not json".utf8)) {} else { Issue.record("expected notJSON") }
        if case .notJSON? = err(Data("[1, 2, 3]".utf8)) {} else { Issue.record("expected notJSON") }
        // A newer minor version imports with a warning.
        let tx = TransactionContext(model: BIMModel(), name: "x")
        let r = try ArcusExchangeImporter.import(data: Self.doc("\"levels\": [{\"id\": \"L\", \"elevation\": 0}]", version: "1.7"), into: tx)
        #expect(r.hasWarning("schema.newerMinor"))
        #expect(r.created("levels") == 1)
    }

    @Test func badReferencesAndMalformedItemsBecomeWarnings() throws {
        let data = Self.doc("""
        "levels": [{"id": "L1", "name": "Ground", "elevation": 0}],
        "walls": [
          {"id": "W1", "typeId": "missing-type", "levelId": "L1", "curve": {"type": "line", "start": [0, 0], "end": [5, 0]}, "unconnectedHeight": 3},
          {"id": "W2", "levelId": "nope", "curve": {"type": "line", "start": [0, 5], "end": [5, 5]}},
          {"id": "W3", "curve": 5},
          {"id": "W4", "levelId": "L1", "curve": {"type": "line", "start": [0, 0], "end": [0, 0]}},
          {"id": "W5", "levelId": "L1", "curve": {"type": "line", "start": [1e300, 0], "end": [0, 0]}},
          {"id": "W6", "levelId": "L1", "curve": {"type": "line", "start": [0, 0], "end": [0, 4]}, "baseOffset": 2, "unconnectedHeight": -5},
          {"id": "W7", "levelId": "L1", "curve": {"type": "spline", "start": [0, 0], "end": [0, 4]}}
        ],
        "inserts": [
          {"id": "D1", "hostId": "W99", "typeId": "x", "location": [1, 0, 0]},
          {"id": "D2", "hostId": "W1", "typeId": "missing", "location": [1, 0, 0]}
        ],
        "floors": [{"id": "F1", "levelId": "L1", "boundary": [[{"type": "line", "start": [0, 0], "end": [4, 4]}, {"type": "line", "start": [4, 0], "end": [0, 4]}]]}],
        "roofs": [{"id": "R1", "levelId": "L1", "kind": "extrusion"}],
        "rooms": [{"id": "R1", "name": "Unplaced"}],
        "stairs": [{"id": "S1", "levelId": "L1", "shape": "spiral"}],
        "meshes": [{"id": "M1", "positions": [0, 0, 0, 1, 0, 0, 0, 1, 0], "indices": [0, 1, 7]}],
        "components": [{"id": "C1", "typeId": "nothing"}],
        "grids": 7,
        "futureSection": {"anything": [1, 2, 3]}
        """)
        let (m, r) = try Fixture.importAndCommit(data)
        #expect(r.created("walls") == 2)
        #expect(m.elements(.walls).count == 2)
        #expect(r.skipped["walls"] == 5)
        #expect(r.hasWarning("ref.type"))
        #expect(r.hasWarning("ref.level"))
        #expect(r.hasWarning("file.item"))
        #expect(r.hasWarning("file.section"))
        #expect(r.hasWarning("wall.curve"))
        #expect(r.hasWarning("wall.height"))
        #expect(r.hasWarning("insert.host"))
        #expect(r.hasWarning("insert.type"))
        #expect(r.hasWarning("slab.boundary"))
        #expect(r.hasWarning("roof.kind"))
        #expect(r.hasWarning("room.unplaced"))
        #expect(r.hasWarning("stair.shape"))
        #expect(r.hasWarning("mesh.invalid"))
        #expect(r.hasWarning("component.type"))
        #expect(r.skipped["doors"] == 2)
        // The fallback wall type is reported and usable.
        let w1 = try #require(m[r.elementMap["W1"]])
        #expect(m.type(of: w1)?.name.contains("type missing") == true)
        // Every warning points at its source object where there is one.
        #expect(r.warnings.first { $0.code == "insert.host" }?.sourceID == "D1")
        #expect(!r.summary.isEmpty)
    }

    @Test func sizeAndCountLimits() throws {
        let data = try Fixture.data("small-project.arcusx")
        var o = ExchangeImportOptions()
        o.maxInputBytes = 100
        #expect(throws: ExchangeImportError.self) { try ArcusExchangeImporter.decode(data, options: o) }
        o = ExchangeImportOptions()
        o.maxObjects = 5
        do { _ = try ArcusExchangeImporter.decode(data, options: o); Issue.record("expected an error") } catch {
            if case .tooManyObjects = error {} else { Issue.record("unexpected \(error)") }
        }
        // Mesh limits: meshes over the cap are skipped, the rest imports.
        o = ExchangeImportOptions()
        o.maxTrianglesPerMesh = 1
        let (m, r) = try Fixture.importAndCommit(data, options: o)
        #expect(r.referenceMeshes.isEmpty)
        #expect(m.elements(.walls).count == 4)
        #expect(r.skipped["reference meshes"] == 1)
        #expect(r.skipped["walls"] == 1)
    }

    @Test func hostileJSONDoesNotCrash() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        let bodies = [
            deep,
            "{\"format\": \"arcus-exchange\", \"schemaVersion\": \"1.0\", \"walls\": \(deep)}",
            "{\"format\": \"arcus-exchange\", \"schemaVersion\": \"1.0\", \"walls\": [{\"curve\": {\"type\": \"line\", \"start\": [1e999, 0], \"end\": [0, 0]}}]}",
            "{\"format\": \"arcus-exchange\", \"schemaVersion\": \"1.0\", \"meshes\": [{\"positions\": [0, 0, 0, 1, 0, 0, 0, 1, 0], \"indices\": [-1, 0, 1]}]}",
            "{\"format\": \"arcus-exchange\", \"schemaVersion\": \"1.0\", \"families\": [{\"name\": \"X\", \"parameters\": [{\"name\": \"A\", \"dataType\": \"length\", \"formula\": \"A + 1 m\"}], \"geometry\": [{\"kind\": \"extrusion\", \"extent\": [0, \"A\"], \"loops\": [[]]}]}]}",
            "\u{0}\u{1}\u{2}",
        ]
        for b in bodies {
            let tx = TransactionContext(model: BIMModel(), name: "x")
            if (try? ArcusExchangeImporter.import(data: Data(b.utf8), into: tx)) != nil {
                #expect((try? tx.commit()) != nil)
            }
        }
    }

    @Test func emptyDocumentImportsNothing() throws {
        let (m, r) = try Fixture.importAndCommit(Self.doc("\"walls\": []"))
        #expect(r.totalCreated == 0)
        #expect(m.count == 0)
        #expect(r.summary == "Nothing was imported.")
    }
}
