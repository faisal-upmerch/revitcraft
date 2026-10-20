import AppKit
import SwiftUI
import ArcusAssistant

// AICORE: Settings ▸ AI Assistant: the opt-in switch (off by default), the API key (Keychain) with Test, the monthly
// budget and this month's spending, what is sent, the price table (editable; the published prices with the date
// they were checked), and Clear All Chats.

struct AISettingsSection: View {
    @Bindable var settings: AISettings = .shared
    var testTransport: (any AITransport)? = nil
    @State private var keyField = ""
    @State private var editingKey = false
    @State private var testState: TestState = .idle
    @State private var showPrices = false
    @State private var showSent = false
    @State private var cleared = false

    enum TestState: Equatable { case idle, running, ok(String), failed(String) }

    var body: some View {
        Toggle(isOn: $settings.enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use the AI assistant")
                Text("The AI button (⇧⌘A) opens a chat in every window. Off by default; while off, Arcus makes no network connections.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        LabeledContent("Anthropic API key") {
            VStack(alignment: .trailing, spacing: 6) {
                if settings.hasKey && !editingKey {
                    HStack(spacing: 8) {
                        Text(settings.maskedKey ?? "").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                        Button("Change…") { editingKey = true; keyField = "" }
                        Button("Remove", role: .destructive) { settings.removeKey(); testState = .idle }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("sk-ant-…", text: $keyField).textFieldStyle(.roundedBorder).frame(width: 220)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey).disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.hasKey { Button("Cancel") { editingKey = false; keyField = "" } }
                    }
                }
            }
        }
        HStack(spacing: 8) {
            Button("Test") { test() }.disabled(!settings.enabled || (!settings.hasKey && keyField.isEmpty) || testState == .running)
            switch testState {
            case .idle:
                Text(settings.enabled ? "Checks the key with Anthropic (free; no tokens used)." : "Turn the assistant on to test the key.")
                    .font(.caption).foregroundStyle(.secondary)
            case .running: ProgressView().controlSize(.small); Text("Checking…").font(.caption).foregroundStyle(.secondary)
            case .ok(let m): Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .failed(let m): Label(m, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Spacer()
            Link("Get a key…", destination: URL(string: "https://console.anthropic.com/settings/keys")!).font(.caption)
        }
        Text("The key is stored in your Mac's Keychain only (never in documents, settings files or logs) and sent only to api.anthropic.com.")
            .font(.caption).foregroundStyle(.secondary)
        LabeledContent("Monthly budget") {
            HStack(spacing: 6) {
                Text("$")
                TextField("Budget", value: $settings.monthlyBudget, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
                Stepper("", value: $settings.monthlyBudget, in: 0...1000, step: 5).labelsHidden()
            }
        }
        Text(spendingLine).font(.caption).foregroundStyle(settings.budgetReached ? .orange : .secondary)
        DisclosureGroup("What the assistant sends", isExpanded: $showSent) {
            AIWhatIsSent().padding(.vertical, 4)
            Text("Models: Haiku 5.5 does the work; a step that fails Arcus's check twice is retried on Sonnet 5.5. No other models. The cost line under each reply shows which ran.")
                .font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Prices", isExpanded: $showPrices) {
            AIPriceTableEditor(settings: settings).padding(.vertical, 4)
        }
        HStack {
            Button("Clear All Chats…") { clearAll() }
            if cleared { Text("Cleared in open documents.").font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
        .onAppear { if !settings.hasKey { editingKey = true } }
    }

    private var spendingLine: String {
        let spent = AIFormat.dollars(settings.spent())
        if settings.monthlyBudget <= 0 { return "This month: \(spent). No budget: Arcus never stops for cost." }
        let line = "This month: \(spent) of \(AIFormat.dollars(settings.monthlyBudget))."
        return settings.budgetReached ? line + " Budget reached: the assistant asks before each prompt." : line + " At the budget the assistant stops and asks."
    }

    private func saveKey() {
        let k = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if settings.setKey(k) {
            keyField = ""
            editingKey = false
            testState = .idle
        } else {
            testState = .failed("The Keychain didn't accept the key.")
        }
    }

    private func test() {
        let typed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .running
        let client = AnthropicClient(transport: testTransport ?? URLSessionTransport(), access: AISettings.access(settings))
        Task {
            let r = await client.test(key: typed.isEmpty ? nil : typed)
            switch r {
            case .success(let m): testState = .ok(m)
            case .failure(let e): testState = .failed(e.message)
            }
        }
    }

    private func clearAll() {
        let a = NSAlert()
        a.messageText = "Clear all AI chats?"
        a.informativeText = "Removes the assistant's chats from every open document (they're dropped from the files on the next save). This can't be undone."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for d in NSDocumentController.shared.documents.compactMap({ $0 as? ArcusDocument }) {
            d.assistantHistory = nil
            if let s = d.state { let p = AIAssistantPanel.of(s); if !p.agent.isRunning { p.agent.store.clearAll(); p.agent.newChat() } }
            d.updateChangeCount(.changeDone)
        }
        cleared = true
    }
}

/// The editable price table, US dollars per million tokens.
struct AIPriceTableEditor: View {
    @Bindable var settings: AISettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("$ / million tokens").gridColumnAlignment(.leading)
                    Text("Input"); Text("Cache write"); Text("Cache read"); Text("Output")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                row("Haiku 5.5", \.haiku)
                row("Haiku 5.5 (prompts over 100K)", \.haikuLong)
                row("Sonnet 5.5", \.sonnet)
            }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: settings.prices.edited ? "pencil.circle" : "checkmark.seal").foregroundStyle(.secondary)
                Text(settings.prices.edited
                     ? "Custom prices. Check current pricing at anthropic.com/pricing."
                     : "Anthropic's published prices, checked \(AIPriceTable.checkedOn). Check current pricing at anthropic.com/pricing; edit if they change.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset") { settings.resetPrices() }.controlSize(.small).disabled(!settings.prices.edited)
            }
        }
    }

    private func row(_ title: String, _ card: WritableKeyPath<AIPriceTable, AIRateCard>) -> some View {
        GridRow {
            Text(title).font(.caption).gridColumnAlignment(.leading)
            field(card.appending(path: \.input))
            field(card.appending(path: \.cacheWrite))
            field(card.appending(path: \.cacheRead))
            field(card.appending(path: \.output))
        }
    }

    private func field(_ kp: WritableKeyPath<AIPriceTable, Double>) -> some View {
        TextField("", value: Binding(get: { settings.prices[keyPath: kp] }, set: { v in
            var p = settings.prices
            p[keyPath: kp] = max(0, v)
            let pub = AIPriceTable.published
            p.edited = p.haiku != pub.haiku || p.haikuLong != pub.haikuLong || p.sonnet != pub.sonnet
            settings.prices = p
        }), format: .number.precision(.fractionLength(0...3)))
        .textFieldStyle(.roundedBorder).frame(width: 62).multilineTextAlignment(.trailing).font(.caption.monospacedDigit())
    }
}
