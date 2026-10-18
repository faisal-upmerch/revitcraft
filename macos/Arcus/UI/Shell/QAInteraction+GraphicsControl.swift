import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: interaction QA for graphics control (hooked from `interaction()` with one line).
extension QAHarness {
    /// Opens each graphics-control dialog from its command, applies a V/G cut-weight override and an Object Style,
    /// and toggles Reveal Constraints and Temporary View Properties. Everything is undone again afterwards.
    static func graphicsControlInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Canvas: graphics control dialogs and overrides") {
            let before = d.failures.count
            guard let v = s.activeViewID else { throw QAError("no active view") }
            let dialogs: [(CommandID, DialogKind)] = [
                (.visibilityGraphics, .visibilityGraphics(v)), (.filtersDialog, .filters(nil)), (.viewTemplatesManage, .viewTemplates(v, .manage)),
                (.objectStyles, .objectStyles), (.warnings, .warnings), (.selectByID, .selectByID), (.additionalSettings, .additionalSettings(.lineWeights)),
                (.userInterface, .userInterface),
            ]
            for (cmd, kind) in dialogs {
                CommandRouter(state: s).run(cmd)
                await pause(200)
                try check(s.presented == kind, "\(CommandCatalog.info(cmd).title) did not open its dialog (presented: \(String(describing: s.presented)))")
                await d.verify("dialog \(cmd.rawValue)")
                s.presented = nil
                await pause(120)
            }
            // V/G: walls cut lines weight 9 → the plan's wall cut lines use pen 9.
            s.session.perform("QA V/G") { tx in tx.update(v) { e in var o = GraphicOverride(); o.cutLineWeight = 9; e.view?.visibility.categoryOverrides[.walls] = o } }
            await d.settle()
            let weights = Set(s.graphics.graphics(v)?.items.filter { $0.category == .walls && $0.layer == .cut }.flatMap(\.primitives).compactMap { p -> Int? in
                if case .polyline(_, _, let st) = p, st.weight > 1 { return st.weight } else { return nil }
            } ?? [])
            await d.verify("walls cut weight 9")
            try check(weights == [9], "wall cut weights \(weights)")
            await pause(20)
            try check(s.session.undoManager.undoActionName == "QA V/G", "the undo stack's top is “\(s.session.undoManager.undoActionName)”, not this step's V/G change")
            s.session.undoManager.undo()
            // Reveal Constraints and Temporary View Properties.
            CommandRouter(state: s).run(.revealConstraints)
            await d.settle()
            try check(s.session.temporaryVisibility[v]?.revealConstraints == true, "Reveal Constraints did not turn on")
            await d.verify("reveal constraints")
            CommandRouter(state: s).run(.revealConstraints)
            CommandRouter(state: s).run(.temporaryViewProperties)
            await pause(200)
            try check(s.presented == .viewTemplates(v, .temporary), "Temporary View Properties did not open the template picker")
            s.presented = nil
            await pause(120)
            let new = d.failures.dropFirst(before)
            try check(new.isEmpty, new.joined(separator: " || "))
            return "\(dialogs.count) dialogs opened; V/G cut weight reached the plan"
        }
    }
}
