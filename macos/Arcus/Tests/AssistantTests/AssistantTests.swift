import Foundation
import Testing
import ArcusDomain
import ArcusApplication
import ArcusMCP
@testable import ArcusAssistant

// AICORE: the in-app assistant without the network: request building (tools, caching, images), SSE parsing, retries,
// the tool loop with risk confirmations, escalation after two failed verifications, the budget stop, one undo step per
// prompt, and the key staying out of everything that is written.

@MainActor
@Suite("AI assistant", .serialized)
struct AssistantTests {
    // MARK: Fixtures

    func project() async -> (FileDocumentHost, ArcusToolbox, ToolboxAIHost) {
        let host = FileDocumentHost()
        let toolbox = ArcusToolbox(host: host)
        _ = await toolbox.callTool("create_project", arguments: ["name": "AI Test"])
        return (host, toolbox, ToolboxAIHost(toolbox: toolbox, selection: { [AISelectionChip(id: 7, title: "Basic Wall: Generic - 8\"", category: "Walls")] }))
    }

    func waitFor(_ cond: () -> Bool) async {
        for _ in 0..<500 { if cond() { return }; try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    static let walls: JSONValue = ["level": "Level 1", "points": [[0, 0], [20, 0], [20, 15], [0, 15]], "closed": true]

    // MARK: Request building

    @Test func requestUsesFourCacheBreakpointsToolsAndImages() async throws {
        let s = readySettings()
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply("Done.")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        await agent.sendAndWait("What is this?", images: [AIImage(name: "sketch.png", mediaType: "image/png", data: png)])

        let req = try #require(t.requests.first)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-0123456789abcdef")
        let body = try #require(t.bodies.first)
        #expect(body["model"]?.stringValue == "claude-haiku-5-5")
        #expect(body["stream"]?.boolValue == true)
        #expect(body["output_config"]?["effort"]?.stringValue == "medium")
        #expect(body["cache_control"]?["type"]?.stringValue == "ephemeral", "top-level automatic caching")
        let tools = try #require(body["tools"]?.arrayValue)
        #expect(tools.last?["cache_control"] != nil, "breakpoint on the last tool")
        #expect(tools.dropLast().allSatisfy { $0["cache_control"] == nil })
        #expect(tools.contains { $0["name"]?.stringValue == "update_plan" })
        for hidden in ["create_project", "open_document", "undo", "redo", "add_furniture_parts"] {
            #expect(!tools.contains { $0["name"]?.stringValue == hidden }, "\(hidden) is not offered in a project")
        }
        #expect(tools.allSatisfy { $0["input_schema"]?["type"]?.stringValue == "object" })
        let system = try #require(body["system"]?.arrayValue)
        #expect(system.last?["cache_control"] != nil, "breakpoint on the system prompt")
        #expect(system.first?["text"]?.stringValue?.contains("feet") == true, "units in the system prompt")
        let user = try #require(body["messages"]?.arrayValue?.first?["content"]?.arrayValue)
        #expect(user[0]["text"]?.stringValue?.hasPrefix("<arcus_context>") == true)
        #expect(user[0]["cache_control"] != nil, "breakpoint on the context summary")
        #expect(user[1]["text"]?.stringValue?.contains("<selection count=\"1\">") == true)
        #expect(user[2]["type"]?.stringValue == "image")
        #expect(user[2]["source"]?["type"]?.stringValue == "base64" && user[2]["source"]?["data"]?.stringValue == png.base64EncodedString())
        #expect(user.last?["text"]?.stringValue == "What is this?")
        #expect(Self.breakpoints(body) == 4)
    }

    static func breakpoints(_ body: JSONValue) -> Int {
        var n = body["cache_control"] == nil ? 0 : 1
        n += (body["tools"]?.arrayValue ?? []).filter { $0["cache_control"] != nil }.count
        n += (body["system"]?.arrayValue ?? []).filter { $0["cache_control"] != nil }.count
        for m in body["messages"]?.arrayValue ?? [] { n += (m["content"]?.arrayValue ?? []).filter { $0["cache_control"] != nil }.count }
        return n
    }

    @Test func laterPromptsMoveTheContextBreakpointAndKeepThePrefix() async throws {
        let s = readySettings()
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply("One."), SSE.reply("Two.")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        await agent.sendAndWait("First", useSelection: false)
        await agent.sendAndWait("Second", useSelection: false)
        let bodies = t.bodies
        #expect(bodies.count == 2)
        #expect(Self.breakpoints(bodies[1]) == 4, "never more than four breakpoints")
        let m1 = try #require(bodies[0]["messages"]?.arrayValue)
        let m2 = try #require(bodies[1]["messages"]?.arrayValue)
        #expect(m2.count == 3)
        #expect(m2[2]["content"]?.arrayValue?.first?["cache_control"] != nil, "the breakpoint is on the new prompt's context")
        // Append-only: the first request's messages are a prefix of the second's (cache markers aside).
        #expect(AIRequest.strippingCacheControl(m1[0]) == AIRequest.strippingCacheControl(m2[0]))
        #expect(bodies[0]["system"] == bodies[1]["system"] && bodies[0]["tools"] == bodies[1]["tools"], "system and tools byte-identical")
    }

    @Test func noRequestWithoutTheSwitchOrAKey() async {
        let s = readySettings()
        s.enabled = false
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply("x")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        await agent.sendAndWait("Hello")
        #expect(t.requests.isEmpty)
        #expect(agent.store.current.turns.last?.errorKind == AIError.Kind.disabled.rawValue)
        s.enabled = true
        s.removeKey()
        await agent.sendAndWait("Hello")
        #expect(t.requests.isEmpty)
        #expect(agent.store.current.turns.last?.errorKind == AIError.Kind.noKey.rawValue)
        let r = await (await client(t, s)).test()
        if case .failure(let e) = r { #expect(e.kind == .noKey) } else { Issue.record("test() must fail without a key") }
    }

    // MARK: SSE

    @Test func parsesStreamsWithThinkingToolsAndUsage() throws {
        var lines = SSE.start(input: 50, cacheRead: 3000, cacheWrite: 200) + SSE.thinking(0) + SSE.text(1, ["Hel", "lo"])
        lines += SSE.tool(2, id: "toolu_1", name: "create_walls", input: Self.walls) + SSE.end("tool_use", output: 321)
        var p = SSEParser()
        var acc = AIStreamAccumulator()
        var text = ""
        for l in lines.map({ $0 + "\r" }) { // CRLF line ends too
            if let e = p.feed(l), let d = try acc.apply(e), case .text(let t) = d { text += t }
        }
        let m = acc.result()
        #expect(acc.finished)
        #expect(text == "Hello" && m.text == "Hello")
        #expect(m.stopReason == "tool_use")
        #expect(m.usage == AIUsage(input: 50, cacheWrite: 200, cacheRead: 3000, output: 321))
        #expect(m.content.count == 3)
        #expect(m.content[0]["signature"]?.stringValue == "sig-abc", "thinking blocks keep their signature")
        let use = try #require(m.toolUses.first)
        #expect(use.id == "toolu_1" && use.name == "create_walls" && JSONValue.object(use.input) == Self.walls)
        // A comment line and an error event.
        var p2 = SSEParser()
        #expect(p2.feed(": keep-alive") == nil)
        _ = p2.feed("event: error")
        _ = p2.feed("data: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}")
        let ended = p2.feed("")
        let e = try #require(ended)
        var acc2 = AIStreamAccumulator()
        #expect(throws: AIError.self) { _ = try acc2.apply(e) }
    }

    @Test func retriesRateLimitsAndMapsErrors() async throws {
        let s = readySettings()
        let t = MockTransport([MockTransport.Canned(status: 429, headers: ["retry-after": "2"], lines: ["{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"slow down\"}}"]),
                               MockTransport.Canned(status: 529, lines: ["{}"]),
                               SSE.reply("ok")])
        let c = await client(t, s)
        let r = try await c.stream(AIRequest(model: .haiku, system: ["s"], tools: [], messages: [["role": "user", "content": "hi"]]))
        #expect(r.text == "ok")
        #expect(t.requests.count == 3)
        let bad = MockTransport([MockTransport.Canned(status: 401, lines: ["{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"])])
        do {
            _ = try await (await client(bad, s)).stream(AIRequest(model: .haiku, system: ["s"], tools: [], messages: [["role": "user", "content": "hi"]]))
            Issue.record("401 must throw")
        } catch {
            #expect(error.kind == .invalidKey && !error.retryable)
        }
        #expect(bad.requests.count == 1, "no retry for a bad key")
        #expect(AIError.transport(URLError(.notConnectedToInternet)).kind == .offline)
    }

    // MARK: The loop

    @Test func toolLoopEditsLiveInOneUndoStep() async throws {
        let s = readySettings()
        let (fileHost, _, host) = await project()
        let t = MockTransport([
            SSE.reply("Adding walls.", tools: [("t1", "update_plan", ["steps": ["Walls", "Floor"]]), ("t2", "create_walls", Self.walls)]),
            SSE.reply(nil, tools: [("t3", "create_floor", ["level": "Level 1", "from_walls": true]), ("t4", "update_plan", ["done": [1, 2]])]),
            SSE.reply("Added 4 walls and a floor."),
        ])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        await agent.sendAndWait("Make a 20 x 15 room with a floor")
        let session = try #require(fileHost.session)
        #expect(session.model.elements(.walls).count == 4)
        #expect(session.model.elements(.floors).count == 1)
        let turn = try #require(agent.store.current.turns.last)
        #expect(turn.status == .done)
        #expect(turn.plan.map(\.title) == ["Walls", "Floor"] && turn.plan.allSatisfy(\.done))
        #expect(turn.steps.map(\.tool) == ["create_walls", "create_floor"])
        #expect(turn.steps.allSatisfy { $0.status == .ok })
        #expect(turn.finalText == "Added 4 walls and a floor.")
        #expect(turn.changes.count == 2)
        #expect(turn.undoName == "AI: Make a 20 x 15 room with a floor")
        #expect(turn.usage.first?.model == .haiku && turn.usage.first?.requests == 3)
        #expect(turn.cost > 0 && s.spent() > 0)
        #expect(turn.costLine.hasPrefix("Haiku 5.5 ·"))
        // Tool results went back in one user message per round, matched to their calls.
        let third = try #require(t.bodies.last?["messages"]?.arrayValue)
        let results = third[2]["content"]?.arrayValue ?? []
        #expect(results.map { $0["tool_use_id"]?.stringValue } == ["t1", "t2"])
        // One undo step for the whole prompt.
        #expect(session.undoManager.undoActionName == "AI: Make a 20 x 15 room with a floor")
        #expect(agent.canUndo(turn))
        agent.undo(turn.id)
        #expect(session.model.elements(.walls).isEmpty && session.model.elements(.floors).isEmpty, "one ⌘Z removes the walls and the floor")
        #expect(agent.store.current.turns.last?.undone == true)
    }

    @Test func asksBeforeLargeDeletesAndFiles() async throws {
        let s = readySettings()
        let (fileHost, toolbox, host) = await project()
        _ = await toolbox.callTool("create_walls", arguments: ["segments": .array((0..<8).map { i in [[.int(i * 10), 0], [.int(i * 10 + 5), 0]] })])
        let ids: [JSONValue] = (fileHost.session?.model.elements(.walls) ?? []).map { .int(Int($0.id.raw)) }
        #expect(ids.count == 8)
        let t = MockTransport([
            SSE.reply(nil, tools: [("d1", "delete_elements", ["elements": .array(ids)])]),
            SSE.reply(nil, tools: [("s1", "save", ["path": "/tmp/ai-test.arcus"])]),
            SSE.reply("Kept the walls."),
        ])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        agent.send("Delete all walls and save")
        await waitFor { agent.store.current.turns.last?.items.contains { if case .confirmation(let c) = $0 { c.decision == .pending } else { false } } == true }
        let card = try #require(agent.store.current.turns.last?.items.compactMap { if case .confirmation(let c) = $0 { c } else { nil } }.first)
        #expect(card.confirmation.title == "Delete 8 elements?")
        #expect(fileHost.session?.model.elements(.walls).count == 8, "nothing deleted before the answer")
        agent.answer(card.id, allow: false)
        await waitFor { (agent.store.current.turns.last?.items.filter { if case .confirmation = $0 { true } else { false } }.count ?? 0) == 2 }
        let save = try #require(agent.store.current.turns.last?.items.compactMap { if case .confirmation(let c) = $0, c.decision == .pending { c } else { nil } }.first)
        #expect(save.confirmation.action == "Save")
        agent.answer(save.id, allow: false)
        await waitFor { !agent.isRunning }
        #expect(fileHost.session?.model.elements(.walls).count == 8)
        let turn = try #require(agent.store.current.turns.last)
        #expect(turn.steps.map(\.status) == [.declined, .declined])
        #expect(turn.undoName == nil, "nothing changed: no undo step")
        let sent = t.bodies[1]["messages"]?.arrayValue?.last?["content"]?.arrayValue?.first
        #expect(sent?["is_error"]?.boolValue == true && sent?["content"]?.stringValue?.contains("declined") == true)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/ai-test.arcus"))
        // A small delete runs without asking.
        #expect(AIRiskPolicy.confirmation(tool: "delete_elements", title: "Delete Elements", risk: .destructive, arguments: ["elements": [1, 2]], documentName: "X") == nil)
        #expect(AIRiskPolicy.confirmation(tool: "set_project_info", title: "Set Project Information", risk: .projectWide, arguments: ["name": "X"], documentName: "X") != nil)
    }

    @Test func retriesAStepOnSonnetAfterTwoFailedVerifications() async throws {
        let s = readySettings()
        let (fileHost, _, host) = await project()
        let bad: JSONValue = ["level": "Level 1", "points": [[0, 0]]] // one point: the tool refuses
        let t = MockTransport([
            SSE.reply(nil, tools: [("a", "create_walls", bad)]),
            SSE.reply(nil, tools: [("b", "create_walls", bad)]),
            SSE.reply(nil, tools: [("c", "create_walls", Self.walls)], model: "claude-sonnet-5-5"),
            SSE.reply("Fixed: 4 walls."),
        ])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        await agent.sendAndWait("Walls around 20 x 15")
        #expect(t.models == ["claude-haiku-5-5", "claude-haiku-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"], "Haiku, Haiku, Sonnet for the step, back to Haiku")
        #expect(fileHost.session?.model.elements(.walls).count == 4)
        let turn = try #require(agent.store.current.turns.last)
        #expect(turn.steps.map(\.status) == [.failed, .failed, .ok])
        #expect(turn.steps[2].model == .sonnet)
        #expect(Set(turn.usage.map(\.model)) == [.haiku, .sonnet])
        #expect(turn.costLine.contains("Sonnet 5.5 (1 step)"))
        // The system prompt and tools did not change when the model did (thinking blocks stay valid).
        #expect(t.bodies[1]["system"] == t.bodies[2]["system"] && t.bodies[1]["tools"] == t.bodies[2]["tools"])
        let note = t.bodies[2]["messages"]?.arrayValue?.last?["content"]?.arrayValue?.last?["text"]?.stringValue
        #expect(note?.contains("failed verification twice") == true)
    }

    @Test func verificationBlocksDecideFailure() {
        let ok = AIAgent.verification(.text("{\"health\":0,\"verification\":{\"ok\":true,\"problems\":[]}}"))
        #expect(ok.ok && ok.findings.isEmpty)
        let bad = AIAgent.verification(.text("{\"health\":2,\"verification\":{\"ok\":false,\"problems\":[\"Dimension 12 overlaps tag D1\"]}}"))
        #expect(!bad.ok && bad.findings == ["Dimension 12 overlaps tag D1"])
        let warn = AIAgent.verification(.text("{\"warnings\":[{\"severity\":\"error\",\"message\":\"Room is not enclosed\",\"elements\":[3]}]}"))
        #expect(!warn.ok && warn.findings == ["Room is not enclosed"])
        #expect(!AIAgent.verification(.error("No wall type matches")).ok)
    }

    @Test func stopsAndAsksAtTheMonthlyBudget() async throws {
        let s = readySettings(budget: 0.01)
        s.record(0.02)
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply("x")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        agent.send("Add a door")
        await waitFor { agent.store.current.turns.last?.items.contains { if case .confirmation = $0 { true } else { false } } == true }
        #expect(t.requests.isEmpty, "nothing is sent past the budget without asking")
        let card = try #require(agent.store.current.turns.last?.items.compactMap { if case .confirmation(let c) = $0 { c } else { nil } }.first)
        #expect(card.confirmation.title == "Monthly budget reached")
        agent.answer(card.id, allow: false)
        await waitFor { !agent.isRunning }
        #expect(t.requests.isEmpty)
        #expect(agent.store.current.turns.last?.status == .stopped)
        // Continue once: the prompt runs.
        await agent.sendAndWait("Add a door", allowOverBudget: true)
        #expect(t.requests.count == 1)
    }

    @Test func stopCancelsAndKeepsTheConversationValid() async throws {
        let s = readySettings()
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply(nil, tools: [("x1", "save", ["path": "/tmp/never.arcus"])]), SSE.reply("Hi.")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        agent.send("Save it")
        await waitFor { agent.store.current.turns.last?.items.contains { if case .confirmation = $0 { true } else { false } } == true }
        agent.stop()
        await waitFor { !agent.isRunning }
        #expect(agent.store.current.turns.last?.status == .stopped)
        await agent.sendAndWait("Hello")
        // The interrupted call got its tool_result before the new prompt.
        let last = t.bodies.last?["messages"]?.arrayValue ?? []
        let ids = last.flatMap { $0["content"]?.arrayValue ?? [] }.filter { $0["type"]?.stringValue == "tool_result" }.compactMap { $0["tool_use_id"]?.stringValue }
        #expect(ids == ["x1"])
    }

    // MARK: Pricing, history, key

    @Test func pricesFollowThePublishedTable() {
        let p = AIPriceTable.published
        let u = AIUsage(input: 1_000_000, cacheWrite: 0, cacheRead: 0, output: 1_000_000)
        #expect(abs(p.cost(u, model: .sonnet) - 12.0) < 1e-9)
        #expect(abs(p.cost(AIUsage(input: 50_000, output: 10_000), model: .haiku) - (0.005 + 0.005)) < 1e-9)
        // Over 100K prompt tokens the whole Haiku request uses the long-prompt card.
        #expect(abs(p.cost(AIUsage(input: 10_000, cacheRead: 100_000), model: .haiku) - (0.005 + 0.005)) < 1e-9)
        #expect(AIFormat.dollars(0.0021) == "$0.0021" && AIFormat.tokens(12_400) == "12.4K")
    }

    @Test func historyRoundTripsWithoutKeyOrImages() throws {
        let store = AIChatStore()
        var turn = AITurn(prompt: "Dimension this plan")
        turn.attachmentNames = ["photo.jpg"]
        turn.items = [.text("Added 6 dimensions."), .step(AIToolStep(id: "1", tool: "add_dimensions", title: "Add Dimensions", summary: "view: Level 1", status: .ok, model: .haiku, edits: true))]
        turn.usage = [AIModelUsage(model: .haiku, usage: AIUsage(input: 10, output: 5), cost: 0.0001, requests: 1)]
        turn.status = .done
        store.current.turns = [turn]
        let data = try store.history.encoded()
        let back = try AIHistory.decode(data)
        #expect(back == store.history)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("sk-ant"), "no key in the saved history")
        #expect(!text.contains("base64"))
        let loaded = AIChatStore()
        loaded.load(back)
        #expect(loaded.current.turns.first?.finalText == "Added 6 dimensions.")
        loaded.clearAll()
        #expect(loaded.history.chats.isEmpty)
    }

    @Test func keyNeverWrittenToDisk() async throws {
        let suite = "arcus.ai.tests.key.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        let keys = MemoryKeyStore()
        let s = AISettings(defaults: d, keys: keys)
        let key = "sk-ant-api03-SECRETSECRETSECRET-xyz"
        s.setKey(key)
        s.enabled = true
        s.monthlyBudget = 5
        s.record(0.5)
        #expect(s.hasKey && s.maskedKey == "sk-ant-••••-xyz")
        let stored = d.dictionaryRepresentation().filter { $0.key.hasPrefix("ai.") }
        for (_, v) in stored {
            let text = (v as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "\(v)"
            #expect(!text.contains("SECRET"), "defaults hold no key")
        }
        // The request carries the key only in its header, never in the body.
        let (_, _, host) = await project()
        let t = MockTransport([SSE.reply("ok")])
        let agent = AIAgent(host: host, client: await client(t, s), settings: s)
        await agent.sendAndWait("Hi")
        let req = try #require(t.requests.first)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == key)
        #expect(!(String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "").contains("SECRET"))
        #expect(!String(decoding: try agent.store.history.encoded(), as: UTF8.self).contains("SECRET"))
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    @Test func undoGroupNestsToolGroups() async throws {
        let (fileHost, toolbox, _) = await project()
        let session = try #require(fileHost.session)
        let group = PromptUndoGroup { session.undoManager }
        await group.begin()
        _ = await toolbox.callTool("create_walls", arguments: ["points": [[0, 0], [10, 0]]])
        _ = await toolbox.callTool("create_walls", arguments: ["points": [[0, 5], [10, 5]]])
        group.end("AI: Two walls", changed: true)
        #expect(session.model.elements(.walls).count == 2)
        #expect(group.canUndo("AI: Two walls"))
        group.undo("AI: Two walls")
        #expect(session.model.elements(.walls).isEmpty)
        #expect(!group.canUndo("AI: Two walls"))
        session.undoManager.redo()
        #expect(session.model.elements(.walls).count == 2)
        #expect(group.canUndo("AI: Two walls"), "redone: undoable again")
        // An empty prompt leaves no step.
        let before = session.undoManager.undoActionName
        await group.begin()
        group.end("AI: Nothing", changed: false)
        #expect(session.undoManager.undoActionName == before)
    }
}
