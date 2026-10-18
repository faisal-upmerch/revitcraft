import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-SCHED: editable schedule cells (write-back, units, drop-downs, read-only cells, undo) and schedule definition
/// edits (fields, filters, sorting/grouping, header groups, appearance).
@Suite("Schedule editing (BL-SCHED)")
@MainActor
struct ScheduleEditingTests {
    @MainActor struct Project {
        var session: DocumentSession
        let ids: ProjectTemplates.Ids
        var doors: [ElementID] = []   // D3, D1, D2 (D1 on the partition; D2 is 1000 x 2100)
        var windows: [ElementID] = [] // two 1200 x 1500, one 600 x 1200
        var model: BIMModel { session.model }
        func schedule(_ name: String) -> Element { model.schedules.first { $0.name == name }! }
        func table(_ name: String) -> ScheduleTable { ScheduleEngine.compute(schedule(name), model) }
    }

    func project() throws -> Project {
        var (m, ids) = Fx.template()
        var doors: [ElementID] = [], windows: [ElementID] = []
        try Fx.commit(&m) { tx in
            let walls = Fx.boxWalls(tx, ids)
            let part = Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8))
            doors = [Fx.door(tx, ids, host: walls[0], at: Vec2(2, 0), mark: "D3"),
                     Fx.door(tx, ids, host: part, at: Vec2(5, 4), mark: "D1"),
                     Fx.door(tx, ids, host: walls[0], at: Vec2(7, 0), type: "Door - Single Flush: 1000 x 2100", mark: "D2")]
            windows = [Fx.window(tx, ids, host: walls[2], at: Vec2(2, 8), sill: 0.9),
                       Fx.window(tx, ids, host: walls[2], at: Vec2(7, 8), sill: 1.2),
                       Fx.window(tx, ids, host: walls[1], at: Vec2(10, 4), sill: 0.9, type: "Window - Casement: 600 x 1200")]
            tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(2, 4), number: "101")), levelID: ids.levels[0])
            tx.create(.rooms, name: "Store", data: .room(RoomData(point: Vec2(7, 4), number: "102")), levelID: ids.levels[0])
        }
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        return Project(session: s, ids: ids, doors: doors, windows: windows)
    }

    /// One undo group around `body` (the app groups by event; tests group explicitly).
    func step(_ p: Project, _ body: () -> Void) { p.session.undoManager.beginUndoGrouping(); body(); p.session.undoManager.endUndoGrouping() }
    func col(_ t: ScheduleTable, _ heading: String) -> Int { t.columns.firstIndex { $0.heading == heading }! }
    func dataRow(_ t: ScheduleTable, _ first: String) -> Int { t.rows.firstIndex { $0.kind == .data && $0.cells.first?.text == first }! }

    @discardableResult
    func addSchedule(_ p: Project, _ def: ScheduleDefinition, name: String = "Test") -> ElementID {
        var id: ElementID!
        step(p) { p.session.perform("Add") { tx in id = tx.create(.schedules, name: name, data: .schedule(def)) } }
        return id
    }

    // MARK: Cell edits

    @Test func markCellWritesBackAndUndoes() throws {
        let p = try project()
        let sid = p.schedule("Door Schedule").id
        let t = p.table("Door Schedule")
        let r = dataRow(t, "D1"), c = col(t, "Mark")
        let target = ScheduleEditing.target(t, row: r, column: c, schedule: p.schedule("Door Schedule"), model: p.model)
        #expect(target.editor == .text && target.elementIDs == [p.doors[1]])
        step(p) { #expect(p.session.editScheduleCell(sid, table: t, row: r, column: c, text: "7")) }
        #expect(p.model[p.doors[1]]?.mark == "7")
        // A door tag in the plan shows the new mark.
        let plan = p.ids.planViews[p.ids.levels[0]]!
        let tagType = TagTool.defaultTagType(for: .doors, p.model)
        step(p) { p.session.perform("Tag") { tx in tx.create(.tags, data: .tag(TagData(taggedID: p.doors[1], head: Vec2(5, 4.5))), typeID: tagType, ownerViewID: plan) } }
        let tagTexts = ViewGraphicsBuilder(model: p.model, view: p.model[plan]!).build().items.filter { $0.category == .tags }
            .flatMap(\.primitives).compactMap { if case .text(let t) = $0 { return t.string } else { return nil } }
        #expect(tagTexts.contains("7"), "tag texts: \(tagTexts)")
        p.session.undoManager.undo()
        // The live table re-sorts by Mark: "7" now sorts before the D-marks.
        #expect(p.table("Door Schedule").rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["7", "D2", "D3"])
        p.session.undoManager.undo()
        #expect(p.model[p.doors[1]]?.mark == "D1")
        p.session.undoManager.redo()
        #expect(p.model[p.doors[1]]?.mark == "7")
    }

    @Test func typeCellOffersTypesAndSwapsTheType() throws {
        let p = try project()
        let s = p.schedule("Door Schedule"), t = p.table("Door Schedule")
        let r = dataRow(t, "D1"), c = col(t, "Type")
        let target = ScheduleEditing.target(t, row: r, column: c, schedule: s, model: p.model)
        guard case .options(let opts) = target.editor else { Issue.record("Type cell should be a drop-down"); return }
        let wide = try #require(opts.first { $0.title == "Door - Single Flush: 1000 x 2100" })
        #expect(opts.allSatisfy { $0.value.refValue.flatMap { p.model[$0]?.typeData?.instanceCategory } == .doors })
        step(p) { #expect(p.session.editScheduleCell(s.id, table: t, row: r, column: c, value: wide.value)) }
        #expect(p.model[p.doors[1]]?.typeID == wide.value.refValue)
        // Typing the type name works too (the family prefix is optional).
        let t2 = p.table("Door Schedule")
        step(p) { #expect(p.session.editScheduleCell(s.id, table: t2, row: dataRow(t2, "D1"), column: c, text: "900 x 2100")) }
        #expect(p.model[p.doors[1]]?.typeID == p.ids.familyTypes[Fx.doorType])
        p.session.undoManager.undo()
        #expect(p.model[p.doors[1]]?.typeID == wide.value.refValue)
    }

    @Test func typeNameFieldSwapsWithinTheFamily() throws {
        let p = try project()
        var def = ScheduleDefinition(kind: .category, categories: [.doors], fields: [ScheduleTemplates.field("mark", "Mark"), ScheduleTemplates.field("typeName", "Type")])
        def.sorting = [ScheduleSort(fieldID: def.fields[0].id)]
        let sid = addSchedule(p, def)
        let t = ScheduleEngine.compute(p.model[sid]!, p.model)
        let target = ScheduleEditing.target(t, row: dataRow(t, "D3"), column: 1, schedule: p.model[sid]!, model: p.model)
        guard case .options(let opts) = target.editor else { Issue.record("Type name should offer the family's types"); return }
        #expect(opts.map(\.title).contains("1000 x 2100"))
        step(p) { #expect(p.session.editScheduleCell(sid, table: t, row: dataRow(t, "D3"), column: 1, text: "1000 x 2100")) }
        #expect(p.model[p.doors[0]]?.typeID == p.ids.familyTypes["Door - Single Flush: 1000 x 2100"])
    }

    @Test func readOnlyCellsRefuseWithAReason() throws {
        let p = try project()
        let sid = p.schedule("Window Schedule").id, t = p.table("Window Schedule")
        let r = try #require(t.rows.firstIndex { $0.kind == .data })
        let count = ScheduleEditing.target(t, row: r, column: col(t, "Count"), schedule: p.model[sid]!, model: p.model)
        guard case .readOnly(let why) = count.editor else { Issue.record("Count must be read-only"); return }
        #expect(why.contains("calculated"))
        let total = ScheduleEditing.target(t, row: t.rows.count - 1, column: 0, schedule: p.model[sid]!, model: p.model)
        #expect(!total.editor.isEditable)
        let before = p.model.revision
        step(p) { #expect(!p.session.editScheduleCell(sid, table: t, row: r, column: col(t, "Count"), text: "5")) }
        #expect(p.session.lastError != nil)
        #expect(p.model.revision == before)
        // From Room is computed from the model.
        let dt = p.table("Door Schedule")
        #expect(!ScheduleEditing.target(dt, row: dataRow(dt, "D1"), column: col(dt, "From Room"), schedule: p.schedule("Door Schedule"), model: p.model).editor.isEditable)
    }

    @Test func numbersWithUnitsWriteToTheType() throws {
        let p = try project()
        let s = p.schedule("Door Schedule"), t = p.table("Door Schedule")
        let r = dataRow(t, "D2"), c = col(t, "Height")
        let target = ScheduleEditing.target(t, row: r, column: c, schedule: s, model: p.model)
        #expect(target.editor == .text)
        #expect(ScheduleEditing.writesToType(target, model: p.model))
        step(p) { #expect(p.session.editScheduleCell(s.id, table: t, row: r, column: c, text: "2.2 m")) }
        let typeID = try #require(p.model[p.doors[2]]?.typeID)
        #expect(p.model[typeID]?.typeData?.params[Parameters.familyParamID("Height")]?.doubleValue.map { Fx.approx($0, 2.2) } == true)
        #expect(p.table("Door Schedule").rows[dataRow(p.table("Door Schedule"), "D2")].cells[c].text == "2200 mm")
        // Bad input is refused and leaves the model alone.
        step(p) { #expect(!p.session.editScheduleCell(s.id, table: p.table("Door Schedule"), row: r, column: c, text: "tall")) }
        #expect(p.model[typeID]?.typeData?.params[Parameters.familyParamID("Height")]?.doubleValue.map { Fx.approx($0, 2.2) } == true)
    }

    @Test func groupedRowEditWritesEveryElementAsOneUndoStep() throws {
        let p = try project()
        var def = ScheduleDefinition(kind: .category, categories: [.windows], fields: [ScheduleTemplates.field("familyAndType", "Type"), ScheduleTemplates.field("comments", "Comments"),
                                                                                       ScheduleField(source: .count, heading: "Count")])
        def.sorting = [ScheduleSort(fieldID: def.fields[0].id)]
        def.itemizeEveryInstance = false
        let sid = addSchedule(p, def)
        let t = ScheduleEngine.compute(p.model[sid]!, p.model)
        let r = try #require(t.rows.firstIndex { $0.kind == .data && $0.elementIDs.count == 2 })
        step(p) { #expect(p.session.editScheduleCell(sid, table: t, row: r, column: 1, text: "Obscured")) }
        #expect(p.model[p.windows[0]]?.comments == "Obscured" && p.model[p.windows[1]]?.comments == "Obscured")
        #expect(p.model[p.windows[2]]?.comments == "")
        p.session.undoManager.undo()
        #expect(p.model[p.windows[0]]?.comments == "" && p.model[p.windows[1]]?.comments == "")
    }

    @Test func levelFieldIsADropDown() throws {
        let p = try project()
        let sid = p.schedule("Door Schedule").id
        step(p) {
            p.session.editSchedule(sid, "Add Field") { $0.fields.append(ScheduleTemplates.field("level", "Level")) }
        }
        let t = p.table("Door Schedule")
        let c = col(t, "Level")
        #expect(t.rows.filter { $0.kind == .data }.allSatisfy { $0.cells[c].text == p.model[p.ids.levels[0]]?.name })
        let target = ScheduleEditing.target(t, row: dataRow(t, "D3"), column: c, schedule: p.model[sid]!, model: p.model)
        guard case .options(let opts) = target.editor else { Issue.record("Level should be a drop-down"); return }
        #expect(opts.map(\.title) == p.model.levels.map(\.name))
        step(p) { #expect(p.session.editScheduleCell(sid, table: t, row: dataRow(t, "D3"), column: c, text: p.model[p.ids.levels[1]]!.name)) }
        #expect(p.model[p.doors[0]]?.levelID == p.ids.levels[1])
    }

    // MARK: Definition edits

    @Test func removingAFieldCleansFiltersSortsAndGroups() {
        var def = ScheduleTemplates.doorSchedule()
        let mark = def.fields[0].id, type = def.fields[1].id
        def.filters = [ScheduleFilter(fieldID: mark, op: .hasValue, value: .text(""))]
        def.groupHeaders([mark, type], title: "Identity")
        #expect(def.headerGroups.first?.fieldIDs == [mark, type])
        def.removeField(mark)
        #expect(def.filters.isEmpty && def.sorting.isEmpty)
        #expect(def.headerGroups.first?.fieldIDs == [type])
        def.ungroupHeaders([type])
        #expect(def.headerGroups.isEmpty && def.headerGroupStorage == nil)
        var d2 = ScheduleTemplates.doorSchedule()
        d2.insertField(ScheduleTemplates.field("level", "Level"), before: d2.fields[1].id)
        #expect(d2.fields.map(\.heading).prefix(3) == ["Mark", "Level", "Type"])
    }

    @Test func filtersUseFieldUnitsAndNames() throws {
        let p = try project()
        var def = ScheduleTemplates.doorSchedule()
        def.fields.append(ScheduleTemplates.field("level", "Level"))
        // "950" on a length field means 950 mm in a metric project.
        def.filters = [ScheduleFilter(fieldID: def.fields[2].id, op: .greater, value: .text("950"))]
        let sid = addSchedule(p, def)
        #expect(ScheduleEngine.compute(p.model[sid]!, p.model).rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["D2"])
        // Element references match by name.
        let level2 = p.model[p.ids.levels[1]]!.name
        step(p) {
            p.session.editSchedule(sid, "Filter") { $0.filters = [ScheduleFilter(fieldID: $0.fields.last!.id, op: .equals, value: .text(p.model[p.ids.levels[0]]!.name))] }
        }
        #expect(ScheduleEngine.compute(p.model[sid]!, p.model).elementCount == 3)
        step(p) {
            p.session.editSchedule(sid, "Filter") { $0.filters = [ScheduleFilter(fieldID: $0.fields.last!.id, op: .equals, value: .text(level2))] }
        }
        #expect(ScheduleEngine.compute(p.model[sid]!, p.model).elementCount == 0)
    }

    @Test func fireRatingNotEmptyFilter() throws {
        let p = try project()
        let fire = ParameterID("type.fireRating")
        step(p) {
            p.session.setParameter(fire, value: .text("30 min"), on: [p.doors[2]], name: "Fire Rating")
        }
        var def = ScheduleTemplates.doorSchedule()
        let fr = def.fields.first { $0.heading == "Fire Rating" }!.id
        def.filters = [ScheduleFilter(fieldID: fr, op: .hasValue, value: .text(""))]
        let sid = addSchedule(p, def)
        let t = ScheduleEngine.compute(p.model[sid]!, p.model)
        #expect(t.rows.filter { $0.kind == .data }.map { $0.cells[0].text } == ["D2"])
        #expect(!ScheduleEditing.opNeedsValue(.hasValue) && ScheduleEditing.opNeedsValue(.equals))
    }

    @Test func sortByMarkAndGroupByLevelWithHeader() throws {
        let p = try project()
        let sid = p.schedule("Door Schedule").id
        // Move D3 to Level 2 so there are two groups.
        step(p) {
            p.session.setParameter(ParameterID("level"), value: .ref(p.ids.levels[1]), on: [p.doors[0]], name: "Level")
        }
        step(p) {
            p.session.editSchedule(sid, "Group") { def in
                def.fields.append(ScheduleTemplates.field("level", "Level"))
                let mark = def.fields[0].id, level = def.fields.last!.id
                var g = ScheduleSort(fieldID: level, header: true)
                g.footer = true
                def.sorting = [g, ScheduleSort(fieldID: mark)]
            }
        }
        let t = p.table("Door Schedule")
        let l1 = p.model[p.ids.levels[0]]!.name, l2 = p.model[p.ids.levels[1]]!.name
        #expect(t.rows.filter { $0.kind == .groupHeader }.map(\.title) == [l1, l2])
        let firstGroup = t.rows.prefix { !($0.kind == .groupHeader && $0.title == l2) }.filter { $0.kind == .data }.map { $0.cells[0].text }
        #expect(firstGroup == ["D1", "D2"])
        #expect(t.rows.contains { $0.kind == .groupFooter && $0.title == "\(l2): 1" })
    }

    // MARK: Appearance and header groups

    @Test func appearanceAndHeaderGroupsLayOut() throws {
        let p = try project()
        let sid = p.schedule("Door Schedule").id
        let plain = ScheduleLayout.height(p.table("Door Schedule"))
        step(p) {
            p.session.editSchedule(sid, "Appearance") { def in
                def.groupHeaders([def.fields[2].id, def.fields[3].id], title: "Size")
                def.showTitle = false
                var a = def.appearance
                a.gridLines = false
                a.headerShading = RGBColor(0.9, 0.9, 0.9)
                def.appearance = a
            }
        }
        let t = p.table("Door Schedule")
        #expect(t.headerSpans.map(\.columns) == [2..<4] && t.headerSpans.first?.title == "Size")
        #expect(Fx.approx(ScheduleLayout.height(t), plain - ScheduleLayout.titleHeight + ScheduleLayout.rowHeight, 1e-12))
        let prims = ScheduleLayout.primitives(t, topLeft: Vec2(0, 0.5))
        let texts = prims.compactMap { if case .text(let g) = $0 { return g.string } else { return nil } }
        #expect(texts.contains("Size") && !texts.contains("DOOR SCHEDULE"))
        #expect(prims.contains { if case .fill = $0 { return true } else { return false } })
    }

    @Test func olderDefinitionsDecodeWithDefaultAppearance() throws {
        let def = ScheduleTemplates.doorSchedule()
        let data = try JSONEncoder().encode(def)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("appearanceStorage") && !json.contains("headerGroupStorage"))
        let back = try JSONDecoder().decode(ScheduleDefinition.self, from: data)
        #expect(back.appearance == ScheduleAppearance() && back.headerGroups.isEmpty && back == def)
        var styled = def
        styled.appearance.gridLines = false
        let round = try JSONDecoder().decode(ScheduleDefinition.self, from: try JSONEncoder().encode(styled))
        #expect(round.appearance.gridLines == false)
    }
}
