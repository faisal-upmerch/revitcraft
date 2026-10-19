import AppKit
import ArcusDomain
import ArcusPersistence

// FM8: File ▸ Open… and Finder open `.arcusfamily` files in the Family Editor, as Home ▸ Family does for a new family:
// for the open project (Load into Project loads there), or for a hidden new project that opens on the first Load into
// Project. The file joins Open Recent and Home's Recent grid.

@MainActor
enum FamilyFileOpen {
    /// Opens the family at `url` in the Family Editor. Returns the error that kept it from opening, or nil.
    @discardableResult
    static func open(_ url: URL) -> (any Error)? {
        do {
            let (family, _, _) = try FamilyPackage.read(from: url)
            // Already open from this file: bring it forward.
            if let wc = FamilyEditorWindowController.open.first(where: { $0.model.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                wc.window?.makeKeyAndOrderFront(nil)
                return nil
            }
            HomeFamilyStart.open(family: family, fileURL: url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return nil
        } catch {
            let a = NSAlert(error: error)
            a.messageText = "“\(url.lastPathComponent)” couldn’t be opened."
            a.runModal()
            return error
        }
    }
}
