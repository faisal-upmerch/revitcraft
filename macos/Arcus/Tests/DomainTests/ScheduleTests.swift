import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Schedules")
struct ScheduleTests {
    /// Box with a partition (two rooms on Level 1), one room on Level 2, three doors and three windows.
    struct Project {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        var doors: [ElementID] = []      // marks D3, D1, D2
        var windows: [ElementID] = []    // 1200x1500 @0.9, 1200x1500 @1.2, 600x1200 @0.9
        var rooms: [ElementID] = []      // 101, 102 (Level 1), 201 (Level 2)
        func schedule(_ name: String) -> Element { model.schedules.first { $0.name == name }! }
    }

    func project() throws -> Project {
        var (m, ids) = Fx.template()
        var p = Project(model: m, ids: ids)
        try Fx.commit(&m) { tx in
            let walls = Fx.boxWalls(tx, ids)
            let part = Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8))
            p.doors = [Fx.door(tx, ids, host: walls[0], at: Vec2(2, 0), mark: "D3"),
                       Fx.door(tx, ids, host: part, at: Vec2(5, 4), mark: "D1"),
                       Fx.door(tx, ids, host: walls[0], at: Vec2(7, 0), type: "Door - Single Flush: 1000 x 2100", mark: "D2")]
            p.windows = [Fx.window(tx, ids, host: walls[2], at: Vec2(2, 8), sill: 0.9),
                         Fx.window(tx, ids, host: walls[2], at: Vec2(7, 8), sill: 1.2),
                         Fx.window(tx, ids, host: walls[1], at: Vec2(10, 4), sill: 0.9, type: "Window - Casement: 600 x 1200")]
            p.rooms = [tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(2, 4), number: "101")), levelID: ids.levels[0]),
                       tx.create(.rooms, name: "Store", data: .room(RoomData(point: Vec2(7, 4), number: "102")), levelID: ids.levels[0]),
                       tx.create(.rooms, name: "Loft", data: .room(RoomData(point: Vec2(2, 4), number: "201")), levelID: ids.levels[1])]
        }
        p.model = m
        return p
    }

    /// Adds a schedule element and returns it.
    func add(_ def: ScheduleDefinition, name: String = "Test Schedule", to p: inout Project) throws -> Element {
        var id: ElementID!
        try Fx.commit(&p.model) { tx in id = tx.create(.schedules, name: name, data: .schedule(def)) }
        return p.model[id]!
    }

    func column(_ t: ScheduleTable, _ heading: String) -> Int { t.columns.firstIndex { $0.heading == heading }! }

    @Test func doorScheduleSortsByMarkWithGrandTotal() throws {
        let p = try project()
        let t = ScheduleEngine.compute(p.schedule("Door Schedule"), p.model)
        #expect(t.elementCount == 3)
        let data = t.rows.filter { $0.kind == .data }
        #expect(data.map { $0.cells[0].text } == ["D1", "D2", "D3"])
        #expect(data.map(\.elementIDs) == [[p.doors[1]], [p.doors[2]], [p.doors[0]]])
        #expect(t.rows.last?.kind == .grandTotal)
        #expect(t.rows.last?.title == "Grand total: 3")
        let w = column(t, "Width")
        #expect(data.map { $0.cells[w].text } == ["900 mm", "1000 mm", "900 mm"])
        #expect(data[0].cells[column(t, "Type")].text == "Door - Single Flush: 900 x 2100")
        // D1 sits in the partition between the two rooms.
        let rooms = Set([data[0].cells[column(t, "From Room")].text, data[0].cells[column(t, "To Room")].text])
        #expect(rooms == ["101 Office", "102 Store"])
    }

    @Test func descendingSortAndFilters() throws {
        var p = try project()
        var def = ScheduleTemplates.doorSchedule()
        def.sorting = [ScheduleSort(fieldID: def.fields[0].id, ascending: false)]
        def.filters = [ScheduleFilter(fieldID: def.fields[0].id, op: .notEquals, value: .text("D2"))]
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        #expect(t.rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["D3", "D1"])
        #expect(t.elementCount == 2)
        var widthDef = ScheduleTemplates.doorSchedule()
        widthDef.filters = [ScheduleFilter(fieldID: widthDef.fields[2].id, op: .greater, value: .double(0.95))]
        #expect(ScheduleEngine.compute(try add(widthDef, name: "Wide", to: &p), p.model).rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["D2"])
    }

    @Test func nonItemizedWindowScheduleGroupsByType() throws {
        let p = try project()
        let t = ScheduleEngine.compute(p.schedule("Window Schedule"), p.model)
        let data = t.rows.filter { $0.kind == .data }
        #expect(data.count == 2)
        let big = try #require(data.first { $0.elementIDs.count == 2 })
        #expect(Set(big.elementIDs) == Set(p.windows[0...1]))
        #expect(big.cells[column(t, "Count")].text == "2")
        #expect(big.cells[column(t, "Width")].text == "1200 mm")
        #expect(big.cells[column(t, "Sill Height")].text == "", "values that differ within a group are blank")
        let small = try #require(data.first { $0.elementIDs.count == 1 })
        #expect(small.cells[column(t, "Sill Height")].text == "900 mm")
        #expect(t.rows.last?.kind == .grandTotal)
        #expect(t.rows.last?.cells[column(t, "Count")].text == "3")
    }

    @Test func nonItemizedMaximumFieldShowsGroupMaximum() throws {
        var p = try project()
        var def = ScheduleTemplates.windowSchedule()
        let sill = def.fields.firstIndex { $0.heading == "Sill Height" }!
        def.fields[sill].total = .maximum
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        let big = try #require(t.rows.first { $0.kind == .data && $0.elementIDs.count == 2 })
        #expect(big.cells[sill].text == "1200 mm")
        #expect(t.rows.last?.cells[sill].text == "1200 mm", "grand total maximum")
    }

    @Test func minimumAndMaximumTotal() throws {
        var p = try project()
        var def = ScheduleTemplates.windowSchedule()
        def.itemizeEveryInstance = true
        let sill = def.fields.firstIndex { $0.heading == "Sill Height" }!
        def.fields[sill].total = .minimum
        #expect(ScheduleEngine.compute(try add(def, name: "Min", to: &p), p.model).rows.last?.cells[sill].text == "900 mm")
        def.fields[sill].total = .minAndMax
        let t = ScheduleEngine.compute(try add(def, name: "MinMax", to: &p), p.model)
        let text = t.rows.last!.cells[sill].text
        #expect(text.contains("900") && text.contains("1200"))
    }

    @Test func roomScheduleGroupsByLevelWithHeadersAndFooters() throws {
        let p = try project()
        let t = ScheduleEngine.compute(p.schedule("Room Schedule"), p.model)
        #expect(t.rows.map(\.kind) == [.groupHeader, .data, .data, .groupFooter, .groupHeader, .data, .groupFooter, .grandTotal])
        #expect(t.rows[0].title == "Level 1")
        #expect(t.rows[3].title == "Level 1: 2")
        #expect(t.rows[4].title == "Level 2")
        #expect(t.rows[6].title == "Level 2: 1")
        #expect(t.rows[7].title == "Grand total: 3")
        #expect(t.rows[1].cells[0].text == "101" && t.rows[2].cells[0].text == "102")
        let area = column(t, "Area")
        let a101 = RoomGeometry.boundary(p.model[p.rooms[0]]!, p.model).area
        let a102 = RoomGeometry.boundary(p.model[p.rooms[1]]!, p.model).area
        #expect(Fx.approx(t.rows[3].cells[area].value!.doubleValue!, a101 + a102, 1e-9))
        #expect(Fx.approx(t.rows[7].cells[area].value!.doubleValue!, a101 + a102, 1e-9), "unbounded Loft adds 0")
        #expect(t.rows[3].elementIDs.count == 2)
    }

    @Test func calculatedFieldUsesOtherFieldsByHeading() throws {
        var p = try project()
        var def = ScheduleTemplates.doorSchedule()
        def.fields.append(ScheduleField(source: .formula("Width * Height", .area), heading: "Leaf Area"))
        def.fields.append(ScheduleField(source: .formula("Width * Nonexistent", .area), heading: "Broken"))
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        let data = t.rows.filter { $0.kind == .data }
        let leaf = column(t, "Leaf Area")
        #expect(Fx.approx(data[0].cells[leaf].value!.doubleValue!, 0.9 * 2.1, 1e-12))
        #expect(Fx.approx(data[1].cells[leaf].value!.doubleValue!, 1.0 * 2.1, 1e-12))
        #expect(data.allSatisfy { $0.cells[column(t, "Broken")].text.isEmpty })
        #expect(!data[0].cells[leaf].isEditable)
    }

    @Test func percentageOfTotal() throws {
        var p = try project()
        var def = ScheduleTemplates.roomSchedule()
        def.sorting = [ScheduleSort(fieldID: def.fields[0].id)]
        let areaID = def.fields[3].id
        def.fields.append(ScheduleField(source: .percentage(of: areaID, byGroup: false), heading: "Share"))
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        let share = column(t, "Share")
        let values = t.rows.filter { $0.kind == .data }.compactMap { $0.cells[share].value?.doubleValue }
        #expect(Fx.approx(values.reduce(0, +), 1, 1e-9))
    }

    @Test func percentageWithinGroup() throws {
        var p = try project()
        var def = ScheduleTemplates.roomSchedule()
        let areaID = def.fields[3].id
        def.fields.append(ScheduleField(source: .percentage(of: areaID, byGroup: true), heading: "Share of Level"))
        var sid: ElementID!
        try Fx.commit(&p.model) { tx in
            // A bounded room on Level 2 so both groups have area.
            Fx.boxWalls(tx, p.ids, w: 4, h: 4, origin: Vec2(20, 0), level: 1, top: 2)
            tx.create(.rooms, name: "Attic", data: .room(RoomData(point: Vec2(22, 2), number: "202")), levelID: p.ids.levels[1])
            sid = tx.create(.schedules, name: "Shares", data: .schedule(def))
        }
        let t = ScheduleEngine.compute(p.model[sid]!, p.model)
        let share = column(t, "Share of Level")
        var groups: [[Double]] = []
        for r in t.rows {
            if r.kind == .groupHeader { groups.append([]) }
            if r.kind == .data, let v = r.cells[share].value?.doubleValue { groups[groups.count - 1].append(v) }
        }
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { Fx.approx($0.reduce(0, +), 1, 1e-9) })
    }

    @Test func hiddenFieldsSortButDoNotShow() throws {
        var p = try project()
        var def = ScheduleTemplates.doorSchedule()
        def.fields[2].hidden = true   // Width
        def.sorting = [ScheduleSort(fieldID: def.fields[2].id, ascending: false), ScheduleSort(fieldID: def.fields[0].id)]
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        #expect(!t.columns.contains { $0.heading == "Width" })
        #expect(t.columns.count == def.fields.count - 1)
        #expect(t.rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["D2", "D1", "D3"])
    }

    @Test func conditionalFormatHighlightsCells() throws {
        var p = try project()
        var def = ScheduleTemplates.doorSchedule()
        def.fields[2].conditionalFormat = ConditionalFormat(op: .greater, value: .double(0.95), background: RGBColor(1, 0, 0))
        let t = ScheduleEngine.compute(try add(def, to: &p), p.model)
        let data = t.rows.filter { $0.kind == .data }
        #expect(data.map { $0.cells[2].background != nil } == [false, true, false])
    }

    @Test func cellEditabilityFollowsParameters() throws {
        let p = try project()
        let doors = ScheduleEngine.compute(p.schedule("Door Schedule"), p.model).rows.first { $0.kind == .data }!
        #expect(doors.cells[0].isEditable && doors.cells[0].parameterID == .mark)
        #expect(!doors.cells[4].isEditable, "From Room is calculated")
        let rooms = ScheduleEngine.compute(p.schedule("Room Schedule"), p.model)
        let row = rooms.rows.first { $0.kind == .data }!
        #expect(row.cells[1].isEditable, "Name")
        #expect(!row.cells[3].isEditable, "Area")
        #expect(rooms.rows.first { $0.kind == .groupFooter }!.cells.allSatisfy { !$0.isEditable })
    }

    @Test func editsThroughScheduleCellsWriteBack() throws {
        var p = try project()
        let row = ScheduleEngine.compute(p.schedule("Door Schedule"), p.model).rows.first { $0.kind == .data }!
        let cell = row.cells[0]
        try Fx.commit(&p.model) { tx in for id in row.elementIDs { try Parameters.set(cell.parameterID!, to: .text("D0"), on: id, in: tx) } }
        #expect(p.model[p.doors[1]]!.mark == "D0")
        let again = ScheduleEngine.compute(p.schedule("Door Schedule"), p.model)
        #expect(again.rows.first { $0.kind == .data }!.cells[0].text == "D0")
    }

    @Test func csvExportQuotesCommasQuotesAndNewlines() throws {
        var p = try project()
        try Fx.commit(&p.model) { tx in
            tx.update(p.doors[1]) { $0.comments = "Say \"hi\", ok" }
            tx.update(p.doors[2]) { $0.comments = "two\nlines" }
        }
        let csv = ScheduleEngine.csv(ScheduleEngine.compute(p.schedule("Door Schedule"), p.model))
        let lines = csv.components(separatedBy: "\r\n")
        #expect(csv.hasSuffix("\r\n"))
        #expect(lines[0] == "Mark,Type,Width,Height,From Room,To Room,Fire Rating,Comments")
        #expect(lines[1].hasPrefix("D1,Door - Single Flush: 900 x 2100,900 mm,2100 mm,"))
        #expect(lines[1].hasSuffix(",\"Say \"\"hi\"\", ok\""))
        #expect(lines[2].hasSuffix(",\"two\nlines\""))
        #expect(lines.contains { $0.hasPrefix("Grand total: 3,") })
    }

    @Test func csvGroupHeadersAndBlankLines() throws {
        var p = try project()
        var def = ScheduleTemplates.roomSchedule()
        def.sorting[0].blankLine = true
        let csv = ScheduleEngine.csv(ScheduleEngine.compute(try add(def, to: &p), p.model))
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.contains("Level 1,,,,,,"))
        #expect(lines.contains(",,,,,,"))
        #expect(lines.contains { $0.hasPrefix("Level 1: 2,") })
    }

    @Test func sheetListHonoursAppearsInList() throws {
        var p = try project()
        try Fx.commit(&p.model) { tx in
            tx.create(.sheets, name: "Plans", data: .sheet(SheetData(number: "A102")))
            var hidden = SheetData(number: "A000")
            hidden.appearsInSheetList = false
            tx.create(.sheets, name: "Internal", data: .sheet(hidden))
            tx.create(.sheets, name: "Details", data: .sheet(SheetData(number: "A110")))
        }
        let t = ScheduleEngine.compute(p.schedule("Sheet List"), p.model)
        #expect(t.rows.map { $0.cells[0].text } == ["A101", "A102", "A110"])
    }

    @Test func phaseFilterLimitsScheduledElements() throws {
        var p = try project()
        let wallsBefore = p.model.elements(.walls).map(\.id)
        var existing: ElementID!
        try Fx.commit(&p.model) { tx in
            existing = Fx.wall(tx, p.ids, Vec2(20, 0), Vec2(25, 0))
            tx.update(existing) { $0.phaseCreated = p.ids.phases[0] }
            tx.update(wallsBefore[0]) { $0.phaseDemolished = p.ids.phases[1] }
        }
        var def = ScheduleTemplates.wallQuantities()
        def.itemizeEveryInstance = true
        def.phaseFilter = .showNew
        let showNew = ScheduleEngine.compute(try add(def, name: "New", to: &p), p.model)
        let newIDs = Set(showNew.rows.flatMap(\.elementIDs))
        #expect(!newIDs.contains(existing))
        def.phaseFilter = .showPreviousPhase
        #expect(Set(ScheduleEngine.compute(try add(def, name: "Prev", to: &p), p.model).rows.filter { $0.kind == .data }.flatMap(\.elementIDs)) == [existing])
        def.phaseFilter = .showComplete
        let complete = Set(ScheduleEngine.compute(try add(def, name: "Complete", to: &p), p.model).rows.filter { $0.kind == .data }.flatMap(\.elementIDs))
        #expect(!complete.contains(wallsBefore[0]), "demolished in this phase")
        #expect(complete.contains(existing))
        def.phaseFilter = .showAll
        #expect(ScheduleEngine.compute(try add(def, name: "All", to: &p), p.model).elementCount == wallsBefore.count + 1)
    }

    @Test func materialTakeoffListsEveryLayer() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(6, 0), type: Fx.brick) }
        var def = ScheduleDefinition(kind: .materialTakeoff, categories: [.walls], fields: [
            ScheduleField(source: .material("Name"), heading: "Material"), ScheduleField(source: .material("Volume"), heading: "Volume"),
        ])
        def.fields[1].total = .total
        def.grandTotals = true
        var sid: ElementID!
        try Fx.commit(&m) { tx in sid = tx.create(.schedules, name: "Takeoff", data: .schedule(def)) }
        let t = ScheduleEngine.compute(m[sid]!, m)
        let data = t.rows.filter { $0.kind == .data }
        #expect(data.count == 4)
        #expect(Set(data.map { $0.cells[0].text }) == ["Brick, Common", "Rigid Insulation", "Concrete Masonry Units", "Plaster"])
        let total = t.rows.last!.cells[1].value!.doubleValue!
        #expect(Fx.approx(total, QuantityEngine.quantities(for: m[w]!, in: m).volume!, 1e-9))
    }

    @Test func scheduleLayoutWidthMatchesColumns() throws {
        let p = try project()
        let t = ScheduleEngine.compute(p.schedule("Door Schedule"), p.model)
        // POLISH: columns keep their set width or widen to fit their contents; the grid and totalWidth agree.
        let fit = ScheduleLayout.fit(t)
        #expect(zip(fit.widths, t.columns).allSatisfy { $0 >= $1.width - 1e-12 })
        #expect(Fx.approx(t.totalWidth, ScheduleLayout.grid(t).width, 1e-12))
        let prims = ScheduleLayout.primitives(t, topLeft: Vec2(0, 0.5))
        let texts = prims.compactMap { if case .text(let g) = $0 { return g.string } else { return nil } }
        #expect(texts.contains("DOOR SCHEDULE"))
        #expect(texts.contains("D1") && texts.contains("Grand total: 3"))
    }
}
