import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// COMP: the Components panel (docked with Properties) and the Component Browser window (the same content at full
// size). Search with synonyms, sizes and typo tolerance; categories and subcategories; Favorites, Recent and My
// Components; filters (host, material) and sorting; grid or list of thumbnails from real geometry; a 2D/3D preview
// (drag to turn, scroll to zoom, Iso/Front/Side/Top/Fit); type and preset; Insert, Replace and Save as Preset.

/// The panel's layout: docked (narrow, preview under the results) or the browser window (sidebar, grid, inspector).
enum ComponentsLayout { case docked, browser }

struct ComponentsPanel: View {
    @Bindable var state: DocumentState
    var layout: ComponentsLayout = .docked
    @Bindable var model: ComponentPanelModel

    init(state: DocumentState, layout: ComponentsLayout = .docked, model: ComponentPanelModel? = nil) {
        self.state = state
        self.layout = layout
        self.model = model ?? ComponentPanelModel.of(state)
    }

    var body: some View {
        switch layout {
        case .docked: docked
        case .browser: browser
        }
    }

    // MARK: Docked

    private var docked: some View {
        VStack(spacing: 0) {
            header
            ComponentSearchField(model: model).padding(.horizontal, 12).padding(.bottom, 8)
            toolbar.padding(.horizontal, 12).padding(.bottom, 6)
            Divider()
            ComponentResults(model: model, state: state, thumb: 76)
                .frame(maxHeight: .infinity)
            if model.selected != nil {
                Divider()
                ComponentDetail(model: model, state: state, previewHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Components").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { ComponentBrowserWindow.show(state) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.borderless).help("Open the Component Browser").accessibilityLabel("Open the Component Browser")
            Button { model.isShown = false; state.onWorkspaceChange?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Hide the Components panel").accessibilityLabel("Hide the Components panel")
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Picker("Show", selection: $model.section) {
                Image(systemName: "square.grid.2x2").help("All").tag(ComponentSection.all)
                Image(systemName: "star").help("Favorites").tag(ComponentSection.favorites)
                Image(systemName: "clock").help("Recently Used").tag(ComponentSection.recent)
                Image(systemName: "person.crop.square").help("My Components").tag(ComponentSection.mine)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            ComponentCategoryMenu(model: model)
            Spacer(minLength: 0)
            ComponentFilterMenu(model: model)
            Button { model.gridView.toggle() } label: { Image(systemName: model.gridView ? "list.bullet" : "square.grid.2x2") }
                .buttonStyle(.borderless).help(model.gridView ? "Show as List" : "Show as Grid")
        }
        .controlSize(.small)
    }

    // MARK: Browser

    private var browser: some View {
        HStack(spacing: 0) {
            ComponentSidebar(model: model).frame(width: 230)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ComponentSearchField(model: model)
                    ComponentFilterMenu(model: model)
                    Picker("Sort", selection: $model.sort) { ForEach(ComponentSort.allCases) { Text($0.rawValue).tag($0) } }
                        .labelsHidden().fixedSize().help("Sort by")
                    Picker("View", selection: $model.gridView) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                .controlSize(.regular)
                .padding(12)
                Divider()
                ComponentResults(model: model, state: state, thumb: 120)
            }
            .frame(minWidth: 420, maxWidth: .infinity)
            Divider()
            ComponentDetail(model: model, state: state, previewHeight: 260)
                .frame(width: 320)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Search

struct ComponentSearchField: View {
    @Bindable var model: ComponentPanelModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search components", text: $model.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.store.searched(model.query) }
                .accessibilityLabel("Search components")
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
            if !model.store.recentSearches.items.isEmpty {
                Menu {
                    Section("Recent Searches") {
                        ForEach(model.store.recentSearches.items, id: \.self) { q in Button(q) { model.query = q } }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath") }
                .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize().help("Recent searches")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(focused ? 0.25 : 0.08)))
    }
}

struct ComponentCategoryMenu: View {
    @Bindable var model: ComponentPanelModel
    var body: some View {
        Menu {
            Button("All Categories") { model.category = nil; model.subcategory = nil }
            Divider()
            ForEach(ComponentCategory.allCases) { c in
                Button { model.category = c; model.subcategory = nil } label: { Label("\(c.code)  \(c.title)", systemImage: c.symbol) }
            }
        } label: {
            Text(model.category.map { "\($0.code) \($0.title)" } ?? "All Categories").lineLimit(1)
        }
        .menuStyle(.button).fixedSize().help("Category")
    }
}

struct ComponentFilterMenu: View {
    @Bindable var model: ComponentPanelModel
    static let materials = ["Steel", "Stainless Steel", "Chrome", "Satin Nickel", "Matte Black", "Brass", "Bronze", "Aluminum", "Plastic", "Nylon", "Oak", "Walnut", "Glass"]
    var active: Bool { model.host != nil || model.material != nil || model.subcategory != nil }
    var body: some View {
        Menu {
            if !model.subcategories.isEmpty {
                Picker("Subcategory", selection: $model.subcategory) {
                    Text("All").tag(String?.none)
                    ForEach(model.subcategories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            Picker("Goes On", selection: $model.host) {
                Text("Anything").tag(ComponentHostKind?.none)
                ForEach(ComponentHostKind.allCases, id: \.self) { Text($0.rawValue).tag(ComponentHostKind?.some($0)) }
            }
            Picker("Material", selection: $model.material) {
                Text("Any").tag(String?.none)
                ForEach(Self.materials, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Picker("Sort By", selection: $model.sort) { ForEach(ComponentSort.allCases) { Text($0.rawValue).tag($0) } }
            if active {
                Divider()
                Button("Clear Filters") { model.host = nil; model.material = nil; model.subcategory = nil }
            }
        } label: {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize().help("Filter and sort")
        .accessibilityLabel("Filter and sort")
    }
}

// MARK: - Sidebar (browser)

struct ComponentSidebar: View {
    @Bindable var model: ComponentPanelModel
    var body: some View {
        List {
            Section("Library") {
                ForEach(ComponentSection.allCases) { s in
                    row(s.rawValue, symbol: symbol(s), selected: model.section == s && model.category == nil) { model.section = s; model.category = nil; model.subcategory = nil }
                }
            }
            Section("Categories") {
                ForEach(ComponentCategory.allCases) { c in
                    row("\(c.code)  \(c.title)", symbol: c.symbol, selected: model.category == c && model.subcategory == nil, count: model.count(c)) {
                        model.section = .all; model.category = c; model.subcategory = nil
                    }
                    if model.category == c {
                        ForEach(model.subcategories, id: \.self) { s in
                            row(s, symbol: nil, selected: model.subcategory == s, indent: true) { model.subcategory = s }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    func symbol(_ s: ComponentSection) -> String {
        switch s { case .all: "square.grid.2x2"; case .favorites: "star"; case .recent: "clock"; case .mine: "person.crop.square" }
    }

    func row(_ title: String, symbol: String?, selected: Bool, count: Int? = nil, indent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).frame(width: 16).foregroundStyle(selected ? Color.accentColor : .secondary) }
                Text(title).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 0)
                if let count, count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
            .padding(.leading, indent ? 22 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color.accentColor.opacity(0.14) : Color.clear)
    }
}

// MARK: - Results

struct ComponentResults: View {
    @Bindable var model: ComponentPanelModel
    @Bindable var state: DocumentState
    var thumb: CGFloat

    var body: some View {
        let results = model.results
        Group {
            if results.isEmpty {
                ComponentEmptyState(model: model)
            } else if model.gridView {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: thumb + 8, maximum: thumb + 40), spacing: 8)], spacing: 10) {
                        ForEach(results, id: \.definition.id) { r in ComponentCell(result: r, model: model, state: state, thumb: thumb) }
                    }
                    .padding(10)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results, id: \.definition.id) { r in ComponentRow(result: r, model: model, state: state) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityLabel("\(results.count) components")
    }
}

struct ComponentEmptyState: View {
    @Bindable var model: ComponentPanelModel
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 20)
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 240)
            if !model.query.isEmpty || model.category != nil || model.host != nil || model.material != nil {
                Button("Clear Search and Filters") { model.query = ""; model.category = nil; model.subcategory = nil; model.host = nil; model.material = nil }
                    .controlSize(.small)
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    var icon: String {
        switch model.section { case .favorites: "star"; case .recent: "clock"; case .mine: "person.crop.square"; case .all: "magnifyingglass" }
    }
    var title: String {
        if !model.query.isEmpty { return "No Matches" }
        switch model.section {
        case .favorites: return "No Favorites"
        case .recent: return "Nothing Used Yet"
        case .mine: return "No Components of Your Own"
        case .all: return "No Components"
        }
    }
    var message: String {
        if !model.query.isEmpty { return "Nothing matches “\(model.query)”. Try another word or a size, like “hinge 110”." }
        switch model.section {
        case .favorites: return "Star a component to keep it here."
        case .recent: return "Components you place show here."
        case .mine: return "Duplicate a component to customize it, or use Save Selection as Component."
        case .all: return "No components in this category."
        }
    }
}

struct ComponentCell: View {
    let result: ComponentSearchResult
    @Bindable var model: ComponentPanelModel
    @Bindable var state: DocumentState
    var thumb: CGFloat
    var selected: Bool { model.selectedID == result.definition.id }

    var body: some View {
        let d = result.definition
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ComponentThumbnail(definition: d, type: result.typeName ?? d.defaultType?.name ?? "", size: CGSize(width: thumb, height: thumb * 0.82))
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                if model.store.isFavorite(d.id) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).padding(5) }
                if d.isUserComponent { Image(systemName: "person.fill").font(.system(size: 8)).foregroundStyle(.secondary).padding(5).offset(x: 0, y: 14) }
            }
            Text(d.name).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center).frame(height: 28, alignment: .top)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Color.accentColor.opacity(0.16) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.select(result); ComponentPanelActions.insert(state) }
        .onTapGesture { model.select(result) }
        .contextMenu { ComponentContextMenu(definition: d, model: model, state: state) }
        .help("\(d.name)\n\(d.category.title) · \(d.subcategory)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.name)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct ComponentRow: View {
    let result: ComponentSearchResult
    @Bindable var model: ComponentPanelModel
    @Bindable var state: DocumentState
    var selected: Bool { model.selectedID == result.definition.id }

    var body: some View {
        let d = result.definition
        HStack(spacing: 9) {
            ComponentThumbnail(definition: d, type: result.typeName ?? d.defaultType?.name ?? "", size: CGSize(width: 34, height: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.system(size: 12)).lineLimit(1)
                Text("\(d.subcategory) · \(d.types.count) \(d.types.count == 1 ? "type" : "types")").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.store.isFavorite(d.id) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(0.16) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.select(result); ComponentPanelActions.insert(state) }
        .onTapGesture { model.select(result) }
        .contextMenu { ComponentContextMenu(definition: d, model: model, state: state) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.name)
    }
}

struct ComponentContextMenu: View {
    let definition: ComponentDefinition
    @Bindable var model: ComponentPanelModel
    @Bindable var state: DocumentState
    var body: some View {
        Button("Insert") { model.select(id: definition.id); ComponentPanelActions.insert(state) }
        Button("Replace Selected") { model.select(id: definition.id); ComponentPanelActions.replace(state) }
            .disabled(!ComponentPanelActions.canReplace(state))
        Divider()
        Button(model.store.isFavorite(definition.id) ? "Remove from Favorites" : "Add to Favorites") { model.store.toggleFavorite(definition.id) }
        Button("Duplicate to Customize") { ComponentPanelActions.duplicate(definition, state) }
        if definition.isUserComponent {
            Button("Delete from My Components", role: .destructive) { ComponentPanelActions.delete(definition, state) }
        }
    }
}

// MARK: - Detail

struct ComponentDetail: View {
    @Bindable var model: ComponentPanelModel
    @Bindable var state: DocumentState
    var previewHeight: CGFloat

    var body: some View {
        if let d = model.selected {
            VStack(alignment: .leading, spacing: 8) {
                ComponentPreview(model: model, definition: d, height: previewHeight)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text("\(d.category.code) \(d.category.title) · \(d.subcategory)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { model.store.toggleFavorite(d.id) } label: { Image(systemName: model.store.isFavorite(d.id) ? "star.fill" : "star") }
                        .buttonStyle(.borderless).foregroundStyle(model.store.isFavorite(d.id) ? Color.yellow : Color.secondary)
                        .help(model.store.isFavorite(d.id) ? "Remove from Favorites" : "Add to Favorites")
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 5) {
                    GridRow {
                        Text("Type").foregroundStyle(.secondary)
                        Picker("Type", selection: Binding(get: { model.selectedType ?? "" }, set: { model.typeName = $0 })) {
                            ForEach(d.types, id: \.name) { Text($0.name).tag($0.name) }
                        }
                        .labelsHidden()
                    }
                    let presets = model.store.presets(for: d)
                    if !presets.isEmpty {
                        GridRow {
                            Text("Preset").foregroundStyle(.secondary)
                            Picker("Preset", selection: $model.presetName) {
                                Text("None").tag(String?.none)
                                ForEach(presets, id: \.name) { Text($0.name).tag(String?.some($0.name)) }
                            }
                            .labelsHidden()
                        }
                    }
                    if let t = d.type(named: model.selectedType ?? "") ?? d.defaultType {
                        GridRow {
                            Text("Cost").foregroundStyle(.secondary)
                            Text(String(format: "$%.2f · %@ · %@", t.cost, t.manufacturer, t.sku)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    GridRow {
                        Text("Goes on").foregroundStyle(.secondary)
                        Text(d.placement.hosts.prefix(4).map(\.rawValue).joined(separator: ", ")).lineLimit(2)
                    }
                    if let el = d.electrical {
                        GridRow {
                            Text("Power").foregroundStyle(.secondary)
                            Text("\(el.supply) · \(el.cable)").lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 11.5))
                .controlSize(.small)
                HStack(spacing: 6) {
                    Button("Insert") { ComponentPanelActions.insert(state) }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .help("Place it on a door, drawer, panel, shelf or bay")
                    Button("Replace") { ComponentPanelActions.replace(state) }
                        .disabled(!ComponentPanelActions.canReplace(state))
                        .help(ComponentPanelActions.canReplace(state) ? "Replace the selected components with this one" : "Select placed components to replace")
                    Spacer(minLength: 0)
                    Menu {
                        Button("Save as Preset…") { state.presented = .comp(.savePreset(d.id)) }
                        Button("Duplicate to Customize") { ComponentPanelActions.duplicate(d, state) }
                        if d.isUserComponent { Button("Delete from My Components", role: .destructive) { ComponentPanelActions.delete(d, state) } }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize().help("More")
                }
                .controlSize(.small)
            }
            .padding(12)
        } else {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "square.dashed").font(.system(size: 26)).foregroundStyle(.tertiary)
                Text("No Component Selected").font(.system(size: 13, weight: .semibold))
                Text("Pick one to preview it.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Actions

@MainActor
enum ComponentPanelActions {
    /// Starts Place Component with the selected component.
    static func insert(_ state: DocumentState) {
        let model = ComponentPanelModel.of(state)
        guard let d = model.selected else { state.show("Pick a component in the Components panel first."); return }
        if let tool = state.activeTool as? ComponentPlaceTool { tool.use(d, typeName: model.selectedType, values: model.presetValues); return }
        CommandRouter(state: state).run(.componentPlace)
    }

    /// Placed components in the selection.
    static func selectedComponents(_ state: DocumentState) -> [ElementID] {
        state.session.selection.ids.filter { id in
            guard let e = state.model[id] else { return false }
            return e.category == .furnitureHardware && !e.isType && e.params[FurnitureHardware.slotParam] == nil
        }
    }
    static func canReplace(_ state: DocumentState) -> Bool { !selectedComponents(state).isEmpty }

    static func replace(_ state: DocumentState) {
        let model = ComponentPanelModel.of(state)
        let ids = selectedComponents(state)
        guard let d = model.selected, !ids.isEmpty else { state.show("Select placed components, then pick the one to replace them with."); return }
        var warnings: [ModelWarning] = []
        state.session.perform("Replace with \(d.name)") { tx in warnings = try ComponentPlacement.replace(ids, with: d, typeName: model.selectedType, in: tx) }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        model.store.used(d.id)
        state.show(warnings.first?.message ?? "Replaced \(ids.count) with \(d.name).")
    }

    static func duplicate(_ d: ComponentDefinition, _ state: DocumentState) {
        let store = ComponentLibraryStore.shared
        let copy = ComponentUserLibrary.duplicate(d, existing: store.catalog.all.map(\.name))
        do {
            try store.addUserComponent(copy)
            ComponentPanelModel.of(state).section = .mine
            ComponentPanelModel.of(state).select(id: copy.id)
            state.show("Added \(copy.name) to My Components.")
        } catch { state.show(DialogErrorText.describe(error), error: true) }
    }

    static func delete(_ d: ComponentDefinition, _ state: DocumentState) {
        do { try ComponentLibraryStore.shared.removeUserComponent(d); ComponentPanelModel.of(state).selectedID = nil }
        catch { state.show(DialogErrorText.describe(error), error: true) }
    }
}
