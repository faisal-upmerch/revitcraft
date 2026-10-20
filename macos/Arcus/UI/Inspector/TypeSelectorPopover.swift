import SwiftUI
import ArcusDomain
import ArcusApplication

/// BL-PROPS: the Type Selector at the top of the Properties palette — the current family and type, opening a popover
/// with a search field, the recently used types and the types grouped by family.
struct TypeSelectorButton: View {
    let state: DocumentState
    let category: Category
    let currentTypeID: ElementID?
    let types: [Element]
    let choose: (Element) -> Void
    @State private var open = false

    var body: some View {
        let m = state.model
        Button { open = true } label: {
            HStack(spacing: 8) {
                TypeSwatch(type: m[currentTypeID])
                VStack(alignment: .leading, spacing: 0) {
                    Text(m[currentTypeID]?.typeData?.familyName ?? category.displayName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Text(m[currentTypeID]?.name ?? (currentTypeID == nil && !types.isEmpty ? "<varies>" : "Choose a type"))
                        .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(m[currentTypeID].map { TypeSelectorModel.searchText($0) } ?? "Change type")
        .accessibilityLabel("Type: \(m[currentTypeID]?.name ?? "none")")
        .accessibilityHint("Opens the type list with search")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            TypeSelectorPopover(state: state, types: types, current: currentTypeID, recent: state.palette.recentTypes) { t in
                open = false
                choose(t)
            }
        }
    }
}

/// Search (keywords in any order, highlighted), Most Recently Used and the family-grouped list. Keyboard: typing
/// filters, ↑/↓ move, Return picks, Tab moves between the field and the list, Esc clears the search, then closes.
struct TypeSelectorPopover: View {
    let state: DocumentState
    let types: [Element]
    let current: ElementID?
    let recent: [ElementID]
    let choose: (Element) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    enum Field: Hashable { case search, list }

    var sections: [TypeSelectorModel.Section] { TypeSelectorModel.sections(types: types, recent: recent, query: query) }
    /// Rows in display order (a recently used type appears twice; the recent row comes first).
    var flat: [(section: Int, id: ElementID)] {
        sections.enumerated().flatMap { i, s in s.types.map { (i, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search types", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .search)
                    .onSubmit { pickHighlighted() }
                    .accessibilityLabel("Search types")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if sections.isEmpty {
                            Text("No types match “\(query)”.").font(.callout).foregroundStyle(.secondary).padding(12)
                        }
                        ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                            Text(s.title.isEmpty ? "Types" : s.title)
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                            ForEach(s.types, id: \.self) { id in
                                if let t = state.model[id] { row(t, section: i).id(RowKey(section: i, id: id)) }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .focusable()
                .focused($focus, equals: .list)
                .focusEffectDisabled()
                .onChange(of: highlightKey) { _, k in if let k { withAnimation(nil) { proxy.scrollTo(k, anchor: .center) } } }
            }
        }
        .frame(width: 320, height: 380)
        .onAppear {
            highlighted = flat.firstIndex { $0.id == current && !(sections[$0.section].isRecent) } ?? 0
            focus = .search
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { pickHighlighted(); return .handled }
        .onKeyPress(.tab) { focus = focus == .search ? .list : .search; return .handled }
        .onKeyPress(.escape) {
            if !query.isEmpty { query = ""; focus = .search } else { dismiss() }
            return .handled
        }
    }

    struct RowKey: Hashable { let section: Int; let id: ElementID }
    var highlightKey: RowKey? {
        let f = flat
        guard f.indices.contains(highlighted) else { return nil }
        return RowKey(section: f[highlighted].section, id: f[highlighted].id)
    }

    func row(_ t: Element, section: Int) -> some View {
        let isHighlighted = highlightKey == RowKey(section: section, id: t.id)
        return Button { choose(t) } label: {
            HStack(spacing: 8) {
                TypeSwatch(type: t).scaleEffect(0.75).frame(width: 18, height: 18)
                highlightedText(t.name)
                Spacer(minLength: 4)
                if t.id == current { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.selectionColor) }
            }
            .padding(.horizontal, PillSpec.rowPadding).padding(.vertical, 4)
            // PILLS: the highlight sits 4 pt inside the list and 12 pt around the row's content.
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHighlighted ? Tokens.selectionColor.opacity(0.16) : .clear))
            .padding(.horizontal, PillSpec.inset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in if h, let i = flat.firstIndex(where: { $0.section == section && $0.id == t.id }) { highlighted = i } }
        .accessibilityLabel(TypeSelectorModel.searchText(t))
        .accessibilityAddTraits(t.id == current ? .isSelected : [])
    }

    /// The name with the search keywords emphasised.
    func highlightedText(_ s: String) -> Text {
        var a = AttributedString(s)
        for r in TypeSelectorModel.match(s, query: query) ?? [] {
            guard let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
            a[lo..<hi].font = .system(size: 12, weight: .bold)
            a[lo..<hi].foregroundColor = Tokens.selectionColor
        }
        return Text(a).font(.system(size: 12))
    }

    func move(_ d: Int) {
        let n = flat.count
        guard n > 0 else { return }
        highlighted = max(0, min(n - 1, highlighted + d))
    }

    func pickHighlighted() {
        let f = flat
        guard f.indices.contains(highlighted), let t = state.model[f[highlighted].id] else { return }
        choose(t)
    }
}
