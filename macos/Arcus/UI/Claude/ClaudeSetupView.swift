import SwiftUI
import AppKit
import ArcusMCP

// MCP: the Design with Claude sheet (Home ▸ Set Up…, Help ▸ Design with Claude…, Manage ▸ Claude, Settings): what it
// is, connecting Claude Desktop or Claude Code, live editing, a connection test and prompts to try.

/// The feature's mark: a sparkle on a warm gradient disc.
struct ClaudeMark: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.89, green: 0.53, blue: 0.36), Color(red: 0.78, green: 0.36, blue: 0.27)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "sparkles").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Status capsule: Not set up / Ready / Claude connected / Claude is editing…
struct ClaudeStatusBadge: View {
    let status: ClaudeIntegration.Status
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            if status == .editing { ProgressView().controlSize(.mini) } else {
                Image(systemName: status.symbol).font(.system(size: compact ? 9 : 10, weight: .semibold))
            }
            Text(status.title).font(.system(size: compact ? 10 : 11, weight: .medium)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(Color(nsColor: status.tint))
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 18 : 20)
        .background(Capsule().fill(Color(nsColor: status.tint).opacity(status == .notSetUp ? 0.10 : 0.14)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude: \(status.title)")
    }
}

struct ClaudeSetupView: View {
    var onDone: () -> Void = {}
    /// The sheet's height (offscreen reviews render it taller to see every section).
    var height: CGFloat = 720
    @State private var claude = ClaudeIntegration.shared
    @State private var client = Client.desktop
    @State private var confirmAdd = false
    @State private var addResult: (ok: Bool, message: String)?
    @State private var testResult: (ok: Bool, message: String)?
    @State private var testing = false
    @State private var copied: String?

    enum Client: String, CaseIterable, Identifiable { case desktop = "Claude Desktop", code = "Claude Code"; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    privacy
                    step(1, "Connect Claude") { connect }
                    step(2, "Edit open documents") { live }
                    step(3, "Test") { test }
                    prompts
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            Divider()
            HStack {
                Text(claude.serverInstalled ? "Server: \(claude.serverPath)" : "This copy of Arcus doesn't include its Claude server. Install the latest Arcus to connect Claude.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction).controlSize(.large)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 620, height: height)
        .onAppear { claude.refresh() }
        .alert("Add Arcus to Claude Desktop?", isPresented: $confirmAdd) {
            Button("Add") { addResult = claude.addToClaudeDesktop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Arcus backs up claude_desktop_config.json, then adds an “arcus” server to it. Your other servers and settings stay as they are.")
        }
    }

    // MARK: Sections

    var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ClaudeMark(size: 52)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Design with Claude").font(.system(size: 22, weight: .semibold))
                    ClaudeStatusBadge(status: claude.status)
                }
                Text("Describe a building or a piece of furniture and Claude builds it in Arcus: walls, doors, rooms, roofs, parts, sheets. You see every change and can undo it.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var privacy: some View {
        Label {
            Text("Runs on this Mac. Arcus itself never goes online: Claude talks to it through the Claude app you use, and only what you send Claude leaves your Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.cardCornerRadius, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    func step<C: View>(_ n: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content().padding(.leading, 28)
        }
    }

    var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            PillSegmented(selection: $client, Client.allCases.map { ($0, $0.rawValue) }, label: "Claude app") // PILLS
            switch client {
            case .desktop:
                clientStatus(claude.desktop, app: "Claude Desktop")
                HStack(spacing: 8) {
                    Button("Add to Claude Desktop…") { confirmAdd = true }.buttonStyle(.borderedProminent)
                    copyButton("Copy Configuration", claude.desktopSnippet)
                }
                if let r = addResult { result(r) }
                code(claude.desktopSnippet)
                Text("Or paste the configuration into Claude ▸ Settings ▸ Developer ▸ Edit Config, then restart Claude Desktop.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .code:
                clientStatus(claude.code, app: "Claude Code")
                code(claude.codeCommand)
                HStack(spacing: 8) { copyButton("Copy Command", claude.codeCommand) }
                Text("Run it in Terminal once. In Claude Code, /mcp then lists the Arcus tools.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    func clientStatus(_ s: ClaudeClientConfig.Status, app: String) -> some View {
        let (symbol, color, text): (String, Color, String) = switch s {
        case .configured(let path) where path == claude.serverPath: ("checkmark.circle.fill", .green, "\(app) is set up for Arcus.")
        case .configured: ("exclamationmark.circle.fill", .orange, "\(app) points at another copy of Arcus. Add it again to use this one.")
        case .notConfigured: ("circle", .secondary, "\(app) isn't set up for Arcus yet.")
        case .clientMissing: ("questionmark.circle", .secondary, "\(app) wasn't found on this Mac. Install it from claude.ai/download, or copy the setup below.")
        case .unreadable: ("exclamationmark.triangle.fill", .orange, "\(app)'s configuration can't be read. Copy the setup and add it by hand.")
        }
        return Label { Text(text).font(.system(size: 12)) } icon: { Image(systemName: symbol).foregroundStyle(color) }
    }

    var live: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Allow Claude to edit open documents", isOn: Binding(get: { claude.liveEnabled }, set: { claude.setLive($0) }))
                .toggleStyle(.switch)
            Text(claude.liveEnabled
                 ? (claude.listening ? "On: Claude works in the front document. Each change is one Undo step; the pill at the bottom of the window shows what Claude did."
                                     : "On, but not listening: \(claude.listenError ?? "try turning it off and on").")
                 : "Off: Claude creates and edits files and saves them; open them in Arcus to look. Only your Mac account can connect either way.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var test: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(testing ? "Testing…" : "Test Connection") {
                    testing = true
                    Task { testResult = await claude.testConnection(); testing = false }
                }
                .disabled(testing)
                if testing { ProgressView().controlSize(.small) }
            }
            if let r = testResult { result(r) }
        }
    }

    var prompts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking Claude").font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            ForEach(ClaudePrompts.all) { p in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: p.symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.system(size: 12, weight: .semibold))
                        Text(p.text).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    copyButton("Copy", p.text, small: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Tokens.cardCornerRadius, style: .continuous).fill(Color.primary.opacity(0.035)))
            }
        }
    }

    // MARK: Pieces

    func code(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    func copyButton(_ title: String, _ text: String, small: Bool = false) -> some View {
        Button(copied == text ? "Copied" : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
            Task { try? await Task.sleep(for: .seconds(1.5)); if copied == text { copied = nil } }
        }
        .controlSize(small ? .small : .regular)
        .help("Copy to the clipboard")
    }

    func result(_ r: (ok: Bool, message: String)) -> some View {
        Label { Text(r.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(r.ok ? .green : .orange)
        }
    }
}

/// The Design with Claude window (Help, Manage ▸ Claude, Settings, command search; Home shows it as a sheet).
@MainActor
enum ClaudeSetupWindow {
    private static var window: NSWindow?

    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 720), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Design with Claude"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: ClaudeSetupView(onDone: { [weak w] in w?.close() }))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window = nil }
        }
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
