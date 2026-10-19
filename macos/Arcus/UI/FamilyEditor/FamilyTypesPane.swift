import SwiftUI
import AppKit
import ArcusCalc
import ArcusDomain

// W4-FAMED: the Family Types dialog (types, values per type, formulas, parameter kind/group, new parameters) and the
// Family Category and Parameters dialog, presented as sheets from the ribbon, toolbar and Properties.

/// Family Types: the type list plus every parameter with value, formula and kind, in a resizable table that reflows.
struct FamilyTypesDialog: View {
    @Bindable var model: FamilyEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var newParamName = ""
    @State private var newParamType: ParamType = .length
    @State private var newParamInstance = false
    @State private var newParamGroup: ParameterGroup = .dimensions
    @State private var tableSelection: String?
    /// F1415: the family as it was when the dialog opened; Cancel restores it (RevitCraft's Family Types is modal).
    @State private var opened: (family: FamilyDefinition, type: String)?

    var sorted: [FamilyParameter] { model.family.parameters.sorted { ($0.group, $0.name) < ($1.group, $1.name) } }

    var body: some View {
        ArcusDialog(icon: "square.grid.2x2", tint: .purple, title: "Family Types", subtitle: model.family.name, size: .extraWide, height: 600,
                    onCancel: { // F1415
                        if let o = opened, o.family != model.family {
                            model.edit("Cancel Family Types") { $0 = o.family }
                            model.currentType = model.family.type(named: o.type) != nil ? o.type : (model.family.types.first?.name ?? "")
                        }
                        dismiss()
                    }, onOK: { dismiss() }) {
            DialogSection {
            HStack {
                Text("Type name").frame(width: 80, alignment: .leading)
                Picker("", selection: $model.currentType) { ForEach(model.family.types) { Text($0.name).tag($0.name) } }
                    .labelsHidden().frame(maxWidth: 300)
                Button("New…") { model.newType(copying: false) }.help("Create a type with the current type's values.")
                Button("Duplicate…") { model.newType(copying: true) }
                Button("Rename…") { model.renameType() }
                Button("Delete") { model.deleteType() }.disabled(model.family.types.count <= 1)
                Spacer()
                Button { model.undo.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.undo.canUndo).help("Undo")
                Button { model.undo.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.undo.canRedo).help("Redo")
            }
            .controlSize(.small)
            }
            Table(sorted, selection: $tableSelection) {
                TableColumn("Parameter") { p in
                    HStack(spacing: 4) {
                        Text(p.name).lineLimit(1)
                        if p.isBuiltIn { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary).help("Built-in parameter") }
                    }
                }
                .width(min: 120, ideal: 170)
                TableColumn("Value") { p in FamilyValueCell(model: model, parameter: p) }
                    .width(min: 100, ideal: 140)
                TableColumn("Formula") { p in
                    ValueField(text: p.formula ?? "", placeholder: "=") { f in
                        let t = f.trimmingCharacters(in: .whitespaces)
                        model.updateParameter(p.name, "Formula") { $0.formula = t.isEmpty ? nil : t }
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .width(min: 140, ideal: 220)
                TableColumn("Type") { p in Text(p.type.displayName).foregroundStyle(.secondary).lineLimit(1) }.width(min: 70, ideal: 90)
                TableColumn("Kind") { p in
                    Picker("", selection: Binding(get: { p.isInstance }, set: { v in model.updateParameter(p.name, v ? "Make Instance Parameter" : "Make Type Parameter") { $0.isInstance = v } })) {
                        Text("Type").tag(false); Text("Instance").tag(true)
                    }
                    .labelsHidden()
                }
                .width(min: 80, ideal: 96)
                TableColumn("Group") { p in
                    Picker("", selection: Binding(get: { p.group }, set: { g in model.updateParameter(p.name, "Change Parameter Group") { $0.group = g } })) {
                        ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                .width(min: 110, ideal: 150)
            }
            .contextMenu(forSelectionType: String.self) { names in
                if let n = names.first, let p = model.family.parameter(named: n) {
                    Button("Rename…") {
                        if let v = FamilyEditorModel.ask("Rename Parameter", "Name", p.name) { model.renameParameter(p.name, to: v) }
                    }.disabled(p.isBuiltIn)
                    Button("Show in Properties") { model.select(.parameter(n)); dismiss() }
                    Divider()
                    Button("Delete", role: .destructive) { model.deleteParameter(p) }.disabled(p.isBuiltIn)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            .frame(minHeight: 220, maxHeight: .infinity)
            DialogSection("New parameter", footnote: "Formulas use parameter names, units (600 mm, 2'), + − × ÷, if(), and(), not(), sin() in degrees, sqrt() and more; cycles are reported. A formula-driven parameter can't be set per type. Renaming a parameter updates the formulas, labels and bindings that use it. Every change is undoable (⌘Z).") {
            HStack {
                TextField("Name", text: $newParamName).textFieldStyle(.roundedBorder).frame(minWidth: 120, maxWidth: 200)
                Picker("", selection: $newParamType) { ForEach(ParamType.userCreatable, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden().fixedSize()
                Picker("", selection: $newParamGroup) { ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
                Toggle("Instance", isOn: $newParamInstance)
                Button("Add Parameter") {
                    model.addParameter(name: newParamName, type: newParamType, instance: newParamInstance, group: newParamGroup)
                    newParamName = ""
                }
                .disabled(!FamilyEditing.isValidName(newParamName) || model.family.parameter(named: newParamName.trimmingCharacters(in: .whitespaces)) != nil)
                Spacer()
            }
            }
            if let m = model.message { DialogNotice(.info, m) }
        } leading: {
            Button("Flex Test") { model.flex() }
            if let sel = tableSelection, let p = model.family.parameter(named: sel) {
                Button("Rename…") { if let v = FamilyEditorModel.ask("Rename Parameter", "Name", p.name) { model.renameParameter(p.name, to: v) } }.disabled(p.isBuiltIn)
                Button("Delete", role: .destructive) { model.deleteParameter(p) }.disabled(p.isBuiltIn)
            }
        }
        .opaqueDialogBackground()
        .onAppear { if opened == nil { opened = (model.family, model.currentType) } }
    }
}

/// Family Category and Parameters: category, tagged categories, shared flag and identity data.
struct FamilyCategoryDialog: View {
    @Bindable var model: FamilyEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ArcusDialog(icon: "cube", tint: .purple, title: "Family Category and Parameters", subtitle: model.family.name, labelWidth: 120, okTitle: "Done", showCancel: false,
                    onCancel: { dismiss() }, onOK: { dismiss() }) {
            DialogSection("Family category", footnote: model.family.template.is3D ? "Only 3D categories are offered; the geometry stays as it is. Hosted templates (door, window) keep the wall opening."
                                                                                : "Only 2D (annotation) categories are offered.") {
                DialogRow("Category") {
                    Picker("", selection: Binding(get: { model.family.template }, set: { t in model.edit("Change Category") { $0.template = t } })) {
                        ForEach(FamilyTemplate.allCases.filter { $0.is3D == model.family.template.is3D }, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 260)
                }
                if model.family.template == .tag {
                    DialogValueRow(label: "Tags categories", value: model.family.taggedCategories.map(\.rawValue).joined(separator: ", "))
                }
            }
            DialogSection("Identity") {
                DialogRow("Shared") {
                    Toggle("", isOn: Binding(get: { model.family.isShared }, set: { v in model.edit(v ? "Make Shared" : "Make Not Shared") { $0.isShared = v } })).labelsHidden()
                }
                DialogRow("Description") {
                    TextField("", text: Binding(get: { model.family.description }, set: { v in model.edit("Edit Description") { $0.description = v } })).labelsHidden()
                }
                DialogRow("Manufacturer") {
                    TextField("", text: Binding(get: { model.family.manufacturer }, set: { v in model.edit("Edit Manufacturer") { $0.manufacturer = v } })).labelsHidden()
                }
            }
            DialogSection("Family parameters", footnote: "Add, rename and delete parameters in Family Types.", boxed: false) {
            DialogListBox(count: model.family.parameters.count, rowHeight: 30, minRows: 2, maxRows: 6) {
            List(model.family.parameters) { p in
                HStack {
                    Text(p.name)
                    Text(p.type.displayName).foregroundStyle(.secondary)
                    Text(p.isInstance ? "Instance" : "Type").foregroundStyle(.tertiary)
                    Spacer()
                    Text(p.group.rawValue).font(.caption).foregroundStyle(.tertiary)
                    Button("Edit") { model.select(.parameter(p.name)); dismiss() }.controlSize(.small)
                }
            }
            }
            }
        } leading: {
            Button("Family Types…") { model.sheet = .familyTypes }
        }
        .opaqueDialogBackground()
    }
}
