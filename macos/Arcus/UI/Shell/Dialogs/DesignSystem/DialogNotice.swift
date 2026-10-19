import SwiftUI

// DIALOGS: callouts. Explanations, warnings and errors in a dialog are notices (an icon, a short line, optional
// detail behind "Learn more"), never raw coloured paragraphs.

/// An info, success, warning or error callout.
struct DialogNotice: View {
    enum Kind: Sendable {
        case info, success, warning, error
        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
        var color: Color {
            switch self {
            case .info: .accentColor
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    var kind: Kind = .info
    var title: String? = nil
    let message: String
    /// Longer explanation revealed by "Learn more".
    var detail: String? = nil
    @State private var expanded = false

    init(_ kind: Kind = .info, title: String? = nil, _ message: String, detail: String? = nil) {
        self.kind = kind; self.title = title; self.message = message; self.detail = detail
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: kind.symbol).foregroundStyle(kind.color).font(.body).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).font(.callout.weight(.semibold)) }
                if !message.isEmpty {
                    Text(message).font(.callout).foregroundStyle(title == nil ? .primary : .secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let detail, !detail.isEmpty {
                    if expanded {
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 3) {
                            Text(expanded ? "Show less" : "Learn more")
                            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.08), in: shape)
        .overlay(shape.strokeBorder(kind.color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Facts about a file shown in import dialogs.
enum DialogFileInfo {
    /// " · 2.4 MB" for an existing file, "" otherwise.
    static func sizeSuffix(_ url: URL) -> String {
        guard let n = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return "" }
        return " · " + ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

/// Readable text for an error shown in a dialog: Foundation and localized errors by their description (not the raw
/// `Error Domain=… UserInfo=…` dump), others by their own description.
enum DialogErrorText {
    static func describe(_ error: any Error) -> String {
        if error is any LocalizedError { return error.localizedDescription }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain || ns.domain == NSURLErrorDomain { return ns.localizedDescription }
        return "\(error)"
    }
}
