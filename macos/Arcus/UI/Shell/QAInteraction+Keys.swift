import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-KEYS: interaction QA for keyboard focus, typed aliases, two-stage Esc, context-menu Cancel, the Modify
// pre-selection flow, Repeat and snap overrides (hooked from `interaction()` with one line). Expects the four walls of
// the first interaction step (0,0)–(12,8).
extension QAHarness {
    @MainActor static func keysInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        let w = d.window
        func focusCanvas() { if let c = d.canvas { w.makeFirstResponder(c) } }
        func reset() { s.cancelTool(); s.keys.pendingCommand = nil; s.session.selection.clear() }

        await step("Keys: a focused text field gets the letters, ⌘A and Return; the canvas runs nothing") {
            reset()
            let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 160, height: 22))
            w.contentView?.addSubview(field)
            defer { field.removeFromSuperview(); focusCanvas() }
            w.makeFirstResponder(field)
            try check(TextInputFocus.isEditingText(in: w), "the field editor is not recognised as text input")
            d.type("WA"); d.type("FL")
            await pause(60)
            try check(s.activeTool == nil, "typing in a text field started \(s.activeTool?.title ?? "?")")
            try check(field.currentEditor()?.string.uppercased() == "WAFL", "the field has “\(field.currentEditor()?.string ?? "")”, expected “wafl”")
            d.perform("selectAll:")
            try check(s.session.selection.isEmpty, "⌘A in a text field selected \(s.session.selection.count) elements")
            d.enter(); await pause(60)
            try check(s.activeTool == nil, "Return in a text field repeated a command")
            // An inline editor that is open but did not get focus (a rename field) blocks canvas keys too.
            focusCanvas()
            var focused = false
            TextInputFocus.begin("qa-inline", window: w) { focused = true }
            defer { TextInputFocus.end("qa-inline") }
            d.type("WA"); await pause(60)
            try check(s.activeTool == nil && focused, "with an inline editor open, WA reached the canvas (focus handed over: \(focused))")
            d.perform("selectAll:")
            try check(s.session.selection.isEmpty, "⌘A with an inline editor open selected elements")
            return "letters, ⌘A and Return stayed in the text controls"
        }

        await step("Keys: ZE/ZA mid-tool zoom and keep the Wall tool; the alias buffer clears") {
            reset(); focusCanvas()
            d.type("WA")
            try check(s.activeTool?.commandID == .wall, "WA did not start the Wall tool")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(2, 3))); d.click(model: Vec2(2, 3)); await pause(40)
            let zoomBefore = d.canvas?.zoom ?? 0
            d.type("ZO"); await pause(60)
            try check(s.activeTool?.commandID == .wall, "ZO ended the Wall tool")
            try check((d.canvas?.zoom ?? 0) < zoomBefore * 0.75, "ZO did not zoom out (\(zoomBefore) → \(d.canvas?.zoom ?? 0))")
            d.type("ZE"); await pause(60)
            try check(s.activeTool?.commandID == .wall, "ZE ended the Wall tool")
            try check(s.keys.aliasTyped == nil && !s.prompt.hasPrefix("Shortcut:"), "the buffer still shows \(s.prompt)")
            d.type("Q"); try check(s.keys.aliasTyped == nil, "Q (no alias) stayed in the buffer")
            d.type("Z"); try check(s.keys.aliasTyped == "Z", "Z is not echoed")
            d.escape(); try check(s.keys.aliasTyped == nil && s.activeTool != nil, "Esc did not just clear the buffer")
            d.type("ZA"); await pause(60)
            try check(s.activeTool?.commandID == .wall, "ZA ended the Wall tool")
            d.escape(); d.escape(); d.escape()
            await d.verify("after zoom aliases mid-tool")
            return "zoomed out, fit and zoom-all while drawing; buffer cleared on match, non-match and Esc"
        }

        await step("Keys: Esc ends the chain, then the tool, then the selection; Select Previous restores it") {
            reset(); focusCanvas()
            let walls = s.model.elements(.walls).count
            d.type("WA")
            for p in [Vec2(2, 2), Vec2(5, 2)] { d.mouse(.mouseMoved, d.windowPoint(p)); d.click(model: p); await pause(30) }
            d.mouse(.mouseMoved, d.windowPoint(Vec2(5, 5))); await pause(30)
            d.escape(); await pause(30)
            try check(s.activeTool?.commandID == .wall, "the first Esc left the Wall tool")
            try check(s.model.elements(.walls).count == walls + 1, "the chain did not keep its one wall")
            d.escape(); await pause(30)
            try check(s.activeTool == nil, "the second Esc did not return to Modify")
            guard let wall = s.model.elements(.walls).last?.id else { throw QAError("no wall") }
            s.session.selection.select([wall])
            d.escape(); await pause(30)
            try check(s.session.selection.isEmpty, "Esc did not clear the selection")
            d.key("\u{F702}", keyCode: 123, flags: [.option, .command]); await pause(30)
            if s.session.selection.isEmpty { CommandRouter(state: s).run(.selectPrevious) } // the menu owns ⌥⌘← when it is key
            try check(s.session.selection.ids == [wall], "Select Previous did not restore the wall")
            s.session.delete([wall])
            return "chain → tool → selection, restored with Select Previous"
        }

        await step("Keys: context-menu Cancel behaves like Esc; the drawing menu has Snap Overrides") {
            reset(); focusCanvas()
            d.type("WA")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(2, 6))); d.click(model: Vec2(2, 6)); await pause(30)
            guard let canvas = d.canvas else { throw QAError("no canvas") }
            @MainActor func menuItem(_ title: String) -> NSMenuItem? { ContextMenuBuilder(state: s, viewID: s.activeViewID!, canvas: canvas).menu(for: nil).items.first { $0.title == title } }
            guard let snaps = menuItem("Snap Overrides")?.submenu, let mid = snaps.items.first(where: { $0.title.hasPrefix("Midpoints") }) else {
                throw QAError("the drawing menu has no Snap Overrides ▸ Midpoints")
            }
            MenuTarget.shared.perform(mid)
            try check(s.toolContext(for: s.activeViewID!).snapOverride == .only(.midpoint), "Midpoints did not set the next-pick override")
            guard let cancel = menuItem("Cancel") else { throw QAError("no Cancel item") }
            KeysMenuAction.shared.run(cancel); await pause(30)
            try check(s.activeTool?.commandID == .wall, "the first Cancel left the Wall tool")
            if let c2 = menuItem("Cancel") { KeysMenuAction.shared.run(c2) }
            try check(s.activeTool == nil, "the second Cancel did not return to Modify")
            let titles = ContextMenuBuilder(state: s, viewID: s.activeViewID!, canvas: canvas).menu(for: nil).items.map(\.title)
            for t in ["Cancel", "Recent Commands", "Select Previous", "Zoom In Region", "Zoom Out (2x)", "Zoom To Fit", "Previous Pan/Zoom", "Next Pan/Zoom", "Browsers", "Properties"] {
                try check(titles.contains(t), "the canvas menu has no “\(t)”: \(titles)")
            }
            try check(titles.contains { $0.hasPrefix("Repeat [Wall]") }, "no Repeat [Wall]: \(titles)")
            return "Cancel twice = Esc twice; Snap Overrides ▸ Midpoints set the override"
        }

        await step("Keys: Move with nothing selected lets you select, then Return continues; Return repeats in Modify") {
            reset(); focusCanvas()
            CommandRouter(state: s).run(.move)
            try check(s.keys.pendingCommand == .move && s.activeTool == nil, "Move did not wait for a selection")
            try check(RibbonContent.contextualTitle(s) == "Modify | Select", "contextual tab: \(RibbonContent.contextualTitle(s) ?? "none")")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(12, 4))); d.click(model: Vec2(12, 4)); await pause(40)
            try check(!s.session.selection.isEmpty, "clicking a wall did not select it")
            d.enter(); await pause(40)
            try check(s.activeTool?.commandID == .move, "Return did not start Move (tool: \(s.activeTool?.title ?? "none"))")
            try check(s.prompt.contains("start"), "Move prompt: \(s.prompt)")
            // The tab keeps the selection's category (a window sits in that wall in some QA models).
            let expected = "Modify | " + (RibbonContent.selectionTitle(s) ?? "?")
            try check(RibbonContent.contextualTitle(s) == expected, "while Move runs the tab reads \(RibbonContent.contextualTitle(s) ?? "none"), expected \(expected)")
            d.escape(); d.escape(); d.escape()
            // Return in Modify repeats the last command: Move again, which waits for a selection.
            d.enter(); await pause(40)
            try check(s.keys.pendingCommand == .move, "Return in Modify did not repeat Move (pending: \(s.keys.pendingCommand.map { "\($0)" } ?? "none"))")
            d.escape()
            try check(s.keys.pendingCommand == nil, "Esc did not cancel the waiting Move")
            d.type("WA"); d.escape(); d.escape()
            d.enter(); await pause(40)
            try check(s.activeTool?.commandID == .wall, "Return in Modify did not repeat Wall (tool: \(s.activeTool?.title ?? "none"))")
            d.escape(); d.escape()
            return "pre-selection → Return → Move; Return repeated Move, then Wall"
        }
    }
}
