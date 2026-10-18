import SwiftUI
import ArcusDomain
import ArcusApplication

// BL-KEYS: contextual ribbon additions — tool options in the 2026 arrangement (Modify tools, Tag on Placement, tag
// orientation/leader, dimension Prefer/Pick, Make Plan Views), the Finish/Cancel panel of the Modify pre-selection flow,
// and the contextual tab title while Modify tools run.

extension RibbonContent {
    /// "Modify | Walls" while Move, Copy, Rotate, … run on a selection (not "Modify | Place Move"), and while a Modify
    /// command waits for its selection. nil: use the standard title.
    @MainActor static func keysContextualTitle(_ state: DocumentState) -> String? {
        if state.keys.pendingCommand != nil { return "Modify | " + (selectionTitle(state) ?? "Select") }
        if let t = state.activeTool, ToolOptionPlacement.keepsSelectionTab(t.commandID), let s = selectionTitle(state) { return "Modify | \(s)" }
        return nil
    }
}

/// The active tool's ribbon-hosted options (see `ToolOptionPlacement`), stacked three to a column. Changes to Modify
/// tool options are remembered for the next time the tool runs, across launches.
struct RibbonToolOptionsPanel: View {
    let state: DocumentState
    let tool: any InteractiveTool

    var body: some View {
        let _ = state.toolRevision
        let options = tool.options.filter { ToolOptionPlacement.isOnRibbon($0, of: tool.commandID) }
        if !options.isEmpty {
            let columns = stride(from: 0, to: options.count, by: 3).map { Array(options[$0..<min($0 + 3, options.count)]) }
            PanelCard(title: ToolOptionPlacement.panelTitle(tool.commandID), contextual: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns.indices, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(columns[c]) { opt in
                                OptionControl(state: state, tool: tool, option: opt)
                                    .frame(height: RibbonMetrics.rowHeight)
                            }
                        }
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 4)
            }
            .onChange(of: options.map { "\($0.id)=\($0.value)" }) { _, _ in ModifyToolSettings.shared.record(tool) }
        }
    }
}

/// Finish and Cancel while a Modify command waits for its selection (Return is Finish, Esc is Cancel).
struct PreselectionPanel: View {
    let state: DocumentState
    var body: some View {
        let title = state.keys.pendingCommand.map { CommandCatalog.info($0).title } ?? "Modify"
        PanelCard(title: title, contextual: true) {
            HStack(spacing: 4) {
                button("Finish", "checkmark", .green) { state.finishPreselection() }
                button("Cancel", "xmark", .red) { state.cancelPreselection() }
            }
        }
    }

    private func button(_ title: String, _ symbol: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(color).frame(width: 30, height: 26)
                Text(title).font(.system(size: 10)).frame(height: 26, alignment: .top)
            }
            .frame(maxHeight: RibbonMetrics.contentHeight, alignment: .top)
            .padding(.horizontal, 4).padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .modifier(HoverBackground(radius: 8))
        .accessibilityLabel(title)
        .help(title == "Finish" ? "Continue with the selected elements (Return)" : "Cancel (Esc)")
    }
}
