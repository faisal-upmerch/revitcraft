import AppKit
import Observation
import ArcusMCP

// MCP: "Design with Claude" (Docs/MCP.md §6): what Home, the Set Up sheet, the bottom bar pill, Help, Manage and
// Settings show about the local Claude connection. Reads Claude's config files to tell whether Arcus is set up; writes
// nothing unless the user asks (Add to Claude Desktop, after a confirmation).

@MainActor
@Observable
final class ClaudeIntegration {
    static let shared = ClaudeIntegration()

    /// Status shown on Home, in the Set Up sheet and on the pill.
    enum Status: Equatable {
        case notSetUp, ready, connected, editing

        var title: String {
            switch self {
            case .notSetUp: "Not set up"
            case .ready: "Ready"
            case .connected: "Claude connected"
            case .editing: "Claude is editing…"
            }
        }
        var symbol: String {
            switch self {
            case .notSetUp: "circle.dashed"
            case .ready: "checkmark.circle"
            case .connected: "dot.radiowaves.left.and.right"
            case .editing: "ellipsis.circle"
            }
        }
        var tint: NSColor {
            switch self {
            case .notSetUp: .secondaryLabelColor
            case .ready: .systemGreen
            case .connected: .systemGreen
            case .editing: .controlAccentColor
            }
        }
    }

    /// One tool call Claude made in the app (live mode).
    struct Action: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var document: String
        var date: Date
        var ok: Bool
        var detail: String
        /// Whether it changed the document (and so has an Undo step).
        var edits: Bool
    }

    // MARK: State

    /// Claude Desktop's and Claude Code's configs, re-read by `refresh()`.
    private(set) var desktop: ClaudeClientConfig.Status = .clientMissing
    private(set) var code: ClaudeClientConfig.Status = .clientMissing
    /// Live mode: the setting and whether the socket is listening.
    private(set) var liveEnabled = false
    private(set) var listening = false
    private(set) var listenError: String?
    /// Tool calls in progress and the most recent ones (newest first, up to 20).
    private(set) var busyTool: String?
    private(set) var actions: [Action] = []
    /// QA and offscreen renders: shows this status instead of the real one.
    var previewStatus: Status?

    private init() { refresh() }

    /// Document windows show the bottom bar pill while live mode listens (or a QA preview is set).
    var showsPill: Bool { listening || previewStatus != nil }

    var isSetUp: Bool {
        if case .configured = desktop { return true }
        if case .configured = code { return true }
        return false
    }

    var status: Status {
        if let previewStatus { return previewStatus }
        if busyTool != nil { return .editing }
        if let last = actions.first, Date().timeIntervalSince(last.date) < 15 * 60 { return .connected }
        return isSetUp ? .ready : .notSetUp
    }

    /// Re-reads the Claude configs and the live setting.
    func refresh() {
        desktop = ClaudeClientConfig.desktopStatus()
        code = ClaudeClientConfig.codeStatus()
        liveEnabled = UserDefaults.standard.bool(forKey: MCPLiveService.defaultsKey)
        listening = MCPLiveService.shared.isRunning
        listenError = MCPLiveService.shared.lastError
    }

    // MARK: The server binary

    /// The bundled server: this app's Contents/Helpers/arcus-mcp, else the installed app's.
    var serverPath: String {
        let own = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/arcus-mcp").path
        if FileManager.default.isExecutableFile(atPath: own) { return own }
        let installed = "/Applications/Arcus.app/Contents/Helpers/arcus-mcp"
        if FileManager.default.isExecutableFile(atPath: installed) { return installed }
        return Bundle.main.bundleURL.pathExtension == "app" ? own : installed
    }
    var serverInstalled: Bool { FileManager.default.isExecutableFile(atPath: serverPath) }
    var desktopSnippet: String { ClaudeClientConfig.desktopSnippet(serverPath: serverPath) }
    var codeCommand: String { ClaudeClientConfig.codeCommand(serverPath: serverPath) }

    // MARK: Actions

    func setLive(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: MCPLiveService.defaultsKey)
        MCPLiveService.shared.setEnabled(on)
        refresh()
    }

    /// Adds Arcus to Claude Desktop (call after the user confirms). Returns a sentence for the sheet.
    func addToClaudeDesktop() -> (ok: Bool, message: String) {
        do {
            let backup = try ClaudeClientConfig.installDesktop(serverPath: serverPath)
            refresh()
            let saved = backup.map { " The previous file was saved as \($0.lastPathComponent)." } ?? ""
            return (true, "Added. Quit and reopen Claude Desktop, then look for Arcus under its tools.\(saved)")
        } catch {
            return (false, error.description)
        }
    }

    /// Starts the server once and, with live mode on, asks the app's socket for hello. Runs off the main thread.
    func testConnection() async -> (ok: Bool, message: String) {
        let path = serverPath, live = liveEnabled
        let probe = await Task.detached { ClaudeClientConfig.probe(serverPath: path) }.value
        var lines: [String] = []
        var ok = true
        switch probe {
        case .success(let n): lines.append("The Arcus server works: \(n) tools.")
        case .failure(let f): lines.append(f.description); ok = false
        }
        if live {
            let reachable = await Task.detached { LiveSocket.isReachable() }.value
            lines.append(reachable ? "Live mode is listening: Claude's changes appear in your open document." : "Live mode is on but not listening. Turn it off and on again.")
            ok = ok && reachable
        } else {
            lines.append("Live mode is off: Claude works on files and saves them.")
        }
        if !isSetUp { lines.append("Claude isn't set up yet: add Arcus to Claude Desktop or Claude Code above.") }
        refresh()
        return (ok, lines.joined(separator: " "))
    }

    // MARK: Recording (MCPLiveService)

    func begin(_ tool: String) { busyTool = tool }

    func finish(_ tool: String, document: String, result: ToolResult) {
        busyTool = nil
        let spec = ArcusToolCatalog.all.first { $0.name == tool }
        let detail = result.isError ? result.text : ""
        actions.insert(Action(title: spec?.title ?? tool, document: document, date: Date(), ok: !result.isError, detail: detail,
                              edits: spec.map { !$0.readOnly } ?? false), at: 0)
        if actions.count > 20 { actions.removeLast(actions.count - 20) }
    }

    func clearActions() { actions = [] }
}

/// Example prompts shown in the Set Up sheet and onboarding.
enum ClaudePrompts {
    struct Prompt: Identifiable, Hashable {
        var id: String { text }
        var symbol: String
        var title: String
        var text: String
    }

    static let all: [Prompt] = [
        Prompt(symbol: "house", title: "A house",
               text: "In Arcus, design a one-storey two-bedroom cottage, about 36' x 28', with a gable roof, open living and kitchen, and a bath between the bedrooms. Add doors, windows, named rooms and a floor plan sheet, then save it in Documents/Arcus."),
        Prompt(symbol: "books.vertical", title: "A piece of furniture",
               text: "In Arcus, make a bookcase 36\" wide, 12\" deep and 72\" tall with four adjustable shelves, a plinth and a back, and render a 3D view."),
        Prompt(symbol: "table.furniture", title: "A table",
               text: "In Arcus, design a 60\" x 36\" dining table with a butcher-block top, tapered legs at the corners and a rounded front edge."),
        Prompt(symbol: "pencil.and.ruler", title: "Edit the open model",
               text: "In the open Arcus project, add a 22' x 22' garage on the east side with an overhead door, then place its room and update the plan dimensions."),
        Prompt(symbol: "checklist", title: "Check the model",
               text: "Check the open Arcus project: list every room with its area and any warnings, and fix rooms that aren't enclosed."),
    ]
}
