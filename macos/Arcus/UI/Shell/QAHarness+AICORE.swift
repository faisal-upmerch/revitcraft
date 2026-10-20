import AppKit
import SwiftUI
import ArcusDomain
import ArcusAssistant

// AICORE: screenshots of the AI assistant (hooked from `screenshots()` with one line, per appearance): the AI button in
// the controls pill, the sidebar empty, a conversation (plan, steps, a Sonnet retry, changes with Undo, cost lines), a
// confirmation card, and Settings ▸ AI Assistant. Preview settings only (in-memory key, never the user's), no network.
extension QAHarness {
    static func aicoreScreenshots(_ suffix: String) async {
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "AI Cottage")
        let doc = ArcusDocument(model: model, displayName: "AI Cottage")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        guard let s = doc.state, let w = s.window else { doc.close(); return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        let d = UserDefaults(suiteName: "arcus.ai.qa") ?? .standard
        let settings = AISettings(defaults: d, keys: MemoryKeyStore("sk-ant-api03-qa-preview-0000"))
        settings.enabled = true
        settings.explainedWhatIsSent = true
        settings.monthlyBudget = 10
        let panel = AIAssistantPanel.installPreview(s, settings: settings)
        await pause(400)
        await shot(w, "aicore-button-\(suffix)")

        AIAssistantPanel.toggle(in: s)
        await pause(700)
        await shot(w, "aicore-sidebar-empty-\(suffix)")

        panel.agent.store.current.turns = [qaDoneTurn(), qaEscalatedTurn()]
        await pause(700)
        await shot(w, "aicore-sidebar-conversation-\(suffix)")

        panel.agent.store.current.turns = [qaConfirmTurn()]
        await pause(700)
        await shot(w, "aicore-sidebar-confirmation-\(suffix)")

        s.workspace = .macSpacious
        s.onWorkspaceChange?()
        await pause(700)
        await shot(w, "aicore-sidebar-mac-spacious-\(suffix)")
        s.workspace = .bimFamiliar
        s.onWorkspaceChange?()

        AppDelegate.shared?.showSettings()
        await pause(500)
        NotificationCenter.default.post(name: AISettingsLink.notification, object: nil)
        await pause(700)
        if let sw = NSApp.windows.first(where: { $0.title == "Arcus Settings" }) {
            await shot(sw, "aicore-settings-\(suffix)")
            sw.close()
        }
        AIAssistantPanel.forget(s)
        doc.updateChangeCount(.changeCleared)
        doc.close()
        UserDefaults.standard.removePersistentDomain(forName: "arcus.ai.qa")
        await pause(400)
    }

    static func qaDoneTurn() -> AITurn {
        var t = AITurn(prompt: "Dimension this plan and tag the doors", started: Date().addingTimeInterval(-40))
        t.plan = [AIPlanStep(id: 1, title: "Read the plan", done: true), AIPlanStep(id: 2, title: "Add dimensions", done: true), AIPlanStep(id: 3, title: "Tag doors", done: true)]
        var a = AIToolStep(id: "1", tool: "add_dimensions", title: "Add Dimensions", summary: "auto: true · view: Level 1", status: .ok, model: .haiku, edits: true); a.duration = 0.8
        var b = AIToolStep(id: "2", tool: "add_tags", title: "Add Tags", summary: "categories: doors · view: Level 1", status: .ok, model: .haiku, edits: true); b.duration = 0.3
        t.items = [.step(a), .step(b), .text("Added **14 dimensions** and tagged the 5 doors on Level 1.")]
        t.status = .done
        t.changes = ["Add Dimensions (auto: true · view: Level 1)", "Add Tags (categories: doors · view: Level 1)"]
        t.undoName = "AI: Dimension this plan and tag the doors"
        t.usage = [AIModelUsage(model: .haiku, usage: AIUsage(input: 1840, cacheWrite: 6200, cacheRead: 21_400, output: 920), cost: 0.0031, requests: 4)]
        return t
    }

    static func qaEscalatedTurn() -> AITurn {
        var t = AITurn(prompt: "Add a 12' x 14' bedroom off the hall with a door and a window")
        var a = AIToolStep(id: "a", tool: "create_walls", title: "Create Walls", summary: "level: Level 1 · 3 points", status: .failed, model: .haiku, edits: true)
        a.findings = ["Wall 812 overlaps wall 714."]
        var b = a; b.id = "b"
        let c = AIToolStep(id: "c", tool: "create_walls", title: "Create Walls", summary: "level: Level 1 · 3 points", status: .ok, model: .sonnet, edits: true)
        t.items = [.step(a), .step(b), .notice(AINotice(.info, "Retrying the failed step on Sonnet 5.5", "Then back to Haiku 5.5.")), .step(c),
                   .text("Added the bedroom (168 SF) with a 36\" door and a casement window.")]
        t.status = .done
        t.changes = ["Create Walls (level: Level 1 · 3 points)"]
        t.undoName = "AI: Add a bedroom"
        t.usage = [AIModelUsage(model: .haiku, usage: AIUsage(input: 2100, cacheWrite: 5800, cacheRead: 30_000, output: 1100), cost: 0.0035, requests: 4),
                   AIModelUsage(model: .sonnet, usage: AIUsage(input: 900, cacheWrite: 31_000, output: 400), cost: 0.0835, requests: 1)]
        return t
    }

    static func qaConfirmTurn() -> AITurn {
        var t = AITurn(prompt: "Prepare a PDF of all sheets")
        let s = AIToolStep(id: "p", tool: "export_pdf", title: "Export PDF", summary: "path: ~/Documents/Arcus/AI Cottage.pdf", status: .waiting, model: .haiku, edits: true)
        t.items = [.text("All sheets are ready."), .step(s),
                   .confirmation(AIConfirmationItem(id: "c1", confirmation: AIConfirmation(title: "Export PDF?", message: "Writes ~/Documents/Arcus/AI Cottage.pdf. An existing file there is replaced.", action: "Export")))]
        t.status = .running
        return t
    }
}
