import SwiftUI
import ArcusDomain

// DIALOGS: report views. Results (Model Health, Warnings, import and export reports) read as summary tiles with counts
// over a list grouped by severity, each row with its own actions (Show, Select), in the proportional system font. A
// plain-text report is laid out as headings, paragraphs and bullet rows rather than a monospaced dump.

/// Severity of a reported item.
enum DialogSeverity: Int, CaseIterable, Comparable, Sendable {
    case error, warning, info
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    init(_ s: ModelWarning.Severity) {
        switch s { case .error: self = .error; case .warning: self = .warning; case .info: self = .info }
    }
    var symbol: String {
        switch self { case .error: "xmark.octagon.fill"; case .warning: "exclamationmark.triangle.fill"; case .info: "info.circle.fill" }
    }
    var color: Color {
        switch self { case .error: .red; case .warning: .orange; case .info: .secondary }
    }
    var plural: String {
        switch self { case .error: "Errors"; case .warning: "Warnings"; case .info: "Info" }
    }
}

/// A count tile (Errors 2, Warnings 5, Info 1). Tapping it filters the list under it when `filter` is bound.
struct DialogSummaryTiles: View {
    struct Tile: Identifiable {
        var id: String { label }
        let label: String
        let count: Int
        let symbol: String
        let tint: Color
        var severity: DialogSeverity? = nil
    }
    let tiles: [Tile]
    var filter: Binding<DialogSeverity?>? = nil

    static func severities(_ counts: [DialogSeverity: Int]) -> [Tile] {
        DialogSeverity.allCases.map { Tile(label: $0.plural, count: counts[$0] ?? 0, symbol: $0.symbol, tint: $0 == .info ? .accentColor : $0.color, severity: $0) }
    }

    var body: some View {
        HStack(spacing: DialogStyle.itemSpacing + 2) {
            ForEach(tiles) { t in tile(t) }
        }
    }

    private func tile(_ t: Tile) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
        let on = filter?.wrappedValue != nil && filter?.wrappedValue == t.severity
        return Button {
            guard let filter, let s = t.severity else { return }
            filter.wrappedValue = filter.wrappedValue == s ? nil : s
        } label: {
            HStack(spacing: 10) {
                Image(systemName: t.symbol).font(.title3).foregroundStyle(t.count == 0 ? Color.secondary.opacity(0.6) : t.tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(t.count)").font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(t.count == 0 ? .secondary : .primary)
                    Text(t.label).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DialogColors.sectionFill, in: shape)
            .overlay(shape.strokeBorder(on ? t.tint.opacity(0.8) : DialogColors.sectionStroke, lineWidth: on ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(filter == nil || t.severity == nil)
        .accessibilityLabel("\(t.count) \(t.label)")
    }
}

/// An item of a `DialogIssueList`.
struct DialogIssue: Identifiable, Hashable {
    let id: String
    let severity: DialogSeverity
    let title: String
    var detail: String = ""
}

/// Issues grouped by severity (errors first), each group titled with its count, each row with its actions.
struct DialogIssueList<Actions: View, Empty: View>: View {
    let issues: [DialogIssue]
    var maxHeight: CGFloat = 340
    @ViewBuilder let actions: (DialogIssue) -> Actions
    @ViewBuilder let empty: Empty

    init(issues: [DialogIssue], maxHeight: CGFloat = 340, @ViewBuilder actions: @escaping (DialogIssue) -> Actions, @ViewBuilder empty: () -> Empty) {
        self.issues = issues; self.maxHeight = maxHeight; self.actions = actions; self.empty = empty()
    }

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        if issues.isEmpty {
            empty
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(DialogColors.sectionFill, in: shape)
                .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(DialogSeverity.allCases, id: \.self) { s in
                        let group = issues.filter { $0.severity == s }
                        if !group.isEmpty {
                            HStack(spacing: 6) {
                                Text(s.plural).font(DialogStyle.sectionTitle).foregroundStyle(.secondary)
                                Text("\(group.count)").font(.caption.weight(.semibold)).monospacedDigit()
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(s.color.opacity(s == .info ? 0.15 : 0.18)))
                                    .foregroundStyle(s == .info ? Color.secondary : s.color)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                            ForEach(Array(group.enumerated()), id: \.element.id) { i, issue in
                                if i > 0 { DialogColors.rowDivider.frame(height: 1).padding(.leading, 40) }
                                row(issue)
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 80), maxHeight))
            .background(DialogColors.sectionFill, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
        }
    }

    private func row(_ issue: DialogIssue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: issue.severity.symbol).foregroundStyle(issue.severity == .info ? Color.accentColor : issue.severity.color)
                .frame(width: 18).accessibilityLabel(issue.severity.plural)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).fixedSize(horizontal: false, vertical: true)
                if !issue.detail.isEmpty { Text(issue.detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) { actions(issue) }.controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A plain-text report laid out for reading: "Heading:" lines bold, "•"/"-" lines as bullet rows, other lines as
/// paragraphs, in the system font; selectable. Scrolls past `maxHeight`.
struct DialogReportText: View {
    let text: String
    var maxHeight: CGFloat = 380
    @State private var contentHeight: CGFloat = 0

    enum Line: Hashable { case heading(String), bullet(String), paragraph(String), gap }

    /// Splits a report into headings, bullets and paragraphs.
    static func lines(_ text: String) -> [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { if let last = out.last, last != .gap { out.append(.gap) }; continue }
            if let first = t.first, "•-*–·".contains(first), t.count > 1 {
                out.append(.bullet(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if t.hasSuffix(":"), t.count <= 80 {
                out.append(.heading(String(t.dropLast())))
            } else {
                out.append(.paragraph(t))
            }
        }
        while out.last == .gap { out.removeLast() }
        return out
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusSection, style: .continuous)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(Self.lines(text).enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .heading(let s): Text(s).font(.callout.weight(.semibold)).padding(.top, 2)
                    case .bullet(let s):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(.secondary).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            Text(s).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 4)
                    case .paragraph(let s): Text(s).fixedSize(horizontal: false, vertical: true)
                    case .gap: Color.clear.frame(height: 6)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 60), maxHeight))
        .background(DialogColors.sectionFill, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(DialogColors.sectionStroke, lineWidth: 1))
    }
}
