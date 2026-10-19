import SwiftUI

// DIALOGS: lists inside dialogs. A list is an inset, rounded box sized to its rows (between `minRows` and `maxRows`
// rows tall, then it scrolls), so a short list never leaves a large blank area. An empty list shows its empty state
// inside the box: an icon, one line of title, a short message and at most one action.

/// A rounded box around a caller's `List` (or `Table`), sized to the row count, with an empty state.
struct DialogListBox<Content: View, Empty: View>: View {
    let count: Int
    var rowHeight: CGFloat = 28
    var minRows = 3
    var maxRows = 9
    var isEmpty: Bool? = nil
    @ViewBuilder let content: Content
    @ViewBuilder let empty: Empty

    init(count: Int, rowHeight: CGFloat = 28, minRows: Int = 3, maxRows: Int = 9, isEmpty: Bool? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder empty: () -> Empty) {
        self.count = count; self.rowHeight = rowHeight; self.minRows = minRows; self.maxRows = maxRows; self.isEmpty = isEmpty
        self.content = content(); self.empty = empty()
    }

    /// Height for `count` rows within the row limits (lists add ~10 pt of inset above and below).
    static func height(count: Int, rowHeight: CGFloat, minRows: Int, maxRows: Int) -> CGFloat {
        CGFloat(min(max(count, minRows), maxRows)) * rowHeight + 10
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        let blank = isEmpty ?? (count == 0)
        content
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, rowHeight)
            .opacity(blank ? 0 : 1)
            .frame(height: blank ? max(Self.height(count: count, rowHeight: rowHeight, minRows: minRows, maxRows: maxRows), 120)
                                 : Self.height(count: count, rowHeight: rowHeight, minRows: minRows, maxRows: maxRows))
            .frame(maxWidth: .infinity)
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
            .overlay { if blank { empty.padding(12) } }
    }
}

extension DialogListBox where Empty == EmptyView {
    init(count: Int, rowHeight: CGFloat = 28, minRows: Int = 3, maxRows: Int = 9, @ViewBuilder content: () -> Content) {
        self.init(count: count, rowHeight: rowHeight, minRows: minRows, maxRows: maxRows, isEmpty: false, content: content, empty: { EmptyView() })
    }
}

/// One row of a dialog list: an optional icon, a title, an optional secondary line and trailing content.
struct DialogListRow<Trailing: View>: View {
    var icon: String? = nil
    var iconTint: Color = .secondary
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    init(icon: String? = nil, iconTint: Color = .secondary, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon; self.iconTint = iconTint; self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).foregroundStyle(iconTint).frame(width: 18).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

extension DialogListRow where Trailing == EmptyView {
    init(icon: String? = nil, iconTint: Color = .secondary, title: String, subtitle: String? = nil) {
        self.init(icon: icon, iconTint: iconTint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// An item of a `DialogCheckList`.
struct DialogCheckItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    /// Shown right-aligned (an element count, an elevation).
    var detail: String? = nil
    /// A colour dot before the title (CAD layers, line styles).
    var swatch: Color? = nil
}

/// A checkbox list with a row per item, a checked count and an empty state.
struct DialogCheckList<ID: Hashable, Empty: View>: View {
    let items: [DialogCheckItem<ID>]
    @Binding var checked: Set<ID>
    /// Fewest rows the box shows (the list hugs its items by default; an empty list shows its empty state in 3 rows).
    var minRows = 1
    var maxRows = 9
    /// "Elements" in "4 of 9 elements" under the list (nil hides the total).
    var noun: String? = nil
    /// The total under the list counts `detail` numbers instead of rows (Filter Selection counts elements).
    var totalOfDetails = false
    @ViewBuilder let empty: Empty

    init(items: [DialogCheckItem<ID>], checked: Binding<Set<ID>>, minRows: Int = 1, maxRows: Int = 9, noun: String? = nil,
         totalOfDetails: Bool = false, @ViewBuilder empty: () -> Empty) {
        self.items = items; self._checked = checked; self.minRows = minRows; self.maxRows = maxRows; self.noun = noun
        self.totalOfDetails = totalOfDetails; self.empty = empty()
    }

    /// 30 pt rows, 40 pt when any item has a second line.
    var rowHeight: CGFloat { items.contains { !($0.subtitle ?? "").isEmpty } ? 40 : 30 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { DialogColors.rowDivider.frame(height: 1).padding(.leading, 38) }
                        row(item)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: items.isEmpty ? 120 : CGFloat(min(max(items.count, minRows), maxRows)) * rowHeight + 8)
            .frame(maxWidth: .infinity)
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
            .overlay { if items.isEmpty { empty.padding(12) } }
            if let noun, !items.isEmpty {
                Text(total(noun)).font(DialogStyle.footnote).foregroundStyle(.secondary).monospacedDigit().padding(.horizontal, 4)
            }
        }
    }

    private func total(_ noun: String) -> String {
        if totalOfDetails {
            let all = items.reduce(0) { $0 + (Int($1.detail ?? "") ?? 0) }
            let on = items.filter { checked.contains($0.id) }.reduce(0) { $0 + (Int($1.detail ?? "") ?? 0) }
            return "\(on) of \(all) \(noun) checked"
        }
        return "\(items.filter { checked.contains($0.id) }.count) of \(items.count) \(noun) checked"
    }

    private func row(_ item: DialogCheckItem<ID>) -> some View {
        let on = Binding(get: { checked.contains(item.id) }, set: { v in if v { checked.insert(item.id) } else { checked.remove(item.id) } })
        return HStack(spacing: 10) {
            Toggle(isOn: on) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
            if let swatch = item.swatch { Circle().fill(swatch).overlay(Circle().strokeBorder(.black.opacity(0.15))).frame(width: 10, height: 10).accessibilityHidden(true) }
            if let icon = item.icon { Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                if let s = item.subtitle, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let d = item.detail { Text(d).foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { on.wrappedValue.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on.wrappedValue ? "checked" : "unchecked")
    }
}

extension DialogCheckList where Empty == DialogEmptyState {
    init(items: [DialogCheckItem<ID>], checked: Binding<Set<ID>>, minRows: Int = 1, maxRows: Int = 9, noun: String? = nil,
         totalOfDetails: Bool = false, emptyTitle: String, emptyMessage: String = "", emptyIcon: String = "tray") {
        self.init(items: items, checked: checked, minRows: minRows, maxRows: maxRows, noun: noun, totalOfDetails: totalOfDetails) {
            DialogEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
        }
    }
}

/// A compact empty state for the inside of a list box: icon, title, a short message and an optional action.
struct DialogEmptyState: View {
    let icon: String
    let title: String
    var message: String = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// A larger icon on a soft disc, for empty master lists (Design Options).
    var illustrated = false

    var body: some View {
        VStack(spacing: illustrated ? 10 : 6) {
            if illustrated {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 64, height: 64)
                    .overlay(Image(systemName: icon).font(.system(size: 28, weight: .regular)).foregroundStyle(Color.accentColor))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            Text(title).font(illustrated ? .headline : .callout.weight(.medium)).multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(illustrated ? .large : .regular).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Small "+" / "−" buttons under a master list (Design Options sets, Phases), the macOS list-editing control.
struct DialogAddRemoveBar: View {
    var addHelp = "Add"
    var removeHelp = "Remove"
    var canRemove = true
    let onAdd: () -> Void
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) { Image(systemName: "plus").frame(width: 24, height: 20) }.help(addHelp).accessibilityLabel(addHelp)
            Divider().frame(height: 14)
            Button(action: onRemove) { Image(systemName: "minus").frame(width: 24, height: 20) }.help(removeHelp).accessibilityLabel(removeHelp).disabled(!canRemove)
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .frame(height: 30)
    }
}

/// A small capsule label on a row ("Primary", "Shared", "Loaded").
struct DialogBadge: View {
    let text: String
    var tint: Color = .accentColor
    var body: some View {
        Text(text).font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}

/// A titled pane of a master-detail dialog: a rounded box holding a list (or any content) that fills the height it
/// is given, with an optional bar of small buttons along its bottom edge (+ / −, Duplicate, Check All).
struct DialogPane<Content: View, Bar: View>: View {
    var title: String?
    @ViewBuilder let content: Content
    @ViewBuilder let bar: Bar

    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder bar: () -> Bar) {
        self.title = title; self.content = content(); self.bar = bar()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(DialogStyle.sectionTitle).foregroundStyle(.secondary).padding(.leading, 4).lineLimit(1) }
            VStack(spacing: 0) {
                content
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if Bar.self != EmptyView.self {
                    Divider()
                    HStack(spacing: 8) { bar }
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 30)
                }
            }
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        }
    }
}

extension DialogPane where Bar == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, bar: { EmptyView() })
    }
}
