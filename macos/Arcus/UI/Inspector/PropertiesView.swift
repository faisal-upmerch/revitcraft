import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Properties inspector: type selector, instance parameters of the selection (or the active view), Edit Type.
/// BL-PROPS: the subject (`DocumentState.paletteSubject`) is the pending new element while a placement tool is active,
/// else the selection ("Common (n)" across categories), else a browser-previewed view, else the active view. The body is
/// rebuilt (and scrolled to the top) whenever the subject changes.
struct PropertiesView: View {
    @Bindable var state: DocumentState
    @State private var collapsed: Set<ParameterGroup> = []
    @AppStorage("properties.labelWidth") private var labelWidth: Double = Double(Tokens.inspectorLabelWidth) // BL-PROPS

    var body: some View {
        let _ = state.session.changeCounter
        let _ = state.toolRevision
        let subject = state.paletteSubject
        VStack(spacing: 0) {
            PanelHeader(title: "Properties", symbol: "slider.horizontal.3", panel: .properties, state: state)
            typeSelector
                .padding(.horizontal, 10).padding(.bottom, 6)
            Divider()
            instanceBar
            Divider()
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groups, id: \.0) { group, rows in
                                Section {
                                    if !collapsed.contains(group) {
                                        ForEach(rows) { row in
                                            ParamRow(state: state, entry: row.entry, targets: editTargets, varies: row.varies,
                                                     labelWidth: CGFloat(labelWidth), apply: applyOverride)
                                                .modifier(HoverBackground(radius: 5))
                                                .padding(.horizontal, 4)
                                        }
                                    }
                                } header: { groupHeader(group) }
                            }
                        }
                        ScheduleInspectorSection(state: state, targets: targets) // BL-SCHED
                    }
                    .scrollContentBackground(.hidden)
                    .id(subject) // BL-PROPS: a new subject rebuilds every row and starts at the top
                    ColumnDivider(labelWidth: $labelWidth, maxWidth: max(90, geo.size.width - 110))
                }
            }
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Properties")
    }

    /// Group header: opaque so pinned headers never show the rows scrolling beneath them.
    func groupHeader(_ group: ParameterGroup) -> some View {
        Button {
            withAnimation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.15)) {
                if collapsed.contains(group) { collapsed.remove(group) } else { collapsed.insert(group) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(group.rawValue).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed.contains(group) ? 0 : 90))
            }
            .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 4)
            .background(AccessibilityPrefs.reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.thinMaterial)) // W4-SHELL: sits on the glass dock
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.rawValue), \(collapsed.contains(group) ? "collapsed" : "expanded")")
    }

    /// Element ID of a single element (the palette hides it from the rows).
    @ViewBuilder var footer: some View {
        if let id = footerElementID {
            Divider()
            HStack {
                Text("Element ID").foregroundStyle(.secondary)
                Spacer()
                Text(String(id.raw)).monospacedDigit().textSelection(.enabled)
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 14).padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
    var footerElementID: ElementID? {
        switch state.paletteSubject {
        case .elements(let ids, _) where ids.count == 1: ids[0]
        default: nil
        }
    }

    // MARK: Targets

    /// Elements whose parameters are shown and edited (empty for a pending new element).
    var targets: [Element] {
        switch state.paletteSubject {
        case .elements(let ids, _): ids.compactMap { state.model[$0] }
        case .view(let id): state.model[id].map { [$0] } ?? []
        case .newElement, .nothing: []
        }
    }
    var editTargets: [ElementID] { targets.map(\.id) }

    var categoriesInSelection: [(Category, Int)] { state.session.selection.categoryCounts(state.model) }

    var rows: [PropertyRow] {
        if case .newElement(let cat, let typeID) = state.paletteSubject {
            return NewElementProperties.rows(category: cat, typeID: typeID, tool: state.activeTool, levelID: newElementLevel,
                                             model: state.model, defaults: state.palette.creationDefaults[cat])
        }
        return PaletteLayout.aggregate(targets, state.model)
    }

    var groups: [(ParameterGroup, [PropertyRow])] { PaletteLayout.grouped(rows) }

    var newElementLevel: ElementID? { state.activeViewID.flatMap { state.toolContext(for: $0).levelID } }

    /// Edits of a pending new element go to the tool or become creation defaults instead of changing the model.
    var applyOverride: ((ParameterID, ParamValue) throws(ParameterError) -> Void)? {
        guard case .newElement(let cat, let typeID) = state.paletteSubject else { return nil }
        let state = self.state, level = newElementLevel
        return { id, value throws(ParameterError) in
            var d = state.palette.creationDefaults[cat] ?? CreationDefaults(categories: [cat])
            try NewElementProperties.set(id, value: value, category: cat, typeID: typeID, tool: state.activeTool, levelID: level,
                                         model: state.model, defaults: &d)
            state.palette.creationDefaults[cat] = d
            state.syncCreationDefaults()
            state.toolChangedState()
        }
    }

    var editableTypeID: ElementID? {
        let ids = Set(targets.compactMap(\.typeID))
        return ids.count == 1 ? ids.first : nil
    }

    /// The palette's instance bar: what the parameters below belong to ("Walls (3)", "Common (5)", "New Walls",
    /// "Floor Plan: Level 1") with a filter menu when the selection spans categories, and Edit Type on the right.
    @ViewBuilder var instanceBar: some View {
        let typeID = state.activeTool != nil ? CommandRouter(state: state).currentTypeID : editableTypeID
        HStack(spacing: 6) {
            if categoriesInSelection.count > 1 && state.placementCategory == nil {
                let total = categoriesInSelection.reduce(0) { $0 + $1.1 }
                let common: Bool = { if case .elements(_, true) = state.paletteSubject { return true }; return false }()
                Menu {
                    Button { setFilter(nil) } label: {
                        if common { Label("Common (\(total))", systemImage: "checkmark") } else { Text("Common (\(total))") }
                    }
                    Divider()
                    ForEach(categoriesInSelection, id: \.0) { c, n in
                        Button { setFilter(c) } label: {
                            if !common && c == targets.first?.category { Label("\(c.displayName) (\(n))", systemImage: "checkmark") } else { Text("\(c.displayName) (\(n))") }
                        }
                    }
                } label: { Text(instanceTitle).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                .menuStyle(.button).controlSize(.small).fixedSize(horizontal: false, vertical: true)
                .help("Show the parameters every selected element shares, or one category's")
                .accessibilityLabel("Show properties for: \(instanceTitle)")
            } else {
                Text(instanceTitle).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .help(instanceTitle)
                    .accessibilityLabel("Properties of \(instanceTitle)")
            }
            Spacer(minLength: 4)
            Button("Edit Type") { if let typeID { state.presented = .typeProperties(typeID) } }
                .controlSize(.small)
                .disabled(typeID == nil)
                .help(typeID == nil ? "The selection has no single type" : "Type parameters shared by every instance of this type")
                .accessibilityHint("Opens the type parameters shared by every instance of this type")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    func setFilter(_ c: Category?) {
        state.palette.filter = c
        state.palette.filterSelection = state.session.selection.ids
    }

    var instanceTitle: String {
        switch state.paletteSubject {
        case .newElement(let cat, _): return "New \(cat.displayName)"
        case .view(let id):
            guard let v = state.model[id] else { return "" }
            if let s = v.sheet { return "Sheet: \(s.number) – \(v.name)" }
            if v.schedule != nil { return "Schedule: \(v.name)" }
            return v.view.map { "\($0.kind.rawValue): \(v.name)" } ?? v.name
        case .elements(let ids, let common):
            guard let first = ids.first.flatMap({ state.model[$0] }) else { return "Nothing selected" }
            return common ? "Common (\(ids.count))" : "\(first.category.displayName) (\(ids.count))"
        case .nothing: return "Nothing selected"
        }
    }

    // MARK: Type selector

    /// Category governing the type selector: the active placement tool's category, or the selection's.
    var typeCategory: Category? {
        if let t = state.activeTool { return Self.category(for: t.commandID) }
        let ts = targets.filter { $0.typeID != nil }
        guard ts.count == targets.count else { return nil }
        let cats = Set(ts.map(\.category))
        return cats.count == 1 ? cats.first : nil
    }

    static func category(for cmd: CommandID) -> Category? {
        switch cmd {
        case .wall, .wallArc, .wallRectangle, .wallPickLines: .walls
        case .curtainWall: .walls // WP3
        case .curtainPanel: .curtainPanels // WP3
        case .door: .doors
        case .window: .windows
        case .component: .furniture
        case .column: .columns
        case .structuralColumn: .structuralColumns
        case .beam: .structuralFraming
        case .floor, .floorPickWalls: .floors
        case .ceiling: .ceilings
        case .roofFootprint, .roofPickWalls, .roofExtrusion: .roofs
        case .stairStraight, .stairL, .stairU: .stairs
        case .ramp: .ramps
        case .railing: .railings
        case .buildingPad: .buildingPads
        case .toposolid, .subdivideToposolid: .topography // BL-SITE
        case .detailComponent: .detailComponents
        case .symbol, .northArrow: .genericAnnotations
        case .textNote: .textNotes
        case .alignedDimension, .linearDimension, .angularDimension, .radialDimension, .diameterDimension, .arcLengthDimension: .dimensions // W2-ANNOT
        case .filledRegion: .filledRegions // W2-ANNOT
        case .repeatingDetailComponent: .detailComponents // W2-ANNOT
        default: nil
        }
    }

    @ViewBuilder var typeSelector: some View {
        if let cat = typeCategory {
            TypeSelectorButton(state: state, category: cat, currentTypeID: state.activeTool != nil ? (state.currentTypes[cat] ?? typesFor(cat).first?.id) : editableTypeID,
                               types: typesFor(cat)) { t in
                choose(t.id, category: t.typeData?.instanceCategory ?? cat)
            }
        } else if let t = targets.first, t.sheet != nil {
            SheetTitleBlockSelector(state: state, sheetID: t.id) // BL-BROWSER: the title block type sets the sheet size
        } else if let t = targets.first {
            HStack {
                Image(systemName: t.view?.kind.symbolName ?? (t.sheet != nil ? "doc.richtext" : "square.dashed")).foregroundStyle(.secondary)
                Text(t.view != nil ? t.view!.kind.rawValue : (targets.count > 1 && Set(targets.map(\.category)).count > 1 ? "Multiple Categories" : t.category.singularName))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
        }
    }

    func typesFor(_ cat: Category) -> [Element] {
        let cats: [Category] = cat == .furniture && state.activeTool != nil ? Category.componentCategories : [cat] // W2-LIB
        return cats.flatMap { state.model.types(for: $0) }
    }

    func choose(_ typeID: ElementID, category: Category) {
        state.palette.recentTypes = TypeSelectorModel.noteUse(typeID, in: state.palette.recentTypes) // BL-PROPS
        if state.activeTool != nil {
            state.currentTypes[category] = typeID
            if category.isComponentCategory { // W2-LIB
                state.currentTypes[.furniture] = typeID
            }
            for c in state.toolContexts.values { c.currentTypes = state.currentTypes }
            // Re-create component tools so the new category takes effect.
            if let t = state.activeTool, t.commandID == .component { CommandRouter(state: state).run(.component) }
            state.syncCreationDefaults() // BL-PROPS
            state.toolChangedState()
        } else {
            let ids = targets.filter { $0.typeID != nil && ($0.category == category || state.model[typeID]?.typeData?.instanceCategory == $0.category) }.map(\.id)
            state.session.setParameter(ParameterID("familyAndType"), value: .ref(typeID), on: ids, name: "Type")
        }
    }
}

/// Small color swatch hinting at a type's primary material.
struct TypeSwatch: View {
    let type: Element?
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
    var color: Color {
        guard let td = type?.typeData else { return .secondary.opacity(0.2) }
        if let m = td.assembly?.layers.first?.materialID { _ = m }
        return ElementMeshes.defaultColor(td.instanceCategory).color
    }
}

/// One parameter row with an editor appropriate to its type.
struct ParamRow: View {
    let state: DocumentState
    let entry: ParameterEntry
    let targets: [ElementID]
    /// BL-PROPS: the value differs across the elements shown ("<varies>"); never true for one element.
    var varies = false
    var labelWidth: CGFloat = Tokens.inspectorLabelWidth
    /// BL-PROPS: where edits go instead of the model (new-element values, staged Type Properties edits).
    var apply: ((ParameterID, ParamValue) throws(ParameterError) -> Void)? = nil
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var model: BIMModel { state.model }
    /// The value to display: nil when it varies.
    var shown: ParamValue? { varies ? nil : entry.value }
    var formatted: String { shown.map { Parameters.format($0, type: entry.type, model: model) } ?? "" }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(entry.name)
                .font(Tokens.label)
                .foregroundStyle(entry.isReadOnly ? .secondary : .primary)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)
                .help(entry.tooltip.isEmpty ? entry.name : "\(entry.name): \(entry.tooltip)")
            editor
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(varies ? "Values differ across the selection" : (entry.isReadOnly ? [formatted, entry.readOnlyReason ?? ""].filter { !$0.isEmpty }.joined(separator: "\n") : formatted))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: Tokens.inspectorRowHeight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder var editor: some View {
        if entry.isReadOnly {
            Text(varies ? "<varies>" : (formatted.isEmpty ? "—" : formatted))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("\(entry.name): \(varies ? "varies" : formatted). Read only. \(entry.readOnlyReason ?? "")")
        } else {
            switch entry.type {
            case .bool:
                Toggle("", isOn: Binding(get: { shown?.boolValue ?? false }, set: { commit(.bool($0)) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(entry.name)
                    .accessibilityValue(varies ? "varies" : ((shown?.boolValue ?? false) ? "on" : "off"))
            case .choice(let options):
                Picker("", selection: Binding(get: { shown?.textValue ?? "" }, set: { commit(.text($0)) })) {
                    if varies || !(options.contains(shown?.textValue ?? "")) { Text(varies ? "<varies>" : "").tag("") }
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(entry.name)
            case .elementRef(.materials):
                MaterialPicker(state: state, selection: Binding(get: { shown?.refValue }, set: { commit(.ref($0)) }),
                               noneLabel: varies ? "<varies>" : "<By Category>")
                    .controlSize(.small)
            case .elementRef(.fillPatterns): // W4-HATCH: patterns with previews
                FillPatternMenu(state: state, selection: Binding(get: { shown?.refValue }, set: { commit(.ref($0)) }), noneLabel: varies ? "<varies>" : "<None>")
                    .controlSize(.small)
            case .elementRef(.lineStyles): // W2-ANNOT: styles with pattern previews
                LineStyleMenu(styles: LineStyleMenu.styles(model), current: shown?.refValue.flatMap { model[$0]?.name } ?? "",
                              placeholder: varies ? "<varies>" : "<None>") { name in
                    if let id = model.lineStyle(named: name)?.id { commit(.ref(id)) }
                }
                .controlSize(.small)
            case .elementRef(let c):
                refPicker(c)
            case .multilineText:
                textField(multiline: true)
            default:
                textField(multiline: false)
            }
        }
    }

    func refPicker(_ c: Category) -> some View {
        let options: [Element]
        switch c {
        case .elementTypes:
            let cat = targets.first.flatMap { model[$0]?.category }
            options = cat.map { model.types(for: $0) } ?? []
        case .levels: options = model.levels
        case .curtainPanels: options = model.types(for: .curtainPanels) // WP3: panel types
        case .phases: options = model.phases
        default: options = model.elements(c).sorted { $0.name < $1.name }
        }
        let noneLabel = c == .levels ? "Unconnected" : "<None>"
        return Picker("", selection: Binding(get: { shown?.refValue?.raw ?? 0 }, set: { commit(.ref($0 == 0 ? nil : ElementID($0))) })) {
            Text(varies ? "<varies>" : noneLabel).tag(UInt64(0))
            ForEach(options, id: \.id) { e in
                Text(e.typeData.map { "\($0.familyName): \(e.name)" } ?? e.name).tag(e.id.raw)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .accessibilityLabel(entry.name)
    }

    func textField(multiline: Bool) -> some View {
        TextField(varies ? "<varies>" : "", text: $text, axis: multiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .font(.system(size: 11).monospacedDigit())
            .lineLimit(multiline ? 1...4 : 1...1)
            .focused($focused)
            .onAppear { text = formatted }
            .onChange(of: formatted) { _, new in if !focused { text = new } }
            .onSubmit { commitText() }
            .onChange(of: focused) { _, f in if !f { commitText() } }
            .onExitCommand { text = formatted; focused = false }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(focused ? Color(nsColor: .textBackgroundColor) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(focused ? Tokens.selectionColor : Color.clear, lineWidth: 1))
            .accessibilityLabel(entry.name)
            .accessibilityValue(text)
    }

    func commitText() {
        guard text != formatted else { return }
        if varies && text.isEmpty { return }
        if apply != nil {
            do { commit(try Parameters.parse(text, type: entry.type, model: model)) } catch { state.show(error.message, error: true); text = formatted }
            return
        }
        state.session.setParameter(entry.id, text: text, on: targets, type: entry.type, name: entry.name)
        if let e = state.session.lastError {
            state.show(e.message, error: true)
            state.session.clearError()
            text = formatted
        }
    }

    func commit(_ v: ParamValue) {
        if let apply {
            do { try apply(entry.id, v) } catch { state.show(error.message, error: true); text = formatted }
            return
        }
        state.session.setParameter(entry.id, value: v, on: targets, name: entry.name)
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
    }
}

/// BL-PROPS: the draggable boundary between the label and value columns (width persisted per user).
struct ColumnDivider: View {
    @Binding var labelWidth: Double
    var maxWidth: CGFloat
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        let x = CGFloat(labelWidth) + 4 + 10 + 3 // row padding + half the row spacing
        Rectangle()
            .fill(Color.primary.opacity(hovering || start != nil ? 0.25 : 0.06))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .frame(maxHeight: .infinity)
            .offset(x: x - 3.5)
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                if start == nil { start = labelWidth }
                labelWidth = min(Double(maxWidth), max(70, (start ?? labelWidth) + g.translation.width))
            }.onEnded { _ in start = nil })
            .accessibilityElement()
            .accessibilityLabel("Column divider")
            .accessibilityValue("\(Int(labelWidth)) points")
            .accessibilityAdjustableAction { d in
                labelWidth = min(Double(maxWidth), max(70, labelWidth + (d == .increment ? 10 : -10)))
            }
    }
}
