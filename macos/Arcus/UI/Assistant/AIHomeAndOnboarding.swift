import AppKit
import SwiftUI
import ArcusAssistant

// AICORE: where the assistant is introduced: a compact card on Home under Design with Claude, and an onboarding step.

/// Home: the in-app assistant, under the Design with Claude card. Opens Settings ▸ AI Assistant.
struct HomeAssistantCard: View {
    @Bindable var settings: AISettings = .shared
    var body: some View {
        Button { AISettingsLink.open() } label: {
            HStack(alignment: .top, spacing: 12) {
                AIMark(size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("AI Assistant").font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        status
                    }
                    Text("Chat in any window with the AI button (⇧⌘A): Arcus makes the changes live, one Undo per prompt.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    Text(settings.isReady ? "Settings…" : "Set Up…")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeCard(selected: false, tint: AIStyle.tint, radius: Tokens.cardCornerRadius + 4, outlined: true)
        }
        .buttonStyle(.plain)
        .help("AI Assistant: uses your Anthropic API key; off until you turn it on")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI Assistant")
        .accessibilityValue(statusText)
        .accessibilityHint("Opens the assistant's settings")
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: String { settings.isReady ? "Ready" : (settings.enabled ? "Needs a key" : "Off") }

    private var status: some View {
        let ready = settings.isReady
        return Text(statusText).font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize()
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((ready ? Color.green : Color.secondary).opacity(0.12)))
    }
}

/// Onboarding: the AI assistant (after Design with Claude).
struct AIOnboardingStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AIMark(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Assistant").font(.title2.weight(.semibold))
                    Text("Ask in the window; Arcus does it.").foregroundStyle(.secondary)
                }
            }
            row("sparkles", "Chat beside your design", "The AI button at the top right (⇧⌘A) opens a sidebar in projects, furniture and the Family Editor. Create, change the selection, dimension plans, fix drawings, prepare PDFs.")
            row("arrow.uturn.backward.circle", "Live, one Undo per prompt", "Changes appear as they're made. Arcus asks before saving files, large deletes or project-wide changes.")
            row("key", "Your key, off by default", "Uses your own Anthropic API key, kept in the Keychain. Only the prompt, a compact model summary and tool results are sent, and only while it's on.")
            Button("Set Up in Settings…") { AISettingsLink.open() }.controlSize(.large).padding(.top, 4)
            Text("Later: Arcus ▸ Settings ▸ AI Assistant, or the card on Home.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(AIStyle.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
