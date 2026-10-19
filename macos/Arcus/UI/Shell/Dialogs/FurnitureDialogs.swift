import SwiftUI
import AppKit
import ArcusCalc
import ArcusDomain
import ArcusApplication

// FM3: Furniture documents' Family Types, Family Category and Parameters, Flex results and Load into Projects
// dialogs, in the main shell. They work like the Family Editor's: edits are kept in the dialog until Apply or OK (one
// undoable "Family Types" change), Cancel discards them.

/// Sheets of the Furniture batch.
enum FM3Dialog: Equatable {
    case familyTypes, category
    /// Flex results (problems found; empty = every type flexed).
    case flex([String])
    /// Load into Projects: which open projects receive the piece; `close` closes the piece after loading.
    case loadInto(close: Bool)
}

struct FM3DialogHost: View {
    let state: DocumentState
    let dialog: FM3Dialog
    var body: some View {
        switch dialog {
        case .familyTypes: FurnitureTypesDialog(state: state)
        case .category: FurnitureCategoryDialog(state: state)
        case .flex(let problems): FurnitureFlexDialog(state: state, problems: problems)
        case .loadInto(let close): FurnitureLoadDialog(state: state, close: close)
        }
    }
}

/// A text field that commits on Return or when it loses focus, and follows outside changes while not being edited.
struct FurnitureField: View {
    let value: String
    var placeholder = ""
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = value }
            .onSubmit { if text != value { commit(text) } }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onChange(of: focused) { _, f in if !f && text != value { commit(text) } }
    }
}

// MARK: - Family Types

/// Family Types for the piece: the type list, every parameter with its value and formula, grouped as the Properties
/// palette groups them, and new parameters.
struct FurnitureTypesDialog: View {
    let state: DocumentState
    @State private var setup: FurnitureSetupData?
    /// Parameter renames made in the dialog (old → new), applied to plane formulas and labels on Apply.
    @State private var renames: [(String, String)] = []
    @State private var message: String?
    @State private var newName = ""
    @State private var newType: ParamType = .length
    @State private var newGroup: ParameterGroup = .dimensions
    @State private var newInstance = false

    var model: BIMModel { state.model }
    var edited: Bool { setup != nil && setup != model.furnitureSetup }

    var body: some View {
        let s = setup ?? model.furnitureSetup
        VStack(alignment: .leading, spacing: DialogMetrics.spacing) {
            DialogTitle(title: "Family Types", subtitle: s?.name ?? "")
            if let s {
                typeRow(s)
                parameterTable(s)
                newParameterRow(s)
            }
            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Flex") { flex() }.help("Try every type, and each length at 50% and 150%.")
                Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }.disabled(!edited)
                Button("OK") { apply(); state.presented = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(DialogMetrics.padding)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 440)
        .onAppear { if setup == nil { setup = model.furnitureSetup } }
    }

    // MARK: Types

    func typeRow(_ s: FurnitureSetupData) -> some View {
        HStack {
            Text("Type name").foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { s.currentType }, set: { t in setup?.currentType = t })) {
                ForEach(s.family.types) { Text($0.name).tag($0.name) }
            }
            .labelsHidden().frame(maxWidth: 280)
            Button { newTypeAsked(s) } label: { Image(systemName: "plus") }.help("New Type")
            Button { renameTypeAsked(s) } label: { Image(systemName: "pencil") }.help("Rename Type")
            Button { setup.map { var x = $0; if FamilyEditing.deleteType(&x.family, x.currentType) { x.currentType = x.family.types[0].name; setup = x } } } label: {
                Image(systemName: "trash")
            }
            .disabled(s.family.types.count <= 1).help("Delete Type")
            Spacer()
        }
    }

    func newTypeAsked(_ s: FurnitureSetupData) {
        guard let n = Self.ask("New Type", "Name", "\(s.currentType) 2") else { return }
        var x = s
        guard FamilyEditing.addType(&x.family, named: n, copying: s.currentType) else { message = "A type named “\(n)” already exists."; return }
        x.currentType = n
        setup = x
    }

    func renameTypeAsked(_ s: FurnitureSetupData) {
        guard let n = Self.ask("Rename Type", "Name", s.currentType) else { return }
        var x = s
        guard FamilyEditing.renameType(&x.family, s.currentType, to: n) else { message = "A type named “\(n)” already exists."; return }
        x.currentType = n
        setup = x
    }

    // MARK: Parameters

    func groups(_ s: FurnitureSetupData) -> [(ParameterGroup, [FamilyParameter])] {
        Dictionary(grouping: s.family.parameters, by: \.group).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func parameterTable(_ s: FurnitureSetupData) -> some View {
        let values = FamilyEvaluator.parameterValues(s.family, typeName: s.currentType, units: model.units).values
        return VStack(spacing: 0) {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Parameter"); Text("Value"); Text("Formula"); Text("Kind"); Text("")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(groups(s), id: \.0) { group, params in
                        GridRow {
                            Text(group.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary).gridCellColumns(5).padding(.top, 6)
                        }
                        ForEach(params) { p in parameterRow(p, s, value: values[p.name]) }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
    }

    @ViewBuilder func parameterRow(_ p: FamilyParameter, _ s: FurnitureSetupData, value: FormulaValue?) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Text(p.name).lineLimit(1)
                if p.isBuiltIn { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary).help("Built-in parameter") }
            }
            .frame(width: 160, alignment: .leading)
            valueCell(p, s, value: value).frame(width: 170)
            FurnitureField(value: p.formula ?? "", placeholder: "=") { f in
                let t = f.trimmingCharacters(in: .whitespaces)
                updateParameter(p.name) { $0.formula = t.isEmpty ? nil : t }
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 180)
            Picker("", selection: Binding(get: { p.isInstance }, set: { v in updateParameter(p.name) { $0.isInstance = v } })) {
                Text("Type").tag(false); Text("Instance").tag(true)
            }
            .labelsHidden().frame(width: 92)
            HStack(spacing: 2) {
                Button { renameParameterAsked(p) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).disabled(p.isBuiltIn).help("Rename Parameter")
                Button { deleteParameter(p) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).disabled(p.isBuiltIn).help("Delete Parameter")
            }
        }
    }

    @ViewBuilder func valueCell(_ p: FamilyParameter, _ s: FurnitureSetupData, value: FormulaValue?) -> some View {
        let raw = s.family.type(named: s.currentType)?.values[p.name] ?? p.type.defaultValue
        if p.formula != nil {
            Text(value.map { Parameters.format(FamilyEvaluator.paramValue($0, type: p.type), type: p.type, model: model) } ?? "")
                .foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if p.type == .bool {
            Toggle("", isOn: Binding(get: { raw.boolValue ?? false }, set: { setRaw(p, .bool($0)) })).labelsHidden().toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .elementRef(.materials) = p.type {
            Picker("", selection: Binding(get: { raw.refValue?.raw ?? 0 }, set: { v in setRaw(p, .ref(v == 0 ? nil : ElementID(v))) })) {
                Text("By Category").tag(UInt64(0))
                ForEach(model.elements(.materials).sorted { $0.name < $1.name }, id: \.id) { m in Text(m.name).tag(m.id.raw) }
            }
            .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FurnitureField(value: Parameters.format(raw, type: p.type, model: model)) { text in
                guard let v = try? Parameters.parse(text, type: p.type, model: model) else { message = "“\(text)” isn't a valid \(p.type.displayName.lowercased())."; return }
                if p.type == .length, (v.doubleValue ?? 0) <= 0 { message = "“\(p.name)” must be greater than zero."; return }
                setRaw(p, v)
            }
        }
    }

    func newParameterRow(_ s: FurnitureSetupData) -> some View {
        HStack {
            TextField("New parameter", text: $newName).textFieldStyle(.roundedBorder).frame(minWidth: 120, maxWidth: 190)
            Picker("", selection: $newType) { ForEach(ParamType.userCreatable, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden().fixedSize()
            Picker("", selection: $newGroup) { ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
            Toggle("Instance", isOn: $newInstance)
            Button("Add Parameter") { addParameter() }
                .disabled(!FamilyEditing.isValidName(newName) || s.family.parameter(named: newName.trimmingCharacters(in: .whitespaces)) != nil)
            Spacer()
        }
    }

    // MARK: Edits (kept in the dialog until Apply)

    func setRaw(_ p: FamilyParameter, _ v: ParamValue) {
        guard var x = setup, let i = x.family.types.firstIndex(where: { $0.name == x.currentType }) else { return }
        x.family.types[i].values[p.name] = v
        setup = x
    }

    func updateParameter(_ name: String, _ mutate: (inout FamilyParameter) -> Void) {
        guard var x = setup, let i = x.family.parameters.firstIndex(where: { $0.name == name }) else { return }
        mutate(&x.family.parameters[i])
        setup = x
    }

    func addParameter() {
        guard var x = setup else { return }
        let n = newName.trimmingCharacters(in: .whitespaces)
        x.family.parameters.append(FamilyParameter(name: n, type: newType, isInstance: newInstance, group: newGroup))
        setup = x
        newName = ""
    }

    func renameParameterAsked(_ p: FamilyParameter) {
        guard var x = setup, let n = Self.ask("Rename Parameter", "Name", p.name) else { return }
        guard FamilyEditing.renameParameter(&x.family, p.name, to: n) else { message = "“\(n)” can't be used as a parameter name."; return }
        renames.append((p.name, n))
        setup = x
    }

    func deleteParameter(_ p: FamilyParameter) {
        guard var x = setup else { return }
        FamilyEditing.deleteParameter(&x.family, p.name)
        setup = x
    }

    func flex() {
        guard let x = setup else { return }
        let problems = FurnitureParameters.flex(model, setup: x)
        message = problems.isEmpty ? "Every type flexes." : "\(problems.count) problem(s): \(problems[0])"
    }

    /// Commits the dialog's edits as one undoable change; the planes follow.
    func apply() {
        guard let x = setup, edited || !renames.isEmpty else { return }
        let done = renames
        state.session.perform("Family Types") { tx in
            for (old, new) in done { try Self.applyRename(old, new, in: tx) }
            try FurnitureParameters.edit(tx) { $0 = x }
        }
        renames = []
        if let e = state.session.lastError { message = e.message } else { setup = state.model.furnitureSetup }
    }

    /// A rename's side effects outside the setup: plane formulas and dimension labels.
    static func applyRename(_ old: String, _ new: String, in tx: TransactionContext) throws(TransactionError) {
        let known = tx.model.furnitureSetup?.family.parameters.map(\.name) ?? []
        for p in FurniturePlanes.all(tx.model) {
            guard let f = p.referencePlane?.furniture?.offsetFormula else { continue }
            let g = FamilyEditing.replacingName(in: f, old, with: new, known: known)
            if g != f { tx.update(p.id) { $0.referencePlane?.furniture?.offsetFormula = g } }
        }
        for d in tx.model.elements(.dimensions) where d.dimension?.labelParameter == old { tx.update(d.id) { $0.dimension?.labelParameter = new } }
    }

    static func ask(_ title: String, _ label: String, _ initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}

// MARK: - Family Category and Parameters

/// The piece's name, category (Furniture or Casework) and identity data.
struct FurnitureCategoryDialog: View {
    let state: DocumentState
    @State private var setup: FurnitureSetupData?

    var body: some View {
        DialogFrame(title: "Family Category and Parameters", state: state, onOK: commit) {
            if let s = setup {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Family Category").foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { s.family.template }, set: { setup?.family.template = $0 })) {
                            Text("Furniture").tag(FamilyTemplate.furniture)
                            Text("Casework").tag(FamilyTemplate.casework)
                        }
                        .pickerStyle(.radioGroup).labelsHidden()
                    }
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        TextField("", text: Binding(get: { s.family.name }, set: { setup?.family.name = $0 })).textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                    GridRow {
                        Text("Description").foregroundStyle(.secondary)
                        TextField("", text: Binding(get: { s.family.description }, set: { setup?.family.description = $0 })).textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                    GridRow {
                        Text("Manufacturer").foregroundStyle(.secondary)
                        TextField("", text: Binding(get: { s.family.manufacturer }, set: { setup?.family.manufacturer = $0 })).textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                    GridRow {
                        Text("Shared").foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(get: { s.family.isShared }, set: { setup?.family.isShared = $0 })).labelsHidden()
                    }
                }
                Text("Projects schedule and tag the piece by its category.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 460)
        .onAppear { if setup == nil { setup = state.model.furnitureSetup } }
    }

    func commit() {
        guard var s = setup else { state.presented = nil; return }
        s.family.name = s.family.name.trimmingCharacters(in: .whitespaces)
        if s.family.name.isEmpty { s.family.name = state.model.furnitureSetup?.name ?? "Furniture" }
        if s != state.model.furnitureSetup {
            state.session.perform("Family Category and Parameters") { tx in try FurnitureParameters.edit(tx) { $0 = s } }
            state.updateWindowSubtitle()
        }
        state.presented = nil
    }
}

// MARK: - Flex

struct FurnitureFlexDialog: View {
    let state: DocumentState
    let problems: [String]
    var body: some View {
        DialogFrame(title: "Flex", subtitle: state.model.furnitureSetup?.name ?? "", okTitle: "Done", showCancel: false, state: state, onOK: { state.presented = nil }) {
            if problems.isEmpty {
                Label("Every type flexes: each length at 50% and 150% solves.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Text("\(problems.count) problem(s)").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, p in
                            Label(p, systemImage: "exclamationmark.triangle.fill").labelStyle(.titleAndIcon).font(.callout)
                                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
        }
        .frame(width: 520)
    }
}

// MARK: - Load into Projects

/// Choose which open projects receive the piece (shown when more than one project is open).
struct FurnitureLoadDialog: View {
    let state: DocumentState
    let close: Bool
    @State private var chosen: Set<ObjectIdentifier> = []

    var body: some View {
        let projects = FurnitureLoad.openProjects()
        DialogFrame(title: "Load into Projects", subtitle: "Check the projects to load “\(state.model.furnitureSetup?.name ?? "")” into.", okTitle: "OK",
                    okDisabled: chosen.isEmpty, state: state, onOK: { load(projects) }) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(projects, id: \.fm3ID) { p in
                    Toggle(p.documentName, isOn: Binding(get: { chosen.contains(p.fm3ID) }, set: { v in if v { chosen.insert(p.fm3ID) } else { chosen.remove(p.fm3ID) } }))
                        .toggleStyle(.checkbox)
                }
            }
        }
        .frame(width: 420)
        .onAppear { if chosen.isEmpty, let first = projects.first { chosen = [first.fm3ID] } }
    }

    func load(_ projects: [DocumentState]) {
        let targets = projects.filter { chosen.contains($0.fm3ID) }
        state.presented = nil
        FurnitureLoad.load(state, into: targets, close: close)
    }
}

extension DocumentState {
    /// Identity for lists of open documents.
    var fm3ID: ObjectIdentifier { ObjectIdentifier(self) }
}
