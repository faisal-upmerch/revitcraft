import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W4-AUDIT: interaction QA for the UI audit and the Revit-feel sweep (hooked from `interaction()` with one line).
// Expects the Interaction QA project with the four walls (0,0)–(12,8) of the first step still present.
extension QAHarness {
    @MainActor static func auditInteraction(_ s: DocumentState, _ d: CanvasDriver, plan: Element) async {
        let w = d.window
        func focusCanvas() { if let c = d.canvas { w.makeFirstResponder(c) } }
        func reset() { s.cancelTool(); s.keys.pendingCommand = nil; s.session.selection.clear() }

        await step("Audit: every dialog opens, fits inside the window and closes with Escape") {
            reset()
            s.open(plan.id); await d.settle()
            let dialogs = await auditDialogs(s, plan: plan.id)
            var tooBig: [String] = [], stuck: [String] = [], never: [String] = []
            for (kind, name) in dialogs {
                s.presented = kind
                for _ in 0..<40 { if w.attachedSheet != nil { break }; await pause(50) }
                await pause(250)
                guard let sheet = w.attachedSheet else { never.append(name); s.presented = nil; await pause(150); continue }
                if sheet.frame.height > w.frame.height + 1 || sheet.frame.width > w.frame.width + 1 {
                    tooBig.append("\(name) \(Int(sheet.frame.width))×\(Int(sheet.frame.height)) in \(Int(w.frame.width))×\(Int(w.frame.height))")
                }
                // Escape as the user presses it: a key event to the sheet's first responder. A dialog that opens with a
                // text field focused (Type Properties) spends the first Escape ending that edit, as the reference tool does.
                for _ in 0..<2 where s.presented != nil {
                    if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                        sheet.sendEvent(e)
                    }
                    for _ in 0..<20 { if s.presented == nil { break }; await pause(50) }
                }
                if s.presented != nil { stuck.append(name); s.presented = nil }
                await pause(200)
            }
            s.session.selection.clear()
            try check(never.isEmpty, "never appeared: \(never.joined(separator: ", "))")
            try check(tooBig.isEmpty, "larger than the window: \(tooBig.joined(separator: "; "))")
            try check(stuck.isEmpty, "Escape did not close: \(stuck.joined(separator: ", "))")
            return "\(dialogs.count) dialogs fit and close with Escape"
        }

        await step("Revit feel: typed length while drawing a wall (listening dimension) and Space flips the side") {
            reset(); focusCanvas()
            d.canvas?.zoom(to: Rect2(min: Vec2(-4, -2), max: Vec2(16, 12))); await pause(60)
            let before = s.model.elements(.walls).count
            d.type("WA")
            guard let t = s.activeTool as? WallTool else { throw QAError("WA did not start the Wall tool") }
            d.mouse(.mouseMoved, d.windowPoint(Vec2(2, 3))); d.click(model: Vec2(2, 3)); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(9, 3))); await pause(40)
            try check(t.numericLabel == "Length", "no length is listened for after the first click (label \(t.numericLabel ?? "nil"))")
            let flipBefore = t.flipSide
            d.key(" ", keyCode: 49); await pause(40)
            try check(t.flipSide != flipBefore, "Space did not flip the wall side while drawing")
            d.key("3"); await pause(60)
            try check(w.firstResponder is NSTextView, "typing a digit did not open the listening dimension field")
            d.key("0"); d.key("0"); d.key("0"); d.enter(); await pause(120)
            d.escape(); d.escape(); d.escape()
            let walls = s.model.elements(.walls)
            try check(walls.count == before + 1, "typed 3000 + Return created \(walls.count - before) wall(s)")
            let len = walls.last.flatMap { $0.wall?.location.asSegment }.map { ($0.end - $0.start).length } ?? 0
            try check(abs(len - 3) < 0.01, "the wall is \(len) m long, expected 3 m")
            await d.verify("wall by typed length")
            return String(format: "wall of %.3f m from a typed 3000; Space flipped", len)
        }

        await step("Revit feel: window selects only enclosed elements, crossing selects touched ones; Tab cycles; two-stage Esc") {
            reset(); focusCanvas()
            d.canvas?.zoom(to: Rect2(min: Vec2(-4, -2), max: Vec2(16, 12))); await pause(60)
            // A marquee only starts from empty space (a press on an element selects and drags it, as in the reference
            // tool), so the start points are found at run time; the rectangle straddles the west wall (x = 0).
            guard let wall = s.model.elements(.walls).first(where: { abs(($0.wall?.location.midpoint.x ?? 1)) < 1e-3 }), let seg = wall.wall?.location.asSegment,
                  let c = d.canvas else { throw QAError("no west wall or canvas") }
            @MainActor func names(_ ids: [ElementID]) -> String { ids.compactMap { s.model[$0]?.category.singularName }.joined(separator: ", ") }
            @MainActor func empty(_ v: Vec2) -> Bool { c.hitCandidates(at: c.toScreen(v)).isEmpty }
            // Floors and the toposurface of earlier steps fill the plan: isolate the walls (IC) so a marquee can start.
            s.session.selection.select([wall.id]); d.type("IC"); await d.settle()
            defer { d.type("HR") }
            s.session.selection.clear()
            let ys = stride(from: min(seg.start.y, seg.end.y) + 0.8, to: max(seg.start.y, seg.end.y) - 0.8, by: 0.9)
            guard let y = ys.first(where: { empty(Vec2(-1.5, $0)) && empty(Vec2(1.5, $0 + 0.6)) }) else { throw QAError("no empty space beside the west wall") }
            // Left→right: the wall is not enclosed, so it must not be selected.
            d.drag(from: d.windowPoint(Vec2(-1.5, y)), to: d.windowPoint(Vec2(1.5, y + 0.6))); await pause(60)
            let windowed = s.session.selection.ids
            d.escape(); d.escape()
            // Right→left over the same area crosses the wall, so it is.
            d.drag(from: d.windowPoint(Vec2(1.5, y + 0.6)), to: d.windowPoint(Vec2(-1.5, y))); await pause(60)
            let crossed = s.session.selection.ids
            try check(!windowed.contains(wall.id) && crossed.contains(wall.id),
                      "window selected \(windowed.count) [\(names(windowed))], crossing selected \(crossed.count) [\(names(crossed))]; wall \(wall.id) \(seg), y \(y)")
            // With no tool running, Esc clears the selection.
            d.escape(); await pause(30)
            try check(s.session.selection.isEmpty, "Esc did not clear the selection")
            // Tab cycles the pre-selection over a corner where two walls meet.
            d.mouse(.mouseMoved, d.windowPoint(Vec2(0.02, 0.02))); await pause(60)
            let first = s.session.selection.preselection
            d.key("\t", keyCode: 48); await pause(40)
            let second = s.session.selection.preselection
            try check(first != nil && second != nil && first != second, "Tab did not cycle (\(String(describing: first)) → \(String(describing: second)))")
            d.escape(); d.escape()
            await d.verify("after selection checks")
            return "window \(windowed.count), crossing \(crossed.count), Tab cycled"
        }

        await step("Revit feel: door Space flips facing during placement; the status prompt says so") {
            reset(); focusCanvas()
            d.type("DR")
            guard let t = s.activeTool as? InsertTool else { throw QAError("DR did not start the Door tool") }
            try check(t.prompt.contains("Space"), "the door prompt does not mention Space: \(t.prompt)")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(5, 0))); await pause(60)
            let before = t.isFacingFlipped
            d.key(" ", keyCode: 49); await pause(40)
            try check(t.isFacingFlipped != before, "Space did not flip the door facing")
            let hand = t.isHandFlipped
            d.key(" ", keyCode: 49, flags: .shift); await pause(40)
            try check(t.isHandFlipped != hand, "Shift+Space did not flip the door hand")
            d.escape(); d.escape()
            try check(s.activeTool == nil, "two Escapes did not leave the Door tool")
            return "facing and hand flipped from the keyboard"
        }
    }
}
