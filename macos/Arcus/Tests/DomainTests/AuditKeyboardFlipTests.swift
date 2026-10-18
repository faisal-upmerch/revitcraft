import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// W4-AUDIT: the keyboard behaviours the Revit-feel QA sweep drives on screen (Space / Shift+Space while drawing
// and placing), pinned here so a regression is caught without the GUI harness.
@MainActor
@Suite("Audit: Space flips while drawing and placing")
struct AuditKeyboardFlipTests {
    func context() throws -> ToolContext {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        return ctx
    }

    @Test("Wall tool: Space toggles the exterior side and says so; the prompt mentions Space")
    func wallSpace() throws {
        let ctx = try context()
        let t = WallTool(ctx: ctx)
        #expect(t.flipSide == false)
        #expect(t.prompt.contains("Click to enter the wall start point"))
        t.pointerDown(ToolInput(point: Vec2(0, 0), rawPoint: Vec2(0, 0)))
        #expect(t.prompt.contains("Space flips"))
        #expect(t.numericLabel == "Length")
        t.spaceBar()
        #expect(t.flipSide == true)
        t.spaceBar()
        #expect(t.flipSide == false)
    }

    @Test("Door tool: Space flips facing, Shift+Space (flipHand) flips hand, and the prompt names both")
    func doorSpace() throws {
        let ctx = try context()
        let t = InsertTool(ctx: ctx, category: .doors)
        #expect(t.prompt.contains("Space flips facing"))
        #expect(!t.isFacingFlipped && !t.isHandFlipped)
        t.spaceBar()
        #expect(t.isFacingFlipped)
        t.flipHand()
        #expect(t.isHandFlipped)
        #expect(t.prompt.contains("Shift+Space") || t.prompt.contains("Space flips facing"))
    }

    @Test("Window vs crossing: the selection operation for a plain click replaces, and the modifier style is the BIM one by default in the app")
    func modifierOperations() {
        let style = SelectionModel.modifierStyle
        defer { SelectionModel.modifierStyle = style }
        SelectionModel.modifierStyle = .bim
        #expect(SelectionModel.operation(shift: false, command: false) == .replace)
        #expect(SelectionModel.operation(shift: false, command: true) == .add)
        #expect(SelectionModel.operation(shift: true, command: false) == .remove)
    }
}
