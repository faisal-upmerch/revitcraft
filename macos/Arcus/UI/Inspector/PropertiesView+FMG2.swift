import SwiftUI
import ArcusDomain
import ArcusApplication

// FMG2: Properties of the joint the Joint tool picked. Editing a joint the rules make creates the user's joint (one
// undo step), as editing a wall join does in Revit; an edit back to the rule removes it again.

extension PropertiesView {
    func fmg2JointEdit(_ key: JointKey) -> (ParameterID, ParamValue) throws(ParameterError) -> Void {
        let state = self.state
        return { id, value throws(ParameterError) in
            var failure: ParameterError?
            state.session.perform("Change Joint") { tx in
                do { try FurnitureJointOperations.setProperty(key, id, value, in: tx) } catch {
                    let e = error as? ParameterError ?? ParameterError("\(error)")
                    failure = e
                    throw TransactionError(e.message)
                }
            }
            if let failure { throw failure }
            if let tool = state.activeTool as? FurnitureJointTool {
                if let id = FurnitureJointOperations.element(key, state.model)?.id { state.session.selection.select([id]) } else { state.session.selection.clear() }
                tool.refresh()
            }
            state.toolChangedState()
        }
    }
}
