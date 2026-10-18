import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

// BL-PROPS: TypePropertiesDialog moved to TypePropertiesDialog.swift (staged OK / Cancel / Apply).

struct ProjectInfoDialog: View {
    let state: DocumentState
    @State private var info = ProjectInfoData()
    var body: some View {
        DialogFrame(title: "Project Information", state: state) {
            let i = info
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Project Information") { tx in tx.update(pid) { $0.projectInfo = i } }
            state.presented = nil
        } content: {
            Form {
                TextField("Project name", text: $info.projectName)
                TextField("Project number", text: $info.projectNumber)
                TextField("Client", text: $info.clientName)
                TextField("Address", text: $info.address, axis: .vertical)
                TextField("Status", text: $info.status)
                TextField("Organization", text: $info.organization)
                TextField("Author", text: $info.author)
                TextField("Building name", text: $info.buildingName)
                TextField("Sheet number prefix", text: $info.sheetNumberPrefix)
            }
        }
        .onAppear { info = state.model.projectInfo }
    }
}

struct ProjectUnitsDialog: View {
    let state: DocumentState
    @State private var units = UnitsSettings.metric
    var body: some View {
        DialogFrame(title: "Project Units", subtitle: "Display and input only. Stored geometry is never rounded.", state: state) {
            let u = units
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Project Units") { tx in tx.update(pid) { $0.projectInfo?.units = u } }
            state.presented = nil
        } content: {
            Form {
                Picker("System", selection: $units.system) { Text("Metric").tag(UnitSystem.metric); Text("Imperial").tag(UnitSystem.imperial) }
                    .onChange(of: units.system) { _, s in units = s == .metric ? .metric : .imperial }
                Picker("Length", selection: $units.length) { ForEach(LengthDisplay.allCases, id: \.self) { Text(label($0)).tag($0) } }
                Picker("Rounding", selection: $units.lengthRounding) {
                    if units.system == .metric { Text("1 mm").tag(0.001); Text("0.1 mm").tag(0.0001); Text("5 mm").tag(0.005); Text("10 mm").tag(0.01) }
                    else { Text("1/16\"").tag(0.0254 / 16); Text("1/8\"").tag(0.0254 / 8); Text("1/4\"").tag(0.0254 / 4); Text("1/32\"").tag(0.0254 / 32) }
                }
                Picker("Area", selection: $units.area) { ForEach(AreaDisplay.allCases, id: \.self) { Text($0.symbol).tag($0) } }
                Stepper("Area decimals: \(units.areaDecimals)", value: $units.areaDecimals, in: 0...4)
                Picker("Volume", selection: $units.volume) { ForEach(VolumeDisplay.allCases, id: \.self) { Text($0.symbol).tag($0) } }
                Stepper("Angle decimals: \(units.angleDecimals)", value: $units.angleDecimals, in: 0...4)
                Picker("Slope", selection: $units.slope) { ForEach(SlopeDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                LabeledContent("Example", value: QuantityFormatter.format(3.8125, kind: .length, units: units))
            }
        }
        .onAppear { units = state.model.units }
    }
    func label(_ d: LengthDisplay) -> String {
        switch d {
        case .millimeters: "Millimeters"; case .centimeters: "Centimeters"; case .meters: "Meters"
        case .feetFractionalInches: "Feet and fractional inches"; case .decimalFeet: "Decimal feet"
        case .fractionalInches: "Fractional inches"; case .decimalInches: "Decimal inches"
        }
    }
}

struct ProjectParametersDialog: View {
    let state: DocumentState
    @State private var params: [ParameterDefinition] = []
    @State private var name = ""
    @State private var type: ParamType = .text
    @State private var isInstance = true
    @State private var group: ParameterGroup = .identity
    @State private var cats: Set<Category> = [.rooms]
    var body: some View {
        DialogFrame(title: "Project Parameters", subtitle: "Parameters added to categories appear in Properties, schedules, tags and IFC property sets.", state: state) {
            let p = params
            state.session.perform("Project Parameters") { tx in tx.setProjectParameters(p) }
            state.presented = nil
        } content: {
            HStack(alignment: .top) {
                List {
                    ForEach(params) { p in
                        VStack(alignment: .leading) {
                            Text(p.name).font(.body.weight(.medium))
                            Text("\(p.type.displayName) · \(p.isInstance ? "Instance" : "Type") · \(p.categories.map(\.displayName).joined(separator: ", "))\(p.sharedGUID != nil ? " · Shared" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { params.remove(atOffsets: $0) }
                }
                .frame(width: 280, height: 260)
                .overlay { // W4-AUDIT: an empty list is otherwise an unexplained blank area
                    if params.isEmpty {
                        Text("No project parameters yet.\nAdd one on the right.").multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                Form {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) { ForEach(ParamType.userCreatable, id: \.self) { Text($0.displayName).tag($0) } }
                    Picker("Group", selection: $group) { ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("Binding", selection: $isInstance) { Text("Instance").tag(true); Text("Type").tag(false) }
                    ScrollView { VStack(alignment: .leading) { ForEach(Category.schedulable, id: \.self) { c in
                        Toggle(c.displayName, isOn: Binding(get: { cats.contains(c) }, set: { if $0 { cats.insert(c) } else { cats.remove(c) } }))
                    } } }.frame(height: 110)
                    HStack {
                        Button("Add Parameter") {
                            params.append(ParameterDefinition(name: name, type: type, group: group, isInstance: isInstance, categories: cats.sorted()))
                            name = ""
                        }.disabled(name.isEmpty || cats.isEmpty || params.contains { $0.name == name })
                        Button("Import Shared…") { importShared() }
                        Button("Export Shared…") { exportShared() }.disabled(params.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 700)
        .onAppear { params = state.model.projectParameters }
    }
    func exportShared() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Shared Parameters.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let shared = params.map { p -> ParameterDefinition in var p = p; if p.sharedGUID == nil { p.sharedGUID = UUID().uuidString }; return p }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(shared).write(to: url, options: .atomic)
    }
    func importShared() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let defs = try? JSONDecoder().decode([ParameterDefinition].self, from: data) else { return }
        for d in defs where !params.contains(where: { $0.id == d.id || $0.name == d.name }) { params.append(d) }
    }
}

// W2-ANNOT: LineStylesDialog moved to LineStylesDialog.swift.

struct PhasesDialog: View {
    let state: DocumentState
    var body: some View {
        let _ = state.session.changeCounter
        let phases = state.model.phases
        DialogFrame(title: "Phases", subtitle: "Phases are ordered from earliest to latest. Views and schedules show elements by phase and phase filter.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            List {
                ForEach(phases, id: \.id) { p in
                    HStack {
                        Text("\((p.phase?.order ?? 0) + 1).").monospacedDigit().foregroundStyle(.secondary)
                        TextField("", text: Binding(get: { p.name }, set: { v in state.session.setParameter(ParameterID("name"), value: .text(v), on: [p.id], name: "Name") }))
                        Spacer()
                        Button(role: .destructive) {
                            if phases.count <= 1 { state.show("A project needs at least one phase.", error: true); return }
                            let used = state.model.allElements.contains { $0.phaseCreated == p.id || $0.phaseDemolished == p.id }
                            if used { state.show("Elements are created or demolished in “\(p.name)”. Reassign them first.", error: true); return }
                            state.session.delete([p.id])
                        } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
            }.frame(minHeight: 180)
            Button("Add Phase") {
                let order = (phases.last?.phase?.order ?? -1) + 1
                state.session.perform("Add Phase") { tx in tx.create(.phases, name: "Phase \(order + 1)", data: .phase(PhaseData(order: order))) }
            }
        }
    }
}

struct DesignOptionsDialog: View {
    let state: DocumentState
    @State private var setName = "Option Set 1"
    var body: some View {
        let _ = state.session.changeCounter
        let options = state.model.elements(.designOptions)
        let sets = Dictionary(grouping: options, by: { $0.designOption?.setName ?? "" })
        DialogFrame(title: "Design Options", subtitle: "Elements in secondary options appear only in views set to show that option.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            List {
                ForEach(sets.keys.sorted(), id: \.self) { s in
                    Section(s) {
                        ForEach(sets[s]!, id: \.id) { o in
                            HStack {
                                Text(o.name + (o.designOption?.isPrimary == true ? " (primary)" : ""))
                                Spacer()
                                Button("Add Selection") { addSelection(o.id) }.disabled(state.session.selection.isEmpty)
                                Button("Make Primary") { makePrimary(o, in: sets[s]!) }.disabled(o.designOption?.isPrimary == true)
                                if let v = state.activeViewID {
                                    Button("Show in View") { state.session.perform("Show Option") { tx in tx.update(v) { $0.view?.designOptions[s] = o.id } } }
                                }
                            }
                        }
                        Button("Add Option") {
                            state.session.perform("Add Option") { tx in tx.create(.designOptions, name: "Option \(sets[s]!.count + 1)", data: .designOption(DesignOptionData(setName: s, isPrimary: false))) }
                        }
                    }
                }
            }.frame(minHeight: 220)
            .overlay { // W4-AUDIT: empty state instead of a blank list
                if sets.isEmpty {
                    Text("No design options yet.\nName an option set below and choose New Option Set.").multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("Set name", text: $setName).frame(width: 200)
                Button("New Option Set") {
                    let n = setName
                    state.session.perform("New Option Set") { tx in tx.create(.designOptions, name: "Option 1", data: .designOption(DesignOptionData(setName: n, isPrimary: true))) }
                }.disabled(setName.isEmpty || sets[setName] != nil)
            }
        }
        .frame(minWidth: 620, idealWidth: 620)
    }
    func addSelection(_ opt: ElementID) {
        let sel = state.session.selection.ids.filter { state.model[$0]?.category.isModel == true }
        state.session.perform("Add to Design Option") { tx in for e in sel { tx.update(e) { $0.designOptionID = opt } } }
    }
    func makePrimary(_ o: Element, in set: [Element]) {
        state.session.perform("Make Primary") { tx in for x in set { tx.update(x.id) { $0.designOption?.isPrimary = x.id == o.id } } }
    }
}

struct RevisionsDialog: View {
    let state: DocumentState
    var body: some View {
        let _ = state.session.changeCounter
        let revs = state.model.revisions
        DialogFrame(title: "Sheet Issues/Revisions", subtitle: "Issued revisions are locked. Clouds reference a revision; sheets list revisions whose clouds appear on them.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            Table(revs) {
                TableColumn("#") { r in Text(RevisionQueries.label(r, state.model)).monospacedDigit() }.width(30)
                TableColumn("Numbering") { r in
                    Picker("", selection: Binding(get: { r.revisionData?.numbering ?? .numeric }, set: { v in state.session.perform("Revision") { tx in tx.update(r.id) { $0.revisionData?.numbering = v } } })) {
                        ForEach(RevisionNumbering.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden()
                }.width(110)
                TableColumn("Date") { r in editable(r, "revision.date", r.revisionData?.date ?? "") }.width(100)
                TableColumn("Description") { r in editable(r, "revision.description", r.revisionData?.description ?? "") }
                TableColumn("Issued") { r in
                    Toggle("", isOn: Binding(get: { r.revisionData?.issued ?? false }, set: { v in state.session.setParameter(ParameterID("revision.issued"), value: .bool(v), on: [r.id], name: "Issued") })).labelsHidden()
                }.width(50)
                TableColumn("Show") { r in
                    Picker("", selection: Binding(get: { r.revisionData?.visibility ?? .cloudAndTag }, set: { v in state.session.perform("Revision") { tx in tx.update(r.id) { $0.revisionData?.visibility = v } } })) {
                        ForEach(RevisionVisibility.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden()
                }.width(170)
            }
            .frame(minHeight: 220)
            Button("Add Revision") {
                let seq = (revs.last?.revisionData?.sequence ?? 0) + 1
                state.session.perform("Add Revision") { tx in tx.create(.revisions, name: "Revision \(seq)", data: .revision(RevisionData(sequence: seq, date: Date().formatted(date: .numeric, time: .omitted), description: ""))) }
            }
        }
        .frame(minWidth: 760, idealWidth: 760)
    }
    func editable(_ r: Element, _ key: String, _ value: String) -> some View {
        TextField("", text: Binding(get: { value }, set: { v in state.session.setParameter(ParameterID(key), value: .text(v), on: [r.id], name: "Revision") }))
            .disabled(r.revisionData?.issued == true)
    }
}

struct LocationDialog: View {
    let state: DocumentState
    @State private var info = ProjectInfoData()
    @State private var northDegrees = 0.0
    var body: some View {
        DialogFrame(title: "Location & Coordinates", subtitle: "Project north is up in plan views. True north and the survey point set shared coordinates for IFC and spot coordinates.", state: state) {
            var i = info
            i.trueNorthAngle = Angle.radians(northDegrees)
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Location") { tx in tx.update(pid) { $0.projectInfo = i } }
            state.presented = nil
        } content: {
            Form {
                TextField("Site name", text: $info.siteName)
                TextField("Latitude (°)", value: $info.latitude, format: .number.precision(.fractionLength(0...6)))
                TextField("Longitude (°)", value: $info.longitude, format: .number.precision(.fractionLength(0...6)))
                TextField("Elevation above sea level (m)", value: $info.elevationAboveSeaLevel, format: .number)
                TextField("Angle to true north (°, counter-clockwise)", value: $northDegrees, format: .number.precision(.fractionLength(0...4)))
                Section("Survey point") {
                    TextField("Easting (m)", value: $info.surveyEasting, format: .number)
                    TextField("Northing (m)", value: $info.surveyNorthing, format: .number)
                    TextField("Elevation (m)", value: $info.surveyElevation, format: .number)
                }
                Section("Project base point (internal coordinates, m)") {
                    TextField("X", value: $info.projectBasePoint.x, format: .number)
                    TextField("Y", value: $info.projectBasePoint.y, format: .number)
                    TextField("Z", value: $info.projectBasePoint.z, format: .number)
                }
            }
        }
        .onAppear { info = state.model.projectInfo; northDegrees = Angle.degrees(info.trueNorthAngle) }
    }
}

// BL-KEYS: KeyboardShortcutsDialog moved to KeyboardShortcutsDialog.swift (import/export, press-keys assignment, conflicts).

struct PurgeDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    var unused: [Element] {
        let m = state.model
        var usedMaterials = Set<ElementID>()
        for t in m.elements(.elementTypes) {
            for l in t.typeData?.assembly?.layers ?? [] { if let x = l.materialID { usedMaterials.insert(x) } }
            for v in t.typeData?.params.values ?? [:].values { if let r = v.refValue { usedMaterials.insert(r) } }
        }
        for e in m.allElements { if let p = e.params[.paintMaterial]?.refValue { usedMaterials.insert(p) } }
        let types = m.elements(.elementTypes).filter { t in
            m.instanceCount(ofType: t.id) == 0 && !m.sheets.contains { $0.sheet?.titleBlockTypeID == t.id } && t.typeData?.instanceCategory != .tags
        }
        let families = m.elements(.families).filter { f in !m.elements(.elementTypes).contains { $0.typeData?.familyID == f.id } }
        let mats = m.materials.filter { !usedMaterials.contains($0.id) }
        return types + families + mats
    }
    var body: some View {
        DialogFrame(title: "Purge Unused", subtitle: "Unused types, families and materials. Purging can be undone.", okTitle: "Purge \(chosen.count)", okDisabled: chosen.isEmpty, state: state) {
            let ids = chosen.sorted()
            state.session.perform("Purge Unused") { tx in for i in ids { tx.delete(i) } }
            state.presented = nil
        } content: {
            List(unused, id: \.id) { e in
                Toggle(isOn: Binding(get: { chosen.contains(e.id) }, set: { if $0 { chosen.insert(e.id) } else { chosen.remove(e.id) } })) {
                    Text("\(e.category.singularName): \(e.typeData.map { "\($0.familyName): " } ?? "")\(e.name)")
                }
            }.frame(minHeight: 280)
            HStack { Button("Check All") { chosen = Set(unused.map(\.id)) }; Button("Check None") { chosen = [] } }
        }
        .frame(minWidth: 520, idealWidth: 520)
    }
}

struct ReportDialog: View {
    let state: DocumentState
    let title: String
    let text: String
    var body: some View {
        DialogFrame(title: title, okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 260)
            Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        }
        .frame(minWidth: 560, idealWidth: 560)
    }
}

struct ModelHealthDialog: View {
    let state: DocumentState
    @State private var selection: String?
    var body: some View {
        DialogFrame(title: "Model Health", subtitle: "\(state.healthWarnings.count) item(s). Select one and choose Show to navigate to its elements.", okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            List(state.healthWarnings, selection: $selection) { w in
                HStack(alignment: .top) {
                    Image(systemName: w.severity == .error ? "exclamationmark.octagon.fill" : w.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(w.severity == .error ? .red : w.severity == .warning ? .orange : .secondary)
                        .accessibilityLabel(w.severity.rawValue)
                    VStack(alignment: .leading) {
                        Text(w.message)
                        Text("\(w.elements.count) element(s) · \(w.code)").font(.caption).foregroundStyle(.secondary)
                    }
                }.tag(w.id)
            }
            .frame(minHeight: 300)
            .overlay {
                if state.healthWarnings.isEmpty {
                    ContentUnavailableView("No Problems Found", systemImage: "checkmark.seal",
                                           description: Text("Rooms, hosts, sketches, overlapping walls, stair rules, links, marks and references all check out."))
                }
            }
            HStack {
                Button("Show") { show() }.disabled(selection == nil)
                Button("Re-check") { state.scheduleHealthCheck() }
                Spacer()
                if state.healthWarnings.isEmpty { Label("No problems found", systemImage: "checkmark.seal").foregroundStyle(.secondary) }
            }
        }
        .frame(minWidth: 640, idealWidth: 640)
    }
    func show() {
        guard let w = state.healthWarnings.first(where: { $0.id == selection }) else { return }
        let m = state.model
        let els = w.elements.compactMap { m[$0] }
        state.presented = nil
        state.session.selection.select(els.map(\.id))
        guard let first = els.first else { return }
        if let plan = m.views.first(where: { $0.view?.kind == .floorPlan && $0.levelID == first.levelID }) ?? m.views.first(where: { $0.view?.kind == .floorPlan }) {
            state.open(plan.id)
            let b = els.reduce(Rect2.empty) { $0.union(ElementMeshes.bounds($1, m).xy) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let canvas = state.canvases[plan.id] as? Canvas2DView, !b.isEmpty { canvas.zoom(to: b.expanded(by: 3)) }
            }
        }
    }
}

struct DWGUnavailableDialog: View {
    let state: DocumentState
    var body: some View {
        DialogFrame(title: "No DWG Converter Found", okTitle: "Import DXF Instead…", state: state) {
            state.presented = nil
            CommandRouter(state: state).run(.importDXF)
        } content: {
            DWGConverterHelpView(state: state) // W2-DWG
        }
    }
}

struct NewFamilyDialog: View {
    let state: DocumentState
    @State private var template: FamilyTemplate = .furniture
    @State private var name = "New Family"
    var body: some View {
        DialogFrame(title: "New Family", subtitle: "Families are Arcus's own parametric content (.arcusfamily). RFA families come in through the Arcus Bridge export (Insert ▸ Import Revit Model).", okTitle: "Create", state: state) {
            var f = FamilyTemplates.make(template)
            f.name = name
            state.presented = nil
            FamilyEditorWindowController.open(new: f, state: state)
        } content: {
            FormRow(label: "Category template") {
                Picker("", selection: $template) { ForEach(FamilyTemplate.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            FormRow(label: "Name") { TextField("", text: $name).textFieldStyle(.roundedBorder) }
        }
    }
}

