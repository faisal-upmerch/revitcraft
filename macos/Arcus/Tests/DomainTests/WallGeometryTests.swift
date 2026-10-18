import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Wall joins and footprints")
struct WallJoinTests {
    func thickness(_ type: String) -> Double { Fx.archMetric.0[Fx.archMetric.1.wallTypes[type]]!.typeData!.assembly!.totalThickness }

    func overlapArea(_ a: Polygon2, _ b: Polygon2) -> Double {
        PolygonBoolean.intersection([Profile2(outer: a)], [Profile2(outer: b)]).reduce(0) { $0 + $1.area }
    }

    @Test(arguments: [Fx.generic, Fx.brick, "Interior - 100mm Partition"])
    func lCornerMitresWithoutOverlap(_ type: String) throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(10, 0), type: type)
            b = Fx.wall(tx, ids, Vec2(10, 0), Vec2(10, 8), type: type)
        }
        let t = thickness(type)
        let fa = WallGeometry.footprint(m[a]!, m)!, fb = WallGeometry.footprint(m[b]!, m)!
        #expect(fa.isSimple && fb.isSimple)
        #expect(Fx.approx(fa.area, 10 * t, 1e-9))
        #expect(Fx.approx(fb.area, 8 * t, 1e-9))
        #expect(overlapArea(fa, fb) < 1e-9)
        let j = WallGeometry.endJoin(m[a]!, atEnd: true, m)
        #expect(j.kind == .corner)
        #expect(j.others == [b])
        #expect(WallGeometry.endJoin(m[a]!, atEnd: false, m).kind == .free)
        // Mitred solid volume equals footprint area × height.
        let v = abs(WallGeometry.solid(m[a]!, m).signedVolume)
        #expect(Fx.approx(v, 10 * t * 4.0, 1e-6))
    }

    @Test func teeJunctionStopsAtThroughWallFace() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(10, 0))
            b = Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 6))
        }
        let j = WallGeometry.endJoin(m[b]!, atEnd: false, m)
        #expect(j.kind == .tee)
        #expect(j.others == [a])
        #expect(Fx.approx(j.leftCorner.y, 0.1) && Fx.approx(j.rightCorner.y, 0.1))
        let fa = WallGeometry.footprint(m[a]!, m)!, fb = WallGeometry.footprint(m[b]!, m)!
        #expect(Fx.approx(fa.area, 2.0, 1e-9), "through wall is unaffected")
        #expect(Fx.approx(fb.area, 5.9 * 0.2, 1e-9))
        #expect(overlapArea(fa, fb) < 1e-9)
    }

    @Test func fourWayCrossSharesTheCentre() throws {
        var (m, ids) = Fx.template()
        var arms: [ElementID] = []
        let c = Vec2(5, 5)
        try Fx.commit(&m) { tx in
            for d in [Vec2(1, 0), Vec2(0, 1), Vec2(-1, 0), Vec2(0, -1)] { arms.append(Fx.wall(tx, ids, c, c + d * 5)) }
        }
        var polys: [Polygon2] = []
        for id in arms {
            let j = WallGeometry.endJoin(m[id]!, atEnd: false, m)
            #expect(j.kind == .corner)
            #expect(j.others.count == 3)
            let fp = WallGeometry.footprint(m[id]!, m)!
            #expect(fp.isSimple)
            // 4.9 m × 0.2 m plus the triangle reaching the shared centre point.
            #expect(Fx.approx(fp.area, 4.9 * 0.2 + 0.2 * 0.1 / 2, 1e-9))
            polys.append(fp)
        }
        for i in 0..<4 { for k in (i + 1)..<4 { #expect(overlapArea(polys[i], polys[k]) < 1e-9) } }
    }

    @Test func disallowedJoinLeavesSquareEnds() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(10, 0)) { $0.allowJoinAtEnd = false }
            b = Fx.wall(tx, ids, Vec2(10, 0), Vec2(10, 8))
        }
        #expect(WallGeometry.endJoin(m[a]!, atEnd: true, m).kind == .free)
        #expect(WallGeometry.endJoin(m[b]!, atEnd: false, m).kind == .free)
        #expect(Fx.approx(WallGeometry.footprint(m[a]!, m)!.area, 2.0, 1e-9))
        #expect(Fx.approx(WallGeometry.footprint(m[b]!, m)!.area, 1.6, 1e-9))
    }

    @Test func wallsOnDifferentStoreysDoNotJoin() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(10, 0))
            b = Fx.wall(tx, ids, Vec2(10, 0), Vec2(10, 8), level: 1, top: 2)
        }
        #expect(WallGeometry.endJoin(m[a]!, atEnd: true, m).kind == .free)
        #expect(!WallGeometry.joinCandidates(m[a]!, m).contains { $0.id == b })
    }

    @Test(arguments: [2.0, 5.0, 12.5])
    func freeWallFootprintIsRectangle(_ length: Double) throws {
        var (m, ids) = Fx.template()
        var a: ElementID!
        try Fx.commit(&m) { tx in a = Fx.wall(tx, ids, .zero, Vec2(length, 0)) }
        let fp = WallGeometry.footprint(m[a]!, m)!
        #expect(fp.count == 4)
        #expect(Fx.approx(fp.area, length * 0.2, 1e-9))
        #expect(fp.isCounterClockwise)
    }

    @Test func arcWallFootprintArea() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!
        try Fx.commit(&m) { tx in
            let arc = Arc2(center: .zero, radius: 5, startAngle: 0, sweep: .pi / 2)
            a = tx.create(.walls, data: .wall(WallData(location: .arc(arc), topLevelID: ids.levels[1])), typeID: ids.wallTypes[Fx.generic], levelID: ids.levels[0])
        }
        let fp = WallGeometry.footprint(m[a]!, m)!
        #expect(abs(fp.area / (.pi / 2 * 5 * 0.2) - 1) < 0.01)
        #expect(abs(abs(WallGeometry.solid(m[a]!, m).signedVolume) / (.pi / 2 * 5 * 0.2 * 4) - 1) < 0.01)
    }

    // MARK: Frames

    @Test(arguments: WallLocationLine.allCases, [false, true])
    func locationLineAndFlipOffsets(_ line: WallLocationLine, _ flipped: Bool) throws {
        var (m, ids) = Fx.template()
        var a: ElementID!
        try Fx.commit(&m) { tx in a = Fx.wall(tx, ids, .zero, Vec2(6, 0), type: Fx.brick) { $0.locationLine = line; $0.flipped = flipped } }
        let f = WallGeometry.frame(m[a]!, m)!
        let asm = f.assembly
        let t = f.thickness
        #expect(Fx.approx(t, 0.38, 1e-12))
        let pos: Double
        switch line {
        case .wallCenterline: pos = t / 2
        case .coreCenterline: pos = asm.exteriorToCore + asm.coreThickness / 2
        case .finishFaceExterior: pos = 0
        case .finishFaceInterior: pos = t
        case .coreFaceExterior: pos = asm.exteriorToCore
        case .coreFaceInterior: pos = asm.exteriorToCore + asm.coreThickness
        }
        let sign = flipped ? -1.0 : 1.0
        #expect(Fx.approx(f.exteriorOffset, sign * pos, 1e-12))
        #expect(Fx.approx(f.exteriorOffset - f.interiorOffset, sign * t, 1e-12))
        #expect(Fx.approx(f.leftOffset - f.rightOffset, t, 1e-12))
        #expect(Fx.approx(WallGeometry.footprint(m[a]!, m)!.area, 6 * t, 1e-9))
    }

    @Test func frameHeightsFollowConstraints() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(5, 0)) { $0.baseOffset = 0.5; $0.topOffset = -0.25 }
            b = Fx.wall(tx, ids, Vec2(0, 3), Vec2(5, 3), top: nil) { $0.unconnectedHeight = 2.7 }
        }
        let fa = WallGeometry.frame(m[a]!, m)!, fb = WallGeometry.frame(m[b]!, m)!
        #expect(Fx.approx(fa.baseZ, 0.5) && Fx.approx(fa.topZ, 3.75))
        #expect(Fx.approx(fb.baseZ, 0) && Fx.approx(fb.topZ, 2.7))
    }

    // MARK: Stations

    @Test(arguments: [0.0, 1.5, 4.0, 7.25])
    func lineStationRoundTrip(_ s: Double) {
        let c = Curve2.line(Segment2(Vec2(1, 1), Vec2(1 + 8 * 0.6, 1 + 8 * 0.8)))
        let p = WallGeometry.point(atStation: s, on: c)
        #expect(Fx.approx(WallGeometry.station(of: p, on: c), s, 1e-9))
    }

    @Test(arguments: [0.0, 1.0, 3.5, 7.8])
    func arcStationRoundTrip(_ s: Double) {
        let c = Curve2.arc(Arc2(center: Vec2(2, 2), radius: 5, startAngle: 0.3, sweep: .pi / 2))
        let p = WallGeometry.point(atStation: s, on: c)
        #expect(Fx.approx(WallGeometry.station(of: p, on: c), s, 1e-9))
    }

    @Test func clockwiseArcStation() {
        let c = Curve2.arc(Arc2(center: .zero, radius: 4, startAngle: .pi / 2, sweep: -.pi / 2))
        #expect(Fx.approx(WallGeometry.station(of: Vec2(4, 0), on: c), 2 * .pi, 1e-9))
        #expect(Fx.approx(WallGeometry.station(of: Vec2(0, 4), on: c), 0, 1e-9))
    }
}

@Suite("Openings and inserts")
struct OpeningTests {
    func freeWall(_ build: (TransactionContext, ProjectTemplates.Ids, ElementID) -> Void = { _, _, _ in }) throws -> (BIMModel, ProjectTemplates.Ids, ElementID) {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(8, 0))
            build(tx, ids, w)
        }
        return (m, ids, w)
    }

    @Test(arguments: [
        (Fx.doorType, 1.0, 2.15), ("Door - Single Flush: 820 x 2040", 0.92, 2.09), ("Door - Double Flush: 1800 x 2100", 1.9, 2.15),
        (Fx.windowType, 1.2, 1.5), ("Window - Casement: 600 x 1200", 0.6, 1.2), ("Window - Casement: 2400 x 2100 Glazed Wall", 2.4, 2.1),
    ])
    func openingSizeIncludesFrames(_ type: String, _ w: Double, _ h: Double) throws {
        let isDoor = type.hasPrefix("Door")
        let (m, _, wall) = try freeWall { tx, ids, host in
            if isDoor { Fx.door(tx, ids, host: host, at: Vec2(4, 0), type: type) } else { Fx.window(tx, ids, host: host, at: Vec2(4, 0), type: type) }
        }
        let ins = m.hosted(by: wall)[0]
        let size = InsertGeometry.openingSize(ins, m)!
        #expect(Fx.approx(size.width, w, 1e-9))
        #expect(Fx.approx(size.height, h, 1e-9))
    }

    @Test func openingsListStationsAndElevations() throws {
        let (m, _, w) = try freeWall { tx, ids, host in
            Fx.window(tx, ids, host: host, at: Vec2(6, 0), sill: 0.9)
            Fx.door(tx, ids, host: host, at: Vec2(3, 0))
        }
        let ops = WallGeometry.openings(m[w]!, m)
        #expect(ops.count == 2)
        #expect(m[ops[0].insertID]?.category == .doors, "sorted by station")
        #expect(Fx.approx(ops[0].s0, 2.5) && Fx.approx(ops[0].s1, 3.5))
        #expect(Fx.approx(ops[0].z0, 0) && Fx.approx(ops[0].z1, 2.15))
        #expect(Fx.approx(ops[1].s0, 5.4) && Fx.approx(ops[1].s1, 6.6))
        #expect(Fx.approx(ops[1].z0, 0.9) && Fx.approx(ops[1].z1, 2.4))
    }

    @Test func sillIsRelativeToHostBase() throws {
        let (m, _, w) = try freeWall { tx, ids, host in
            tx.update(host) { $0.wall?.baseOffset = 0.3 }
            Fx.window(tx, ids, host: host, at: Vec2(4, 0), sill: 0.9)
        }
        let win = m.hosted(by: w)[0]
        #expect(Fx.approx(m.baseElevation(of: win), 1.2))
        #expect(Fx.approx(WallGeometry.openings(m[w]!, m)[0].z0, 1.2))
    }

    @Test func windowHoleIsSubtractedFromSolid() throws {
        let (m, _, w) = try freeWall { tx, ids, host in Fx.window(tx, ids, host: host, at: Vec2(4, 0), sill: 0.9) }
        let v = abs(WallGeometry.solid(m[w]!, m).signedVolume)
        #expect(Fx.approx(v, 8 * 4 * 0.2 - 1.2 * 1.5 * 0.2, 1e-6))
        let q = QuantityEngine.quantities(for: m[w]!, in: m)
        #expect(Fx.approx(q.area!, 8 * 4 - 1.2 * 1.5, 1e-9))
        #expect(Fx.approx(q.volume!, (8 * 4 - 1.2 * 1.5) * 0.2, 1e-9))
        #expect(Fx.approx(q.length!, 8) && Fx.approx(q.height!, 4) && Fx.approx(q.width!, 0.2))
    }

    @Test(arguments: [(0.5, 2), (1.2, 3), (3.0, 1), (5.0, 0)])
    func planCutRemovesOpeningsSpanningTheCut(_ z: Double, _ pieces: Int) throws {
        let (m, _, w) = try freeWall { tx, ids, host in
            Fx.door(tx, ids, host: host, at: Vec2(3, 0))
            Fx.window(tx, ids, host: host, at: Vec2(6, 0), sill: 0.9)
        }
        let cut = WallGeometry.planCut(m[w]!, atZ: z, m)
        #expect(cut.count == pieces)
        let expectedArea: Double
        switch z {
        case 0.5: expectedArea = (8 - 1.0) * 0.2
        case 1.2: expectedArea = (8 - 1.0 - 1.2) * 0.2
        case 3.0: expectedArea = 8 * 0.2
        default: expectedArea = 0
        }
        #expect(Fx.approx(cut.reduce(0) { $0 + $1.area }, expectedArea, 1e-9))
    }

    @Test func handFlipKeepsSymmetricOpening() throws {
        let (m, _, w) = try freeWall { tx, ids, host in
            let d = Fx.door(tx, ids, host: host, at: Vec2(3, 0))
            tx.update(d) { $0.insert?.handFlipped = true }
        }
        let o = WallGeometry.openings(m[w]!, m)[0]
        #expect(Fx.approx(o.s0, 2.5) && Fx.approx(o.s1, 3.5))
    }

    @Test func shorteningHostSlidesInsertBackInside() throws {
        var (m, ids, w) = try freeWall { tx, ids, host in Fx.door(tx, ids, host: host, at: Vec2(7, 0)) }
        let (_, warnings) = try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.location = .line(Segment2(.zero, Vec2(6, 0))) } }
        let door = m.hosted(by: w)[0]
        #expect(Fx.approx(door.insert!.location, Vec2(5.5, 0)))
        #expect(warnings.isEmpty)
        _ = ids
    }

    @Test func movingHostCarriesInsert() throws {
        var (m, _, w) = try freeWall { tx, ids, host in Fx.door(tx, ids, host: host, at: Vec2(3, 0)) }
        try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.location = .line(Segment2(Vec2(0, 2), Vec2(8, 2))) } }
        #expect(Fx.approx(m.hosted(by: w)[0].insert!.location, Vec2(3, 2)))
    }

    @Test func insertIsDeletedWhenHostBecomesTooShort() throws {
        var (m, _, w) = try freeWall { tx, ids, host in Fx.door(tx, ids, host: host, at: Vec2(3, 0), mark: "D7") }
        let door = m.hosted(by: w)[0].id
        let (_, warnings) = try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.location = .line(Segment2(.zero, Vec2(0.9, 0))) } }
        #expect(m[door] == nil)
        let warning = try #require(warnings.first { $0.code == "insert.removed" })
        #expect(warning.elements.contains(door) && warning.elements.contains(w))
        #expect(warning.message.contains("D7"))
    }

    @Test func headHeightParameterDrivesSill() throws {
        var (m, _, w) = try freeWall { tx, ids, host in Fx.window(tx, ids, host: host, at: Vec2(4, 0), sill: 0.9) }
        let win = m.hosted(by: w)[0].id
        #expect(Fx.approx(Parameters.value(ParameterID("insert.headHeight"), of: m[win]!, m)!.doubleValue!, 2.4))
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("insert.headHeight"), to: .double(2.6), on: win, in: tx) }
        #expect(Fx.approx(m[win]!.insert!.sillHeight, 1.1))
    }
}
