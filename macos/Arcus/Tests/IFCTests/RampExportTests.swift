import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

@Suite("IFC ramps")
struct RampExportTests {
    @Test(arguments: [IFCSchema.ifc4, .ifc2x3])
    func rampsExportAsIfcRamp(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let ids = b.ids
        let tx = TransactionContext(model: b.model, name: "Ramps")
        let type = tx.create(.elementTypes, name: RampGeometry.defaultTypeName, data: .type(RampGeometry.defaultType(material: nil)))
        var straight = RampData(path: [Vec2(20, 0), Vec2(32, 0)])
        straight.unconnectedHeight = 1
        let r1 = tx.create(.ramps, data: .ramp(straight), typeID: type, levelID: ids.levels[0])
        var turn = RampData(path: [Vec2(20, 5), Vec2(28, 5), Vec2(28, 12)])
        turn.unconnectedHeight = 1
        let r2 = tx.create(.ramps, data: .ramp(turn), typeID: type, levelID: ids.levels[0])
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let (d, _) = try TestModel.export(m, TestModel.options(schema))
        let f = try TestModel.parse(d)
        func entity(_ id: ElementID) -> STEPEntity? {
            let g = m[id]!.ifcGUID.value
            return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
        }
        let e1 = try #require(entity(r1)), e2 = try #require(entity(r2))
        #expect(e1.type == "IFCRAMP" && e2.type == "IFCRAMP")
        #expect(e1[8].enumValue == "STRAIGHT_RUN_RAMP")
        #expect(e2[8].enumValue == "QUARTER_TURN_RAMP")
        #expect(e1[6].refValue != nil, "has a body representation")
        #expect(f.count("IFCRAMPTYPE") == (schema == .ifc4 ? 1 : 0))
    }

    @Test func rampShapeTypes() {
        #expect(IFCFileBuilder.rampShapeType([Vec2(0, 0), Vec2(5, 0), Vec2(10, 0)]) == "TWO_STRAIGHT_RUN_RAMP")
        #expect(IFCFileBuilder.rampShapeType([Vec2(0, 0), Vec2(5, 0), Vec2(5, 3), Vec2(0, 3)]) == "HALF_TURN_RAMP")
        #expect(IFCFileBuilder.rampShapeType([Vec2(0, 0), Vec2(5, 0), Vec2(5, 3), Vec2(10, 3)]) == "TWO_QUARTER_TURN_RAMP")
        #expect(IFCFileBuilder.rampShapeType([Vec2(0, 0)]) == "NOTDEFINED")
    }
}
