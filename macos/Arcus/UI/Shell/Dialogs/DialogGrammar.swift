import SwiftUI

// W4-SHELL → DIALOGS: the older dialog grammar, now thin adapters over the dialog design system
// (Dialogs/DesignSystem, Docs/Dialogs.md). New dialogs use `ArcusDialog` (or `DialogFrame` for a document sheet)
// with `DialogSection` / `DialogRow`; these names stay so older call sites keep compiling and look the same.

enum DialogMetrics {
    static let padding: CGFloat = DialogStyle.outer
    static let spacing: CGFloat = DialogStyle.sectionSpacing
    static let buttonMinWidth: CGFloat = DialogStyle.buttonMinWidth
    static let title = DialogStyle.title
    static let subtitle = DialogStyle.subtitle
    static let sectionHeader = DialogStyle.sectionTitle
}

/// Dialog title (and subtitle) block: the design system's header with an icon chosen from the title.
struct DialogTitle: View {
    let title: String
    var subtitle: String = ""
    var icon: String? = nil
    var body: some View { DialogHeader(icon: icon ?? DialogIcons.symbol(for: title), title: title, subtitle: subtitle) }
}

extension View {
    /// Gives a dialog button the minimum width so short titles ("OK") match their neighbours.
    func dialogButton() -> some View { frame(minWidth: DialogStyle.buttonMinWidth) }
}

/// The trailing button row: optional leading accessories (Apply, Reset, Paint Selection…), a spacer, Cancel, then the
/// default button. `okTitle` "Done" without Cancel is the close-only form. (The footer bar's buttons without its
/// separator and padding; dialogs use `ArcusDialog`'s footer.)
struct DialogButtonRow<Leading: View>: View {
    var okTitle = "OK"
    var okDisabled = false
    var showCancel = true
    let onCancel: () -> Void
    let onOK: () -> Void
    @ViewBuilder let leading: Leading

    init(okTitle: String = "OK", okDisabled: Bool = false, showCancel: Bool = true, onCancel: @escaping () -> Void, onOK: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading = { EmptyView() }) {
        self.okTitle = okTitle; self.okDisabled = okDisabled; self.showCancel = showCancel
        self.onCancel = onCancel; self.onOK = onOK; self.leading = leading()
    }

    var body: some View {
        HStack(spacing: DialogStyle.itemSpacing) {
            leading
            Spacer(minLength: 16)
            if showCancel { Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction).dialogButton() }
            Button(okTitle, action: onOK).keyboardShortcut(.defaultAction).disabled(okDisabled).dialogButton()
        }
    }
}

/// Window-like dialog chrome: the content fills the dialog edge to edge, a hairline separates it from the button strip.
struct DialogChrome<Content: View, Buttons: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons
    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            buttons.padding(.horizontal, DialogStyle.outer).padding(.vertical, DialogStyle.footerPaddingV)
        }
        .background(DialogColors.background)
    }
}

/// A large, editable name at the top of a detail pane (Materials, Type Properties…). The explicit height keeps the
/// 20 pt text inside the field's frame: a plain text field otherwise sizes itself for the default font and draws the
/// larger text clipped above its frame.
struct DialogNameField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .semibold))
            .lineLimit(1)
            .frame(height: 30)
            .onSubmit(onCommit)
    }
}

/// The header icon for a dialog that doesn't name one: picked from words in its title.
enum DialogIcons {
    static func symbol(for title: String) -> String {
        let t = title.lowercased()
        let table: [(String, String)] = [
            ("export", "square.and.arrow.up"), ("import", "square.and.arrow.down"), ("link", "link"), ("print", "printer"),
            ("schedule", "tablecells"), ("sheet", "doc.richtext"), ("revision", "cloud"), ("view", "rectangle.on.rectangle"),
            ("phase", "clock.arrow.circlepath"), ("option", "square.stack.3d.up"), ("material", "paintpalette"), ("unit", "ruler"),
            ("parameter", "slider.horizontal.3"), ("family", "cube"), ("type", "square.grid.2x2"), ("level", "square.3.layers.3d"),
            ("location", "location"), ("coordinate", "scope"), ("health", "stethoscope"), ("warning", "exclamationmark.triangle"),
            ("purge", "trash"), ("rename", "pencil"), ("filter", "line.3.horizontal.decrease.circle"), ("select", "cursorarrow.rays"),
            ("snap", "dot.squareshape.split.2x2"), ("render", "camera.aperture"), ("site", "mountain.2"), ("topo", "mountain.2"),
            ("surface", "mountain.2"), ("joint", "square.split.diagonal"), ("stock", "rectangle.split.3x3"), ("hardware", "wrench.and.screwdriver"),
            ("part", "checklist"), ("furniture", "chair.lounge"), ("template", "doc.badge.gearshape"), ("setting", "gearshape"),
            ("style", "paintbrush"), ("tag", "tag"), ("color", "paintpalette"), ("area", "square.dashed"), ("spell", "textformat.abc"),
            ("find", "magnifyingglass"), ("keyboard", "keyboard"), ("shortcut", "keyboard"), ("report", "doc.text.magnifyingglass"),
        ]
        return table.first { t.contains($0.0) }?.1 ?? "macwindow"
    }
}
