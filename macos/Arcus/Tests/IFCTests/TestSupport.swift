import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusIFC

/// Deterministic test model and helpers shared by the IFC tests.
enum TestModel {
    static let fixedDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    struct Built {
        var model: BIMModel
        var ids: ProjectTemplates.Ids
        var walls: [ElementID]
        var door: ElementID
        var window: ElementID
        var floor: ElementID
        var roof: ElementID
        var room: ElementID
        var column: ElementID
    }

    /// Template project + 10 x 8 m box of exterior walls, a door, a window, a floor, a hipped roof, a room and a column.
    /// Every element gets a fixed GUID so exports are byte-for-byte reproducible.
    static func build() throws -> Built {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric, projectName: "IFC Golden")
        let tx = TransactionContext(model: m0, name: "Build")
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let wt = ids.wallTypes["Exterior - Brick on CMU"]!
        let pts = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        var walls: [ElementID] = []
        for i in 0..<4 {
            let w = WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)
            walls.append(tx.create(.walls, data: .wall(w), typeID: wt, levelID: l1))
        }
        tx.update(walls[0]) {
            $0.mark = "W-01"
            $0.comments = "South façade"
            $0.classification = Classification(system: "Uniclass 2015", code: "EF_25_10", title: "Walls")
        }
        let door = tx.create(.doors, data: .insert(InsertData(location: Vec2(5, 0))), typeID: ids.familyTypes["Door - Single Flush: 900 x 2100"]!,
                             levelID: l1, hostID: walls[0])
        let window = tx.create(.windows, data: .insert(InsertData(location: Vec2(10, 4), sillHeight: 0.9)), typeID: ids.familyTypes["Window - Casement: 1200 x 1500"]!,
                               levelID: l1, hostID: walls[1])
        let floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"],
                              levelID: l1)
        let roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: Vec2(-0.5, -0.5), max: Vec2(10.5, 8.5))), edgeSlopes: [0.5, 0.5, 0.5, 0.5])),
                             typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: l2)
        let room = tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(5, 4), number: "101")), levelID: l1)
        let column = tx.create(.columns, data: .column(ColumnData(location: Vec2(3, 3), topLevelID: l2)), typeID: ids.systemTypes["Concrete Column 400 x 400"], levelID: l1)
        var m = try tx.commit().model
        m = try fixGUIDs(m)
        return Built(model: m, ids: ids, walls: walls, door: door, window: window, floor: floor, roof: roof, room: room, column: column)
    }

    /// Replaces every GUID with a deterministic one derived from the element id.
    static func fixGUIDs(_ m: BIMModel) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "GUIDs")
        for e in m.allElements { tx.update(e.id) { $0.ifcGUID = IFCGUID.deterministic("arcus-ifc-test/\(e.id.raw)") } }
        return try tx.commit().model
    }

    static func options(_ schema: IFCSchema) -> IFCExportOptions {
        var o = IFCExportOptions()
        o.schema = schema
        o.timeStamp = fixedDate
        o.authorName = "Arcus Tests"
        o.organization = "Arcus"
        o.fileName = "Golden.ifc"
        return o
    }

    static func export(_ m: BIMModel, _ o: IFCExportOptions) throws -> (Data, IFCExportReport) {
        let r = try IFCExporter.export(m, options: o)
        return (r.files[0].data, r.report)
    }

    static func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    /// Imports into a fresh architectural template and commits.
    static func importIntoTemplate(_ data: Data, fileName: String = "test.ifc", options: IFCImportOptions = IFCImportOptions()) throws -> (BIMModel, IFCImportReport, BIMModel) {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Import IFC")
        let report = try IFCImporter.importFile(data, fileName: fileName, into: tx, options: options)
        let m = try tx.commit().model
        return (m, report, m0)
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Source-tree Fixtures directory (used only to regenerate goldens).
    static func sourceFixturesDir(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    /// Entities of a STEP file by type.
    static func parse(_ d: Data) throws -> STEPFile { try STEPParser.parse(d) }
}

extension STEPFile {
    func count(_ type: String) -> Int { byType[type.uppercased()]?.count ?? 0 }
    func globalIds(_ types: [String]) -> Set<String> {
        Set(types.flatMap { all($0.uppercased()) }.compactMap { $0[0].stringValue })
    }
}
