import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

@Suite("Undo and redo")
@MainActor
struct UndoTests {
    @Test func typeParameterUndoRestoresWidth() throws {
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let session = DocumentSession(model: m0)
        session.undoManager.groupsByEvent = false
        func group(_ body: () -> Void) { session.undoManager.beginUndoGrouping(); body(); session.undoManager.endUndoGrouping() }
        var wall: ElementID!
        group {
            session.perform("Wall") { tx in
                wall = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(10, 0))), topLevelID: ids.levels[1])),
                                 typeID: ids.wallTypes["Generic - 200mm"], levelID: ids.levels[0])
            }
        }
        var door: ElementID!
        group {
            session.perform("Door") { tx in
                door = tx.create(.doors, data: .insert(InsertData(location: Vec2(5, 0))), typeID: ids.familyTypes["Door - Single Flush: 900 x 2100"], levelID: ids.levels[0], hostID: wall)
            }
        }
        func width() -> Double { InsertGeometry.openingSize(session.model[door]!, session.model)?.width ?? -1 }
        #expect(abs(width() - 1.0) < 1e-9)
        group { session.setParameter(Parameters.familyParamID("Width"), text: "1000", on: [door], type: .length, name: "Width") }
        #expect(abs(width() - 1.1) < 1e-9)
        session.undoManager.undo()
        #expect(abs(width() - 1.0) < 1e-9, "after undo: \(width())")
        session.undoManager.redo()
        #expect(abs(width() - 1.1) < 1e-9, "after redo: \(width())")
        session.undoManager.undo()
        session.undoManager.undo()
        #expect(session.model[door] == nil)
        session.undoManager.redo()
        #expect(abs(width() - 1.0) < 1e-9, "after re-place: \(width())")
    }
}
