import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusRevit

@Suite("Arcus Exchange import — families")
struct FamilyImportTests {
    static func definition() throws -> (FamilyDefinition, [String]) {
        let results = try ArcusExchangeImporter.familyDefinitions(data: try Fixture.data("parametric-door.arcusx"))
        #expect(results.count == 1)
        let r = try #require(results.first)
        return (r.definition, r.warnings)
    }

    @Test func parametersFormulasAndTypes() throws {
        let (def, warnings) = try Self.definition()
        #expect(def.name == "Single-Flush Parametric")
        #expect(def.template == .door)
        #expect(def.parameter(named: "Width")?.isBuiltIn == true)
        #expect(def.parameter(named: "Frame Width")?.type == .length)
        #expect(def.parameter(named: "Rough Width")?.formula == "Width + 2 * Frame Width")
        #expect(def.parameter(named: "Frame Material")?.type == .elementRef(.materials))
        #expect(def.parameter(named: "Has Kick Plate")?.isInstance == true)
        #expect(def.parameter(named: "Has Kick Plate")?.type == .bool)
        #expect(def.parameter(named: "Material: Paint - White") != nil, "fixed material becomes a material parameter")
        #expect(def.parameter(named: "Nested Hardware") == nil)
        #expect(warnings.contains { $0.contains("Nested Hardware") })
        #expect(def.types.map(\.name) == ["0915 x 2134mm", "1015 x 2134mm"])
        let t0 = try #require(def.type(named: "0915 x 2134mm"))
        #expect(t0.values["Width"] == .double(0.915))
        #expect(t0.values["Has Kick Plate"] == .bool(false))
        #expect(t0.values["Rough Width"] == nil, "formula parameters have no stored value")
        #expect(t0.values["Frame Material"] == nil, "material values live on project types")
        let values = FamilyEvaluator.parameterValues(def, typeName: "0915 x 2134mm").values
        if case .quantity(let v, _)? = values["Rough Width"] { #expect(near(v, 1.015)) } else { Issue.record("Rough Width not evaluated") }
        if case .quantity(let v, _)? = FamilyEvaluator.parameterValues(def, typeName: "1015 x 2134mm").values["Rough Height"] {
            #expect(near(v, 2.184))
        } else { Issue.record("Rough Height not evaluated") }
    }

    @Test func referencePlanesDimensionsAndLines() throws {
        let (def, _) = try Self.definition()
        #expect(def.referencePlanes.map(\.name) == ["Center (Left/Right)", "Left", "Right", "Center (Front/Back)", "Bottom", "Top"])
        #expect(def.referencePlanes[1].offset == "-Width / 2")
        #expect(def.referencePlanes[1].strength == .left)
        #expect(def.referencePlanes[0].definesOrigin)
        #expect(def.dimensions.map(\.labelParameter) == ["Width", "Height"])
        #expect(def.planLines.count == 2)
        if case .arc(let c, let r, _, let sweep) = def.planLines[0].shape {
            #expect(c == FamilyPoint("-Width / 2", "-Frame Depth / 2"))
            #expect(r == "Width")
            #expect(near(Double(sweep), 90, 1e-3))
        } else { Issue.record("swing is not an arc") }
        #expect(def.planLines[0].subcategory == .swing)
        #expect(def.planLines[1].shape == .line(FamilyPoint(.plane("Left"), .expr("-Frame Depth / 2")), FamilyPoint(.plane("Left"), .expr("-Frame Depth / 2 - Width"))))
    }

    @Test func solidsVoidsAndApproximations() throws {
        let (def, warnings) = try Self.definition()
        #expect(def.solids.map(\.name) == ["Left Jamb", "Right Jamb", "Head", "Panel", "Vision Panel Cut", "Kick Plate", "Door Stop", "Hinge"])
        let jamb = def.solids[0]
        guard case .polygon(let pts) = jamb.profile else { Issue.record("jamb is not a polygon"); return }
        #expect(pts.first == FamilyPoint(.expr("-Width / 2 - Frame Width"), .expr("-Frame Depth / 2")))
        #expect(pts[1] == FamilyPoint(.plane("Left"), .expr("-Frame Depth / 2")))
        #expect(jamb.zMin == .plane("Bottom") && jamb.zMax == .expr("Height + Frame Width"))
        #expect(jamb.materialParameter == "Frame Material")
        #expect(jamb.subcategory == .frame)
        // Out-of-order loop is chained into a closed polygon.
        if case .polygon(let rp) = def.solids[1].profile { #expect(rp.count == 4) } else { Issue.record("right jamb") }
        // Horizontal extrusion of a rectangle maps exactly.
        #expect(def.solids[2].profile == .rectangle(xMin: .plane("Left"), xMax: .plane("Right"), yMin: .expr("-Frame Depth / 2"), yMax: .expr("Frame Depth / 2")))
        #expect(def.solids[2].zMin == .plane("Top") && def.solids[2].zMax == .expr("Height + Frame Width"))
        #expect(!def.solids[3].visibleInPlan)
        #expect(def.solids[4].isVoid)
        #expect(def.solids[5].visibilityParameter == "Has Kick Plate")
        #expect(def.solids[5].visibleAt == [.medium, .fine])
        #expect(def.solids[5].materialParameter == "Material: Paint - White")
        #expect(def.solids[6].profile == .circle(center: FamilyPoint("0.3", "-0.6"), radius: "0.02"))
        // The tessellated hinge is approximated by a box; the unknown kind is skipped.
        guard case .rectangle(let x0, let x1, _, _) = def.solids[7].profile else { Issue.record("hinge"); return }
        #expect(x0 == .expr("-0.5") && x1 == .expr("-0.48"))
        #expect(warnings.contains { $0.contains("Hinge") && $0.contains("approximated") })
        #expect(warnings.contains { $0.contains("Unknown Kind") })
        #expect(!warnings.contains { $0.contains("voids") }, "void extrusions cut, so no void warning")
    }

    @Test func evaluatesForEachType() throws {
        let (def, _) = try Self.definition()
        let a = FamilyEvaluator.evaluate(def, typeName: "0915 x 2134mm")
        #expect(a.errors.isEmpty, "\(a.errors)")
        #expect(!a.solids.contains { $0.name == "Kick Plate" }, "kick plate hidden for the first type")
        let b = FamilyEvaluator.evaluate(def, typeName: "1015 x 2134mm")
        #expect(b.errors.isEmpty, "\(b.errors)")
        #expect(b.solids.contains { $0.name == "Kick Plate" })
        #expect(b.solids.count == a.solids.count + 1)
        let head = try #require(a.solids.first { $0.name == "Head" })
        #expect(near(head.profile.outer.points.map(\.x).min(), -0.4575))
        #expect(near(head.zMin, 2.134) && near(head.zMax, 2.184))
        let o = try #require(a.opening)
        #expect(near(o.xMax - o.xMin, 1.015) && near(o.zMax - o.zMin, 2.184))
        let bo = try #require(b.opening)
        #expect(near(bo.xMax - bo.xMin, 1.115))
        #expect(FamilyEvaluator.flexTest(def).isEmpty, "\(FamilyEvaluator.flexTest(def))")
    }

    @Test func familyFileImportsAsLoadableFamily() throws {
        let (m, r) = try Fixture.importAndCommit(try Fixture.data("parametric-door.arcusx"))
        #expect(r.documentKind == .family)
        #expect(r.created("families") == 1)
        #expect(r.created("types") == 2)
        #expect(r.created("materials") == 2)
        #expect(r.familyDefinitions.first?.name == "Single-Flush Parametric")
        let fam = try #require(m.family(named: "Single-Flush Parametric"))
        #expect(fam.ifcGUID == IFCGUID.deterministic("revit-uniqueid:fx-family-single-flush"))
        let t = try #require(m[r.elementMap["ft-0915"]])
        #expect(t.typeData?.familyID == fam.id)
        #expect(t.typeData?.instanceCategory == .doors)
        #expect(m[t.typeData?.params[Parameters.familyParamID("Frame Material")]?.refValue]?.name == "Oak, Red")
        #expect(m[t.typeData?.params[Parameters.familyParamID("Material: Paint - White")]?.refValue]?.name == "Paint - White")
        #expect(t.typeData?.params[ParameterID("type.mark")] == .text("D1"))
        #expect((r.approximated["family items"] ?? 0) >= 1)
        #expect((r.skipped["family items"] ?? 0) >= 1)

        // Place it in a wall and edit the type.
        let tx = TransactionContext(model: m, name: "Place")
        let level = tx.create(.levels, name: "L1", data: .level(LevelData(elevation: 0)))
        let wtype = tx.create(.elementTypes, name: "Wall 200", data: .type(TypeData(instanceCategory: .walls, systemFamily: .basicWall, familyName: "Basic Wall",
                                                                                    assembly: CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: nil, thickness: 0.2)]))))
        let wall = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 0), Vec2(6, 0))), unconnectedHeight: 3)), typeID: wtype, levelID: level)
        let door = tx.create(.doors, data: .insert(InsertData(location: Vec2(3, 0))), typeID: t.id, levelID: level, hostID: wall)
        let m1 = try tx.commit().model
        let d1 = try #require(m1[door])
        #expect(near(InsertGeometry.openingSize(d1, m1)?.width, 1.015))
        let tx2 = TransactionContext(model: m1, name: "Resize")
        tx2.update(t.id) { $0.typeData?.params[Parameters.familyParamID("Width")] = .double(1.2) }
        let m2 = try tx2.commit().model
        let d2 = try #require(m2[door])
        #expect(near(InsertGeometry.openingSize(d2, m2)?.width, 1.3))
        #expect(!InsertGeometry.meshParts(d2, m2).isEmpty)
    }

    @Test func skipPolicyLeavesApproximationsOut() throws {
        var o = ExchangeImportOptions()
        o.unsupportedFamilyGeometry = .skip
        let results = try ArcusExchangeImporter.familyDefinitions(data: try Fixture.data("parametric-door.arcusx"), options: o)
        #expect(results.first?.definition.solids.contains { $0.name == "Hinge" } == false)
    }

    @Test func doorWithoutGeometryGetsAParametricPanel() throws {
        let data = Data("""
        {"format": "arcus-exchange", "schemaVersion": "1.0", "documentKind": "family",
         "families": [{"id": "f", "name": "Bare Door", "category": "doors", "definitionIncluded": false,
                       "parameters": [{"name": "Breite", "dataType": "length", "builtIn": "width"}, {"name": "Höhe", "dataType": "length", "builtIn": "height"}],
                       "types": [{"id": "t", "name": "A", "values": {"Breite": 0.8, "Höhe": 2.0}}]}]}
        """.utf8)
        let def = try #require(try ArcusExchangeImporter.familyDefinitions(data: data).first?.definition)
        #expect(!def.solids.isEmpty)
        let ev = FamilyEvaluator.evaluate(def, typeName: "A")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let o = try #require(ev.opening)
        #expect(near(o.xMax - o.xMin, 0.8))
        #expect(near(o.zMax - o.zMin, 2.0))
    }

    @Test func unreadableFormulasAreDroppedNotFatal() throws {
        let data = Data("""
        {"format": "arcus-exchange", "schemaVersion": "1.0", "documentKind": "family",
         "families": [{"id": "f", "name": "Box", "category": "genericModels",
                       "parameters": [{"name": "L", "dataType": "length"}, {"name": "M", "dataType": "length", "formula": "L * (("},
                                      {"name": "N", "dataType": "length", "formula": "Unknown + L"}],
                       "types": [{"name": "T", "values": {"L": 1, "M": 0.5}}],
                       "geometry": [{"kind": "extrusion", "extrusionAxis": "z", "extent": [0, "L"],
                                     "loops": [[{"type": "circle", "center": [0, 0], "radius": "L / 2"}]]}]}]}
        """.utf8)
        let r = try #require(try ArcusExchangeImporter.familyDefinitions(data: data).first)
        #expect(r.definition.parameter(named: "M")?.formula == nil)
        #expect(r.definition.parameter(named: "N")?.formula == nil)
        #expect(r.definition.type(named: "T")?.values["M"] == .double(0.5))
        #expect(r.warnings.filter { $0.contains("formula") }.count == 2)
        #expect(r.definition.solids.first?.profile == .circle(center: FamilyPoint("0", "0"), radius: "L / 2"))
        #expect(r.definition.template == .genericModel)
    }
}

@Suite("Revit providers")
struct RevitProviderTests {
    @Test func unavailableProviderExplainsTheRoutes() throws {
        let p = UnavailableRevitProvider()
        #expect(!p.isAvailable)
        let reason = try #require(p.unavailableReason)
        #expect(reason.contains("Arcus Bridge"))
        #expect(reason.contains("Export to Arcus"))
        #expect(reason.contains(".arcusx"))
        #expect(reason.contains("IFC"))
        #expect(reason.contains("ODA BimRv SDK"))
        #expect(reason.contains("does not reverse-engineer"))
    }

    @Test func currentProviderIsTruthful() {
        // Builds without the licensed SDK must never claim direct support.
        let p = RevitProviders.current
        if p is UnavailableRevitProvider { #expect(!p.isAvailable) }
        if !p.isAvailable { #expect(p.unavailableReason?.contains("Arcus Bridge") == true) }
    }

    @Test func canOpenByExtension() {
        let p = UnavailableRevitProvider()
        #expect(p.canOpen(URL(fileURLWithPath: "/a/House.rvt")))
        #expect(p.canOpen(URL(fileURLWithPath: "/a/Door.RFA")))
        #expect(p.canOpen(URL(fileURLWithPath: "/a/T.rte")))
        #expect(!p.canOpen(URL(fileURLWithPath: "/a/House.ifc")))
        #expect(RevitProviders.isExchangeFile(URL(fileURLWithPath: "/a/House.arcusx")))
    }

    @Test func importThrowsUnavailableWithFileFacts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-provider-\(UUID().uuidString).rvt")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestData.revitContainer().write(to: url)
        let p = UnavailableRevitProvider()
        #expect(try p.inspect(url).revitRelease == "2024")
        let tx = TransactionContext(model: BIMModel(), name: "x")
        do {
            _ = try p.import(url, into: tx, options: .init())
            Issue.record("expected an error")
        } catch {
            guard case .unavailable(let m) = error else { Issue.record("unexpected \(error)"); return }
            #expect(m.contains("is a revit project saved by Revit 2024"))
            #expect(m.contains("Arcus Bridge"))
        }
        #expect(!tx.hasChanges)
    }

    @Test func exchangeFilesImportInEveryBuild() throws {
        let tx = TransactionContext(model: BIMModel(), name: "Import")
        let r = try RevitProviders.importExchangeFile(try Fixture.url("small-project.arcusx"), into: tx)
        #expect(r.created("walls") == 4)
        _ = try tx.commit()
    }
}
