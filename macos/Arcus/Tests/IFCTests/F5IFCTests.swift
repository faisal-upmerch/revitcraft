import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusIFC

/// F5: spaces export as IfcSpace beside rooms; masses are conceptual and are left out.
@Suite("F5 IFC")
struct F5IFCTests {
    @Test func spacesExportAndMassesDoNot() throws {
        var b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "F5")
        let level = b.model[b.room]!.levelID!
        try SpacePlacement.place(at: Vec2(3, 3), level: level, in: tx)
        try MassGeometry.create(boundary: Polygon2.rectangle(Rect2(min: Vec2(20, 0), max: Vec2(30, 10))).points, height: 6, level: level, in: tx)
        b.model = try tx.commit().model
        let (data, _) = try TestModel.export(b.model, TestModel.options(.ifc4))
        let f = try TestModel.parse(data)
        #expect(f.count("IfcSpace") == 2, "the room and the space")
        #expect(!TestModel.text(data).contains("'Mass 1'"), "masses are not exported")
    }
}
