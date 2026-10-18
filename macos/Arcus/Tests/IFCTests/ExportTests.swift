import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

@Suite("IFC export")
struct ExportTests {
    @Test(arguments: IFCSchema.allCases)
    func headerDeclaresSchemaAndViewDefinition(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let (d, _) = try TestModel.export(b.model, TestModel.options(schema))
        let f = try TestModel.parse(d)
        #expect(f.header.schemas == [schema.rawValue])
        #expect(f.header.description == ["ViewDefinition [\(schema == .ifc2x3 ? "CoordinationView_V2.0" : "ReferenceView_V1.2")]"])
        #expect(f.header.timeStamp == "2026-01-01T00:00:00")
        #expect(f.header.name == "Golden.ifc")
        #expect(f.header.author == ["Arcus Tests"])
    }

    @Test(arguments: IFCSchema.allCases)
    func everyReferenceResolvesAndCountsMatchReport(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let (d, report) = try TestModel.export(b.model, TestModel.options(schema))
        let f = try TestModel.parse(d)
        func refs(_ v: STEPValue, _ out: inout [Int]) {
            switch v {
            case .ref(let r): out.append(r)
            case .list(let l): for x in l { refs(x, &out) }
            case .typed(_, let l): for x in l { refs(x, &out) }
            default: break
            }
        }
        for id in f.order {
            var out: [Int] = []
            for a in f[id]!.args { refs(a, &out) }
            for r in out { #expect(f[r] != nil, "#\(id) references missing #\(r)") }
        }
        #expect(report.entityCounts.values.reduce(0, +) == f.count)
        for (k, v) in report.entityCounts { #expect(f.count(k) == v, "\(k)") }
        #expect(report.files == ["Golden.ifc"])
    }

    @Test func exportIsDeterministic() throws {
        let b = try TestModel.build()
        for schema in IFCSchema.allCases {
            let (a, _) = try TestModel.export(b.model, TestModel.options(schema))
            let (c, _) = try TestModel.export(b.model, TestModel.options(schema))
            #expect(a == c)
        }
    }

    @Test(arguments: IFCSchema.allCases)
    func unitsContextsAndSpatialStructure(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(schema)).0)
        let units = Set(f.all("IFCSIUNIT").compactMap { $0[3].enumValue })
        #expect(units == ["METRE", "SQUARE_METRE", "CUBIC_METRE", "RADIAN"])
        #expect(f.all("IFCSIUNIT").allSatisfy { $0[2].isNull }) // no prefix: metres
        #expect(f.count("IfcGeometricRepresentationContext") == 1)
        #expect(Set(f.all("IFCGEOMETRICREPRESENTATIONSUBCONTEXT").compactMap { $0[0].stringValue }) == ["Body", "Axis"])
        #expect(f.count("IfcProject") == 1 && f.count("IfcSite") == 1 && f.count("IfcBuilding") == 1)
        let storeys = f.all("IFCBUILDINGSTOREY")
        #expect(storeys.compactMap { $0[2].stringValue } == ["Level 1", "Level 2", "Roof"])
        #expect(storeys.compactMap { $0[9].doubleValue } == [0, 4, 8])
        // Storey GUIDs are the level GUIDs.
        let levelGUIDs = Set(b.model.levels.map(\.ifcGUID.value))
        #expect(Set(storeys.compactMap { $0[0].stringValue }) == levelGUIDs)
        // Spaces are aggregated, elements are contained.
        let space = try #require(f.all("IFCSPACE").first)
        #expect(f.all("IFCRELAGGREGATES").contains { $0[5].listValue?.contains(.ref(space.id)) == true })
        let wallType = schema == .ifc2x3 ? "IFCWALLSTANDARDCASE" : "IFCWALL"
        let contained = f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE").flatMap { $0[4].listValue ?? [] }
        for w in f.all(wallType) { #expect(contained.contains(.ref(w.id))) }
    }

    @Test(arguments: IFCSchema.allCases)
    func elementsKeepTheirGUIDs(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(schema)).0)
        let m = b.model
        let exported = f.globalIds(["IfcWall", "IfcWallStandardCase", "IfcDoor", "IfcWindow", "IfcSlab", "IfcRoof", "IfcSpace", "IfcColumn"])
        for id in b.walls + [b.door, b.window, b.floor, b.roof, b.room, b.column] {
            #expect(exported.contains(m[id]!.ifcGUID.value))
        }
        // Types carry the type element GUID.
        let wt = m.type(of: m[b.walls[0]]!)!
        #expect(f.all("IFCWALLTYPE").first?[0].stringValue == wt.ifcGUID.value)
        // Every GlobalId in the file is unique.
        var seen: Set<String> = []
        for id in f.order {
            guard let g = f[id]![0].stringValue, g.count == 22, IFCGUID(g) != nil, f[id]!.args.count >= 4, f[id]![1].refValue != nil else { continue }
            #expect(!seen.contains(g), "duplicate GlobalId \(g)")
            seen.insert(g)
        }
    }

    @Test func derivedGUIDsAreStableAcrossEdits() throws {
        let b = try TestModel.build()
        let o = TestModel.options(.ifc4)
        let f1 = try TestModel.parse(try TestModel.export(b.model, o).0)
        // Move an unrelated element; opening and relationship GUIDs must not change.
        let tx = TransactionContext(model: b.model, name: "Move")
        tx.update(b.column) { $0.column?.location = Vec2(4, 4) }
        let m2 = try tx.commit().model
        let f2 = try TestModel.parse(try TestModel.export(m2, o).0)
        for t in ["IfcOpeningElement", "IfcRelVoidsElement", "IfcRelFillsElement", "IfcPropertySet", "IfcRelDefinesByType", "IfcRelContainedInSpatialStructure"] {
            #expect(f1.globalIds([t]) == f2.globalIds([t]), "\(t)")
            #expect(!f1.globalIds([t]).isEmpty, "\(t)")
        }
        let door = b.model[b.door]!
        #expect(f1.globalIds(["IfcOpeningElement"]).contains(IFCGUID.deterministic("\(door.ifcGUID.value)/opening").value))
    }

    @Test func ifc2x3UsesStandardCaseSweptSolidsAndBreps() throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(.ifc2x3)).0)
        #expect(f.count("IfcWallStandardCase") == 4)
        #expect(f.count("IfcWall") == 0)
        #expect(f.count("IfcTriangulatedFaceSet") == 0)
        #expect(f.count("IfcFacetedBrep") > 0)
        let reps = f.all("IFCSHAPEREPRESENTATION")
        for w in f.all("IFCWALLSTANDARDCASE") {
            let shape = try #require(f[w[6]])
            let kinds = (shape[2].listValue ?? []).compactMap { f[$0] }.map { "\($0[1].stringValue ?? ""):\($0[2].stringValue ?? "")" }
            #expect(Set(kinds) == ["Axis:Curve2D", "Body:SweptSolid"])
        }
        #expect(reps.allSatisfy { ["Curve2D", "SweptSolid", "Brep", "SurfaceModel"].contains($0[2].stringValue ?? "") })
        #expect(f.count("IfcDoorStyle") == 1 && f.count("IfcWindowStyle") == 1)
        #expect(f.count("IfcPresentationStyleAssignment") > 0)
    }

    @Test func ifc4UsesTessellationForBodies() throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(.ifc4)).0)
        #expect(f.count("IfcWall") == 4 && f.count("IfcWallStandardCase") == 0)
        #expect(f.count("IfcFacetedBrep") == 0)
        #expect(f.count("IfcTriangulatedFaceSet") > 0)
        let bodyTypes = Set(f.all("IFCSHAPEREPRESENTATION").filter { $0[1].stringValue == "Body" }.compactMap { $0[2].stringValue })
        #expect(bodyTypes == ["Tessellation", "SweptSolid"]) // SweptSolid only for opening boxes
        for o in f.all("IFCOPENINGELEMENT") {
            let rep = try #require(f[f[o[6]]![2].listValue![0]])
            #expect(rep[2].stringValue == "SweptSolid")
        }
        // Triangle indices are 1-based and in range.
        for t in f.all("IFCTRIANGULATEDFACESET") {
            let n = f[t[0]]![0].listValue!.count
            for tri in t[3].listValue! { for i in tri.listValue!.compactMap(\.intValue) { #expect(i >= 1 && i <= n) } }
        }
        #expect(f.count("IfcDoorType") == 1 && f.count("IfcWindowType") == 1 && f.count("IfcRelDeclares") == 1)
    }

    @Test(arguments: IFCSchema.allCases)
    func doorsAndWindowsFillOpenings(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(schema)).0)
        let door = try #require(f.all("IFCDOOR").first)
        #expect(door[8].doubleValue == 2.1)
        #expect(door[9].doubleValue == 0.9)
        let window = try #require(f.all("IFCWINDOW").first)
        #expect(window[8].doubleValue == 1.5)
        #expect(window[9].doubleValue == 1.2)
        #expect(f.count("IfcOpeningElement") == 2 && f.count("IfcRelVoidsElement") == 2 && f.count("IfcRelFillsElement") == 2)
        let filled = Set(f.all("IFCRELFILLSELEMENT").compactMap { $0[5].refValue })
        #expect(filled == [door.id, window.id])
        // The door's opening voids the wall that hosts it.
        let fill = f.all("IFCRELFILLSELEMENT").first { $0[5].refValue == door.id }!
        let void = f.all("IFCRELVOIDSELEMENT").first { $0[5] == fill[4] }!
        #expect(f[void[4]]?[0].stringValue == b.model[b.walls[0]]!.ifcGUID.value)
    }

    @Test(arguments: IFCSchema.allCases)
    func spaceNamingMaterialsAndLayers(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(schema)).0)
        let space = try #require(f.all("IFCSPACE").first)
        #expect(space[2].stringValue == "101")
        #expect(space[7].stringValue == "Office")
        let names = Set(f.all("IFCMATERIAL").compactMap { $0[0].stringValue })
        #expect(names.isSuperset(of: ["Brick, Common", "Rigid Insulation", "Concrete Masonry Units", "Plaster", "Concrete, Cast-in-Place"]))
        let usages = f.all("IFCMATERIALLAYERSETUSAGE")
        let wallUsage = try #require(usages.first { $0[1].enumValue == "AXIS2" })
        #expect(wallUsage[2].enumValue == "NEGATIVE")
        let set = try #require(f[wallUsage[0]])
        let thick = (set[0].listValue ?? []).compactMap { f[$0]?[1].doubleValue }
        #expect(thick == [0.102, 0.075, 0.19, 0.013])
        #expect(usages.contains { $0[1].enumValue == "AXIS3" })
        // Colours are attached to bodies.
        #expect(f.count("IfcStyledItem") > 0)
        #expect(f.all("IFCSURFACESTYLE").contains { $0[0].stringValue == "Brick, Common" })
    }

    @Test(arguments: IFCSchema.allCases)
    func propertySetsQuantitiesAndClassification(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let d = try TestModel.export(b.model, TestModel.options(schema)).0
        let f = try TestModel.parse(d)
        func pset(_ name: String) -> [String: STEPValue] {
            guard let p = f.all("IFCPROPERTYSET").first(where: { $0[2].stringValue == name }) else { return [:] }
            var out: [String: STEPValue] = [:]
            for r in p[4].listValue ?? [] { if let pv = f[r], let n = pv[0].stringValue { out[n] = pv[2] } }
            return out
        }
        let wallCommon = pset("Pset_WallCommon")
        #expect(wallCommon["IsExternal"]?.boolValue == true)
        #expect(wallCommon["LoadBearing"]?.boolValue == false)
        #expect(wallCommon["Reference"]?.stringValue == "Exterior - Brick on CMU")
        let params = f.all("IFCPROPERTYSET").filter { $0[2].stringValue == "Arcus_Parameters" }
        #expect(params.count >= 8)
        let allValues = params.flatMap { $0[4].listValue ?? [] }.compactMap { f[$0] }
        #expect(allValues.contains { $0[0].stringValue == "Mark" && $0[2].stringValue == "W-01" })
        #expect(allValues.contains { $0[0].stringValue == "Comments" && $0[2].stringValue == "South façade" })
        #expect(TestModel.text(d).contains("South fa\\X2\\00E7\\X0\\ade"))
        #expect(f.all("IFCPROPERTYSET").contains { $0[2].stringValue == "Arcus_TypeParameters" })
        // Base quantities.
        let qtoName = schema == .ifc4 ? "Qto_WallBaseQuantities" : "BaseQuantities"
        let qtos = f.all("IFCELEMENTQUANTITY").filter { $0[2].stringValue == qtoName }
        #expect(!qtos.isEmpty)
        let lengths = qtos.flatMap { $0[5].listValue ?? [] }.compactMap { f[$0] }.filter { $0.type == "IFCQUANTITYLENGTH" && $0[0].stringValue == "Length" }.compactMap { $0[3].doubleValue }
        #expect(lengths.contains(10) && lengths.contains(8))
        // Classification.
        let ref = try #require(f.all("IFCCLASSIFICATIONREFERENCE").first)
        #expect(ref[1].stringValue == "EF_25_10")
        #expect(f[ref[3]]?[3].stringValue == "Uniclass 2015")
        let assoc = try #require(f.all("IFCRELASSOCIATESCLASSIFICATION").first)
        #expect(assoc[4].listValue?.count == 1)
    }

    @Test func optionsDisablePropertiesQuantitiesAndClassification() throws {
        let b = try TestModel.build()
        var o = TestModel.options(.ifc4)
        o.includePropertySets = false
        o.includeBaseQuantities = false
        o.includeClassification = false
        let f = try TestModel.parse(try TestModel.export(b.model, o).0)
        #expect(f.count("IfcPropertySet") == 0)
        #expect(f.count("IfcElementQuantity") == 0)
        #expect(f.count("IfcClassificationReference") == 0)
        #expect(f.count("IfcWall") == 4)
    }

    @Test func skippedElementsHaveReasons() throws {
        let b = try TestModel.build()
        let (_, r) = try TestModel.export(b.model, TestModel.options(.ifc4))
        #expect(r.exportedElements == 10) // 4 walls, door, window, floor, roof, room, column
        let reasons = Dictionary(r.skipped.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        for v in b.model.views { #expect(reasons[v.id]?.contains("not exported") == true) }
        #expect(r.skipped.allSatisfy { !$0.1.isEmpty })
        #expect(r.warnings.contains { $0.contains("IfcRoof") })
        #expect(r.elapsed >= 0)
    }

    @Test func visibleInViewFiltersHiddenCategories() throws {
        let b = try TestModel.build()
        let view = b.model.views.first { $0.name == "{3D}" }!
        let tx = TransactionContext(model: b.model, name: "Hide")
        tx.update(view.id) { $0.view?.visibility.hiddenCategories.insert(.windows) }
        tx.update(view.id) { $0.view?.visibility.hiddenElements.insert(b.column) }
        let m = try tx.commit().model
        var o = TestModel.options(.ifc4)
        o.visibleInViewID = view.id
        let (d, r) = try TestModel.export(m, o)
        let f = try TestModel.parse(d)
        #expect(f.count("IfcWindow") == 0)
        #expect(f.count("IfcColumn") == 0)
        #expect(f.count("IfcDoor") == 1)
        #expect(f.count("IfcOpeningElement") == 2) // the window opening still voids its wall
        #expect(f.count("IfcRelFillsElement") == 1)
        #expect(r.skipped.contains { $0.0 == b.window && $0.1.contains("view") })
        o.visibleInViewID = b.walls[0]
        #expect(throws: IFCError.self) { try IFCExporter.export(m, options: o) }
    }

    @Test func splitByStoreyWritesOneFilePerStorey() throws {
        let b = try TestModel.build()
        var o = TestModel.options(.ifc2x3)
        o.splitByStorey = true
        o.fileName = "House.ifc"
        let r = try IFCExporter.export(b.model, options: o)
        #expect(r.files.map(\.name) == ["House - Level 1.ifc", "House - Level 2.ifc", "House - Roof.ifc"])
        #expect(r.report.files == r.files.map(\.name))
        let l1 = try TestModel.parse(r.files[0].data), l2 = try TestModel.parse(r.files[1].data), roof = try TestModel.parse(r.files[2].data)
        for f in [l1, l2, roof] {
            #expect(f.count("IfcProject") == 1 && f.count("IfcSite") == 1 && f.count("IfcBuilding") == 1 && f.count("IfcBuildingStorey") == 1)
        }
        #expect(l1.count("IfcWallStandardCase") == 4 && l1.count("IfcDoor") == 1 && l1.count("IfcSpace") == 1)
        #expect(l2.count("IfcRoof") == 1 && l2.count("IfcWallStandardCase") == 0)
        #expect(roof.count("IfcWallStandardCase") == 0 && roof.count("IfcRoof") == 0)
        #expect(r.report.exportedElements == 10)
    }

    @Test func coordinateBaseShiftsGeometry() throws {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "Base point")
        tx.update(b.model.projectInfoElement!.id) {
            $0.projectInfo?.projectBasePoint = Vec3(100, 50, 2)
            $0.projectInfo?.surveyPoint = Vec3(-10, -20, 0)
            $0.projectInfo?.surveyEasting = 500_000
            $0.projectInfo?.surveyNorthing = 5_400_000
            $0.projectInfo?.surveyElevation = 35
            $0.projectInfo?.trueNorthAngle = .pi / 6
        }
        let m = try tx.commit().model
        func wallOrigin(_ base: IFCCoordinateBase, _ schema: IFCSchema = .ifc4) throws -> (Vec3, STEPFile) {
            var o = TestModel.options(schema)
            o.coordinateBase = base
            let f = try TestModel.parse(try TestModel.export(m, o).0)
            let s = try IFCImportSession(file: f, fileName: "x", options: IFCImportOptions())
            let wall = f.all(schema == .ifc4 ? "IFCWALL" : "IFCWALLSTANDARDCASE").first { $0[0].stringValue == m[b.walls[0]]!.ifcGUID.value }!
            return (s.geo.placement(wall[5]).origin, f)
        }
        let (internalO, _) = try wallOrigin(.internalOrigin)
        #expect(internalO.isAlmostEqual(Vec3(0, 0, 0), tolerance: 1e-9))
        let (pbp, fp) = try wallOrigin(.projectBasePoint)
        #expect(pbp.isAlmostEqual(Vec3(-100, -50, -2), tolerance: 1e-9))
        #expect(fp.all("IFCBUILDINGSTOREY").first?[9].doubleValue == -2)
        #expect(fp.count("IfcMapConversion") == 0)
        let (sh, fs) = try wallOrigin(.sharedCoordinates)
        #expect(sh.isAlmostEqual(Vec3(10, 20, 0), tolerance: 1e-9))
        let mc = try #require(fs.all("IFCMAPCONVERSION").first)
        #expect(mc[2].doubleValue == 500_000 && mc[3].doubleValue == 5_400_000 && mc[4].doubleValue == 35)
        #expect(abs((mc[5].doubleValue ?? 0) - cos(-Double.pi / 6)) < 1e-9)
        #expect(fs.count("IfcProjectedCRS") == 1)
        let north = fs.all("IFCGEOMETRICREPRESENTATIONCONTEXT").first.flatMap { fs[$0[5]] }?[0].listValue?.compactMap(\.doubleValue) ?? []
        #expect(abs(north[0] + sin(Double.pi / 6)) < 1e-9 && abs(north[1] - cos(Double.pi / 6)) < 1e-9)
        // IFC2X3: survey values recorded in a property set, with a warning.
        var o = TestModel.options(.ifc2x3)
        o.coordinateBase = .sharedCoordinates
        let r = try IFCExporter.export(m, options: o)
        let f2 = try TestModel.parse(r.files[0].data)
        #expect(f2.count("IfcMapConversion") == 0)
        #expect(f2.all("IFCPROPERTYSET").contains { $0[2].stringValue == "Arcus_SharedCoordinates" })
        #expect(r.report.warnings.contains { $0.contains("map conversion") })
    }

    @Test func phaseFilterSkipsDemolishedAndFutureElements() throws {
        let b = try TestModel.build()
        let existing = b.ids.phases[0], newC = b.ids.phases[1]
        let tx = TransactionContext(model: b.model, name: "Phases")
        tx.update(b.column) { $0.phaseCreated = existing; $0.phaseDemolished = newC }
        let m = try tx.commit().model
        let (d, r) = try TestModel.export(m, TestModel.options(.ifc4))
        #expect(try TestModel.parse(d).count("IfcColumn") == 0)
        #expect(r.skipped.contains { $0.0 == b.column && $0.1.contains("Demolished") })
        var o = TestModel.options(.ifc4)
        o.phaseID = existing
        let (d2, r2) = try TestModel.export(m, o)
        let f2 = try TestModel.parse(d2)
        #expect(f2.count("IfcColumn") == 1)
        #expect(f2.count("IfcWall") == 0) // walls were created in New Construction
        #expect(r2.skipped.contains { $0.0 == b.walls[0] && $0.1.contains("later phase") })
        o.phaseID = b.walls[0]
        #expect(throws: IFCError.self) { try IFCExporter.export(m, options: o) }
    }

    @Test func groupsBecomeIfcGroups() throws {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "Group")
        tx.create(.modelGroups, name: "Façade", data: .group(GroupData(members: [b.walls[0], b.door], origin: .zero, groupTypeName: "Façade Group")))
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let f = try TestModel.parse(try TestModel.export(m, TestModel.options(.ifc2x3)).0)
        let g = try #require(f.all("IFCGROUP").first)
        #expect(g[2].stringValue == "Façade")
        let assign = try #require(f.all("IFCRELASSIGNSTOGROUP").first)
        #expect(assign[6] == .ref(g.id))
        #expect(assign[4].listValue?.count == 2)
    }

    @Test func progressAndCancellation() throws {
        let b = try TestModel.build()
        final class Box: @unchecked Sendable { var values: [Double] = []; let lock = NSLock() }
        let box = Box()
        _ = try IFCExporter.export(b.model, options: TestModel.options(.ifc4), progress: { v in box.lock.lock(); box.values.append(v); box.lock.unlock() })
        #expect(box.values.last == 1)
        #expect(box.values == box.values.sorted())
        #expect(throws: IFCError.self) { try IFCExporter.export(b.model, options: TestModel.options(.ifc4), isCancelled: { true }) }
    }

    @Test func exportRunsOffTheMainActor() async throws {
        let b = try TestModel.build()
        let model = b.model
        let count = try await Task.detached { try IFCExporter.export(model, options: TestModel.options(.ifc4)).report.exportedElements }.value
        #expect(count == 10)
    }
}
