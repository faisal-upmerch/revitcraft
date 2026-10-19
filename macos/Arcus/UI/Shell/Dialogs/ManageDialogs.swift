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
        DialogFrame(title: "Project Information", icon: "info.circle", subtitle: "Shown in title blocks, schedules and exports.", state: state) {
            let i = info
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Project Information") { tx in tx.update(pid) { $0.projectInfo = i } }
            state.presented = nil
        } content: {
            DialogSection("Project") {
                DialogRow("Name") { TextField("", text: $info.projectName).labelsHidden() }
                DialogRow("Number") { TextField("", text: $info.projectNumber).labelsHidden() }
                DialogRow("Status") { TextField("", text: $info.status).labelsHidden() }
                DialogRow("Building name") { TextField("", text: $info.buildingName).labelsHidden() }
            }
            DialogSection("Client") {
                DialogRow("Client") { TextField("", text: $info.clientName).labelsHidden() }
                DialogRow("Address") { TextField("", text: $info.address, axis: .vertical).lineLimit(2...4).labelsHidden() }
            }
            DialogSection("Issued by", footnote: "New sheets are numbered after the prefix (A101, A102…).") {
                DialogRow("Organization") { TextField("", text: $info.organization).labelsHidden() }
                DialogRow("Author") { TextField("", text: $info.author).labelsHidden() }
                DialogRow("Sheet number prefix") { TextField("", text: $info.sheetNumberPrefix).labelsHidden().frame(width: 90) }
            }
        }
        .onAppear { info = state.model.projectInfo }
    }
}

struct ProjectUnitsDialog: View {
    let state: DocumentState
    @State private var units = UnitsSettings.metric
    var body: some View {
        DialogFrame(title: "Project Units", icon: "ruler", subtitle: "Display and input only. Geometry is never rounded.", state: state) {
            let u = units
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Project Units") { tx in tx.update(pid) { $0.projectInfo?.units = u } }
            state.presented = nil
        } content: {
            DialogSection {
                DialogRow("System") {
                    Picker("", selection: $units.system) { Text("Metric").tag(UnitSystem.metric); Text("Imperial").tag(UnitSystem.imperial) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .onChange(of: units.system) { _, s in units = s == .metric ? .metric : .imperial }
                }
            }
            DialogSection("Length", footnote: "Example: \(QuantityFormatter.format(3.8125, kind: .length, units: units))") {
                DialogRow("Format") { Picker("", selection: $units.length) { ForEach(LengthDisplay.allCases, id: \.self) { Text(label($0)).tag($0) } }.labelsHidden().fixedSize() }
                DialogRow("Rounding") {
                    Picker("", selection: $units.lengthRounding) {
                        if units.system == .metric { Text("1 mm").tag(0.001); Text("0.1 mm").tag(0.0001); Text("5 mm").tag(0.005); Text("10 mm").tag(0.01) }
                        else { Text("1/16\"").tag(0.0254 / 16); Text("1/8\"").tag(0.0254 / 8); Text("1/4\"").tag(0.0254 / 4); Text("1/32\"").tag(0.0254 / 32) }
                    }.labelsHidden().fixedSize()
                }
            }
            DialogSection("Area, volume and angles") {
                DialogRow("Area") {
                    HStack(spacing: 12) {
                        Picker("", selection: $units.area) { ForEach(AreaDisplay.allCases, id: \.self) { Text($0.symbol).tag($0) } }.labelsHidden().fixedSize()
                        Stepper("\(units.areaDecimals) decimals", value: $units.areaDecimals, in: 0...4).monospacedDigit()
                    }
                }
                DialogRow("Volume") { Picker("", selection: $units.volume) { ForEach(VolumeDisplay.allCases, id: \.self) { Text($0.symbol).tag($0) } }.labelsHidden().fixedSize() }
                DialogRow("Angle") { Stepper("\(units.angleDecimals) decimals", value: $units.angleDecimals, in: 0...4).monospacedDigit() }
                DialogRow("Slope") { Picker("", selection: $units.slope) { ForEach(SlopeDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize() }
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
        DialogFrameWithActions(title: "Project Parameters", icon: "slider.horizontal.3", size: .large, subtitle: "Appear in Properties, schedules, tags and IFC property sets.", labelWidth: 70, state: state) {
            let p = params
            state.session.perform("Project Parameters") { tx in tx.setProjectParameters(p) }
            state.presented = nil
        } content: {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parameters").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
                    DialogListBox(count: params.count, rowHeight: 40, minRows: 7, maxRows: 7) {
                        List {
                            ForEach(params) { p in
                                DialogListRow(icon: p.sharedGUID != nil ? "link" : "slider.horizontal.3", title: p.name,
                                              subtitle: "\(p.type.displayName) · \(p.isInstance ? "Instance" : "Type") · \(p.categories.map(\.displayName).joined(separator: ", "))")
                            }
                            .onDelete { params.remove(atOffsets: $0) }
                        }
                    } empty: {
                        DialogEmptyState(icon: "slider.horizontal.3", title: "No project parameters", message: "Add one on the right.")
                    }
                }
                .frame(width: 290)
                DialogSection("New parameter") {
                    DialogRow("Name") { TextField("", text: $name).labelsHidden() }
                    DialogRow("Type") { Picker("", selection: $type) { ForEach(ParamType.userCreatable, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden() }
                    DialogRow("Group") { Picker("", selection: $group) { ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                    DialogRow("Binding") { Picker("", selection: $isInstance) { Text("Instance").tag(true); Text("Type").tag(false) }.pickerStyle(.segmented).labelsHidden().fixedSize() }
                    DialogRow("Categories", alignment: .top) {
                        ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(Category.schedulable, id: \.self) { c in
                            Toggle(c.displayName, isOn: Binding(get: { cats.contains(c) }, set: { if $0 { cats.insert(c) } else { cats.remove(c) } }))
                        } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 104)
                    }
                    HStack {
                        Spacer()
                        Button("Add Parameter") {
                            params.append(ParameterDefinition(name: name, type: type, group: group, isInstance: isInstance, categories: cats.sorted()))
                            name = ""
                        }.disabled(name.isEmpty || cats.isEmpty || params.contains { $0.name == name })
                    }
                }
            }
        } actions: {
            Button("Import Shared…") { importShared() }
            Button("Export Shared…") { exportShared() }.disabled(params.isEmpty)
        }
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
        DialogFrameWithActions(title: "Phases", icon: "clock.arrow.circlepath", tint: .teal, subtitle: "Earliest first. Views show elements by phase and phase filter.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            DialogListBox(count: phases.count, rowHeight: 34, minRows: 3, maxRows: 8) {
                List {
                    ForEach(phases, id: \.id) { p in
                        HStack(spacing: 10) {
                            Text("\((p.phase?.order ?? 0) + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                            TextField("", text: Binding(get: { p.name }, set: { v in state.session.setParameter(ParameterID("name"), value: .text(v), on: [p.id], name: "Name") }))
                                .textFieldStyle(.plain).labelsHidden()
                            Spacer()
                            Button(role: .destructive) {
                                if phases.count <= 1 { state.show("A project needs at least one phase.", error: true); return }
                                let used = state.model.allElements.contains { $0.phaseCreated == p.id || $0.phaseDemolished == p.id }
                                if used { state.show("Elements are created or demolished in “\(p.name)”. Reassign them first.", error: true); return }
                                state.session.delete([p.id])
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete Phase").accessibilityLabel("Delete \(p.name)")
                        }
                    }
                }
            }
        } actions: {
            Button("Add Phase") {
                let order = (phases.last?.phase?.order ?? -1) + 1
                state.session.perform("Add Phase") { tx in tx.create(.phases, name: "Phase \(order + 1)", data: .phase(PhaseData(order: order))) }
            }
        }
    }
}

/// Design Options: option sets on the left (+ / −), the selected set's options on the right with Make Primary,
/// Add Selection and Show in View. An empty project shows one illustrated empty state with New Option Set.
struct DesignOptionsDialog: View {
    let state: DocumentState
    @State private var selectedSet: String?
    @State private var selectedOption: ElementID?
    @State private var naming = false
    @State private var newSetName = ""

    var body: some View {
        let _ = state.session.changeCounter
        let options = state.model.elements(.designOptions)
        let sets = Dictionary(grouping: options, by: { $0.designOption?.setName ?? "" })
        let names = sets.keys.sorted()
        let current = selectedSet.flatMap { sets[$0] != nil ? $0 : nil } ?? names.first
        DialogFrame(title: "Design Options", icon: "square.stack.3d.up", tint: .indigo, size: .large,
                    subtitle: "Secondary options show only in views set to show them.", okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            if names.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                    setsColumn(names, sets: sets, current: current).frame(width: 230)
                    if let current, let opts = sets[current] { optionsColumn(current, opts.sorted { ($0.designOption?.isPrimary == true ? 0 : 1, $0.id) < ($1.designOption?.isPrimary == true ? 0 : 1, $1.id) }) }
                }
            }
        }
        .onAppear { selectedSet = names.first }
    }

    private var emptyState: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        return VStack(spacing: 14) {
            DialogEmptyState(icon: "square.stack.3d.up", title: "No Design Options Yet",
                             message: "An option set holds alternatives for part of the design, such as two kitchen layouts. One option is primary; the others show only where a view asks for them.",
                             illustrated: true)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Option set name", text: $newSetName).textFieldStyle(.roundedBorder).frame(width: 200).onSubmit(createSet)
                Button("New Option Set", action: createSet).buttonStyle(.borderedProminent).disabled(newSetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 28).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(DialogColors.sectionFill, in: shape)
        .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        .onAppear { if newSetName.isEmpty { newSetName = "Option Set 1" } }
    }

    private func setsColumn(_ names: [String], sets: [String: [Element]], current: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        let removable = current.map { s in !(sets[s] ?? []).contains { o in state.model.allElements.contains { $0.designOptionID == o.id } } } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Text("Option Sets").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) {
                List(selection: Binding(get: { current }, set: { selectedSet = $0; selectedOption = nil })) {
                    ForEach(names, id: \.self) { n in
                        DialogListRow(icon: "square.stack.3d.up", iconTint: .indigo, title: n, subtitle: "\(sets[n]?.count ?? 0) option\((sets[n]?.count ?? 0) == 1 ? "" : "s")").tag(Optional(n))
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(height: 236)
                Divider()
                DialogAddRemoveBar(addHelp: "New Option Set", removeHelp: removable ? "Delete Option Set" : "Remove the elements from this set's options first",
                                   canRemove: removable, onAdd: { newSetName = uniqueSetName(names); naming = true }, onRemove: { deleteSet(current, sets) })
                    .popover(isPresented: $naming, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("New Option Set").font(.headline)
                            TextField("Name", text: $newSetName).textFieldStyle(.roundedBorder).frame(width: 220).onSubmit(createSet)
                            if names.contains(newSetName) { Text("A set with this name exists.").font(.caption).foregroundStyle(.secondary) }
                            HStack { Spacer(); Button("Cancel") { naming = false }; Button("Create", action: createSet).buttonStyle(.borderedProminent)
                                .disabled(newSetName.trimmingCharacters(in: .whitespaces).isEmpty || names.contains(newSetName)) }
                        }
                        .padding(16)
                    }
            }
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        }
    }

    private func optionsColumn(_ set: String, _ opts: [Element]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        let chosen = opts.first { $0.id == selectedOption } ?? opts.first
        let view = state.activeViewID.flatMap { state.model[$0] }
        let shown = view?.view?.designOptions[set]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Options in “\(set)”").font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4).lineLimit(1)
            VStack(spacing: 0) {
                List(selection: Binding(get: { chosen?.id }, set: { selectedOption = $0 })) {
                    ForEach(opts, id: \.id) { o in
                        let primary = o.designOption?.isPrimary == true
                        let members = state.model.allElements.filter { $0.designOptionID == o.id }.count
                        DialogListRow(icon: primary ? "star.fill" : "square.on.square", iconTint: primary ? .yellow : .secondary, title: o.name,
                                      subtitle: "\(members) element\(members == 1 ? "" : "s")") {
                            HStack(spacing: 6) {
                                if shown == o.id { Image(systemName: "eye").foregroundStyle(.secondary).help("Shown in \(view?.name ?? "this view")") }
                                if primary { DialogBadge(text: "Primary") }
                            }
                        }
                        .tag(Optional(o.id))
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(height: 236)
                Divider()
                HStack(spacing: 8) {
                    Button { state.session.perform("Add Option") { tx in tx.create(.designOptions, name: "Option \(opts.count + 1)", data: .designOption(DesignOptionData(setName: set, isPrimary: false))) } } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless).help("Add Option").accessibilityLabel("Add Option")
                    Spacer()
                    if let chosen {
                        if let v = view {
                            Button("Show in View") { state.session.perform("Show Option") { tx in tx.update(v.id) { $0.view?.designOptions[set] = chosen.id } } }
                                .disabled(shown == chosen.id)
                        }
                        Button("Add Selection") { addSelection(chosen.id) }.disabled(state.session.selection.isEmpty)
                            .help(state.session.selection.isEmpty ? "Select model elements first." : "Move the selected elements into \(chosen.name).")
                        Button("Make Primary") { makePrimary(chosen, in: opts) }.disabled(chosen.designOption?.isPrimary == true)
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 6)
                .frame(height: 28)
            }
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        }
    }

    private func uniqueSetName(_ names: [String]) -> String {
        var i = names.count + 1
        while names.contains("Option Set \(i)") { i += 1 }
        return "Option Set \(i)"
    }

    private func createSet() {
        let n = newSetName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !state.model.elements(.designOptions).contains(where: { $0.designOption?.setName == n }) else { return }
        state.session.perform("New Option Set") { tx in tx.create(.designOptions, name: "Option 1", data: .designOption(DesignOptionData(setName: n, isPrimary: true))) }
        selectedSet = n
        selectedOption = nil
        naming = false
    }

    private func deleteSet(_ set: String?, _ sets: [String: [Element]]) {
        guard let set, let opts = sets[set] else { return }
        state.session.delete(opts.map(\.id))
        selectedSet = nil
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
        DialogFrameWithActions(title: "Sheet Issues/Revisions", icon: "cloud", tint: .orange, size: .large, subtitle: "Issued revisions are locked. Sheets list the revisions clouded on them.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            DialogListBox(count: revs.count, rowHeight: 30, minRows: 6, maxRows: 10, isEmpty: revs.isEmpty) {
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
                }.width(150)
            }
            } empty: {
                DialogEmptyState(icon: "cloud", title: "No revisions", message: "Add a revision, then draw revision clouds on sheets.")
            }
        } actions: {
            Button("Add Revision") {
                let seq = (revs.last?.revisionData?.sequence ?? 0) + 1
                state.session.perform("Add Revision") { tx in tx.create(.revisions, name: "Revision \(seq)", data: .revision(RevisionData(sequence: seq, date: Date().formatted(date: .numeric, time: .omitted), description: ""))) }
            }
        }
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
        DialogFrame(title: "Location", icon: "location", tint: .blue, subtitle: "True north and the survey point set shared coordinates.", scrolls: true, labelWidth: 170, state: state) {
            var i = info
            i.trueNorthAngle = Angle.radians(northDegrees)
            guard let pid = state.model.projectInfoElement?.id else { return }
            state.session.perform("Location") { tx in tx.update(pid) { $0.projectInfo = i } }
            state.presented = nil
        } content: {
            DialogSection("Site") {
                DialogRow("Site name") { TextField("", text: $info.siteName).labelsHidden() }
                DialogRow("Latitude") { unitField($info.latitude, "°", digits: 6) }
                DialogRow("Longitude") { unitField($info.longitude, "°", digits: 6) }
                DialogRow("Elevation above sea") { unitField($info.elevationAboveSeaLevel, "m") }
            }
            DialogSection("North", footnote: "Project north is up in plan views. Angles are counter-clockwise.") {
                DialogRow("Angle to true north") { unitField($northDegrees, "°", digits: 4) }
            }
            DialogSection("Survey point") {
                DialogRow("Easting") { unitField($info.surveyEasting, "m") }
                DialogRow("Northing") { unitField($info.surveyNorthing, "m") }
                DialogRow("Elevation") { unitField($info.surveyElevation, "m") }
            }
            DialogSection("Project base point", footnote: "Internal coordinates.") {
                DialogRow("X") { unitField($info.projectBasePoint.x, "m") }
                DialogRow("Y") { unitField($info.projectBasePoint.y, "m") }
                DialogRow("Z") { unitField($info.projectBasePoint.z, "m") }
            }
        }
        .onAppear { info = state.model.projectInfo; northDegrees = Angle.degrees(info.trueNorthAngle) }
    }

    /// A number field with its unit after it.
    private func unitField(_ value: Binding<Double>, _ unit: String, digits: Int = 3) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number.precision(.fractionLength(0...digits))).labelsHidden().multilineTextAlignment(.trailing).frame(width: 140)
            Text(unit).foregroundStyle(.secondary)
        }
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
        let items = unused
        DialogFrameWithActions(title: "Purge Unused", icon: "trash", tint: .gray, subtitle: "Unused types, families and materials. Purging can be undone.",
                               okTitle: chosen.isEmpty ? "Purge" : "Purge \(chosen.count)", okDisabled: chosen.isEmpty, disabledReason: "Check the items to purge", state: state) {
            let ids = chosen.sorted()
            state.session.perform("Purge Unused") { tx in for i in ids { tx.delete(i) } }
            state.presented = nil
        } content: {
            DialogCheckList(items: items.map { e in
                DialogCheckItem(id: e.id, title: "\(e.typeData.map { "\($0.familyName): " } ?? "")\(e.name)", subtitle: e.category.singularName)
            }, checked: $chosen, maxRows: 10, noun: "items", emptyTitle: "Nothing to purge", emptyMessage: "Every type, family and material is in use.", emptyIcon: "checkmark.seal")
        } actions: {
            Button("Check All") { chosen = Set(items.map(\.id)) }.disabled(items.isEmpty)
            Button("Check None") { chosen = [] }.disabled(chosen.isEmpty)
        }
    }
}

/// A text report (import, export, paste results): headings, paragraphs and bullet rows in the system font, with Copy
/// Report in the footer. A short first line becomes the subtitle.
struct ReportDialog: View {
    let state: DocumentState
    let title: String
    let text: String

    /// The first paragraph when it is one short line ("Checked 412 elements."), and the rest of the report.
    static func split(_ text: String) -> (lead: String, body: String) {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count > 1, let first = parts.first, !first.contains("\n"), first.count <= 90, !first.hasSuffix(":") else { return ("", text) }
        return (first, parts.dropFirst().joined(separator: "\n\n"))
    }

    var body: some View {
        let (lead, rest) = Self.split(text)
        let t = title.lowercased()
        let icon = t.contains("import") ? "square.and.arrow.down" : t.contains("export") ? "square.and.arrow.up" : t.contains("health") ? "stethoscope"
            : t.contains("paste") ? "doc.on.clipboard" : t.contains("id") ? "number" : "doc.text.magnifyingglass"
        DialogFrameWithActions(title: title, icon: icon, tint: t.contains("health") ? .pink : .accentColor, subtitle: lead, okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            DialogReportText(text: rest)
        } actions: {
            Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        }
    }
}

/// Model Health: counts by severity (click a tile to filter), then the results grouped by severity with Show and
/// Select on each row; Copy Report and Check Again in the footer.
struct ModelHealthDialog: View {
    let state: DocumentState
    @State private var filter: DialogSeverity?

    var body: some View {
        let warnings = state.healthWarnings
        let counts = Dictionary(grouping: warnings, by: { DialogSeverity($0.severity) }).mapValues(\.count)
        let issues = warnings.filter { filter == nil || DialogSeverity($0.severity) == filter }.map { w in
            DialogIssue(id: w.id, severity: DialogSeverity(w.severity), title: w.message, detail: "\(w.elements.count) element\(w.elements.count == 1 ? "" : "s") · \(w.code)")
        }
        DialogFrameWithActions(title: "Model Health", icon: "stethoscope", tint: .pink, size: .large,
                               subtitle: warnings.isEmpty ? "No problems found." : "\(warnings.count) item\(warnings.count == 1 ? "" : "s") to review. Show goes to the elements.",
                               okTitle: "Done", showCancel: false, state: state) {
            state.presented = nil
        } content: {
            DialogSummaryTiles(tiles: DialogSummaryTiles.severities(counts), filter: $filter)
            DialogIssueList(issues: issues, maxHeight: 400) { issue in
                Button("Select") { select(issue.id) }
                Button("Show") { show(issue.id) }
            } empty: {
                DialogEmptyState(icon: "checkmark.seal", title: filter == nil ? "No Problems Found" : "No \(filter!.plural.lowercased())",
                                 message: filter == nil ? "Rooms, hosts, sketches, overlapping walls, stairs, links, marks and references all check out." : "")
            }
        } actions: {
            Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report(warnings), forType: .string) }
                .disabled(warnings.isEmpty)
            Button("Check Again") { state.scheduleHealthCheck() }
        }
    }

    func report(_ ws: [ModelWarning]) -> String {
        var out = "Model Health: \(ws.count) item\(ws.count == 1 ? "" : "s")"
        for s in DialogSeverity.allCases {
            let group = ws.filter { DialogSeverity($0.severity) == s }
            guard !group.isEmpty else { continue }
            out += "\n\n\(s.plural) (\(group.count)):\n" + group.map { "• \($0.message) [\($0.code); \($0.elements.map(\.description).joined(separator: ", "))]" }.joined(separator: "\n")
        }
        return out
    }

    func select(_ id: String) {
        guard let w = state.healthWarnings.first(where: { $0.id == id }) else { return }
        state.presented = nil
        state.session.selection.select(w.elements.filter { state.model[$0] != nil })
    }

    func show(_ id: String) {
        guard let w = state.healthWarnings.first(where: { $0.id == id }) else { return }
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
        DialogFrame(title: "DWG Import Not Available", icon: "exclamationmark.triangle", tint: .orange, subtitle: "Install a DWG converter, or import DXF.", okTitle: "Import DXF Instead…", scrolls: true, state: state) {
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
        let blank = name.trimmingCharacters(in: .whitespaces).isEmpty
        DialogFrame(title: "New Family", icon: "cube", tint: .purple, size: .small, subtitle: "Arcus parametric content (.arcusfamily).", okTitle: "Create",
                    okDisabled: blank, disabledReason: "Enter a name", state: state) {
            var f = FamilyTemplates.make(template)
            f.name = name
            state.presented = nil
            FamilyEditorWindowController.open(new: f, state: state)
        } content: {
            DialogSection(footnote: "RFA families come in through Insert ▸ Import Revit Model (Arcus Bridge export).") {
                DialogRow("Template") {
                    Picker("", selection: $template) { ForEach(FamilyTemplate.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                }
                DialogRow("Name") { TextField("", text: $name).labelsHidden() }
            }
        }
    }
}
