import SwiftUI
import ArcusDomain
import ArcusApplication

// F5: Architecture ▸ Component ▸ Model In-place: RevitCraft's Family Category and Parameters, then Name (rc-app
// dialogs/mod.rs `in_place_dialog`), in one sheet.

enum F5Dialog: Equatable {
    case modelInPlace
}

struct F5DialogHost: View {
    let state: DocumentState
    let dialog: F5Dialog
    var body: some View {
        switch dialog {
        case .modelInPlace: ModelInPlaceDialog(state: state)
        }
    }
}

/// The category and name of a new in-place family; OK opens it in the Family Editor.
struct ModelInPlaceDialog: View {
    let state: DocumentState
    @State private var template: FamilyTemplate = .genericModel
    @State private var name = ""

    var body: some View {
        DialogFrame(title: "Model In-place", icon: "cube", tint: .purple, size: .small, subtitle: "Family Category and Parameters", okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
                    disabledReason: "Enter a name", labelWidth: 60, state: state) {
            state.presented = nil
            InPlaceFamilyFlow.begin(state: state, template: template, name: name)
        } content: {
            DialogSection("Family category", boxed: false) {
                DialogListBox(count: InPlaceFamilies.templates.count, rowHeight: 26, minRows: 4, maxRows: 7) {
                    List(InPlaceFamilies.templates, id: \.self, selection: Binding(get: { template }, set: { if let t = $0 { template = t } })) { t in
                        Text(t.category.displayName).tag(t)
                    }
                }
            }
            DialogSection(footnote: "The family opens in the Family Editor. Load into Project places it at the project origin on this view's level.") {
                DialogRow("Name") { TextField("", text: $name).labelsHidden() }
            }
        }
        .onAppear { if name.isEmpty { name = InPlaceFamilies.defaultName(state.model) } }
    }
}
