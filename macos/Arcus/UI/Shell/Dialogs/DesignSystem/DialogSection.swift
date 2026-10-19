import SwiftUI

// DIALOGS: grouped sections (the macOS grouped-form look): an optional title above a rounded box whose rows are
// separated by inset hairlines, and an optional footnote below. Rows label their controls in a column of one shared
// width (`dialogLabelWidth`, set by `ArcusDialog`), so every control in a dialog starts on the same line.

/// A titled group of rows in a rounded box.
struct DialogSection<Content: View, Accessory: View>: View {
    var title: String?
    var footnote: String?
    /// Pad and separate each child as a row (false: the child brings its own layout, e.g. a preview or a progress view).
    var rows = true
    /// Draw the rounded box (false: only the title, accessory and footnote around a child with its own box, e.g. a list).
    var boxed = true
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    init(_ title: String? = nil, footnote: String? = nil, rows: Bool = true, boxed: Bool = true, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.footnote = footnote; self.rows = rows; self.boxed = boxed
        self.content = content(); self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .firstTextBaseline) {
                    if let title { Text(title).font(DialogStyle.sectionTitle).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader) }
                    Spacer(minLength: 8)
                    accessory.controlSize(.small)
                }
                .padding(.horizontal, 4)
            }
            if boxed { box } else { content }
            if let footnote, !footnote.isEmpty {
                Text(footnote).font(DialogStyle.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var box: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        Group {
            if rows {
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { subviews in
                        ForEach(Array(subviews.enumerated()), id: \.element.id) { i, row in
                            if i > 0 { DialogColors.rowDivider.frame(height: 1).padding(.leading, DialogStyle.rowPaddingH) }
                            row
                                .frame(maxWidth: .infinity, minHeight: DialogStyle.rowMinHeight - 2 * DialogStyle.rowPaddingV, alignment: .leading)
                                .padding(.horizontal, DialogStyle.rowPaddingH)
                                .padding(.vertical, DialogStyle.rowPaddingV)
                        }
                    }
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DialogColors.sectionFill, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
    }
}

extension DialogSection where Accessory == EmptyView {
    init(_ title: String? = nil, footnote: String? = nil, rows: Bool = true, boxed: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title, footnote: footnote, rows: rows, boxed: boxed, content: content, accessory: { EmptyView() })
    }
}

/// A labelled row: the label in the dialog's label column, the control after it.
struct DialogRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let content: Content
    @Environment(\.dialogLabelWidth) private var labelWidth

    init(_ label: String, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.label = label; self.alignment = alignment; self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: labelWidth, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A row that only shows a value (read-only facts: file size, schema, counts).
struct DialogValueRow: View {
    let label: String
    let value: String
    var body: some View {
        DialogRow(label) {
            Text(value).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}

/// A free-standing caption line under a control group (units, ranges, what an option does).
struct DialogCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(DialogStyle.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
