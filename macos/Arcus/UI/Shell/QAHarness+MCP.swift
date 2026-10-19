import AppKit
import SwiftUI
import ArcusDomain

// MCP: screenshots of Design with Claude (hooked from `screenshots()` with one line, per appearance): Home with the card,
// the Set Up window, and a project window's bottom bar with the Claude pill (a preview status: QA never opens the
// live socket).
extension QAHarness {
    static func mcpScreenshots(_ suffix: String) async {
        let claude = ClaudeIntegration.shared
        let hub = AppDelegate.makeHubWindow(model: HomeModel(tab: .recent))
        hub.title = "Home (QA)"
        hub.center()
        hub.orderFront(nil)
        await pause(1200)
        await shot(hub, "mcp-home-\(suffix)")
        hub.close()
        ClaudeSetupWindow.show()
        await pause(900)
        if let w = NSApp.windows.first(where: { $0.title == "Design with Claude" }) {
            await shot(w, "mcp-setup-\(suffix)")
            w.close()
        }
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Claude Pill")
        let doc = ArcusDocument(model: model, displayName: "Claude Pill")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        if let w = doc.state?.window {
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            for status in [ClaudeIntegration.Status.connected, .editing] {
                claude.previewStatus = status
                await pause(600)
                await shot(w, "mcp-pill-\(status == .editing ? "editing" : "connected")-\(suffix)")
            }
        }
        claude.previewStatus = nil
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(400)
    }
}
