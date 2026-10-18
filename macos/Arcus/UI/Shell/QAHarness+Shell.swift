import AppKit
import ArcusDomain
import ArcusApplication

// W4-SHELL: screenshots of the floating docks (hooked from `QAHarness.screenshots()` with one line, per appearance).

extension QAHarness {
    /// Captures the floating sidebar over a plan (spacious window), collapsed, in the narrowest window, and the Mac
    /// Spacious inspector. Leaves the window at 1600 × 1000 with the BIM Familiar workspace and the sidebar shown.
    static func shellScreenshots(_ s: DocumentState, _ w: NSWindow, suffix: String) async {
        guard let plan = view(s, kind: .floorPlan, level: "Ground Floor") else { return }
        s.open(plan.id)
        _ = await waitForGraphics(s, plan.id)
        w.setContentSize(NSSize(width: 1600, height: 1000)); w.center()
        s.docks.setCollapsed(false, .leading); s.onWorkspaceChange?()
        if let wall = s.model.elements(.walls).first(where: { $0.levelID == plan.levelID }) { s.session.selection.select([wall.id]) }
        await pause(600)
        await shot(w, "sidebar-floating-\(suffix)")
        // W4-WIRE: the ribbon minimized to its tab pill; a tool with its Options pill; a second open view's tab pills.
        s.ribbonCollapsed = true
        await pause(500)
        await shot(w, "shell-ribbon-minimized-\(suffix)")
        s.ribbonCollapsed = false
        CommandRouter(state: s).run(.wall)
        await pause(500)
        await shot(w, "shell-options-pill-\(suffix)")
        s.cancelTool()
        // N2: every ribbon tab with nothing selected, to check panels, order and fit against RevitCraft's ribbon.
        let kept = s.session.selection.ids
        s.session.selection.clear()
        for tab in RibbonTab.allCases {
            s.ribbonTab = tab; s.ribbonShowsContextual = false
            await pause(300)
            await shot(w, "ribbon-\(tab.rawValue.lowercased().replacingOccurrences(of: " & ", with: "-"))-\(suffix)")
        }
        s.ribbonTab = .architecture
        s.session.selection.select(Array(kept))
        if let other = s.model.views.first(where: { $0.id != plan.id && $0.view?.kind == .floorPlan }) {
            s.open(other.id)
            _ = await waitForGraphics(s, other.id)
            s.activeViewID = plan.id
            await pause(600)
            await shot(w, "shell-view-tabs-\(suffix)")
            s.close(other.id)
        }
        s.docks.setCollapsed(true, .leading); s.onWorkspaceChange?()
        await pause(600)
        await shot(w, "sidebar-collapsed-\(suffix)")
        s.docks.setCollapsed(false, .leading); s.onWorkspaceChange?()
        w.setContentSize(NSSize(width: 980, height: 640)); w.center()
        await pause(600)
        await shot(w, "sidebar-narrow-\(suffix)")
        w.setContentSize(NSSize(width: 1600, height: 1000)); w.center()
        let workspace = s.workspace
        s.workspace = .macSpacious
        s.docks.setCollapsed(false, .trailing); s.onWorkspaceChange?()
        await pause(700)
        await shot(w, "inspector-floating-\(suffix)")
        w.setContentSize(NSSize(width: 980, height: 640)); w.center() // W4-WIRE: both docks at the minimum window
        await pause(600)
        await shot(w, "shell-spacious-narrow-\(suffix)")
        w.setContentSize(NSSize(width: 1600, height: 1000)); w.center()
        s.workspace = workspace
        s.session.selection.clear()
        await pause(400)
    }
}
