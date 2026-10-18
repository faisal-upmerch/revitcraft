import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusOutput

/// F5: spaces in gbXML and the Room/Area Report.
@Suite("F5 Output")
struct F5OutputTests {
    @Test func spacesExportToGbXMLAndTheReport() throws {
        var (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m, name: "Spaces")
        let p = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        let type = ids.wallTypes["Generic - 200mm"]
        for i in 0..<4 {
            tx.create(.walls, data: .wall(WallData(location: .line(Segment2(p[i], p[(i + 1) % 4])), topLevelID: ids.levels[1])), typeID: type, levelID: ids.levels[0])
        }
        tx.create(.spaceSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(5, 0), Vec2(5, 8))))), levelID: ids.levels[0])
        try SpacePlacement.place(at: Vec2(2, 4), level: ids.levels[0], in: tx)
        try SpacePlacement.place(at: Vec2(8, 4), level: ids.levels[0], in: tx)
        m = try tx.commit().model
        let (xml, n) = GbXMLExporter.write(m)
        #expect(n == 2)
        #expect(xml.components(separatedBy: "<Space ").count - 1 == 2)
        let (csv, rows) = RoomAreaReport.write(m, format: .csv)
        #expect(rows == 2 && csv.components(separatedBy: "\nSpace,").count - 1 == 2)
    }
}
