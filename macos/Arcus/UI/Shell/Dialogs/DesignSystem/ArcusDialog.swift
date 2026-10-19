import AppKit
import SwiftUI
import UniformTypeIdentifiers

// DIALOGS: the container every modal uses (Docs/Dialogs.md). Layout, top to bottom:
//   header   icon tile · title (.title3 semibold) · one-line subtitle (secondary)
//   content  sections on the window background, 20 pt from the edges, 16 pt apart
//   footer   full-width separator; secondary actions on the left (Copy, Check All, Help…); on the right an optional
//            reason the default button is disabled, extra buttons (Apply), Cancel (Esc) and the default button (Return)
// The dialog is opaque, as wide as its size class and as tall as its content; content taller than the class's maximum
// scrolls when `scrolls` is set (lists and tables size themselves instead).

/// A modal dialog: header, content and footer bar.
struct ArcusDialog<Content: View, Leading: View, Trailing: View>: View {
    var icon: String
    var tint: Color = .accentColor
    var title: String
    var subtitle: String = ""
    /// The file the dialog acts on (imports, links): the header shows its Finder icon instead of the symbol tile.
    var file: URL? = nil
    var size: DialogSize = .medium
    /// Label column width of the dialog's `DialogRow`s (the size class's default when nil).
    var labelWidth: CGFloat? = nil
    var okTitle: String = "OK"
    var okDisabled = false
    /// Why the default button is disabled: shown in the footer and as its help tag.
    var disabledReason: String? = nil
    var showCancel = true
    var cancelTitle = "Cancel"
    /// The default button is destructive (Purge, Delete): it keeps Return but reads as a warning.
    var destructive = false
    /// The default button's key: Return, ⌘Return in editors whose fields take Return, nil while a field takes it.
    var okShortcut: KeyboardShortcut? = .defaultAction
    /// Wrap the content in a scroll view that grows with the content up to the size class's maximum height.
    var scrolls = false
    /// Window-like editors: the content fills the dialog, which starts at this height (and the class's width).
    var height: CGFloat? = nil
    /// Content edge padding (editors that run edge to edge pass false).
    var padded = true
    let onCancel: () -> Void
    let onOK: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(icon: icon, tint: tint, title: title, subtitle: subtitle, file: file)
                .padding(.horizontal, DialogStyle.outer)
                .padding(.top, DialogStyle.outer)
                .padding(.bottom, DialogStyle.sectionSpacing)
            contentArea
            DialogFooter(okTitle: okTitle, okDisabled: okDisabled, disabledReason: disabledReason, showCancel: showCancel,
                         cancelTitle: cancelTitle, destructive: destructive, okShortcut: okShortcut, onCancel: onCancel, onOK: onOK) {
                leading
            } trailing: {
                trailing
            }
        }
        .environment(\.dialogLabelWidth, labelWidth ?? size.labelWidth)
        .frame(minWidth: size.minWidth, idealWidth: size.width, maxWidth: height == nil ? size.width : size.maxWidth,
               minHeight: height.map { min($0, 360) }, idealHeight: height, maxHeight: height == nil ? nil : .infinity)
        .background(DialogColors.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) { content }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, padded ? DialogStyle.outer : 0)
            .padding(.bottom, padded ? DialogStyle.outer : 0)
    }

    @ViewBuilder private var contentArea: some View {
        if height != nil {
            stack.frame(maxHeight: .infinity, alignment: .top)
        } else if scrolls {
            ScrollView(.vertical) {
                stack.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 60), size.maxContentHeight))
        } else {
            stack.fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension ArcusDialog {
    /// Whether Return presses the default button (off while a field in the dialog takes Return itself).
    func returnKeyEnabled(_ on: Bool) -> Self { var d = self; d.okShortcut = on ? .defaultAction : nil; return d }
    /// The default button's keyboard shortcut (⌘Return in editors whose fields take Return).
    func okKeyboardShortcut(_ s: KeyboardShortcut?) -> Self { var d = self; d.okShortcut = s; return d }
}

extension ArcusDialog where Leading == EmptyView, Trailing == EmptyView {
    init(icon: String, tint: Color = .accentColor, title: String, subtitle: String = "", file: URL? = nil, size: DialogSize = .medium, labelWidth: CGFloat? = nil,
         okTitle: String = "OK", okDisabled: Bool = false, disabledReason: String? = nil, showCancel: Bool = true, cancelTitle: String = "Cancel",
         destructive: Bool = false, scrolls: Bool = false, height: CGFloat? = nil, padded: Bool = true,
         onCancel: @escaping () -> Void, onOK: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, file: file, size: size, labelWidth: labelWidth, okTitle: okTitle, okDisabled: okDisabled,
                  disabledReason: disabledReason, showCancel: showCancel, cancelTitle: cancelTitle, destructive: destructive, scrolls: scrolls,
                  height: height, padded: padded, onCancel: onCancel, onOK: onOK, content: content, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension ArcusDialog where Trailing == EmptyView {
    init(icon: String, tint: Color = .accentColor, title: String, subtitle: String = "", file: URL? = nil, size: DialogSize = .medium, labelWidth: CGFloat? = nil,
         okTitle: String = "OK", okDisabled: Bool = false, disabledReason: String? = nil, showCancel: Bool = true, cancelTitle: String = "Cancel",
         destructive: Bool = false, scrolls: Bool = false, height: CGFloat? = nil, padded: Bool = true,
         onCancel: @escaping () -> Void, onOK: @escaping () -> Void, @ViewBuilder content: () -> Content, @ViewBuilder leading: () -> Leading) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, file: file, size: size, labelWidth: labelWidth, okTitle: okTitle, okDisabled: okDisabled,
                  disabledReason: disabledReason, showCancel: showCancel, cancelTitle: cancelTitle, destructive: destructive, scrolls: scrolls,
                  height: height, padded: padded, onCancel: onCancel, onOK: onOK, content: content, leading: leading, trailing: { EmptyView() })
    }
}

extension ArcusDialog where Leading == EmptyView {
    init(icon: String, tint: Color = .accentColor, title: String, subtitle: String = "", file: URL? = nil, size: DialogSize = .medium, labelWidth: CGFloat? = nil,
         okTitle: String = "OK", okDisabled: Bool = false, disabledReason: String? = nil, showCancel: Bool = true, cancelTitle: String = "Cancel",
         destructive: Bool = false, scrolls: Bool = false, height: CGFloat? = nil, padded: Bool = true,
         onCancel: @escaping () -> Void, onOK: @escaping () -> Void, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle, file: file, size: size, labelWidth: labelWidth, okTitle: okTitle, okDisabled: okDisabled,
                  disabledReason: disabledReason, showCancel: showCancel, cancelTitle: cancelTitle, destructive: destructive, scrolls: scrolls,
                  height: height, padded: padded, onCancel: onCancel, onOK: onOK, content: content, leading: { EmptyView() }, trailing: trailing)
    }
}

/// The dialog's header: a tinted icon tile, the title and a one-line subtitle.
struct DialogHeader: View {
    let icon: String
    var tint: Color = .accentColor
    let title: String
    var subtitle: String = ""
    var file: URL? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let file {
                Image(nsImage: DialogFileIcon.image(for: file)).resizable().interpolation(.high)
                    .frame(width: DialogStyle.iconTile + 6, height: DialogStyle.iconTile + 6)
                    .padding(-3)
                    .accessibilityHidden(true)
            } else {
                DialogIconTile(symbol: icon, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DialogStyle.title).lineLimit(1).truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle).font(DialogStyle.subtitle).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded tile with an SF Symbol on a tinted gradient (the System Settings look).
struct DialogIconTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = DialogStyle.iconTile

    var body: some View {
        RoundedRectangle(cornerRadius: Tokens.radiusTile * size / DialogStyle.iconTile, style: .continuous)
            .fill(tint.gradient)
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusTile * size / DialogStyle.iconTile, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// The footer bar: full-width separator, secondary actions left, Cancel and the default button right.
struct DialogFooter<Leading: View, Trailing: View>: View {
    var okTitle = "OK"
    var okDisabled = false
    var disabledReason: String? = nil
    var showCancel = true
    var cancelTitle = "Cancel"
    var destructive = false
    var okShortcut: KeyboardShortcut? = .defaultAction
    let onCancel: () -> Void
    let onOK: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: DialogStyle.itemSpacing) {
                HStack(spacing: DialogStyle.itemSpacing) { leading }.fixedSize()
                Spacer(minLength: 12)
                if okDisabled, let disabledReason, !disabledReason.isEmpty {
                    Label(disabledReason, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(okTitle) is unavailable: \(disabledReason)")
                }
                HStack(spacing: DialogStyle.itemSpacing) { trailing }.fixedSize()
                if showCancel {
                    Button(cancelTitle, action: onCancel).keyboardShortcut(.cancelAction).dialogButton()
                }
                Button(okTitle, role: destructive ? .destructive : nil, action: onOK)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? .red : .accentColor)
                    .keyboardShortcut(okShortcut)
                    .disabled(okDisabled)
                    .help(okDisabled ? (disabledReason ?? "") : "")
                    .dialogButton()
            }
            .padding(.horizontal, DialogStyle.outer)
            .padding(.vertical, DialogStyle.footerPaddingV)
        }
    }
}

/// The Finder icon of a file, or of its type when the file doesn't exist.
enum DialogFileIcon {
    static func image(for url: URL) -> NSImage {
        if FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}
