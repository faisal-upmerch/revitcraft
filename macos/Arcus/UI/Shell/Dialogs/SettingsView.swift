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
            Section("Claude (MCP)") { MCPSettingsSection() } // MCP: Docs/MCP.md
            Section("Privacy") {
                Text("Arcus makes no network connections, collects no analytics and requires no special permissions. Diagnostics stay on this Mac unless you export them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") { Text(LocalOnlyUpdateProvider().statusMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 560)
    }
}


/// MCP: lets Claude (Claude Desktop, Claude Code) build in the open document through arcus-mcp. Off by default.
struct MCPSettingsSection: View {
    @AppStorage(MCPLiveService.defaultsKey) private var enabled = false
    @State private var status = ""
    var body: some View {
        Toggle("Allow Claude to edit open documents", isOn: $enabled)
            .onChange(of: enabled) { _, v in MCPLiveService.shared.setEnabled(v); refresh() }
        Text("Claude's Arcus tools (arcus-mcp) then work in the front document: every change is one Undo step. Only your Mac account can connect; nothing goes over the network.")
            .font(.caption).foregroundStyle(.secondary)
        if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        HStack {
            Button("Copy Claude Code Command") { copy("claude mcp add arcus -- \"\(MCPLiveService.shared.helperPath)\"") }
            Button("Copy Claude Desktop Setup") {
                copy("{ \"mcpServers\": { \"arcus\": { \"command\": \"\(MCPLiveService.shared.helperPath)\" } } }")
            }
        }
        .onAppear(perform: refresh)
    }
    func refresh() {
        let s = MCPLiveService.shared
        status = s.lastError.map { "Not listening: \($0)" } ?? (s.isRunning ? "Listening on \(s.socketPath)" : "")
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
