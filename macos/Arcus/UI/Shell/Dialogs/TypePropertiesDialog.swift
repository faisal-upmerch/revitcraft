import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// BL-PROPS: Type Properties — Family and Type rows with Duplicate… / Rename…, collapsible parameter groups in
/// reference order with the structure editor inside Construction, and OK / Cancel / Apply over staged edits
/// (`TypePropertiesEditor`). Return in a field commits that field; ⌘Return is OK; Esc is Cancel.
struct TypePropertiesDialog: View {
    let state: DocumentState
    @State private var editor: TypePropertiesEditor
    @State private var collapsed: Set<ParameterGroup> = []
    @State private var prompt: NamePrompt?

    enum NamePrompt: String, Identifiable { case duplicate, rename; var id: String { rawValue } }

    init(state: DocumentState, typeID: ElementID) {
        self.state = state
        // Opened from a selection: OK gives those elements the type shown (after Duplicate or a Type switch).
        let targets = state.activeTool == nil ? state.session.selection.ids : []
        _editor = State(initialValue: TypePropertiesEditor(session: state.session, typeID: typeID, assignTo: targets))
    }

    var body: some View {
        let _ = state.session.changeCounter
        let t = editor.type
        ArcusDialog(icon: "square.grid.2x2", tint: .blue, title: "Type Properties", subtitle: subtitle, size: .wide, labelWidth: 70, height: 640,
                    onCancel: { editor.cancel(); state.presented = nil }, onOK: { ok() }) {
            DialogSection {
                DialogRow("Family") { Text(t.map { PaletteLayout.familyLabel($0) } ?? "").textSelection(.enabled) }
                DialogRow("Type") {
                    HStack {
                        Picker("", selection: Binding(get: { editor.typeID }, set: { editor.show($0) })) {
                            ForEach(editor.siblingTypes, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 320)
                        .accessibilityLabel("Type")
                        Button("Duplicate…") { prompt = .duplicate }
                            .popover(item: Binding(get: { prompt == .duplicate ? prompt : nil }, set: { prompt = $0 })) { _ in
                                NamePromptView(title: "Name", initial: editor.suggestedDuplicateName, okTitle: "Duplicate") { name throws(ParameterError) in
                                    try editor.duplicate(named: name)
                                } dismiss: { prompt = nil }
                            }
                        Button("Rename…") { prompt = .rename }
                            .popover(item: Binding(get: { prompt == .rename ? prompt : nil }, set: { prompt = $0 })) { _ in
                                NamePromptView(title: "New name", initial: t?.name ?? "", okTitle: "Rename") { name throws(ParameterError) in
                                    try editor.rename(name)
                                } dismiss: { prompt = nil }
                            }
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.0) { group, entries in
                        Section {
                            if !collapsed.contains(group) {
                                if group == .construction, let a = t?.typeData?.assembly {
                                    AssemblyEditor(state: state, assembly: a, isWall: t?.typeData?.instanceCategory == .walls,
                                                   isToposolid: t?.typeData?.systemFamily == .toposolid) { a in
                                        do throws(ParameterError) { try editor.stage(assembly: a); return nil } catch { return error.message }
                                    }
                                    .id(editor.typeID)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                }
                                if group == .construction, let st = t?.typeData?.stack { // F2: stacked walls
                                    StackedWallEditor(state: state, model: editor.preview, spec: st) { s in
                                        do throws(ParameterError) { try editor.stage(stack: s); return nil } catch { return error.message }
                                    }
                                    .id(editor.typeID)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                }
                                ForEach(entries, id: \.id) { e in
                                    ParamRow(state: state, entry: e, targets: [editor.typeID], labelWidth: 190) { id, v throws(ParameterError) in
                                        try editor.stage(id, value: v)
                                    }
                                    Divider().opacity(0.35)
                                }
                            }
                        } header: { header(group) }
                    }
                }
            }
            .frame(minHeight: 320, maxHeight: .infinity)
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
        } trailing: {
            Button("Apply") { if !editor.apply() { reportError() } }
                .disabled(!editor.hasChanges)
                .help("Save the changes and keep the dialog open")
                .dialogButton()
        }
        .okKeyboardShortcut(KeyboardShortcut(.return, modifiers: .command)) // OK is ⌘Return: Return commits the field being edited
    }

    var groups: [(ParameterGroup, [ParameterEntry])] {
        guard let t = editor.type else { return [] }
        var order: [ParameterGroup] = []
        var by: [ParameterGroup: [ParameterEntry]] = [:]
        for e in PaletteLayout.typeEntries(t, editor.preview) {
            if by[e.group] == nil { order.append(e.group) }
            by[e.group, default: []].append(e)
        }
        if t.typeData?.assembly != nil || t.typeData?.stack != nil, by[.construction] == nil { order.append(.construction); by[.construction] = [] } // F2: stack
        return order.sorted().map { ($0, by[$0]!) }
    }

    var subtitle: String {
        if editor.isStagedDuplicate(editor.typeID) { return "New type. It is created when you click Apply or OK." }
        let n = state.model.instanceCount(ofType: editor.typeID)
        return "Changes apply to every instance of this type (\(n) instance\(n == 1 ? "" : "s"))."
    }

    func header(_ group: ParameterGroup) -> some View {
        Button {
            if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
        } label: {
            HStack {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed.contains(group) ? 0 : 90))
                Text(group.rawValue).font(.system(size: 11.5, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.rawValue), \(collapsed.contains(group) ? "collapsed" : "expanded")")
    }

    func ok() {
        let shown = editor.typeID
        guard editor.ok() else { reportError(); return }
        // Placing elements: the type shown becomes the tool's type.
        if state.activeTool != nil, let cat = state.model[editor.typeID]?.typeData?.instanceCategory, editor.typeID != shown || state.placementCategory == cat {
            state.currentTypes[cat] = editor.typeID
            if cat.isComponentCategory { state.currentTypes[.furniture] = editor.typeID }
            for c in state.toolContexts.values { c.currentTypes = state.currentTypes }
            state.toolChangedState()
        }
        state.palette.recentTypes = TypeSelectorModel.noteUse(editor.typeID, in: state.palette.recentTypes)
        state.presented = nil
    }

    func reportError() {
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
    }
}

/// Name entry for Duplicate… and Rename…: validates inline; Cancel (or Esc) changes nothing.
struct NamePromptView: View {
    let title: String
    let initial: String
    let okTitle: String
    let commit: (String) throws(ParameterError) -> Void
    let dismiss: () -> Void
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(title, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .focused($focused)
                .onSubmit(ok)
                .onChange(of: name) { _, _ in error = nil }
            if let error { Label(error, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button(okTitle, action: ok).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .onAppear { name = initial; focused = true }
    }

    func ok() {
        do { try commit(name); dismiss() } catch { self.error = error.message }
    }
}
