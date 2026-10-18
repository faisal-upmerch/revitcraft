import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

@Suite("IFC round trip")
struct RoundTripTests {
    static let productTypes = ["IfcWall", "IfcWallStandardCase", "IfcDoor", "IfcWindow", "IfcSlab", "IfcSpace", "IfcColumn", "IfcRoof"]

    @Test(arguments: IFCSchema.allCases)
    func exportImportPreservesTheModel(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let src = b.model
        let (d, _) = try TestModel.export(src, TestModel.options(schema))
        let (m, r, m0) = try TestModel.importIntoTemplate(d)

        // Levels: all three storeys match the template levels; nothing new created.
        #expect(m.levels.count == m0.levels.count)
        #expect(r.nativeCounts["levels"] == nil)
        #expect(r.nativeCounts == ["walls": 4, "doors": 1, "windows": 1, "floors": 1, "rooms": 1, "columns": 1])
        #expect(r.referenceCounts == ["IfcRoof": 1])

        // Walls: count, lengths, thickness, type and layer materials.
        let walls = m.elements(.walls)
        #expect(walls.count == 4)
        let lengths = walls.map { WallGeometry.frame($0, m)!.length }.sorted()
        #expect(zip(lengths, [8.0, 8, 10, 10]).allSatisfy { abs($0 - $1) < 1e-6 })
        let srcFrame = WallGeometry.frame(src[b.walls[0]]!, src)!
        for w in walls {
            let f = WallGeometry.frame(w, m)!
            #expect(abs(f.thickness - srcFrame.thickness) < 1e-6)
            #expect(abs(f.baseZ - srcFrame.baseZ) < 1e-6 && abs(f.topZ - srcFrame.topZ) < 1e-6)
            #expect(m.type(of: w)?.name == "Exterior - Brick on CMU")
            // Faces coincide with the source wall faces (same GUID).
            let s = src.allElements.first { $0.ifcGUID == w.ifcGUID }!
            let sf = WallGeometry.frame(s, src)!
            #expect(f.exteriorFace.start.isAlmostEqual(sf.exteriorFace.start, tolerance: 1e-6))
            #expect(f.interiorFace.end.isAlmostEqual(sf.interiorFace.end, tolerance: 1e-6))
        }
        let layerNames = m.type(of: walls[0])!.typeData!.assembly!.layers.compactMap { m[$0.materialID]?.name }
        #expect(layerNames == ["Brick, Common", "Rigid Insulation", "Concrete Masonry Units", "Plaster"])

        // Doors and windows: sizes, sill, host, location.
        let door = try #require(m.elements(.doors).first)
        let window = try #require(m.elements(.windows).first)
        func size(_ e: Element) -> (Double, Double) {
            (Parameters.value(Parameters.familyParamID("Width"), of: e, m)!.doubleValue!, Parameters.value(Parameters.familyParamID("Height"), of: e, m)!.doubleValue!)
        }
        #expect(size(door) == (0.9, 2.1))
        #expect(size(window) == (1.2, 1.5))
        #expect(m.type(of: door)?.name == "900 x 2100" && m.type(of: window)?.name == "1200 x 1500")
        #expect(door.insert!.location.isAlmostEqual(Vec2(5, 0), tolerance: 1e-6))
        #expect(window.insert!.location.isAlmostEqual(Vec2(10, 4), tolerance: 1e-6))
        #expect(abs(window.insert!.sillHeight - 0.9) < 1e-6)
        #expect(m[door.hostID]?.ifcGUID == src[b.walls[0]]!.ifcGUID)
        #expect(m[window.hostID]?.ifcGUID == src[b.walls[1]]!.ifcGUID)
        #expect(WallGeometry.openings(m[door.hostID]!, m).count == 1)

        // Room: name, number and computed area.
        let room = try #require(m.elements(.rooms).first)
        #expect(room.name == "Office" && room.room?.number == "101")
        let srcArea = RoomGeometry.boundary(src[b.room]!, src).area
        let area = RoomGeometry.boundary(room, m).area
        #expect(srcArea > 60 && abs(area - srcArea) < 1e-3)

        // Floor and column.
        let floor = try #require(m.elements(.floors).first)
        #expect(abs(SlabGeometry.profile(floor)!.area - 80) < 1e-6)
        #expect(m.type(of: floor)?.name == "Concrete Slab 200mm")
        let column = try #require(m.elements(.columns).first)
        #expect(column.column!.location.isAlmostEqual(Vec2(3, 3), tolerance: 1e-6))
        #expect(m.type(of: column)?.name == "Concrete Column 400 x 400")

        // Properties and classification on the marked wall.
        let w0 = try #require(walls.first { $0.ifcGUID == src[b.walls[0]]!.ifcGUID })
        #expect(w0.mark == "W-01")
        #expect(w0.comments == "South façade")
        #expect(w0.classification == Classification(system: "Uniclass 2015", code: "EF_25_10", title: "Walls"))
        #expect(w0.source?.attributes["Pset_WallCommon.IsExternal"] == "TRUE")

        // GUID preservation for every exported product.
        for id in b.walls + [b.door, b.window, b.floor, b.room, b.column, b.roof] {
            let g = src[id]!.ifcGUID
            #expect(m.allElements.contains { $0.ifcGUID == g }, "missing GUID of \(src[id]!.category)")
        }

        // Export again: the same product GUIDs come out.
        let (d2, _) = try TestModel.export(m, TestModel.options(schema))
        let g1 = try TestModel.parse(d).globalIds(Self.productTypes)
        let g2 = try TestModel.parse(d2).globalIds(Self.productTypes)
        #expect(g1.count == 10)
        #expect(g1 == g2)
    }

    @Test func crossSchemaRoundTripOfReferenceElements() throws {
        // IFC2X3 fixture → Arcus → IFC4 and IFC2X3: the unsupported IfcFlowSegment survives as itself with its GUID and property set.
        let (m, _, _) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc2x3.ifc"))
        for schema in IFCSchema.allCases {
            let (d, r) = try TestModel.export(m, TestModel.options(schema))
            let f = try TestModel.parse(d)
            let seg = try #require(f.all("IFCFLOWSEGMENT").first)
            #expect(seg[0].stringValue == "0ArcusFixturesPipe2x31")
            #expect(seg[2].stringValue == "Rohr DN100")
            #expect(f.all("IFCPROPERTYSET").contains { $0[2].stringValue == "Pset_PipeSegmentTypeCommon" })
            let furn = schema == .ifc4 ? "IFCFURNITURE" : "IFCFURNISHINGELEMENT"
            #expect(f.all(furn).first?[0].stringValue == "0ArcusFixturesFurn2x31")
            #expect(!r.warnings.contains { $0.contains("IfcBuildingElementProxy") })
            // And back in again: still a reference of the same class.
            let (m2, r2, _) = try TestModel.importIntoTemplate(d)
            #expect(r2.referenceCounts["IfcFlowSegment"] == 1)
            #expect(m2.elements(.ifcReference).contains { $0.ifcGUID.value == "0ArcusFixturesPipe2x31" })
        }
    }

    @Test func referenceClassMissingFromTargetSchemaFallsBack() throws {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Ref")
        let mesh = Mesh.box(Box3(min: .zero, max: Vec3(1, 1, 1)))
        tx.create(.ifcReference, name: "Pump", data: .referenceGeometry(ReferenceGeometryData(mesh: mesh, ifcType: "IfcPump", properties: ["Name": "Pump"])),
                  levelID: m0.levels[0].id)
        tx.create(.ifcReference, name: "Thing", data: .referenceGeometry(ReferenceGeometryData(mesh: mesh, ifcType: "IfcMadeUpClass")), levelID: m0.levels[0].id)
        let m = try tx.commit().model
        let (d3, r3) = try TestModel.export(m, TestModel.options(.ifc2x3))
        let f3 = try TestModel.parse(d3)
        #expect(f3.count("IfcFlowMovingDevice") == 1)
        #expect(f3.count("IfcBuildingElementProxy") == 1)
        #expect(r3.warnings.contains { $0.contains("IfcMadeUpClass") })
        let f4 = try TestModel.parse(try TestModel.export(m, TestModel.options(.ifc4)).0)
        #expect(f4.count("IfcPump") == 1)
    }
}
