import SwiftUI
import ArcusDomain
import ArcusApplication

// FMG4: Associate Family Parameter (the small = button beside a property in Properties, as in a Revit-style Family
// Editor): pick the family parameter of a compatible type that sets the property, or make a new one; <None> removes
// the association. OK applies it in one undo step.

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
    var article: String { "aeiouAEIOU".contains(typeText.first ?? "x") ? "an" : "a" }
    var typeText: String { types.map(\.displayName).joined(separator: " or ") }
    var newNameProblem: String? {
        let n = newName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Name the parameter." }
        if !FamilyEditing.isValidName(n) { return "Names can't contain [ ] or start with a space." }
        if state.model.furnitureSetup?.family.parameter(named: n) != nil { return "There is already a parameter named “\(n)”." }
        return nil
    }

    var body: some View {
        DialogChrome {
            VStack(alignment: .leading, spacing: DialogMetrics.spacing) {
                header
                AssociateSection(title: "Property") {
                    AssociateRow(label: "Property") { Text(propertyName) }
                    AssociateRow(label: "Element") { Text(elementText).foregroundStyle(.secondary) }
                    AssociateRow(label: "Compatible types") { Text(typeText).foregroundStyle(.secondary) }
                }
                AssociateSection(title: "Family Parameters") {
                    list
                }
                AssociateSection(title: "New Parameter") {
                    if adding {
                        AssociateRow(label: "Name") {
                            TextField("Parameter name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 220)
                        }
                        if types.count > 1 {
                            AssociateRow(label: "Type of parameter") {
                                Picker("", selection: $newType) { ForEach(types, id: \.self) { Text($0.displayName).tag($0) } }
                                    .labelsHidden().fixedSize()
                            }
                        }
                        AssociateRow(label: "Varies by") {
                            Picker("", selection: $newIsInstance) { Text("Type").tag(false); Text("Instance").tag(true) }
                                .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        if let p = newNameProblem, !newName.isEmpty { FMG4Notice(text: p) }
                    } else {
                        HStack {
                            Text("Add \(article) \(typeText) parameter to the family and associate it.").foregroundStyle(.secondary)
                            Spacer()
                            Button("New Parameter…") { adding = true; newType = types.first ?? .bool }
                        }
                    }
                }
            }
            .padding(DialogMetrics.padding)
        } buttons: {
            DialogButtonRow(okDisabled: adding && newNameProblem != nil, onCancel: { state.presented = nil }, onOK: apply) {
                if adding { Button("Back to List") { adding = false; newName = "" } }
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !loaded, let e = element else { return }
            loaded = true
            choice = FurnitureAssociations.association(property, e)
            newType = types.first ?? .bool
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "equal.square.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
            DialogTitle(title: "Associate Family Parameter", subtitle: "Each family type sets \(propertyName) through the parameter you choose.")
        }
    }

    var elementText: String {
        guard let e = element else { return "—" }
        let what = e.furnitureFront.map { $0.kind.rawValue } ?? e.category.singularName
        let mark = e.mark.isEmpty ? "" : " \(e.mark)"
        return elements.count > 1 ? "\(elements.count) elements" : "\(what)\(mark)"
    }

    @ViewBuilder var list: some View {
        VStack(spacing: 0) {
            AssociateChoiceRow(title: "<None>", detail: "The property's own value", selected: choice == nil && !adding) { choice = nil; adding = false }
            ForEach(parameters, id: \.name) { p in
                Divider()
                AssociateChoiceRow(title: p.name, detail: "\(p.type.displayName) · \(p.isInstance ? "Instance" : "Type")", selected: choice == p.name && !adding) {
                    choice = p.name; adding = false
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        if parameters.isEmpty {
            Text("No \(typeText) parameters in this family yet. Make one with New Parameter.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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

/// A titled group of rows on a rounded background (the dialog's sections).
struct AssociateSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DialogMetrics.sectionHeader).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}

/// A label and its value, labels aligned in one column.
struct AssociateRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
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
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(title)
                Spacer()
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A short notice under a field (instead of raw coloured text).
struct FMG4Notice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
    }
}
