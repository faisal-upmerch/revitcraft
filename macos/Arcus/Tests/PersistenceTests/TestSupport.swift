import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// A unique temporary directory removed when the value is deinitialized. Never touches Application Support.
final class TempDir: @unchecked Sendable {
    let url: URL
    init(_ label: String = "ArcusPersistenceTests") {
        url = FileManager.default.temporaryDirectory.appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    func file(_ name: String) -> URL { url.appending(path: name) }
}

enum Sample {
    static let info = ArcusPackage.WriteInfo(documentID: UUID(uuidString: "3F2B8C1E-2D4A-4C8B-9E1F-5A6B7C8D9E0F")!, appVersion: "1.2.3", build: "456",
                                              created: Date(timeIntervalSince1970: 1_750_000_000.25), thumbnailPNG: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))

    static func drawing(_ seed: Int = 0) -> ReferenceDrawing {
        var ents: [ReferenceDrawing.Entity] = []
        for i in 0..<200 {
            let x = Double(i) * 0.5 + Double(seed)
            ents.append(.line(Segment2(Vec2(x, 0), Vec2(x, 10)), .init(layer: i % 2, handle: "H\(i)")))
        }
        ents.append(.text(position: Vec2(1, 2), height: 0.25, rotation: 0.1, text: "Existing survey — ümlaut ✓", alignment: .center, .init(layer: 0)))
        ents.append(.insert(block: "Door", transform: .identity, attributes: ["TAG": "D1"], .init(layer: 1)))
        return ReferenceDrawing(layers: [.init(name: "A-WALL"), .init(name: "A-DOOR", color: .black, lineWeight: 0.35)],
                                blocks: ["Door": [.arc(Arc2(center: .zero, radius: 0.9, startAngle: 0, sweep: .pi / 2), .init(layer: 1))]],
                                entities: ents, extents: Rect2(min: .zero, max: Vec2(100, 10)), metadata: ["source": "survey.dxf", "seed": "\(seed)"])
    }

    /// Template model plus walls, doors, windows, rooms, floor, roof, reference drawings, project parameters,
    /// sheet sets, a design option, a group and element parameter values.
    static func richModel() throws -> BIMModel {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Build")
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let wt = ids.wallTypes["Exterior - Brick on CMU"]!
        let pts = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        var walls: [ElementID] = []
        for i in 0..<4 {
            walls.append(tx.create(.walls, data: .wall(WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)), typeID: wt, levelID: l1))
        }
        let door = tx.create(.doors, data: .insert(InsertData(location: Vec2(5, 0))), typeID: ids.familyTypes["Door - Single Flush: 900 x 2100"]!, levelID: l1, hostID: walls[0]) {
            $0.mark = "D-101"; $0.comments = "Fire door, ✓ checked"
        }
        tx.create(.windows, data: .insert(InsertData(location: Vec2(10, 4), sillHeight: 0.9)), typeID: ids.familyTypes["Window - Casement: 1200 x 1500"]!, levelID: l1, hostID: walls[1])
        tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: l1)
        tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: Vec2(-0.5, -0.5), max: Vec2(10.5, 8.5))), edgeSlopes: [0.5, 0.5, 0.5, 0.5])),
                  typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: l2)
        tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(5, 4), number: "101")), levelID: l1)
        let option = tx.create(.designOptions, name: "Option A", data: .designOption(DesignOptionData(setName: "Entry", isPrimary: true)))
        let furniture = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(2, 2), Vec2(4, 2))), topLevelID: l2)), typeID: wt, levelID: l1) {
            $0.designOptionID = option
            $0.phaseDemolished = ids.phases.last
        }
        let group = tx.create(.modelGroups, name: "Group 1", data: .group(GroupData(members: [furniture], origin: Vec2(2, 2), groupTypeName: "Pair")))
        tx.update(furniture) { $0.groupID = group }
        tx.update(door) { $0[param: .user("abc")] = .double(.infinity) }
        tx.addReferenceDrawing(drawing(0))
        tx.addReferenceDrawing(drawing(1))
        tx.setProjectParameters([ParameterDefinition(id: .user("abc"), name: "Acoustic Rating", type: .number, group: .identity, categories: [.doors, .walls]),
                                 ParameterDefinition(name: "Finish", type: .choice(["Paint", "Stain"]), categories: [.doors])])
        tx.setViewSheetSets([ViewSheetSet(name: "Issue 1", members: m0.sheets.map(\.id))])
        return try tx.commit().model
    }

    static func expectEqual(_ a: BIMModel, _ b: BIMModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count, sourceLocation: sourceLocation)
        let ae = a.allElements, be = b.allElements
        #expect(ae.map(\.id) == be.map(\.id), sourceLocation: sourceLocation)
        var mismatches = 0
        for (x, y) in zip(ae, be) where x != y {
            mismatches += 1
            if mismatches < 3 { Issue.record("element \(x.id) differs", sourceLocation: sourceLocation) }
        }
        #expect(mismatches == 0, sourceLocation: sourceLocation)
        #expect(a.nextID == b.nextID, sourceLocation: sourceLocation)
        #expect(a.revision == b.revision, sourceLocation: sourceLocation)
        #expect(a.projectParameters == b.projectParameters, sourceLocation: sourceLocation)
        #expect(a.viewSheetSets == b.viewSheetSets, sourceLocation: sourceLocation)
        #expect(a.referenceDrawings == b.referenceDrawings, sourceLocation: sourceLocation)
    }

    /// A model with `count` extra walls built through transactions (performance tests).
    static func largeModel(walls count: Int) throws -> BIMModel {
        var (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let wt = ids.wallTypes["Generic - 200mm"]!
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let batch = 2_000
        var made = 0
        while made < count {
            let tx = TransactionContext(model: m, name: "Walls")
            for i in made..<min(count, made + batch) {
                let x = Double(i % 100) * 3, y = Double(i / 100) * 3
                tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(x, y), Vec2(x + 2, y))), topLevelID: l2)), typeID: wt, levelID: l1) {
                    $0.mark = "W\(i)"
                }
            }
            m = try tx.commit().model
            made = min(count, made + batch)
        }
        return m
    }
}

/// Direct SQLite access for tampering tests.
import SQLite3
enum RawSQLite {
    static func exec(_ path: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_close(db) }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw NSError(domain: "sqlite", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
