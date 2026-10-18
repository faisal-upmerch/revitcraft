import AppKit

extension DocumentState {
    /// Asks a yes/no question as a sheet on the document window (no window: the answer is no).
    func requestConfirmation(message: String, confirmTitle: String, completion: @escaping (Bool) -> Void) {
        guard let window else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Don’t \(confirmTitle)")
        alert.beginSheetModal(for: window) { r in completion(r == .alertFirstButtonReturn) }
    }
}
