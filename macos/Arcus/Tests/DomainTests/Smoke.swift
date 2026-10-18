import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Domain smoke")
struct DomainSmokeTests {
    @Test func templateBuildsAndModelRegenerates() throws {
        let (model0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        #expect(model0.levels.count == 3)
        let tx = TransactionContext(model: model0, name: "Box")
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let wt = ids.wallTypes["Exterior - Brick on CMU"]!
        let pts = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        var walls: [ElementID] = []
        for i in 0..<4 {
            var w = WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)
            w.locationLine = .wallCenterline
            walls.append(tx.create(.walls, data: .wall(w), typeID: wt, levelID: l1))
        }
        let doorType = ids.familyTypes["Door - Single Flush: 900 x 2100"]!
        let door = tx.create(.doors, data: .insert(InsertData(location: Vec2(5, 0))), typeID: doorType, levelID: l1, hostID: walls[0])
        let winType = ids.familyTypes["Window - Casement: 1200 x 1500"]!
        tx.create(.windows, data: .insert(InsertData(location: Vec2(10, 4), sillHeight: 0.9)), typeID: winType, levelID: l1, hostID: walls[1])
        tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: l1)
        tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: Vec2(-0.5, -0.5), max: Vec2(10.5, 8.5))), edgeSlopes: [0.5, 0.5, 0.5, 0.5])),
                  typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: l2)
        let room = tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(5, 4), number: "101")), levelID: l1)
        let result = try tx.commit()
        let m = result.model

        // Wall geometry and openings.
        let wall0 = m[walls[0]]!
        #expect(WallGeometry.openings(wall0, m).count == 1)
        let solid = WallGeometry.solid(wall0, m)
        #expect(solid.triangleCount > 0)
        #expect(abs(solid.signedVolume) > 1)

        // Room bounded by the four walls.
        let b = RoomGeometry.boundary(m[room]!, m)
        #expect(b.state == .bounded)
        let wallThickness = WallGeometry.frame(wall0, m)!.thickness
        let expected = (10 - wallThickness) * (8 - wallThickness)
        #expect(abs(b.area - expected) < 1e-3)

        // Door rooms.
        let around = RoomQueries.roomsAround(insert: m[door]!, m)
        #expect(around.from?.id == room || around.to?.id == room)

        // Plan graphics.
        let plan = m[ids.planViews[l1]]!
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        #expect(g.items.contains { $0.category == .walls && $0.layer == .cut })
        #expect(g.items.contains { $0.category == .doors })

        // Elevation graphics show walls by hidden line.
        let south = m.views.first { $0.name == "South" }!
        let eg = ViewGraphicsBuilder(model: m, view: south).build()
        #expect(eg.items.contains { $0.category == .walls })
        #expect(eg.items.contains { $0.category == .levels })

        // Schedules.
        let doorSched = m.schedules.first { $0.name == "Door Schedule" }!
        let table = ScheduleEngine.compute(doorSched, m)
        #expect(table.elementCount == 1)
        let rooms = ScheduleEngine.compute(m.schedules.first { $0.name == "Room Schedule" }!, m)
        #expect(rooms.elementCount == 1)

        // Sheet graphics.
        let sheet = m.sheets.first!
        let sg = SheetGraphicsBuilder(model: m, sheet: sheet).build()
        #expect(!sg.items.isEmpty)
    }
}

@Suite("Courtyard House")
struct CourtyardHouseTests {
    @Test func generatesReferenceProject() throws {
        let t0 = Date()
        let m = CourtyardHouse.make()
        let s = CourtyardHouse.stats(m)
        print("Courtyard House: \(s) in \(Date().timeIntervalSince(t0))s")
        #expect(s.rooms >= 110)
        #expect(s.sheets == 16)
        #expect(s.schedules >= 10)
        #expect(s.elements >= 1500)
        #expect(m.levels.count == 4)
        let t1 = Date()
        var bounded = 0
        for r in m.elements(.rooms) where RoomGeometry.boundary(r, m).state == .bounded { bounded += 1 }
        print("Rooms bounded: \(bounded)/\(s.rooms) in \(Date().timeIntervalSince(t1))s")
        #expect(bounded >= s.rooms - 4)
        let t2 = Date()
        let plan = m.views.first { $0.name == "Ground Floor" && $0.view?.kind == .floorPlan }!
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        print("Ground plan items: \(g.items.count) in \(Date().timeIntervalSince(t2))s")
        let t3 = Date()
        let sec = m.views.first { $0.name == "Section 1" }!
        let sg = ViewGraphicsBuilder(model: m, view: sec).build()
        print("Section items: \(sg.items.count) in \(Date().timeIntervalSince(t3))s")
        let health = ModelHealth.check(m)
        print("Health: \(health.count) warnings: \(Dictionary(grouping: health, by: \.code).mapValues(\.count))")
    }
}

@Suite("Stairs")
struct StairTests {
    @Test(arguments: [StairShape.straight, .lShaped, .uShaped])
    func stairsProduceSolids(_ shape: StairShape) throws {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Stair")
        let sid = tx.create(.stairs, data: .stair(StairData(shape: shape, origin: Vec2(0, 0), direction: 0, width: 1.2, topLevelID: ids.levels[1])),
                            typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
        let m = try tx.commit().model
        let parts = StairGeometry.meshParts(m[sid]!, m)
        let volume = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
        #expect(volume > 0.5)
        let layout = StairGeometry.layout(m[sid]!, m)!
        #expect(layout.runs.count == (shape == .straight ? 1 : 2))
        #expect(abs(Double(layout.riserCount) * layout.riserHeight - 4.0) < 1e-9)
    }
}
