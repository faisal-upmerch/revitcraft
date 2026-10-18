import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// F11: Manage dialogs (RevitCraft rc-app dialogs/manage.rs `global_params`, `keynoting`; dialogs/mod.rs
// `project_turn_dialog`, `add_to_set_dialog`, starting view and saved selections).

/// The F11–F13 dialogs presented through `DialogKind.f11`.
enum F11Dialog: Equatable {
    case globalParameters, specifyCoordinates(Vec3), projectTurn(mirror: Bool), addToSet, startingView
    case selectionSets(edit: Bool), keynotingSettings
    case combineParameters(ElementID), shading(ElementID, [ScheduleCellKey]), borders(ElementID, [ScheduleCellKey]), font(ElementID, [ScheduleCellKey])
    case splitAndPlace(ElementID)
    case printSetup, printPreview(Data, String), exportDWFx
}

struct F11DialogHost: View {
    let state: DocumentState
    let dialog: F11Dialog
    var body: some View {
        switch dialog {
        case .globalParameters: GlobalParametersDialog(state: state)
        case .specifyCoordinates(let p): SpecifyCoordinatesDialog(state: state, point: p)
        case .projectTurn(let mirror): ProjectTurnDialog(state: state, mirror: mirror)
        case .addToSet: AddToSetDialog(state: state)
        case .startingView: StartingViewDialog(state: state)
        case .selectionSets(let edit): SelectionSetsDialog(state: state, edit: edit)
        case .keynotingSettings: KeynotingSettingsDialog(state: state)
        case .combineParameters(let s): CombineParametersDialog(state: state, scheduleID: s)
        case .shading(let s, let keys): ScheduleShadingDialog(state: state, scheduleID: s, keys: keys)
        case .borders(let s, let keys): ScheduleBordersDialog(state: state, scheduleID: s, keys: keys)
        case .font(let s, let keys): ScheduleFontDialog(state: state, scheduleID: s, keys: keys)
        case .splitAndPlace(let s): SplitAndPlaceDialog(state: state, scheduleID: s)
        case .printSetup: PrintSetupDialog(state: state)
        case .printPreview(let data, let title): PrintPreviewDialog(state: state, pdf: data, title: title)
        case .exportDWFx: ExportDWFxDialog(state: state)
        }
    }
}

extension DocumentState {
    /// Runs a model change and reports a refusal in the status bar; true when it committed (or changed nothing).
    @discardableResult
    func f11Perform(_ name: String, _ build: (TransactionContext) throws -> Void) -> Bool {
        let r = session.perform(name, build)
        if r == nil, let e = session.lastError { show(e.message, error: true); session.clearError(); return false }
        return true
    }
}

// MARK: - Global Parameters

struct GlobalParametersDialog: View {
    let state: DocumentState
    @State private var list: [GlobalParameter] = []
    @State private var selected: String?
    @State private var newName = ""
    @State private var newType: ParamType = .length
    @State private var newGroup: ParameterGroup = .dimensions
    @State private var error: String?

    var groups: [ParameterGroup] { Array(Set(list.map(\.group))).sorted() }

    var body: some View {
        DialogFrame(title: "Global Parameters", subtitle: "Project-wide values that drive element parameters and dimensions. A formula computes a value from other global parameters.", state: state) {
            let l = list
            if state.f11Perform("Global Parameters", { tx in try GlobalParameters.set(l, in: tx) }) { state.presented = nil }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Parameter").frame(width: 170, alignment: .leading)
                    Text("Value").frame(width: 150, alignment: .leading)
                    Text("Formula").frame(width: 200, alignment: .leading)
                    Text("Type").frame(width: 90, alignment: .leading)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.self) { g in
                            Text(g.rawValue).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.05))
                            ForEach($list) { $p in
                                if p.group == g { row($p) }
                            }
                        }
                    }
                }
                .frame(height: 240)
                .overlay {
                    if list.isEmpty { Text("No global parameters. Add one below.").font(.callout).foregroundStyle(.secondary) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Button("Delete") { list.removeAll { $0.id == selected }; selected = nil }.disabled(selected == nil)
                Button("Move Up") { move(-1) }.disabled(index(selected).map { $0 == 0 } ?? true)
                Button("Move Down") { move(1) }.disabled(index(selected).map { $0 + 1 >= list.count } ?? true)
                Spacer()
            }
            GroupBox("New Global Parameter") {
                HStack {
                    TextField("Name", text: $newName).frame(width: 160)
                    Picker("Type", selection: $newType) { ForEach(GlobalParameters.types, id: \.self) { Text($0.displayName).tag($0) } }.frame(width: 160)
                    Picker("Group", selection: $newGroup) { ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 220)
                    Button("Add") {
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        guard !list.contains(where: { $0.name == n }) else { error = "A global parameter with this name already exists."; return }
                        let g = GlobalParameter(name: n, type: newType, group: newGroup)
                        list.append(g); selected = g.id; newName = ""; error = nil
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Associate an element parameter with the globe button beside its value in Properties; label a dimension from its Value row.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 680, idealWidth: 680)
        .onAppear { list = GlobalParameters.all(state.model) }
    }

    func index(_ id: String?) -> Int? { id.flatMap { i in list.firstIndex { $0.id == i } } }
    func move(_ d: Int) { guard let i = index(selected), i + d >= 0, i + d < list.count else { return }; list.swapAt(i, i + d) }

    @ViewBuilder func row(_ p: Binding<GlobalParameter>) -> some View {
        let g = p.wrappedValue
        HStack(spacing: 0) {
            TextField("", text: p.name).textFieldStyle(.plain).frame(width: 170, alignment: .leading)
            Group {
                if g.type == .bool {
                    Toggle("", isOn: Binding(get: { p.wrappedValue.value.boolValue ?? false }, set: { p.wrappedValue.value = .bool($0) })).labelsHidden().disabled(g.isComputed)
                } else {
                    GlobalValueField(state: state, parameter: p).disabled(g.isComputed)
                }
            }.frame(width: 150, alignment: .leading)
            TextField("=", text: Binding(get: { p.wrappedValue.formula ?? "" }, set: { p.wrappedValue.formula = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.plain).frame(width: 200, alignment: .leading).disabled(g.type == .text)
            Text(g.type.displayName).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(selected == g.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = g.id }
    }
}

/// A global's value typed with units ("2400", "2.4 m", "45°"); shown formatted.
private struct GlobalValueField: View {
    let state: DocumentState
    @Binding var parameter: GlobalParameter
    @State private var text = ""
    @FocusState private var focused: Bool
    var formatted: String { Parameters.format(parameter.value, type: parameter.type, model: state.model) }
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { text = formatted }
            .onChange(of: parameter.value) { _, _ in if !focused { text = formatted } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit { commit() }
    }
    func commit() {
        if let v = try? Parameters.parse(text, type: parameter.type, model: state.model) { parameter.value = v }
        text = formatted
    }
}

// MARK: - Coordinates and Position

struct SpecifyCoordinatesDialog: View {
    let state: DocumentState
    let point: Vec3
    @State private var ns = ""
    @State private var ew = ""
    @State private var elev = ""
    @State private var angle = ""
    @State private var error: String?
    var body: some View {
        DialogFrame(title: "Specify Shared Coordinates", subtitle: "The shared coordinates the picked point should read, and the angle from project north to true north.", state: state) {
            apply()
        } content: {
            Form {
                TextField("North/South", text: $ns)
                TextField("East/West", text: $ew)
                TextField("Elevation", text: $elev)
                TextField("Angle from project north to true north (°)", text: $angle)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .frame(minWidth: 460)
        .onAppear {
            let m = state.model
            let s = SharedCoordinates.shared(point, m.projectInfo)
            func f(_ v: Double) -> String { Parameters.format(.double(v), type: .length, model: m) }
            ns = f(s.northSouth); ew = f(s.eastWest); elev = f(s.elevation)
            angle = String(format: "%.2f", Angle.degrees(state.model.projectInfo.trueNorthAngle))
        }
    }
    func apply() {
        let m = state.model
        func len(_ s: String) -> Double? { (try? Parameters.parse(s, type: .length, model: m))?.doubleValue }
        guard let n = len(ns), let e = len(ew), let z = len(elev), let a = Double(angle.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)) else {
            error = "Type lengths (with units if you like) and an angle in degrees."; return
        }
        let p = point
        if state.f11Perform("Specify Coordinates at Point", { tx in
            guard let pid = tx.model.projectInfoElement?.id else { return }
            tx.update(pid) { el in
                guard var info = el.projectInfo else { return }
                SharedCoordinates.specify(at: p, reads: SharedPoint(northSouth: n, eastWest: e, elevation: z), trueNorth: Angle.radians(a), &info)
                el.projectInfo = info
            }
        }) {
            state.presented = nil
            state.show("The point now reads \(SharedCoordinates.report(SharedCoordinates.shared(p, state.model.projectInfo), state.model)).")
        }
    }
}

struct ProjectTurnDialog: View {
    let state: DocumentState
    let mirror: Bool
    @State private var pick = 0
    var choices: [String] { mirror ? ["Mirror North/South Axis", "Mirror East/West Axis"] : ["Rotate 90° Clockwise", "Rotate 90° Counterclockwise", "Rotate 180°"] }
    var body: some View {
        DialogFrame(title: mirror ? "Mirror Project" : "Rotate Project North",
                    subtitle: mirror ? "The whole project — model, views and their annotations — flips about the internal origin." : "The whole project turns about the internal origin; true north turns back so the site stays where it is.",
                    state: state) {
            let mirror = mirror, pick = pick
            if state.f11Perform(mirror ? "Mirror Project" : "Rotate Project North", { tx in
                if mirror { ProjectPosition.mirror(northSouth: pick == 0, in: tx) } else { ProjectPosition.rotate(degrees: [-90, 90, 180][min(pick, 2)], in: tx) }
            }) { state.presented = nil }
        } content: {
            Picker("", selection: $pick) { ForEach(choices.indices, id: \.self) { Text(choices[$0]).tag($0) } }.pickerStyle(.radioGroup).labelsHidden()
        }
    }
}

// MARK: - Design Options

struct AddToSetDialog: View {
    let state: DocumentState
    @State private var setName = ""
    @State private var chosen: Set<ElementID> = []
    var body: some View {
        let sets = DesignOptionEditing.sets(state.model)
        let options = sets.first { $0.name == setName }?.options ?? []
        DialogFrame(title: "Add to Design Option Set", subtitle: "The selected main model elements move into the first chosen option; every other chosen option gets its own copy.",
                    okDisabled: chosen.isEmpty, state: state) {
            let ids = state.session.selection.ids, opts = options.map(\.id).filter { chosen.contains($0) }
            if state.f11Perform("Add to Set", { tx in try DesignOptionEditing.addToSet(ids, options: opts, in: tx) }) { state.presented = nil }
        } content: {
            Picker("Design option set", selection: $setName) { ForEach(sets.map(\.name), id: \.self) { Text($0).tag($0) } }
                .onChange(of: setName) { _, n in chosen = Set(sets.first { $0.name == n }?.options.map(\.id) ?? []) }
            Text("Add selected elements to:").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                ForEach(options, id: \.id) { o in
                    Toggle(o.name + (o.designOption?.isPrimary == true ? " (primary)" : ""), isOn: Binding(get: { chosen.contains(o.id) }, set: { if $0 { chosen.insert(o.id) } else { chosen.remove(o.id) } }))
                }
            }
        }
        .frame(minWidth: 420)
        .onAppear { setName = sets.first?.name ?? ""; chosen = Set(sets.first?.options.map(\.id) ?? []) }
    }
}

// MARK: - Starting View

struct StartingViewDialog: View {
    let state: DocumentState
    @State private var choice: UInt64 = 0
    var body: some View {
        let m = state.model
        let views = m.sheets + m.views.sorted { ViewTitles.qualified($0) < ViewTitles.qualified($1) } + m.schedules
        DialogFrame(title: "Starting View", subtitle: "The view that opens when the project opens.", state: state) {
            let id = choice == 0 ? nil : ElementID(choice)
            if state.f11Perform("Starting View", { tx in StartingView.set(id, in: tx) }) { state.presented = nil }
        } content: {
            Picker("Starting view", selection: $choice) {
                Text("<Default: the first floor plan>").tag(UInt64(0))
                ForEach(views, id: \.id) { v in Text(ViewTitles.qualified(v)).tag(v.id.raw) }
            }
        }
        .frame(minWidth: 460)
        .onAppear { choice = m.manageData.startingViewID?.raw ?? 0 }
    }
}

// MARK: - Saved selections

struct SelectionSetsDialog: View {
    let state: DocumentState
    let edit: Bool
    @State private var selected: String?
    var body: some View {
        let _ = state.session.changeCounter
        let sets = state.model.manageData.selectionSets
        DialogFrame(title: edit ? "Edit Saved Selections" : "Load Saved Selection",
                    subtitle: edit ? "Rename or delete saved selections." : "Choose a saved selection to select its elements.",
                    okTitle: edit ? "Done" : "Load", okDisabled: !edit && selected == nil, showCancel: !edit, state: state) {
            if !edit, let s = selected {
                let ids = SavedSelections.elements(of: s, state.model)
                state.session.selection.select(ids)
                state.show(ids.isEmpty ? "The saved selection's elements no longer exist." : "Selected \(ids.count) element\(ids.count == 1 ? "" : "s").")
            }
            state.presented = nil
        } content: {
            List(sets, id: \.id, selection: $selected) { s in
                HStack {
                    if edit {
                        TextField("", text: Binding(get: { s.name }, set: { n in state.f11Perform("Rename Selection") { tx in try SavedSelections.rename(s.id, to: n, in: tx) } }))
                    } else { Text(s.name) }
                    Spacer()
                    Text("\(SavedSelections.elements(of: s.id, state.model).count) elements").font(.caption).foregroundStyle(.secondary)
                    if edit {
                        Button(role: .destructive) { state.f11Perform("Delete Selection") { tx in SavedSelections.delete(s.id, in: tx) } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }.tag(s.id)
            }
            .frame(minHeight: 200)
            .overlay { if sets.isEmpty { Text("No saved selections. Select elements and choose Manage ▸ Selection ▸ Save.").font(.callout).foregroundStyle(.secondary) } }
        }
        .frame(minWidth: 440)
    }
}

// MARK: - Keynoting Settings

struct KeynotingSettingsDialog: View {
    let state: DocumentState
    @State private var display: KeynoteDisplay = .key
    @State private var applyToExisting = true
    var body: some View {
        let _ = state.session.changeCounter
        let data = state.model.manageData
        DialogFrame(title: "Keynoting Settings", subtitle: "The keynote table keynote tags read from, and what they show.", state: state) {
            let d = display, apply = applyToExisting
            if state.f11Perform("Keynoting Settings", { tx in
                tx.updateManageData { $0.keynoteDisplay = d == .key ? nil : d }
                if apply { for t in tx.model.elements(.tags) where t.tag?.kind?.isKeynote == true { tx.update(t.id) { $0.tag?.keynoteDisplay = d } } }
            }) { state.presented = nil }
        } content: {
            GroupBox("Keynote Table") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Path", value: data.keynoteFile ?? "Built-in keynote table")
                    Text("\(Keynoting.table(state.model).count) keynotes").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Browse…") { load() }
                        Button("Use Built-in") { state.f11Perform("Built-in Keynote Table") { tx in tx.updateManageData { $0.keynoteTable = nil; $0.keynoteFile = nil } } }
                            .disabled(data.keynoteTable == nil)
                        Button("Export Table…") { export() }
                    }
                    Text("A keynote file is plain text: key, tab, keynote text, tab, parent key — one keynote per line.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Keynote Display") {
                Picker("", selection: $display) {
                    Text("Keynote Number").tag(KeynoteDisplay.key); Text("Keynote Text").tag(KeynoteDisplay.text); Text("Keynote Number and Text").tag(KeynoteDisplay.keyAndText)
                }.pickerStyle(.radioGroup).labelsHidden()
                Toggle("Apply to keynotes already placed", isOn: $applyToExisting)
            }
        }
        .frame(minWidth: 500)
        .onAppear { display = Keynoting.display(state.model) }
    }

    func load() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "txt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { state.show("The keynote file couldn't be read.", error: true); return }
        let name = url.lastPathComponent
        state.f11Perform("Load Keynote Table") { tx in
            let table = try Keynoting.parse(text)
            tx.updateManageData { $0.keynoteTable = table; $0.keynoteFile = name }
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Keynotes.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Keynoting.write(Keynoting.table(state.model)).write(to: url, atomically: true, encoding: .utf8) } catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
    }
}
