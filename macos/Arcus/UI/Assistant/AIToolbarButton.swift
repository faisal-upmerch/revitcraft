import AppKit
import SwiftUI
import ArcusApplication
import ArcusAssistant

// AICORE: the AI button at the right of every document window's controls pill (⇧⌘A): sparkles in the assistant's
// tint, a tinted capsule while the sidebar is open, a small dot while a reply is running.

struct AIToolbarButton: View {
    @Bindable var panel: AIAssistantPanel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AIStyle.tint)
                    .symbolEffect(.pulse, isActive: panel.agent.isRunning)
                Text("AI").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, PillSpec.padding)
            .frame(height: PillSpec.shellItemHeight)
            .pillHighlight(panel.isShown, .tint(AIStyle.tint)) // PILLS: 28 pt capsule, tinted while open
        }
        .buttonStyle(RibbonPressStyle())
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .help(panel.isShown ? "Hide the AI assistant (⇧⌘A)" : "AI assistant: describe a change and Arcus makes it (⇧⌘A)")
        .accessibilityLabel("AI Assistant")
        .accessibilityValue(panel.isShown ? "Open" : "Closed")
    }
}

extension AIAssistantPanel {
    /// Opens or closes the sidebar in a project or Furniture window: the trailing dock shows it (Components close).
    static func toggle(in state: DocumentState) {
        let p = of(state)
        p.toggle()
        if p.isShown {
            ComponentPanelModel.of(state).isShown = false
            if state.docks.prefs.trailingCollapsed { state.docks.setCollapsed(false, .trailing) }
            if state.docks.prefs.width(.trailing) < minWidth { state.docks.setWidth(preferredWidth, .trailing); state.docks.save() }
        }
        state.onWorkspaceChange?()
        state.toolChangedState()
    }

    /// The sidebar is open in this window (without creating the panel).
    static func isShown(_ state: DocumentState) -> Bool { existing(state)?.isShown == true }
    static func existing(_ state: DocumentState) -> AIAssistantPanel? { existingPanel(ObjectIdentifier(state)) }
    static func existing(family model: FamilyEditorModel) -> AIAssistantPanel? { existingPanel(ObjectIdentifier(model)) }

    static let minWidth = 320.0
    static let preferredWidth = 360.0
}

extension AIAssistantPanel {
    /// Opens or closes the sidebar in a Family Editor window.
    static func toggle(family model: FamilyEditorModel) {
        let p = of(family: model)
        p.toggle()
        let docks = model.chrome.docks
        if p.isShown, docks.prefs.width(.trailing) < minWidth { docks.setWidth(preferredWidth, .trailing); docks.save() }
    }
}

/// The Family Editor's right dock: Properties, the AI assistant, or both (Properties above).
struct FamilyTrailingDock: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let ai = AIAssistantPanel.existing(family: model)
        let properties = model.chrome.propertiesShown
        Group {
            if let ai, ai.isShown {
                let sidebar = AISidebarView(panel: ai) { AIAssistantPanel.toggle(family: model) }
                if properties {
                    PersistentVSplit(key: "familyEditor.assistantFraction", defaultFraction: 0.35, minTop: 160, minBottom: 360) {
                        FamilyInspectorView(model: model)
                    } bottom: { sidebar }
                } else {
                    sidebar
                }
            } else {
                FamilyInspectorView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
