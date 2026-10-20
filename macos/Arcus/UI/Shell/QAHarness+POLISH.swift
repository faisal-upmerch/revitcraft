import AppKit
import ArcusDomain
import ArcusApplication

// POLISH: ribbon panel collapsing (RibbonCollapse.swift), hooked from `screenshots()` with one line per appearance.
// At 1280 × 800 and at the minimum window size, every ribbon tab of the project window, a Furniture document and the
// Family Editor is checked: every panel is laid out, and none runs out of the ribbon strip (shrunk, collapsed or in
// More, every command stays reachable). QA steps "Ribbon …"; captures "polish-ribbon-…".
extension QAHarness {
    static func polishScreenshots(_ s: DocumentState, _ w: NSWindow, _ suffix: String) async {
        let size = w.contentView?.frame.size ?? NSSize(width: 1440, height: 900)
        s.session.selection.clear()
        await checkRibbonTabs(s, w, label: "project", suffix: suffix)
        w.setContentSize(size)
        AppDelegate.shared?.newFurniture(name: "Ribbon Check", category: .furniture, template: nil)
        await pause(900)
        if let f = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, f.mode == .furniture, let fw = f.window {
            await checkRibbonTabs(f, fw, label: "furniture", suffix: suffix)
            f.document?.updateChangeCount(.changeCleared)
            f.document?.close()
            await pause(500)
        }
        await checkFamilyEditorRibbon(s, suffix)
    }

    /// The window sizes the ribbon is checked at: 1280 × 800 and the window's minimum.
    static func ribbonSizes(_ w: NSWindow) -> [(NSSize, String)] {
        [(NSSize(width: 1280, height: 800), "1280"), (NSSize(width: max(w.minSize.width, 980), height: max(w.minSize.height, 640)), "min")]
    }

    /// QA steps: every tab of a document window's ribbon, at each size.
    static func checkRibbonTabs(_ s: DocumentState, _ w: NSWindow, label: String, suffix: String) async {
        let previous = s.ribbonTab
        for (size, sizeLabel) in ribbonSizes(w) {
            w.setContentSize(size)
            await pause(400)
            for tab in RibbonTab.tabs(for: s.mode) {
                await showRibbonTab(s, tab)
                await step("Ribbon \(label) \(sizeLabel) \(tab.rawValue) \(suffix)") { try ribbonTabReport(s, tab) }
                await shot(w, "polish-ribbon-\(label)-\(sizeLabel)-\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(suffix)")
            }
        }
        s.ribbonTab = previous
    }

    /// QA steps: every tab of the Family Editor's ribbon at 1280 × 800 and at the minimum size; Load into Project's
    /// panel is on every tab but Modify.
    static func checkFamilyEditorRibbon(_ s: DocumentState, _ suffix: String) async {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Ribbon Check"
        FamilyEditorWindowController.open(new: f, state: s)
        await pause(600)
        guard let wc = FamilyEditorWindowController.open.last, let w = wc.window else { return }
        for (size, label) in [(NSSize(width: 1280, height: 800), "1280"), (FamilyEditorChrome.minimumSize, "min")] {
            w.setContentSize(size)
            await pause(400)
            for tab in FamilyRibbonTab.allCases {
                await showFamilyRibbonTab(wc.model, tab)
                await step("Ribbon Family Editor \(label) \(tab.rawValue) \(suffix)") { try familyRibbonTabReport(wc.model, tab) }
                if tab == .create || tab == .modify { await shot(w, "polish-ribbon-family-editor-\(label)-\(tab.rawValue.lowercased())-\(suffix)") }
            }
        }
        w.close()
        await pause(300)
    }

    // PILLS: the steps' logic, shared with RibbonQAStepTests (UITests) so it runs without the app.

    /// Shows `tab`'s panels freshly laid out: another tab first (picking the tab already showing changes nothing, so
    /// nothing would be measured), then the frames are cleared and `tab` is picked.
    static func showRibbonTab(_ s: DocumentState, _ tab: RibbonTab, settle: Int = 300, view: NSView? = nil) async {
        let tabs = RibbonTab.tabs(for: s.mode)
        if s.ribbonTab == tab, let other = tabs.first(where: { $0 != tab }) {
            s.ribbonTab = other; s.ribbonShowsContextual = false
            await settleRibbon(view, settle / 2)
        }
        RibbonFrames.of(s).reset()
        s.ribbonTab = tab; s.ribbonShowsContextual = false
        await settleRibbon(view, settle)
    }

    /// Waits `ms`, laying `view` out as it goes (tests host the ribbon in a window that is never shown).
    static func settleRibbon(_ view: NSView?, _ ms: Int) async {
        guard let view else { await pause(ms); return }
        for _ in 0..<max(1, ms / 30) { view.layoutSubtreeIfNeeded(); await pause(30) }
        view.layoutSubtreeIfNeeded()
    }

    /// Every panel of the tab is laid out (in the row, shrunk or collapsed, or parked for the More popover) and none
    /// sticks out of the strip.
    static func ribbonTabReport(_ s: DocumentState, _ tab: RibbonTab) throws -> String {
        let frames = RibbonFrames.of(s)
        let expected = RibbonContent.panels(tab, mode: s.mode).count
        let more = frames.inOverflow.count
        try check(frames.panels.count == expected, "\(frames.panels.count - more) of \(expected) panels laid out, \(more) in More")
        let clipped = frames.clipped()
        try check(clipped.isEmpty, "clipped: \(clipped.joined(separator: ", "))")
        let shrunk = frames.density.filter { $0.value == 1 || $0.value == 2 }.count, collapsed = frames.density.filter { $0.value == 3 }.count
        return "\(expected) panels in \(Int(frames.row.width)) pt: \(shrunk) shrunk, \(collapsed) collapsed, \(more) in More"
    }

    /// The Family Editor's version of `showRibbonTab`.
    static func showFamilyRibbonTab(_ m: FamilyEditorModel, _ tab: FamilyRibbonTab, settle: Int = 300, view: NSView? = nil) async {
        if m.chrome.ribbonTab == tab, let other = FamilyRibbonTab.allCases.first(where: { $0 != tab }) {
            m.chrome.ribbonTab = other; m.chrome.ribbonShowsContextual = false
            await settleRibbon(view, settle / 2)
        }
        m.chrome.measuredPanels = [:]
        m.chrome.ribbonTab = tab; m.chrome.ribbonShowsContextual = false
        await settleRibbon(view, settle)
    }

    /// The Family Editor's tab: panels laid out, none out of the strip, Load into Project there (but on Modify).
    static func familyRibbonTabReport(_ m: FamilyEditorModel, _ tab: FamilyRibbonTab) throws -> String {
        let c = m.chrome, strip = c.measuredStrip
        try check(!c.measuredPanels.isEmpty, "no panels laid out")
        let parked = c.measuredPanels.filter { $0.value.maxX < RibbonPanelRow.parking / 2 }.map(\.key)
        let out = c.measuredPanels.filter { !parked.contains($0.key) && ($0.value.minX < strip.minX - 0.5 || $0.value.maxX > strip.maxX + 0.5) }.map(\.key)
        try check(out.isEmpty, "runs out of the strip: \(out.sorted().joined(separator: ", "))")
        try check(tab == .modify || c.measuredPanels["Family Editor"] != nil || !parked.isEmpty, "no Family Editor panel (Load into Project)")
        return "\(c.measuredPanels.count - parked.count) panels in \(Int(strip.width)) pt, \(parked.count) in More"
    }
}
