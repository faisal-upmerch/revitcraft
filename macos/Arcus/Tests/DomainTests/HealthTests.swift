import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Model health")
struct HealthTests {
    func codes(_ m: BIMModel) -> [String] { ModelHealth.check(m).map(\.code) }

    @Test func cleanModelHasNoWarnings() throws {
        let box = try Fx.box { tx, ids, walls in
            Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0), mark: "D1")
            tx.create(.rooms, name: "R", data: .room(RoomData(point: Vec2(5, 4), number: "1")), levelID: ids.levels[0])
        }
        #expect(ModelHealth.check(box.model).isEmpty)
    }

    @Test func overlappingCollinearWallsAreFlagged() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(6, 0))
            b = Fx.wall(tx, ids, Vec2(10, 0), Vec2(4, 0))
            // Touching end to end, collinear: fine.
            Fx.wall(tx, ids, Vec2(0, 5), Vec2(4, 5)); Fx.wall(tx, ids, Vec2(4, 5), Vec2(9, 5))
            // Overlapping but on another level: fine.
            Fx.wall(tx, ids, Vec2(0, 9), Vec2(6, 9)); Fx.wall(tx, ids, Vec2(3, 9), Vec2(8, 9), level: 1, top: 2)
        }
        let overlaps = ModelHealth.check(m).filter { $0.code == "wall.overlap" }
        #expect(overlaps.count == 1)
        #expect(overlaps.first?.elements == [a, b].sorted())
    }

    @Test func duplicateMarksPerCategory() throws {
        let box = try Fx.box { tx, ids, walls in
            Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0), mark: "X1")
            Fx.door(tx, ids, host: walls[0], at: Vec2(7, 0), mark: "X1")
            let w = Fx.window(tx, ids, host: walls[2], at: Vec2(5, 8))
            tx.update(w) { $0.mark = "X2" }
            tx.update(walls[1]) { $0.mark = "X2" }   // same mark, different category: fine
        }
        let dup = ModelHealth.check(box.model).filter { $0.code == "mark.duplicate" }
        #expect(dup.count == 1)
        #expect(dup.first?.elements.count == 2)
        #expect(dup.first?.message.contains("X1") == true)
    }

    @Test func roomProblemsAreReported() throws {
        var outside: ElementID!, first: ElementID!, second: ElementID!
        let box = try Fx.box { tx, ids, _ in
            first = tx.create(.rooms, name: "A", data: .room(RoomData(point: Vec2(2, 2), number: "1")), levelID: ids.levels[0])
            second = tx.create(.rooms, name: "B", data: .room(RoomData(point: Vec2(8, 6), number: "2")), levelID: ids.levels[0])
            outside = tx.create(.rooms, name: "C", data: .room(RoomData(point: Vec2(30, 6), number: "3")), levelID: ids.levels[0])
        }
        let w = ModelHealth.check(box.model)
        #expect(w.first { $0.code == "room.unbounded" }?.elements == [outside!])
        #expect(w.first { $0.code == "room.redundant" }?.elements == [first, second].sorted())
        #expect(w.first { $0.code == "room.unbounded" }?.message.contains("3 C") == true)
    }

    @Test func brokenReferencesInALoadedModelAreErrors() throws {
        var box = try Fx.box { tx, ids, walls in
            Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0))
            tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            Fx.wall(tx, ids, Vec2(20, 0), Vec2(25, 0), type: "Retaining - 300mm Concrete")
        }
        // Simulate a damaged file: bypass transactions.
        var m = box.model
        let door = m.elements(.doors)[0]
        var floor = m.elements(.floors)[0]
        floor.slab?.boundary = Sketch(loops: [[.line(Segment2(.zero, Vec2(1, 0)))]])
        m.put(floor)
        m.remove(box.walls[0])
        m.remove(box.ids.wallTypes["Retaining - 300mm Concrete"]!)
        let w = ModelHealth.check(m)
        #expect(w.contains { $0.code == "host.orphan" && $0.elements == [door.id] })
        #expect(w.contains { $0.code == "sketch.invalid" && $0.elements == [floor.id] && $0.severity == .error })
        #expect(w.contains { $0.code == "type.missing" })
        #expect(w.first?.severity == .error, "errors sort first")
        #expect(w.map(\.severity) == w.map(\.severity).sorted(by: >))
        box.model = m
    }

    @Test func missingLevelsAndUnnamedLevels() throws {
        var (m, ids) = Fx.template()
        try Fx.commit(&m) { tx in Fx.wall(tx, ids, .zero, Vec2(5, 0), level: 1, top: nil) }
        var damaged = m
        damaged.remove(ids.levels[1])
        #expect(codes(damaged).contains("level.missing"))
        var unnamed = m
        var l = unnamed[ids.levels[2]]!
        l.name = "  "
        unnamed.put(l)
        #expect(codes(unnamed).contains("export.levelName"))
    }

    @Test func missingMaterialsInAssembliesAreReported() throws {
        var (m, ids) = Fx.template()
        m.remove(ids.materials["Brick, Common"]!)
        let w = ModelHealth.check(m).filter { $0.code == "material.missing" }
        #expect(w.contains { $0.elements == [ids.wallTypes[Fx.brick]!] })
    }

    @Test func elementsFarFromOriginAreReported() throws {
        var (m, ids) = Fx.template()
        var far: ElementID!
        let limit = m.projectInfo.extentsWarningDistance
        try Fx.commit(&m) { tx in far = Fx.wall(tx, ids, Vec2(limit + 10, 0), Vec2(limit + 15, 0)) }
        #expect(ModelHealth.check(m).contains { $0.code == "extents.far" && $0.elements == [far] })
    }

    @Test func stairRulesAndUnloadedLinks() throws {
        var (m, ids) = Fx.template()
        try Fx.commit(&m) { tx in
            var s = StairData(origin: .zero, direction: 0, width: 1.2, topLevelID: ids.levels[1])
            s.desiredRiserCount = 10
            tx.create(.stairs, data: .stair(s), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
            var link = LinkData(format: .dwg, isLinked: true, sourcePath: "/tmp/none.dwg", sourceName: "none.dwg", contentKey: "k")
            link.isLoaded = false
            tx.create(.importedCAD, data: .link(link), levelID: ids.levels[0])
        }
        let c = codes(m)
        #expect(c.contains("stair.rule"))
        #expect(c.contains("link.unloaded"))
    }

    @Test func cancellationStopsEarly() throws {
        var outside: ElementID!
        let box = try Fx.box { tx, ids, walls in
            Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0), mark: "Z")
            Fx.door(tx, ids, host: walls[0], at: Vec2(7, 0), mark: "Z")
            outside = tx.create(.rooms, name: "C", data: .room(RoomData(point: Vec2(30, 6), number: "3")), levelID: ids.levels[0])
        }
        let partial = ModelHealth.check(box.model, isCancelled: { true })
        #expect(partial.map(\.code) == ["mark.duplicate"])
        _ = outside
    }

    @Test func courtyardHouseIsHealthy() {
        let m = CourtyardHouse.make()
        #expect(!ModelHealth.check(m).contains { $0.severity == .error })
    }
}
