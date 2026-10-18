import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W4-SHELL: interaction QA for the floating docks (hooked from `QAHarness.interaction()` with one line).

extension QAHarness {
    /// The floating dock panel views in a window (leading first).
    @MainActor static func dockPanels(_ w: NSWindow) -> [DockPanelView] {
        var out: [DockPanelView] = []
        func find(_ v: NSView) { if let p = v as? DockPanelView { out.append(p) }; v.subviews.forEach(find) }
        if let c = w.contentView { find(c) }
        return out.sorted { $0.edge == .leading && $1.edge != .leading }
    }
    /// Every glass shield of a role in a window, in window coordinates (W4-WIRE).
    @MainActor static func shields(_ w: NSWindow, _ role: ShellPillRole) -> [(view: GlassShieldView, frame: NSRect)] {
        var out: [(GlassShieldView, NSRect)] = []
        func find(_ v: NSView) { if let p = v as? GlassShieldView, p.role == role, !p.isHiddenOrHasHiddenAncestor { out.append((p, p.convert(p.bounds, to: nil))) }; v.subviews.forEach(find) }
        if let c = w.contentView { find(c) }
        return out
    }

    /// Wheel and clicks over the sidebar never reach the canvas; ⌥⌘S collapses and shows it with the insets following;
    /// dragging its inner edge resizes it and the width is saved.
    static func shellInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        let w = d.window
        await step("Shell: sidebar floats over the canvas and takes its own input (W4-SHELL)") {
            guard let c = d.canvas else { throw QAError("no canvas") }
            try check(DockVisibility(s).leading, "the sidebar is not visible")
            await pause(200)
            guard let panel = dockPanels(w).first(where: { $0.edge == .leading }) else { throw QAError("no floating sidebar panel in the window") }
            let frame = panel.convert(panel.bounds, to: nil)
            try check(frame.minX > 0 && frame.minY > 0, "the sidebar is jammed against the window edge: \(frame)")
            // The canvas spans the whole content area (the panel floats over it), and the insets keep the controls clear.
            let canvasFrame = c.convert(c.bounds, to: nil)
            try check(canvasFrame.minX < frame.minX, "the canvas does not extend behind the sidebar (canvas \(canvasFrame), sidebar \(frame))")
            try check(s.docks.leadingInset >= Double(frame.width), "leading inset \(s.docks.leadingInset) is smaller than the sidebar \(frame.width)")
            try check(c.safeAreaRect.minX >= frame.maxX - 1, "the canvas safe area \(c.safeAreaRect) does not exclude the sidebar")
            // Wheel over the panel's header: the canvas zoom must not change.
            let p = NSPoint(x: frame.midX, y: frame.maxY - 24)
            let zoom = c.zoom, downs = c.mouseDownCount
            for _ in 0..<4 { d.scroll(at: p, dy: 3, continuous: false); await pause(15) }
            try check(c.zoom == zoom, "a wheel over the sidebar zoomed the canvas (\(zoom) → \(c.zoom))")
            // A click over the panel lands in the panel, not the canvas.
            let hit = w.contentView?.hitTest(w.contentView!.convert(p, from: nil))
            var inPanel = false
            var v: NSView? = hit
            while let cur = v { if cur === panel { inPanel = true; break }; v = cur.superview }
            try check(inPanel, "hit test over the sidebar returned \(hit.map { "\(type(of: $0))" } ?? "nil")")
            d.click(p); await pause(60)
            try check(c.mouseDownCount == downs, "a click over the sidebar reached the canvas")
            return String(format: "sidebar %.0f×%.0f at x=%.0f; canvas %.0f wide behind it", frame.width, frame.height, frame.minX, canvasFrame.width)
        }
        await step("Shell: ⌥⌘S collapses and shows the sidebar; insets follow (W4-SHELL)") {
            // The menu item's route: the app delegate forwards to the key document window's controller.
            AppDelegate.shared?.toggleDocumentSidebar(nil)
            await pause(500)
            try check(!DockVisibility(s).leading, "the sidebar did not collapse (key window \(NSApp.keyWindow === w), first responder \(w.firstResponder.map { "\(type(of: $0))" } ?? "nil"))")
            try check(s.docks.leadingInset == 0, "leading inset \(s.docks.leadingInset) after collapsing")
            try check(dockPanels(w).first(where: { $0.edge == .leading }) == nil, "the collapsed sidebar is still in the window")
            try check(UserDefaults.standard.bool(forKey: "dock.leading.collapsed"), "collapsed state not saved")
            AppDelegate.shared?.toggleDocumentSidebar(nil)
            await pause(500)
            try check(DockVisibility(s).leading && s.docks.leadingInset > 0, "the sidebar did not come back")
            try check(dockPanels(w).contains { $0.edge == .leading }, "the shown sidebar is not in the window")
            await d.verify("sidebar shown again")
            return "collapsed and shown"
        }
        await step("Shell: dragging the sidebar's edge resizes it and the width persists (W4-SHELL)") {
            guard let panel = dockPanels(w).first(where: { $0.edge == .leading }) else { throw QAError("no sidebar panel") }
            let before = panel.convert(panel.bounds, to: nil)
            let start = NSPoint(x: before.maxX - 3, y: before.midY)
            let width0 = s.docks.prefs.leadingWidth
            d.drag(from: start, to: NSPoint(x: start.x + 40, y: start.y))
            await pause(300)
            let after = panel.convert(panel.bounds, to: nil)
            try check(abs(after.width - before.width - 40) < 2, "sidebar width \(before.width) → \(after.width) after a 40 pt drag")
            try check(abs(UserDefaults.standard.double(forKey: "dock.leading.width") - Double(after.width)) < 2, "saved width \(UserDefaults.standard.double(forKey: "dock.leading.width")) ≠ \(after.width)")
            try check(s.docks.leadingInset >= Double(after.width), "inset did not follow the resize")
            // Back to the previous width.
            s.docks.setWidth(width0, .leading); s.docks.save()
            await pause(200)
            await d.verify("sidebar resized and restored")
            return String(format: "%.0f → %.0f → %.0f", before.width, after.width, width0)
        }
        await wireInteraction(s, d) // W4-WIRE: the floating shell
    }

    /// W4-WIRE: the pills float over the canvas, swallow input, keep clear of each other and inset the canvas; the
    /// traffic lights live in the sidebar (or the collapsed strip); the ribbon minimizes to its tab pill; the Options
    /// pill and the view-tab pills appear when they apply.
    static func wireInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        let w = d.window
        func one(_ role: ShellPillRole) throws -> NSRect {
            let all = shields(w, role)
            try check(all.count == 1, "expected one \(role) pill, found \(all.count)")
            return all[0].frame
        }
        await step("Shell: no toolbar; the canvas spans the whole window and the pills sit over it (W4-WIRE)") {
            guard let c = d.canvas, let content = w.contentView else { throw QAError("no canvas") }
            try check(w.toolbar == nil, "the window still has a toolbar")
            try check(w.styleMask.contains(.fullSizeContentView) && w.titlebarAppearsTransparent, "the title bar is not transparent full-size content")
            let canvasFrame = c.convert(c.bounds, to: nil)
            try check(abs(canvasFrame.height - content.frame.height) < 1 && abs(canvasFrame.width - content.frame.width) < 1,
                      "the canvas \(canvasFrame) does not fill the content view \(content.frame)")
            let tabs = try one(.tabs), controls = try one(.controls), ribbon = try one(.ribbon), bottom = try one(.bottom)
            let top = content.frame.maxY
            let m = CGFloat(ShellMetrics.arcus.margin)
            try check(abs(top - tabs.maxY - m) < 1 && abs(top - controls.maxY - m) < 1, "top-row pills are not \(m) pt under the window top: tabs \(tabs), controls \(controls)")
            try check(tabs.maxX + m <= controls.minX + 0.5, "the tab pill \(tabs) collides with the controls pill \(controls)")
            try check(abs(ribbon.maxY + m - tabs.minY) < 1, "the ribbon strip \(ribbon) is not one margin under the tab pill \(tabs)")
            try check(abs(bottom.minY - m) < 1, "the bottom pill \(bottom) is not \(m) pt above the window bottom")
            if let sidebar = dockPanels(w).first(where: { $0.edge == .leading }) {
                let sf = sidebar.convert(sidebar.bounds, to: nil)
                for (name, f) in [("tabs", tabs), ("ribbon", ribbon), ("bottom", bottom)] { try check(f.minX >= sf.maxX + m - 0.5, "the \(name) pill \(f) overlaps the sidebar \(sf)") }
            }
            // The canvas's safe area excludes every row above and the bottom pill.
            let safe = c.convert(c.safeAreaRect, to: nil)
            try check(safe.maxY <= ribbon.minY - m + 0.5, "the canvas safe area \(safe) reaches under the ribbon strip \(ribbon)")
            try check(safe.minY >= bottom.maxY + m - 0.5, "the canvas safe area \(safe) reaches under the bottom pill \(bottom)")
            try check(s.docks.topInset >= Double(top - ribbon.minY) && s.docks.bottomInset >= Double(bottom.maxY), "insets \(s.docks.topInset)/\(s.docks.bottomInset) do not cover the rows")
            return String(format: "tabs %.0f wide, controls %.0f wide, ribbon %.0f×%.0f, canvas safe %.0f×%.0f", tabs.width, controls.width, ribbon.width, ribbon.height, safe.width, safe.height)
        }
        await step("Shell: the traffic lights sit in the sidebar and work (W4-WIRE)") {
            guard let sidebar = dockPanels(w).first(where: { $0.edge == .leading }) else { throw QAError("no sidebar") }
            let sf = sidebar.convert(sidebar.bounds, to: nil)
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { w.standardWindowButton($0) }
            try check(buttons.count == 3, "\(buttons.count) standard window buttons")
            for b in buttons {
                let f = b.convert(b.bounds, to: nil)
                try check(sf.contains(f), "window button \(f) is outside the sidebar \(sf); superview \(b.superview.map { "\(type(of: $0))" } ?? "nil")")
                try check(f.minY > sf.maxY - 44, "window button \(f) is not in the sidebar's top row (sidebar top \(sf.maxY))")
                try check(!b.isHiddenOrHasHiddenAncestor && b.isEnabled && b.action != nil && b.window === w, "window button is not functional: hidden \(b.isHidden) enabled \(b.isEnabled) action \(b.action.map { "\($0)" } ?? "nil")")
            }
            let xs = buttons.map { $0.convert($0.bounds, to: nil).minX }
            try check(xs[0] < xs[1] && xs[1] < xs[2], "window buttons are out of order: \(xs)")
            let hit = w.contentView?.hitTest(w.contentView!.convert(buttons[0].convert(NSPoint(x: buttons[0].bounds.midX, y: buttons[0].bounds.midY), to: nil), from: nil))
            try check(hit === buttons[0] || hit?.isDescendant(of: buttons[0]) == true, "hit test over the close button returned \(hit.map { "\(type(of: $0))" } ?? "nil")")
            return String(format: "close at x=%.0f y=%.0f (sidebar top %.0f)", xs[0], buttons[0].convert(buttons[0].bounds, to: nil).minY, sf.maxY)
        }
        await step("Shell: clicks and wheels over the pills never reach the canvas (W4-WIRE)") {
            guard let c = d.canvas else { throw QAError("no canvas") }
            for role in [ShellPillRole.tabs, .controls, .ribbon, .bottom] {
                let f = try one(role)
                // The pill's own surface, away from its controls: the padding row along its top edge.
                let p = NSPoint(x: f.minX + 14, y: f.maxY - 2.5)
                let zoom = c.zoom, downs = c.mouseDownCount, center = c.center
                for _ in 0..<3 { d.scroll(at: p, dy: 3, continuous: false); await pause(15) }
                d.scroll(at: p, dx: 20, dy: 0, continuous: true); await pause(30)
                try check(c.zoom == zoom && c.center == center, "a wheel over the \(role) pill moved the canvas (zoom \(zoom) → \(c.zoom))")
                let hit = w.contentView?.hitTest(w.contentView!.convert(p, from: nil))
                var inShield = false
                var v: NSView? = hit
                while let cur = v { if cur is GlassShieldView { inShield = true; break }; v = cur.superview }
                try check(inShield, "hit test over the \(role) pill returned \(hit.map { "\(type(of: $0))" } ?? "nil")")
                d.click(p); await pause(40)
                try check(c.mouseDownCount == downs, "a click over the \(role) pill reached the canvas")
            }
            return "tabs, controls, ribbon and bottom pills contain their input"
        }
        await step("Shell: minimizing the ribbon hides the strip, keeps the tab pill and lifts the canvas inset (W4-WIRE)") {
            let tabsBefore = try one(.tabs)
            let insetBefore = s.docks.topInset
            s.ribbonCollapsed = true
            await pause(450)
            var problems: [String] = []
            if !shields(w, .ribbon).isEmpty { problems.append("the ribbon strip is still showing while minimized") }
            let tabsAfter = try one(.tabs)
            if abs(tabsAfter.minY - tabsBefore.minY) >= 1 { problems.append("the tab pill moved when the ribbon minimized: \(tabsBefore) → \(tabsAfter)") }
            if s.docks.topInset >= insetBefore - 60 { problems.append("the top inset did not shrink: \(insetBefore) → \(s.docks.topInset)") }
            if let c = d.canvas {
                let safe = c.convert(c.safeAreaRect, to: nil)
                let expected = w.contentView!.frame.maxY - CGFloat(s.docks.topInset)
                if abs(safe.maxY - expected) >= 1 { problems.append("the canvas safe area \(safe) does not end at the top inset \(s.docks.topInset) (expected maxY \(expected)); container insets \(c.superview.map { "\($0.safeAreaInsets) + \($0.additionalSafeAreaInsets)" } ?? "-")") }
            }
            s.ribbonCollapsed = false // restored before any check can throw: the flag persists per user
            await pause(450)
            try check(problems.isEmpty, problems.joined(separator: " | "))
            try check(!shields(w, .ribbon).isEmpty && abs(s.docks.topInset - insetBefore) < 1, "the ribbon strip did not come back (inset \(s.docks.topInset))")
            return String(format: "inset %.0f → %.0f → %.0f", insetBefore, insetBefore - 108, s.docks.topInset)
        }
        await step("Shell: the collapsed sidebar becomes a strip with the traffic lights; the tab pill follows (W4-WIRE)") {
            let tabsBefore = try one(.tabs)
            AppDelegate.shared?.toggleDocumentSidebar(nil)
            await pause(500)
            let strip = try one(.collapsedStrip)
            let m = CGFloat(ShellMetrics.arcus.margin)
            try check(abs(strip.minX - m) < 1 && abs(w.contentView!.frame.maxY - strip.maxY - m) < 1, "the strip \(strip) is not in the top-left corner")
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { w.standardWindowButton($0) }
            for b in buttons { try check(strip.contains(b.convert(b.bounds, to: nil)), "window button \(b.convert(b.bounds, to: nil)) is outside the strip \(strip)") }
            let tabsAfter = try one(.tabs)
            try check(abs(tabsAfter.minX - strip.maxX - m) < 1, "the tab pill \(tabsAfter) did not follow the strip \(strip)")
            try check(tabsAfter.minX < tabsBefore.minX - 100, "the tab pill did not slide left (\(tabsBefore.minX) → \(tabsAfter.minX))")
            AppDelegate.shared?.toggleDocumentSidebar(nil)
            await pause(900) // the strip slides out with the sidebar's spring
            try check(shields(w, .collapsedStrip).isEmpty, "the strip is still showing with the sidebar back")
            guard let sidebar = dockPanels(w).first(where: { $0.edge == .leading }) else { throw QAError("the sidebar did not come back") }
            let sf = sidebar.convert(sidebar.bounds, to: nil)
            capture(w, "wire-after-sidebar-toggle")
            for b in buttons { try check(sf.contains(b.convert(b.bounds, to: nil)), "window button \(b.convert(b.bounds, to: nil)) did not return to the sidebar \(sf); superview \(b.superview.map { "\(type(of: $0))" } ?? "nil") in window \(b.window === w)") }
            return String(format: "strip %.0f×%.0f; tab pill x %.0f → %.0f → %.0f", strip.width, strip.height, tabsBefore.minX, tabsAfter.minX, try one(.tabs).minX)
        }
        await step("Shell: a running tool adds the Options pill under the ribbon; two views add the tab pills (W4-WIRE)") {
            try check(shields(w, .options).isEmpty, "an Options pill shows with no tool running")
            let insetBefore = s.docks.topInset
            CommandRouter(state: s).run(.wall)
            await pause(450)
            capture(w, "wire-options-step")
            let options = try one(.options), ribbon = try one(.ribbon)
            let m = CGFloat(ShellMetrics.arcus.margin)
            try check(abs(ribbon.minY - options.maxY - m) < 1, "the Options pill \(options) is not under the ribbon strip \(ribbon)")
            try check(abs(options.minX - ribbon.minX) < 1, "the Options pill \(options) is not left-aligned with the ribbon \(ribbon)")
            try check(s.docks.topInset > insetBefore + 30, "the top inset did not grow for the Options pill")
            s.cancelTool()
            await pause(450)
            try check(shields(w, .options).isEmpty && abs(s.docks.topInset - insetBefore) < 1, "the Options pill did not go away")
            let openBefore = s.openViews.count
            try check(shields(w, .viewTab).isEmpty == (openBefore < 2), "view-tab pills: \(shields(w, .viewTab).count) with \(openBefore) view(s) open")
            let first = s.activeViewID
            guard let other = s.model.views.first(where: { $0.id != first && $0.view?.kind == .floorPlan }) ?? s.model.views.first(where: { $0.id != first }) else { throw QAError("no second view") }
            s.open(other.id)
            await pause(600)
            let pills = shields(w, .viewTab)
            try check(pills.count == s.openViews.count + 1, "expected a pill per open view plus the menu (\(s.openViews.count + 1)), found \(pills.count)")
            let row = pills.map(\.frame)
            try check(row.allSatisfy { abs($0.minY - row[0].minY) < 1 }, "view-tab pills are not on one row: \(row)")
            try check(row.allSatisfy { abs(ribbon.minY - $0.maxY - m) < 1 }, "the view-tab row \(row[0]) is not under the ribbon \(ribbon)")
            try check(row.min(by: { $0.minX < $1.minX })!.minX >= ribbon.minX - 0.5, "view-tab pills start left of the ribbon strip")
            if let first { s.activeViewID = first }
            s.close(other.id)
            await pause(400)
            try check(shields(w, .viewTab).isEmpty == (s.openViews.count < 2), "view-tab pills after closing the second view: \(shields(w, .viewTab).count) with \(s.openViews.count) open")
            return "Options pill \(Int(options.width)) wide; \(pills.count) view-tab pills"
        }
    }
}
