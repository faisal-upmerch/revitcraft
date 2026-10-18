import SwiftUI
import ArcusDomain
import ArcusApplication

// F11: Associate Global Parameter, the button at the right of a parameter's value in Properties (RevitCraft rc-app
// properties.rs). A dimension's Value row labels the dimension with a length or angle global.

struct GlobalParameterAssociationButton: View {
    let state: DocumentState
    let entry: ParameterEntry
    let targets: [ElementID]

    var element: Element? { targets.count == 1 ? state.model[targets[0]] : nil }

    /// Globals that can drive this row, or nil when the row can't be associated.
    var choices: [GlobalParameter]? {
        guard let e = element, !entry.isType else { return nil }
        let m = state.model
        if entry.id == GlobalParameters.dimensionLabel {
            guard let d = e.dimension, d.kind == .linear || d.kind == .aligned, d.references.count == 2 else { return nil }
            return GlobalParameters.compatible(with: .length, m)
        }
        let associated = GlobalParameters.association(e.id, entry.id, m) != nil
        guard !entry.isReadOnly || associated, entry.type.isNumeric || entry.type == .bool || entry.type == .text else { return nil }
        return GlobalParameters.compatible(with: entry.type, m)
    }

    var body: some View {
        if let e = element, let choices {
            let current = GlobalParameters.association(e.id, entry.id, state.model)
            if !choices.isEmpty || current != nil {
                Menu {
                    Button("<None>") { associate(nil) }.disabled(current == nil)
                    Divider()
                    ForEach(choices) { g in
                        Button { associate(g.id) } label: {
                            if current?.id == g.id { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
                        }
                    }
                } label: {
                    Image(systemName: current == nil ? "globe" : "globe.badge.chevron.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(current == nil ? Color.secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(current.map { "Associated with the global parameter “\($0.name)”" } ?? "Associate Global Parameter")
                .accessibilityLabel("Associate global parameter with \(entry.name)")
            }
        }
    }

    func associate(_ globalID: String?) {
        guard let e = element else { return }
        let pid = entry.id
        state.f11Perform(globalID == nil ? "Remove Global Parameter Association" : "Associate Global Parameter") { tx in
            try GlobalParameters.associate(e.id, pid, with: globalID, in: tx)
        }
    }
}
