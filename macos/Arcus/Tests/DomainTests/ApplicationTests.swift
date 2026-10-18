import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// MARK: - Undo / redo through DocumentSession

@MainActor
@Suite("Document session undo and redo")
struct SessionUndoTests {
    @MainActor struct Env {
        let session: DocumentSession
        let ids: ProjectTemplates.Ids
        func step(_ body: () -> Void) {
            session.undoManager.beginUndoGrouping(); body(); session.undoManager.endUndoGrouping()
        }
        var model: BIMModel { session.model }
    }

    func env() -> Env {
        let (m, ids) = Fx.template()
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        return Env(session: s, ids: ids)
    }

    /// Creates a wall with a door and returns their ids.
    func wallWithDoor(_ e: Env) -> (ElementID, ElementID) {
        var w: ElementID!, d: ElementID!
        e.step { e.session.perform("Wall") { tx in w = Fx.wall(tx, e.ids, .zero, Vec2(8, 0)); d = Fx.door(tx, e.ids, host: w, at: Vec2(3, 0)) } }
        return (w, d)
    }

    @Test func createUndoRedo() {
        let e = env()
        let before = e.model.elements
        let (w, d) = wallWithDoor(e)
        #expect(e.session.canUndo && !e.session.canRedo)
        #expect(e.session.undoManager.undoActionName == "Wall")
        e.session.undoManager.undo()
        #expect(e.model.elements == before)
        #expect(e.session.canRedo)
        e.session.undoManager.redo()
        #expect(e.model[w] != nil && e.model[d]?.hostID == w)
    }

    @Test func moveUndoRestoresHostAndInsert() throws {
        let e = env()
        let (w, d) = wallWithDoor(e)
        let before = e.model.elements
        e.step { e.session.perform("Move") { tx in try ElementOperations.transform([w], by: .translation(Vec2(2, 3)), in: tx, viewID: nil) } }
        #expect(Fx.approx(e.model[d]!.insert!.location, Vec2(5, 3)))
        #expect(e.model[w]!.wall!.location.start == Vec2(2, 3))
        e.session.undoManager.undo()
        #expect(e.model.elements == before)
        e.session.undoManager.redo()
        #expect(Fx.approx(e.model[d]!.insert!.location, Vec2(5, 3)))
    }

    @Test func parameterAndTypeChangesUndo() {
        let e = env()
        let (w, d) = wallWithDoor(e)
        e.step { e.session.setParameter(.mark, text: "D-9", on: [d], type: .text, name: "Mark") }
        #expect(e.model[d]!.mark == "D-9")
        let brick = e.ids.wallTypes[Fx.brick]!
        e.step { e.session.setParameter(ParameterID("familyAndType"), value: .ref(brick), on: [w], name: "Type") }
        #expect(e.model[w]!.typeID == brick)
        e.session.undoManager.undo()
        #expect(e.model[w]!.typeID == e.ids.wallTypes[Fx.generic])
        #expect(e.model[d]!.mark == "D-9")
        e.session.undoManager.undo()
        #expect(e.model[d]!.mark == "1") // BL-CANVAS: doors are numbered on placement (ARCUS-045)
        e.session.undoManager.redo()
        e.session.undoManager.redo()
        #expect(e.model[d]!.mark == "D-9" && e.model[w]!.typeID == brick)
    }

    @Test func deleteUndoBringsBackDependents() {
        let e = env()
        let (w, d) = wallWithDoor(e)
        e.step { e.session.delete([w]) }
        #expect(e.model[w] == nil && e.model[d] == nil)
        #expect(e.session.undoManager.undoActionName == "Delete Wall")
        e.session.undoManager.undo()
        #expect(e.model[w] != nil && e.model[d]?.hostID == w)
    }

    @Test func multiStepStackUndoesToOriginalAndRedoesToFinal() {
        let e = env()
        let original = e.model.elements
        var ids: [ElementID] = []
        for i in 0..<4 {
            e.step { e.session.perform("Wall \(i)") { tx in ids.append(Fx.wall(tx, e.ids, Vec2(0, Double(i) * 3), Vec2(6, Double(i) * 3))) } }
        }
        e.step { e.session.perform("Edit") { tx in tx.update(ids[0]) { $0.mark = "A" } } }
        e.step { e.session.delete([ids[1]]) }
        let final = e.model.elements
        var undos = 0
        while e.session.canUndo { e.session.undoManager.undo(); undos += 1 }
        #expect(undos == 6)
        #expect(e.model.elements == original)
        while e.session.canRedo { e.session.undoManager.redo() }
        #expect(e.model.elements == final)
    }

    @Test func newCommitClearsRedo() {
        let e = env()
        _ = wallWithDoor(e)
        e.session.undoManager.undo()
        #expect(e.session.canRedo)
        e.step { e.session.perform("Other") { tx in Fx.wall(tx, e.ids, Vec2(0, 5), Vec2(5, 5)) } }
        #expect(!e.session.canRedo)
    }

    @Test func rejectedAndEmptyTransactionsAreNotUndoable() {
        let e = env()
        let rev = e.model.revision
        // No undo group is opened: a rejected transaction must not register anything (registering outside a group would raise).
        _ = e.session.perform("Bad") { tx in Fx.wall(tx, e.ids, .zero, Vec2(0.0001, 0)) }
        #expect(e.session.lastError != nil)
        #expect(!e.session.canUndo)
        #expect(e.model.revision == rev)
        let r = e.session.perform("Nothing") { _ in }
        #expect(r == nil && !e.session.canUndo)
        #expect(throws: TransactionError.self) { try e.session.performThrowing("Bad") { tx in Fx.wall(tx, e.ids, .zero, Vec2(0.0001, 0)) } }
        // A ParameterError thrown inside the build closure becomes lastError.
        e.session.perform("Bad param") { tx in try Parameters.set(ParameterID("q.area"), to: .double(1), on: e.ids.levels[0], in: tx) }
        #expect(e.session.lastError?.message.contains("read-only") == true)
        e.session.clearError()
        #expect(e.session.lastError == nil)
    }

    @Test func pinnedElementsAreNotDeleted() {
        let e = env()
        let (w, _) = wallWithDoor(e)
        e.step { e.session.perform("Pin") { tx in tx.update(w) { $0.pinned = true } } }
        e.step { e.session.delete([w]) }
        #expect(e.model[w] != nil)
        #expect(e.session.lastError?.message.contains("Pinned") == true)
    }

    @Test func replaceModelClearsHistoryAndSelection() {
        let e = env()
        let (w, _) = wallWithDoor(e)
        e.session.selection.select([w])
        let fresh = Fx.template().0
        e.session.replaceModel(fresh)
        #expect(!e.session.canUndo && !e.session.canRedo)
        #expect(e.session.selection.isEmpty)
        #expect(e.model[w] == nil)
        #expect(e.session.lastChange?.kind == .replace)
    }

    @Test func changeNotificationsReportKinds() {
        let e = env()
        var kinds: [DocumentSession.ChangeKind] = []
        var categories: Set<ArcusDomain.Category> = []
        let token = e.session.onChange { c in kinds.append(c.kind); categories.formUnion(c.categories) }
        let (w, _) = wallWithDoor(e)
        e.session.undoManager.undo()
        e.session.undoManager.redo()
        #expect(kinds == [.commit, .undo, .redo])
        #expect(categories.isSuperset(of: [.walls, .doors]))
        #expect(e.session.lastChange?.changed.contains(w) == true)
        e.session.removeChangeHandler(token)
        e.step { e.session.delete([w]) }
        #expect(kinds.count == 3)
    }

    @Test func selectionDropsDeletedElements() {
        let e = env()
        let (w, d) = wallWithDoor(e)
        e.session.selection.select([w, d])
        e.session.selection.preselection = d
        e.step { e.session.delete([w]) }
        #expect(e.session.selection.isEmpty)
        #expect(e.session.selection.preselection == nil)
    }

    /// FamilyEvalCache keys evaluated families by (type id, type revision) instead of the type's values.
    @Test func typeParameterUndoThenDifferentValue() {
        let e = env()
        var t: ElementID!, d: ElementID!
        e.step {
            e.session.perform("Setup") { tx in
                let src = tx.model[e.ids.familyTypes[Fx.doorType]!]!
                t = tx.create(.elementTypes, name: "900 x 2100", data: src.data)
                let w = Fx.wall(tx, e.ids, .zero, Vec2(8, 0))
                d = tx.create(.doors, data: .insert(InsertData(location: Vec2(3, 0))), typeID: t, levelID: e.ids.levels[0], hostID: w)
            }
        }
        func width() -> Double { InsertGeometry.openingSize(e.model[d]!, e.model)!.width }
        #expect(Fx.approx(width(), 1.0))
        e.step { e.session.setParameter(Parameters.familyParamID("Width"), text: "1000", on: [d], type: .length, name: "Width") }
        #expect(Fx.approx(width(), 1.1))
        e.session.undoManager.undo()
        #expect(Fx.approx(width(), 1.0))
        e.step { e.session.setParameter(Parameters.familyParamID("Width"), text: "1200", on: [d], type: .length, name: "Width") }
        #expect(e.model[t]!.typeData!.params[Parameters.familyParamID("Width")] == .double(1.2))
        #expect(Fx.approx(width(), 1.3), "a new type edit after undo is not served from the family cache")
    }
}

// MARK: - Selection

@MainActor
@Suite("Selection model")
struct SelectionTests {
    let a = ElementID(1), b = ElementID(2), c = ElementID(3)

    @Test func selectDeduplicatesAndKeepsOrder() {
        let s = SelectionModel()
        s.select([b, a, b, c, a])
        #expect(s.ids == [b, a, c])
        #expect(s.count == 3 && s.single == nil)
        s.add([c, a])
        #expect(s.ids == [b, a, c])
        s.remove([a])
        #expect(s.ids == [b, c])
        s.toggle(a); s.toggle(b)
        #expect(s.ids == [c, a])
        s.clear()
        #expect(s.isEmpty && s.single == nil)
    }

    @Test func bimClickModifiers() {
        let saved = SelectionModel.modifierStyle
        SelectionModel.modifierStyle = .bim
        defer { SelectionModel.modifierStyle = saved }
        let s = SelectionModel()
        s.click(a, shift: false, command: false)
        s.click(b, shift: false, command: true)
        #expect(s.ids == [a, b], "⌘-click adds")
        s.click(b, shift: false, command: true)
        #expect(s.ids == [a, b], "⌘-click never removes")
        s.click(a, shift: true, command: false)
        #expect(s.ids == [b], "⇧-click removes")
        s.click(c, shift: true, command: false)
        #expect(s.ids == [b], "⇧-click on an unselected element does nothing")
        s.click(nil, shift: true, command: false)
        #expect(s.ids == [b])
        #expect(SelectionModel.operation(shift: true, command: false) == .remove)
        s.apply(SelectionModel.operation(shift: false, command: true), [a, c])
        #expect(s.ids == [b, a, c])
    }

    @Test func clickModifiers() {
        let saved = SelectionModel.modifierStyle
        SelectionModel.modifierStyle = .mac
        defer { SelectionModel.modifierStyle = saved }
        let s = SelectionModel()
        s.click(a, shift: false, command: false)
        #expect(s.ids == [a])
        s.click(b, shift: true, command: false)
        #expect(s.ids == [a, b])
        s.click(a, shift: false, command: true)
        #expect(s.ids == [b])
        s.click(nil, shift: true, command: false)
        #expect(s.ids == [b], "shift-click on empty space keeps the selection")
        s.click(nil, shift: false, command: false)
        #expect(s.isEmpty)
        s.click(c, shift: false, command: false)
        #expect(s.single == c)
    }

    @Test func tabCyclingThroughCandidates() {
        let s = SelectionModel()
        s.setCycleCandidates([a, b, c])
        #expect(s.preselection == a)
        s.cycle(); #expect(s.preselection == b)
        s.cycle(); s.cycle()
        #expect(s.preselection == a)
        s.setCycleCandidates([c])
        #expect(s.cycleIndex == 0 && s.preselection == c)
    }

    /// The host calls setCycleCandidates on every pointer move; with unchanged candidates the Tab position is kept.
    @Test func tabPositionSurvivesPointerMoves() {
        let s = SelectionModel()
        s.setCycleCandidates([a, b, c])
        s.cycle()
        #expect(s.preselection == b)
        s.setCycleCandidates([a, b, c])
        #expect(s.preselection == s.cycleCandidates[s.cycleIndex])
        #expect(s.preselection == b, "the Tab position survives pointer moves over the same candidates")
    }

    @Test func filterAndStatus() throws {
        let box = try Fx.box { tx, ids, walls in Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0)) }
        let s = SelectionModel()
        let wall = box.model[box.walls[0]]!
        let door = box.model.elements(.doors)[0]
        s.filter = [.doors]
        #expect(!s.allows(wall) && s.allows(door))
        s.filter = nil
        var pinned = wall
        pinned.pinned = true
        s.selectPinned = false
        #expect(!s.allows(pinned))
        s.select([wall.id])
        #expect(s.statusDescription(box.model) == "Walls : Basic Wall : Generic - 200mm")
        s.select(box.walls + [door.id])
        #expect(s.statusDescription(box.model) == "5 elements selected")
        let counts = s.categoryCounts(box.model)
        #expect(counts.map(\.0) == [.walls, .doors] && counts.map(\.1) == [4, 1])
    }
}

// MARK: - Commands

@Suite("Command catalog")
struct CommandCatalogTests {
    @Test func everyCommandHasInfo() {
        let missing = CommandID.allCases.filter { CommandCatalog.byID[$0] == nil }
        #expect(missing.isEmpty, "\(missing)")
        #expect(CommandCatalog.all.count == Set(CommandCatalog.all.map(\.id)).count, "no duplicate entries")
        #expect(CommandCatalog.all.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    @Test func aliasesAreUniqueAndShort() {
        let aliases = CommandCatalog.all.flatMap { c in c.aliases.map { ($0.uppercased(), c.id) } }
        let grouped = Dictionary(grouping: aliases, by: \.0).filter { $0.value.count > 1 }
        #expect(grouped.isEmpty, "\(grouped.keys.sorted())")
        #expect(aliases.allSatisfy { (2...3).contains($0.0.count) })
        #expect(CommandCatalog.defaultAliases.count == aliases.count)
        #expect(CommandCatalog.defaultAliases["WA"] == .wall)
    }

    @Test func shortcutsAreUnique() {
        let shortcuts = CommandCatalog.all.compactMap(\.shortcut)
        let dup = Dictionary(grouping: shortcuts, by: { $0 }).filter { $0.value.count > 1 }.keys
        #expect(dup.isEmpty, "\(dup.sorted())")
    }

    @Test(arguments: [("WA", CommandID.wall), ("wall", .wall), ("door", .door), ("partition", .wall), ("sheet list", .sheetList), ("MV", .move)])
    func searchFindsBestMatchFirst(_ q: String, _ expected: CommandID) {
        let r = CommandCatalog.search(q, aliases: CommandCatalog.defaultAliases, recent: [], available: { _ in true })
        #expect(r.first?.id == expected)
    }

    /// Every default alias typed exactly should bring up its own command first.
    @Test func exactAliasRanksFirst() {
        let aliases = CommandCatalog.defaultAliases
        let losers = aliases.keys.sorted().filter { a in
            CommandCatalog.search(a, aliases: aliases, recent: [], available: { _ in true }).first?.id != aliases[a]
        }
        #expect(losers.isEmpty, "\(losers.map { "\($0)→\(CommandCatalog.search($0, aliases: aliases, recent: [], available: { _ in true }).first!.id)" })")
    }

    @Test func searchRespectsAvailabilityAndRecents() {
        let aliases = CommandCatalog.defaultAliases
        let r = CommandCatalog.search("wall", aliases: aliases, recent: [], available: { $0 != .wall })
        #expect(!r.contains { $0.id == .wall })
        let empty = CommandCatalog.search("  ", aliases: aliases, recent: [.save, .wall], available: { _ in true })
        #expect(Array(empty.prefix(2).map(\.id)) == [.save, .wall])
        #expect(!empty.dropFirst(2).contains { $0.id == .wall })
        #expect(CommandCatalog.search("zzzqqq", aliases: aliases, recent: [], available: { _ in true }).isEmpty)
        // A user alias remaps a command.
        var custom = aliases
        custom["QQ"] = .floor
        #expect(CommandCatalog.search("qq", aliases: custom, recent: [], available: { _ in true }).first?.id == .floor)
    }

    @Test func infoFallsBackForUnknownIDs() {
        #expect(CommandCatalog.info(.wall).title == "Wall")
    }
}

// MARK: - Element operations

@MainActor
@Suite("Element operations and grips")
struct ElementOperationTests {
    func wallDoorTag() throws -> (BIMModel, ProjectTemplates.Ids, ElementID, ElementID, ElementID) {
        var (m, ids) = Fx.template()
        var w: ElementID!, d: ElementID!, t: ElementID!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(8, 0))
            d = Fx.door(tx, ids, host: w, at: Vec2(3, 0), mark: "D1")
            t = tx.create(.tags, data: .tag(TagData(taggedID: d, head: Vec2(3, -1))), typeID: ids.familyTypes["Door Tag: Standard"], ownerViewID: ids.planViews[ids.levels[0]])
        }
        return (m, ids, w, d, t)
    }

    @Test func dependentsTravelWithTheirHost() throws {
        let (m, ids, w, d, t) = try wallDoorTag()
        #expect(ElementOperations.dependentsToCarry([w], m, viewID: nil) == [w, d])
        #expect(ElementOperations.dependentsToCarry([d], m, viewID: ids.planViews[ids.levels[0]]) == [d, t])
        #expect(ElementOperations.dependentsToCarry([d], m, viewID: ids.planViews[ids.levels[1]]) == [d])
    }

    @Test func rotateKeepsInsertOnHost() throws {
        var (m, _, w, d, _) = try wallDoorTag()
        try Fx.commit(&m) { tx in try ElementOperations.transform([w], by: .rotation(.pi / 2), in: tx, viewID: nil) }
        #expect(Fx.approx(m[w]!.wall!.location.end, Vec2(0, 8)))
        #expect(Fx.approx(m[d]!.insert!.location, Vec2(0, 3)))
        let o = WallGeometry.openings(m[w]!, m)
        #expect(o.count == 1 && Fx.approx(o[0].s0, 2.5) && Fx.approx(o[0].s1, 3.5))
    }

    @Test func mirrorFlipsWallAndCarriesInsert() throws {
        var (m, _, w, d, _) = try wallDoorTag()
        try Fx.commit(&m) { tx in try ElementOperations.transform([w], by: .mirror(through: Vec2(10, 0), direction: Vec2(0, 1)), in: tx, viewID: nil) }
        #expect(m[w]!.wall!.flipped)
        // The insert's hand is not toggled: mirroring the host already mirrors the insert (see mirroredDoorIsAReflection).
        #expect(!m[d]!.insert!.handFlipped)
        #expect(Fx.approx(m[d]!.insert!.location, Vec2(17, 0)))
        #expect(WallGeometry.openings(m[w]!, m).count == 1)
        // Mirroring twice restores the original orientation.
        try Fx.commit(&m) { tx in try ElementOperations.transform([w], by: .mirror(through: Vec2(10, 0), direction: Vec2(0, 1)), in: tx, viewID: nil) }
        #expect(!m[w]!.wall!.flipped && !m[d]!.insert!.handFlipped)
    }

    /// After a mirror, the element's plan placement must equal the mirror applied to the old placement (a reflection).
    func expectReflected(_ old: Transform2, _ new: Transform2, by mirror: Transform2, _ what: String) -> Bool {
        [Vec2(0.3, 0.2), Vec2(-0.4, 0.7), Vec2(1, -0.5)].allSatisfy { p in new.apply(p).distance(to: mirror.apply(old.apply(p))) < 1e-9 }
    }

    @Test(arguments: [Vec2(0, 1), Vec2(1, 0)])
    func mirroredDoorIsAReflection(_ axis: Vec2) throws {
        var (m, _, w, d, _) = try wallDoorTag()
        let mirror = Transform2.mirror(through: Vec2(10, 5), direction: axis)
        let before = InsertGeometry.placement(m[d]!, m)!.plan
        try Fx.commit(&m) { tx in try ElementOperations.transform([w], by: mirror, in: tx, viewID: nil) }
        let after = InsertGeometry.placement(m[d]!, m)!.plan
        #expect(expectReflected(before, after, by: mirror, "door"))
    }

    @Test(arguments: [Vec2(0, 1), Vec2(1, 0), Vec2(1, 1)])
    func mirroredComponentIsAReflection(_ axis: Vec2) throws {
        var (m, ids) = Fx.template()
        var c: ElementID!
        try Fx.commit(&m) { tx in
            c = tx.create(.furniture, data: .component(ComponentData(location: Vec2(3, 1), rotation: 0.3)), typeID: ids.familyTypes["Desk: 1500 x 750"], levelID: ids.levels[0])
        }
        let mirror = Transform2.mirror(through: Vec2(10, 5), direction: axis)
        let before = ComponentGeometry.placement(m[c]!, m)!.plan
        try Fx.commit(&m) { tx in try ElementOperations.transform([c], by: mirror, in: tx, viewID: nil) }
        let after = ComponentGeometry.placement(m[c]!, m)!.plan
        #expect(m[c]!.component!.mirrored)
        #expect(expectReflected(before, after, by: mirror, "component"))
    }

    @Test func mirroredArcWallKeepsItsShape() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        let arc = Arc2(center: .zero, radius: 5, startAngle: 0, sweep: .pi / 2)
        try Fx.commit(&m) { tx in
            w = tx.create(.walls, data: .wall(WallData(location: .arc(arc), topLevelID: ids.levels[1])), typeID: ids.wallTypes[Fx.generic], levelID: ids.levels[0])
        }
        let mirror = Transform2.mirror(through: .zero, direction: Vec2(0, 1))
        let before = m[w]!.wall!.location
        try Fx.commit(&m) { tx in try ElementOperations.transform([w], by: mirror, in: tx, viewID: nil) }
        let after = m[w]!.wall!.location
        #expect(Fx.approx(after.length, before.length, 1e-9))
        for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(Fx.approx(after.point(at: t), mirror.apply(before.point(at: t)), 1e-9))
        }
        #expect(Fx.approx(WallGeometry.footprint(m[w]!, m)!.area, .pi / 2 * 5 * 0.2, 0.02))
    }

    @Test func copyToAnotherLevelKeepsWallHeight() throws {
        var (m, ids, w, d, _) = try wallDoorTag()
        let tx = TransactionContext(model: m, name: "Paste to Level 2")
        let map = ElementOperations.copy([w], by: .identity, in: tx, viewID: nil, targetLevel: ids.levels[1], levelDelta: 4)
        #expect(tx.model[map[w]!]!.levelID == ids.levels[1])
        #expect(tx.model[map[d]!]!.levelID == ids.levels[1])
        _ = try tx.commit()
        m = tx.model
        #expect(Fx.approx(WallGeometry.frame(m[map[w]!]!, m)!.height, 4))
    }

    @Test func pinnedElementsRefuseTransforms() throws {
        var (m, _, w, d, _) = try wallDoorTag()
        try Fx.commit(&m) { tx in tx.update(d) { $0.pinned = true } }
        let tx = TransactionContext(model: m, name: "Move")
        #expect(throws: TransactionError.self) { try ElementOperations.transform([w], by: .translation(Vec2(1, 0)), in: tx, viewID: nil) }
    }

    @Test func copyRemapsHostsAndTags() throws {
        var (m, ids, w, d, t) = try wallDoorTag()
        var map: [ElementID: ElementID] = [:]
        try Fx.commit(&m) { tx in map = ElementOperations.copy([w], by: .translation(Vec2(0, 5)), in: tx, viewID: ids.planViews[ids.levels[0]]) }
        #expect(map.count == 2, "the wall and its door; the tag follows only the door")
        let nw = map[w]!, nd = map[d]!
        #expect(m[nd]!.hostID == nw)
        #expect(Fx.approx(m[nd]!.insert!.location, Vec2(3, 5)))
        #expect(m[nd]!.mark == "", "marks are not copied")
        #expect(m[nd]!.ifcGUID != m[d]!.ifcGUID)
        #expect(m.hosted(by: w).map(\.id) == [d])
        #expect(m.tags(of: d).map(\.id) == [t])
        var tagMap: [ElementID: ElementID] = [:]
        try Fx.commit(&m) { tx in tagMap = ElementOperations.copy([d], by: .translation(Vec2(3, 0)), in: tx, viewID: ids.planViews[ids.levels[0]]) }
        let copiedTag = try #require(tagMap[t])
        #expect(m[copiedTag]!.tag!.taggedID == tagMap[d])
        #expect(m[tagMap[d]!]!.hostID == w, "copying only the door keeps the original host")
    }

    @Test func arrayCopiesAtEqualSpacing() throws {
        var (m, _, w, _, _) = try wallDoorTag()
        try Fx.commit(&m) { tx in for k in 1...3 { ElementOperations.copy([w], by: .translation(Vec2(0, 4 * Double(k))), in: tx, viewID: nil) } }
        let ys = m.elements(.walls).map { $0.wall!.location.start.y }.sorted()
        #expect(ys == [0, 4, 8, 12])
        #expect(m.elements(.doors).count == 4)
        #expect(m.elements(.doors).allSatisfy { m[$0.hostID]?.wall != nil && WallGeometry.openings(m[$0.hostID]!, m).count == 1 })
    }

    @Test func splitRehostsInserts() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!, d1: ElementID!, d2: ElementID!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(10, 0))
            d1 = Fx.door(tx, ids, host: w, at: Vec2(2, 0))
            d2 = Fx.door(tx, ids, host: w, at: Vec2(8, 0))
        }
        try Fx.commit(&m) { tx in try ElementOperations.split(w, at: Vec2(5, 0.3), in: tx) }
        let walls = m.elements(.walls)
        #expect(walls.count == 2)
        #expect(walls.allSatisfy { Fx.approx($0.wall!.location.length, 5) })
        #expect(m[d1]!.hostID == w)
        #expect(m[d2]!.hostID != w && m[m[d2]!.hostID]?.wall != nil)
        let tx = TransactionContext(model: m, name: "Split end")
        #expect(throws: TransactionError.self) { try ElementOperations.split(w, at: Vec2(0, 0), in: tx) }
        #expect(throws: TransactionError.self) { try ElementOperations.split(ids.levels[0], at: .zero, in: tx) }
    }

    @Test func trimAndExtendToABoundary() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, .zero, Vec2(4, 0))
            b = Fx.wall(tx, ids, Vec2(0, 2), Vec2(9, 2))
        }
        try Fx.commit(&m) { tx in
            try ElementOperations.trimExtend(a, keepNear: Vec2(1, 0), to: .line(Segment2(Vec2(6, -5), Vec2(6, 5))), in: tx)
            try ElementOperations.trimExtend(b, keepNear: Vec2(1, 2), to: .line(Segment2(Vec2(6, -5), Vec2(6, 5))), in: tx)
        }
        #expect(m[a]!.wall!.location == .line(Segment2(.zero, Vec2(6, 0))), "extended")
        #expect(m[b]!.wall!.location == .line(Segment2(Vec2(0, 2), Vec2(6, 2))), "trimmed on the picked side")
        let tx = TransactionContext(model: m, name: "Parallel")
        #expect(throws: TransactionError.self) { try ElementOperations.trimExtend(a, keepNear: .zero, to: .line(Segment2(Vec2(0, 1), Vec2(5, 1))), in: tx) }
    }

    @Test func wallGripsMoveEndpointsAndInsertsFollow() throws {
        var (m, _, w, d, _) = try wallDoorTag()
        let grips = GripService.grips(for: m[w]!, m, viewKind: .floorPlan)
        #expect(grips.map(\.kind) == [.start, .end])
        #expect(grips[1].position == Vec2(8, 0))
        #expect(GripService.grips(for: m[d]!, m, viewKind: .floorPlan).map(\.kind) == [.point])
        #expect(GripService.grips(for: m.levels[0], m, viewKind: .floorPlan).isEmpty)
        try Fx.commit(&m) { tx in GripService.apply(grips[1], to: Vec2(3.2, 0), in: tx) }
        #expect(m[w]!.wall!.location.end == Vec2(3.2, 0))
        #expect(Fx.approx(m[d]!.insert!.location, Vec2(2.7, 0)), "door slides to stay inside the shorter wall")
    }

    @Test func centerOfSelection() throws {
        let (m, _, w, _, _) = try wallDoorTag()
        let c = ElementOperations.center(of: [w], m)
        #expect(Fx.approx(c, Vec2(4, 0), 1e-9))
        #expect(ElementOperations.center(of: [], m) == .zero)
    }
}

// MARK: - Snapping

@Suite("Snapping")
struct SnapTests {
    func index(_ items: [(ElementID, [Vec2], ArcusDomain.Category)]) -> SnapIndex {
        let g = ViewGraphics(viewID: ElementID(99), scale: 100,
                             items: items.map { GItem(elementID: $0.0, category: $0.2, layer: .model, primitives: [.polyline($0.1, closed: false, .thin)]) },
                             extents: .empty, crop: nil, modelRevision: 0)
        let view = Element(id: ElementID(99), category: .views, data: .view(ViewData(kind: .drafting)))
        return SnapIndex(graphics: g, model: BIMModel(), view: view)
    }
    var cross: SnapIndex { index([(ElementID(1), [Vec2(0, 0), Vec2(10, 0)], .detailLines), (ElementID(2), [Vec2(7, -2), Vec2(7, 6)], .detailLines)]) }

    @Test(arguments: [
        (Vec2(0.05, 0.03), SnapKind.endpoint, Vec2(0, 0)), (Vec2(5.05, -0.04), .midpoint, Vec2(5, 0)), (Vec2(7.06, 0.05), .intersection, Vec2(7, 0)),
        (Vec2(3.0, 0.08), .nearest, Vec2(3, 0)), (Vec2(7.04, 2.03), .midpoint, Vec2(7, 2)),
    ])
    func snapsToTheRightKind(_ p: Vec2, _ kind: SnapKind, _ at: Vec2) throws {
        let r = try #require(cross.snap(p, radius: 0.2, from: nil, settings: SnapSettings()))
        #expect(r.kind == kind)
        #expect(Fx.approx(r.point, at, 1e-9))
    }

    @Test func intersectionNamesBothElements() throws {
        let r = try #require(cross.snap(Vec2(7.05, 0.05), radius: 0.2, from: nil, settings: SnapSettings()))
        #expect(Set(r.elementIDs) == [ElementID(1), ElementID(2)])
    }

    @Test func priorityBeatsDistance() throws {
        let short = index([(ElementID(1), [Vec2(0, 0), Vec2(0.2, 0)], .detailLines)])
        let r = try #require(short.snap(Vec2(0.09, 0), radius: 0.5, from: nil, settings: SnapSettings()))
        #expect(r.kind == .endpoint, "an endpoint within the radius wins over a closer midpoint")
    }

    @Test func settingsControlSnapping() {
        var s = SnapSettings()
        s.enabled = [.nearest]
        #expect(cross.snap(Vec2(0.05, 0.03), radius: 0.2, from: nil, settings: s)?.kind == .nearest)
        s.snapsOn = false
        #expect(cross.snap(Vec2(0.05, 0.03), radius: 0.2, from: nil, settings: s) == nil)
        #expect(cross.snap(Vec2(3, 3), radius: 0.2, from: nil, settings: SnapSettings()) == nil)
    }

    @Test func perpendicularFromPreviousPoint() throws {
        var s = SnapSettings()
        s.enabled = [.perpendicular]
        let r = try #require(cross.snap(Vec2(3.1, 0.1), radius: 0.2, from: Vec2(3, 4), settings: s))
        #expect(r.kind == .perpendicular && Fx.approx(r.point, Vec2(3, 0), 1e-9))
    }

    @Test func gridIntersections() throws {
        let grids = index([(ElementID(1), [Vec2(0, 0), Vec2(10, 0)], .grids), (ElementID(2), [Vec2(4, -5), Vec2(4, 5)], .grids)])
        let r = try #require(grids.snap(Vec2(4.05, 0.05), radius: 0.2, from: nil, settings: SnapSettings()))
        #expect(r.kind == .gridIntersection)
    }

    @Test func arcsSnapToCenterAndQuadrants() throws {
        let g = ViewGraphics(viewID: ElementID(99), scale: 100,
                             items: [GItem(elementID: ElementID(5), category: .detailLines, layer: .model,
                                           primitives: [.arc(Arc2(center: .zero, radius: 2, startAngle: 0, sweep: 2 * .pi), .thin)])],
                             extents: .empty, crop: nil, modelRevision: 0)
        let idx = SnapIndex(graphics: g, model: BIMModel(), view: Element(id: ElementID(99), category: .views, data: .view(ViewData(kind: .drafting))))
        #expect(idx.snap(Vec2(0.05, 0.05), radius: 0.2, from: nil, settings: SnapSettings())?.kind == .center)
        let q = try #require(idx.snap(Vec2(0.05, 2.02), radius: 0.2, from: nil, settings: SnapSettings()))
        #expect(q.kind == .quadrant && Fx.approx(q.point, Vec2(0, 2), 1e-9))
    }

    @Test func angleSnapWithinTolerance() throws {
        let p = try #require(SnapIndex.angleSnap(Vec2(10, 0.3), from: .zero, increment: 15))
        #expect(Fx.approx(p.y, 0, 1e-9) && Fx.approx(p.x, Vec2(10, 0.3).length, 1e-9))
        #expect(SnapIndex.angleSnap(Vec2(10, 10 * tan(0.13)), from: .zero, increment: 15) == nil)
        let q = try #require(SnapIndex.angleSnap(Vec2(5, 5.1), from: .zero, increment: 15))
        #expect(Fx.approx(q.x, q.y, 1e-9))
        #expect(SnapIndex.angleSnap(.zero, from: .zero, increment: 15) == nil)
    }

    @Test func nearestSegmentForPickLines() throws {
        let hit = try #require(cross.nearestSegment(Vec2(7.1, 4), radius: 0.3))
        #expect(hit.1 == ElementID(2))
        #expect(cross.nearestSegment(Vec2(3, 3), radius: 0.3) == nil)
    }

    @Test func planSnapIndexIncludesWallLocationLines() throws {
        let box = try Fx.box()
        let g = ViewGraphicsBuilder(model: box.model, view: box.plan).build()
        let idx = SnapIndex(graphics: g, model: box.model, view: box.plan)
        // Hidden location lines snap when no visible geometry is within reach.
        let r = try #require(idx.snap(Vec2(5.02, 0.005), radius: 0.03, from: nil, settings: SnapSettings()))
        #expect(r.kind == .midpoint && Fx.approx(r.point, Vec2(5, 0), 1e-9))
        #expect(r.elementIDs.contains(box.walls[0]))
    }

    @Test func visibleWallFacesBeatHiddenLocationLines() throws {
        let box = try Fx.box()
        let g = ViewGraphicsBuilder(model: box.model, view: box.plan).build()
        let idx = SnapIndex(graphics: g, model: box.model, view: box.plan)
        let half = WallGeometry.assembly(for: box.model[box.walls[0]]!, box.model).totalThickness / 2
        // Pointer on the face, drawing from a point whose perpendicular foot on the hidden centre line is also in reach.
        let onFace = Vec2(3, -half + 0.002)
        let r = try #require(idx.snap(onFace, radius: half * 1.5, from: Vec2(3.01, -5), settings: SnapSettings()))
        #expect(abs(abs(r.point.y) - half) < 1e-6, "snapped to \(r.point) (\(r.kind)); the face is at y = ±\(half)")
    }

    @MainActor @Test func parallelAndPerpendicularToNearbyAndHoveredLines() {
        let session = DocumentSession(model: BIMModel())
        let ctx = ToolContext(session: session, viewID: ElementID(99))
        ctx.pixel = 0.01
        // A line at 30° far from where we draw.
        let dir = Vec2.fromAngle(Angle.radians(30), length: 1)
        ctx.snapIndex = SnapTests().index([(ElementID(1), [Vec2(20, 20), Vec2(20, 20) + dir * 10], .detailLines)])
        var s = SnapSettings(); s.angleIncrement = 90
        ctx.snapSettings = s
        // Not near it and not hovered yet: no parallel.
        let raw = Vec2(0, 0) + dir * 5 + Vec2(-dir.y, dir.x) * 0.03
        #expect(ctx.snap(raw, from: .zero).1?.kind != .parallel)
        // Hover over the line (acquire it), then come back: the rubber band snaps parallel.
        _ = ctx.snap(Vec2(20, 20) + dir * 5)
        let (p, r) = ctx.snap(raw, from: .zero)
        #expect(r?.kind == .parallel)
        #expect(abs((p - .zero).normalized.dot(dir) - 1) < 1e-9)
        // Perpendicular to it as well.
        let perp = Vec2(-dir.y, dir.x)
        let (q, r2) = ctx.snap(perp * 4 + dir * 0.02, from: .zero)
        #expect(r2?.kind == .perpendicular && abs((q - .zero).normalized.dot(perp) - 1) < 1e-9)
    }

    /// I2: RevitCraft's adaptive increments: 45° for a short rubber band, then 15°, 5° and 1° as it grows on screen.
    @MainActor @Test func adaptiveAngleIncrementFollowsTheRubberBandLength() {
        #expect(SnapSettings().angleIncrement == 0)
        #expect(SnapSettings.adaptiveIncrement(pixels: 40) == 45)
        #expect(SnapSettings.adaptiveIncrement(pixels: 100) == 15)
        #expect(SnapSettings.adaptiveIncrement(pixels: 500) == 5)
        #expect(SnapSettings.adaptiveIncrement(pixels: 2000) == 1)
        let ctx = ToolContext(session: DocumentSession(model: BIMModel()), viewID: ElementID(99))
        ctx.pixel = 0.01
        // 20 m is 2,000 pt on screen: 1° steps, so a 2° direction snaps to its own guide.
        let (p, r) = ctx.snap(Vec2(20, 20 * tan(Angle.radians(2))), from: .zero)
        #expect(r?.kind == .angle && abs(Angle.degrees(p.angle) - 2) < 1e-6)
        // 0.4 m is 40 pt: 45° steps, so 30° is too far from any guide to snap.
        #expect(ctx.snap(Vec2.fromAngle(Angle.radians(30), length: 0.4), from: .zero).1?.kind != .angle)
    }

    @MainActor @Test func angleSnapToleranceIsAScreenDistance() {
        let session = DocumentSession(model: BIMModel())
        let ctx = ToolContext(session: session, viewID: ElementID(99))
        ctx.pixel = 0.01            // 6 pt tolerance = 0.06 m
        ctx.snapSettings.angleIncrement = 15 // a fixed increment (the default is adaptive)
        // 2° off horizontal at 20 m is 0.7 m off the line: far away on screen, so no angle snap.
        let far = Vec2(20, 20 * tan(Angle.radians(2)))
        #expect(ctx.snap(far, from: .zero).1 == nil)
        // 0.03 m off the line snaps.
        let (p, r) = ctx.snap(Vec2(20, 0.03), from: .zero)
        #expect(r?.kind == .angle && abs(p.y) < 1e-9)
    }
}

// MARK: - Tools

@MainActor
@Suite("Interactive tools")
struct ToolTests {
    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()   // one open group per test: tools commit without a run loop
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2) {
        tool.pointerMoved(ToolInput(point: p, rawPoint: p))
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
    }

    @Test func oneShotSnapOverrideAndShiftConstraint() {
        let (ctx, _) = context()
        ctx.pixel = 0.01
        ctx.snapIndex = SnapTests().cross
        // Near the corner of the crossing lines both an endpoint and a nearest snap are in range; SM forces midpoint.
        #expect(ctx.snap(Vec2(0.05, 0.03)).1?.kind == .endpoint)
        ctx.snapOverride = .only(.midpoint)
        #expect(ctx.snap(Vec2(0.05, 0.03)).1 == nil, "no midpoint in range")
        #expect(ctx.snap(Vec2(5.05, 0.05)).1?.kind == .midpoint)
        ctx.snapOverride = .off
        let (p, s) = ctx.snap(Vec2(5.05, 0.05), from: Vec2(20, 20))
        #expect(s == nil && p == Vec2(5.05, 0.05), "SO: no object or angle snap")
        ctx.snapOverride = nil
        // Shift: constrained to the horizontal or vertical through the start point.
        let (h, _) = ctx.snap(Vec2(30, 21.5), from: Vec2(20, 20), constrainOrtho: true)
        #expect(h == Vec2(30, 20))
        let (v, _) = ctx.snap(Vec2(21.5, 40), from: Vec2(20, 20), constrainOrtho: true)
        #expect(v == Vec2(20, 40))
        // An object snap under the pointer is projected onto the constraint line.
        let (q, qs) = ctx.snap(Vec2(7.04, 2.03), from: Vec2(0, 2), constrainOrtho: true)
        #expect(qs?.kind == .midpoint && q == Vec2(7, 2))
    }

    @Test func wallToolChainsSegments() {
        let (ctx, ids) = context()
        let tool = WallTool(ctx: ctx)
        #expect(tool.topLevelID == ids.levels[1], "defaults to the level above")
        #expect(tool.numericLabel == nil)
        click(tool, Vec2(0, 0))
        #expect(tool.numericLabel == "Length")
        click(tool, Vec2(6, 0))
        click(tool, Vec2(6, 4))
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 2)
        #expect(walls[0].wall!.location == .line(Segment2(Vec2(0, 0), Vec2(6, 0))))
        #expect(walls[1].wall!.location == .line(Segment2(Vec2(6, 0), Vec2(6, 4))))
        #expect(walls.allSatisfy { $0.typeID == ids.wallTypes[Fx.generic] && $0.levelID == ids.levels[0] && $0.wall?.topLevelID == ids.levels[1] })
        #expect(WallGeometry.endJoin(walls[0], atEnd: true, ctx.model).kind == .corner)
        #expect(tool.escape() == .stayInTool)
        #expect(tool.escape() == .exitTool)
        ctx.session.undoManager.endUndoGrouping()
        #expect(ctx.session.canUndo)
    }

    @Test func wallToolTypedLength() {
        let (ctx, _) = context()
        let tool = WallTool(ctx: ctx)
        click(tool, Vec2(1, 1))
        tool.pointerMoved(ToolInput(point: Vec2(1, 9), rawPoint: Vec2(1, 9)))
        #expect(tool.numericInput("3500"))
        #expect(!tool.numericInput("abc"))
        let w = ctx.model.elements(.walls)
        #expect(w.count == 1)
        #expect(w[0].wall!.location.end == Vec2(1, 4.5))
    }

    @Test func wallToolRectangleAndOptions() {
        let (ctx, ids) = context()
        let tool = WallTool(ctx: ctx, mode: .rectangle)
        #expect(tool.commandID == .wallRectangle)
        tool.setOption("top", .text("Unconnected"))
        tool.setOption("height", .double(2.7))
        tool.setOption("location", .text(WallLocationLine.finishFaceInterior.rawValue))
        #expect(tool.options.contains { $0.id == "height" })
        click(tool, Vec2(0, 0))
        click(tool, Vec2(5, 3))
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 4)
        #expect(walls.allSatisfy { $0.wall?.topLevelID == nil && $0.wall?.unconnectedHeight == 2.7 && $0.wall?.locationLine == .finishFaceInterior })
        // Drawn clockwise so the exterior (left of each wall) faces out.
        let loop = Polygon2(walls.map { $0.wall!.location.start })
        #expect(!loop.isCounterClockwise)
        _ = ids
    }

    @Test func wallToolOutsidePlanViewsDoesNothing() {
        let (ctx, _) = context()
        ctx.viewID = ctx.model.views.first { $0.name == "South" }!.id
        let tool = WallTool(ctx: ctx)
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        click(tool, .zero); click(tool, Vec2(4, 0))
        #expect(ctx.model.elements(.walls).isEmpty)
        #expect(!messages.isEmpty)
        #expect(tool.prompt.contains("plan"))
    }

    @Test func arrayToolCopiesSelection() {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(4, 0)) }
        let tool = ArrayTool(ctx: ctx, ids: [w])
        tool.setOption("count", .int(4))
        tool.setOption("last", .bool(true))
        var finished = false
        ctx.toolFinished = { finished = true }
        click(tool, .zero)
        click(tool, Vec2(0, 9))
        let ys = ctx.model.elements(.walls).map { $0.wall!.location.start.y }.sorted()
        #expect(ys == [0, 3, 6, 9])
        #expect(finished)
    }
}
