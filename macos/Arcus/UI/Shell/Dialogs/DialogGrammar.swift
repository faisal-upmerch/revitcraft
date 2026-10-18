import SwiftUI

// W4-SHELL: one dialog grammar for every sheet and window-like dialog: a 15 pt semibold title with an optional
// 12 pt secondary subtitle, 20 pt outer padding, 12 pt between sections, and a trailing button row whose buttons are
// never narrower than 76 pt (OK/Cancel keep their keyboard equivalents). Window-like dialogs (Materials, Component
// Library) use `DialogChrome`: content fills the dialog, a hairline, then the button row on its own strip.

enum DialogMetrics {
    static let padding: CGFloat = 20
    static let spacing: CGFloat = 12
    static let buttonMinWidth: CGFloat = 76
    static let title = Font.system(size: 15, weight: .semibold)
    static let subtitle = Font.system(size: 12)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
}

/// Dialog title (and subtitle) block.
struct DialogTitle: View {
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DialogMetrics.title).lineLimit(1).truncationMode(.middle)
            if !subtitle.isEmpty { Text(subtitle).font(DialogMetrics.subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Gives a dialog button the grammar's minimum width so short titles ("OK") match their neighbours.
struct DialogButtonWidth: ViewModifier {
    func body(content: Content) -> some View { content.frame(minWidth: DialogMetrics.buttonMinWidth) }
}
extension View {
    func dialogButton() -> some View { modifier(DialogButtonWidth()) }
}

/// The trailing button row: optional leading accessories (Apply, Reset, Paint Selection…), a spacer, Cancel, then the
/// default button. `okTitle` "Done" without Cancel is the close-only form.
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
        HStack(spacing: 10) {
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
            buttons.padding(.horizontal, DialogMetrics.padding).padding(.vertical, 12)
        }
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
