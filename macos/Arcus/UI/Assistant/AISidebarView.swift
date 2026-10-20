import AppKit
import SwiftUI
import ArcusAssistant

// AICORE: the AI assistant's right sidebar (in the trailing glass dock, like Properties): a header with the model
// state and New Chat / History / Settings / Close, the transcript (or the empty state, the set-up states, History),
// and the composer.

/// The assistant's mark: sparkles on an indigo-to-violet disc.
struct AIMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.96), Color(red: 0.62, green: 0.36, blue: 0.93)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "sparkles").font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum AIStyle {
    static let tint = Color(red: 0.45, green: 0.39, blue: 0.95)
    static let side: CGFloat = 14
    static let bubble = Color.primary.opacity(0.06)
    static let card = Color.primary.opacity(0.045)
    static let stroke = Color.primary.opacity(0.09)
    static let radius: CGFloat = 12
}

struct AISidebarView: View {
    @Bindable var panel: AIAssistantPanel
    var onClose: () -> Void

    var body: some View {
        let agent = panel.agent
        VStack(spacing: 0) {
            AISidebarHeader(panel: panel, onClose: onClose)
            Divider().opacity(0.6)
            Group {
                if panel.showingHistory {
                    AIHistoryList(panel: panel)
                } else if let b = panel.blocker, b != .budget, agent.store.current.turns.isEmpty {
                    ScrollView { AIBlockerView(panel: panel, blocker: b).padding(AIStyle.side) }
                } else if agent.store.current.turns.isEmpty {
                    ScrollView { AIEmptyState(panel: panel).padding(AIStyle.side) }
                } else {
                    AITranscript(panel: panel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let b = panel.blocker, !agent.store.current.turns.isEmpty || b == .budget {
                AIBlockerStrip(panel: panel, blocker: b).padding(.horizontal, 10).padding(.bottom, 6)
            }
            AIComposer(panel: panel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI Assistant")
    }
}

// MARK: - Header

struct AISidebarHeader: View {
    @Bindable var panel: AIAssistantPanel
    var onClose: () -> Void

    var body: some View {
        let agent = panel.agent
        HStack(spacing: 8) {
            AIMark(size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Assistant").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            headerButton("square.and.pencil", "New Chat") { agent.newChat(); panel.showingHistory = false; panel.focusRequest += 1 }
                .disabled(agent.isRunning || agent.store.current.turns.isEmpty)
            headerButton(panel.showingHistory ? "bubble.left.and.text.bubble.right" : "clock.arrow.circlepath", panel.showingHistory ? "Back to the Chat" : "History") {
                panel.showingHistory.toggle()
            }
            headerButton("gearshape", "AI Settings…") { AISettingsLink.open() }
            headerButton("xmark", "Close the Assistant (⇧⌘A)", action: onClose)
        }
        .padding(.leading, AIStyle.side).padding(.trailing, 8)
        .frame(height: 48)
    }

    private var subtitle: String {
        let agent = panel.agent
        if let m = agent.activeModel { return m == .sonnet ? "Retrying a step on \(m.displayName)…" : "Working with \(m.displayName)…" }
        if agent.isRunning { return "Working…" }
        switch panel.blocker {
        case .off: return "Off: turn it on in Settings"
        case .noKey: return "Needs your API key"
        default: break
        }
        return "\(panel.kind.title) · \(AIModel.haiku.displayName)"
    }

    private func headerButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .pillHighlight(false) // PILLS: hover capsule
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Opens Settings at the AI section.
enum AISettingsLink {
    static let notification = Notification.Name("arcus.ai.showSettings")
    @MainActor static func open() {
        AppDelegate.shared?.showSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NotificationCenter.default.post(name: notification, object: nil) }
    }
}

// MARK: - Empty state and suggestions

/// Suggested prompts for the document kind and the selection.
enum AISuggestions {
    static func prompts(_ kind: AIDocumentKind, selection: Int) -> [(symbol: String, text: String)] {
        switch (kind, selection > 0) {
        case (.project, false):
            return [("ruler", "Dimension this plan"), ("arrow.triangle.branch", "Fix overlapping dimensions"),
                    ("doc.richtext", "Prepare a PDF of all sheets"), ("tag", "Tag all doors and windows in this view"),
                    ("house", "Add a 12' x 14' bedroom with a door and a window")]
        case (.project, true):
            return [("pencil.and.outline", "Make these 10' high"), ("ruler", "Dimension the selected walls"),
                    ("tag", "Tag the selection"), ("questionmark.circle", "What's selected and what can I change?")]
        case (.furniture, false):
            return [("square.stack.3d.down.right", "Add drawers to this cabinet"), ("books.vertical", "Add four adjustable shelves"),
                    ("arrow.left.and.right", "Make it 48\" wide and keep the proportions"), ("table.furniture", "Add legs at the corners"),
                    ("doc.richtext", "Prepare a PDF of all sheets")]
        case (.furniture, true):
            return [("pencil.and.outline", "Make the selected parts 3/4\" thick"), ("square.split.2x1", "Divide this bay into two"),
                    ("questionmark.circle", "What's selected?")]
        case (.family, _):
            return [("list.bullet.rectangle", "Explain this family's parameters"), ("arrow.left.and.right", "Which parameters drive the width?"),
                    ("checkmark.seal", "What should I check before loading it into the project?")]
        }
    }
}

struct AIEmptyState: View {
    @Bindable var panel: AIAssistantPanel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AIMark(size: 40).padding(.bottom, 4)
                Text("What should we build?").font(.system(size: 17, weight: .semibold))
                Text(intro).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Try").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(AISuggestions.prompts(panel.kind, selection: panel.selectionCount()), id: \.text) { s in
                    AISuggestionRow(symbol: s.symbol, text: s.text) { panel.send(s.text) }
                        .disabled(!panel.settings.isReady || panel.agent.isRunning)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
                Text("Changes apply live. Each prompt is one Undo; Arcus asks before saving files, large deletes or project-wide changes.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var intro: String {
        switch panel.kind {
        case .project: "Describe what to create or change: walls, rooms, doors, sheets, dimensions, PDFs. Select elements first to change just those."
        case .furniture: "Describe the piece or a change: size, parts, shelves, drawers, legs, drawings."
        case .family: "Ask about this family's parameters, types and forms."
        }
    }
}

struct AISuggestionRow: View {
    let symbol: String
    let text: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(AIStyle.tint).frame(width: 18)
                Text(text).font(.system(size: 12)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Color.primary.opacity(0.08) : AIStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AIStyle.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(text)
        .accessibilityHint("Sends this prompt")
    }
}

// MARK: - Set-up states

struct AIBlockerView: View {
    @Bindable var panel: AIAssistantPanel
    let blocker: AIBlocker

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIMark(size: 40)
            switch blocker {
            case .off:
                title("Turn on the AI assistant", "It's off by default. It's the one part of Arcus that uses the internet, and only while it's on.")
                AIWhatIsSent()
                Button("Open AI Settings…") { AISettingsLink.open() }.buttonStyle(.borderedProminent).controlSize(.large)
            case .noKey:
                title("Add your API key", "The assistant uses your own Anthropic API key, kept in your Mac's Keychain. You pay Anthropic directly for what you use.")
                Button("Open AI Settings…") { AISettingsLink.open() }.buttonStyle(.borderedProminent).controlSize(.large)
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!).font(.system(size: 11))
            case .explain:
                title("Before you start", "This is everything the assistant sends to Anthropic, over HTTPS with your key. Nothing else in Arcus uses the network.")
                AIWhatIsSent()
                HStack {
                    Button("Continue") { panel.settings.explainedWhatIsSent = true; panel.focusRequest += 1 }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    Button("Settings…") { AISettingsLink.open() }.controlSize(.large)
                }
            case .budget:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 16, weight: .semibold))
            Text(s).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The exact list of what is sent (Settings ▸ AI shows it too).
struct AIWhatIsSent: View {
    static let items: [(String, String)] = [
        ("text.bubble", "Your prompt, and earlier prompts and replies of the same chat"),
        ("square.stack.3d.up", "A compact model summary: levels, element counts, units, the active view and the selected elements"),
        ("wrench.and.screwdriver", "Results of the Arcus tools the assistant runs (ids, sizes, warnings)"),
        ("photo", "View images only when checking drawings, and images you attach"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Self.items, id: \.1) { symbol, text in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(AIStyle.tint).frame(width: 16)
                    Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Never sent: your files, other documents, the API key in any message, or anything when the assistant is off.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).fill(AIStyle.card))
        .overlay(RoundedRectangle(cornerRadius: AIStyle.radius, style: .continuous).strokeBorder(AIStyle.stroke))
    }
}

/// A one-line state above the composer when a chat is already open (switched off, key removed, budget reached).
struct AIBlockerStrip: View {
    @Bindable var panel: AIAssistantPanel
    let blocker: AIBlocker
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: blocker == .budget ? "gauge.with.dots.needle.100percent" : "exclamationmark.circle")
                .foregroundStyle(blocker == .budget ? .orange : .secondary)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 4)
            Button(blocker == .explain ? "Review" : "Settings…") {
                if blocker == .explain { panel.settings.explainedWhatIsSent = true } else { AISettingsLink.open() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AIStyle.card))
    }
    private var text: String {
        switch blocker {
        case .off: "The assistant is off."
        case .noKey: "No API key in Settings ▸ AI."
        case .explain: "Review what the assistant sends."
        case .budget: "Monthly budget reached (\(AIFormat.dollars(panel.settings.spent())) of \(AIFormat.dollars(panel.settings.monthlyBudget))). Arcus asks before each prompt."
        }
    }
}

// MARK: - History

struct AIHistoryList: View {
    @Bindable var panel: AIAssistantPanel
    var body: some View {
        let store = panel.agent.store
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chats in this document").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if store.earlier.isEmpty && store.current.turns.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 22)).foregroundStyle(.tertiary)
                        Text("No chats yet").font(.system(size: 12, weight: .medium))
                        Text("Chats are saved with the document.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    if !store.current.turns.isEmpty { row(store.current, current: true) }
                    ForEach(store.earlier) { c in row(c, current: false) }
                    Button(role: .destructive) { store.clearAll(); panel.agent.newChat() } label: { Text("Clear History") }
                        .controlSize(.small).padding(.top, 6)
                        .disabled(panel.agent.isRunning)
                    Text("Earlier chats are never sent; reopening one continues it from its text.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .padding(AIStyle.side)
        }
    }

    private func row(_ c: AIChat, current: Bool) -> some View {
        Button {
            if !current { panel.agent.store.reopen(c.id) }
            panel.showingHistory = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(c.turns.count) prompt\(c.turns.count == 1 ? "" : "s") · \(c.created.formatted(date: .abbreviated, time: .shortened)) · \(AIFormat.dollars(c.cost))\(current ? " · Open" : "")")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(current ? AIStyle.tint.opacity(0.12) : AIStyle.card))
        }
        .buttonStyle(.plain)
        .disabled(panel.agent.isRunning)
    }
}
