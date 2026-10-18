import AppKit
import ArcusDomain

// W4-FAMED: screenshots of the Family Editor window (hooked from `screenshots()` with one line).
extension QAHarness {
    /// Opens a furniture family from the New Family template in the editor, captures it at the minimum (1000 pt) and a
    /// spacious (1440 pt) width with a form selected, then the Family Types sheet, and closes the window.
    static func familyEditorScreenshots(_ s: DocumentState, _ suffix: String) async {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        FamilyEditorWindowController.open(new: f, state: s)
        await pause(600)
        guard let wc = FamilyEditorWindowController.open.last, let w = wc.window else { return }
        for (width, height, label) in [(1000.0, 640.0, "min"), (1440.0, 900.0, "wide")] {
            w.setContentSize(NSSize(width: width, height: height))
            w.center()
            wc.model.select(nil)
            wc.model.zoomToFit()
            await pause(500)
            await shot(w, "family-editor-\(label)-\(suffix)")
            if let solid = wc.model.family.solids.first { wc.model.select(.solid(solid.id)) }
            await pause(400)
            await shot(w, "family-editor-form-selected-\(label)-\(suffix)")
        }
        wc.model.view = .front
        wc.model.select(nil)
        await pause(500)
        await shot(w, "family-editor-front-\(suffix)")
        wc.model.view = .plan
        wc.model.sheet = .familyTypes
        await pause(900)
        if let sheet = w.attachedSheet { await shot(sheet, "family-types-dialog-\(suffix)") }
        wc.model.sheet = nil
        await pause(400)
        w.close()
        await pause(300)
    }
}
