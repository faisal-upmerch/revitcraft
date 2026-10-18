import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// MARK: - Swatches

/// A material's color as a small rounded tile (with a checkerboard under transparent materials).
struct MaterialSwatch: View {
    let color: RGBColor?
    var transparency: Double = 0
    var size: CGFloat = 16
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            if transparency > 0.01 { Checkerboard(cell: max(3, size / 4)).clipShape(shape) }
            shape.fill(LinearGradient(colors: [fill.opacity(1 - transparency * 0.8), shade.opacity(1 - transparency * 0.8)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    var fill: Color { (color ?? RGBColor(0.75, 0.75, 0.75)).color }
    var shade: Color { (color.map { RGBColor($0.r * 0.86, $0.g * 0.86, $0.b * 0.86) } ?? RGBColor(0.65, 0.65, 0.65)).color }
}

/// A shaded sphere in the material's color: the material preview in the Materials window and the New Material form.
struct MaterialBall: View {
    let color: RGBColor
    var transparency: Double = 0
    var size: CGFloat = 88
    var body: some View {
        let c = color
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            if transparency > 0.01 { Checkerboard(cell: size / 11).clipShape(Circle()).frame(width: size * 0.74, height: size * 0.74) }
            Circle()
                .fill(RadialGradient(colors: [RGBColor(min(1, c.r * 1.25 + 0.12), min(1, c.g * 1.25 + 0.12), min(1, c.b * 1.25 + 0.12)).color,
                                              c.color, RGBColor(c.r * 0.55, c.g * 0.55, c.b * 0.55).color],
                                     center: UnitPoint(x: 0.34, y: 0.3), startRadius: 1, endRadius: size * 0.5))
                .opacity(1 - transparency * 0.75)
                .frame(width: size * 0.74, height: size * 0.74)
                .shadow(color: .black.opacity(0.22), radius: size * 0.05, y: size * 0.04)
            Ellipse().fill(.white.opacity(0.45)).frame(width: size * 0.16, height: size * 0.1).blur(radius: 1.5)
                .offset(x: -size * 0.13, y: -size * 0.17)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct Checkerboard: View {
    var cell: CGFloat
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : cell
                while x < size.width { ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.82))); x += cell * 2 }
                y += cell; row += 1
            }
        }
    }
}

/// Colors offered when creating or editing a material: common building material tones.
enum MaterialPalette {
    static let colors: [(String, RGBColor)] = [
        ("Concrete", RGBColor(0.72, 0.71, 0.68)), ("Brick", RGBColor(0.62, 0.30, 0.22)), ("Terracotta", RGBColor(0.78, 0.45, 0.30)),
        ("Sandstone", RGBColor(0.86, 0.78, 0.62)), ("Oak", RGBColor(0.76, 0.58, 0.36)), ("Walnut", RGBColor(0.42, 0.28, 0.18)),
        ("Plaster", RGBColor(0.95, 0.94, 0.91)), ("Steel", RGBColor(0.56, 0.60, 0.64)), ("Aluminum", RGBColor(0.80, 0.82, 0.84)),
        ("Glass", RGBColor(0.62, 0.80, 0.88)), ("Slate", RGBColor(0.34, 0.37, 0.41)), ("Charcoal", RGBColor(0.18, 0.19, 0.20)),
        ("Sage", RGBColor(0.60, 0.68, 0.56)), ("Moss", RGBColor(0.36, 0.45, 0.30)), ("Ochre", RGBColor(0.82, 0.64, 0.26)),
        ("Insulation", RGBColor(0.96, 0.84, 0.52)),
    ]
    /// A sensible starting color for a new material of a class.
    static func suggested(for c: MaterialClass) -> RGBColor {
        switch c {
        case .concrete: RGBColor(0.72, 0.71, 0.68)
        case .masonry: RGBColor(0.62, 0.30, 0.22)
        case .metal: RGBColor(0.56, 0.60, 0.64)
        case .wood: RGBColor(0.76, 0.58, 0.36)
        case .glass: RGBColor(0.62, 0.80, 0.88)
        case .plaster, .paint: RGBColor(0.95, 0.94, 0.91)
        case .insulation: RGBColor(0.96, 0.84, 0.52)
        case .stone: RGBColor(0.86, 0.78, 0.62)
        case .ceramic: RGBColor(0.90, 0.88, 0.84)
        case .earth: RGBColor(0.55, 0.43, 0.30)
        case .plastic: RGBColor(0.85, 0.85, 0.85)
        case .liquid: RGBColor(0.45, 0.62, 0.80)
        case .gas: RGBColor(0.90, 0.93, 0.96)
        case .generic: RGBColor(0.80, 0.80, 0.80)
        }
    }
}

/// A row of palette swatches; the chosen one is ringed.
struct PaletteRow: View {
    @Binding var color: RGBColor
    var columns = 8
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 7), count: columns), spacing: 7) {
            ForEach(MaterialPalette.colors, id: \.0) { name, c in
                Button { color = c } label: {
                    Circle().fill(c.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(2.5)
                        .overlay(Circle().strokeBorder(same(c) ? Color.accentColor : .clear, lineWidth: 2))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(RibbonPressStyle())
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(same(c) ? .isSelected : [])
            }
        }
    }
    func same(_ c: RGBColor) -> Bool { abs(c.r - color.r) + abs(c.g - color.g) + abs(c.b - color.b) < 0.01 }
}

extension RGBColor {
    /// Bridges to a SwiftUI color well.
    var swiftUIBinding: Color { color }
    static func from(_ c: Color) -> RGBColor { .from(NSColor(c)) }
}

// MARK: - Searchable picker

/// A material picker for compound layers and material parameters: a compact button that opens a searchable list.
struct MaterialPicker: View {
    let state: DocumentState
    @Binding var selection: ElementID?
    var noneLabel = "<By Category>"
    @State private var open = false
    var body: some View {
        let mat = state.model[selection]
        Button { open = true } label: {
            HStack(spacing: 6) {
                MaterialSwatch(color: mat?.material?.color, transparency: mat?.material?.transparency ?? 0, size: 14)
                    .opacity(mat == nil ? 0.35 : 1)
                Text(mat?.name ?? noneLabel).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(mat == nil ? .secondary : .primary)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(open ? 0.3 : 0.12), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MaterialSearchList(state: state, selection: $selection, noneLabel: noneLabel) { open = false }
        }
        .accessibilityLabel("Material")
        .accessibilityValue(mat?.name ?? noneLabel)
    }
}

/// The searchable list inside `MaterialPicker`: type to filter by name, class or description; arrows and Return choose.
struct MaterialSearchList: View {
    let state: DocumentState
    @Binding var selection: ElementID?
    var noneLabel: String
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    /// nil stands for the "none" choice.
    var items: [Element?] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let mats = state.model.materials.filter { m in
            q.isEmpty || m.name.lowercased().contains(q) || (m.material?.materialClass.rawValue.lowercased().contains(q) ?? false)
                || (m.material?.description.lowercased().contains(q) ?? false)
        }
        return (q.isEmpty || noneLabel.lowercased().contains(q) ? [nil] : []) + mats.map { Optional($0) }
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search materials", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { choose(list) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(list.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                    .onExitCommand { close() }
                    .accessibilityLabel("Search materials")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, m in
                            row(m, highlighted: i == highlighted)
                                .id(i)
                                .onTapGesture { selection = m?.id; close() }
                                .onHover { if $0 { highlighted = i } }
                        }
                        if list.isEmpty {
                            Text("No materials match “\(query)”.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: highlighted) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 300)
            Divider()
            Text("\(state.model.materials.count) materials").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(width: 300)
        .onAppear {
            focused = true
            highlighted = list.firstIndex { $0?.id == selection } ?? 0
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    func row(_ m: Element?, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            MaterialSwatch(color: m?.material?.color, transparency: m?.material?.transparency ?? 0, size: 18).opacity(m == nil ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(m?.name ?? noneLabel).font(.system(size: 12)).lineLimit(1)
                if let c = m?.material?.materialClass { Text(c.rawValue).font(.system(size: 10)).foregroundStyle(highlighted ? .white.opacity(0.8) : .secondary) }
            }
            Spacer(minLength: 4)
            if m?.id == selection { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(highlighted ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    func choose(_ list: [Element?]) {
        guard highlighted < list.count else { return }
        selection = list[highlighted]?.id
        close()
    }
}

// MARK: - Materials window

/// Manage > Materials: a searchable library grouped by class on the left, the selected material's appearance and
/// identity on the right. New materials start from a name, a class and a color.
struct MaterialsDialog: View {
    let state: DocumentState
    @State private var selected: ElementID?
    @State private var query = ""
    @State private var showingNew = false
    @State private var confirmDelete: ElementID?
    @State private var showingLibrary = false // W2-TYPES

    var body: some View {
        let _ = state.session.changeCounter
        DialogChrome { // W4-SHELL: window-like dialog grammar (content, hairline, button strip)
            HStack(spacing: 0) {
                sidebar.frame(width: 270)
                Divider()
                Group {
                    if let id = selected, let mat = state.model[id], mat.material != nil {
                        MaterialDetail(state: state, materialID: id).id(id)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "paintpalette").font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                            Text("Select a material").font(.title3).foregroundStyle(.secondary)
                            Text("or create one with the + button.").font(.callout).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
        } buttons: {
            DialogButtonRow(okTitle: "Done", showCancel: false, onCancel: {}, onOK: { state.presented = nil }) {
                Button { if let id = selected { paint(id) } } label: { Label("Paint Selection", systemImage: "paintbrush") }
                    .disabled(selected == nil || state.session.selection.isEmpty)
                    .help(state.session.selection.isEmpty ? "Select elements in the view first" : "Apply this material to all surfaces of the selected elements")
                // W2-TYPES: add materials from the built-in library.
                Button { showingLibrary = true } label: { Label("Add from Library…", systemImage: "books.vertical") }
                    .help("Add common building materials from the built-in library")
                    .sheet(isPresented: $showingLibrary) {
                        MaterialLibraryPicker(state: state) { added in showingLibrary = false; if let first = added.first { selected = first } }
                    }
            }
        }
        .frame(width: 880, height: 600)
        .onAppear { if selected == nil { selected = state.model.materials.first?.id } }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let id = confirmDelete { delete(id) } }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Layers and faces that use it fall back to their category's material.")
        }
    }

    var deleteTitle: String {
        guard let id = confirmDelete else { return "" }
        let n = MaterialUsage.count(id, state.model)
        return "Delete “\(state.model[id]?.name ?? "")”? It is used \(n == 1 ? "once" : "\(n) times")."
    }

    var filtered: [Element] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return state.model.materials.filter { m in
            guard !q.isEmpty, let d = m.material else { return true }
            return [m.name, d.materialClass.rawValue, d.description, d.manufacturer, d.keynote, d.mark].contains { $0.lowercased().contains(q) }
        }
    }

    var sidebar: some View {
        let mats = filtered
        let groups = Dictionary(grouping: mats) { $0.material?.materialClass ?? .generic }
        let classes = MaterialClass.allCases.filter { groups[$0] != nil }
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain).accessibilityLabel("Search materials")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(classes, id: \.self) { c in
                            Section {
                                ForEach(groups[c]!, id: \.id) { m in
                                    materialRow(m, selected: m.id == selected)
                                        .id(m.id)
                                        .onTapGesture { selected = m.id }
                                        .contextMenu {
                                            Button("Duplicate") { duplicate(m) }
                                            Button("Delete", role: .destructive) { confirmDelete = m.id }
                                        }
                                }
                            } header: {
                                Text(c.rawValue).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 3)
                            }
                        }
                        if mats.isEmpty {
                            Text("No materials match “\(query)”.").font(.callout).foregroundStyle(.secondary).padding(12)
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { step(1, mats); return .handled }
                .onKeyPress(.upArrow) { step(-1, mats); return .handled }
                .onChange(of: selected) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
            }
            Divider()
            HStack(spacing: 2) {
                Button { showingNew = true } label: { Image(systemName: "plus").frame(width: 24, height: 20).contentShape(Rectangle()) }
                    .buttonStyle(RibbonPressStyle()).modifier(HoverBackground(radius: 5))
                    .help("New Material")
                    .accessibilityLabel("New Material")
                    .popover(isPresented: $showingNew, arrowEdge: .top) {
                        NewMaterialForm(state: state) { id in selected = id; showingNew = false } cancel: { showingNew = false }
                    }
                Button { if let id = selected { confirmDelete = id } } label: { Image(systemName: "minus").frame(width: 24, height: 20).contentShape(Rectangle()) }
                    .buttonStyle(RibbonPressStyle()).modifier(HoverBackground(radius: 5))
                    .disabled(selected == nil)
                    .help("Delete Material")
                    .accessibilityLabel("Delete Material")
                Button { if let id = selected, let m = state.model[id] { duplicate(m) } } label: {
                    Image(systemName: "plus.square.on.square").frame(width: 24, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(RibbonPressStyle()).modifier(HoverBackground(radius: 5))
                .disabled(selected == nil)
                .help("Duplicate Material")
                .accessibilityLabel("Duplicate Material")
                Spacer()
                Text("\(mats.count) of \(state.model.materials.count)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .background(Color.primary.opacity(0.025))
    }

    func materialRow(_ m: Element, selected isSelected: Bool) -> some View {
        let n = MaterialUsage.count(m.id, state.model)
        return HStack(spacing: 9) {
            MaterialSwatch(color: m.material?.color, transparency: m.material?.transparency ?? 0, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.name).font(.system(size: 12.5, weight: isSelected ? .medium : .regular)).lineLimit(1)
                Text(n == 0 ? "Not used" : "Used \(n == 1 ? "once" : "\(n) times")").font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.accentColor : .clear))
        .modifier(HoverBackground(radius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    func step(_ d: Int, _ mats: [Element]) {
        let order = MaterialClass.allCases.flatMap { c in mats.filter { ($0.material?.materialClass ?? .generic) == c } }.map(\.id)
        guard !order.isEmpty else { return }
        let i = selected.flatMap { order.firstIndex(of: $0) } ?? -1
        selected = order[max(0, min(order.count - 1, i + d))]
    }

    func paint(_ id: ElementID) {
        let sel = state.session.selection.ids
        state.session.perform("Paint") { tx in for e in sel { tx.update(e) { $0.params[.paintMaterial] = .ref(id) } } }
        state.show("Painted \(sel.count) element(s) with \(state.model[id]?.name ?? "the material").")
    }
    func duplicate(_ mat: Element) {
        guard let d = mat.material else { return }
        let name = MaterialUsage.uniqueName(mat.name + " Copy", state.model)
        var created: ElementID?
        state.session.perform("Duplicate Material") { tx in created = tx.create(.materials, name: name, data: .material(d)) }
        selected = created
    }
    func delete(_ id: ElementID) {
        let next = state.model.materials.map(\.id).filter { $0 != id }.first
        state.session.delete([id])
        confirmDelete = nil
        selected = next
    }
}

enum MaterialUsage {
    /// How many compound layers, type parameters and painted elements refer to a material.
    static func count(_ id: ElementID, _ m: BIMModel) -> Int {
        var n = 0
        for t in m.elements(.elementTypes) {
            n += t.typeData?.assembly?.layers.filter { $0.materialID == id }.count ?? 0
            n += t.typeData?.params.values.filter { $0.refValue == id }.count ?? 0
        }
        for e in m.allElements where e.params[.paintMaterial]?.refValue == id { n += 1 }
        return n
    }
    static func uniqueName(_ base: String, _ m: BIMModel) -> String {
        let names = Set(m.materials.map(\.name))
        guard names.contains(base) else { return base }
        var k = 2
        while names.contains("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }
}

/// The selected material: preview, name and class, then Appearance and Identity.
private struct MaterialDetail: View {
    let state: DocumentState
    let materialID: ElementID
    @State private var name = ""
    @State private var color = RGBColor(0.8, 0.8, 0.8)
    @State private var transparency = 0.0
    @State private var colorCommit: Task<Void, Never>?

    var body: some View {
        let mat = state.model[materialID]
        let d = mat?.material
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    MaterialBall(color: color, transparency: transparency, size: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        // W4-SHELL: fixed-height name field (the 20 pt text used to draw clipped above a default-height field).
                        DialogNameField(placeholder: "Name", text: $name) { commitName() }
                            .accessibilityLabel("Material name")
                        HStack(spacing: 10) {
                            Picker("Class", selection: Binding(get: { d?.materialClass ?? .generic }, set: { set("material.class", .text($0.rawValue), "Material Class") })) {
                                ForEach(MaterialClass.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                            .accessibilityLabel("Material class")
                            let n = MaterialUsage.count(materialID, state.model)
                            Text(n == 0 ? "Not used in the project" : "Used \(n == 1 ? "once" : "\(n) times") in the project")
                                .font(DialogMetrics.subtitle).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)

                section("Appearance") {
                    row("Color") {
                        HStack(spacing: 10) {
                            ColorPicker("", selection: Binding(get: { color.color }, set: { color = .from($0); scheduleColorCommit() }), supportsOpacity: false)
                                .labelsHidden()
                            Text(color.hexString).font(.system(size: 12).monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    PaletteRow(color: Binding(get: { color }, set: { color = $0; scheduleColorCommit() }), columns: 8)
                        .fixedSize()
                        .padding(.leading, 112)
                    row("Transparency") {
                        HStack(spacing: 10) {
                            Slider(value: $transparency, in: 0...1) { editing in
                                if !editing { set("material.transparency", .double(transparency), "Transparency") }
                            }
                            .frame(maxWidth: 260)
                            Text("\(Int((transparency * 100).rounded()))%").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                section("Graphics") { // W4-HATCH: cut and surface patterns
                    row("Cut Pattern") {
                        HStack(spacing: 10) {
                            FillPatternMenu(state: state, selection: Binding(get: { d?.cutPatternID }, set: { set("material.cutPattern", .ref($0), "Cut Pattern") }), noneLabel: "<By Class>")
                            ColorPicker("", selection: Binding(get: { (d?.cutPatternColor ?? .black).color }, set: { set("material.cutPatternColor", .text(RGBColor.from($0).hexString), "Cut Pattern Color") }), supportsOpacity: false)
                                .labelsHidden().accessibilityLabel("Cut Pattern Color")
                            Text("Drawn where the material is cut at medium and fine detail; coarse views use solid poché.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    row("Surface Pattern") {
                        HStack(spacing: 10) {
                            FillPatternMenu(state: state, selection: Binding(get: { d?.surfacePatternID }, set: { set("material.surfacePattern", .ref($0), "Surface Pattern") }), noneLabel: "<None>")
                            ColorPicker("", selection: Binding(get: { (d?.surfacePatternColor ?? .black).color }, set: { set("material.surfacePatternColor", .text(RGBColor.from($0).hexString), "Surface Pattern Color") }), supportsOpacity: false)
                                .labelsHidden().accessibilityLabel("Surface Pattern Color")
                            Text("Drawn on visible surfaces (floor and ceiling finishes in plan).").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                section("Identity") {
                    textRow("Description", "material.description", d?.description ?? "")
                    textRow("Manufacturer", "material.manufacturer", d?.manufacturer ?? "")
                    textRow("Model", "material.model", d?.model ?? "")
                    textRow("Cost", "material.cost", Parameters.format(.double(d?.cost ?? 0), type: .currency, model: state.model), type: .currency)
                    textRow("Keynote", "material.keynote", d?.keynote ?? "")
                    textRow("Mark", "material.mark", d?.mark ?? "")
                }
            }
            .padding(22)
        }
        .onAppear { load() }
        .onChange(of: state.session.changeCounter) { _, _ in if colorCommit == nil { load() } }
    }

    func load() {
        guard let m = state.model[materialID], let d = m.material else { return }
        name = m.name; color = d.color; transparency = d.transparency
    }

    @ViewBuilder func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(DialogMetrics.sectionHeader).foregroundStyle(.secondary).textCase(.uppercase) // W4-SHELL
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    func textRow(_ label: String, _ key: String, _ value: String, type: ParamType = .text) -> some View {
        row(label) { MaterialTextField(value: value) { set(key, text: $0, type: type, label) } }
    }

    func commitName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != state.model[materialID]?.name else { name = state.model[materialID]?.name ?? name; return }
        set("name", .text(n), "Rename Material")
    }

    func scheduleColorCommit() {
        colorCommit?.cancel()
        colorCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            set("material.color", .text(color.hexString), "Material Color")
            colorCommit = nil
        }
    }

    func set(_ key: String, _ v: ParamValue, _ undoName: String) {
        state.session.setParameter(ParameterID(key), value: v, on: [materialID], name: undoName)
        report()
    }
    func set(_ key: String, text: String, type: ParamType, _ undoName: String) {
        state.session.setParameter(ParameterID(key), text: text, on: [materialID], type: type, name: undoName)
        report()
    }
    func report() {
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError(); load() }
    }
}

/// A text field that commits on Return or when it loses focus.
private struct MaterialTextField: View {
    let value: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 340)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onSubmit { if text != value { commit(text) } }
            .onChange(of: focused) { _, f in if !f, text != value { commit(text) } }
    }
}

/// The + popover: a name, a class and a color (palette or custom) for a new material.
struct NewMaterialForm: View {
    let state: DocumentState
    let created: (ElementID) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var materialClass: MaterialClass = .generic
    @State private var color = MaterialPalette.suggested(for: .generic)
    @State private var colorTouched = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let clash = state.model.materials.contains { $0.name == name.trimmingCharacters(in: .whitespaces) }
        VStack(alignment: .leading, spacing: 14) {
            Text("New Material").font(.headline)
            HStack(alignment: .center, spacing: 14) {
                MaterialBall(color: color, size: 72)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                    Picker("Class", selection: $materialClass) { ForEach(MaterialClass.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .onChange(of: materialClass) { _, c in if !colorTouched { color = MaterialPalette.suggested(for: c) } }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Color").font(.subheadline.weight(.medium))
                    Spacer()
                    ColorPicker("Custom", selection: Binding(get: { color.color }, set: { color = .from($0); colorTouched = true }), supportsOpacity: false)
                        .font(.caption)
                }
                PaletteRow(color: Binding(get: { color }, set: { color = $0; colorTouched = true }))
            }
            if clash { Text("A material named “\(name)” already exists.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create") { create() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || clash)
            }
        }
        .padding(18)
        .frame(width: 330)
        .onAppear { name = MaterialUsage.uniqueName("New Material", state.model); nameFocused = true }
    }

    func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let data = MaterialData(materialClass: materialClass, color: color)
        var id: ElementID?
        state.session.perform("New Material") { tx in id = tx.create(.materials, name: n, data: .material(data)) }
        if let id { created(id) }
    }
}
