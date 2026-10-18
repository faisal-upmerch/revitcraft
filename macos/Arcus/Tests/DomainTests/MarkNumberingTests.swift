import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-CANVAS (ARCUS-045): automatic Mark numbering and the duplicate-Mark warning.
@MainActor
@Suite("Mark numbering")
struct MarkNumberingTests {
    func session() -> (DocumentSession, ProjectTemplates.Ids, ElementID) {
        let (m, ids) = Fx.template()
        let s = DocumentSession(model: m)
        s.undoManager.groupsByEvent = false
        s.undoManager.beginUndoGrouping()
        var w: ElementID!
        s.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(20, 0)) }
        return (s, ids, w)
    }
    func marks(_ s: DocumentSession, _ c: ArcusDomain.Category) -> [String] { s.model.elements(c).sorted { $0.id < $1.id }.map(\.mark) }

    @Test func placedDoorsAreNumberedOneTwoThreeAndWindowsCountSeparately() throws {
        let (s, ids, w) = session()
        #expect(s.model.elements(.doors).isEmpty)
        for x in [2.0, 6, 10] { s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(x, 0)) } }
        #expect(marks(s, .doors) == ["1", "2", "3"])
        s.perform("Place Window") { tx in Fx.window(tx, ids, host: w, at: Vec2(15, 0)) }
        #expect(marks(s, .windows) == ["1"])
        #expect(s.model[w]?.mark == "", "walls are not numbered")
    }

    @Test func toolPlacementTagsShowTheNumber() throws {
        let (s, ids, w) = session()
        let ctx = ToolContext(session: s, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        let tool = InsertTool(ctx: ctx, category: .doors)
        let p = Vec2(5, 0)
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = w
        tool.pointerMoved(i)
        tool.pointerDown(i)
        let door = try #require(s.model.elements(.doors).first)
        #expect(door.mark == "1")
        let tag = try #require(s.model.tags(of: door.id).first)
        #expect(tag.tag?.taggedID == door.id)
    }

    @Test func copiesGetTheNextNumberAndUndoReleasesIt() throws {
        let (s, ids, w) = session()
        for x in [2.0, 6, 10] { s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(x, 0)) } }
        let first = s.model.elements(.doors).min { $0.id < $1.id }!.id
        s.undoManager.endUndoGrouping()
        s.undoManager.beginUndoGrouping()
        s.perform("Copy") { tx in ElementOperations.copy([first], by: .translation(Vec2(12, 0)), in: tx, viewID: nil) }
        #expect(marks(s, .doors) == ["1", "2", "3", "4"])
        s.undoManager.endUndoGrouping()
        s.undoManager.undo()
        s.undoManager.beginUndoGrouping()
        #expect(marks(s, .doors) == ["1", "2", "3"])
        s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(16, 0)) }
        #expect(marks(s, .doors).last == "4", "the highest mark plus one")
    }

    @Test func explicitAndNonNumericMarksAreKept() throws {
        let (s, ids, w) = session()
        s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(2, 0), mark: "D-01") }
        s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(6, 0), mark: "7") }
        s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(10, 0)) }
        #expect(marks(s, .doors) == ["D-01", "7", "8"])
    }

    @Test func duplicateMarkWarnsButKeepsTheValue() throws {
        let (s, ids, w) = session()
        for x in [2.0, 6] { s.perform("Place Door") { tx in Fx.door(tx, ids, host: w, at: Vec2(x, 0)) } }
        let doors = s.model.elements(.doors).sorted { $0.id < $1.id }
        s.perform("Mark") { tx in tx.update(doors[1].id) { $0.mark = "1" } }
        #expect(s.lastError == nil)
        #expect(s.model[doors[1].id]?.mark == "1")
        let warning = try #require(s.lastWarnings.first { $0.code == "mark.duplicate" })
        #expect(warning.severity == .warning && Set(warning.elements) == Set(doors.map(\.id)))
        // A unique value doesn't warn.
        s.perform("Mark") { tx in tx.update(doors[1].id) { $0.mark = "5" } }
        #expect(!s.lastWarnings.contains { $0.code == "mark.duplicate" })
    }

    @Test func furnitureIsNumberedPerCategory() {
        #expect(MarkNumbering.numberedCategories.isSuperset(of: [.doors, .windows, .furniture, .casework, .plumbingFixtures, .mechanicalEquipment, .lightingFixtures, .specialtyEquipment]))
        #expect(!MarkNumbering.numberedCategories.contains(.walls) && !MarkNumbering.numberedCategories.contains(.rooms))
        var m = BIMModel()
        _ = try? Fx.commit(&m) { tx in tx.create(.furniture, data: .component(ComponentData(location: .zero))) { $0.mark = "3" } }
        #expect(MarkNumbering.nextMark(for: .furniture, in: m) == "4")
        #expect(MarkNumbering.nextMark(for: .casework, in: m) == "1")
    }
}
