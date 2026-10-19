import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: View ▸ View Templates — manage templates and which settings they control, create one from the current
// view, assign one to the view (its controlled parameters lock in Properties), apply a template's properties once,
// or apply one temporarily (Temporary View Properties, session only).

enum ViewTemplatesMode: Equatable {
    case manage, assign, applyProperties, temporary
    var title: String {
        switch self {
        case .manage: "View Templates"
        case .assign: "Assign View Template"
        case .applyProperties: "Apply Template Properties to Current View"
        case .temporary: "Temporary View Properties"
        }
    }
}

struct ViewTemplatesDialog: View {
    let state: DocumentState
    let viewID: ElementID?
    let mode: ViewTemplatesMode
    var initial: ElementID? = nil

    @State private var selection: ElementID?
    @State private var draft: ViewTemplateData?
    @State private var name = ""
    @State private var showAll = false
    @State private var editVG: ElementID?
    /// The template `draft` and `name` belong to.
    @State private var loaded: ElementID?

    var model: BIMModel { state.model }
    var view: Element? { model[viewID] }
    var templates: [Element] {
        model.elements(.viewTemplates)
            .filter { t in showAll || view?.view.map { v in t.viewTemplate.map { ViewTemplates.compatible($0, with: v.kind) } ?? false } ?? true }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var temporaryActive: Bool { viewID.flatMap { state.session.temporaryVisibility[$0]?.temporaryTemplateID } != nil }

    var body: some View {
        ArcusDialog(icon: "doc.text.below.ecg", tint: .indigo, title: mode.title, subtitle: mode == .temporary ? "Shown in “\(view?.name ?? "")” until you restore it. Nothing is saved." : (view?.name ?? "Templates of view settings"),
                    size: .wide, okTitle: primaryTitle, okDisabled: mode != .manage && selection == nil, disabledReason: "Choose a template", height: 560,
                    onCancel: { close() }, onOK: { primary() }) {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                templateList.frame(width: 250)
                if let d = draft { settingsTable(d) } else {
                    DialogPane {
                        DialogEmptyState(icon: "doc.text.below.ecg", title: "No Template Selected", message: view == nil ? "Create a template from a view." : "Create one from the current view.")
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } leading: {
            if mode == .temporary, temporaryActive { Button("Restore View Properties") { setTemporary(nil); close() } }
            if mode == .assign, view?.view?.templateID != nil { Button("Remove Template") { assign(nil) } }
        } trailing: {
            if mode == .manage { Button("Apply") { save() }.disabled(!dirty).dialogButton() }
        }
        .onAppear {
            let current = mode == .assign || mode == .manage ? view?.view?.templateID : nil
            select(initial ?? current ?? templates.first?.id)
        }
        .onChange(of: selection) { old, new in
            if let old, old == loaded, old != new { save(old) }
            select(new)
        }
        .sheet(item: Binding(get: { editVG.map(IdentifiedID.init) }, set: { editVG = $0?.id })) { t in
            VisibilityGraphicsDialog(state: state, target: .template(t.id), onClose: { editVG = nil; reloadVisibility() }).opaqueDialogBackground() // DIALOGS
        }
    }

    var primaryTitle: String {
        switch mode {
        case .manage: "OK"
        case .assign: "Assign"
        case .applyProperties: "Apply Properties"
        case .temporary: "Apply Temporarily"
        }
    }

    // MARK: List

    var templateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            DialogPane("Templates") {
                List(templates, id: \.id, selection: $selection) { t in
                    let n = ViewTemplates.views(using: t.id, model).count
                    DialogListRow(icon: "doc.text.below.ecg", title: t.name, subtitle: "\(t.viewTemplate?.appliesTo.rawValue ?? "") · \(n) view\(n == 1 ? "" : "s")").tag(t.id)
                }
                .overlay { if templates.isEmpty { DialogEmptyState(icon: "doc.text.below.ecg", title: "No view templates") } }
            } bar: {
                Button("New from View") { createFromView() }.disabled(view?.view == nil).help("Create a template from the current view's settings")
                Spacer()
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate").accessibilityLabel("Duplicate template").disabled(selection == nil)
                Button { delete() } label: { Image(systemName: "minus") }.help("Delete (views using it keep their settings)").accessibilityLabel("Delete template").disabled(selection == nil)
            }
            .buttonStyle(.borderless)
            if view != nil { Toggle("Show all view types", isOn: $showAll).controlSize(.small) }
            if selection != nil { TextField("Name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Template name") }
        }
    }

    // MARK: Settings

    func settingsTable(_ d: ViewTemplateData) -> some View {
        let source = view?.view ?? ViewData(kind: d.appliesTo)
        return VStack(alignment: .leading, spacing: 6) {
            Text("View properties · \(d.appliesTo.rawValue)").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
            ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Parameter"); Text("Value"); Text("Include")
                }
                .font(DialogStyle.sectionTitle).foregroundStyle(.secondary)
                Divider().gridCellColumns(3)
                ForEach(ViewTemplates.Setting.allCases, id: \.self) { s in
                    if s != .viewRange || d.appliesTo.isPlan {
                        GridRow {
                            Text(s.rawValue)
                            value(s, d).disabled(!ViewTemplates.controls(d, s)).frame(width: 260, alignment: .leading)
                            Toggle("", isOn: Binding(get: { ViewTemplates.controls(d, s) }, set: { on in
                                guard var t = draft else { return }
                                ViewTemplates.setControls(&t, s, on, source: source)
                                draft = t
                            })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Include \(s.rawValue)")
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            DialogCaption("Included settings are controlled by the template: views that use it show the template's values and lock them in Properties.").padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func value(_ s: ViewTemplates.Setting, _ d: ViewTemplateData) -> some View {
        switch s {
        case .scale:
            Picker("", selection: Binding(get: { draft?.scale ?? d.scale ?? 100 }, set: { draft?.scale = $0 })) {
                if model.units.system == .imperial { ForEach(ViewScales.imperial, id: \.value) { Text($0.label).tag($0.value) } }
                else { ForEach(ViewScales.metric, id: \.self) { Text("1 : \($0)").tag($0) } }
            }.labelsHidden()
        case .detailLevel:
            Picker("", selection: Binding(get: { draft?.detailLevel ?? .medium }, set: { draft?.detailLevel = $0 })) {
                ForEach(DetailLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden()
        case .visualStyle:
            Picker("", selection: Binding(get: { draft?.visualStyle ?? .hiddenLine }, set: { draft?.visualStyle = $0 })) {
                ForEach(VisualStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden()
        case .discipline:
            Picker("", selection: Binding(get: { draft?.discipline ?? .architectural }, set: { draft?.discipline = $0 })) {
                ForEach(Discipline.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden()
        case .phaseFilter:
            Picker("", selection: Binding(get: { draft?.phaseFilter ?? .showAll }, set: { draft?.phaseFilter = $0 })) {
                ForEach(PhaseFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden()
        case .viewRange:
            HStack {
                let r = d.viewRange ?? .floorPlanDefault
                let f = { (v: Double) in Parameters.format(.double(v), type: .length, model: model) }
                Text("Cut \(f(r.cutOffset)) · Top \(f(r.topOffset))").font(.caption).lineLimit(1)
                if let vr = view?.view?.viewRange, view?.view?.kind.isPlan == true {
                    Button("From View") { draft?.viewRange = vr }.controlSize(.small)
                }
            }
        case .visibility:
            HStack {
                let vg = d.visibility ?? VisibilityGraphics()
                Text("\(vg.hiddenCategories.count) hidden · \(vg.categoryOverrides.count) overridden · \(vg.filters.count) filter(s)").font(.caption).lineLimit(1)
                Button("Edit…") { save(); editVG = selection }.controlSize(.small).disabled(selection == nil)
            }
        }
    }

    // MARK: Actions

    var dirty: Bool {
        guard let id = selection, let t = model[id] else { return false }
        return t.viewTemplate != draft || t.name != name
    }

    func select(_ id: ElementID?) {
        selection = id
        loaded = id
        draft = id.flatMap { model[$0]?.viewTemplate }
        name = id.flatMap { model[$0]?.name } ?? ""
    }

    func reloadVisibility() { if let id = selection { draft?.visibility = model[id]?.viewTemplate?.visibility } }

    func save(_ id: ElementID? = nil) {
        guard let id = id ?? loaded, let t = model[id], let d = draft, t.viewTemplate != d || t.name != name else { return }
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? t.name : name
        state.session.perform("Edit View Template") { tx in
            tx.update(id) { $0.viewTemplate = d; $0.name = n }
            ViewTemplates.propagate(id, in: tx)
        }
    }

    func uniqueName(_ base: String) -> String {
        var n = base, k = 2
        while model.elements(.viewTemplates).contains(where: { $0.name == n }) { n = "\(base) \(k)"; k += 1 }
        return n
    }

    func createFromView() {
        guard let v = view, let vd = v.view else { return }
        save()
        let td = ViewTemplates.make(from: vd)
        let n = uniqueName("\(v.name) Template")
        var created: ElementID?
        state.session.perform("Create View Template") { tx in created = tx.create(.viewTemplates, name: n, data: .viewTemplate(td)) }
        if let created { select(created) }
    }

    func duplicate() {
        guard let id = selection, let t = model[id], let d = draft else { return }
        save()
        let n = uniqueName(t.name + " Copy")
        var created: ElementID?
        state.session.perform("Duplicate View Template") { tx in created = tx.create(.viewTemplates, name: n, data: .viewTemplate(d)) }
        if let created { select(created) }
    }

    func delete() {
        guard let id = selection else { return }
        state.session.perform("Delete View Template") { tx in
            for v in ViewTemplates.views(using: id, tx.model) { tx.update(v.id) { $0.view?.templateID = nil } }
            tx.delete(id)
        }
        for (v, t) in state.session.temporaryVisibility where t.temporaryTemplateID == id { state.session.temporaryVisibility[v]?.temporaryTemplateID = nil }
        select(templates.first?.id)
    }

    func assign(_ template: ElementID?) {
        guard let v = viewID else { return }
        state.session.perform(template == nil ? "Remove View Template" : "Assign View Template") { tx in try ViewTemplates.assign(template, to: v, in: tx) }
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError(); return }
        close()
    }

    func setTemporary(_ template: ElementID?) {
        guard let v = viewID else { return }
        var t = state.session.temporaryVisibility[v] ?? TemporaryVisibility()
        t.temporaryTemplateID = template
        state.session.temporaryVisibility[v] = t
        state.graphics.invalidateView(v)
        state.toolChangedState()
    }

    func primary() {
        save()
        switch mode {
        case .manage: close()
        case .assign: assign(selection)
        case .applyProperties:
            guard let v = viewID, let id = selection, let td = model[id]?.viewTemplate else { return }
            state.session.perform("Apply Template Properties") { tx in tx.update(v) { e in if var d = e.view { ViewTemplates.apply(td, to: &d); e.view = d } } }
            close()
        case .temporary:
            setTemporary(selection)
            close()
        }
    }

    func close() { state.presented = nil }
}
