import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-KEYS: typed aliases, key routing, the shortcut file, two-stage Esc, Repeat, pre-selection, Select All scope,
/// tool option placement and memory, undo history, Find Referring Views, pinned elements and Space flips.
@MainActor
@Suite("Keyboard, aliases and tool lifecycle")
struct KeyboardLifecycleTests {
    let table = CommandCatalog.defaultAliases

    /// Types `keys` quickly (0.1 s apart) and returns the commands run.
    func type(_ keys: String, _ m: inout AliasMatcher, table t: [String: CommandID]? = nil, start: TimeInterval = 100) -> [CommandID] {
        var out: [CommandID] = []
        for (i, ch) in keys.enumerated() { out += m.feed(ch, at: start + Double(i) * 0.1, in: t ?? table).commands }
        return out
    }

    // MARK: Aliases (ARCUS-003/068/067)

    @Test func zoomAliasesExecuteAndClearTheBuffer() {
        let expected: [String: CommandID] = ["ZE": .zoomExtents, "ZF": .zoomExtents, "ZX": .zoomExtents, "ZA": .zoomAllToFit, "ZR": .zoomRegion,
                                             "ZZ": .zoomRegion, "ZO": .zoomOutTwice, "ZV": .zoomOutTwice, "ZS": .zoomSheetSize, "ZP": .previousPanZoom,
                                             "ZC": .previousPanZoom]
        for (keys, id) in expected {
            var m = AliasMatcher()
            let first = m.feed(keys.first!, at: 0, in: table)
            #expect(first.commands.isEmpty && first.echo == "Z", "\(keys): Z alone waits")
            let second = m.feed(keys.last!, at: 0.5, in: table)
            #expect(second.commands == [id], "\(keys) ran \(second.commands)")
            #expect(second.echo == nil && m.buffer.isEmpty, "\(keys): buffer not cleared")
        }
        var lower = AliasMatcher()
        #expect(type("ze", &lower) == [.zoomExtents], "aliases are case-insensitive")
    }

    @Test func everyDefaultAliasRunsItsCommandWhenTyped() {
        for (alias, id) in table {
            var m = AliasMatcher()
            let ran = type(alias, &m)
            // An alias that is also the start of a longer one waits for a pause.
            let pending = table.keys.contains { $0.count > alias.count && $0.hasPrefix(alias) }
            if pending {
                #expect(ran.isEmpty)
                #expect(m.flush(at: 1000, in: table).commands == [id], "\(alias) did not run after the pause")
            } else {
                #expect(ran == [id], "\(alias) ran \(ran), expected \(id)")
            }
            #expect(m.buffer.isEmpty, "\(alias) left \(m.buffer) in the buffer")
        }
    }

    @Test func bufferClearsOnNonMatchTimeoutAndEsc() {
        var m = AliasMatcher()
        #expect(m.feed("Q", at: 0, in: table).echo == nil, "nothing starts with Q: dropped at once")
        #expect(m.feed("W", at: 1, in: table).echo == "W")
        let broken = m.feed("Z", at: 1.1, in: table)
        #expect(broken.commands.isEmpty && broken.echo == "Z", "WZ matches nothing; Z starts a new sequence")
        // Timeout: Z then E after 2 s is not ZE.
        var t = AliasMatcher()
        _ = t.feed("Z", at: 0, in: table)
        let late = t.feed("E", at: 2, in: table)
        #expect(!late.commands.contains(.zoomExtents))
        #expect(t.flush(at: 10, in: table).echo == nil && t.buffer.isEmpty)
        // Esc.
        var e = AliasMatcher()
        _ = e.feed("W", at: 0, in: table)
        let cleared = e.cancel()
        let again = e.cancel()
        #expect(cleared && e.buffer.isEmpty && !again)
    }

    @Test func aShorterAliasWaitsForTheNextKeyOrThePause() {
        let t: [String: CommandID] = ["AB": .wall, "ABC": .door]
        var m = AliasMatcher()
        #expect(type("AB", &m, table: t).isEmpty)
        #expect(m.feed("C", at: 100.3, in: t).commands == [.door])
        var n = AliasMatcher()
        _ = type("AB", &n, table: t)
        #expect(n.feed("X", at: 100.3, in: t).commands == [.wall], "a key that can't continue runs the complete alias")
        var p = AliasMatcher()
        _ = type("AB", &p, table: t)
        #expect(p.flush(at: 100.5, in: t).commands.isEmpty, "not yet timed out")
        #expect(p.flush(at: 103, in: t).commands == [.wall])
    }

    @Test func defaultsFollowTheReferenceToolWithDocumentedExtras() {
        let expected: [String: CommandID] = [
            "SX": .snapPoints, "SR": .snapRemote, "SW": .snapWorkPlaneGrid, "SZ": .snapClose, "SS": .snapOverrideOff, "SO": .snapsOff,
            "SE": .snapEndpoint, "SM": .snapMidpoint, "SN": .snapNearest, "SQ": .snapQuadrant, "SI": .snapIntersection, "SC": .snapCenter,
            "SP": .snapPerpendicular, "ST": .snapTangent, "ZA": .zoomAllToFit, "SA": .selectAllInstancesInProject, "RC": .repeatLastCommand,
            "KS": .keyboardShortcuts, "EOD": .overrideGraphicsElement, "VP": .viewProperties, "CS": .createSimilar, "RE": .scale,
            "PP": .toggleProperties, "WA": .wall, "DR": .door, "MV": .move, "VG": .visibilityGraphics, "VV": .visibilityGraphics,
        ]
        for (a, id) in expected { #expect(table[a] == id, "\(a) → \(table[a].map { "\($0)" } ?? "nil"), expected \(id)") }
        // Arcus extras kept.
        for a in ["FL", "RF", "EV", "3D"] { #expect(table[a] != nil, "extra \(a) missing") }
        #expect(!CommandCatalog.info(.section).aliases.contains("SX"))
        #expect(!CommandCatalog.info(.stairStraight).aliases.contains("SR"))
    }

    // MARK: Key routing (ARCUS-002/024/041/052)

    @Test func textFocusSuppressesAliasesReturnAndSpace() {
        let editing = CanvasKeyContext(textEditing: true, toolActive: true, preselectionPending: true, hasSelection: true)
        for key: CanvasKey in [.character("W"), .character("A"), .returnKey, .escape, .space(shift: false), .other] {
            #expect(CanvasKeyRouter.route(key, editing) == .ignore, "\(key) must not reach the canvas while text is edited")
        }
        let modifyEmpty = CanvasKeyContext()
        #expect(CanvasKeyRouter.route(.character("W"), modifyEmpty) == .standard)
        #expect(CanvasKeyRouter.route(.returnKey, modifyEmpty) == .repeatLastCommand)
        #expect(CanvasKeyRouter.route(.returnKey, CanvasKeyContext(preselectionPending: true)) == .finishPreselection)
        #expect(CanvasKeyRouter.route(.returnKey, CanvasKeyContext(toolActive: true)) == .standard, "Return finishes the tool")
        #expect(CanvasKeyRouter.route(.space(shift: false), CanvasKeyContext(hasSelection: true)) == .flipSelection)
        #expect(CanvasKeyRouter.route(.space(shift: true), CanvasKeyContext(toolActive: true)) == .flipHand)
        #expect(CanvasKeyRouter.route(.space(shift: false), CanvasKeyContext(toolActive: true)) == .standard)
        #expect(CanvasKeyRouter.route(.returnKey, CanvasKeyContext(modified: true)) == .standard)
    }

    // MARK: Alias table and shortcut file (ARCUS-069)

    @Test func aliasTableReportsConflictsAndReassigns() {
        var t = AliasTable()
        let c = t.conflict(for: "wa", assigningTo: .door)
        #expect(c?.usedBy == .wall)
        #expect(t.add("WA", to: .door)?.usedBy == .wall, "a used alias is not taken silently")
        #expect(t.command(for: "WA") == .wall)
        #expect(t.add("WA", to: .door, reassign: true) == nil)
        #expect(t.command(for: "WA") == .door)
        #expect(t.customizations["WA"] == .some(.door))
        #expect(t.set(["DR", "MV"], for: .window)?.usedBy != nil)
        #expect(t.conflict(for: "Z", assigningTo: .wall)?.prefixOf.contains("ZE") == true, "Z would wait for ZE and others")
        t.restoreDefaults()
        #expect(t == AliasTable())
    }

    @Test func shortcutFileRoundTripsAndReportsProblems() throws {
        var t = AliasTable()
        t.add("QW", to: .wall)
        t.remove("VV")
        let xml = ShortcutFile.export(t)
        #expect(xml.contains("<Shortcuts application=\"Arcus\""))
        #expect(xml.contains("CommandId=\"zoomExtents\" CommandName=\"Zoom to Fit\" Shortcuts=\"ZE#ZF#ZX\""))
        let back = try ShortcutFile.import(Data(xml.utf8), base: AliasTable())
        #expect(back.table == t)
        #expect(back.unknownCommands.isEmpty && back.commandsRead == CommandCatalog.all.count)

        let partial = """
        <?xml version="1.0"?><Shortcuts><ShortcutItem CommandId="door" Shortcuts="DD DX"/><ShortcutItem CommandId="noSuchCommand" Shortcuts="QQ"/>
        <ShortcutItem CommandId="window" Shortcuts="DD"/></Shortcuts>
        """
        let r = try ShortcutFile.import(Data(partial.utf8), base: AliasTable())
        #expect(r.unknownCommands == ["noSuchCommand"])
        #expect(r.duplicates == ["DD"])
        #expect(r.table.command(for: "DX") == .door && r.table.command(for: "DD") == .window)
        #expect(r.table.aliases(for: .door) == ["DX"], "listed commands get exactly the file's keys")
        #expect(r.table.command(for: "WA") == .wall, "commands not in the file keep their keys")
        #expect(throws: ShortcutFile.ImportError.self) { try ShortcutFile.import(Data("not xml <".utf8), base: AliasTable()) }
        #expect(throws: ShortcutFile.ImportError.notAShortcutFile) { try ShortcutFile.import(Data("<a/>".utf8), base: AliasTable()) }
        #expect(ShortcutFile.escape("A&B \"C\" <D>") == "A&amp;B &quot;C&quot; &lt;D&gt;")
    }

    // MARK: Two-stage Esc (ARCUS-001/040)

    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }

    @Test func escEndsTheWallChainThenTheToolThenTheSelection() {
        let (ctx, _) = context()
        let sel = ctx.session.selection
        let wall = WallTool(ctx: ctx, mode: .line)
        click(wall, .zero); click(wall, Vec2(5, 0))
        #expect(ctx.model.elements(.walls).count == 1)
        #expect(ToolLifecycle.escape(tool: wall, selection: sel) == .cancelledStep, "first Esc ends the chain, the tool stays")
        #expect(ToolLifecycle.escape(tool: wall, selection: sel) == .exitedTool, "second Esc returns to Modify")
        let w = ctx.model.elements(.walls)[0].id
        sel.select([w])
        #expect(ToolLifecycle.escape(tool: nil, selection: sel) == .clearedSelection)
        #expect(sel.isEmpty)
        #expect(sel.selectPrevious(in: ctx.model) && sel.ids == [w], "Select Previous restores the cleared selection")
        #expect(ToolLifecycle.escape(tool: nil, selection: SelectionModel()) == .none)
    }

    @Test func escDuringMovePreviewKeepsTheSelection() {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(6, 0)) }
        ctx.session.selection.select([w])
        let move = MoveCopyTool(ctx: ctx, ids: [w], copy: false)
        click(move, Vec2(1, 0))
        move.pointerMoved(ToolInput(point: Vec2(3, 2), rawPoint: Vec2(3, 2)))
        #expect(!move.preview.primitives.isEmpty, "the move preview is showing")
        #expect(ToolLifecycle.escape(tool: move, selection: ctx.session.selection) == .cancelledStep)
        #expect(move.preview.primitives.isEmpty && ctx.session.selection.ids == [w])
        #expect(ToolLifecycle.escape(tool: move, selection: ctx.session.selection) == .exitedTool)
        #expect(ctx.session.selection.ids == [w], "leaving Move keeps the selection")
        #expect(ctx.model[w]!.wall!.location.asSegment!.start == .zero, "nothing moved")
    }

    /// A sketch-mode tool that would like to exit on Esc.
    final class EagerSketch: InteractiveTool {
        let commandID = CommandID.floor
        let title = "Sketch"
        var prompt: String { "" }
        var preview = ToolPreview()
        var isSketchMode: Bool { true }
        var escapes = 0
        func pointerMoved(_ i: ToolInput) {}
        func pointerDown(_ i: ToolInput) {}
        func escape() -> EscapeResult { escapes += 1; return .exitTool }
    }

    @Test func escNeverLeavesSketchMode() {
        let (ctx, _) = context()
        let sketch = SketchTool(ctx: ctx, target: .floor, commandID: .floor)
        sketch.drawMode = .line
        click(sketch, .zero); click(sketch, Vec2(4, 0))
        for _ in 0..<3 { #expect(ToolLifecycle.escape(tool: sketch, selection: ctx.session.selection) == .cancelledStep) }
        let eager = EagerSketch()
        #expect(ToolLifecycle.escape(tool: eager, selection: ctx.session.selection) == .cancelledStep)
        #expect(eager.escapes == 1, "the tool still cancels its current step")
    }

    // MARK: Repeat and pre-selection (ARCUS-041/052)

    @Test func repeatOffersCreationAndModifyCommandsOnly() {
        for id: CommandID in [.wall, .door, .alignedDimension, .detailLine, .section, .move, .copy, .rotate] { #expect(ToolLifecycle.isRepeatable(id), "\(id)") }
        for id: CommandID in [.zoomExtents, .zoomRegion, .undo, .redo, .paste, .copyClipboard, .snapEndpoint, .visibilityGraphics, .save, .modify,
                              .selectAll, .repeatLastCommand, .keyboardShortcuts, .previousPanZoom, .threeDView] {
            #expect(!ToolLifecycle.isRepeatable(id), "\(id)")
        }
        let recent: [CommandID] = [.zoomExtents, .wall, .undo, .door, .wall, .section, .paste, .detailLine, .move, .alignedDimension, .grid]
        #expect(ToolLifecycle.lastRepeatable(recent) == .wall)
        #expect(ToolLifecycle.recentRepeatable(recent) == [.wall, .door, .section, .detailLine, .move])
        for id: CommandID in [.move, .copy, .rotate, .mirrorPickAxis, .array, .scale, .pin, .delete] { #expect(ToolLifecycle.preselectionCommands.contains(id)) }
    }

    // MARK: Select All (ARCUS-024)

    @Test func selectAllTakesModelElementsOnly() throws {
        let (ctx, ids) = context()
        var w: ElementID!, line: ElementID!
        let plan = ctx.viewID
        ctx.session.perform("Setup") { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(6, 0))
            line = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(0, 2), Vec2(3, 2))))), ownerViewID: plan)
        }
        let marks = ctx.model.elements(.elevationMarks).map(\.id) + ctx.model.elements(.sectionMarks).map(\.id)
        let everything = [w!, line!] + ids.levels + marks
        #expect(SelectAllScope.filter(everything, in: ctx.model) == [w])
        #expect(SelectAllScope.filter([line!] + ids.levels + marks, in: ctx.model) == [line], "no model elements: detail elements, never markers or datums")
    }

    // MARK: Tool options on the ribbon and their memory (ARCUS-055/046/091)

    @Test func modifyAndTagOptionsMoveToTheRibbonPlacementValuesStay() {
        let (ctx, ids) = context()
        let move = MoveCopyTool(ctx: ctx, ids: [], copy: false)
        #expect(move.options.allSatisfy { ToolOptionPlacement.isOnRibbon($0, of: .move) }, "Constrain and Disjoin are on the ribbon")
        let copy = MoveCopyTool(ctx: ctx, ids: [], copy: true)
        #expect(copy.options.contains { $0.id == "multiple" && ToolOptionPlacement.isOnRibbon($0, of: .copy) })
        let wall = WallTool(ctx: ctx, mode: .line)
        #expect(!wall.options.contains { ToolOptionPlacement.isOnRibbon($0, of: .wall) }, "wall placement values stay on the Options Bar")
        let window = InsertTool(ctx: ctx, category: .windows)
        #expect(window.options.filter { ToolOptionPlacement.isOnRibbon($0, of: .window) }.map(\.id) == ["tag"], "sill height stays on the bar")
        let dim = DimensionTool(ctx: ctx, kind: .aligned)
        #expect(Set(dim.options.filter { ToolOptionPlacement.isOnRibbon($0, of: dim.commandID) }.map(\.id)) == ["pref", "pick"])
        #expect(ToolOptionPlacement.ribbonOptionIDs(.level) == ["plans"])
        #expect(ToolOptionPlacement.keepsSelectionTab(.move) && !ToolOptionPlacement.keepsSelectionTab(.wall))
        _ = ids
    }

    @Test func modifyToolSettingsAreRememberedAcrossSessions() throws {
        let (ctx, _) = context()
        let suite = "arcus.tests.modifySettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModifyToolSettings(defaults: defaults)
        let move = MoveCopyTool(ctx: ctx, ids: [], copy: false)
        move.setOption("constrain", .bool(true)); move.setOption("disjoin", .bool(true))
        store.record(move)
        let array = ArrayTool(ctx: ctx, ids: [])
        array.setOption("arrayMode", .text(ArraySpec.Kind.radial.rawValue)); array.setOption("count", .int(6)); array.setOption("associate", .bool(false))
        store.record(array)
        // A new launch: a new store over the same defaults.
        let later = ModifyToolSettings(defaults: defaults)
        let move2 = MoveCopyTool(ctx: ctx, ids: [], copy: false)
        later.restore(into: move2)
        #expect(move2.constrain && move2.disjoin)
        let array2 = ArrayTool(ctx: ctx, ids: [])
        later.restore(into: array2)
        #expect(array2.radial && array2.count == 6 && !array2.associate)
        let wall = WallTool(ctx: ctx, mode: .line)
        store.record(wall)
        #expect(defaults.dictionary(forKey: ModifyToolSettings.key)?["wall"] == nil, "placement tools are not remembered here")
    }

    // MARK: Undo history (ARCUS-065)

    @Test func undoHistoryListsStepsAndUndoesThroughAPickedOne() {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        let history = UndoHistory(undoManager: session.undoManager)
        func step(_ name: String, _ x: Double) {
            session.undoManager.beginUndoGrouping()
            session.perform(name) { tx in Fx.wall(tx, ids, Vec2(x, 0), Vec2(x, 5)) }
            session.undoManager.endUndoGrouping()
        }
        step("Wall A", 0); step("Wall B", 2); step("Wall C", 4)
        #expect(history.undoNames == ["Wall C", "Wall B", "Wall A"])
        history.undo(through: 1)
        #expect(session.model.elements(.walls).count == 1)
        #expect(history.undoNames == ["Wall A"] && history.redoNames == ["Wall B", "Wall C"])
        history.redo(through: 0)
        #expect(history.undoNames == ["Wall B", "Wall A"] && history.redoNames == ["Wall C"])
        step("Wall D", 6)
        #expect(history.redoNames.isEmpty && history.undoNames.first == "Wall D")
        history.reset()
        #expect(history.undoNames.isEmpty)
    }

    // MARK: Find Referring Views (ARCUS-056)

    @Test func referringViewsListTheViewsShowingAnElement() {
        let (ctx, ids) = context()
        var w: ElementID!, line: ElementID!
        let plan = ctx.viewID
        ctx.session.perform("Setup") { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(6, 0))
            line = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(0, 2), Vec2(3, 2))))), ownerViewID: plan)
        }
        let views = ReferringViews.find(w, in: ctx.model)
        #expect(views.contains(plan), "the wall's floor plan shows it")
        #expect(views.count >= 2, "and at least one other view (elevation, 3D): \(views.count)")
        #expect(ReferringViews.find(line, in: ctx.model) == [plan], "a detail line is only in its own view")
    }

    // MARK: Pinned elements (ARCUS-078)

    @Test func pinnedElementsRefuseMoveAndDeleteButDoNotBlockTheirNeighbours() throws {
        let (ctx, ids) = context()
        let s = ctx.session
        var a: ElementID!, b: ElementID!
        s.perform("Walls") { tx in a = Fx.wall(tx, ids, .zero, Vec2(6, 0)); b = Fx.wall(tx, ids, Vec2(6, 0), Vec2(6, 5)) }
        s.perform("Pin") { tx in tx.update(b) { $0.pinned = true } }
        let before = s.model[b]!.wall!.location
        let r = s.perform("Move") { tx in try ElementOperations.transform([b], by: .translation(Vec2(1, 0)), in: tx, viewID: ctx.viewID) }
        #expect(r == nil && s.lastError?.message.contains("Pinned") == true, "moving a pinned wall is refused with a message")
        #expect(s.model[b]!.wall!.location == before, "and nothing changed")
        s.clearError()
        s.delete([b])
        #expect(s.model[b] != nil && s.lastError?.message.contains("Pinned") == true, "deleting a pinned wall is refused")
        s.clearError()
        // The unpinned neighbour moves; the pinned wall it is joined to stays where it is.
        let moved = s.perform("Move") { tx in try ElementOperations.transform([a], by: .translation(Vec2(0, -1)), in: tx, viewID: ctx.viewID, disjoin: true) }
        #expect(moved != nil && s.lastError == nil)
        #expect(s.model[b]!.wall!.location == before, "the pinned wall is untouched")
    }

    // MARK: Space flips (ARCUS-028)

    @Test func spaceFlipsTheDoorBeingPlacedAndTheFlipSticks() {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(10, 0)) }
        let door = InsertTool(ctx: ctx, category: .doors)
        var i = ToolInput(point: Vec2(4, 0.4), rawPoint: Vec2(4, 0.4))
        i.hit = w
        door.pointerMoved(i)
        let natural = door.isFacingFlipped
        door.spaceBar()
        #expect(door.isFacingFlipped == !natural)
        door.pointerMoved(i)
        #expect(door.isFacingFlipped == !natural, "moving the pointer keeps the flip")
        door.flipHand()
        #expect(door.isHandFlipped)
        door.pointerDown(i)
        let placed = ctx.model.elements(.doors).first
        #expect(placed != nil)
        #expect(placed?.insert?.facingFlipped == !natural && placed?.insert?.handFlipped == true)
    }
}
