import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-PROPS: staged Type Properties (OK / Cancel / Apply, Duplicate with a name and assignment) and the palette's
/// "New <Category>" values honoured by placed elements.
@Suite("Type Properties and new-element properties")
@MainActor
struct TypePropertiesEditorTests {
    static let fire = ParameterID("type.fireRating")

    /// A session on a box of walls with one door; undo groups are explicit (as in the app, one group per event).
    static func session() throws -> (DocumentSession, Fx.Box, ElementID) {
        var door = ElementID(0)
        let b = try Fx.box { tx, ids, walls in door = Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0)) }
        let s = DocumentSession(model: b.model)
        s.undoManager.groupsByEvent = false
        return (s, b, door)
    }
    static func group(_ s: DocumentSession, _ body: () -> Void) { s.undoManager.beginUndoGrouping(); body(); s.undoManager.endUndoGrouping() }
    static func fireRating(_ s: DocumentSession, _ t: ElementID) -> String? { Parameters.value(fire, of: s.model[t]!, s.model)?.textValue }

    @Test func cancelDiscardsStagedEdits() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let before = s.model
        let ed = TypePropertiesEditor(session: s, typeID: t)
        try ed.stage(Self.fire, text: "60", type: .text)
        #expect(Parameters.value(Self.fire, of: ed.preview[t]!, ed.preview)?.textValue == "60", "the dialog shows the staged value")
        #expect(Self.fireRating(s, t) != "60", "nothing reaches the model before Apply/OK")
        ed.cancel()
        #expect(s.model.revision == before.revision && s.model.nextID == before.nextID && !ed.hasChanges)
    }

    @Test func applyCommitsAndStaysOpenUndoRevertsIt() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let ed = TypePropertiesEditor(session: s, typeID: t)
        try ed.stage(Self.fire, text: "60", type: .text)
        Self.group(s) { #expect(ed.apply()) }
        #expect(Self.fireRating(s, t) == "60" && !ed.hasChanges && ed.typeID == t)
        s.undoManager.undo()
        #expect(Self.fireRating(s, t) != "60")
    }

    @Test func okCommitsEveryEditAsOneUndoStep() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let before = s.model[t]
        let ed = TypePropertiesEditor(session: s, typeID: t)
        try ed.stage(Self.fire, text: "90", type: .text)
        try ed.stage(ParameterID("type.mark"), text: "W1", type: .text)
        var a = try #require(before?.typeData?.assembly)
        a.layers[0].thickness += 0.05
        try ed.stage(assembly: a)
        Self.group(s) { #expect(ed.ok()) }
        #expect(Self.fireRating(s, t) == "90" && s.model[t]?.typeData?.assembly == a)
        s.undoManager.undo()
        #expect(s.model[t] == before)
    }

    @Test func invalidValuesAreRejectedWhenStaged() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let ed = TypePropertiesEditor(session: s, typeID: t)
        #expect(throws: ParameterError.self) { try ed.stage(ParameterID("type.cost"), text: "lots", type: .currency) }
        var a = try #require(s.model[t]?.typeData?.assembly)
        a.layers[0].thickness = 0
        #expect(throws: ParameterError.self) { try ed.stage(assembly: a) }
        #expect(!ed.hasChanges)
    }

    @Test func duplicateProposesUniqueNameAndRejectsDuplicates() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let name = s.model[t]!.name
        let ed = TypePropertiesEditor(session: s, typeID: t)
        #expect(ed.suggestedDuplicateName == "\(name) 2")
        #expect(throws: ParameterError.self) { try ed.duplicate(named: name) }
        #expect(throws: ParameterError.self) { try ed.duplicate(named: "  ") }
        try ed.duplicate(named: "\(name) 2")
        #expect(ed.suggestedDuplicateName == "\(name) 2 2")
        #expect(throws: ParameterError.self) { try ed.duplicate(named: "\(name) 2") }
    }

    @Test func duplicateThenOKAssignsSelectionAndUndoRevertsBoth() throws {
        let (s, b, _) = try Self.session()
        let wall = b.walls[0]
        let t = b.model[wall]!.typeID!
        let types = s.model.types(for: .walls).count
        let ed = TypePropertiesEditor(session: s, typeID: t, assignTo: [wall])
        try ed.duplicate(named: "Custom Wall")
        #expect(ed.isStagedDuplicate(ed.typeID) && ed.type?.name == "Custom Wall")
        #expect(s.model.types(for: .walls).count == types, "not created before OK")
        try ed.stage(Self.fire, text: "120", type: .text)
        Self.group(s) { #expect(ed.ok()) }
        let new = try #require(s.model.types(for: .walls).first { $0.name == "Custom Wall" })
        #expect(ed.typeID == new.id && s.model[wall]?.typeID == new.id)
        #expect(Self.fireRating(s, new.id) == "120" && Self.fireRating(s, t) != "120", "the original type is untouched")
        s.undoManager.undo()
        #expect(s.model[wall]?.typeID == t && s.model.types(for: .walls).count == types)
    }

    @Test func cancelAfterDuplicateCreatesNothing() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let before = s.model
        let ed = TypePropertiesEditor(session: s, typeID: t, assignTo: [b.walls[0]])
        try ed.duplicate(named: "Scratch")
        ed.cancel()
        #expect(s.model.revision == before.revision && s.model.nextID == before.nextID && ed.typeID == t)
    }

    @Test func switchingTypeThenOKAssignsIt() throws {
        let (s, b, _) = try Self.session()
        let wall = b.walls[0]
        let other = try #require(s.model.types(for: .walls).first { $0.id != s.model[wall]!.typeID && $0.typeData?.familyName == s.model[wall]!.typeData(in: s.model)?.familyName })
        let ed = TypePropertiesEditor(session: s, typeID: s.model[wall]!.typeID!, assignTo: [wall])
        ed.show(other.id)
        Self.group(s) { #expect(ed.ok()) }
        #expect(s.model[wall]?.typeID == other.id)
    }

    @Test func renameIsStagedAndValidated() throws {
        let (s, b, _) = try Self.session()
        let t = b.model[b.walls[0]]!.typeID!
        let old = s.model[t]!.name
        let taken = try #require(s.model.types(for: .walls).first { $0.id != t }).name
        let ed = TypePropertiesEditor(session: s, typeID: t)
        #expect(throws: ParameterError.self) { try ed.rename(taken) }
        try ed.rename("Renamed")
        #expect(s.model[t]?.name == old && ed.type?.name == "Renamed")
        Self.group(s) { #expect(ed.apply()) }
        #expect(s.model[t]?.name == "Renamed")
    }

    // MARK: New element properties

    @Test func newDoorRowsAndSillHeightHonoured() throws {
        let (s, b, _) = try Self.session()
        let plan = b.ids.planViews[b.l1]!
        let ctx = ToolContext(session: s, viewID: plan)
        let tool = InsertTool(ctx: ctx, category: .doors)
        let doorType = b.ids.familyTypes[Fx.doorType]
        let rows = NewElementProperties.rows(category: .doors, typeID: doorType, tool: tool, levelID: b.l1, model: s.model, defaults: nil)
        let names = rows.map(\.entry.name)
        for n in ["Level", "Sill Height", "Comments", "Mark", "Phase Created"] { #expect(names.contains(n), "New Doors shows \(n)") }
        for n in ["Sweep", "Sheet Name", "Cut Plane Offset", "Family", "Area"] { #expect(!names.contains(n), "New Doors lacks \(n)") }

        var d = CreationDefaults(categories: [.doors])
        try NewElementProperties.set(ParameterID("insert.sillHeight"), value: .double(0.9), category: .doors, typeID: doorType, tool: tool,
                                     levelID: b.l1, model: s.model, defaults: &d)
        #expect(tool.sillHeight == 0.9 && d.isEmpty, "the tool owns the sill (its Options Bar stays in step)")
        try NewElementProperties.set(.comments, value: .text("Fire exit"), category: .doors, typeID: doorType, tool: tool,
                                     levelID: b.l1, model: s.model, defaults: &d)
        #expect(d[.comments] == .text("Fire exit"))
        let shown = NewElementProperties.rows(category: .doors, typeID: doorType, tool: tool, levelID: b.l1, model: s.model, defaults: d)
        #expect(shown.first { $0.entry.name == "Sill Height" }?.entry.value == .double(0.9))
        #expect(shown.first { $0.entry.name == "Comments" }?.entry.value == .text("Fire exit"))

        // Placing a door while the defaults are installed.
        s.creationDefaults = d
        var placed = ElementID(0)
        Self.group(s) {
            s.perform("Door") { tx in
                placed = tx.create(.doors, data: .insert(InsertData(location: Vec2(6, 0), sillHeight: tool.sillHeight)), typeID: doorType, levelID: b.l1, hostID: b.walls[0])
            }
        }
        #expect(s.model[placed]?.insert?.sillHeight == 0.9 && s.model[placed]?.comments == "Fire exit")
        s.undoManager.undo()
        #expect(s.model[placed] == nil, "values are applied in the placing transaction")
        s.creationDefaults = nil
    }

    @Test func creationDefaultsApplyOnlyToNewElementsOfTheirCategory() throws {
        let (s, b, door) = try Self.session()
        var d = CreationDefaults(categories: [.doors])
        d.set(ParameterID("insert.sillHeight"), .double(0.45))
        d.set(.mark, .text("D-X"))
        s.creationDefaults = d
        Self.group(s) {
            s.perform("Edit") { tx in
                tx.update(door) { $0.comments = "existing" }
                Fx.wall(tx, b.ids, Vec2(0, 20), Vec2(5, 20))
            }
        }
        #expect(s.model[door]?.insert?.sillHeight == 0 && s.model[door]?.mark != "D-X", "existing doors are untouched")
        let newWall = try #require(s.model.elements(.walls).first { $0.wall?.location.start == Vec2(0, 20) })
        #expect(newWall.mark != "D-X", "other categories are untouched")
        s.creationDefaults = nil
    }

    @Test func newWallParametersGoToTheTool() throws {
        let (s, b, _) = try Self.session()
        let ctx = ToolContext(session: s, viewID: b.ids.planViews[b.l1]!)
        let tool = WallTool(ctx: ctx)
        #expect(tool.topLevelID == b.l2, "Arcus's default: up to the level above (documented deviation)")
        let type = b.ids.wallTypes[Fx.generic]
        var d = CreationDefaults(categories: [.walls])
        try NewElementProperties.set(ParameterID("wall.topConstraint"), value: .ref(nil), category: .walls, typeID: type, tool: tool,
                                     levelID: b.l1, model: s.model, defaults: &d)
        #expect(tool.topLevelID == nil)
        try NewElementProperties.set(ParameterID("wall.unconnectedHeight"), value: .double(4), category: .walls, typeID: type, tool: tool,
                                     levelID: b.l1, model: s.model, defaults: &d)
        #expect(tool.unconnectedHeight == 4 && d.isEmpty)
        let rows = NewElementProperties.rows(category: .walls, typeID: type, tool: tool, levelID: b.l1, model: s.model, defaults: d)
        #expect(rows.first { $0.entry.name == "Unconnected Height" }?.entry.value == .double(4))
        #expect(rows.first { $0.entry.name == "Base Constraint" }?.entry.value == .ref(b.l1))
        #expect(!rows.contains { $0.entry.name == "Length" }, "calculated values are not shown before placement")
    }
}

private extension Element {
    func typeData(in m: BIMModel) -> TypeData? { m.typeData(of: self) }
}
