import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// STAIR: the Railing dialog of Create Stair (Tools ▸ Railing): the railing type the new stair gets, or None, and its
// position on the treads or the stringer. Shown as a sheet on the document window.

@MainActor
enum StairRailingDialog {
    static func present(state: DocumentState, tool: StairTool) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Railing"
        let view = StairRailingDialogView(model: state.model, typeID: tool.railingTypeID, position: tool.railingPosition) { result in
            if let (type, position) = result {
                tool.railingTypeID = type
                tool.railingPosition = position
                state.toolChangedState()
            }
            if let parent = panel.sheetParent { parent.endSheet(panel) } else { panel.close() }
        }
        let host = NSHostingController(rootView: view.background(DialogColors.background)) // DIALOGS: sized to the dialog, opaque
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        if let w = state.window { w.beginSheet(panel) } else { panel.center(); panel.makeKeyAndOrderFront(nil) }
    }
}

/// Railing type (or None) and Position.
struct StairRailingDialogView: View {
    let model: BIMModel
    @State var typeID: ElementID?
    @State var position: StairRailingPosition
    /// nil: cancelled.
    let done: ((ElementID?, StairRailingPosition)?) -> Void

    var body: some View {
        ArcusDialog(icon: "stairs", tint: .brown, title: "Railing", subtitle: "Goes on both sides of the stair when you finish it.", size: .small, labelWidth: 90,
                    onCancel: { done(nil) }, onOK: { done((typeID, position)) }) {
            DialogSection {
                DialogRow("Railing type") {
                    Picker("", selection: $typeID) {
                        Text("None").tag(Optional<ElementID>.none)
                        ForEach(model.types(for: .railings), id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden()
                }
                DialogRow("Position", alignment: .top) {
                    Picker("", selection: $position) {
                        ForEach(StairRailingPosition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    .disabled(typeID == nil)
                }
            }
        }
    }
}
