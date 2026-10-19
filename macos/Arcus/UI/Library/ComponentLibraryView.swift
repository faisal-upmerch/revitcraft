import SwiftUI
import AppKit
import ArcusCalc
import ArcusDomain
import ArcusApplication

// W2-LIB: the Component Library browser. A searchable catalog of the built-in families with a category sidebar,
// region filter, grid or list of generated previews, a size picker and Place (loads the family on first use and starts
// the Component tool). Fully keyboard driven: type to search, arrows to move, Return to place, Esc to close.

/// Sidebar selection in the library browser.
enum LibrarySidebarItem: Hashable {
    case all, recent, inProject
    case category(Category)
    case group(Category, String)
    /// FM9: the Furniture Library (nil = all its pieces, else one room).
    case furniture(String?)
}

struct ComponentLibraryView: View {
    let state: DocumentState
    /// Categories the browser is limited to (empty = the whole library).
    let categories: [Category]
    /// FM9: the Furniture Library pieces shown (tests pass their own; the app scans the library).
    var furnitureItems: [FurnitureLibraryCatalog.Item]? = nil

    @State private var query = ""
    @State private var region: LibraryRegion?
    @State private var sidebar: LibrarySidebarItem = .all
    @State private var selectedID: String?
    @State private var chosenType: [String: String] = [:]
    @State private var listLayout = false
    @State private var planPreview = false
    @State private var showAllSizes = false
    @State private var columns = 4
    @State private var expanded: Set<Category> = []
    @FocusState private var searchFocused: Bool
    /// FM9: the Furniture Library's pieces (bundled and the user's templates) and the selected one.
    @State private var furniture: [FurnitureLibraryCatalog.Item] = []
    @State private var furnitureSelected: String?

    /// FM9: QA captures open the browser on the Furniture Library.
    static var startInFurniture = false

    /// FM9: the Furniture Library shows when the browser isn't limited to other categories.
    var showsFurniture: Bool { categories.isEmpty || categories.contains(.furniture) || categories.contains(.casework) }
    var furnitureRoom: String?? { if case .furniture(let r) = sidebar { return .some(r) }; return nil }
    var furnitureRooms: [FurnitureLibraryCatalog.Room] { FurnitureRoomList.rooms(furniture, room: furnitureRoom ?? nil, query: query) }
    var furnitureItem: FurnitureLibraryCatalog.Item? {
        let list = furnitureRooms.flatMap(\.items)
        return list.first { $0.id == furnitureSelected } ?? list.first
    }

    static let cardWidth: CGFloat = 164
    static let cardSpacing: CGFloat = 12

    var units: UnitsSettings { state.model.units }
    var baseItems: [ComponentLibraryItem] { ComponentLibrary.items(in: categories) }
    var visibleCategories: [Category] { ComponentLibrary.categories.filter { c in categories.isEmpty || categories.contains(c) } }

    var loadedNames: Set<String> {
        Set(state.model.elements(.families).map(\.name))
    }

    /// Items after the sidebar, region and search filters.
    var items: [ComponentLibraryItem] {
        var list = baseItems
        switch sidebar {
        case .all: break
        case .recent:
            let order = LibraryRecents.names
            list = order.compactMap { n in list.first { $0.name == n } }
        case .inProject:
            let names = loadedNames
            list = list.filter { names.contains($0.name) }
        case .category(let c): list = list.filter { $0.category == c }
        case .group(let c, let g): list = list.filter { $0.category == c && $0.group == g }
        case .furniture: return [] // FM9: the Furniture Library has its own grid
        }
        return list.filter { $0.isAvailable(in: region) && $0.matches(query) }
    }

    var selected: ComponentLibraryItem? {
        let list = items
        return list.first { $0.id == selectedID } ?? list.first
    }

    func types(of item: ComponentLibraryItem) -> [ComponentLibraryType] {
        item.types(for: units.system, region: region, showAll: showAllSizes)
    }

    func typeName(for item: ComponentLibraryItem) -> String {
        if let t = chosenType[item.id], item.family.type(named: t) != nil { return t }
        return item.defaultType(for: units.system, region: region).name
    }

    var title: String {
        if categories.isEmpty { return "Component Library" }
        if categories == ComponentLibrary.siteCategories { return "Site & Parking Library" }
        return categories.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebarView.frame(width: 214)
                Divider()
                if furnitureRoom != nil {
                    furnitureBrowser.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Group { if let f = furnitureItem { FurniturePieceDetail(item: f) } else { Color.clear } }.frame(width: 300)
                } else {
                    browser(list).frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    detail.frame(width: 300)
                }
            }
            Divider()
            if furnitureRoom != nil { furnitureFooter } else { footer(list) }
        }
        .frame(width: 1120, height: 720)
        .onAppear {
            if showsFurniture { furniture = furnitureItems ?? FurnitureLibraryCatalog.all() } // FM9
            if Self.startInFurniture, showsFurniture { sidebar = .furniture(nil) }
            searchFocused = true
            if categories.count == 1, let c = categories.first { sidebar = .category(c) }
            expanded = Set(visibleCategories.prefix(categories.isEmpty ? 1 : visibleCategories.count))
        }
        .onChange(of: query) { _, _ in selectedID = items.first?.id }
        .onChange(of: sidebar) { _, _ in selectedID = items.first?.id }
        .onChange(of: region) { _, _ in if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id } }
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 12) {
            DialogIconTile(symbol: categories == ComponentLibrary.siteCategories ? "tree" : "books.vertical", tint: categories == ComponentLibrary.siteCategories ? .green : .blue) // DIALOGS
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.semibold))
                Text("\(baseItems.count) families · \(baseItems.reduce(0) { $0 + $1.types.count }) sizes · loaded into the project only when used")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search furniture, fixtures, trees, vehicles…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { placeSelected() }
                    .onKeyPress(.downArrow) { move(listLayout ? 1 : columns); return .handled }
                    .onKeyPress(.upArrow) { move(listLayout ? -1 : -columns); return .handled }
                    .accessibilityLabel("Search the component library")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .frame(width: 330)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden().frame(width: 0)
            Picker("Region", selection: $region) {
                Text("All Regions").tag(LibraryRegion?.none)
                Divider()
                ForEach(LibraryRegion.allCases.filter { $0 != .global }) { r in Text(r.displayName).tag(LibraryRegion?.some(r)) }
            }
            .labelsHidden()
            .frame(width: 124)
            .help("Show items typical of a region; global items always show")
            Picker("Layout", selection: $listLayout) {
                Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("Grid")
                Image(systemName: "list.bullet").tag(true).accessibilityLabel("List")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help("Grid or list")
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: Sidebar

    var sidebarView: some View {
        let names = loadedNames
        let recent = LibraryRecents.names.filter { n in baseItems.contains { $0.name == n } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                sidebarRow(.all, categories.isEmpty ? "All Components" : "All", symbol: "square.grid.3x3", count: baseItems.count)
                if !recent.isEmpty { sidebarRow(.recent, "Recently Placed", symbol: "clock", count: recent.count) }
                sidebarRow(.inProject, "In This Project", symbol: "checkmark.circle", count: baseItems.filter { names.contains($0.name) }.count)
                if showsFurniture, !furniture.isEmpty { furnitureSection } // FM9
                Text("Categories").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 3)
                ForEach(visibleCategories, id: \.self) { c in
                    let groups = ComponentLibrary.groups(in: c)
                    HStack(spacing: 0) {
                        Button {
                            if expanded.contains(c) { expanded.remove(c) } else { expanded.insert(c) }
                        } label: {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(expanded.contains(c) ? 90 : 0))
                                .frame(width: 14, height: 18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(expanded.contains(c) ? "Collapse \(c.displayName)" : "Expand \(c.displayName)")
                        sidebarRow(.category(c), c.displayName, symbol: Self.symbol(for: c), count: ComponentLibrary.items(in: [c]).count)
                    }
                    if expanded.contains(c) {
                        ForEach(groups, id: \.self) { g in
                            sidebarRow(.group(c, g), g, symbol: nil, count: ComponentLibrary.items(in: [c]).filter { $0.group == g }.count)
                                .padding(.leading, 26)
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color.primary.opacity(0.025))
    }

    func sidebarRow(_ sel: LibrarySidebarItem, _ label: String, symbol: String?, count: Int) -> some View {
        let on = sidebar == sel
        return Button { sidebar = sel } label: {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).frame(width: 16).foregroundStyle(on ? Color.white : Color.accentColor) }
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.system(size: 12.5, weight: on ? .medium : .regular))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.accentColor : .clear))
            .modifier(HoverBackground(radius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .accessibilityLabel("\(label), \(count) items")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func symbol(for c: Category) -> String {
        switch c {
        case .furniture: "sofa"
        case .casework: "cabinet"
        case .specialtyEquipment: "refrigerator"
        case .plumbingFixtures: "toilet"
        case .lightingFixtures: "lightbulb"
        case .electricalFixtures: "bolt"
        case .mechanicalEquipment: "fan"
        case .planting: "tree"
        case .entourage: "figure.walk"
        case .site: "signpost.right"
        case .parking: "parkingsign"
        default: "cube"
        }
    }

    // MARK: Furniture Library (FM9)

    /// The sidebar's Furniture Library section: all its pieces and each room.
    @ViewBuilder var furnitureSection: some View {
        Text("Furniture Library").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 3)
        sidebarRow(.furniture(nil), "All Pieces", symbol: "chair.lounge", count: Set(furniture.map(\.url)).count)
        ForEach(FurnitureLibraryCatalog.rooms(furniture)) { r in
            sidebarRow(.furniture(r.name), r.name, symbol: FurnitureRoomList.symbol(r.name), count: r.items.count).padding(.leading, 14)
        }
    }

    @ViewBuilder var furnitureBrowser: some View {
        let rooms = furnitureRooms
        if rooms.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text("No pieces match “\(query)”").font(.title3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                FurnitureLibraryGrid(rooms: rooms, selectedID: furnitureItem?.id, onSelect: { furnitureSelected = $0.id }, onOpen: { placeFurniture($0) })
                    .padding(14)
            }
        }
    }

    var furnitureFooter: some View {
        HStack(spacing: 10) {
            Text("\(Set(furnitureRooms.flatMap(\.items).map(\.url)).count) pieces · loads as a family").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            Text("Double-click or press Place to load and place").font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction)
            Button("Place") { if let f = furnitureItem { placeFurniture(f) } }
                .keyboardShortcut(.defaultAction)
                .disabled(furnitureItem == nil)
                .help("Load the piece as a family (compiled from its furniture document) and start placing it")
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    func placeFurniture(_ item: FurnitureLibraryCatalog.Item) {
        state.presented = nil
        let url = item.url
        DispatchQueue.main.async { FurnitureFileLoad.place(url, in: state) }
    }

    // MARK: Browser

    @ViewBuilder
    func browser(_ list: [ComponentLibraryItem]) -> some View {
        if list.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text(query.isEmpty ? "Nothing here yet" : "No components match “\(query)”").font(.title3).foregroundStyle(.secondary)
                if region != nil { Button("Show All Regions") { region = nil } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if listLayout {
                            LazyVStack(spacing: 2) {
                                ForEach(list) { item in listRow(item).id(item.id) }
                            }
                            .padding(10)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: Self.cardSpacing), count: columns),
                                      alignment: .leading, spacing: Self.cardSpacing) {
                                ForEach(list) { item in card(item).id(item.id) }
                            }
                            .padding(14)
                        }
                    }
                    .onChange(of: selectedID) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
                }
                .onAppear { columns = Self.columnCount(geo.size.width) }
                .onChange(of: geo.size.width) { _, w in columns = Self.columnCount(w) }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.rightArrow) { move(1); return .handled }
            .onKeyPress(.leftArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(listLayout ? 1 : columns); return .handled }
            .onKeyPress(.upArrow) { move(listLayout ? -1 : -columns); return .handled }
            .onKeyPress(.return) { placeSelected(); return .handled }
        }
    }

    static func columnCount(_ width: CGFloat) -> Int { max(1, Int((width - 28 + cardSpacing) / (cardWidth + cardSpacing))) }

    func card(_ item: ComponentLibraryItem) -> some View {
        let on = item.id == selected?.id
        let loaded = loadedNames.contains(item.name)
        let t = typeName(for: item)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                LibraryPreview(item: item, type: t, plan: planPreview, size: CGSize(width: Self.cardWidth - 16, height: 104))
                    .padding(8)
                if loaded {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.green)
                        .background(Circle().fill(.white).padding(1)).padding(6)
                        .help("Already in this project")
                }
            }
            .frame(height: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(2, reservesSpace: true)
                Text(subtitle(item)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(6)
        .frame(width: Self.cardWidth)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.accentColor.opacity(0.14) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 2 : 0.5))
        .modifier(HoverBackground(radius: 12))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectedID = item.id; place(item) }
        .onTapGesture { selectedID = item.id }
        .contextMenu { itemMenu(item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.category.singularName), \(item.types.count) sizes\(loaded ? ", in project" : "")")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Place") { place(item) }
    }

    func listRow(_ item: ComponentLibraryItem) -> some View {
        let on = item.id == selected?.id
        let loaded = loadedNames.contains(item.name)
        return HStack(spacing: 10) {
            LibraryPreview(item: item, type: typeName(for: item), plan: planPreview, size: CGSize(width: 54, height: 40))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 0.95)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5, weight: .medium))
                Text("\(item.category.displayName) · \(item.group)").font(.system(size: 10.5)).foregroundStyle(on ? Color.white.opacity(0.85) : .secondary)
            }
            Spacer()
            Text(regionText(item)).font(.system(size: 10.5)).foregroundStyle(on ? Color.white.opacity(0.85) : .secondary)
            Text("\(item.types.count) sizes").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.85) : .secondary)
                .frame(width: 58, alignment: .trailing)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(on ? .white : .green).opacity(loaded ? 1 : 0)
        }
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Color.accentColor : .clear))
        .modifier(HoverBackground(radius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectedID = item.id; place(item) }
        .onTapGesture { selectedID = item.id }
        .contextMenu { itemMenu(item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.category.singularName), \(item.types.count) sizes\(loaded ? ", in project" : "")")
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Place") { place(item) }
    }

    @ViewBuilder
    func itemMenu(_ item: ComponentLibraryItem) -> some View {
        Button("Place \(typeName(for: item))") { place(item) }
        Button("Load into Project") { load(item) }
        Divider()
        Menu("Place Size") {
            ForEach(types(of: item)) { t in Button(t.name) { chosenType[item.id] = t.name; place(item) } }
        }
    }

    func subtitle(_ item: ComponentLibraryItem) -> String {
        let n = types(of: item).count
        return "\(n) size\(n == 1 ? "" : "s") · \(regionText(item))"
    }

    func regionText(_ item: ComponentLibraryItem) -> String {
        let r = item.regions.filter { $0 != .global }
        return r.isEmpty || item.regions.contains(.global) && r.count > 2 ? "Global" : r.map(\.rawValue).joined(separator: ", ")
    }

    // MARK: Detail

    @ViewBuilder
    var detail: some View {
        if let item = selected {
            let current = typeName(for: item)
            let loadedTypes = ComponentLibraryLoader.loadedTypeNames(item, state.model)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.89)], startPoint: .top, endPoint: .bottom))
                        LibraryPreview(item: item, type: current, plan: planPreview, size: CGSize(width: 252, height: 176)).padding(12)
                        Picker("Preview", selection: $planPreview) {
                            Text("3D").tag(false)
                            Text("Plan").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 96).padding(8)
                        .help("Preview the 3D model or the plan symbol")
                    }
                    .frame(height: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.system(size: 15, weight: .semibold))
                        Text("\(item.category.displayName) · \(item.group)").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(item.regions, id: \.self) { r in
                                Text(r.displayName).font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            }
                        }
                        .padding(.top, 2)
                    }
                    Text(item.summary).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sizes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("All units", isOn: $showAllSizes).toggleStyle(.switch).controlSize(.mini).font(.system(size: 10.5))
                                .help("Also show sizes named in the other unit system")
                        }
                        ForEach(types(of: item)) { t in
                            sizeRow(item, t, on: t.name == current, loaded: loadedTypes.contains(t.name))
                        }
                    }
                    if !loadedTypes.isEmpty {
                        Label("In this project with \(loadedTypes.count) size\(loadedTypes.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.green)
                    }
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cube.transparent").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text("Select a component").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func sizeRow(_ item: ComponentLibraryItem, _ t: ComponentLibraryType, on: Bool, loaded: Bool) -> some View {
        Button { chosenType[item.id] = t.name } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 11)).foregroundStyle(on ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.name).font(.system(size: 12, weight: on ? .medium : .regular)).lineLimit(1)
                    Text(dimensions(t)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                if loaded { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green).help("In this project") }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Color.accentColor.opacity(0.12) : .clear))
            .modifier(HoverBackground(radius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { chosenType[item.id] = t.name; place(item) })
        .accessibilityLabel("\(t.name), \(dimensions(t))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func dimensions(_ t: ComponentLibraryType) -> String {
        let f = { (v: Double) in QuantityFormatter.format(v, kind: .length, units: units) }
        return "\(f(t.width)) × \(f(t.depth)) × \(f(t.height))"
    }

    // MARK: Footer and actions

    func footer(_ list: [ComponentLibraryItem]) -> some View {
        HStack(spacing: 10) {
            Text(list.count == baseItems.count ? "\(list.count) components" : "\(list.count) of \(baseItems.count) components")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            Text("Double-click or press Return to place · arrows to browse")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") { state.presented = nil }.keyboardShortcut(.cancelAction).dialogButton()
            Button("Load") { if let i = selected { load(i) } }
                .disabled(selected == nil)
                .help("Load the selected size into the project without placing it")
                .dialogButton()
            Button("Place") { placeSelected() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
                .help("Load the selected size if needed and start placing it")
                .dialogButton()
        }
        .padding(.horizontal, DialogStyle.outer).padding(.vertical, DialogStyle.footerPaddingV) // DIALOGS: the dialog footer
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = list[max(0, min(list.count - 1, i + delta))].id
    }

    func placeSelected() { if let i = selected { place(i) } }

    func place(_ item: ComponentLibraryItem) {
        state.placeFromLibrary(item, typeName: typeName(for: item))
    }

    func load(_ item: ComponentLibraryItem) {
        state.placeFromLibrary(item, typeName: typeName(for: item), startTool: false)
    }
}
