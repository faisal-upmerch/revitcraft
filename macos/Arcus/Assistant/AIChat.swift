import Foundation
import Observation

// AICORE: the chat as the sidebar shows it and the document saves it (optional, Docs/FileFormat.md
// `assistant/history.json`). Attached images aren't saved, only their names; the API key never appears here.

/// A plan step the model set with update_plan.
public struct AIPlanStep: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var done = false
    public init(id: Int, title: String, done: Bool = false) { self.id = id; self.title = title; self.done = done }
}

/// One tool call as a collapsible step in the reply.
public struct AIToolStep: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable { case running, ok, failed, declined, waiting }
    public var id: String
    public var tool: String
    public var title: String
    /// A short line about the arguments ("3 walls on Level 1").
    public var summary: String
    public var status: Status
    /// The result, shortened (shown when the step is expanded).
    public var detail = ""
    public var findings: [String] = []
    public var model: AIModel
    public var started: Date
    public var duration: Double = 0
    public var edits: Bool
    public var imageCount = 0

    public init(id: String, tool: String, title: String, summary: String, status: Status, model: AIModel, started: Date = Date(), edits: Bool) {
        self.id = id; self.tool = tool; self.title = title; self.summary = summary; self.status = status; self.model = model
        self.started = started; self.edits = edits
    }
}

/// A question the reply is waiting on (an inline card with two buttons).
public struct AIConfirmationItem: Codable, Sendable, Hashable, Identifiable {
    public enum Decision: String, Codable, Sendable { case pending, allowed, declined }
    public var id: String
    public var confirmation: AIConfirmation
    public var decision: Decision = .pending
    public init(id: String, confirmation: AIConfirmation) { self.id = id; self.confirmation = confirmation }
}

/// A line from Arcus inside a reply (retrying on Sonnet, a verification result, a stop).
public struct AINotice: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case info, success, warning, error }
    public var kind: Kind
    public var title: String
    public var message: String
    public init(_ kind: Kind, _ title: String, _ message: String = "") { self.kind = kind; self.title = title; self.message = message }
}

public enum AIReplyItem: Codable, Sendable, Hashable {
    case text(String)
    case step(AIToolStep)
    case confirmation(AIConfirmationItem)
    case notice(AINotice)
}

/// Usage of one model within a reply.
public struct AIModelUsage: Codable, Sendable, Hashable {
    public var model: AIModel
    public var usage: AIUsage
    public var cost: Double
    public var requests: Int
    public init(model: AIModel, usage: AIUsage, cost: Double, requests: Int) {
        self.model = model; self.usage = usage; self.cost = cost; self.requests = requests
    }
}

/// One prompt and its reply.
public struct AITurn: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable { case running, done, stopped, failed }
    public var id: UUID
    public var prompt: String
    public var attachmentNames: [String] = []
    public var selection: [AISelectionChip] = []
    public var items: [AIReplyItem] = []
    public var plan: [AIPlanStep] = []
    public var status: Status = .running
    /// What changed (one line per editing step), shown with the Undo button.
    public var changes: [String] = []
    /// The undo action name of the prompt's step, when it changed the document.
    public var undoName: String?
    public var undone = false
    public var usage: [AIModelUsage] = []
    public var started: Date
    public var finished: Date?
    public var errorKind: String?

    public init(id: UUID = UUID(), prompt: String, started: Date = Date()) { self.id = id; self.prompt = prompt; self.started = started }

    public var cost: Double { usage.reduce(0) { $0 + $1.cost } }
    public var totalUsage: AIUsage { usage.reduce(AIUsage()) { $0 + $1.usage } }
    /// The reply's final text (the last text item).
    public var finalText: String {
        for i in items.reversed() { if case .text(let t) = i, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t } }
        return ""
    }
    public var steps: [AIToolStep] { items.compactMap { if case .step(let s) = $0 { s } else { nil } } }

    /// "Haiku 5.5 · 12.4K tokens (9.8K cached) · $0.0021", with Sonnet when a step was retried on it.
    public var costLine: String {
        guard !usage.isEmpty else { return "" }
        let models = usage.map { u in u.model == .sonnet ? "\(u.model.displayName) (\(u.requests) step\(u.requests == 1 ? "" : "s"))" : u.model.displayName }
        let t = totalUsage
        var s = models.joined(separator: " + ") + " · " + AIFormat.tokens(t.total) + " tokens"
        if t.cacheRead > 0 { s += " (\(AIFormat.tokens(t.cacheRead)) cached)" }
        return s + " · " + AIFormat.dollars(cost)
    }
}

/// A whole chat.
public struct AIChat: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var created = Date()
    public var turns: [AITurn] = []
    public init() {}

    public var cost: Double { turns.reduce(0) { $0 + $1.cost } }
    public var title: String {
        guard let p = turns.first?.prompt, !p.isEmpty else { return turns.isEmpty ? "New Chat" : "Images" }
        guard p.count > 60 else { return p }
        let cut = p.prefix(60)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}

/// The chats saved in a document (`assistant/history.json`).
public struct AIHistory: Codable, Sendable, Hashable {
    public static let formatVersion = 1
    public var version = AIHistory.formatVersion
    public var chats: [AIChat] = []
    public init(chats: [AIChat] = []) { self.chats = chats }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> AIHistory {
        try JSONDecoder().decode(AIHistory.self, from: data)
    }
}

/// One window's chats: the current chat (whose API messages are live in the agent) and earlier saved ones.
@MainActor
@Observable
public final class AIChatStore {
    public var current = AIChat()
    /// Earlier chats of this document, newest first (shown under History; never sent).
    public var earlier: [AIChat] = []
    /// Bumped whenever something worth saving changes (the document marks itself edited).
    public private(set) var revision = 0
    /// Called after every saved-worthy change.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init() {}

    public var history: AIHistory {
        AIHistory(chats: ([current] + earlier).filter { !$0.turns.isEmpty })
    }

    public func load(_ h: AIHistory) {
        let chats = h.chats.sorted { ($0.turns.last?.started ?? $0.created) > ($1.turns.last?.started ?? $1.created) }
        current = chats.first ?? AIChat()
        // A reply that was running when the document was saved can't resume.
        for i in current.turns.indices where current.turns[i].status == .running { current.turns[i].status = .stopped }
        earlier = Array(chats.dropFirst())
    }

    /// Starts a new chat; the old one moves to History.
    public func newChat() {
        if !current.turns.isEmpty { earlier.insert(current, at: 0) }
        current = AIChat()
        changed()
    }

    public func reopen(_ id: UUID) {
        guard let i = earlier.firstIndex(where: { $0.id == id }) else { return }
        let c = earlier.remove(at: i)
        if !current.turns.isEmpty { earlier.insert(current, at: 0) }
        current = c
        changed()
    }

    public func clearAll() {
        current = AIChat()
        earlier = []
        changed()
    }

    public func changed() {
        revision += 1
        onChange?()
    }

    // MARK: Editing the running turn

    func index(_ turn: UUID) -> Int? { current.turns.firstIndex { $0.id == turn } }

    public func update(_ turn: UUID, _ change: (inout AITurn) -> Void) {
        guard let i = index(turn) else { return }
        change(&current.turns[i])
    }

    public func appendText(_ turn: UUID, _ t: String) {
        update(turn) { tr in
            if case .text(let s)? = tr.items.last { tr.items[tr.items.count - 1] = .text(s + t) } else { tr.items.append(.text(t)) }
        }
    }

    public func updateStep(_ turn: UUID, _ id: String, _ change: (inout AIToolStep) -> Void) {
        update(turn) { tr in
            for k in tr.items.indices.reversed() {
                if case .step(var s) = tr.items[k], s.id == id { change(&s); tr.items[k] = .step(s); return }
            }
        }
    }

    public func updateConfirmation(_ turn: UUID, _ id: String, _ d: AIConfirmationItem.Decision) {
        update(turn) { tr in
            for k in tr.items.indices.reversed() {
                if case .confirmation(var c) = tr.items[k], c.id == id { c.decision = d; tr.items[k] = .confirmation(c); return }
            }
        }
    }
}
