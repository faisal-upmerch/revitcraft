import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// F1: Model Text exports as a building element proxy; walls with reveals keep their grooves (mesh body).
@Suite("IFC F1 elements")
struct F1ExportTests {
    @Test func modelTextAndRevealedWallsExport() throws {
        if !ModelTextGlyphs.isInstalled {
            ModelTextGlyphs.install { line, _ in
                (line.enumerated().map { k, _ in let x = Double(k) * 0.7; return [Vec2(x, 0), Vec2(x + 0.6, 0), Vec2(x + 0.6, 1), Vec2(x, 1)] }, Double(line.count) * 0.7)
            }
        }
        let b = try TestModel.build()
        let tx = TransactionContext(model: b.model, name: "F1")
        let text = tx.create(.genericModels, name: "Model Text", data: .modelText(ModelTextData(text: "AB", position: Vec2(2, -2))), levelID: b.ids.levels[0])
        tx.create(.reveals, name: "Reveal", data: .wallReveal(WallRevealData(offset: 1)), levelID: b.ids.levels[0], hostID: b.walls[0])
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let (d, _) = try TestModel.export(m, TestModel.options(.ifc2x3))
        let f = try TestModel.parse(d)
        func entity(_ id: ElementID) -> STEPEntity? {
            let g = m[id]!.ifcGUID.value
            return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
        }
        let t = try #require(entity(text))
        #expect(t.type == "IFCBUILDINGELEMENTPROXY" && t[6].refValue != nil, "Model Text has a body")
        #expect(try #require(entity(b.walls[0])).type == "IFCWALL", "the grooved wall is not a standard case")
        #expect(try #require(entity(b.walls[1])).type == "IFCWALLSTANDARDCASE")
    }
}
