import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// Export classes for the remaining architectural categories, and native import of beams/columns.
@Suite("IFC element classes")
struct ElementClassTests {
    struct Extra {
        var model: BIMModel
        var stair: ElementID, railing: ElementID, beam: ElementID, desk: ElementID, cabinet: ElementID, wc: ElementID, box: ElementID
        var topo: ElementID, pad: ElementID, ceiling: ElementID, roundColumn: ElementID
    }

    static func build() throws -> Extra {
        let b = try TestModel.build()
        let ids = b.ids
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let tx = TransactionContext(model: b.model, name: "More")
        let stair = tx.create(.stairs, data: .stair(StairData(origin: Vec2(2, 5), direction: 0, width: 1.1, topLevelID: l2)), typeID: ids.systemTypes["Stair"], levelID: l1)
        let railing = tx.create(.railings, data: .railing(RailingData(path: [.line(Segment2(Vec2(1, 7), Vec2(6, 7)))])), typeID: ids.systemTypes["Handrail"], levelID: l1)
        let beam = tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(Segment2(Vec2(0, 4), Vec2(10, 4))), startOffset: 3.9, endOffset: 3.9)),
                             typeID: ids.systemTypes["Steel Beam 200 x 400"], levelID: l1)
        let desk = tx.create(.furniture, data: .component(ComponentData(location: Vec2(7, 6), rotation: .pi / 2)), typeID: ids.familyTypes["Desk: 1500 x 750"], levelID: l1)
        let cabinet = tx.create(.casework, data: .component(ComponentData(location: Vec2(8, 1))), typeID: ids.familyTypes["Base Cabinet: 600"], levelID: l1)
        let wc = tx.create(.plumbingFixtures, data: .component(ComponentData(location: Vec2(9, 7))), typeID: ids.familyTypes["WC Pan: Standard"], levelID: l1)
        let box = tx.create(.genericModels, data: .component(ComponentData(location: Vec2(20, 20), mirrored: true)), typeID: ids.familyTypes["Generic Box: 1000 x 1000 x 1000"], levelID: l1)
        let topo = tx.create(.topography, data: .topography(TopographyData(points: [Vec3(-20, -20, -0.5), Vec3(30, -20, -0.4), Vec3(30, 30, -0.2), Vec3(-20, 30, -0.3), Vec3(5, 5, -0.1)])))
        let pad = tx.create(.buildingPads, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(12, 0), max: Vec2(16, 4))), offset: -0.2)),
                            typeID: ids.systemTypes["Building Pad"], levelID: l1)
        let ceiling = tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(0.2, 0.2), max: Vec2(9.8, 7.8))), offset: 2.7)),
                                typeID: ids.ceilingTypes["Plasterboard Ceiling"], levelID: l1)
        let round = tx.create(.columns, data: .column(ColumnData(location: Vec2(6, 3), topLevelID: l2)), typeID: ids.systemTypes["Concrete Column Round 350"], levelID: l1)
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        return Extra(model: m, stair: stair, railing: railing, beam: beam, desk: desk, cabinet: cabinet, wc: wc, box: box, topo: topo, pad: pad, ceiling: ceiling, roundColumn: round)
    }

    func entity(_ f: STEPFile, _ m: BIMModel, _ id: ElementID) -> STEPEntity? {
        let g = m[id]!.ifcGUID.value
        return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
    }

    @Test func ifc4Classes() throws {
        let x = try Self.build()
        let (d, r) = try TestModel.export(x.model, TestModel.options(.ifc4))
        let f = try TestModel.parse(d)
        let m = x.model
        #expect(entity(f, m, x.stair)?.type == "IFCSTAIR")
        #expect(entity(f, m, x.stair)?[8].enumValue == "STRAIGHT_RUN_STAIR")
        #expect(entity(f, m, x.railing)?.type == "IFCRAILING")
        #expect(entity(f, m, x.railing)?[8].enumValue == "HANDRAIL")
        #expect(entity(f, m, x.beam)?.type == "IFCBEAM")
        #expect(entity(f, m, x.desk)?.type == "IFCFURNITURE")
        #expect(entity(f, m, x.cabinet)?.type == "IFCFURNITURE")
        #expect(entity(f, m, x.wc)?.type == "IFCSANITARYTERMINAL")
        #expect(entity(f, m, x.box)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(entity(f, m, x.topo)?.type == "IFCGEOGRAPHICELEMENT")
        #expect(entity(f, m, x.pad)?[8].enumValue == "BASESLAB")
        #expect(entity(f, m, x.ceiling)?.type == "IFCCOVERING")
        #expect(entity(f, m, x.ceiling)?[8].enumValue == "CEILING")
        #expect(f.count("IfcFurnitureType") == 2 && f.count("IfcSanitaryTerminalType") == 1 && f.count("IfcBeamType") == 1)
        #expect(f.count("IfcRailingType") == 1 && f.count("IfcStairType") == 1 && f.count("IfcCoveringType") == 1)
        // Topography is contained in the site, not a storey.
        let site = try #require(f.all("IFCSITE").first)
        let siteRel = try #require(f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE").first { $0[5].refValue == site.id })
        #expect(siteRel[4].listValue == [.ref(entity(f, m, x.topo)!.id)])
        #expect(r.exportedElements == 21)
        // Mirrored component: the mirror is baked into the tessellation, placements stay rigid.
        let boxPlacement = try IFCImportSession(file: f, fileName: "x", options: IFCImportOptions()).geo.placement(entity(f, m, x.box)![5])
        #expect(abs(boxPlacement.determinant - 1) < 1e-9)
    }

    @Test func ifc2x3Classes() throws {
        let x = try Self.build()
        let f = try TestModel.parse(try TestModel.export(x.model, TestModel.options(.ifc2x3)).0)
        let m = x.model
        #expect(entity(f, m, x.desk)?.type == "IFCFURNISHINGELEMENT")
        #expect(entity(f, m, x.wc)?.type == "IFCFLOWTERMINAL")
        #expect(entity(f, m, x.box)?.type == "IFCBUILDINGELEMENTPROXY")
        #expect(entity(f, m, x.stair)?[8].enumValue == "STRAIGHT_RUN_STAIR")
        #expect(entity(f, m, x.topo) == nil) // IFC2X3: the terrain is the IfcSite body
        let site = try #require(f.all("IFCSITE").first)
        #expect(!site[6].isNull)
        let rep = try #require(f[f[site[6]]![2].listValue![0]])
        #expect(rep[2].stringValue == "SurfaceModel")
        #expect(f.count("IfcStairType") == 0 && f.count("IfcRoofType") == 0)
        // Flat pad and ceiling are swept solids.
        let padShape = try #require(f[entity(f, m, x.pad)![6]])
        #expect(f[padShape[2].listValue![0]]?[2].stringValue == "SweptSolid")
    }

    @Test(arguments: IFCSchema.allCases)
    func beamsAndColumnsImportNatively(_ schema: IFCSchema) throws {
        let x = try Self.build()
        let (d, _) = try TestModel.export(x.model, TestModel.options(schema))
        let (m, r, _) = try TestModel.importIntoTemplate(d)
        #expect(r.nativeCounts["structuralFraming"] == 1)
        #expect(r.nativeCounts["columns"] == 2)
        let beam = try #require(m.elements(.structuralFraming).first)
        let seg = try #require(beam.beam?.curve.asSegment)
        let ends = [seg.start, seg.end]
        #expect(ends.contains { $0.isAlmostEqual(Vec2(0, 4), tolerance: 1e-6) } && ends.contains { $0.isAlmostEqual(Vec2(10, 4), tolerance: 1e-6) })
        #expect(abs(beam.beam!.startOffset - 3.9) < 1e-6)
        #expect(m.type(of: beam)?.name == "Steel Beam 200 x 400")
        let round = try #require(m.elements(.columns).first { $0.column!.location.isAlmostEqual(Vec2(6, 3), tolerance: 1e-3) })
        #expect(m.type(of: round)?.name == "Concrete Column Round 350")
        // Furniture, fixtures, stairs, railings and terrain remain available as reference geometry.
        #expect((r.referenceCounts.values.reduce(0, +)) >= 6)
    }
}
