import SwiftUI
import ArcusDomain
import ArcusApplication

// FMG4: Associate Family Parameter (the small = button beside a property in Properties, as in a Revit-style Family
// Editor): pick the family parameter of a compatible type that sets the property, or make a new one; <None> removes
// the association. OK applies it in one undo step. Built on the dialog design system (Docs/Dialogs.md).

enum FMG4Dialog: Equatable {
    /// The property `property` (shown as `name`) of `elements`.
    case associate(elements: [ElementID], property: ParameterID, name: String)
}

struct FMG4DialogHost: View {
    let state: DocumentState
    let dialog: FMG4Dialog
    var body: some View {
        switch dialog {
        case .associate(let ids, let p, let n): AssociateFamilyParameterDialog(state: state, elements: ids, property: p, propertyName: n)
        }
    }
}

struct AssociateFamilyParameterDialog: View {
    let state: DocumentState
    let elements: [ElementID]
    let property: ParameterID
    let propertyName: String

    /// The chosen parameter; nil is <None>.
    @State private var choice: String?
    @State private var adding = false
    @State private var newName = ""
    @State private var newType: ParamType = .bool
    @State private var newIsInstance = false
    @State private var loaded = false

    init(state: DocumentState, elements: [ElementID], property: ParameterID, propertyName: String, startAdding: Bool = false, newName: String = "") {
        self.state = state; self.elements = elements; self.property = property; self.propertyName = propertyName
        _adding = State(initialValue: startAdding)
        _newName = State(initialValue: newName)
    }

    var element: Element? { elements.first.flatMap { state.model[$0] } }
    var types: [ParamType] { element.flatMap { FurnitureAssociations.compatibleTypes(property, $0) } ?? [] }
    var parameters: [FamilyParameter] { element.map { FurnitureAssociations.compatibleParameters(property, $0, state.model) } ?? [] }
    var typeText: String { types.isEmpty ? "Yes/No" : types.map(\.displayName).joined(separator: " or ") }
    var article: String { "aeiouAEIOU".contains(typeText.first ?? "x") ? "an" : "a" }
    var newNameProblem: String? {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Name the parameter." }
        if !FamilyEditing.isValidName(n) { return "Names can't contain [ ] or start with a space." }
        if state.model.furnitureSetup?.family.parameter(named: n) != nil { return "There is already a parameter named “\(n)”." }
        return nil
    }

    var body: some View {
        ArcusDialog(icon: "equal.square", title: "Associate Family Parameter", subtitle: "Each family type sets \(propertyName) through the parameter you choose.",
                    size: .medium, okDisabled: adding && newNameProblem != nil, disabledReason: adding ? newNameProblem : nil,
                    onCancel: { state.presented = nil }, onOK: apply) {
            DialogSection("Property") {
                DialogValueRow(label: "Property", value: propertyName)
                DialogValueRow(label: "Element", value: elementText)
                DialogValueRow(label: "Compatible types", value: typeText)
            }
            DialogSection("Family Parameters", rows: false) {
                list
            }
            DialogSection("New Parameter", footnote: adding ? nil : "Adds \(article) \(typeText) parameter to the family (Family Types) and associates it.") {
                if adding {
                    DialogRow("Name") {
                        TextField("Parameter name", text: $newName).textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: 260)
                    }
                    if types.count > 1 {
                        DialogRow("Type of parameter") {
                            Picker("Type of parameter", selection: $newType) { ForEach(types, id: \.self) { Text($0.displayName).tag($0) } }
                                .labelsHidden().fixedSize()
                        }
                    }
                    DialogRow("Varies by") {
                        PillSegmented(selection: $newIsInstance, [(false, "Type"), (true, "Instance")], label: "Varies by") // PILLS
                    }
                } else {
                    DialogRow("Parameter") {
                        Button("New Parameter…") { adding = true; newType = types.first ?? .bool }
                    }
                }
            }
        } leading: {
            if adding { Button("Back to List") { adding = false; newName = "" } }
        }
        .onAppear {
            guard !loaded, let e = element else { return }
            loaded = true
            choice = FurnitureAssociations.association(property, e)
            newType = types.first ?? .bool
        }
    }

    var elementText: String {
        guard let e = element else { return "—" }
        let what = e.furnitureFront.map { $0.kind.rawValue } ?? e.category.singularName
        let mark = e.mark.isEmpty ? "" : " \(e.mark)"
        return elements.count > 1 ? "\(elements.count) elements" : "\(what)\(mark)"
    }

    @ViewBuilder var list: some View {
        DialogListBox(count: parameters.count + 1, minRows: 2, maxRows: 7) {
            VStack(spacing: 0) {
                AssociateChoiceRow(title: "<None>", detail: "The property's own value", selected: choice == nil && !adding) { choice = nil; adding = false }
                ForEach(parameters, id: \.name) { p in
                    Divider()
                    AssociateChoiceRow(title: p.name, detail: "\(p.type.displayName) · \(p.isInstance ? "Instance" : "Type")", selected: choice == p.name && !adding) {
                        choice = p.name; adding = false
                    }
                }
            }
        }
        if parameters.isEmpty {
            DialogNotice(.info, "This family has no \(typeText) parameters yet. Make one with New Parameter.")
        }
    }

    func apply() {
        let ids = elements, prop = property
        var parameter = choice
        var newParam: FamilyParameter?
        if adding {
            let n = newName.trimmingCharacters(in: .whitespaces)
            newParam = FamilyParameter(name: n, type: newType, isInstance: newIsInstance, group: .construction)
            parameter = n
        }
        state.session.perform(parameter == nil ? "Remove Family Parameter Association" : "Associate Family Parameter") { tx in
            try FurnitureAssociations.associate(ids, prop, with: parameter, adding: newParam, in: tx)
        }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.presented = nil
    }
}

/// One selectable parameter in the list.
struct AssociateChoiceRow: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            DialogListRow(icon: selected ? "checkmark.circle.fill" : "circle", iconTint: selected ? .accentColor : .secondary, title: title) {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
