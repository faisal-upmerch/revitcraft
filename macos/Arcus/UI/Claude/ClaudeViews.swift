import SwiftUI
import AppKit
import ArcusApplication

// MCP: Design with Claude in Home (the card under the Start cards, the hint on the Furniture card) and in document
// windows (the bottom bar pill and its activity popover).

/// Home: the card under the Start cards. Clicking it (or Set Up…) opens the Set Up sheet.
struct HomeClaudeCard: View {
    let action: () -> Void
    @State private var claude = ClaudeIntegration.shared

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ClaudeMark(size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Design with Claude").font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        ClaudeStatusBadge(status: claude.status, compact: true)
                    }
                    Text("Describe a building or a piece of furniture and Claude builds it in Arcus.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text(claude.isSetUp ? "Prompts and settings…" : "Set Up…")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeCard(selected: false, tint: .accentColor, radius: Tokens.cardCornerRadius + 4, outlined: true)
        }
        .buttonStyle(.plain)
        .onAppear { claude.refresh() }
        .help("Design with Claude: set up Claude Desktop or Claude Code to build in Arcus")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Design with Claude")
        .accessibilityValue(claude.status.title)
        .accessibilityHint("Opens the setup for building in Arcus with Claude")
        .accessibilityAddTraits(.isButton)
    }
}

/// Home ▸ Furniture and Load Furniture: one line saying Claude can design pieces.
struct ClaudeFurnitureHint: View {
    var action: () -> Void = { ClaudeSetupWindow.show() }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(Color(red: 0.82, green: 0.45, blue: 0.32))
            Text("Claude can design a piece for you: “a walnut sideboard, 60 in wide, with two drawers”.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Button("Design with Claude…", action: action).buttonStyle(.link).font(.system(size: 11))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bottom bar pill while live mode is on: Claude ready / connected / editing; click for what Claude did.
struct ClaudeStatusPill: View {
    let session: DocumentSession
    @State private var claude = ClaudeIntegration.shared
    @State private var showing = false

    var body: some View {
        let status = claude.status == .notSetUp ? ClaudeIntegration.Status.ready : claude.status
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                if status == .editing { ProgressView().controlSize(.mini).scaleEffect(0.8) } else {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                }
                Text(status == .ready ? "Claude" : status.title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(status == .ready ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color(nsColor: status.tint)))
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(status == .ready ? Color.primary.opacity(0.06) : Color(nsColor: status.tint).opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(status == .ready ? "Claude can edit this document (live mode). Click for activity." : status.title)
        .accessibilityLabel("Claude: \(status.title)")
        .popover(isPresented: $showing, arrowEdge: .top) { ClaudeActivityView(session: session) }
    }
}

/// What Claude did recently, with Undo for the last change and the setup.
struct ClaudeActivityView: View {
    let session: DocumentSession
    @State private var claude = ClaudeIntegration.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ClaudeMark(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude").font(.system(size: 13, weight: .semibold))
                    Text(claude.listening ? "Can edit open documents" : "Live editing is off").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                ClaudeStatusBadge(status: claude.status, compact: true)
            }
            Divider()
            if claude.actions.isEmpty {
                Text("Nothing yet. Ask Claude to build or change something in Arcus; each change shows here and is one Undo step.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(claude.actions.prefix(8)) { a in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: a.ok ? (a.edits ? "pencil.circle.fill" : "eye.circle") : "exclamationmark.triangle.fill")
                                .foregroundStyle(a.ok ? (a.edits ? Color.accentColor : Color.secondary) : Color.orange)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.title).font(.system(size: 12, weight: .medium))
                                Text(a.ok ? a.document : a.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Text(a.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Undo \(undoTitle ?? "")") { session.undoManager.undo() }
                    .disabled(undoTitle == nil)
                    .help("Undo Claude's last change in this document (⌘Z does the same)")
                Spacer()
                Button("Design with Claude…") { ClaudeSetupWindow.show() }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    /// The last Claude change, when it is this document's next Undo.
    var undoTitle: String? {
        guard let last = claude.actions.first(where: { $0.edits && $0.ok }), session.undoManager.canUndo,
              session.undoManager.undoActionName == last.title else { return nil }
        return last.title
    }
}
