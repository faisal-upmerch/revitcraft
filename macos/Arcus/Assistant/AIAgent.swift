import Foundation
import Observation
import ArcusMCP

// AICORE: the assistant's loop. One prompt: context summary + selection + images + text go to Haiku with the
// document's tools; tool calls run in process through the host (risk-gated, inside one undo step); every step is
// verified (tool errors, the tools' verification blocks, model health); a step that fails verification twice is
// retried alone on Sonnet, then work returns to Haiku; before finishing, drawing tasks are checked. Text streams
// into the chat, tool calls show as live steps, and the cost of each request is recorded against the budget.

/// An image attached to the prompt (pasted or dropped), already sized for the API.
public struct AIImage: Sendable, Hashable {
    public var name: String
    public var mediaType: String
    public var data: Data
    public init(name: String, mediaType: String, data: Data) { self.name = name; self.mediaType = mediaType; self.data = data }

    var block: JSONValue {
        ["type": "image", "source": ["type": "base64", "media_type": .string(mediaType), "data": .string(data.base64EncodedString())]]
    }
}

@MainActor
@Observable
public final class AIAgent {
    /// Requests per prompt before the agent stops and says so.
    public var maxSteps = 24
    /// Tokens (all kinds) per prompt before the agent stops: a guard against runaway loops.
    public var tokenGuard = 1_500_000
    /// Sonnet retries per prompt.
    public var maxEscalations = 3
    /// Rounds of "fix what the final check found" per prompt.
    public var maxFinalChecks = 1
    public var maxTokensPerRequest = 16_000

    public let store: AIChatStore
    @ObservationIgnored public let host: any AIToolHost
    @ObservationIgnored let client: AnthropicClient
    @ObservationIgnored let settings: AISettings

    /// The running prompt, or nil.
    public private(set) var runningTurn: UUID?
    public var isRunning: Bool { runningTurn != nil }
    /// The model of the request in flight (the header shows it).
    public private(set) var activeModel: AIModel?
    /// The API conversation of the current chat (append-only: thinking blocks stay valid).
    @ObservationIgnored public private(set) var messages: [JSONValue] = []
    /// Tool calls of the last assistant message that never got results (a stop or a cut-off reply).
    @ObservationIgnored var unanswered: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    /// The chat whose turns are in `messages` (a reopened or loaded chat starts from a condensed history).
    @ObservationIgnored private var messagesChat: UUID?

    public init(host: any AIToolHost, client: AnthropicClient, settings: AISettings, store: AIChatStore = AIChatStore()) {
        self.host = host; self.client = client; self.settings = settings; self.store = store
    }

    // MARK: Requests

    public var systemBlocks: [String] { [AISystemPrompt.text(kind: host.documentKind, units: host.unitsDescription)] }
    public var tools: [JSONValue] { (host.toolSpecs + [AISystemPrompt.planTool]).map(AISystemPrompt.apiTool) }

    // MARK: Running a prompt

    /// Sends `prompt` (with images and, when `useSelection`, the selection). Returns at once; the reply streams in.
    public func send(_ prompt: String, images: [AIImage] = [], useSelection: Bool = true, allowOverBudget: Bool = false) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !text.isEmpty || !images.isEmpty else { return }
        let selection = useSelection ? host.selection() : []
        var turn = AITurn(prompt: text)
        turn.attachmentNames = images.map(\.name)
        turn.selection = selection
        store.current.turns.append(turn)
        runningTurn = turn.id
        store.changed()
        task = Task { [weak self] in
            await self?.run(turn.id, text, images, selection, allowOverBudget: allowOverBudget)
        }
    }

    /// Runs a prompt to the end (tests await this directly).
    public func sendAndWait(_ prompt: String, images: [AIImage] = [], useSelection: Bool = true, allowOverBudget: Bool = false) async {
        send(prompt, images: images, useSelection: useSelection, allowOverBudget: allowOverBudget)
        await task?.value
    }

    /// The stop button: cancels the request in flight, declines a pending question, keeps what was done (one undo step).
    public func stop() {
        task?.cancel()
        for (_, c) in pending { c.resume(returning: false) }
        pending = [:]
    }

    /// Answers an inline confirmation card.
    public func answer(_ id: String, allow: Bool) {
        guard let turn = runningTurn, let c = pending.removeValue(forKey: id) else { return }
        store.updateConfirmation(turn, id, allow ? .allowed : .declined)
        c.resume(returning: allow)
    }

    /// The reply's Undo button.
    public func undo(_ turnID: UUID) {
        guard !isRunning, let t = store.current.turns.first(where: { $0.id == turnID }) ?? store.earlier.flatMap(\.turns).first(where: { $0.id == turnID }),
              let name = t.undoName, host.undo.canUndo(name) else { return }
        host.undo.undo(name)
        store.update(turnID) { $0.undone = true }
        store.changed()
    }
    public func canUndo(_ turn: AITurn) -> Bool { !isRunning && !turn.undone && turn.undoName.map { host.undo.canUndo($0) } == true }

    /// A new chat: the API conversation starts over (nothing from earlier chats is sent).
    public func newChat() {
        guard !isRunning else { return }
        store.newChat()
        messages = []; unanswered = []; messagesChat = store.current.id
    }

    /// Rebuilds the API history of a chat loaded from the document or reopened from History: plain text turns
    /// (no tool calls or thinking), so nothing replayed can be invalid.
    func syncMessagesWithChat() {
        guard messagesChat != store.current.id else { return }
        messagesChat = store.current.id
        unanswered = []
        messages = []
        for t in store.current.turns where t.status != .running && t.errorKind == nil {
            messages.append(["role": "user", "content": .string(t.prompt.isEmpty ? "(images)" : t.prompt)])
            var reply = t.finalText.isEmpty ? "Done." : t.finalText
            if !t.changes.isEmpty { reply += "\nChanges: " + t.changes.joined(separator: "; ") }
            if t.undone { reply += "\n(The user undid these changes.)" }
            messages.append(["role": "assistant", "content": .string(reply)])
        }
    }

    // MARK: The loop

    private func run(_ turnID: UUID, _ prompt: String, _ images: [AIImage], _ selection: [AISelectionChip], allowOverBudget: Bool) async {
        let started = Date()
        let startCount = host.changeCount
        var overBudgetOK = allowOverBudget
        var editsMade = false
        defer {
            activeModel = nil
            let changed = host.changeCount != startCount
            let name = "AI: " + Self.shortName(prompt)
            if host.undo.isOpen { host.undo.end(name, changed: changed) }
            store.update(turnID) { t in
                t.finished = Date()
                if t.status == .running { t.status = Task.isCancelled ? .stopped : .done }
                if changed {
                    t.undoName = name
                    t.changes = Self.changeLines(t.steps)
                }
            }
            runningTurn = nil
            store.changed()
            _ = started
        }

        do {
            try checkReady()
        } catch {
            fail(turnID, error)
            return
        }
        syncMessagesWithChat()

        // The prompt's user message: context (cached breakpoint), selection, images, text.
        let context = await host.contextSummary()
        let promptStart = messages.count
        let priorUnanswered = unanswered
        var content: [JSONValue] = unanswered.map { Self.toolResult($0, text: "Not run: the reply was interrupted.", error: true) }
        unanswered = []
        let contextBlockIndex = content.count
        content.append(["type": "text", "text": .string("<arcus_context>\n\(context)\n</arcus_context>")])
        if !selection.isEmpty {
            let lines = selection.prefix(50).map { "\($0.id): \($0.category) — \($0.title)" }
            content.append(["type": "text", "text": .string("<selection count=\"\(selection.count)\">\n" + lines.joined(separator: "\n") + "\n</selection>")])
        }
        content += images.map(\.block)
        content.append(["type": "text", "text": .string(prompt.isEmpty ? "Look at the attached image." : prompt)])
        messages.append(["role": "user", "content": .array(content)])
        let contextBreakpoint = (message: messages.count - 1, block: contextBlockIndex)

        let vision = !images.isEmpty || AIIntent.isDrawingTask(prompt)
        var consecutiveFailures = 0
        var escalateNext = false
        var escalations = 0
        var finalChecks = 0
        var tokens = 0

        for _ in 0..<maxSteps {
            if Task.isCancelled { return }
            // Budget: stop and ask.
            if settings.budgetReached && !overBudgetOK {
                let ok = await ask(turnID, AIConfirmation(title: "Monthly budget reached",
                    message: "You've spent \(AIFormat.dollars(settings.spent())) of your \(AIFormat.dollars(settings.monthlyBudget)) monthly AI budget. Continue this prompt anyway? You can raise the budget in Settings ▸ AI.",
                    action: "Continue"))
                if !ok {
                    note(turnID, AINotice(.warning, "Stopped at the monthly budget", "Raise it in Settings ▸ AI to keep going."))
                    store.update(turnID) { $0.status = .stopped; $0.errorKind = AIError.Kind.budget.rawValue }
                    return
                }
                overBudgetOK = true
            }
            let model: AIModel = escalateNext ? .sonnet : .haiku
            activeModel = model
            let request = AIRequest(model: model, maxTokens: maxTokensPerRequest, system: systemBlocks, tools: tools, messages: messages,
                                    contextBreakpoint: contextBreakpoint)
            let response: AIResponseMessage
            do {
                response = try await client.stream(request) { [weak self] d in
                    await MainActor.run { self?.delta(turnID, d) }
                }
            } catch {
                if error.kind == .cancelled {
                    store.update(turnID) { $0.status = .stopped }
                } else {
                    fail(turnID, error)
                    // The failed prompt is taken out of the API conversation (the next prompt's context shows its edits).
                    messages.removeSubrange(promptStart...)
                    unanswered = priorUnanswered
                }
                return
            }
            record(turnID, model: model, usage: response.usage)
            tokens += response.usage.total
            messages.append(["role": "assistant", "content": .array(response.content)])
            let uses = response.toolUses

            switch response.stopReason {
            case "tool_use":
                unanswered = uses.map(\.id)
                let round = await runTools(turnID, uses, model: model, vision: vision)
                editsMade = editsMade || round.edited
                var results = round.results
                if Task.isCancelled {
                    // Keep the conversation valid for the next prompt: the calls not run get error results then.
                    unanswered = uses.map(\.id).filter { id in !results.contains { $0["tool_use_id"]?.stringValue == id } }
                    if !results.isEmpty { messages.append(["role": "user", "content": .array(results)]); }
                    store.update(turnID) { $0.status = .stopped }
                    return
                }
                unanswered = []
                if model == .sonnet {
                    // The retried step is done: back to Haiku.
                    escalateNext = false
                    consecutiveFailures = 0
                } else if round.failed {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 2 && escalations < maxEscalations {
                        escalateNext = true
                        escalations += 1
                        consecutiveFailures = 0
                        results.append(["type": "text", "text": "Arcus: this step failed verification twice. Retry only this step, carefully; then continue."])
                        note(turnID, AINotice(.info, "Retrying the failed step on \(AIModel.sonnet.displayName)", "Then back to \(AIModel.haiku.displayName)."))
                    }
                } else {
                    consecutiveFailures = 0
                }
                messages.append(["role": "user", "content": .array(results)])
            case "max_tokens":
                if !uses.isEmpty { unanswered = uses.map(\.id) }
                note(turnID, AINotice(.warning, "The reply was cut off", "Ask again with a smaller request."))
                return
            case "refusal":
                note(turnID, AINotice(.warning, "Claude declined this request", "Rephrase it, or try a different request."))
                return
            case "pause_turn":
                continue
            default:
                // end_turn: verify before finishing.
                if editsMade && finalChecks < maxFinalChecks, let problems = await finalCheck(turnID, prompt: prompt, vision: vision), !problems.isEmpty {
                    finalChecks += 1
                    let text = "Arcus check before finishing found:\n- " + problems.prefix(8).joined(separator: "\n- ") + "\nFix these, or explain in one line why they are fine."
                    messages.append(["role": "user", "content": .array([["type": "text", "text": .string(text)]])])
                    continue
                }
                return
            }
            if tokens > tokenGuard {
                note(turnID, AINotice(.warning, "Stopped: this prompt used \(AIFormat.tokens(tokens)) tokens", "Split the request into smaller steps."))
                return
            }
        }
        note(turnID, AINotice(.warning, "Stopped after \(maxSteps) steps", "Ask again to continue from here."))
    }

    func checkReady() throws(AIError) {
        guard settings.enabled else { throw AIError(.disabled, "Turn on the AI assistant in Settings ▸ AI.") }
        guard settings.hasKey else { throw AIError(.noKey, "Add your Anthropic API key in Settings ▸ AI.") }
    }

    private func delta(_ turn: UUID, _ d: AIStreamDelta) {
        guard case .text(let t) = d else { return }
        store.appendText(turn, t)
    }

    private func record(_ turn: UUID, model: AIModel, usage: AIUsage) {
        let cost = settings.prices.cost(usage, model: model)
        settings.record(cost)
        store.update(turn) { t in
            if let i = t.usage.firstIndex(where: { $0.model == model }) {
                t.usage[i].usage += usage; t.usage[i].cost += cost; t.usage[i].requests += 1
            } else {
                t.usage.append(AIModelUsage(model: model, usage: usage, cost: cost, requests: 1))
            }
        }
    }

    private func note(_ turn: UUID, _ n: AINotice) { store.update(turn) { $0.items.append(.notice(n)) } }

    private func fail(_ turn: UUID, _ e: AIError) {
        store.update(turn) { t in
            t.status = .failed
            t.errorKind = e.kind.rawValue
            t.items.append(.notice(AINotice(.error, e.title, e.message)))
        }
    }

    /// Shows a confirmation card and waits for the answer (false if stopped).
    private func ask(_ turn: UUID, _ c: AIConfirmation) async -> Bool {
        let id = UUID().uuidString
        store.update(turn) { $0.items.append(.confirmation(AIConfirmationItem(id: id, confirmation: c))) }
        if Task.isCancelled { return false }
        return await withCheckedContinuation { cont in pending[id] = cont }
    }

    // MARK: Tools

    struct Round {
        var results: [JSONValue] = []
        var failed = false
        var edited = false
    }

    private func runTools(_ turn: UUID, _ uses: [(id: String, name: String, input: [String: JSONValue])], model: AIModel, vision: Bool) async -> Round {
        var round = Round()
        let specs = Dictionary(host.toolSpecs.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for u in uses {
            if Task.isCancelled { break }
            if u.name == AISystemPrompt.planTool.name {
                applyPlan(turn, u.input)
                round.results.append(Self.toolResult(u.id, text: "Shown.", error: false))
                continue
            }
            guard let spec = specs[u.name] else {
                round.results.append(Self.toolResult(u.id, text: "Unknown tool \(u.name). Use one of the listed tools.", error: true))
                round.failed = true
                continue
            }
            let risk = host.risk(of: u.name)
            var step = AIToolStep(id: u.id, tool: u.name, title: spec.title, summary: Self.argumentSummary(u.input), status: .running, model: model, edits: risk != .read)
            store.update(turn) { $0.items.append(.step(step)) }
            if let c = AIRiskPolicy.confirmation(tool: u.name, title: spec.title, risk: risk, arguments: u.input, documentName: host.documentName) {
                store.updateStep(turn, u.id) { $0.status = .waiting }
                let ok = await ask(turn, c)
                if !ok {
                    store.updateStep(turn, u.id) { $0.status = .declined; $0.detail = "Not run: you declined." }
                    round.results.append(Self.toolResult(u.id, text: "The user declined this (\(c.title)). Don't retry it; say what wasn't done.", error: true))
                    continue
                }
                store.updateStep(turn, u.id) { $0.status = .running }
            }
            if risk != .read && !host.undo.isOpen { await host.undo.begin() }
            let t0 = Date()
            let r = await host.call(u.name, arguments: u.input)
            let check = Self.verification(r)
            step.status = check.ok ? .ok : .failed
            let images = r.content.filter { $0["type"]?.stringValue == "image" }
            store.updateStep(turn, u.id) { s in
                s.status = check.ok ? .ok : .failed
                s.duration = Date().timeIntervalSince(t0)
                s.detail = String(r.text.prefix(600))
                s.findings = check.findings
                s.imageCount = vision ? images.count : 0
            }
            if !check.ok { round.failed = true }
            if risk != .read && !r.isError { round.edited = true }
            round.results.append(Self.apiToolResult(u.id, r, includeImages: vision))
        }
        return round
    }

    private func applyPlan(_ turn: UUID, _ input: [String: JSONValue]) {
        store.update(turn) { t in
            if let steps = input["steps"]?.arrayValue?.compactMap(\.stringValue), !steps.isEmpty {
                t.plan = steps.prefix(8).enumerated().map { AIPlanStep(id: $0.offset + 1, title: $0.element) }
            }
            for n in input["done"]?.arrayValue?.compactMap(\.intValue) ?? [] {
                if let i = t.plan.firstIndex(where: { $0.id == n }) { t.plan[i].done = true }
            }
            if let f = input["finding"]?.stringValue, !f.isEmpty { t.items.append(.notice(AINotice(.info, f))) }
        }
    }

    /// Whether a tool result passed verification: no error, the tool's `verification.ok` not false, and no error-level
    /// model health warning on the elements it touched.
    static func verification(_ r: ToolResult) -> (ok: Bool, findings: [String]) {
        if r.isError { return (false, [String(r.text.prefix(300))]) }
        guard let json = try? JSONValue.parse(r.text) else { return (true, []) }
        var findings: [String] = []
        var ok = true
        if let v = json["verification"] {
            if v["ok"]?.boolValue == false { ok = false }
            findings += (v["problems"]?.arrayValue ?? []).compactMap { $0.stringValue ?? $0["message"]?.stringValue }
        }
        for w in json["warnings"]?.arrayValue ?? [] {
            if let m = w["message"]?.stringValue {
                findings.append(m)
                if w["severity"]?.stringValue == "error" { ok = false }
            }
        }
        return (ok, Array(findings.prefix(6)))
    }

    /// Before finishing: for drawing tasks, the drawing check; for every prompt, the tool steps that are still failing.
    private func finalCheck(_ turn: UUID, prompt: String, vision: Bool) async -> [String]? {
        var problems: [String] = []
        if AIIntent.isDrawingTask(prompt), host.toolSpecs.contains(where: { $0.name == "verify_drawing" }) {
            let id = "check-" + UUID().uuidString
            store.update(turn) { $0.items.append(.step(AIToolStep(id: id, tool: "verify_drawing", title: "Check Drawing", summary: "Before finishing", status: .running, model: .haiku, edits: false))) }
            let t0 = Date()
            let r = await host.call("verify_drawing", arguments: [:])
            let c = Self.verification(r)
            var found = c.findings
            if let json = try? JSONValue.parse(r.text) {
                found += (json["problems"]?.arrayValue ?? []).compactMap { $0.stringValue ?? $0["message"]?.stringValue }
            }
            let unique = Array(NSOrderedSet(array: found).compactMap { $0 as? String })
            store.updateStep(turn, id) { s in
                s.status = unique.isEmpty && c.ok ? .ok : .failed
                s.duration = Date().timeIntervalSince(t0)
                s.findings = unique
                s.detail = String(r.text.prefix(600))
            }
            problems += unique
            if !c.ok && unique.isEmpty { problems.append(String(r.text.prefix(200))) }
        }
        let steps = store.current.turns.first { $0.id == turn }?.steps ?? []
        // The last call of each tool: failing ones are unfinished work.
        var last: [String: AIToolStep] = [:]
        for s in steps where s.tool != "verify_drawing" { last[s.tool] = s }
        for s in last.values.sorted(by: { $0.started < $1.started }) where s.status == .failed {
            problems.append("\(s.title) still fails: \(s.findings.first ?? s.detail.prefix(160).description)")
        }
        return problems
    }

    // MARK: Helpers

    static func toolResult(_ id: String, text: String, error: Bool) -> JSONValue {
        var o: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(id), "content": .string(text)]
        if error { o["is_error"] = true }
        return .object(o)
    }

    /// An MCP result as a Messages API tool_result: text blocks as they are; images (base64 PNG) only when the prompt
    /// is a drawing check or the user attached images, otherwise a note.
    static func apiToolResult(_ id: String, _ r: ToolResult, includeImages: Bool) -> JSONValue {
        var blocks: [JSONValue] = []
        var skipped = 0
        for c in r.content {
            switch c["type"]?.stringValue {
            case "text":
                blocks.append(["type": "text", "text": .string(c["text"]?.stringValue ?? "")])
            case "image":
                if includeImages, let data = c["data"]?.stringValue {
                    blocks.append(["type": "image", "source": ["type": "base64", "media_type": .string(c["mimeType"]?.stringValue ?? "image/png"), "data": .string(data)]])
                } else {
                    skipped += 1
                }
            default:
                break
            }
        }
        if skipped > 0 { blocks.append(["type": "text", "text": "(Image not sent: Arcus sends view images only when checking drawings.)"]) }
        if blocks.isEmpty { blocks = [["type": "text", "text": r.isError ? "Failed." : "Done."]] }
        var o: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(id), "content": .array(blocks)]
        if r.isError { o["is_error"] = true }
        return .object(o)
    }

    /// "level: Level 1 · 4 points": a short line about a call's arguments.
    static func argumentSummary(_ a: [String: JSONValue]) -> String {
        var parts: [String] = []
        for k in a.keys.sorted() {
            guard let v = a[k] else { continue }
            let key = k.replacingOccurrences(of: "_", with: " ")
            if let arr = v.arrayValue {
                let strings = arr.compactMap(\.stringValue)
                if !strings.isEmpty && strings.count == arr.count && strings.count <= 3 {
                    parts.append("\(key): " + strings.joined(separator: ", "))
                } else {
                    parts.append("\(arr.count) " + (arr.count == 1 && key.hasSuffix("s") ? String(key.dropLast()) : key))
                }
            } else if let s = v.stringValue { parts.append("\(key): \(s.prefix(30))") }
            else if v.objectValue != nil { parts.append(key) } else { parts.append("\(key): \(v.jsonText.prefix(20))") }
            if parts.count == 3 { break }
        }
        return parts.joined(separator: " · ")
    }

    /// One line per editing step that succeeded ("Create Walls: 4 points"), repeated tools merged.
    static func changeLines(_ steps: [AIToolStep]) -> [String] {
        var out: [String] = []
        var counts: [String: Int] = [:]
        for s in steps where s.edits && s.status == .ok { counts[s.title, default: 0] += 1 }
        var seen = Set<String>()
        for s in steps where s.edits && s.status == .ok && !seen.contains(s.title) {
            seen.insert(s.title)
            let n = counts[s.title] ?? 1
            out.append(n > 1 ? "\(s.title) ×\(n)" : (s.summary.isEmpty ? s.title : "\(s.title) (\(s.summary))"))
        }
        return out
    }

    /// The undo step's name: "AI: Add drawers to this cabinet" (shortened).
    static func shortName(_ prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Edit"
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 40 { return trimmed.isEmpty ? "Edit" : trimmed }
        return String(trimmed.prefix(39)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
