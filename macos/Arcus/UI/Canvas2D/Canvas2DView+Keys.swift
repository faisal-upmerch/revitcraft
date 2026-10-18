import AppKit
import ArcusApplication

// BL-KEYS: canvas keys decided before the canvas's own handling; the decisions are `CanvasKeyRouter`'s (unit tested).
extension Canvas2DView {
    /// Returns true when the key was handled here.
    func keysHandle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        let key: CanvasKey
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .returnKey
        case 49: key = .space(shift: event.modifierFlags.contains(.shift))
        default: key = (event.charactersIgnoringModifiers?.first).map(CanvasKey.character) ?? .other
        }
        let context = CanvasKeyContext(textEditing: TextInputFocus.isEditingText(in: window), modified: !flags.isEmpty,
                                       toolActive: state.activeTool != nil, preselectionPending: state.keys.pendingCommand != nil,
                                       hasSelection: !state.session.selection.isEmpty)
        switch CanvasKeyRouter.route(key, context) {
        case .ignore:
            TextInputFocus.focusInlineEditor(in: window)
            return true
        case .standard:
            return false
        case .finishPreselection:
            state.finishPreselection()
        case .repeatLastCommand:
            state.repeatLastCommand()
        case .flipSelection:
            guard state.flipSelectionWithSpace() else { return false }
        case .flipHand:
            if let t = state.activeTool as? InsertTool { t.flipHand() } else { state.activeTool?.spaceBar() }
            state.toolChangedState()
        }
        needsDisplay = true
        return true
    }
}
