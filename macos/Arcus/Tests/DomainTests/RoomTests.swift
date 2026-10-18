import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Rooms")
struct RoomTests {
    func room(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, _ p: Vec2, _ number: String, name: String = "Room", level: Int = 0) -> ElementID {
        tx.create(.rooms, name: name, data: .room(RoomData(point: p, number: number)), levelID: ids.levels[level])
    }

    @Test(arguments: [Fx.generic, Fx.brick, "Interior - 100mm Partition"])
    func boxedRoomAreaExcludesWallThickness(_ type: String) throws {
        var r: ElementID!
        let box = try Fx.box(type: type) { tx, ids, _ in r = room(tx, ids, Vec2(5, 4), "101") }
        let t = WallGeometry.frame(box.model[box.walls[0]]!, box.model)!.thickness
        let b = RoomGeometry.boundary(box.model[r]!, box.model)
        #expect(b.state == .bounded)
        #expect(Fx.approx(b.area, (10 - t) * (8 - t), 1e-6))
        #expect(Fx.approx(b.perimeter, 2 * ((10 - t) + (8 - t)), 1e-6))
    }

    @Test func roomOutsideWallsIsNotEnclosed() throws {
        var r: ElementID!
        let box = try Fx.box { tx, ids, _ in r = room(tx, ids, Vec2(20, 4), "X") }
        #expect(RoomGeometry.boundary(box.model[r]!, box.model).state == .notEnclosed)
        #expect(RoomGeometry.boundary(box.model[r]!, box.model).area == 0)
    }

    @Test func secondRoomInSameRegionIsRedundant() throws {
        var a: ElementID!, b: ElementID!
        let box = try Fx.box { tx, ids, _ in
            a = room(tx, ids, Vec2(2, 2), "1")
            b = room(tx, ids, Vec2(8, 6), "2")
        }
        #expect(RoomGeometry.boundary(box.model[a]!, box.model).state == .bounded)
        #expect(RoomGeometry.boundary(box.model[b]!, box.model).state == .redundant(a))
    }

    @Test func roomWithoutLevelIsNotPlaced() {
        let e = Element(id: ElementID(1), category: .rooms, name: "Loose", data: .room(RoomData(point: .zero, number: "0")))
        #expect(RoomGeometry.boundary(e, Fx.archMetric.0).state == .notPlaced)
    }

    @Test func separationLineSplitsRoom() throws {
        var a: ElementID!, b: ElementID!
        let box = try Fx.box { tx, ids, _ in
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(4, 0), Vec2(4, 8))))), levelID: ids.levels[0])
            a = room(tx, ids, Vec2(2, 4), "1")
            b = room(tx, ids, Vec2(7, 4), "2")
        }
        let ba = RoomGeometry.boundary(box.model[a]!, box.model), bb = RoomGeometry.boundary(box.model[b]!, box.model)
        #expect(ba.state == .bounded && bb.state == .bounded)
        #expect(Fx.approx(ba.area, 3.9 * 7.8, 1e-6))
        #expect(Fx.approx(bb.area, 5.9 * 7.8, 1e-6))
    }

    @Test func separationLineOnOtherLevelIsIgnored() throws {
        var a: ElementID!, b: ElementID!
        let box = try Fx.box { tx, ids, _ in
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(4, 0), Vec2(4, 8))))), levelID: ids.levels[1])
            a = room(tx, ids, Vec2(2, 4), "1")
            b = room(tx, ids, Vec2(7, 4), "2")
        }
        #expect(RoomGeometry.boundary(box.model[b]!, box.model).state == .redundant(a))
    }

    @Test func nonBoundingAndDemolishedWallsDoNotSplitRooms() throws {
        for mode in ["unbounding", "demolished"] {
            var a: ElementID!, b: ElementID!
            let box = try Fx.box { tx, ids, _ in
                Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8)) { if mode == "unbounding" { $0.roomBounding = false } }
                a = room(tx, ids, Vec2(2, 4), "1")
                b = room(tx, ids, Vec2(7, 4), "2")
            }
            var m = box.model
            if mode == "demolished" {
                let partition = m.elements(.walls).last!.id
                try Fx.commit(&m) { tx in tx.update(partition) { $0.phaseDemolished = box.ids.phases[1] } }
            }
            #expect(RoomGeometry.boundary(m[b]!, m).state == .redundant(a), "\(mode)")
            #expect(Fx.approx(RoomGeometry.boundary(m[a]!, m).area, 9.8 * 7.8, 1e-6), "\(mode)")
        }
    }

    @Test func doorReportsRoomsOnEitherSideAndFlipSwapsThem() throws {
        var a: ElementID!, b: ElementID!, d: ElementID!
        var box = try Fx.box { tx, ids, _ in
            let p = Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8))
            d = Fx.door(tx, ids, host: p, at: Vec2(5, 4))
            a = room(tx, ids, Vec2(2, 4), "101", name: "West")
            b = room(tx, ids, Vec2(7, 4), "102", name: "East")
        }
        let around = RoomQueries.roomsAround(insert: box.model[d]!, box.model)
        #expect(Set([around.from?.id, around.to?.id]) == Set([a, b]))
        try Fx.commit(&box.model) { tx in tx.update(d) { $0.insert?.facingFlipped.toggle() } }
        let flipped = RoomQueries.roomsAround(insert: box.model[d]!, box.model)
        #expect(flipped.from?.id == around.to?.id)
        #expect(flipped.to?.id == around.from?.id)
        // The built-in From/To parameters show "number name".
        let from = Parameters.value(ParameterID("insert.fromRoom"), of: box.model[d]!, box.model)?.textValue
        #expect(from == "\(flipped.from!.room!.number) \(flipped.from!.name)")
    }

    @Test func exteriorDoorHasOneRoom() throws {
        var r: ElementID!, d: ElementID!
        let box = try Fx.box { tx, ids, walls in
            d = Fx.door(tx, ids, host: walls[0], at: Vec2(5, 0))
            r = room(tx, ids, Vec2(5, 4), "101")
        }
        let around = RoomQueries.roomsAround(insert: box.model[d]!, box.model)
        #expect([around.from?.id, around.to?.id].compactMap { $0 } == [r])
    }

    @Test func roomAtPointQueries() throws {
        var r: ElementID!
        let box = try Fx.box { tx, ids, _ in r = room(tx, ids, Vec2(5, 4), "101") }
        #expect(RoomQueries.room(at: Vec2(1, 1), level: box.l1, box.model)?.id == r)
        #expect(RoomQueries.room(at: Vec2(-1, 1), level: box.l1, box.model) == nil)
        #expect(RoomQueries.room(at: Vec2(1, 1), level: box.l2, box.model) == nil)
    }

    @Test func movingWallUpdatesArea() throws {
        var r: ElementID!
        var box = try Fx.box { tx, ids, _ in r = room(tx, ids, Vec2(5, 4), "101") }
        #expect(Fx.approx(RoomGeometry.boundary(box.model[r]!, box.model).area, 9.8 * 7.8, 1e-6))
        try Fx.commit(&box.model) { tx in
            try ElementOperationsShim.move([box.walls[1]], by: Vec2(2, 0), tx)
            // Keep the rectangle closed: stretch south and north walls.
            tx.update(box.walls[0]) { $0.wall?.location = .line(Segment2(.zero, Vec2(12, 0))) }
            tx.update(box.walls[2]) { $0.wall?.location = .line(Segment2(Vec2(12, 8), Vec2(0, 8))) }
        }
        #expect(Fx.approx(RoomGeometry.boundary(box.model[r]!, box.model).area, 11.8 * 7.8, 1e-6))
    }

    /// Room boundaries are memoized by (element id, element revision). Undo restores the old revision numbers, so a later
    /// different edit reuses a revision number that was already cached for other geometry.
    @Test func roomAreaAfterUndoThenDifferentEdit() throws {
        var r: ElementID!
        var box = try Fx.box { tx, ids, _ in r = room(tx, ids, Vec2(5, 4), "101") }
        let m0 = box.model
        func stretch(_ m: inout BIMModel, to x: Double) throws -> TransactionRecord {
            try Fx.commit(&m) { tx in
                tx.update(box.walls[1]) { $0.wall?.location = .line(Segment2(Vec2(x, 0), Vec2(x, 8))) }
                tx.update(box.walls[0]) { $0.wall?.location = .line(Segment2(.zero, Vec2(x, 0))) }
                tx.update(box.walls[2]) { $0.wall?.location = .line(Segment2(Vec2(x, 8), Vec2(0, 8))) }
            }.record
        }
        var m1 = m0
        let rec = try stretch(&m1, to: 12)
        #expect(Fx.approx(RoomGeometry.boundary(m1[r]!, m1).area, 11.8 * 7.8, 1e-6))
        var m2 = m1.applying(rec.inverse)   // undo
        #expect(Fx.approx(RoomGeometry.boundary(m2[r]!, m2).area, 9.8 * 7.8, 1e-6))
        _ = try stretch(&m2, to: 14)        // a different edit reaches the same element revisions as the first one
        box.model = m2
        #expect(Fx.approx(RoomGeometry.boundary(m2[r]!, m2).area, 13.8 * 7.8, 1e-6), "a new edit after undo gets fresh revision stamps")
    }

    @Test func roomHeightAndVolume() throws {
        var a: ElementID!, b: ElementID!
        let box = try Fx.box(w: 5, h: 4) { tx, ids, _ in
            a = room(tx, ids, Vec2(2, 2), "1")
        }
        var m = box.model
        try Fx.commit(&m) { tx in
            tx.update(a) { $0.room?.upperLimitLevelID = box.ids.levels[1]; $0.room?.limitOffset = -0.5 }
            b = room(tx, box.ids, Vec2(2, 2), "2", level: 1)
        }
        #expect(Fx.approx(RoomGeometry.height(m[a]!, m), 3.5))
        #expect(Fx.approx(RoomGeometry.height(m[b]!, m), 2.7), "default limit offset above its own level")
        let q = QuantityEngine.quantities(for: m[a]!, in: m)
        #expect(Fx.approx(q.area!, 4.8 * 3.8, 1e-6))
        #expect(Fx.approx(q.volume!, 4.8 * 3.8 * 3.5, 1e-6))
        #expect(Fx.approx(Parameters.value(ParameterID("q.area"), of: m[a]!, m)!.doubleValue!, 4.8 * 3.8, 1e-6))
    }

    @Test func columnsAreRoomBounding() throws {
        var r: ElementID!
        let box = try Fx.box { tx, ids, _ in
            tx.create(.columns, data: .column(ColumnData(location: Vec2(5, 4), topLevelID: ids.levels[1])),
                      typeID: ids.systemTypes["Concrete Column 400 x 400"], levelID: ids.levels[0])
            r = room(tx, ids, Vec2(2, 2), "1")
        }
        #expect(Fx.approx(RoomGeometry.boundary(box.model[r]!, box.model).area, 9.8 * 7.8 - 0.16, 1e-6))
    }
}

/// Minimal move helper so Domain-only suites don't need the Application module.
enum ElementOperationsShim {
    static func move(_ ids: [ElementID], by d: Vec2, _ tx: TransactionContext) throws {
        for id in ids { tx.update(id) { ElementTransform.apply(.translation(d), to: &$0) } }
    }
}
