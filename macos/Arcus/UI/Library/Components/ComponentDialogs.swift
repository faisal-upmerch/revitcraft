import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// COMP: the Component Library's dialogs, on the dialog design system (Docs/Dialogs.md): the one-click hardware
// confirmation (what will be added, where, and the rule findings), Insert Assembly, Hardware Rules, Save Selection as
// Component, Save as Preset and Update Components.

enum COMPDialog: Equatable {
    case action(ComponentAction, [ElementID])
    case assembly(ElementID)
    case hardwareRules
    case saveSelection([ElementID])
    case savePreset(String)
    case update
}

struct COMPDialogHost: View {
    let state: DocumentState
    let dialog: COMPDialog
    var body: some View {
        switch dialog {
        case .action(let a, let ids): ComponentActionDialog(state: state, action: a, ids: ids)
        case .assembly(let bay): ComponentAssemblyDialog(state: state, bayID: bay)
        case .hardwareRules: HardwareRulesDialog(state: state)
        case .saveSelection(let ids): SaveSelectionComponentDialog(state: state, ids: ids)
        case .savePreset(let id): SaveComponentPresetDialog(state: state, definitionID: id)
        case .update: UpdateComponentsDialog(state: state)
        }
    }
}

// MARK: - One-click hardware

struct ComponentActionDialog: View {
    let state: DocumentState
    let action: ComponentAction
    let ids: [ElementID]

    var plan: ComponentActionPlan { ComponentActions.plan(action, for: ids, state.model, catalog: ComponentLibraryStore.shared.catalog) }

    var body: some View {
        let p = plan
        let what = ids.count == 1 ? state.model[ids[0]].map { $0.mark.isEmpty ? $0.category.singularName : $0.mark } ?? "the selection" : "\(ids.count) elements"
        DialogFrame(title: action.rawValue, icon: action.symbol, tint: .brown, subtitle: "On \(what). Check what will be added, then add it.",
                    okTitle: "Add", okDisabled: p.isEmpty, disabledReason: "Nothing to add", state: state) { apply(p) } content: {
            DialogSection("Will Add", rows: false) {
                if p.lines.isEmpty {
                    DialogEmptyState(icon: "tray", title: "Nothing to Add", message: "The selection already has it, or nothing in the library fits.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(p.lines.enumerated()), id: \.offset) { k, l in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: action.symbol).foregroundStyle(.brown).frame(width: 18)
                                Text(l).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            if k < p.lines.count - 1 { Divider().padding(.leading, 36) }
                        }
                    }
                }
            }
            if action == .hinges { DialogNotice(.info, "Hinges per door follow Manage ▸ Hardware Rules (\(ruleText)).") }
            ForEach(Array(p.notes.enumerated()), id: \.offset) { _, n in DialogNotice(n.contains("too") || n.contains("isn't") || n.contains("needs") ? .warning : .info, n) }
        }
    }

    var ruleText: String {
        let r = ComponentRules.hingeRule(state.model)
        return r.steps.map { "\($0.count) up to \(FurnitureSizeText.inches($0.upTo))" }.joined(separator: ", ") + ", then \(r.maximumCount)"
    }

    func apply(_ p: ComponentActionPlan) {
        var placed: [ElementID] = []
        state.session.perform(action.rawValue) { tx in placed = try ComponentActions.apply(p, in: tx) }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        for it in p.items { ComponentLibraryStore.shared.used(it.definition.id) }
        state.presented = nil
        if !placed.isEmpty { state.session.selection.select(placed) }
        state.show("\(action.rawValue): \(p.lines.count) \(p.lines.count == 1 ? "change" : "changes").")
    }
}

// MARK: - Insert Assembly

struct ComponentAssemblyDialog: View {
    let state: DocumentState
    let bayID: ElementID
    @State private var chosen = ComponentAssembly.builtIn[0].id

    var assembly: ComponentAssembly { ComponentAssembly.builtIn.first { $0.id == chosen } ?? ComponentAssembly.builtIn[0] }

    var body: some View {
        let preview = ComponentAssemblies.preview(assembly, bay: bayID, state.model, catalog: ComponentLibraryStore.shared.catalog)
        let bayName = state.model[bayID].map { $0.name.isEmpty ? "the bay" : $0.name } ?? "the bay"
        DialogFrame(title: "Insert Assembly", icon: "square.stack.3d.up", tint: .brown, size: .large, subtitle: "A ready module for \(bayName), editable afterwards.",
                    okTitle: "Insert", okDisabled: preview.lines.isEmpty || preview.notes.contains { $0.hasPrefix("The bay already") || $0.hasPrefix("Pick") },
                    disabledReason: preview.notes.first ?? "Nothing to insert", state: state, onOK: insert) {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                DialogSection("Assemblies", rows: false) {
                    VStack(spacing: 0) {
                        ForEach(ComponentAssembly.builtIn) { a in
                            Button { chosen = a.id } label: {
                                DialogListRow(icon: a.symbol, iconTint: chosen == a.id ? .accentColor : .secondary, title: a.name, subtitle: a.summary)
                                    .padding(.horizontal, 10)
                                    .background(chosen == a.id ? Color.accentColor.opacity(0.14) : .clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen == a.id ? .isSelected : [])
                        }
                    }
                }
                .frame(width: 330)
                VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) {
                    DialogSection("Adds", rows: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(preview.lines, id: \.self) { l in Label(l, systemImage: "plus.circle").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(preview.notes, id: \.self) { n in DialogNotice(.warning, n) }
                }
            }
        }
    }

    func insert() {
        let a = assembly
        state.session.perform("Insert \(a.name)") { tx in _ = try ComponentAssemblies.insert(a, bay: bayID, in: tx, catalog: ComponentLibraryStore.shared.catalog) }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.presented = nil
        state.show("Inserted \(a.name).")
    }
}

// MARK: - Hardware Rules

struct HardwareRulesDialog: View {
    let state: DocumentState
    @State private var steps: [ComponentCountStep] = []
    @State private var maximum = 5
    @State private var inset = 3.0

    var body: some View {
        DialogFrame(title: "Hardware Rules", icon: "ruler", tint: .brown, subtitle: "How many hinges doors and flaps get by the length of their hinge edge.",
                    okTitle: "OK", state: state, onOK: save) {
            DialogSection("Hinges per Door", footnote: "Doors taller than the last height get \(maximum). The first and last hinges sit \(fmt(inset)) from the ends.") {
                ForEach(steps.indices, id: \.self) { k in
                    DialogRow(k == 0 ? "Up to" : "Then up to") {
                        HStack(spacing: 6) {
                            TextField("", value: Binding(get: { steps[k].upTo / 0.0254 }, set: { steps[k].upTo = $0 * 0.0254 }), format: .number)
                                .labelsHidden().frame(width: 56)
                            Text("in").foregroundStyle(.secondary)
                            Stepper(value: Binding(get: { steps[k].count }, set: { steps[k].count = $0 }), in: 1...9) { Text("\(steps[k].count) hinges").monospacedDigit() }
                        }
                    }
                }
                DialogRow("Taller") {
                    Stepper(value: $maximum, in: 1...12) { Text("\(maximum) hinges").monospacedDigit() }
                }
                DialogRow("End inset") {
                    HStack(spacing: 6) {
                        TextField("", value: $inset, format: .number).labelsHidden().frame(width: 56)
                        Text("in").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            let r = ComponentRules.hingeRule(state.model)
            steps = r.steps; maximum = r.maximumCount; inset = r.inset / 0.0254
        }
    }

    func fmt(_ inches: Double) -> String { FurnitureSizeText.inches(inches * 0.0254) }

    func save() {
        let rule = ComponentCountRule(steps: steps.sorted { $0.upTo < $1.upTo }, maximumCount: maximum, inset: inset * 0.0254)
        state.session.perform("Hardware Rules") { tx in ComponentRules.setHingeRule(rule == .hinges ? nil : rule, in: tx) }
        state.presented = nil
    }
}

// MARK: - Save Selection as Component

struct SaveSelectionComponentDialog: View {
    let state: DocumentState
    let ids: [ElementID]
    @State private var name = ""
    @State private var category: ComponentCategory = .decorative
    @State private var subcategory = "Modules"
    @State private var tags = ""
    @State private var error: String?

    var body: some View {
        DialogFrame(title: "Save Selection as Component", icon: "square.and.arrow.down.on.square", tint: .brown,
                    subtitle: "\(ids.count) selected \(ids.count == 1 ? "element" : "elements") become a component in My Components.",
                    okTitle: "Save", okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, disabledReason: "Enter a name", state: state, onOK: save) {
            DialogSection(footnote: "Built-in components stay read-only; yours can be edited, duplicated and deleted.") {
                DialogRow("Name") { TextField("", text: $name).labelsHidden() }
                DialogRow("Category") {
                    Picker("", selection: $category) { ForEach(ComponentCategory.allCases) { Text("\($0.code) \($0.title)").tag($0) } }.labelsHidden().fixedSize()
                }
                DialogRow("Subcategory") { TextField("", text: $subcategory).labelsHidden() }
                DialogRow("Search tags") { TextField("", text: $tags, prompt: Text("Comma-separated")).labelsHidden() }
            }
            if let error { DialogNotice(.error, error) }
        }
        .onAppear { name = "\(state.documentName) Module" }
    }

    func save() {
        do {
            let t = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            let d = try ComponentUserLibrary.fromSelection(ids, in: state.model, name: name.trimmingCharacters(in: .whitespaces), category: category,
                                                           subcategory: subcategory, tags: t)
            try ComponentLibraryStore.shared.addUserComponent(d)
            ComponentPanelModel.of(state).isShown = true
            ComponentPanelModel.of(state).section = .mine
            ComponentPanelModel.of(state).select(id: d.id)
            state.presented = nil
            state.onWorkspaceChange?()
            state.show("Saved \(d.name) to My Components.")
        } catch {
            self.error = DialogErrorText.describe(error)
        }
    }
}

// MARK: - Save as Preset

struct SaveComponentPresetDialog: View {
    let state: DocumentState
    let definitionID: String
    @State private var name = ""

    var body: some View {
        let model = ComponentPanelModel.of(state)
        let d = model.store.catalog.definition(id: definitionID)
        DialogFrame(title: "Save as Preset", icon: "bookmark", tint: .brown, size: .small, subtitle: d.map { "\($0.name) : \(model.selectedType ?? "")" } ?? "",
                    okTitle: "Save", okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, disabledReason: "Enter a name", state: state) {
            guard let d else { return }
            model.store.savePreset(ComponentPreset(name: name.trimmingCharacters(in: .whitespaces), definitionID: d.id, typeName: model.selectedType ?? d.defaultType?.name ?? "",
                                                   values: model.presetValues))
            model.presetName = name
            state.presented = nil
        } content: {
            DialogSection(footnote: "A preset keeps the type and settings, for placing it the same way again.") {
                DialogRow("Name") { TextField("", text: $name).labelsHidden() }
            }
        }
        .onAppear { name = model.selectedType ?? "" }
    }
}

// MARK: - Update Components

struct UpdateComponentsDialog: View {
    let state: DocumentState

    var body: some View {
        let loaded = ComponentDocument.loaded(state.model, catalog: ComponentLibraryStore.shared.catalog)
        let outdated = loaded.filter(\.isOutdated), missing = loaded.filter(\.isMissing)
        DialogFrame(title: "Update Components", icon: "arrow.down.circle", tint: .brown, subtitle: "\(loaded.count) components in this document.",
                    okTitle: "Update", okDisabled: outdated.isEmpty, disabledReason: "Everything is up to date", state: state, onOK: update) {
            DialogSection("Newer in the Library", rows: false) {
                if outdated.isEmpty {
                    DialogEmptyState(icon: "checkmark.circle", title: "Up to Date", message: "Every component matches the library.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(outdated, id: \.familyID) { l in
                            DialogListRow(icon: "arrow.down.circle", iconTint: .accentColor, title: state.model[l.familyID]?.name ?? l.definitionID,
                                          subtitle: l.loadedVersion == 0 ? "New types from the library" : "Version \(l.loadedVersion) → \(l.libraryVersion ?? l.loadedVersion)")
                                .padding(.horizontal, 10)
                        }
                    }
                }
            }
            if !missing.isEmpty {
                DialogNotice(.info, title: "Not in the library", "\(missing.count) \(missing.count == 1 ? "component isn't" : "components aren't") in your library any more. They keep working as they are.")
            }
        }
    }

    func update() {
        var n = 0
        state.session.perform("Update Components") { tx in n = ComponentDocument.upgradeAll(in: tx, catalog: ComponentLibraryStore.shared.catalog) }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.presented = nil
        state.show("Updated \(n) \(n == 1 ? "component" : "components").")
    }
}
