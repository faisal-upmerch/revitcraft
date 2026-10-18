import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// F34: reinforcement exports as IfcReinforcingBar and IfcReinforcingMesh with its bar sizes and a body.
@Suite("IFC reinforcement")
struct F34ReinforcementExportTests {
    @Test(arguments: [IFCSchema.ifc4, .ifc2x3])
    func reinforcementExportsAsReinforcingBarsAndMeshes(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "Reinforcement")
        let bt = Reinforcement.ensureBarTypes(in: tx)[1]
        let l1 = b.ids.levels[0]
        let rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(1, 1), end: Vec2(5, 1), count: 3, spacing: 0.2)), typeID: bt, levelID: l1, hostID: b.floor)
        let area = tx.create(.areaReinforcement, data: .areaReinforcement(AreaReinforcementData(boundary: [Vec2(6, 1), Vec2(9, 1), Vec2(9, 4), Vec2(6, 4)], major: .unitX,
                                                                                              layers: Array(repeating: RebarLayer(barTypeID: bt, spacing: 0.3), count: 4))),
                             levelID: l1, hostID: b.floor)
        let ft = Reinforcement.ensureFabricType(in: tx)
        let sheet = tx.create(.fabricReinforcement, data: .fabricSheet(FabricSheetData(center: Vec2(5, 5))), typeID: ft, levelID: l1, hostID: b.floor)
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let (d, report) = try TestModel.export(m, TestModel.options(schema))
        let f = try TestModel.parse(d)
        func entity(_ id: ElementID) -> STEPEntity? {
            let g = m[id]!.ifcGUID.value
            return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
        }
        let bar = try #require(entity(rb)), mesh = try #require(entity(sheet)), areaBar = try #require(entity(area))
        #expect(bar.type == "IFCREINFORCINGBAR" && areaBar.type == "IFCREINFORCINGBAR" && mesh.type == "IFCREINFORCINGMESH")
        #expect(bar[9].doubleValue == 0.016)
        #expect(bar[11].doubleValue.map { abs($0 - 4) < 1e-9 } == true)
        #expect(bar[12].enumValue == "MAIN")
        #expect(mesh[8 + 3].doubleValue == 0.006)
        #expect(bar[6].refValue != nil && mesh[6].refValue != nil, "has a body representation")
        #expect(report.exportedElements >= 3)
    }
}
