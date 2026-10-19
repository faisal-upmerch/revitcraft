import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// STAIR: a component stair exports as an IfcStair aggregating an IfcStairFlight per run and an IfcSlab LANDING per
/// landing, in both schemas.
@Suite("STAIR IFC export")
struct STAIRExportTests {
    static func build() throws -> (BIMModel, ElementID) {
        let b = try TestModel.build()
        let ids = b.ids
        let tx = TransactionContext(model: b.model, name: "Stair")
        var s = StairData(origin: Vec2(2, 1), direction: .pi / 2, width: 1.1, topLevelID: ids.levels[1])
        s.runs = [StairRun(start: Vec2(2, 1), direction: .pi / 2, risers: 12, width: 1.1),
                  StairRun(start: Vec2(2 - 1.3, 1 + 11 * 0.28), direction: -.pi / 2, risers: 11, width: 1.1)]
        let assembled = b.model.types(for: .stairs).first { $0.typeData?.familyName == "Assembled Stair" }?.id
        let id = tx.create(.stairs, data: .stair(s), typeID: assembled ?? ids.systemTypes["Stair"], levelID: ids.levels[0])
        return (try TestModel.fixGUIDs(try tx.commit().model), id)
    }

    @Test(arguments: IFCSchema.allCases)
    func flightsAndLandingsAreParts(_ schema: IFCSchema) throws {
        let (m, id) = try Self.build()
        let (d, _) = try TestModel.export(m, TestModel.options(schema))
        let f = try TestModel.parse(d)
        let g = m[id]!.ifcGUID.value
        let stair = try #require(f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g })
        #expect(stair.type == "IFCSTAIR" && stair[8].enumValue == "HALF_TURN_STAIR")
        #expect(f.count("IfcStairFlight") == 2)
        let flights = f.order.compactMap { f[$0] }.filter { $0.type == "IFCSTAIRFLIGHT" }
        #expect(flights.contains { $0[8].intValue == 12 && $0[9].intValue == 11 }, "risers and treads of run 1")
        let landings = f.order.compactMap { f[$0] }.filter { $0.type == "IFCSLAB" && $0[8].enumValue == "LANDING" }
        #expect(landings.count == 1)
        #expect(f.count("IfcRelAggregates") >= 4, "project, site, building, storeys and the stair's parts")
    }
}
