import SwiftUI
import ArcusDomain
import ArcusApplication

// BL-SCHED: the "Modify Schedule/Quantities" contextual tab, shown while a schedule is the active view.

extension RibbonContent {
    /// Title of the schedule contextual tab, or nil when the active view isn't a schedule (or a tool runs, or elements
    /// are selected — then the usual contextual tab applies).
    @MainActor static func scheduleContextualTitle(_ state: DocumentState) -> String? {
        // An active schedule always shows its own tab, even when elements chosen in another view are still selected.
        guard state.activeTool == nil, state.activeView?.schedule != nil else { return nil }
        return "Modify Schedule/Quantities"
    }

    @MainActor static func schedulePanels(_ state: DocumentState) -> [RibbonPanel]? {
        guard scheduleContextualTitle(state) != nil else { return nil }
        // F12: RevitCraft's panels and order (rc-app ribbon.rs, the Schedule/Quantities tab), plus Arcus's Appearance dialog
        // and CSV exchange.
        return [
            RibbonPanel(title: "Properties", items: [.large(.scheduleProperties)], tint: view),
            RibbonPanel(title: "Parameters", items: [.small(.scheduleFormatUnit), .small(.scheduleCalculatedField), .small(.scheduleCombineParameters)], tint: view),
            RibbonPanel(title: "Columns", items: [.large(.scheduleInsertColumn), .small(.scheduleDeleteColumn), .small(.scheduleResizeColumn),
                                                  .small(.scheduleHideColumn), .small(.scheduleUnhideAllColumns).newColumn()], tint: view),
            RibbonPanel(title: "Rows", items: [.large(.scheduleInsertHeaderRow, [.scheduleInsertRowAbove, .scheduleInsertRowBelow]), .small(.scheduleInsertRow),
                                               .small(.scheduleDeleteRow), .small(.scheduleResizeRow)], tint: view),
            RibbonPanel(title: "Titles & Headers", items: [.large(.scheduleMergeHeaders), .small(.scheduleInsertImage), .small(.scheduleClearCell), .small(.scheduleGroupHeaders),
                                                           .small(.scheduleUngroupHeaders), .small(.scheduleFreezeHeader)], tint: view),
            RibbonPanel(title: "Appearance", items: [.small(.scheduleShading), .small(.scheduleBorders), .small(.scheduleResetAppearance), .small(.scheduleFont),
                                                     .small(.scheduleAlignLeft, [.scheduleAlignLeft, .scheduleAlignCenter, .scheduleAlignRight]),
                                                     .small(.scheduleAlignMiddle, [.scheduleAlignTop, .scheduleAlignMiddle, .scheduleAlignBottom]),
                                                     .small(.scheduleAppearance).newColumn()], tint: view),
            RibbonPanel(title: "Element", items: [.large(.highlightInModel)], tint: view),
            RibbonPanel(title: "Split", items: [.large(.scheduleSplitAndPlace)], tint: sheet),
            RibbonPanel(title: "Export", items: [.small(.exportScheduleCSV), .small(.importScheduleCSV)], tint: sheet),
        ]
    }
}

extension RibbonView {
    /// The schedule tab's panels while a schedule is active; otherwise the regular contextual panels.
    @ViewBuilder func scheduleOrContextualPanels(tool: (any InteractiveTool)?) -> some View {
        if tool == nil, let panels = RibbonContent.schedulePanels(state) {
            ForEach(panels) { p in panelView(p, contextual: true) }
        } else {
            contextualPanels(tool: tool)
        }
    }
}
