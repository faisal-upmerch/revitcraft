import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

// W4-HATCH: line-family fill patterns, material pattern references, type coarse fills and view pattern overrides
// survive a package round trip; older patterns without families still decode.

@Suite("Fill pattern persistence")
struct FillPatternPersistenceTests {
    @Test func customPatternsReferencesAndOverridesRoundTrip() throws {
        let tmp = TempDir()
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Patterns")
        let custom = try FillPatternEdits.create(name: "Rammed Earth", isModel: false,
                                                 families: [HatchFamily(angle: 12.5, origin: Vec2(0.25, -1), shift: 3.3, spacing: 2.75, dashes: [4, -1.5, 0, -1.5]),
                                                            HatchFamily(angle: 102.5, spacing: 5)],
                                                 description: "Layered earth wall", in: tx)
        let modelPattern = try FillPatternEdits.create(name: "Board 120", isModel: true, families: [HatchFamily(angle: 0, spacing: 120)], in: tx)
        let brick = ids.materials["Brick, Common"]!
        tx.update(brick) { e in
            e.material?.cutPatternID = custom; e.material?.cutPatternColor = RGBColor(hex: 0x804020)
            e.material?.surfacePatternID = modelPattern; e.material?.surfacePatternColor = RGBColor(hex: 0x203040)
        }
        tx.update(ids.wallTypes["Generic - 200mm"]!) { $0.typeData?.params[ParameterID("type.coarseFillPattern")] = .ref(custom); $0.typeData?.params[ParameterID("type.coarseFillColor")] = .text("#112233") }
        let plan = ids.planViews[ids.levels[0]]!
        tx.update(plan) { e in
            var o = GraphicOverride(); o.cutPatternID = custom; o.cutPatternColor = .black
            e.view?.visibility.categoryOverrides[.walls] = o
            var eo = GraphicOverride(); eo.surfacePatternID = modelPattern
            e.view?.visibility.elementOverrides[brick] = eo
        }
        let model = try tx.commit().model
        let url = tmp.file("Patterns.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, _) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        let p = try #require(read[custom]?.fillPattern)
        #expect(p.families?.count == 2 && p.description == "Layered earth wall" && p.isModelPattern == false)
        #expect(p.families?[0] == HatchFamily(angle: 12.5, origin: Vec2(0.25, -1), shift: 3.3, spacing: 2.75, dashes: [4, -1.5, 0, -1.5]))
        #expect(read[custom]?.name == "Rammed Earth")
        #expect(read[modelPattern]?.fillPattern?.isModelPattern == true)
        let mat = try #require(read[brick]?.material)
        #expect(mat.cutPatternID == custom && mat.surfacePatternID == modelPattern && mat.cutPatternColor == RGBColor(hex: 0x804020))
        #expect(read[ids.wallTypes["Generic - 200mm"]!]?.typeData?.params[ParameterID("type.coarseFillPattern")]?.refValue == custom)
        let vg = try #require(read[plan]?.view?.visibility)
        #expect(vg.categoryOverrides[.walls]?.cutPatternID == custom && vg.elementOverrides[brick]?.surfacePatternID == modelPattern)
        // Every standard pattern came back with its families.
        let standard = read.elements(.fillPatterns).filter { FillPatternLibrary.isStandard($0.name) }
        #expect(standard.count == FillPatternLibrary.all.count)
        #expect(standard.allSatisfy { $0.fillPattern?.isSolid == true || $0.fillPattern?.hatch != nil })
    }

    @Test func patternsWithoutFamiliesAndOverridesWithoutIDsDecode() throws {
        let dec = JSONDecoder()
        let legacy = try dec.decode(FillPatternData.self, from: Data(#"{"kind":"Brick","isModelPattern":true,"spacing":0.075}"#.utf8))
        #expect(legacy.kind == .brick && legacy.families == nil && legacy.description == nil && legacy.hatch == nil)
        let o = try dec.decode(GraphicOverride.self, from: Data(#"{"cutPattern":"Solid Fill","halftone":true}"#.utf8))
        #expect(o.cutPattern == .solid && o.cutPatternID == nil && o.surfacePatternID == nil && o.halftone == true)
        // Encoding a pattern without families doesn't invent them.
        let data = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: data, as: UTF8.self).contains("families"))
    }
}
