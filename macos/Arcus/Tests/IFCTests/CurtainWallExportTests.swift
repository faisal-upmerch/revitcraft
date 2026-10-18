import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

@Suite("IFC export: curtain walls and openings")
struct CurtainWallExportTests {
    struct Built {
        var model: BIMModel
        var curtain: ElementID
        var opening: ElementID
        var host: ElementID
    }

    /// The golden test model plus a Storefront curtain wall, a wall opening and a shaft through the floor.
    func build() throws -> Built {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "WP3")
        let storefront = try #require(b.ids.systemTypes["Curtain Wall: Storefront"])
        let cw = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 12), Vec2(6, 12))), topLevelID: b.ids.levels[1])),
                           typeID: storefront, levelID: b.ids.levels[0])
        let op = tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: 1, end: 2, bottom: 1, top: 2))), levelID: b.ids.levels[0], hostID: b.walls[2])
        tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(rect: Rect2(min: Vec2(7, 5), max: Vec2(8, 6))), baseOffset: -0.5, unconnectedHeight: 1))),
                  levelID: b.ids.levels[0])
        return Built(model: try tx.commit().model, curtain: cw, opening: op, host: b.walls[2])
    }

    @Test(arguments: IFCSchema.allCases)
    func curtainWallExportsAsIfcCurtainWallWithPlatesAndMembers(_ schema: IFCSchema) throws {
        let b = try build()
        let (data, report) = try TestModel.export(b.model, TestModel.options(schema))
        let f = try TestModel.parse(data)
        #expect(f.count("IfcCurtainWall") == 1)
        let layout = try #require(CurtainWallGeometry.layout(b.model[b.curtain]!, b.model))
        let panels = layout.panels.filter { $0.kind != .empty }.count
        #expect(f.count("IfcPlate") == panels)
        #expect(f.count("IfcMember") == layout.mullions.count)
        let cw = try #require(f.all("IFCCURTAINWALL").first)
        #expect(cw[0].stringValue == b.model[b.curtain]!.ifcGUID.value)
        // Plates and members are aggregated by the curtain wall, not contained in the storey.
        let agg = f.all("IFCRELAGGREGATES").first { $0[4].refValue == cw.id }
        #expect(agg.map { a in if case .list(let l) = a[5] { return l.count }; return 0 } == panels + layout.mullions.count)
        let contained = f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE").flatMap { r -> [Int] in if case .list(let l) = r[4] { return l.compactMap(\.refValue) }; return [] }
        #expect(contained.contains(cw.id))
        #expect(!contained.contains { f[$0]?.type == "IFCPLATE" || f[$0]?.type == "IFCMEMBER" })
        if schema == .ifc4 {
            #expect(f.all("IFCPLATE").allSatisfy { $0[8].enumValue == "CURTAIN_PANEL" })
            #expect(f.all("IFCMEMBER").allSatisfy { $0[8].enumValue == "MULLION" })
        }
        #expect(f.all("IFCPROPERTYSET").contains { $0[2].stringValue == "Pset_CurtainWallCommon" })
        // Every reference resolves and the report matches the file.
        #expect(report.entityCounts.values.reduce(0, +) == f.count)
        // GUIDs are unique.
        let guids = f.order.compactMap { f[$0] }.filter { $0.type.hasPrefix("IFC") && $0.args.first?.stringValue?.count == 22 }.compactMap { $0[0].stringValue }
        #expect(Set(guids).count == guids.count)
    }

    @Test(arguments: IFCSchema.allCases)
    func wallOpeningExportsAsAVoidWithoutFill(_ schema: IFCSchema) throws {
        let b = try build()
        let f = try TestModel.parse(try TestModel.export(b.model, TestModel.options(schema)).0)
        // Door + window + the wall opening void their walls; only the door and window fill theirs.
        #expect(f.count("IfcOpeningElement") == 3)
        #expect(f.count("IfcRelVoidsElement") == 3)
        #expect(f.count("IfcRelFillsElement") == 2)
    }
}
