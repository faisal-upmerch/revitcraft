import SwiftUI
import AppKit
import ArcusDomain
import ArcusCalc
import ArcusApplication
import ArcusPersistence
import ArcusServices

struct SettingsView: View {
    @AppStorage("snapRadius") private var snapRadius = 10.0
    @AppStorage("workspace") private var workspace = Workspace.bimFamiliar.rawValue
    @AppStorage("selection.modifiers") private var modifiers = SelectionModel.ModifierStyle.bim.rawValue
    @AppStorage("ribbon.stayOnModify") private var stayOnModify = false
    @AppStorage("navigationBar.visible") private var navigationBar = true
    var body: some View {
        ScrollViewReader { proxy in // AICORE: the assistant's settings link scrolls to its section
        Form {
            Section("New projects") { // HOME: Architectural projects start in Imperial
                Text("New architectural projects and furniture start in Imperial (feet and inches). Change a project's units in Manage ▸ Project Units.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Workspace") {
                Picker("Layout", selection: $workspace) { ForEach(Workspace.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
                Text("BIM Familiar puts Properties above the Project Browser on the left; Mac Spacious puts Properties in a right inspector.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Selection") {
                Picker("Click modifiers", selection: $modifiers) {
                    Text("BIM: ⌘ adds, ⇧ removes").tag(SelectionModel.ModifierStyle.bim.rawValue)
                    Text("Mac: ⇧ adds, ⌘ toggles").tag(SelectionModel.ModifierStyle.mac.rawValue)
                }
                .onChange(of: modifiers) { _, v in SelectionModel.modifierStyle = SelectionModel.ModifierStyle(rawValue: v) ?? .bim }
                Text("Applies to clicks and window selections in every view.").font(.caption).foregroundStyle(.secondary)
            }
            Section("User Interface") {
                Toggle("Stay on the Modify tab after a tool ends or the selection clears", isOn: $stayOnModify)
                Toggle("Show the navigation bar on views", isOn: $navigationBar)
            }
            Section("3D Navigation") { NavigationSettingsSection() } // BL-SITE
            Section("Drawing") {
                Slider(value: $snapRadius, in: 4...24, step: 1) { Text("Snap distance: \(Int(snapRadius)) pt") }
                    .onChange(of: snapRadius) { _, _ in for d in NSDocumentController.shared.documents { (d as? ArcusDocument)?.state.reloadSnapRadius() } }
            }
            CanvasSettingsSections() // BL-CANVAS: Colors, temporary dimensions, tooltips, double-click
            Section("Notifications") { SaveReminderSettingsSection() } // F11
            Section("DWG") { DWGEngineSettingsSection(); DWGConverterSettingsSection() } // W2-DWG; DWG: bundled engines and the last file read
            Section("AI Assistant") { AISettingsSection() }.id("ai") // AICORE: the in-app assistant (opt-in, the one network exception)
            Section("Claude (MCP)") { MCPSettingsSection() } // MCP: Docs/MCP.md
            Section("Privacy") {
                Text("Arcus makes no network connections, collects no analytics and requires no special permissions. The one exception is the AI assistant, only while you turn it on above: it then talks to Anthropic with your key. Diagnostics stay on this Mac unless you export them.").font(.caption).foregroundStyle(.secondary) // AICORE
            }
            Section("Updates") { Text(LocalOnlyUpdateProvider().statusMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: AISettingsLink.notification)) { _ in withAnimation { proxy.scrollTo("ai", anchor: .top) } } // AICORE
        }
        .frame(width: 540, height: 560)
    }
}


/// MCP: Design with Claude: live editing and the setup sheet. Off by default.
struct MCPSettingsSection: View {
    @State private var claude = ClaudeIntegration.shared
    var body: some View {
        Toggle("Allow Claude to edit open documents", isOn: Binding(get: { claude.liveEnabled }, set: { claude.setLive($0) }))
        Text("Claude's Arcus tools then work in the front document: every change is one Undo step. Only your Mac account can connect; nothing goes over the network.")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            ClaudeStatusBadge(status: claude.status, compact: true)
            if let e = claude.listenError, claude.liveEnabled { Text("Not listening: \(e)").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Design with Claude…") { ClaudeSetupWindow.show() }
        }
        .onAppear { claude.refresh() }
    }
}
