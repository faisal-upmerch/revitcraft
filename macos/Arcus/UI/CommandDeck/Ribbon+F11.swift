import SwiftUI
import ArcusDomain
import ArcusApplication

// F11: ribbon captions for the Manage tab's new dropdowns and the schedule tools, and the Design Options panel with
// RevitCraft's active option combo (rc-app ribbon.rs `OptionCombo`).

extension RibbonItem {
    /// Captions of F11–F13 commands where RevitCraft's ribbon labels differ from the command titles.
    static func f11Caption(_ id: CommandID, size: Size, split: Bool) -> String? {
        switch id {
        case .specifyCoordinates where split: return "Coordinates"
        case .relocateProject where split: return "Position"
        case .saveSelection: return "Save"
        case .loadSelection: return "Load"
        case .editSelection: return "Edit"
        case .startingView where size == .large: return "Starting\nView"
        case .scheduleInsertHeaderRow: return "Insert"
        case .scheduleResizeRow: return "Resize"
        case .scheduleAlignLeft where split: return size == .large ? "Align\nHorizontal" : "Align Horizontal"
        case .scheduleAlignMiddle where split: return size == .large ? "Align\nVertical" : "Align Vertical"
        case .scheduleSplitAndPlace: return size == .large ? "Split &\nPlace" : "Split & Place"
        case .scheduleCombineParameters where size == .large: return "Combine\nParameters"
        default: return nil
        }
    }
}

/// Design Options: the dialog, Add to Set / Pick to Edit, and the combo choosing the option being edited ("Main Model"
/// or an option). New elements join the chosen option.
struct DesignOptionsRibbonPanel: View {
    let panel: RibbonPanel
    let state: DocumentState
    var body: some View {
        let _ = state.session.changeCounter
        let sets = DesignOptionEditing.sets(state.model)
        PanelCard(title: panel.title) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                RibbonButton(item: .large(.designOptions), state: state, tint: panel.tint)
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    RibbonButton(item: .small(.addToSet), state: state, tint: panel.tint)
                    RibbonButton(item: .small(.pickToEdit), state: state, tint: panel.tint)
                    Picker("", selection: Binding(get: { state.session.activeDesignOptionID?.raw ?? 0 },
                                                  set: { v in F11Actions(state: state).setActiveOption(v == 0 ? nil : ElementID(v)) })) {
                        Text("Main Model").tag(UInt64(0))
                        ForEach(sets, id: \.name) { s in
                            Section(s.name) { ForEach(s.options, id: \.id) { o in Text(DesignOptionEditing.label(o)).tag(o.id.raw) } }
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                    .disabled(sets.isEmpty)
                    .help("The design option being edited. New elements join it.")
                    .accessibilityLabel("Active design option")
                }
                .frame(height: RibbonMetrics.contentHeight, alignment: .top)
            }
        }
    }
}
