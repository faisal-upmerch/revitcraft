import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// F2: stacked walls export their parts' body (not a standard case); slanted columns export their leaning body.
@Suite("IFC F2 elements")
struct F2ExportTests {
    @Test func stackedWallsAndSlantedColumnsExport() throws {
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "F2")
        let stacked = try #require(StackedWallDefaults.populate(tx))
        tx.update(b.walls[0]) { $0.typeID = stacked }
        var c = ColumnData(location: Vec2(20, 20), topLevelID: b.ids.levels.count > 1 ? b.ids.levels[1] : nil)
        c.topLocation = Vec2(21, 20)
        let col = tx.create(.structuralColumns, data: .column(c), typeID: tx.model.types(for: .structuralColumns).first?.id, levelID: b.ids.levels[0])
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let (d, _) = try TestModel.export(m, TestModel.options(.ifc2x3))
        let f = try TestModel.parse(d)
        func entity(_ id: ElementID) -> STEPEntity? {
            let g = m[id]!.ifcGUID.value
            return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
        }
        let w = try #require(entity(b.walls[0]))
        #expect(w.type == "IFCWALL" && w[6].refValue != nil, "a stacked wall's body is its parts")
        #expect(try #require(entity(col)).type == "IFCCOLUMN")
    }
}
