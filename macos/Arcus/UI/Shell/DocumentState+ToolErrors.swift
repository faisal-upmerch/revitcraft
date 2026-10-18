import AppKit
import ArcusDomain

// BL-CANVAS (ARCUS-050): errors that stop a tool operation (a sketch that doesn't close, lines that cross) are shown
// as an alert with the tool's own actions — for sketches, Continue (back to the sketch, offending lines highlighted)
// and Quit Sketch.

extension DocumentState {
    func presentToolError(message: String, detail: String, actions: [String], completion: @escaping (Int) -> Void) {
        toolChangedState()
        guard let window else { show(message, error: true); completion(0); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        for a in actions { alert.addButton(withTitle: a) }
        alert.beginSheetModal(for: window) { [weak self] r in
            completion(r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            self?.toolChangedState()
            (self?.canvases[self?.activeViewID ?? ElementID(0)] as? Canvas2DView)?.needsDisplay = true
        }
    }
}
