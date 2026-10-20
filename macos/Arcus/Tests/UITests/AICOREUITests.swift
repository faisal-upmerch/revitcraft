import AppKit
import SwiftUI
import Testing
import ArcusDomain
import ArcusApplication
import ArcusMCP
import ArcusAssistant
@testable import ArcusUI

// AICORE: the AI assistant's UI rendered offscreen, light and dark, to /tmp/arcus-aicore/ for review: the sidebar's
// states (set-up, empty, conversation, confirmation, error), the controls pill with the AI button, Settings ▸ AI
// Assistant, the Home card and the onboarding step. No network: the chats are seeded.

@MainActor
@Suite("AI assistant UI", .serialized)
struct AICOREUITests {
    static let outDir = URL(fileURLWithPath: "/tmp/arcus-aicore", isDirectory: true)

    static func write(_ view: NSView, _ name: String) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appending(path: "\(name).png"))
    }

    static func render<V: View>(_ view: V, size: CGSize, _ name: String, dark: Bool, background: Color = Color(nsColor: .windowBackgroundColor)) {
        _ = NSApplication.shared
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(background))
        h.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        h.frame = NSRect(origin: .zero, size: size)
        h.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        h.layoutSubtreeIfNeeded()
        write(h, "\(name)-\(dark ? "dark" : "light")")
    }

    static func settings(enabled: Bool = true, key: Bool = true, explained: Bool = true) -> AISettings {
        let d = UserDefaults(suiteName: "arcus.ai.ui.\(UUID().uuidString)")!
        let s = AISettings(defaults: d, keys: MemoryKeyStore(key ? "sk-ant-api03-preview-0000-abcd" : nil))
        s.enabled = enabled
        s.explainedWhatIsSent = explained
        s.monthlyBudget = 10
        s.record(0.43)
        return s
    }

    static func panel(_ s: AISettings, furniture: Bool = false) -> (AIAssistantPanel, DocumentState) {
        let model = furniture ? FurnitureTemplates.blank(name: "Sideboard") : ProjectTemplates.make(.architectural, units: .imperial, projectName: "Cottage").0
        let state = DocumentState(session: DocumentSession(model: model))
        let toolbox = ArcusToolbox(host: AIWindowDocumentHost(state: state))
        let host = ToolboxAIHost(toolbox: toolbox, selection: {
            [AISelectionChip(id: 714, title: "Generic - 8\"", category: "Walls"), AISelectionChip(id: 715, title: "Generic - 8\"", category: "Walls")]
        })
        return (AIAssistantPanel(host: host, settings: s), state)
    }

    /// A finished prompt with a plan, steps, text, changes and cost.
    static func doneTurn() -> AITurn {
        var t = AITurn(prompt: "Dimension this plan and tag the doors", started: Date().addingTimeInterval(-40))
        t.plan = [AIPlanStep(id: 1, title: "Read the plan", done: true), AIPlanStep(id: 2, title: "Add dimensions", done: true), AIPlanStep(id: 3, title: "Tag doors", done: true)]
        let now = Date()
        var s1 = AIToolStep(id: "1", tool: "query_model", title: "Query Model", summary: "what: walls", status: .ok, model: .haiku, started: now, edits: false); s1.duration = 0.2
        var s2 = AIToolStep(id: "2", tool: "add_dimensions", title: "Add Dimensions", summary: "auto: true · view: Level 1", status: .ok, model: .haiku, started: now, edits: true); s2.duration = 0.8
        var s3 = AIToolStep(id: "3", tool: "add_tags", title: "Add Tags", summary: "1 categories · view: Level 1", status: .ok, model: .haiku, started: now, edits: true); s3.duration = 0.3
        s3.findings = ["5 doors tagged"]
        t.items = [.step(s1), .step(s2), .step(s3), .text("Added **14 dimensions** (overall and wall chains on all four sides) and tagged the 5 doors on Level 1.\n- Plan: Level 1\n- Health: no new warnings")]
        t.status = .done
        t.changes = ["Add Dimensions (auto: true · view: Level 1)", "Add Tags (1 categories · view: Level 1)"]
        t.undoName = "AI: Dimension this plan and tag the doors"
        t.usage = [AIModelUsage(model: .haiku, usage: AIUsage(input: 1840, cacheWrite: 6200, cacheRead: 21_400, output: 920), cost: 0.0031, requests: 4)]
        t.finished = Date()
        return t
    }

    static func escalatedTurn() -> AITurn {
        var t = AITurn(prompt: "Add a 12' x 14' bedroom off the hall with a door and a window")
        let now = Date()
        var a = AIToolStep(id: "a", tool: "create_walls", title: "Create Walls", summary: "level: Level 1 · 3 points", status: .failed, model: .haiku, started: now, edits: true)
        a.findings = ["Wall 812 overlaps wall 714."]; a.duration = 0.4
        var b = a; b.id = "b"
        var c = AIToolStep(id: "c", tool: "create_walls", title: "Create Walls", summary: "level: Level 1 · 3 points", status: .ok, model: .sonnet, started: now, edits: true); c.duration = 0.5
        var d = AIToolStep(id: "d", tool: "place_doors", title: "Place Doors", summary: "1 doors", status: .ok, model: .haiku, started: now, edits: true); d.duration = 0.3
        t.items = [.step(a), .step(b), .notice(AINotice(.info, "Retrying the failed step on Sonnet 5.5", "Then back to Haiku 5.5.")), .step(c), .step(d),
                   .text("Added the bedroom (168 SF) with a 36\" door from the hall and a 36\" casement window.")]
        t.status = .done
        t.changes = ["Create Walls (level: Level 1 · 3 points)", "Place Doors (1 doors)"]
        t.undoName = "AI: Add a bedroom"
        t.usage = [AIModelUsage(model: .haiku, usage: AIUsage(input: 2100, cacheWrite: 5800, cacheRead: 30_000, output: 1100), cost: 0.0035, requests: 4),
                   AIModelUsage(model: .sonnet, usage: AIUsage(input: 900, cacheWrite: 31_000, cacheRead: 0, output: 400), cost: 0.0835, requests: 1)]
        return t
    }

    static func confirmTurn() -> AITurn {
        var t = AITurn(prompt: "Prepare a PDF of all sheets")
        var s = AIToolStep(id: "p", tool: "export_pdf", title: "Export PDF", summary: "path: ~/Documents/Arcus/Cottage.pdf", status: .waiting, model: .haiku, edits: true)
        s.duration = 0
        t.plan = [AIPlanStep(id: 1, title: "Check the sheets", done: true), AIPlanStep(id: 2, title: "Export the PDF")]
        t.items = [.text("All 4 sheets are ready."), .step(s),
                   .confirmation(AIConfirmationItem(id: "c1", confirmation: AIConfirmation(title: "Export PDF?", message: "Writes ~/Documents/Arcus/Cottage.pdf. An existing file there is replaced.", action: "Export")))]
        t.status = .running
        t.started = Date().addingTimeInterval(-12)
        return t
    }

    static func errorTurn() -> AITurn {
        var t = AITurn(prompt: "Add legs at the corners")
        t.items = [.notice(AINotice(.error, "You're offline", "Connect to the internet to use the AI assistant. Everything else in Arcus works offline."))]
        t.status = .failed
        t.errorKind = "offline"
        return t
    }

    @Test func rendersSidebarStates() {
        let size = CGSize(width: 360, height: 760)
        for dark in [false, true] {
            let (empty, _) = Self.panel(Self.settings())
            Self.render(AISidebarView(panel: empty, onClose: {}), size: size, "sidebar-empty", dark: dark)
            let (furniture, _) = Self.panel(Self.settings(), furniture: true)
            Self.render(AISidebarView(panel: furniture, onClose: {}), size: size, "sidebar-empty-furniture", dark: dark)
            Self.render(AISidebarView(panel: Self.panel(Self.settings(enabled: false)).0, onClose: {}), size: size, "sidebar-off", dark: dark)
            Self.render(AISidebarView(panel: Self.panel(Self.settings(key: false)).0, onClose: {}), size: size, "sidebar-no-key", dark: dark)
            Self.render(AISidebarView(panel: Self.panel(Self.settings(explained: false)).0, onClose: {}), size: size, "sidebar-what-is-sent", dark: dark)

            let (conv, _) = Self.panel(Self.settings())
            conv.agent.store.current.turns = [Self.doneTurn(), Self.escalatedTurn()]
            Self.render(AISidebarView(panel: conv, onClose: {}), size: CGSize(width: 360, height: 1300), "sidebar-conversation", dark: dark)

            let (confirm, _) = Self.panel(Self.settings())
            confirm.agent.store.current.turns = [Self.confirmTurn()]
            confirm.draft = "Then email it to the client"
            Self.render(AISidebarView(panel: confirm, onClose: {}), size: size, "sidebar-confirmation", dark: dark)

            let (err, _) = Self.panel(Self.settings())
            err.agent.store.current.turns = [Self.doneTurn(), Self.errorTurn()]
            Self.render(AISidebarView(panel: err, onClose: {}), size: CGSize(width: 360, height: 900), "sidebar-error", dark: dark)

            let s = Self.settings(); s.monthlyBudget = 0.25
            let (budget, _) = Self.panel(s)
            budget.agent.store.current.turns = [Self.doneTurn()]
            Self.render(AISidebarView(panel: budget, onClose: {}), size: CGSize(width: 360, height: 900), "sidebar-budget", dark: dark)

            let (hist, _) = Self.panel(Self.settings())
            hist.agent.store.current.turns = [Self.doneTurn()]
            var older = AIChat(); older.turns = [Self.escalatedTurn()]
            hist.agent.store.earlier = [older]
            hist.showingHistory = true
            Self.render(AISidebarView(panel: hist, onClose: {}), size: CGSize(width: 360, height: 500), "sidebar-history", dark: dark)
        }
        #expect(FileManager.default.fileExists(atPath: Self.outDir.appending(path: "sidebar-empty-light.png").path))
    }

    @Test func rendersButtonSettingsHomeAndOnboarding() {
        for dark in [false, true] {
            let (p, state) = Self.panel(Self.settings())
            Self.render(HStack { AIToolbarButton(panel: p) {} }.padding(PillSpec.inset).modifier(GlassPill(role: .controls)).padding(20),
                        size: CGSize(width: 140, height: 76), "button-closed", dark: dark)
            p.isShown = true
            Self.render(HStack { AIToolbarButton(panel: p) {} }.padding(PillSpec.inset).modifier(GlassPill(role: .controls)).padding(20),
                        size: CGSize(width: 140, height: 76), "button-open", dark: dark)
            _ = state
            let s = Self.settings()
            Self.render(Form { Section("AI Assistant") { AISettingsSection(settings: s) } }.formStyle(.grouped), size: CGSize(width: 540, height: 640), "settings-ai", dark: dark)
            let noKey = Self.settings(key: false)
            Self.render(Form { Section("AI Assistant") { AISettingsSection(settings: noKey) } }.formStyle(.grouped), size: CGSize(width: 540, height: 600), "settings-ai-no-key", dark: dark)
            Self.render(AIPriceTableEditor(settings: s).padding(16), size: CGSize(width: 540, height: 180), "settings-prices", dark: dark)
            Self.render(HomeAssistantCard(settings: s).padding(16), size: CGSize(width: 300, height: 130), "home-card", dark: dark)
            Self.render(OnboardingView(onFinish: {}, step: 3), size: CGSize(width: 720, height: 520), "onboarding-ai", dark: dark)
        }
    }

    @Test func commandAndSuggestions() {
        let info = CommandCatalog.info(.aiAssistant)
        #expect(info.shortcut == "⇧⌘A" && info.symbol == "sparkles")
        for q in ["ai", "assistant", "chat"] {
            #expect(CommandCatalog.search(q, aliases: [:], recent: [], available: { _ in true }).contains { $0.id == .aiAssistant }, "search “\(q)”")
        }
        #expect(AISuggestions.prompts(.project, selection: 0).contains { $0.text == "Dimension this plan" })
        #expect(AISuggestions.prompts(.project, selection: 0).contains { $0.text == "Prepare a PDF of all sheets" })
        #expect(AISuggestions.prompts(.furniture, selection: 0).contains { $0.text == "Add drawers to this cabinet" })
        #expect(AISuggestions.prompts(.project, selection: 0).contains { $0.text == "Fix overlapping dimensions" })
    }
}
