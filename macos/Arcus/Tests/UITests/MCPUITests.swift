import AppKit
import SwiftUI
import Testing
import ArcusDomain
import ArcusApplication
import ArcusMCP
@testable import ArcusUI

// MCP: Design with Claude in the UI (Docs/MCP.md §6): Home's card, the Set Up sheet, the bottom bar pill and its
// activity popover, the onboarding step, rendered offscreen (light and dark) to /tmp/arcus-mcp-ui/ for review; and
// where the feature is reachable (Help, Manage ▸ Add-Ins, command search).

@MainActor
@Suite("Design with Claude UI", .serialized)
struct MCPUITests {
    static let outDir = URL(fileURLWithPath: "/tmp/arcus-mcp-ui", isDirectory: true)

    static func write(_ view: NSView, _ name: String) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appending(path: "\(name).png"))
    }

    static func renderHome(_ card: HomeCard?, _ name: String, dark: Bool) {
        _ = NSApplication.shared
        let m = HomeModel(tab: .recent, readsDisk: false)
        m.selected = card
        let w = AppDelegate.makeHubWindow(model: m)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setContentSize(CGSize(width: 1040, height: 660))
        w.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        w.contentView?.layoutSubtreeIfNeeded()
        w.displayIfNeeded()
        if let v = w.contentView?.superview ?? w.contentView { write(v, "\(name)-\(dark ? "dark" : "light")") }
        w.close()
    }

    static func render<V: View>(_ view: V, size: CGSize, _ name: String, dark: Bool) {
        _ = NSApplication.shared
        let h = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        h.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        h.frame = NSRect(origin: .zero, size: size)
        h.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        h.layoutSubtreeIfNeeded()
        write(h, "\(name)-\(dark ? "dark" : "light")")
    }

    @Test func rendersHomeSetupPillAndOnboarding() {
        let claude = ClaudeIntegration.shared
        let session = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial, projectName: "Pill").0)
        let state = DocumentState(session: session)
        for dark in [false, true] {
            claude.previewStatus = .notSetUp
            Self.renderHome(nil, "home-claude-not-set-up", dark: dark)
            claude.previewStatus = .ready
            Self.renderHome(nil, "home-claude-ready", dark: dark)
            Self.renderHome(.furniture, "home-furniture-hint", dark: dark)
            claude.previewStatus = .notSetUp
            Self.render(ClaudeSetupView(), size: CGSize(width: 620, height: 720), "setup-sheet", dark: dark)
            // The whole sheet, scrolled content laid out flat, to review the lower steps and prompts.
            Self.render(ClaudeSetupView(height: 1180), size: CGSize(width: 620, height: 1180), "setup-sheet-full", dark: dark)
            for (status, name) in [(ClaudeIntegration.Status.ready, "ready"), (.connected, "connected"), (.editing, "editing")] {
                claude.previewStatus = status
                Self.render(BottomBarView(state: state).modifier(GlassCapsule()).padding(12), size: CGSize(width: 1180, height: 60), "pill-\(name)", dark: dark)
            }
            claude.previewStatus = .connected
            if claude.actions.isEmpty {
                claude.finish("create_walls", document: "MCP Demo", result: .text("{}"))
                claude.finish("place_doors", document: "MCP Demo", result: .text("{}"))
                claude.finish("place_windows", document: "MCP Demo", result: .error("windows[2]: offset 40' is outside wall 714 (length 36' - 0\")."))
                claude.finish("place_rooms", document: "MCP Demo", result: .text("{}"))
            }
            Self.render(ClaudeActivityView(session: session), size: CGSize(width: 340, height: 300), "activity-popover", dark: dark)
            Self.render(OnboardingView(onFinish: {}, step: 2), size: CGSize(width: 720, height: 520), "onboarding-claude", dark: dark)
        }
        claude.previewStatus = nil
        claude.clearActions()
        #expect(FileManager.default.fileExists(atPath: Self.outDir.appending(path: "setup-sheet-light.png").path))
    }

    @Test func featureIsReachableEverywhere() {
        let info = CommandCatalog.info(.designWithClaude)
        #expect(info.title == "Design with Claude…")
        for q in ["claude", "mcp", "ai", "design with"] {
            #expect(CommandCatalog.search(q, aliases: [:], recent: [], available: { _ in true }).contains { $0.id == .designWithClaude }, "search “\(q)”")
        }
        for mode in [DocumentKind.project, .furniture] {
            let manage = RibbonContent.panels(.manage, mode: mode)
            #expect(manage.contains { $0.title == "Add-Ins" && $0.items.contains { $0.id == .designWithClaude } }, "Manage ▸ Add-Ins in \(mode)")
        }
        let help = MainMenuBuilder.build().items.first { $0.title == "Help" }?.submenu
        #expect(help?.items.contains { ($0.representedObject as? String) == CommandID.designWithClaude.rawValue } == true)
        #expect(OnboardingView.steps == 4)
    }

    @Test func statusFollowsActivity() {
        let c = ClaudeIntegration.shared
        c.previewStatus = nil
        c.clearActions()
        c.begin("create_walls")
        #expect(c.status == .editing)
        c.finish("create_walls", document: "Doc", result: .text("{}"))
        #expect(c.status == .connected)
        #expect(c.actions.first?.title == "Create Walls" && c.actions.first?.edits == true)
        c.finish("query_model", document: "Doc", result: .text("{}"))
        #expect(c.actions.first?.edits == false)
        c.clearActions()
        #expect(c.status == (c.isSetUp ? .ready : .notSetUp))
        #expect(c.desktopSnippet.contains("arcus-mcp") && c.codeCommand.hasPrefix("claude mcp add"))
    }
}
