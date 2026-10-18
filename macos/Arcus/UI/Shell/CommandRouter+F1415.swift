import AppKit
import ArcusDomain
import ArcusApplication

// F1415: Family Editor: main-window editor, views, reference/model lines, controls, swept blend, voids, openings. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    /// The Family Editor commands (`fe…`): they run in the Family Editor window open on this project (the most recent one).
    static let f1415Commands: Set<CommandID> = [
        .feExtrusion, .feBlend, .feRevolve, .feSweep, .feSweptBlend, .feVoidExtrusion, .feVoidBlend, .feVoidRevolve, .feVoidSweep, .feModelLine,
        .feComponent, .feModelText, .feOpening, .feControl, .feReferenceLine, .feReferencePlane, .feDimension, .feSymbolicLine, .feFamilyTypes,
        .feFamilyCategory, .feLoadIntoProject, .feLoadAndClose, .feFinishSketch, .feCancelSketch, .feDefault3D, .feControlSingleVertical,
        .feControlDoubleVertical, .feControlSingleHorizontal, .feControlDoubleHorizontal, .feFilledRegion, .feMaskingRegion, .feText,
        .feWorkPlaneSet, .feWorkPlaneShow, .feLoadNestedFamily, .fePurgeUnused, .feFlexTest, .feSaveFamilyAs,
    ]

    /// The Family Editor window editing a family of this document (the key one first, else the newest).
    var f1415Editor: FamilyEditorWindowController? {
        let mine = FamilyEditorWindowController.open.filter { $0.model.state === state }
        return mine.first { $0.window?.isKeyWindow == true } ?? mine.last
    }

    /// The tool for one of this batch's commands, or nil.
    func f1415MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? { nil }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f1415Perform(_ id: CommandID) -> Bool {
        guard Self.f1415Commands.contains(id) else { return false }
        guard let editor = f1415Editor else { state.show("Open a family in the Family Editor first (Edit Family or New Family…).", error: true); return true }
        editor.window?.makeKeyAndOrderFront(nil)
        editor.model.perform(id)
        return true
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f1415DisabledReason(_ id: CommandID) -> String? {
        guard Self.f1415Commands.contains(id) else { return nil }
        guard let editor = f1415Editor else { return "Open a family in the Family Editor (Edit Family or New Family…)." }
        return editor.model.disabledReason(id)
    }
}
