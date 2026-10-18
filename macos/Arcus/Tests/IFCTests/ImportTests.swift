import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

@Suite("IFC import")
struct ImportTests {
    func near(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

    @Test func ifc4MillimetreFixtureMapsToNativeElements() throws {
        let (m, r, m0) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc4-mm.ifc"), fileName: "small-ifc4-mm.ifc")
        #expect(r.schema == "IFC4")
        #expect(r.fileName == "small-ifc4-mm.ifc")
        #expect(r.entityCount == 104)
        #expect(r.nativeCounts["walls"] == 1 && r.nativeCounts["doors"] == 1 && r.nativeCounts["floors"] == 1 && r.nativeCounts["rooms"] == 1)
        #expect(r.referenceCounts == ["IfcBuildingElementProxy": 2])
        #expect(r.warnings.contains { $0.contains("boolean") })

        // Levels: "Ground Floor" (0 m) reuses Level 1; "Upper Floor" (3.5 m) is created with a plan view.
        #expect(m.levels.count == m0.levels.count + 1)
        let upper = try #require(m.level(named: "Upper Floor"))
        #expect(near(upper.level!.elevation, 3.5))
        #expect(upper.ifcGUID.value == "0ArcusFixturesStor0002")
        #expect(m.views.contains { $0.name == "Upper Floor" && $0.levelID == upper.id })

        let wall = try #require(m.elements(.walls).first)
        let w = wall.wall!
        let seg = try #require(w.location.asSegment)
        #expect(seg.start.isAlmostEqual(Vec2(1, 2), tolerance: 1e-9) && seg.end.isAlmostEqual(Vec2(7, 2), tolerance: 1e-9))
        #expect(near(w.unconnectedHeight, 3) && w.topLevelID == nil && near(w.baseOffset, 0))
        #expect(w.structural)
        #expect(wall.ifcGUID.value == "0ArcusFixturesWall0001")
        #expect(wall.levelID == m0.level(named: "Level 1")!.id)
        #expect(wall.mark == "W-7")
        let wt = try #require(m.type(of: wall))
        #expect(wt.name == "Concrete 200")
        #expect(near(wt.typeData!.assembly!.totalThickness, 0.2))
        #expect(m[wt.typeData!.assembly!.layers[0].materialID]?.name == "Concrete")
        #expect(wall.source?.format == "IFC4")
        #expect(wall.source?.originalType == "IfcWall")
        #expect(wall.source?.attributes["Pset_WallCommon.Height"] == "3") // length measure converted from mm

        let door = try #require(m.elements(.doors).first)
        #expect(door.hostID == wall.id)
        #expect(door.insert!.location.isAlmostEqual(Vec2(3.5, 2), tolerance: 1e-6))
        #expect(near(door.insert!.sillHeight, 0))
        #expect(m.type(of: door)?.name == "900 x 2100") // matched the starter family type
        #expect(door.mark == "D-1")

        let floor = try #require(m.elements(.floors).first)
        #expect(near(SlabGeometry.profile(floor)!.area, 24))
        #expect(near(floor.slab!.offset, 0))
        #expect(near(SlabGeometry.thickness(floor, m), 0.2))

        let room = try #require(m.elements(.rooms).first)
        #expect(room.name == "Kitchen" && room.room?.number == "R1")
        #expect(Rect2(min: Vec2(1, 2.1), max: Vec2(5, 5.1)).contains(room.room!.point))
        #expect(near(room.room!.limitOffset, 2.7))

        let proxies = m.elements(.ifcReference)
        #expect(proxies.count == 2)
        let planter = try #require(proxies.first { $0.name == "Planter" })
        #expect(planter.levelID == upper.id)
        let bb = planter.referenceGeometry!.mesh.bounds
        #expect(bb.min.isAlmostEqual(Vec3(2, 3, 3.5), tolerance: 1e-9) && bb.max.isAlmostEqual(Vec3(2.5, 3.4, 3.8), tolerance: 1e-9))
        #expect(planter.referenceGeometry?.properties["ObjectType"] == "Planter Box")
        #expect(planter.referenceGeometry?.ifcType == "IfcBuildingElementProxy")
    }

    @Test func ifc2x3FixtureKeepsUnsupportedElementsAsReferences() throws {
        let (m, r, _) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc2x3.ifc"))
        #expect(r.schema == "IFC2X3")
        #expect(r.nativeCounts["walls"] == 1 && r.nativeCounts["floors"] == 1 && r.nativeCounts["rooms"] == 1)
        #expect(r.referenceCounts == ["IfcFlowSegment": 1, "IfcFurnishingElement": 1])
        #expect(r.unsupported.isEmpty)

        let wall = try #require(m.elements(.walls).first)
        let seg = try #require(wall.wall!.location.asSegment)
        #expect(seg.start.isAlmostEqual(Vec2(0, 0), tolerance: 1e-9) && seg.end.isAlmostEqual(Vec2(0, 4), tolerance: 1e-9))
        #expect(abs(WallGeometry.frame(wall, m)!.thickness - 0.25) < 1e-9)
        #expect(abs(wall.wall!.unconnectedHeight - 2.8) < 1e-9)
        #expect(wall.source?.attributes["Name"] == "Wand Süd")
        #expect(m.type(of: wall)?.name == "Imported 250 mm")

        let floor = try #require(m.elements(.floors).first)
        #expect(abs(SlabGeometry.profile(floor)!.area - 20) < 1e-9)
        #expect(abs(SlabGeometry.thickness(floor, m) - 0.25) < 1e-9)

        let room = try #require(m.elements(.rooms).first)
        #expect(room.name == "Büro" && room.room?.number == "001")

        let pipe = try #require(m.elements(.ifcReference).first { $0.referenceGeometry?.ifcType == "IfcFlowSegment" })
        #expect(pipe.name == "Rohr DN100")
        #expect(pipe.ifcGUID.value == "0ArcusFixturesPipe2x31")
        let props = pipe.referenceGeometry!.properties
        #expect(props["Pset_PipeSegmentTypeCommon.System"] == "Kältewasser")
        #expect(props["Pset_PipeSegmentTypeCommon.NominalDiameter"] == "0.1")
        #expect(props["GlobalId"] == "0ArcusFixturesPipe2x31" && props["ObjectType"] == "Pipe")
        let pb = pipe.referenceGeometry!.mesh.bounds
        #expect(abs(pb.min.x - 0.5) < 1e-9 && abs(pb.max.x - 3.5) < 1e-9 && abs(pb.max.z - 2.55) < 1e-3)
        #expect(pipe.source?.format == "IFC2X3" && pipe.source?.originalType == "IfcFlowSegment")
    }

    @Test func mappedItemsArePlacedByTheirTransformationOperator() throws {
        let (m, _, _) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc2x3.ifc"))
        let desk = try #require(m.elements(.ifcReference).first { $0.referenceGeometry?.ifcType == "IfcFurnishingElement" })
        #expect(desk.name == "Schreibtisch Übung")
        let mesh = desk.referenceGeometry!.mesh
        #expect(mesh.triangleCount == 24) // two mapped boxes
        let bb = mesh.bounds
        #expect(bb.min.isAlmostEqual(Vec3(2.6, 0.7, 0), tolerance: 1e-9))
        #expect(bb.max.isAlmostEqual(Vec3(3.4, 2.8, 0.75), tolerance: 1e-9))
    }

    @Test func feetUnitsAndPlacementChains() throws {
        let (m, r, _) = try TestModel.importIntoTemplate(try TestModel.fixture("units-feet.ifc"))
        #expect(r.referenceCounts == ["IfcBuildingElementProxy": 1])
        let level = try #require(m.level(named: "Level 10ft"))
        #expect(abs(level.level!.elevation - 3.048) < 1e-9)
        let crate = try #require(m.elements(.ifcReference).first)
        #expect(crate.levelID == level.id)
        let bb = crate.referenceGeometry!.mesh.bounds
        let ft = 0.3048
        #expect(bb.min.isAlmostEqual(Vec3(95 * ft, 60 * ft, 10 * ft), tolerance: 1e-9))
        #expect(bb.max.isAlmostEqual(Vec3(100 * ft, 70 * ft, 12 * ft), tolerance: 1e-9))
    }

    @Test func unitConversionTable() throws {
        func unitFile(_ units: String) -> Data {
            STEPParserTests.wrap("""
            \(units)
            #100=IFCPROJECT('0ArcusFixturesProjUnit',$,'U',$,$,$,$,$,#9);
            """)
        }
        let cases: [(String, Double)] = [
            ("#1=IFCSIUNIT(*,.LENGTHUNIT.,.CENTI.,.METRE.);#9=IFCUNITASSIGNMENT((#1));", 0.01),
            ("#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);#2=IFCMEASUREWITHUNIT(IFCLENGTHMEASURE(0.0254),#1);#3=IFCCONVERSIONBASEDUNIT($,.LENGTHUNIT.,'INCH',#2);#9=IFCUNITASSIGNMENT((#3));", 0.0254),
            ("#1=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);#2=IFCMEASUREWITHUNIT(IFCLENGTHMEASURE(304.8),#1);#3=IFCCONVERSIONBASEDUNIT($,.LENGTHUNIT.,'FOOT',#2);#9=IFCUNITASSIGNMENT((#3));", 0.3048),
        ]
        for (u, expected) in cases {
            let s = try IFCImportSession(file: try STEPParser.parse(unitFile(u)), fileName: "u", options: IFCImportOptions())
            #expect(abs(s.lengthScale - expected) < 1e-12)
        }
        let none = try IFCImportSession(file: try STEPParser.parse(unitFile("#9=IFCUNITASSIGNMENT(());")), fileName: "u", options: IFCImportOptions())
        #expect(none.lengthScale == 1)
        #expect(none.report.warnings.contains { $0.contains("meters were assumed") })
    }

    @Test func hostileInputDoesNotCrash() throws {
        let (m, r, _) = try TestModel.importIntoTemplate(try TestModel.fixture("hostile-cycles.ifc"))
        #expect(r.referenceCounts["IfcBuildingElementProxy"] == 3)
        #expect(m.elements(.ifcReference).count == 3)
        let bad = try #require(m.elements(.ifcReference).first { $0.name == "Bad Indices" })
        #expect(bad.referenceGeometry!.indices.count == 3) // only the valid triangle survives
        #expect(!r.warnings.isEmpty)
    }

    @Test func malformedInputThrowsAndLeavesTransactionUntouched() throws {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        for name in ["truncated.ifc", "malformed.ifc"] {
            let tx = TransactionContext(model: m0, name: "Import")
            #expect(throws: IFCError.self) { try IFCImporter.importFile(try TestModel.fixture(name), fileName: name, into: tx) }
            #expect(!tx.hasChanges)
        }
        let noProject = STEPParserTests.wrap("#1=IFCWALL('0ArcusFixturesWall9999',$,$,$,$,$,$,$);")
        let tx = TransactionContext(model: m0, name: "Import")
        #expect(throws: IFCError.self) { try IFCImporter.importFile(noProject, fileName: "x", into: tx) }
        let ifc5 = STEPParserTests.wrap("#1=IFCPROJECT('0ArcusFixturesProj9999',$,$,$,$,$,$,$,$);", schema: "IFC5")
        do {
            _ = try IFCImporter.importFile(ifc5, fileName: "x", into: tx)
            Issue.record("expected error")
        } catch let e as IFCError {
            #expect(e.message.contains("IFC5"))
        }
        #expect(!tx.hasChanges)
    }

    @Test func cancellationLeavesTransactionUntouched() throws {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Import")
        #expect(throws: IFCError.self) {
            try IFCImporter.importFile(try TestModel.fixture("small-ifc4-mm.ifc"), fileName: "x", into: tx, isCancelled: { true })
        }
        #expect(!tx.hasChanges)
    }

    @Test func mapToNativeOffKeepsEverythingAsReference() throws {
        var o = IFCImportOptions()
        o.mapToNative = false
        let (m, r, _) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc4-mm.ifc"), options: o)
        #expect(r.nativeCounts["walls"] == nil && r.nativeCounts["rooms"] == nil)
        #expect(r.referenceCounts == ["IfcWall": 1, "IfcDoor": 1, "IfcSlab": 1, "IfcSpace": 1, "IfcBuildingElementProxy": 2])
        #expect(m.elements(.walls).isEmpty)
        let wall = try #require(m.elements(.ifcReference).first { $0.referenceGeometry?.ifcType == "IfcWall" })
        #expect(abs(abs(wall.referenceGeometry!.mesh.signedVolume) - 6 * 0.2 * 3) < 1e-9)
    }

    @Test func repeatedImportAssignsFreshGUIDs() throws {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Import twice")
        let d = try TestModel.fixture("small-ifc2x3.ifc")
        _ = try IFCImporter.importFile(d, fileName: "a.ifc", into: tx)
        let r2 = try IFCImporter.importFile(d, fileName: "a.ifc", into: tx)
        #expect(r2.warnings.contains { $0.contains("GlobalId") })
        let m = try tx.commit().model
        let guids = m.allElements.map(\.ifcGUID.value)
        #expect(Set(guids).count == guids.count)
        #expect(m.elements(.walls).count == 2)
    }

    @Test func levelMatchToleranceIsHonoured() throws {
        var o = IFCImportOptions()
        o.targetLevelMatchTolerance = 0.6 // 3.5 m storey now matches Level 2 at 4.0 m
        let (m, r, m0) = try TestModel.importIntoTemplate(try TestModel.fixture("small-ifc4-mm.ifc"), options: o)
        #expect(m.levels.count == m0.levels.count)
        #expect(r.nativeCounts["levels"] == nil)
        let planter = try #require(m.elements(.ifcReference).first { $0.name == "Planter" })
        #expect(planter.levelID == m0.level(named: "Level 2")!.id)
    }

    @Test func geometryEvaluatorProfilesAndCurves() throws {
        let d = STEPParserTests.wrap("""
        #1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);#2=IFCUNITASSIGNMENT((#1));
        #3=IFCPROJECT('0ArcusFixturesProjGeom',$,'G',$,$,$,$,$,#2);
        #10=IFCCARTESIANPOINT((0.,0.));#11=IFCCARTESIANPOINT((2.,0.));#12=IFCCARTESIANPOINT((2.,2.));#13=IFCCARTESIANPOINT((0.,2.));
        #14=IFCLINE(#10,#15);#15=IFCVECTOR(#16,1.);#16=IFCDIRECTION((1.,0.));
        #17=IFCTRIMMEDCURVE(#14,(#10),(#11),.T.,.CARTESIAN.);
        #18=IFCPOLYLINE((#11,#12,#13,#10));
        #19=IFCCOMPOSITECURVESEGMENT(.CONTINUOUS.,.T.,#17);#20=IFCCOMPOSITECURVESEGMENT(.CONTINUOUS.,.T.,#18);
        #21=IFCCOMPOSITECURVE((#19,#20),.F.);
        #22=IFCCIRCLEPROFILEDEF(.AREA.,$,$,0.5);
        #23=IFCARBITRARYPROFILEDEFWITHVOIDS(.AREA.,$,#21,(#24));
        #24=IFCPOLYLINE((#25,#26,#27,#28,#25));#25=IFCCARTESIANPOINT((0.5,0.5));#26=IFCCARTESIANPOINT((1.5,0.5));#27=IFCCARTESIANPOINT((1.5,1.5));#28=IFCCARTESIANPOINT((0.5,1.5));
        #29=IFCRECTANGLEHOLLOWPROFILEDEF(.AREA.,$,$,1.,2.,0.1,$,$);
        #30=IFCISHAPEPROFILEDEF(.AREA.,$,$,0.2,0.4,0.01,0.02,$,$,$);
        #31=IFCCARTESIANPOINTLIST2D(((0.,0.),(2.,0.),(1.,1.),(0.,2.)));
        #32=IFCINDEXEDPOLYCURVE(#31,(IFCLINEINDEX((1,2)),IFCARCINDEX((2,3,4)),IFCLINEINDEX((4,1))),$);
        """)
        let s = try IFCImportSession(file: try STEPParser.parse(d), fileName: "g", options: IFCImportOptions())
        let g = s.geo
        #expect(abs(g.profile(.ref(23), depth: 0)!.area - 3) < 1e-9)
        #expect(abs(g.profile(.ref(22), depth: 0)!.area - .pi * 0.25) < 0.01)
        #expect(abs(g.profile(.ref(29), depth: 0)!.area - (2 - 0.8 * 1.8)) < 1e-9)
        #expect(abs(g.profile(.ref(30), depth: 0)!.area - (2 * 0.2 * 0.02 + 0.36 * 0.01)) < 1e-9)
        let arc = try #require(g.curvePoints(.ref(32), depth: 0))
        #expect(arc.count > 6)
        #expect(arc.allSatisfy { $0.xy.length <= 2 + 1e-9 })
        // Extrusion volume and orientation (outward normals → positive volume).
        let prof = try #require(g.profile(.ref(23), depth: 0))
        let mesh = g.extrude(prof, direction: .unitZ, depth: 2).domainMesh
        #expect(abs(mesh.signedVolume - 6) < 1e-9)
        let down = g.extrude(prof, direction: -.unitZ, depth: 2).domainMesh
        #expect(abs(down.signedVolume - 6) < 1e-9)
    }

    static func productFile(_ body: String) -> Data {
        STEPParserTests.wrap("""
        #1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);#2=IFCUNITASSIGNMENT((#1));
        #3=IFCPROJECT('0ArcusFixturesProjTess',$,'T',$,$,$,$,$,#2);
        #4=IFCCARTESIANPOINT((0.,0.,0.));#5=IFCAXIS2PLACEMENT3D(#4,$,$);#6=IFCLOCALPLACEMENT($,#5);
        #7=IFCBUILDINGSTOREY('0ArcusFixturesStorTess',$,'L0',$,$,#6,$,$,.ELEMENT.,0.);
        \(body)
        """)
    }

    @Test func wallWithoutAxisUsesItsBox() throws {
        let d = Self.productFile("""
        #10=IFCBLOCK(#5,5.,0.3,2.5);
        #11=IFCSHAPEREPRESENTATION($,'Body','CSG',(#10));#12=IFCPRODUCTDEFINITIONSHAPE($,$,(#11));
        #13=IFCWALL('0ArcusFixturesWallNoAx',$,'Box Wall',$,$,#6,#12,$,$);
        #14=IFCRELCONTAINEDINSPATIALSTRUCTURE('0ArcusFixturesRelCTess',$,$,$,(#13),#7);
        """)
        let (m, r, _) = try TestModel.importIntoTemplate(d)
        #expect(r.nativeCounts["walls"] == 1)
        let w = try #require(m.elements(.walls).first)
        let seg = try #require(w.wall?.location.asSegment)
        #expect(abs(seg.length - 5) < 1e-9)
        #expect(abs(seg.start.y - 0.15) < 1e-9 && abs(seg.end.y - 0.15) < 1e-9)
        #expect(abs(WallGeometry.frame(w, m)!.thickness - 0.3) < 1e-9)
        #expect(m.type(of: w)?.name == "Imported 300 mm")
    }

    @Test func tessellatedAndSurfaceModelVariants() throws {
        let d = Self.productFile("""
        #20=IFCCARTESIANPOINTLIST3D(((0.,0.,0.),(1.,0.,0.),(1.,1.,0.),(0.,1.,0.),(0.,0.,1.),(1.,0.,1.),(1.,1.,1.),(0.,1.,1.)));
        #21=IFCINDEXEDPOLYGONALFACE((1,4,3,2));#22=IFCINDEXEDPOLYGONALFACE((5,6,7,8));#23=IFCINDEXEDPOLYGONALFACE((1,2,6,5));
        #24=IFCINDEXEDPOLYGONALFACE((2,3,7,6));#25=IFCINDEXEDPOLYGONALFACE((3,4,8,7));#26=IFCINDEXEDPOLYGONALFACE((4,1,5,8));
        #27=IFCPOLYGONALFACESET(#20,.T.,(#21,#22,#23,#24,#25,#26),$);
        #28=IFCSHAPEREPRESENTATION($,'Body','Tessellation',(#27));#29=IFCPRODUCTDEFINITIONSHAPE($,$,(#28));
        #30=IFCBUILDINGELEMENTPROXY('0ArcusFixturesPolyFace',$,'Cube',$,$,#6,#29,$,$);
        #40=IFCCARTESIANPOINT((0.,0.,0.));#41=IFCCARTESIANPOINT((4.,0.,0.));#42=IFCCARTESIANPOINT((4.,4.,0.));#43=IFCCARTESIANPOINT((0.,4.,0.));
        #44=IFCCARTESIANPOINT((1.,1.,0.));#45=IFCCARTESIANPOINT((3.,1.,0.));#46=IFCCARTESIANPOINT((3.,3.,0.));#47=IFCCARTESIANPOINT((1.,3.,0.));
        #49=IFCPOLYLOOP((#40,#41,#42,#43));#50=IFCFACEOUTERBOUND(#49,.T.);#51=IFCPOLYLOOP((#44,#45,#46,#47));#52=IFCFACEBOUND(#51,.F.);
        #53=IFCFACE((#50,#52));#54=IFCOPENSHELL((#53));#55=IFCSHELLBASEDSURFACEMODEL((#54));
        #56=IFCSHAPEREPRESENTATION($,'Body','SurfaceModel',(#55));#57=IFCPRODUCTDEFINITIONSHAPE($,$,(#56));
        #58=IFCBUILDINGELEMENTPROXY('0ArcusFixturesShellMod',$,'Frame Sheet',$,$,#6,#57,$,$);
        #59=IFCRELCONTAINEDINSPATIALSTRUCTURE('0ArcusFixturesRelCTess',$,$,$,(#30,#58),#7);
        """)
        let (m, r, _) = try TestModel.importIntoTemplate(d)
        #expect(r.referenceCounts["IfcBuildingElementProxy"] == 2)
        let cube = try #require(m.elements(.ifcReference).first { $0.name == "Cube" })
        #expect(abs(abs(cube.referenceGeometry!.mesh.signedVolume) - 1) < 1e-9)
        #expect(cube.referenceGeometry!.indices.count == 36)
        let sheet = try #require(m.elements(.ifcReference).first { $0.name == "Frame Sheet" })
        #expect(abs(sheet.referenceGeometry!.mesh.surfaceArea - 12) < 1e-9) // 16 m² minus the 4 m² hole
    }

    @Test func unfilledOpeningsAreReported() throws {
        let d = Self.productFile("""
        #10=IFCBLOCK(#5,5.,0.3,2.5);
        #11=IFCSHAPEREPRESENTATION($,'Body','CSG',(#10));#12=IFCPRODUCTDEFINITIONSHAPE($,$,(#11));
        #13=IFCWALL('0ArcusFixturesWallNoAx',$,'Box Wall',$,$,#6,#12,$,$);
        #20=IFCBLOCK(#5,1.,1.,1.);#21=IFCSHAPEREPRESENTATION($,'Body','CSG',(#20));#22=IFCPRODUCTDEFINITIONSHAPE($,$,(#21));
        #23=IFCOPENINGELEMENT('0ArcusFixturesOpenPass',$,'Pass-through',$,$,#6,#22,$,$);
        #24=IFCRELVOIDSELEMENT('0ArcusFixturesRelVPass',$,$,$,#13,#23);
        """)
        let (_, r, _) = try TestModel.importIntoTemplate(d)
        #expect(r.nativeCounts["walls"] == 1)
        #expect(r.unsupported["IfcOpeningElement"] == 1)
        #expect(r.warnings.contains { $0.contains("opening") })
    }

    @Test func importRunsOffTheMainActor() async throws {
        let data = try TestModel.fixture("small-ifc2x3.ifc")
        let walls = try await Task.detached {
            let (m, _, _) = try TestModel.importIntoTemplate(data)
            return m.elements(.walls).count
        }.value
        #expect(walls == 1)
    }
}
