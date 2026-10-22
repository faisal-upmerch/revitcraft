import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

/// Interaction QA (`--qa interact`): drives the real 2D canvas with synthesized mouse, scroll and keyboard events sent
/// through the window (so hit testing, responder routing and tools run exactly as for a user) and, after every action,
/// verifies the canvas:
/// - the display list on screen is current (built from the current model revision) and has the same elements as a
///   fresh build of the view;
/// - every element the display list says is on screen really has ink on screen: pixels along its strokes differ from
///   the canvas background (catches culling, stale bounds, masking and redraw bugs where things "vanish").
extension QAHarness {
    @MainActor
    final class CanvasDriver {
        let s: DocumentState
        var window: NSWindow { s.window! }
        var failures: [String] = []
        var checks = 0
        let shotDir: URL

        init(state: DocumentState, shotDir: URL) {
            s = state
            self.shotDir = shotDir
            try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        }

        var viewID: ElementID { s.activeViewID! }
        var canvas: Canvas2DView? { s.canvases[viewID] as? Canvas2DView }

        // MARK: Events

        /// A model point's window position. The floating docks cover the canvas's edges (W4-SHELL): a point behind one
        /// would be clicked on the dock instead, so the canvas is panned first to bring it into the visible region.
        func windowPoint(_ v: Vec2) -> NSPoint {
            guard let c = canvas else { return .zero }
            var p = c.toScreen(v)
            // W4-WIRE: the shell's insets from the document state are current even before AppKit has relaid the safe area,
            // and the row a tool's Options pill will take is kept clear even before the tool starts, so starting a tool
            // never pans the framing between a hover and its click.
            let optionsRow = s.activeTool == nil ? ShellMetrics.arcus.optionsHeight + ShellMetrics.arcus.margin : 0
            let shell = NSRect(x: s.docks.leadingInset, y: s.docks.bottomInset, width: c.bounds.width - s.docks.leadingInset - s.docks.trailingInset,
                               height: c.bounds.height - s.docks.topInset - s.docks.bottomInset - optionsRow)
            let safe = c.safeAreaRect.intersection(shell).insetBy(dx: 24, dy: 24)
            if !safe.isEmpty, !safe.contains(p) {
                let target = NSPoint(x: min(max(p.x, safe.minX), safe.maxX), y: min(max(p.y, safe.minY), safe.maxY))
                c.center = c.center + Vec2((p.x - target.x) / c.zoom, (p.y - target.y) / c.zoom)
                c.needsDisplay = true
                p = c.toScreen(v)
            }
            return c.convert(p, to: nil)
        }
        func windowPoint(canvasFraction fx: Double, _ fy: Double) -> NSPoint {
            guard let c = canvas else { return .zero }
            return c.convert(NSPoint(x: c.bounds.width * fx, y: c.bounds.height * fy), to: nil)
        }

        func mouse(_ type: NSEvent.EventType, _ p: NSPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
            guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
                                             pressure: type == .leftMouseUp ? 0 : 1) else { return }
            if type == .mouseMoved {
                // Tracking-area mouse-moved events come from the window server; deliver to the view under the pointer.
                if let v = window.contentView?.hitTest(window.contentView!.convert(p, from: nil)) { v.mouseMoved(with: e) }
            } else {
                window.sendEvent(e)
            }
        }
        func click(_ p: NSPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
            mouse(.mouseMoved, p)
            mouse(.leftMouseDown, p, clicks: clicks, flags: flags)
            mouse(.leftMouseUp, p, clicks: clicks, flags: flags)
        }
        func click(model v: Vec2, flags: NSEvent.ModifierFlags = []) { click(windowPoint(v), flags: flags) }
        func drag(from a: NSPoint, to b: NSPoint, steps: Int = 8, flags: NSEvent.ModifierFlags = []) {
            mouse(.mouseMoved, a)
            mouse(.leftMouseDown, a, flags: flags)
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                mouse(.leftMouseDragged, NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags)
            }
            mouse(.leftMouseUp, b, flags: flags)
        }
        func hover(_ path: [NSPoint]) { for p in path { mouse(.mouseMoved, p) } }

        /// Scroll at a window point. `continuous` = trackpad-style precise deltas (pans); otherwise a mouse wheel (zooms).
        func scroll(at p: NSPoint, dx: Int32 = 0, dy: Int32, continuous: Bool, flags: CGEventFlags = []) {
            let screen = window.convertPoint(toScreen: p)
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
            cg.location = CGPoint(x: screen.x, y: top - screen.y)
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            cg.flags = flags
            guard let e = NSEvent(cgEvent: cg) else { return }
            // An event made from a CGEvent has no window, so its location would be misread by `sendEvent`: deliver it
            // to the view under the point, as AppKit's dispatch does.
            let target = window.contentView.flatMap { $0.hitTest($0.convert(p, from: nil)) } ?? window.contentView
            target?.scrollWheel(with: e)
        }

        func key(_ chars: String, keyCode: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode) else { return }
            if flags.contains(.command) { NSApp.sendEvent(e) } else { window.sendEvent(e) }
        }
        func type(_ letters: String) { for ch in letters { key(String(ch).lowercased(), keyCode: keyCode(ch)) } }
        func escape() { key("\u{1b}", keyCode: 53) }
        func enter() { key("\r", keyCode: 36) }
        func delete() { key("\u{7f}", keyCode: 51) }
        /// Menu actions go to the document window's first responder and up its chain, as the Edit menu sends them (the
        /// menu itself only reaches the key window, which may be another app's while QA runs in the background).
        func undo() { perform("undo:") }
        func redo() { perform("redo:") }
        func perform(_ name: String) {
            var r: NSResponder? = window.firstResponder
            let sel = NSSelectorFromString(name)
            while let cur = r {
                if cur.responds(to: sel) { cur.perform(sel, with: nil); return }
                r = cur.nextResponder
            }
            if window.responds(to: sel) { window.perform(sel, with: nil); return }
            // As AppKit's action dispatch does: after the window come its controller and its document.
            if let wc = window.windowController, wc.responds(to: sel) { wc.perform(sel, with: nil); return }
            if let d = window.windowController?.document as? NSDocument, d.responds(to: sel) { d.perform(sel, with: nil) }
        }
        private func keyCode(_ c: Character) -> UInt16 {
            let map: [Character: UInt16] = ["A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13,
                                            "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40,
                                            "N": 45, "M": 46]
            return map[Character(c.uppercased())] ?? 0
        }

        // MARK: Verification

        /// Posts an event through the application's event queue and waits for it to be dispatched, so AppKit runs
        /// its end-of-event processing (which closes the automatic undo group) as it does after real input.
        func flushEvents() async {
            await QAHarness.dispatchEvent()
        }

        func settle() async {
            await flushEvents()
            for _ in 0..<400 {
                if !s.graphics.isBuilding, let g = s.graphics.graphics(viewID), g.modelRevision == s.model.revision { break }
                await pause(25)
            }
            await pause(120)
        }

        /// Verifies the active canvas; records failures with a screenshot. Returns true when the canvas is correct.
        @discardableResult
        func verify(_ label: String) async -> Bool {
            await settle()
            checks += 1
            guard let c = canvas else { failures.append("\(label): no canvas for active view"); return false }
            c.needsDisplay = true
            c.displayIfNeeded()
            guard let g = c.graphics else { failures.append("\(label): canvas has no display list"); return false }
            var problems: [String] = []
            // 0. Every user action is its own undo step: no undo group may stay open once the event loop is idle.
            if s.session.undoManager.groupingLevel > 0 {
                problems.append("an undo group is still open (level \(s.session.undoManager.groupingLevel), last action “\(s.session.undoManager.undoActionName)”)")
            }
            // 1. Current.
            if g.modelRevision != s.model.revision { problems.append("display list is stale (built for revision \(g.modelRevision), model is \(s.model.revision))") }
            // 2. Same elements as a fresh build.
            if let v = s.model[viewID] {
                let fresh: ViewGraphics
                if v.sheet != nil { fresh = SheetGraphicsBuilder(model: s.model, sheet: v).build() }
                else { fresh = ViewGraphicsBuilder(model: s.model, view: v, temporary: s.session.temporaryVisibility[viewID] ?? TemporaryVisibility()).build() }
                let shown = Set(g.items.compactMap(\.elementID)), expected = Set(fresh.items.compactMap(\.elementID))
                let missing = expected.subtracting(shown), extra = shown.subtracting(expected)
                if !missing.isEmpty { problems.append("\(missing.count) element(s) missing from the display list: \(describe(missing))") }
                if !extra.isEmpty { problems.append("\(extra.count) deleted/hidden element(s) still in the display list: \(describe(extra))") }
            }
            // 3. Ink on screen for every element the display list draws inside the visible area.
            let vanished = inkCheck(c, g)
            if !vanished.isEmpty { problems.append("\(vanished.count) element(s) not drawn although in view: \(vanished.prefix(8).joined(separator: "; "))") }
            if problems.isEmpty { return true }
            let name = String(format: "%02d-%@", failures.count + 1, label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_"))
            saveCanvas(c, name)
            failures.append("\(label): " + problems.joined(separator: " | "))
            return false
        }

        func describe(_ ids: Set<ElementID>) -> String {
            ids.sorted().prefix(6).map { id in s.model[id].map { "\($0.category.singularName) \(id)" } ?? "\(id)" }.joined(separator: ", ")
        }

        func saveCanvas(_ c: NSView, _ name: String) {
            guard let rep = (c as? Canvas2DView)?.renderedSnapshot() ?? c.bitmapImageRepForCachingDisplay(in: c.bounds) else { return }
            if !(c is Canvas2DView) { c.cacheDisplay(in: c.bounds, to: rep) }
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: shotDir.appendingPathComponent(name + ".png")) }
        }

        /// Samples each drawn element's strokes on screen and returns elements with (almost) no ink where they should be.
        func inkCheck(_ c: Canvas2DView, _ g: ViewGraphics) -> [String] {
            // The composited frame (GPU display list included), not just the AppKit layer tree.
            guard let rep = c.renderedSnapshot() else { return [] }
            let sx = Double(rep.pixelsWide) / Double(c.bounds.width), sy = Double(rep.pixelsHigh) / Double(c.bounds.height)
            // Background: the most common colour of a coarse sample grid.
            var counts: [UInt32: Int] = [:]
            func px(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
                return (Int(col.redComponent * 255), Int(col.greenComponent * 255), Int(col.blueComponent * 255))
            }
            for i in stride(from: 5, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 40)) {
                for j in stride(from: 5, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 40)) {
                    if let (r, gg, b) = px(i, j) { counts[UInt32(r << 16 | gg << 8 | b), default: 0] += 1 }
                }
            }
            let bgKey = counts.max { $0.value < $1.value }?.key ?? 0xFFFFFF
            let bg = (Int(bgKey >> 16 & 0xFF), Int(bgKey >> 8 & 0xFF), Int(bgKey & 0xFF))
            func inked(_ p: NSPoint) -> Bool {
                let x = Int(Double(p.x) * sx), y = Int((Double(c.bounds.height) - Double(p.y)) * sy)
                for dx in -2...2 { for dy in -2...2 {
                    if let (r, gg, b) = px(x + dx, y + dy), abs(r - bg.0) + abs(gg - bg.1) + abs(b - bg.2) > 45 { return true }
                } }
                return false
            }
            let visible = c.bounds.insetBy(dx: 12, dy: 12)
            var out: [String] = []
            let hidden = Set<ElementID>()
            for item in g.items {
                guard let id = item.elementID, !hidden.contains(id), [.model, .cut, .annotation].contains(item.layer) else { continue }
                var samples = 0, hits = 0
                for p in item.primitives {
                    guard case .polyline(let pts, let closed, let st) = p, pts.count >= 2, !st.halftone else { continue }
                    let n = closed ? pts.count : pts.count - 1
                    for i in 0..<n {
                        let a = c.toScreen(pts[i]), b = c.toScreen(pts[(i + 1) % pts.count])
                        let len = hypot(b.x - a.x, b.y - a.y)
                        guard len >= 6 else { continue }
                        let k = min(12, Int(len / 6))
                        for j in 1..<k {
                            let t = Double(j) / Double(k)
                            let q = NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                            guard visible.contains(q) else { continue }
                            samples += 1
                            if inked(q) { hits += 1 }
                        }
                    }
                }
                // Elements partly covered by masks (tags, text) keep most of their ink; a vanished one has none.
                if samples >= 6 && Double(hits) / Double(samples) < 0.2 {
                    out.append("\(s.model[id]?.category.singularName ?? "?") \(id) (\(hits)/\(samples) samples inked)")
                }
            }
            return out
        }
    }

    // MARK: Scenario

    static func interaction() async {
        let appDelegate = AppDelegate.shared!
        appDelegate.newProject(template: .architectural, units: .metric, name: "Interaction QA")
        guard let s = await activeState(), let w = s.window else { results.append(StepResult(name: "Interaction QA", passed: false, detail: "no document", seconds: 0)); return }
        w.setContentSize(NSSize(width: 1500, height: 940))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let d = CanvasDriver(state: s, shotDir: outDir.appendingPathComponent("interact", isDirectory: true))
        let l1 = view(s, kind: .floorPlan, level: "Level 1")!
        s.open(l1.id)
        await d.settle()

        func snapshot() -> String {
            let sel = s.session.selection.ids.compactMap { s.model[$0].map { "\($0.category.singularName) \($0.id)" } }
            let walls = s.model.elements(.walls).compactMap { $0.wall?.location.asSegment }.map { "(\(String(format: "%.2f,%.2f", $0.start.x, $0.start.y))→\(String(format: "%.2f,%.2f", $0.end.x, $0.end.y)))" }
            let hitView = (d.canvas?.window?.contentView?.hitTest(d.windowPoint(canvasFraction: 0.1, 0.1))).map { "\(type(of: $0))" } ?? "-"
            return " [state: canvas mouseDowns \(d.canvas?.mouseDownCount ?? -1), zoomRegionArmed \(d.canvas?.zoomRegionArmed ?? false), hit at 10%: \(hitView); selection \(sel); tool \(s.activeTool.map { "\($0.title): \($0.prompt)" } ?? "none"); last error \(s.session.lastError.map { "\($0)" } ?? "-"); message \(s.message ?? "-"); walls \(walls)]"
        }
        func run(_ name: String, _ body: () async throws -> String) async {
            let before = d.failures.count
            await step("Canvas: " + name) {
                let detail: String
                do { detail = try await body() } catch { throw QAError("\(error)" + snapshot()) }
                let new = d.failures.dropFirst(before)
                try check(new.isEmpty, new.joined(separator: " || "))
                return detail
            }
        }

        await run("initial plan") { await d.verify("initial plan"); return "ok" }

        await run("draw walls with the Wall tool (typed alias WA, clicks, Esc)") {
            if let c = d.canvas { w.makeFirstResponder(c) }
            d.type("WA")
            try check(s.activeTool != nil, "WA did not start a tool")
            for p in [Vec2(0, 0), Vec2(12, 0), Vec2(12, 8), Vec2(0, 8), Vec2(0, 0)] {
                d.mouse(.mouseMoved, d.windowPoint(p)); await pause(20)
                d.click(model: p); await pause(40)
                await d.verify("wall chain at \(p)")
            }
            d.escape(); d.escape()
            let walls = s.model.elements(.walls)
            try check(walls.count == 4, "expected 4 walls, got \(walls.count)")
            await d.verify("after drawing walls")
            return "4 walls drawn by mouse"
        }
        await run("zoom to fit, hover and preselect") {
            CommandRouter(state: s).run(.zoomExtents)
            await d.verify("zoom to fit")
            try check(w.firstResponder?.undoManager === s.session.undoManager, "the window's undo manager is not the document session's")
            d.type("ZR")
            d.drag(from: d.windowPoint(Vec2(-3, -3)), to: d.windowPoint(Vec2(15, 11)))
            await d.verify("zoomed to the building")
            d.hover((0...20).map { i in d.windowPoint(Vec2(Double(i) * 0.6, 0.02)) })
            await d.verify("hover along wall")
            d.hover([d.windowPoint(canvasFraction: 0.02, 0.02)])
            return "ok"
        }
        let south = { s.model.elements(.walls).first { abs(($0.wall?.location.midpoint.y ?? 1)) < 1e-3 } }
        await run("click-select and drag-move a wall, then undo/redo") {
            guard let wall = south() else { throw QAError("no south wall") }
            d.click(model: Vec2(6, 0))
            await d.verify("selected wall")
            try check(s.session.selection.ids == [wall.id], "selection is \(s.session.selection.ids)")
            let wallsBefore = s.model.elements(.walls).map { $0.wall!.location.midpoint }
            var snapInfo = ""
            if let c = d.canvas {
                for v in [Vec2(6, 0), Vec2(6, -1.5)] {
                    let raw = c.toView(c.convert(d.windowPoint(v), from: nil))
                    let (pt, sn) = c.toolContext.snap(raw)
                    snapInfo += "\(v) raw \(raw) → \(pt) [\(sn?.kind.rawValue ?? "none")]; "
                }
                snapInfo += "zoom \(c.zoom), pixel \(c.toolContext.pixel)"
            }
            d.drag(from: d.windowPoint(Vec2(6, 0)), to: d.windowPoint(Vec2(6, -1.5)))
            await d.verify("after drag-move")
            let y1 = s.model[wall.id]?.wall?.location.midpoint.y ?? 0
            let wallsAfter = s.model.elements(.walls).map { $0.wall!.location.midpoint }
            func desc(_ e: Element?) -> String {
                guard let e else { return "nil" }
                if let w = e.wall { return "\(w.location.midpoint)" }
                return e.category.rawValue
            }
            let rec = (s.session.lastChange?.record.changes ?? []).map { c in "\(c.id): \(desc(c.before))→\(desc(c.after))" }.joined(separator: ", ")
            try check(abs(y1 + 1.5) < 0.3, "wall midpoint y after drag = \(y1); walls \(wallsBefore) → \(wallsAfter); undo “\(s.session.undoManager.undoActionName)”; record: \(rec); snaps: \(snapInfo)")
            await d.flushEvents()
            let um = s.session.undoManager
            let beforeUndo = "undo “\(um.undoActionName)”, grouping level \(um.groupingLevel), walls \(s.model.elements(.walls).count)"
            d.undo(); await d.verify("after undo move")
            try check(abs(s.model[wall.id]?.wall?.location.midpoint.y ?? 9) < 1e-6,
                      "undo did not restore the wall (before: \(beforeUndo); after: undo “\(um.undoActionName)”, redo “\(um.redoActionName)”, walls \(s.model.elements(.walls).count))")
            d.redo(); await d.verify("after redo move")
            d.undo(); await d.verify("after second undo")
            return String(format: "moved to y = %.2f, undo/redo ok", y1)
        }
        await run("pan with trackpad scroll and zoom with wheel") {
            let mid = d.windowPoint(canvasFraction: 0.5, 0.5)
            for _ in 0..<6 { d.scroll(at: mid, dx: 25, dy: -18, continuous: true); await pause(15) }
            await d.verify("after pan")
            for _ in 0..<5 { d.scroll(at: d.windowPoint(Vec2(12, 8)), dy: 3, continuous: false); await pause(15) }
            await d.verify("after zoom in on corner")
            for _ in 0..<9 { d.scroll(at: mid, dy: -3, continuous: false); await pause(15) }
            await d.verify("after zoom out")
            CommandRouter(state: s).run(.zoomExtents)
            await d.verify("zoom to fit again")
            d.type("ZR"); d.drag(from: d.windowPoint(Vec2(-3, -3)), to: d.windowPoint(Vec2(15, 11)))
            await d.verify("zoomed back to the building")
            return "ok"
        }
        await run("window select, delete, undo") {
            d.drag(from: d.windowPoint(Vec2(-2, -2)), to: d.windowPoint(Vec2(14, 10)))
            await d.verify("after window select")
            try check(s.session.selection.ids.count >= 4, "window selected \(s.session.selection.ids.count)")
            let selected = s.session.selection.ids.compactMap { s.model[$0]?.category.singularName }
            d.delete(); await d.verify("after delete")
            try check(s.model.elements(.walls).isEmpty, "walls not deleted (selection \(selected))")
            let undoName = s.session.undoManager.undoActionName
            d.undo(); await d.verify("after undo delete")
            try check(s.model.elements(.walls).count == 4, "undo “\(undoName)” restored \(s.model.elements(.walls).count) walls; selection was \(selected); now undo “\(s.session.undoManager.undoActionName)”")
            d.escape(); d.escape()
            return "ok"
        }
        await run("place a door and a window with the mouse") {
            d.type("DR")
            try check(s.activeTool != nil, "DR did not start the door tool")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(4, 0))); await pause(30)
            await d.verify("door preview")
            d.click(model: Vec2(4, 0)); await pause(40)
            d.escape(); d.escape()
            d.type("WN")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(12, 4))); await pause(30)
            d.click(model: Vec2(12, 4)); await pause(40)
            d.escape(); d.escape()
            await d.verify("after door and window")
            try check(s.model.elements(.doors).count == 1 && s.model.elements(.windows).count == 1,
                      "doors \(s.model.elements(.doors).count), windows \(s.model.elements(.windows).count)")
            return "ok"
        }
        await libraryInteraction(s, d) // W2-LIB: component library
        await propertiesInteraction(s, d) // BL-PROPS: palette subject
        await keysInteraction(s, d) // BL-KEYS: focus, aliases, Esc, Cancel, pre-selection, Repeat
        await canvasFeedbackInteraction(s, d) // BL-CANVAS: sketch halftone, floor highlight
        await graphicsControlInteraction(s, d) // BL-VG: V/G, filters, templates, object styles, warnings
        await shellInteraction(s, d) // W4-SHELL: floating sidebar input containment, ⌥⌘S, resize
        await hatchInteraction(s, d) // W4-HATCH: cut patterns at coarse/medium/fine, a section, and the Fill Patterns dialog
        await run("room, dimension, text") {
            d.type("RM"); d.click(model: Vec2(6, 4)); await pause(40); d.escape(); d.escape()
            await d.verify("after room")
            d.type("DI")
            d.click(model: Vec2(0, 4)); d.click(model: Vec2(12, 4)); d.click(model: Vec2(6, 6)); await pause(40)
            d.escape(); d.escape()
            await d.verify("after dimension")
            try check(s.model.elements(.rooms).count == 1, "rooms \(s.model.elements(.rooms).count)")
            try check(s.model.elements(.dimensions).count == 1, "dimensions \(s.model.elements(.dimensions).count)")
            return "ok"
        }
        await run("switch views and come back") {
            let l2 = view(s, kind: .floorPlan, level: "Level 2")!
            s.open(l2.id); await d.verify("Level 2 plan")
            s.open(l1.id); await d.verify("back to Level 1")
            if let v3 = s.model.views.first(where: { $0.view?.kind == .threeD }) { s.open(v3.id); await pause(600) }
            s.open(l1.id); await d.verify("back from 3D")
            if let south = view(s, kind: .elevation, name: "South") { s.open(south.id); await d.verify("south elevation"); s.open(l1.id) }
            await d.verify("back from elevation")
            return "ok"
        }
        await run("resize window and toggle panels") {
            w.setContentSize(NSSize(width: 1000, height: 660)); await d.verify("small window")
            s.showNavigator.toggle(); s.onWorkspaceChange?(); await pause(400); await d.verify("navigator toggled")
            s.showNavigator.toggle(); s.onWorkspaceChange?(); await pause(400)
            w.setContentSize(NSSize(width: 1600, height: 1000)); await d.verify("large window")
            return "ok"
        }
        await run("temporary hide / isolate and reset") {
            d.click(model: Vec2(6, 8))
            d.type("HH"); await d.verify("temporary hide")
            d.type("HR"); await d.verify("reset temporary")
            d.click(model: Vec2(6, 8))
            d.type("HI"); await d.verify("temporary isolate")
            d.type("HR"); await d.verify("reset after isolate")
            d.escape(); d.escape()
            return "ok"
        }
        // Every drawing/placement tool driven by alias + clicks; each must create its element and leave the canvas intact.
        func toolRun(_ name: String, _ alias: String, _ clicks: [Vec2], finish: Bool = false, expect: [ArcusDomain.Category] = [], in viewID: ElementID? = nil,
                     command: CommandID? = nil) async {
            await run(name) {
                if let v = viewID { s.open(v); await d.settle() }
                // Tools may ask a question on completion (e.g. attach the walls below a new roof): answer yes, as a user would.
                let toolCtx = s.toolContext(for: s.activeViewID ?? l1.id)
                let originalConfirm = toolCtx.requestConfirmation
                var questions: [String] = []
                toolCtx.requestConfirmation = { message, _, done in questions.append(message); done(true) }
                defer { toolCtx.requestConfirmation = originalConfirm }
                let before = Dictionary(uniqueKeysWithValues: expect.map { ($0, s.model.elements($0).count) })
                let total = s.model.count
                if let c = d.canvas { w.makeFirstResponder(c) }
                if let command { CommandRouter(state: s).run(command) } else { d.type(alias) }
                try check(s.activeTool != nil, "\(alias.isEmpty ? "\(command!)" : alias) did not start a tool")
                for p in clicks {
                    d.mouse(.mouseMoved, d.windowPoint(p)); await pause(15)
                    d.click(model: p); await pause(30)
                }
                await d.verify("\(name): during tool")
                if finish { d.enter(); await pause(60) }
                d.escape(); d.escape()
                await d.verify("\(name): after tool")
                for c in expect {
                    try check(s.model.elements(c).count > before[c]!, "\(c.rawValue): \(before[c]!) → \(s.model.elements(c).count) (tool prompt: \(s.activeTool?.prompt ?? "-"); last error: \(s.session.lastError.map { "\($0)" } ?? "-"))")
                }
                if expect.isEmpty { try check(s.model.count > total, "nothing was created") }
                if let v = viewID, v != l1.id { s.open(l1.id); await d.settle() }
                return "\(s.model.count - total) element(s) created" + (questions.isEmpty ? "" : "; answered: " + questions.joined(separator: " | "))
            }
        }
        let l2 = view(s, kind: .floorPlan, level: "Level 2")!
        let rcp1 = s.model.views.first { $0.view?.kind == .ceilingPlan && $0.levelID == l1.levelID }
        await toolRun("grid", "GR", [Vec2(-3, -3), Vec2(-3, 11)], expect: [.grids])
        await toolRun("model line", "LI", [Vec2(1, 1), Vec2(3, 1)])
        await run("snapping: new wall and model line snap to existing geometry") {
            guard let c = d.canvas else { throw QAError("no canvas") }
            w.makeFirstResponder(c)
            // Earlier steps must leave no furniture behind (its plan lines would offer snaps); say so if they did.
            let stray = s.model.elements(.furniture).map(\.id)
            if !stray.isEmpty { d.failures.append("snapping: \(stray.count) stray furniture element(s) before the step (top of the undo stack: \(s.session.undoManager.undoActionName))"); s.session.delete(stray) }
            // A known framing: earlier steps leave the plan panned and zoomed anywhere, and snap reach is in screen points.
            c.zoom(to: Rect2(min: Vec2(-3, -3), max: Vec2(18, 13))); await pause(60)
            let px = 1 / c.zoom                       // model units per screen point
            let off = Vec2(2.5 * px, -2 * px)         // about 3 pt from the target
            @MainActor func pick(_ pts: [Vec2]) async {
                for p in pts { d.mouse(.mouseMoved, d.windowPoint(p)); await pause(20); d.click(model: p); await pause(40) }
                d.escape(); d.escape(); await pause(80)
            }
            @MainActor func newest(_ cat: ArcusDomain.Category, notIn before: Set<ElementID>) -> Segment2? {
                for e in s.model.elements(cat) where !before.contains(e.id) {
                    if case .line(let seg)? = e.wall?.location { return seg }
                    if case .line(let seg)? = e.modelLine?.curve { return seg }
                }
                return nil
            }
            // Wall starting near the north-east corner (wall location lines meet at (12, 8)).
            let walls = Set(s.model.elements(.walls).map(\.id))
            d.type("WA"); await pause(40)
            // What the user sees: the snap marker must be drawn at the corner while hovering, before any click.
            d.mouse(.mouseMoved, d.windowPoint(Vec2(5, 5))); await pause(60)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(12, 8) + off)); await pause(120)
            // A visible point of the corner (face or layer corner) is shown; the wall itself then joins at the location corner.
            let cornerHalf = (s.model.elements(.walls).first.map { WallGeometry.assembly(for: $0, s.model).totalThickness } ?? 0.2) / 2
            try check(c.lastDrawnSnap.map { $0.distance(to: Vec2(12, 8)) <= cornerHalf * 1.5 } == true,
                      "snap marker on screen is at \(c.lastDrawnSnap.map { "\($0)" } ?? "nothing"), expected a point of the corner (12, 8)")
            await pick([Vec2(12, 8) + off, Vec2(16, 11)])
            guard let ws = newest(.walls, notIn: walls) else { throw QAError("no wall was created") }
            try check(ws.start.distance(to: Vec2(12, 8)) < 1e-6, "wall start \(ws.start) did not snap to the corner (12, 8)")
            // Model line starting just off the new wall's visible face (not its hidden centre line) lands on the face.
            let lines = Set(s.model.elements(.detailLines).map(\.id))
            let half = WallGeometry.assembly(for: s.model.elements(.walls).first { !walls.contains($0.id) }!, s.model).totalThickness / 2
            let u = (ws.end - ws.start).normalized, n = Vec2(-u.y, u.x)
            let facePoint = ws.start + u * (ws.length * 0.4) + n * half
            d.type("LI"); await pause(40)
            await pick([facePoint + n * (2 * px), facePoint + n * 3 + u * 0.7])
            guard let ls = newest(.detailLines, notIn: lines) else { throw QAError("no model line was created") }
            let faceDistance = abs((ls.start - ws.start).dot(n))
            try check(abs(faceDistance - half) < 1e-6, "model line start \(ls.start) is \(faceDistance) from the wall centre line; the face is at \(half)")
            // Parallel: start in open space, hover the wall face to acquire it, come back nearly parallel: the line is parallel.
            let lines2 = Set(s.model.elements(.detailLines).map(\.id))
            // Open space: away from every wall face's extension (the default wall type's thickness changes with the template),
            // and far enough along (5 m) that the nearest angle increments (30°, 45°) are out of reach of the wall's 36.9°.
            let p0 = Vec2(2, 2)
            d.type("LI"); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(p0)); await pause(20)
            let rawP0 = c.toView(c.convert(d.windowPoint(p0), from: nil))
            let p0snap = c.toolContext.snap(rawP0)
            let p0desc = "raw \(rawP0) → \(p0snap.0) \(p0snap.1.map { "\($0.kind.rawValue) \($0.description)" } ?? "free"); px \(c.toolContext.pixel)"
            d.click(model: p0); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(ws.start + u * (ws.length * 0.75) + n * half)); await pause(40)
            let target = p0 + u * 5 + n * (3 * px)
            d.mouse(.mouseMoved, d.windowPoint(target)); await pause(40)
            let tsnap = c.toolContext.snap(c.toView(c.convert(d.windowPoint(target), from: nil)), from: p0).1
            let tdesc = tsnap.map { "\($0.kind.rawValue) on \($0.elementIDs.compactMap { s.model[$0].map { "\($0.category.rawValue) \($0.id)" } })" } ?? "none"
            let acquired = c.toolContext.acquiredLines.count
            let hoverSnap = s.snapDescription ?? "none"
            d.click(model: target); await pause(40)
            let clickSnap = s.snapDescription ?? "none"
            d.escape(); d.escape(); await pause(80)
            guard let pl = newest(.detailLines, notIn: lines2) else { throw QAError("no parallel line was created") }
            let cross = abs((pl.end - pl.start).normalized.x * u.y - (pl.end - pl.start).normalized.y * u.x)
            try check(cross < 1e-9, "the second line is not parallel to the wall (sin angle \(cross)); snap at the target: \(tdesc); acquired lines \(acquired); hover snap \(hoverSnap); after click \(clickSnap); line \(pl.start)→\(pl.end); target \(target); units \(s.model.units.system); start probe: \(p0desc)")
            d.undo(); await pause(40)
            d.undo(); await pause(40); d.undo(); await d.verify("after undoing the snap test")
            // Aiming at the visible outer corner (a face corner, not the location lines' meeting point) must still join.
            let walls2 = Set(s.model.elements(.walls).map(\.id))
            let rectHalf = (s.model.elements(.walls).first.map { WallGeometry.assembly(for: $0, s.model).totalThickness } ?? 0.2) / 2
            d.type("WA"); await pause(40)
            await pick([Vec2(12 + rectHalf, 8 + rectHalf) + off, Vec2(12 + rectHalf + 5, 8 + rectHalf)])
            guard let fw = s.model.elements(.walls).first(where: { !walls2.contains($0.id) }) else { throw QAError("no wall from the outer corner") }
            let j = WallGeometry.endJoin(fw, atEnd: false, s.model)
            try check(j.kind != .free, "a wall started at the outer corner \(fw.wall!.location.start) is not joined (\(j.kind))")
            d.undo(); await d.verify("after undoing the corner-join test")
            // A wall drawn beside a parallel one stops level with its end (vertical and alignment).
            let walls3 = Set(s.model.elements(.walls).map(\.id))
            d.type("WA"); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(4, 2))); await pause(20); d.click(model: Vec2(4, 2)); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(4, 5))); await pause(40)
            let endProbe = c.toolContext.snap(c.toView(c.convert(d.windowPoint(Vec2(4, 5)), from: nil)), from: Vec2(4, 2))
            let endDesc = "\(endProbe.0) \(endProbe.1.map { "\($0.kind.rawValue): \($0.description)" } ?? "free"); override \(String(describing: c.toolContext.snapOverride))"
            d.click(model: Vec2(4, 5)); await pause(40)
            d.escape(); d.escape(); await pause(80)
            d.type("WA"); await pause(40)
            await pick([Vec2(7, 2), Vec2(7, 5) + Vec2(2 * px, 3 * px)])
            let beside = s.model.elements(.walls).filter { !walls3.contains($0.id) }.compactMap { e -> Segment2? in
                if case .line(let seg)? = e.wall?.location, seg.start.x > 6 { return seg } else { return nil }
            }.first
            try check(beside.map { $0.end.distance(to: Vec2(7, 5)) < 1e-6 } == true,
                      "the wall beside a parallel one ends at \(beside.map { "\($0.end)" } ?? "nothing"), expected level with its end (7, 5); first wall end probe: \(endDesc)")
            d.undo(); await pause(40); d.undo(); await d.verify("after undoing the alignment test")
            // Pictures of the drawing aids (for visual review): a rubber band on a guide crossing, a door preview with
            // its spacing, and a wall mid-drag with live dimensions.
            d.type("LI"); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(2, 10))); await pause(20); d.click(model: Vec2(2, 10)); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(12, 10.02))); await pause(80)
            d.saveCanvas(c, "aid-rubber-band-on-guides")
            d.escape(); d.escape(); await pause(40)
            d.type("DR"); await pause(40)
            d.mouse(.mouseMoved, d.windowPoint(Vec2(9, 8))); await pause(80)
            d.saveCanvas(c, "aid-door-preview")
            d.escape(); d.escape(); await pause(40)
            if let east = s.model.elements(.walls).first(where: { ($0.wall?.location.midpoint.x ?? 0) > 11.5 && abs(($0.wall?.location.midpoint.y ?? 0) - 4) < 1 }) {
                d.click(model: Vec2(12, 2)); await pause(40)
                if s.session.selection.ids == [east.id] {
                    d.mouse(.mouseMoved, d.windowPoint(Vec2(12, 2)))
                    d.mouse(.leftMouseDown, d.windowPoint(Vec2(12, 2)))
                    for k in 1...6 { d.mouse(.leftMouseDragged, d.windowPoint(Vec2(12 + Double(k) * 0.25, 2.3))); await pause(15) }
                    await pause(60)
                    d.saveCanvas(c, "aid-wall-drag")
                    d.escape(); d.mouse(.leftMouseUp, d.windowPoint(Vec2(12, 2))); await pause(40)
                    if (s.model[east.id]?.wall?.location.midpoint.x ?? 12) != 12 { d.undo() }
                }
                d.escape(); d.escape()
            }
            return "wall start \(ws.start), line \(ls.start) → \(ls.end)"
        }
        await toolRun("detail line", "DL", [Vec2(1, 2), Vec2(3, 2)], expect: [.detailLines])
        await toolRun("structural column", "CL", [Vec2(3, 5)], expect: [.structuralColumns])
        await toolRun("component", "CM", [Vec2(9, 5)])
        await toolRun("beam", "BM", [Vec2(1, 6.5), Vec2(11, 6.5)], expect: [.structuralFraming])
        await toolRun("stair", "", [Vec2(10, 1), Vec2(10, 5)], finish: true, expect: [.stairs], command: .stair) // STAIR: Create Stair, Finish // BL-KEYS: SR is Snap to Remote Objects
        await toolRun("room separator", "RS", [Vec2(8, 0.2), Vec2(8, 7.8)], expect: [.roomSeparationLines])
        await toolRun("floor sketch", "FL", [Vec2(0, 0), Vec2(12, 0), Vec2(12, 8), Vec2(0, 8), Vec2(0, 0)], finish: true, expect: [.floors])
        if let rcp1 {
            await toolRun("ceiling sketch in RCP", "", [Vec2(0.2, 0.2), Vec2(7.8, 0.2), Vec2(7.8, 7.8), Vec2(0.2, 7.8), Vec2(0.2, 0.2)], finish: true,
                          expect: [.ceilings], in: rcp1.id, command: .ceiling)
        }
        await toolRun("roof sketch on Level 2", "RF", [Vec2(-0.5, -0.5), Vec2(12.5, -0.5), Vec2(12.5, 8.5), Vec2(-0.5, 8.5), Vec2(-0.5, -0.5)],
                      finish: true, expect: [.roofs], in: l2.id)
        await toolRun("elevation marker", "EV", [Vec2(6, 12)])
        await run("text note") {
            let ctx = s.toolContext(for: l1.id)
            let original = ctx.requestText
            ctx.requestText = { _, _, done in done("QA TEXT") }
            let inPlace = ctx.requestTextInPlace; ctx.requestTextInPlace = nil; defer { ctx.requestTextInPlace = inPlace } // W2-ANNOT: answer through requestText
            defer { ctx.requestText = original }
            d.type("TX"); d.click(model: Vec2(2, 3)); await pause(60)
            d.escape(); d.escape()
            await d.verify("after text")
            try check(s.model.elements(.textNotes).contains { $0.textNote?.text == "QA TEXT" }, "text not created")
            return "ok"
        }
        await run("tag a door") {
            let before = s.model.elements(.tags).count
            d.type("TG"); d.click(model: Vec2(4, 0)); await pause(60); d.escape(); d.escape()
            await d.verify("after tag")
            return "tags \(before) → \(s.model.elements(.tags).count)"
        }
        await run("Move tool keeps joins") {
            guard let north = s.model.elements(.walls).first(where: { abs(($0.wall?.location.midpoint.y ?? 0) - 8) < 1e-3 }) else { throw QAError("no north wall") }
            d.click(model: Vec2(6.4, 8)); await pause(30)
            try check(s.session.selection.ids.contains(north.id), "north wall not selected: \(s.session.selection.ids)")
            d.type("MV")
            d.click(model: Vec2(6, 8)); await pause(30)          // base: the wall's midpoint
            d.mouse(.mouseMoved, d.windowPoint(Vec2(6, 10))); await pause(30)
            await d.verify("move preview")
            d.click(model: Vec2(6, 10)); await pause(60)
            d.escape(); d.escape()
            await d.verify("after move tool")
            let y = s.model[north.id]?.wall?.location.midpoint.y ?? 0
            try check(abs(y - 10) < 0.05, "north wall y = \(y)")
            let east = s.model.elements(.walls).first { abs(($0.wall?.location.midpoint.x ?? 0) - 12) < 1e-3 }
            try check(abs((east?.wall?.location.asSegment.map { max($0.start.y, $0.end.y) } ?? 0) - 10) < 0.05, "east wall did not follow the moved corner")
            return "ok"
        }
        await run("Copy tool, rotate, mirror") {
            guard let col = s.model.elements(.structuralColumns).first else { throw QAError("no column") }
            let n0 = s.model.elements(.structuralColumns).count
            let hits = d.canvas.map { c in c.hitCandidates(at: c.toScreen(col.column!.location)).compactMap { id -> String? in
                let b = c.graphics?.items.filter { $0.elementID == id }.map { "\($0.layer)[\(String(format: "%.2f,%.2f..%.2f,%.2f", $0.bounds.min.x, $0.bounds.min.y, $0.bounds.max.x, $0.bounds.max.y)) prims \($0.primitives.count) hitPolys \($0.hitPolygons.count)]" }.joined(separator: " ") ?? ""
                return s.model[id].map { "\($0.category.singularName) \($0.id) \(b)" }
            } } ?? []
            d.click(model: col.column!.location)
            try check(s.session.selection.ids == [col.id], "clicking the column selected \(s.session.selection.ids) (hits \(hits), column \(col.id))")
            d.type("CO"); d.click(model: col.column!.location); d.click(model: col.column!.location + Vec2(2, 0)); await pause(40)
            d.escape(); d.escape()
            await d.verify("after copy")
            try check(s.model.elements(.structuralColumns).count == n0 + 1, "copy made \(s.model.elements(.structuralColumns).count - n0)")
            return "ok"
        }
        await run("grip drag of a model line end") {
            guard let line = s.model.allElements.first(where: { $0.modelLine != nil && $0.ownerViewID == nil && ![.propertyLines, .roomSeparationLines].contains($0.category) }),
                  let seg = line.modelLine?.curve.asSegment else { return "no model line" }
            d.click(model: seg.midpoint); await pause(40)
            try check(s.session.selection.ids == [line.id], "clicking the line's midpoint \(seg.midpoint) selected \(s.session.selection.ids), line is \(line.id) \(line.category) \(seg.start)→\(seg.end) owner \(String(describing: line.ownerViewID))")
            d.drag(from: d.windowPoint(seg.end), to: d.windowPoint(seg.end + Vec2(0, 2)))
            await d.verify("after grip drag")
            let e = s.model[line.id]?.modelLine?.curve.asSegment?.end ?? .zero
            // A free end grip rounds the length to the zoom's increment (measured from the fixed end), so allow that step.
            let step = d.canvas?.toolContext.lengthIncrement ?? 0.5
            try check(e.distance(to: seg.end + Vec2(0, 2)) < max(0.3, step * 0.75), "line end at \(e), expected \(seg.end + Vec2(0, 2)) (length step \(step))")
            d.escape()
            return "ok"
        }
        await run("copy / paste with the keyboard") {
            guard let col = s.model.elements(.structuralColumns).first else { throw QAError("no column") }
            let n0 = s.model.elements(.structuralColumns).count
            d.click(model: col.column!.location)
            d.perform("copy:"); await pause(40)
            d.perform("paste:"); await pause(80)
            if s.activeTool != nil { d.click(model: col.column!.location + Vec2(0, 1.5)); await pause(60) }
            d.escape(); d.escape()
            await d.verify("after paste")
            try check(s.model.elements(.structuralColumns).count == n0 + 1, "paste made \(s.model.elements(.structuralColumns).count - n0)")
            return "ok"
        }
        await run("zoom region and thin lines") {
            d.type("ZR")
            d.drag(from: d.windowPoint(Vec2(0, 0)), to: d.windowPoint(Vec2(6, 4)))
            await d.verify("after zoom region")
            d.type("TL"); await d.verify("thin lines on")
            d.type("TL"); await d.verify("thin lines off")
            d.type("ZE"); await d.verify("zoom extents")
            d.type("ZR"); d.drag(from: d.windowPoint(Vec2(-3, -3)), to: d.windowPoint(Vec2(15, 11)))
            return "ok"
        }
        await run("schedule: edit a cell, see it in the model and the plan") {
            guard let sched = s.model.schedules.first(where: { $0.name == "Door Schedule" }) else { throw QAError("no door schedule") }
            s.open(sched.id)
            var table: ScheduleTableView?
            for _ in 0..<100 { table = s.canvases[sched.id] as? ScheduleTableView; if table?.tableModel?.rows.isEmpty == false { break }; await pause(30) }
            guard let tv = table, let tm = tv.tableModel else { throw QAError("schedule table did not load") }
            guard let row = tm.rows.firstIndex(where: { $0.kind == .data }), let ci = tm.columns.firstIndex(where: { $0.heading == "Mark" }) else { throw QAError("no data row / Mark column") }
            let doorID = tm.rows[row].elementIDs[0]
            tv.setActive(row: row, column: ci) // BL-SCHED: cells edit in place; rows highlight, Highlight in Model selects
            try check(tv.activeTarget?.editor == .text, "Mark cell is not editable")
            try check(tv.commit("QA-7", at: (row, ci)), "Mark edit refused")
            await d.flushEvents()
            try check(s.model[doorID]?.mark == "QA-7", "door mark is \(s.model[doorID]?.mark ?? "nil")")
            tv.recomputeNow()
            if let r2 = tv.tableModel?.rows.firstIndex(where: { $0.elementIDs == [doorID] }) { tv.setActive(row: r2, column: ci) }
            CommandRouter(state: s).run(.highlightInModel)
            try check(s.session.selection.ids == [doorID], "Highlight in Model → \(s.session.selection.ids)")
            s.open(l1.id); await d.verify("plan after schedule edit")
            // The door tag in the plan shows the new mark.
            let texts = d.canvas?.graphics?.items.filter { $0.category == .tags }.flatMap { $0.primitives }.compactMap { p -> String? in if case .text(let t) = p { return t.string }; return nil } ?? []
            try check(texts.contains("QA-7"), "tags show \(texts)")
            d.escape()
            return "Mark edited in the schedule; tag updated"
        }
        await scheduleEditingInteraction(s, d) // BL-SCHED
        await run("3D view: orbit, click-select, back to plan") {
            guard let v3 = s.model.views.first(where: { $0.view?.kind == .threeD }) else { throw QAError("no 3D view") }
            s.open(v3.id)
            var host: Viewport3DHost?
            for _ in 0..<200 { host = s.canvases[v3.id] as? Viewport3DHost; if host?.viewport.statistics.triangles ?? 0 > 0 { break }; await pause(30) }
            guard let h = host, h.viewport.statistics.triangles > 0 else { throw QAError("3D scene has no triangles") }
            h.viewport.zoomExtents(animated: false)
            // Start with nothing selected: a left-drag that begins on a selected element moves it instead of orbiting.
            s.session.selection.clear(); await pause(40)
            let vp = h.viewport
            let mid = vp.convert(NSPoint(x: vp.bounds.midX, y: vp.bounds.midY), to: nil)
            d.drag(from: mid, to: NSPoint(x: mid.x + 120, y: mid.y + 40))
            await d.flushEvents(); await pause(150)
            // Click the first element under a grid of points.
            var picked: ElementID?
            for fx in stride(from: 0.3, through: 0.7, by: 0.1) {
                for fy in stride(from: 0.3, through: 0.7, by: 0.1) {
                    let p = NSPoint(x: vp.bounds.width * fx, y: vp.bounds.height * fy)
                    if let id = vp.element(at: p) { d.click(vp.convert(p, to: nil)); picked = id; break }
                }
                if picked != nil { break }
            }
            await d.flushEvents(); await pause(200)
            try check(picked != nil, "nothing under the cursor in 3D")
            try check(s.session.selection.ids.contains(picked!), "3D click selected \(s.session.selection.ids), expected \(picked!)")
            guard let img = vp.snapshot(size: CGSize(width: 400, height: 300)) else { throw QAError("3D snapshot failed") }
            let rep = NSBitmapImageRep(cgImage: img)
            var colours = Set<Int>()
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) { for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
                if let c = rep.colorAt(x: x, y: y) { colours.insert(Int(c.redComponent * 31) << 10 | Int(c.greenComponent * 31) << 5 | Int(c.blueComponent * 31)) }
            } }
            try check(colours.count > 4, "3D render looks empty (\(colours.count) colours)")
            d.escape()
            s.open(l1.id); await d.verify("plan after 3D")
            return "selected \(s.model[picked!]?.category.singularName ?? "?") in 3D; \(colours.count) colours rendered"
        }
        await run("3D: wall and door on the work plane, drag a floor with snapping") { try await interaction3DTools(d, s, plan: l1.id) } // W2-3D
        await cameraInteraction(s, d, plan: l1, run: run) // W2-CAM
        await blSiteInteraction(s, d, plan: l1, run: run) // BL-SITE
        await run("sheet: place a view, double-click the viewport to open it") {
            guard let sheet = s.model.sheets.first else { return "no sheet" }
            if !s.model.owned(byView: sheet.id).contains(where: { $0.viewport?.viewID == l2.id }) {
                s.session.perform("Place View") { tx in
                    tx.create(.viewports, data: .viewport(ViewportData(viewID: l2.id, center: Vec2(0.3, 0.3), detailNumber: "9")), ownerViewID: sheet.id)
                }
            }
            s.open(sheet.id); await d.verify("sheet with viewport")
            guard let vp = s.model.owned(byView: sheet.id).first(where: { $0.viewport?.viewID == l2.id }),
                  let item = d.canvas?.graphics?.items.first(where: { $0.elementID == vp.id && !$0.hitPolygons.isEmpty }) else { throw QAError("viewport not drawn on the sheet") }
            let p = d.windowPoint(item.bounds.center)
            d.mouse(.mouseMoved, p)
            d.mouse(.leftMouseDown, p, clicks: 1); d.mouse(.leftMouseUp, p, clicks: 1)
            d.mouse(.leftMouseDown, p, clicks: 2); d.mouse(.leftMouseUp, p, clicks: 2)
            await d.flushEvents(); await pause(200)
            try check(s.activeViewID == l2.id || s.activeViewID == sheet.id, "double-click opened \(String(describing: s.activeViewID))")
            let opened = s.activeViewID == l2.id ? "opened Level 2 plan" : "activated the viewport on the sheet"
            s.open(l1.id); await d.settle()
            return opened
        }
        await auditInteraction(s, d, plan: l1) // W4-AUDIT: dialogs fit/Escape, typed lengths, Space flips, window vs crossing, Tab
        await run("undo everything, then redo everything") {
            let finalCount = s.model.count
            var undone = 0
            while s.session.undoManager.canUndo && undone < 200 {
                d.undo(); undone += 1; await pause(10)
                if undone % 5 == 0 { await d.verify("undo step \(undone)") }
            }
            await d.verify("fully undone")
            var redone = 0
            while s.session.undoManager.canRedo && redone < 200 {
                d.redo(); redone += 1; await pause(10)
                if redone % 5 == 0 { await d.verify("redo step \(redone)") }
            }
            await d.verify("fully redone")
            try check(s.model.count == finalCount, "after undo/redo the model has \(s.model.count) elements, expected \(finalCount)")
            return "\(undone) undos, \(redone) redos"
        }
        await run("dark appearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua); await pause(300)
            await d.verify("dark plan")
            NSApp.appearance = NSAppearance(named: .aqua); await pause(300)
            await d.verify("light plan")
            NSApp.appearance = nil
            return "ok"
        }
        await run("section tool and section view") {
            if let c = d.canvas { w.makeFirstResponder(c) }
            d.canvas?.zoom(to: Rect2(min: Vec2(-4, -2), max: Vec2(16, 12))); await pause(60) // both picks on screen
            CommandRouter(state: s).run(.section) // BL-KEYS: SX is Snap to Points
            try check(s.activeTool?.commandID == .section, "Section did not start the Section tool (tool: \(s.activeTool.map { "\($0.commandID)" } ?? "none"))")
            d.mouse(.mouseMoved, d.windowPoint(Vec2(-2, 4))); await pause(20)
            d.click(model: Vec2(-2, 4)); await pause(40)
            let wp = d.windowPoint(Vec2(-2, 4))
            let hit = w.contentView?.hitTest(w.contentView!.convert(wp, from: nil))
            let afterFirst = "tool \(s.activeTool.map { "\($0.commandID)" } ?? "none"), prompt “\(s.prompt)”, window point \(wp), hit \(hit.map { String(describing: type(of: $0)) } ?? "nil"), canvas frame \(d.canvas.map { $0.convert($0.bounds, to: nil) } ?? .zero), key window \(NSApp.keyWindow === w), sheets \(w.sheets.count), attached \(w.attachedSheet != nil)"
            d.mouse(.mouseMoved, d.windowPoint(Vec2(14, 4))); await pause(20)
            d.click(model: Vec2(14, 4)); await pause(60)
            let afterSecond = "tool \(s.activeTool.map { "\($0.commandID)" } ?? "none"), prompt “\(s.prompt)”, message \(s.message ?? "-")"
            d.escape(); d.escape()
            await d.verify("plan with section marker")
            guard let sec = s.model.views.first(where: { $0.view?.kind == .section }) else {
                throw QAError("no section view (after 1st click: \(afterFirst); after 2nd: \(afterSecond); sections \(s.model.elements(.sectionMarks).count))")
            }
            s.open(sec.id); await d.verify("section view")
            s.open(l1.id)
            return "ok"
        }
        // The browser steps close tabs and end on a sheet with a placed viewport, so they run after the plan steps.
        await browserInteraction(s, d, plan: l1, run: run) // BL-BROWSER
        await run("sheet: open, pan and zoom") {
            guard let sheet = s.model.sheets.first else { return "no sheet in template" }
            s.open(sheet.id); await d.verify("sheet")
            let mid = d.windowPoint(canvasFraction: 0.5, 0.5)
            for _ in 0..<4 { d.scroll(at: mid, dy: 3, continuous: false); await pause(15) }
            await d.verify("sheet zoomed")
            for _ in 0..<4 { d.scroll(at: mid, dx: -30, dy: 20, continuous: true); await pause(15) }
            await d.verify("sheet panned")
            s.open(l1.id)
            return "ok"
        }

        // The reference project: large plans, sheets and many annotations.
        await run("Courtyard House: plan pan/zoom/hover/select") {
            s.document?.updateChangeCount(.changeCleared)
            s.document?.close()
            await pause(400)
            appDelegate.openSample()
            var cs: DocumentState?
            for _ in 0..<200 {
                cs = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state
                if cs?.model.elements(.rooms).count ?? 0 > 100 { break }
                await pause(50)
            }
            guard let cs, let cw = cs.window else { throw QAError("sample did not open") }
            cw.setContentSize(NSSize(width: 1500, height: 940))
            let cd = CanvasDriver(state: cs, shotDir: outDir.appendingPathComponent("interact", isDirectory: true))
            let plan = view(cs, kind: .floorPlan, level: "Ground Floor")!
            cs.open(plan.id)
            await cd.verify("courtyard plan")
            let mid = cd.windowPoint(canvasFraction: 0.5, 0.5)
            for _ in 0..<6 { cd.scroll(at: mid, dy: 3, continuous: false); await pause(15) }
            await cd.verify("courtyard zoomed in")
            for _ in 0..<8 { cd.scroll(at: mid, dx: 40, dy: 30, continuous: true); await pause(15) }
            await cd.verify("courtyard panned")
            cd.hover((0..<30).map { i in cd.windowPoint(canvasFraction: 0.1 + Double(i) * 0.027, 0.5) })
            await cd.verify("courtyard hovered")
            cd.click(cd.windowPoint(canvasFraction: 0.5, 0.5))
            await cd.verify("courtyard click")
            CommandRouter(state: cs).run(.zoomExtents)
            await cd.verify("courtyard zoom to fit")
            for name in ["A101", "A201", "A301"] {
                if let sh = cs.model.sheets.first(where: { $0.sheet?.number == name }) {
                    cs.open(sh.id); await cd.verify("courtyard sheet \(name)")
                    for _ in 0..<5 { cd.scroll(at: cd.windowPoint(canvasFraction: 0.4, 0.5), dy: 3, continuous: false); await pause(15) }
                    await cd.verify("courtyard sheet \(name) zoomed")
                }
            }
            for v in cs.model.views where [.section, .elevation, .ceilingPlan].contains(v.view?.kind) && v.view?.parentViewID == nil {
                cs.open(v.id); await cd.verify("courtyard \(v.view!.kind.rawValue) \(v.name)")
            }
            d.failures += cd.failures
            d.checks += cd.checks
            cs.document?.updateChangeCount(.changeCleared)
            cs.document?.close()
            return "\(cd.checks) canvas checks"
        }
        results.append(StepResult(name: "Canvas checks summary", passed: d.failures.isEmpty,
                                  detail: "\(d.checks) canvas checks, \(d.failures.count) failure(s)"
                                      + (d.failures.isEmpty ? "" : ": " + d.failures.prefix(6).joined(separator: " || ")), seconds: 0))
    }
}
