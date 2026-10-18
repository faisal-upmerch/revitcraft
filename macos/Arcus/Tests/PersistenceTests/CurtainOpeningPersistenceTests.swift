import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Curtain walls and openings persist")
struct CurtainOpeningPersistenceTests {
    @Test func curtainWallOverridesOpeningsAndShaftsRoundTrip() throws {
        let tmp = TempDir()
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "WP3")
        let empty = m0.type(category: .curtainPanels, name: "Empty")!.id
        let cw = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(6, 0))), topLevelID: ids.levels[1])),
                           typeID: ids.systemTypes["Curtain Wall: Storefront"], levelID: ids.levels[0])
        let basic = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 5), Vec2(8, 5))), topLevelID: ids.levels[1])),
                              typeID: ids.wallTypes["Generic - 200mm"], levelID: ids.levels[0])
        tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: 1, end: 2, bottom: 0.5, top: 2))), levelID: ids.levels[0], hostID: basic)
        tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(rect: Rect2(min: Vec2(2, 2), max: Vec2(3, 3))), topLevelID: ids.levels[1]))),
                  levelID: ids.levels[0])
        var model = try tx.commit().model
        let tx2 = TransactionContext(model: model, name: "Overrides")
        tx2.update(cw) { e in
            e.wall?.curtain?.verticalGrids = [0.5]
            e.wall?.curtain?.panels = [CurtainPanelOverride(station: 0.2, height: 1, typeID: empty)]
            e.wall?.curtain?.mullions = [CurtainMullionOverride(isVertical: true, position: 0.5, from: 0, to: 4, present: false)]
        }
        tx2.update(ids.wallTypes["Generic - 200mm"]!) { t in t.typeData?.assembly?.wrappingAtInserts = .both; t.typeData?.assembly?.layers[0].wraps = true }
        model = try tx2.commit().model
        let url = tmp.file("CW.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, _) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        #expect(read[cw]?.wall?.curtain?.panels.first?.typeID == empty)
        #expect(read.elements(.wallOpenings).count == 1 && read.elements(.shaftOpenings).count == 1)
        #expect(read.types(for: .walls).contains { $0.typeData?.curtain?.borderMullions == true })
        #expect(CurtainWallGeometry.layout(read[cw]!, read)?.panels.first?.kind == .empty)
    }
}
