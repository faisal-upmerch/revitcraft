import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-BROWSER: interaction QA for the Project Browser (hooked from `QAHarness.interaction()`).

extension QAHarness {
    /// The Project Browser outline in the document window.
    @MainActor static func browserOutline(_ w: NSWindow) -> BrowserOutlineView? {
        func find(_ v: NSView) -> BrowserOutlineView? {
            if let o = v as? BrowserOutlineView { return o }
            for c in v.subviews { if let hit = find(c) { return hit } }
            return nil
        }
        return w.contentView.flatMap(find)
    }

    /// F2 rename takes the keyboard (typing starts no tool), Enter commits, a duplicate name keeps the editor open,
    /// Esc cancels, undo restores; the browser selection follows the active view; a view dragged in places with a click.
    static func browserInteraction(_ s: DocumentState, _ d: CanvasDriver, plan: Element,
                                   run: @MainActor (String, () async throws -> String) async -> Void) async {
        await run("browser: F2 rename owns the keyboard, Enter commits, duplicates rejected, Esc cancels, undo") {
            guard let w = s.window, let outline = browserOutline(w), let browser = outline.controller else { throw QAError("no Project Browser outline") }
            s.open(plan.id)
            await d.settle()
            let original = s.model[plan.id]?.name ?? ""
            w.makeFirstResponder(outline)
            if let row = browser.item(ProjectBrowserTree.viewNodeID(plan.id)).map(outline.row(forItem:)), row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            d.key("\u{F705}", keyCode: 120) // F2
            await d.flushEvents()
            try check(browser.renaming != nil, "F2 did not start renaming")
            try check((w.firstResponder as? NSTextView)?.isFieldEditor == true, "the rename field is not first responder (\(String(describing: w.firstResponder)))")
            d.type("WAFL")
            await d.flushEvents()
            try check(s.activeTool == nil, "typing into the rename field started \(s.activeTool?.title ?? "a tool")")
            d.enter()
            await d.flushEvents(); await pause(100)
            try check(s.model[plan.id]?.name == "wafl", "Enter did not commit the typed name (\(s.model[plan.id]?.name ?? "-"))")
            d.undo(); await d.flushEvents(); await pause(100)
            try check(s.model[plan.id]?.name == original, "undo did not restore “\(original)”")
            // A name used by another floor plan is refused and the editor stays open; Esc then cancels.
            browser.beginRename(ProjectBrowserTree.viewNodeID(plan.id))
            (w.firstResponder as? NSTextView)?.string = "Level 2"
            d.enter(); await d.flushEvents()
            try check(browser.renaming != nil && s.model[plan.id]?.name == original, "a duplicate name was accepted or closed the editor")
            d.escape(); await d.flushEvents()
            try check(browser.renaming == nil && s.model[plan.id]?.name == original, "Esc did not cancel renaming")
            return "renamed to “wafl” without starting a tool, undid, refused “Level 2”, Esc cancelled"
        }
        await run("browser: highlight follows the active view; tabs show for one view") {
            guard let w = s.window, let browser = browserOutline(w)?.controller else { throw QAError("no Project Browser outline") }
            guard let ceiling = s.model.views.first(where: { $0.view?.kind == .ceilingPlan && $0.name == plan.name }) else { return "no ceiling plan" }
            s.open(ceiling.id); await d.settle()
            try check(browser.selectedNodes().map(\.elementID) == [ceiling.id], "the ceiling plan with the same name is not the highlighted node")
            s.open(plan.id); await d.settle()
            try check(browser.selectedNodes().map(\.elementID) == [plan.id], "switching back did not move the highlight")
            s.closeInactiveViews(); await d.settle()
            try check(s.openViews == [plan.id], "close inactive views left \(s.openViews.count) open")
            return "highlight moved with activation; one tab left open"
        }
        await run("sheet: a dragged-in view follows the cursor and a click places it") {
            guard let sheet = s.model.sheets.first else { return "no sheet" }
            guard let view = PlaceViewCandidates.list(forSheet: sheet.id, s.model).first(where: { s.model[$0.id]?.view?.kind == .elevation }) else { return "nothing to place" }
            try check(s.beginViewportPlacement([view.id], onSheet: sheet.id), "placement did not start")
            await d.settle()
            let before = s.model.owned(byView: sheet.id).count
            d.click(d.windowPoint(canvasFraction: 0.3, 0.4))
            await d.flushEvents(); await pause(100)
            try check(s.model.owned(byView: sheet.id).count == before + 1 && s.model.sheet(containing: view.id)?.id == sheet.id, "the click did not place the viewport")
            try check(!s.beginViewportPlacement([view.id], onSheet: sheet.id), "an already placed view was accepted again")
            return "placed \(view.title) with a click; a second placement was refused"
        }
    }
}
