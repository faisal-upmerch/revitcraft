import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Transactions and regeneration")
struct TransactionTests {
    @Test func createUpdateDeleteTracksRevisions() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(5, 0)) }
        #expect(m[w]?.category == .walls)
        let r1 = try #require(m[w]?.revision)
        try Fx.commit(&m) { tx in tx.update(w) { $0.wall?.baseOffset = 0.5 } }
        let r2 = try #require(m[w]?.revision)
        #expect(r2 > r1, "an edit issues a fresh, larger revision stamp")
        #expect(m[w]?.wall?.baseOffset == 0.5)
        try Fx.commit(&m) { tx in tx.delete(w) }
        #expect(m[w] == nil)
    }

    @Test func eachCommitBumpsModelRevisionOnce() throws {
        var (m, ids) = Fx.template()
        let r0 = m.revision
        try Fx.commit(&m) { tx in Fx.wall(tx, ids, .zero, Vec2(5, 0)); Fx.wall(tx, ids, Vec2(0, 3), Vec2(5, 3)) }
        #expect(m.revision == r0 + 1)
        try Fx.commit(&m) { tx in Fx.wall(tx, ids, Vec2(0, 6), Vec2(5, 6)) }
        #expect(m.revision == r0 + 2)
    }

    @Test func idsAreNeverReusedAfterDelete() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in a = Fx.wall(tx, ids, .zero, Vec2(5, 0)) }
        try Fx.commit(&m) { tx in tx.delete(a) }
        try Fx.commit(&m) { tx in b = Fx.wall(tx, ids, .zero, Vec2(5, 0)) }
        #expect(b > a)
    }

    @Test func updateOfMissingElementReturnsFalse() {
        let (m, _) = Fx.template()
        let tx = TransactionContext(model: m, name: "Missing")
        #expect(tx.update(ElementID(999_999_999)) { $0.name = "x" } == false)
        #expect(!tx.hasChanges)
    }

    @Test func noOpUpdateHasNoChanges() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(5, 0)) }
        let tx = TransactionContext(model: m, name: "Noop")
        tx.update(w) { $0.wall?.baseOffset = 0 }
        #expect(!tx.hasChanges)
        let r = try tx.commit()
        #expect(r.record.changes.isEmpty)
    }

    @Test func deletingWallCascadesToInsertsAndTags() throws {
        var box = try Fx.box { tx, ids, walls in
            let d = Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0))
            let w = Fx.window(tx, ids, host: walls[0], at: Vec2(7, 0))
            let plan = ids.planViews[ids.levels[0]]!
            tx.create(.tags, data: .tag(TagData(taggedID: d, head: Vec2(3, -1))), typeID: ids.familyTypes["Door Tag: Standard"], ownerViewID: plan)
            tx.create(.tags, data: .tag(TagData(taggedID: w, head: Vec2(7, -1))), typeID: ids.familyTypes["Window Tag: Standard"], ownerViewID: plan)
        }
        #expect(box.model.elements(.doors).count == 1)
        #expect(box.model.elements(.tags).count == 2)
        let (rec, _) = try Fx.commit(&box.model) { tx in tx.delete(box.walls[0]) }
        #expect(box.model.elements(.doors).isEmpty)
        #expect(box.model.elements(.windows).isEmpty)
        #expect(box.model.elements(.tags).isEmpty)
        #expect(box.model.elements(.walls).count == 3)
        #expect(rec.changes.filter(\.isDelete).count == 5)
    }

    @Test func deletingTypeDeletesItsInstances() throws {
        var box = try Fx.box()
        try Fx.commit(&box.model) { tx in tx.delete(box.ids.wallTypes[Fx.generic]!) }
        #expect(box.model.elements(.walls).isEmpty)
        #expect(box.model[box.ids.wallTypes[Fx.generic]!] == nil)
    }

    @Test func deletingViewDeletesOwnedAnnotationsAndViewports() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        var note: ElementID!, vp: ElementID!
        let sheet = m.sheets[0].id
        try Fx.commit(&m) { tx in
            note = tx.create(.textNotes, data: .textNote(TextNoteData(position: .zero, text: "Hi")), ownerViewID: plan)
            vp = tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.4, 0.3), detailNumber: "1")), ownerViewID: sheet)
        }
        try Fx.commit(&m) { tx in tx.delete(plan) }
        #expect(m[note] == nil)
        #expect(m[vp] == nil)
        #expect(m.sheets.count == 1)
    }

    @Test func deletingRevisionDeletesItsClouds() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        let rev = m.revisions[0].id
        var cloud: ElementID!
        try Fx.commit(&m) { tx in
            cloud = tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: .rectangle(Rect2(min: .zero, max: Vec2(2, 2))), revisionID: rev)), ownerViewID: plan)
        }
        try Fx.commit(&m) { tx in tx.delete(rev) }
        #expect(m[cloud] == nil)
    }

    @Test func deletingGroupMembersShrinksThenRemovesGroup() throws {
        var box = try Fx.box()
        var g: ElementID!
        try Fx.commit(&box.model) { tx in
            g = tx.create(.modelGroups, name: "G", data: .group(GroupData(members: [box.walls[0], box.walls[1]], origin: .zero, groupTypeName: "G")))
        }
        try Fx.commit(&box.model) { tx in tx.delete(box.walls[0]) }
        #expect(box.model[g]?.group?.members == [box.walls[1]])
        try Fx.commit(&box.model) { tx in tx.delete(box.walls[1]) }
        #expect(box.model[g] == nil)
    }

    @Test func deletingAttachedFloorDetachesWallTop() throws {
        var box = try Fx.box { tx, ids, walls in
            let f = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(-1, -1), max: Vec2(11, 9))))),
                              typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[1])
            tx.update(walls[0]) { $0.wall?.attachedTopIDs = [f] }
        }
        let floor = box.model.elements(.floors)[0].id
        try Fx.commit(&box.model) { tx in tx.delete(floor) }
        #expect(box.model[box.walls[0]]?.wall?.attachedTopIDs.isEmpty == true)
    }

    // MARK: Validation failures

    enum InvalidEdit: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case shortWall, topBelowBase, unhostedDoor, doorOnFloor, wrongTypeCategory, missingType, duplicateLevelName, duplicateSheetNumber
        case duplicateViewName, emptySchedule, roomWithoutLevel, openSlabBoundary, roofSlopeMismatch, stairWithoutHeight, missingOwnerView
        var testDescription: String { rawValue }

        func apply(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, _ m: BIMModel) {
            switch self {
            case .shortWall:
                Fx.wall(tx, ids, .zero, Vec2(0.0005, 0))
            case .topBelowBase:
                Fx.wall(tx, ids, .zero, Vec2(5, 0)) { $0.baseOffset = 5 }
            case .unhostedDoor:
                tx.create(.doors, data: .insert(InsertData(location: .zero)), typeID: ids.familyTypes[Fx.doorType], levelID: ids.levels[0])
            case .doorOnFloor:
                let f = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 4))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
                tx.create(.doors, data: .insert(InsertData(location: .zero)), typeID: ids.familyTypes[Fx.doorType], levelID: ids.levels[0], hostID: f)
            case .wrongTypeCategory:
                tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(5, 0))), topLevelID: ids.levels[1])),
                          typeID: ids.familyTypes[Fx.doorType], levelID: ids.levels[0])
            case .missingType:
                tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(5, 0))), topLevelID: ids.levels[1])),
                          typeID: ElementID(987_654_321), levelID: ids.levels[0])
            case .duplicateLevelName:
                tx.create(.levels, name: "Level 2", data: .level(LevelData(elevation: 12)))
            case .duplicateSheetNumber:
                tx.create(.sheets, name: "Copy", data: .sheet(SheetData(number: "A101")))
            case .duplicateViewName:
                tx.create(.views, name: "Level 1", data: .view(ViewData(kind: .floorPlan)), levelID: ids.levels[0])
            case .emptySchedule:
                tx.create(.schedules, name: "Empty", data: .schedule(ScheduleDefinition(kind: .category, categories: [.walls])))
            case .roomWithoutLevel:
                tx.create(.rooms, name: "Nowhere", data: .room(RoomData(point: .zero, number: "1")))
            case .openSlabBoundary:
                let open = Sketch(loops: [[.line(Segment2(.zero, Vec2(4, 0))), .line(Segment2(Vec2(4, 0), Vec2(4, 4))), .line(Segment2(Vec2(4, 4), Vec2(0, 4)))]])
                tx.create(.floors, data: .slab(SlabData(boundary: open)), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            case .roofSlopeMismatch:
                tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(4, 4))), edgeSlopes: [0.5, 0.5])),
                          typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
            case .stairWithoutHeight:
                var s = StairData(origin: .zero, direction: 0, width: 1.2, topLevelID: nil)
                s.unconnectedHeight = 0.05
                tx.create(.stairs, data: .stair(s), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
            case .missingOwnerView:
                tx.create(.textNotes, data: .textNote(TextNoteData(position: .zero, text: "orphan")), ownerViewID: ElementID(987_654_320))
            }
        }
    }

    @Test(arguments: InvalidEdit.allCases)
    func rejectedCommitLeavesModelUntouched(_ edit: InvalidEdit) {
        let (m0, ids) = Fx.template()
        let tx = TransactionContext(model: m0, name: edit.rawValue)
        edit.apply(tx, ids, m0)
        #expect(throws: TransactionError.self) { try tx.commit() }
        // The input snapshot is a value: nothing leaked into it.
        #expect(m0.elements == Fx.archMetric.0.elements)
        #expect(m0.revision == Fx.archMetric.0.revision)
    }

    @Test func transactionErrorNamesTheOffendingElement() {
        let (m0, ids) = Fx.template()
        let tx = TransactionContext(model: m0, name: "Short")
        let w = Fx.wall(tx, ids, .zero, Vec2(0.0001, 0))
        do {
            _ = try tx.commit()
            Issue.record("expected failure")
        } catch {
            #expect(error.elements == [w])
            #expect(error.message.contains("too short"))
        }
    }

    // MARK: Records

    @Test func recordInverseRoundTripsExactly() throws {
        var box = try Fx.box { tx, ids, walls in Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0)) }
        let before = box.model
        let param = ParameterDefinition(name: "Acoustic Rating", type: .text, categories: [.walls])
        let (rec, _) = try Fx.commit(&box.model, "Mixed") { tx in
            tx.update(box.walls[1]) { $0.wall?.location = .line(Segment2(Vec2(10, 0), Vec2(10, 9))) }
            tx.delete(box.walls[0])
            Fx.wall(tx, box.ids, Vec2(0, 4), Vec2(10, 4))
            tx.update(box.ids.levels[1]) { $0.name = "Upper" }
            tx.setProjectParameters([param])
        }
        let after = box.model
        #expect(before.applying(rec).elements == after.elements)
        #expect(before.applying(rec).projectParameters == after.projectParameters)
        let undone = after.applying(rec.inverse)
        #expect(undone.elements == before.elements)
        #expect(undone.projectParameters == before.projectParameters)
        #expect(undone.nextID >= after.nextID, "ids are not reused after undo")
        #expect(after.applying(rec.inverse).applying(rec.inverse.inverse).elements == after.elements)
    }

    @Test func recordChangesAreSortedAndClassified() throws {
        var box = try Fx.box()
        let (rec, _) = try Fx.commit(&box.model) { tx in
            Fx.wall(tx, box.ids, Vec2(0, 4), Vec2(10, 4))
            tx.delete(box.walls[2])
            tx.update(box.walls[0]) { $0.mark = "S" }
        }
        #expect(rec.changes.map(\.id) == rec.changes.map(\.id).sorted())
        #expect(rec.changes.filter(\.isInsert).count == 1)
        #expect(rec.changes.filter(\.isDelete).count == 1)
        #expect(rec.inverse.changes.filter(\.isInsert).count == 1)
        #expect(rec.changedIDs.contains(box.walls[0]))
        #expect(!rec.isEmpty)
    }

    // MARK: Dangling references

    @Test func deletingTopLevelKeepsWallHeights() throws {
        var box = try Fx.box()
        let l2 = box.l2
        #expect(WallGeometry.frame(box.model[box.walls[0]]!, box.model)!.height == 4.0)
        try Fx.commit(&box.model) { tx in tx.delete(l2) }
        #expect(box.model[l2] == nil)
        #expect(box.model[box.ids.planViews[l2]!] == nil, "the level's plan view goes with it")
        for w in box.walls {
            let e = box.model[w]!
            #expect(e.wall?.topLevelID == nil)
            #expect(Fx.approx(e.wall!.unconnectedHeight, 4.0))
            #expect(Fx.approx(WallGeometry.frame(e, box.model)!.height, 4.0))
        }
    }

    @Test func deletingTopLevelHonoursTopOffset() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(5, 0)) { $0.topOffset = -0.5; $0.baseOffset = 0.25 } }
        try Fx.commit(&m) { tx in tx.delete(ids.levels[1]) }
        #expect(Fx.approx(m[w]!.wall!.unconnectedHeight, 4.0 - 0.5 - 0.25))
    }

    @Test func deletingLevelDeletesElementsHostedOnIt() throws {
        var (m, ids) = Fx.template()
        var upper: ElementID!
        try Fx.commit(&m) { tx in upper = Fx.wall(tx, ids, .zero, Vec2(5, 0), level: 1, top: 2) }
        try Fx.commit(&m) { tx in tx.delete(ids.levels[1]) }
        #expect(m[upper] == nil)
    }

    @Test func deletingRoomUpperLimitClearsIt() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        try Fx.commit(&m) { tx in
            r = tx.create(.rooms, name: "R", data: .room(RoomData(point: .zero, number: "1")), levelID: ids.levels[0]) { $0.room?.upperLimitLevelID = ids.levels[1] }
        }
        try Fx.commit(&m) { tx in tx.delete(ids.levels[1]) }
        #expect(m[r]?.room?.upperLimitLevelID == nil)
    }

    // MARK: Warnings

    @Test func insertBeyondWallEndWarns() throws {
        var box = try Fx.box()
        let (_, warnings) = try Fx.commit(&box.model) { tx in Fx.door(tx, box.ids, host: box.walls[0], at: Vec2(9.9, 0)) }
        #expect(warnings.contains { $0.code == "insert.outside" })
    }

    @Test func insertHeadAboveWallTopWarns() throws {
        var box = try Fx.box()
        let (_, warnings) = try Fx.commit(&box.model) { tx in Fx.window(tx, box.ids, host: box.walls[0], at: Vec2(5, 0), sill: 3.5) }
        #expect(warnings.contains { $0.code == "insert.aboveTop" })
    }

    @Test func stairRuleViolationsBecomeWarnings() throws {
        var (m, ids) = Fx.template()
        var s = StairData(origin: .zero, direction: 0, width: 1.2, topLevelID: ids.levels[1])
        s.desiredRiserCount = 8   // 500 mm risers
        let (_, warnings) = try Fx.commit(&m) { tx in tx.create(.stairs, data: .stair(s), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0]) }
        #expect(warnings.contains { $0.code == "stair.rule" })
    }
}
