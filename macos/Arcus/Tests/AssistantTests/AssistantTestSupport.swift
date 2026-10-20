import Foundation
@testable import ArcusAssistant
import ArcusMCP

// AICORE: a scripted transport (no network): each request pops the next canned response and is recorded.

final class MockTransport: AITransport, @unchecked Sendable {
    struct Canned { var status = 200; var headers: [String: String] = [:]; var lines: [String]; var failAfter: Int? = nil; var error: (any Error)? = nil }
    private let lock = NSLock()
    private var queue: [Canned]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Canned]) { queue = responses }

    private func pop(_ request: URLRequest) -> Canned? {
        lock.withLock {
            requests.append(request)
            return queue.isEmpty ? nil : queue.removeFirst()
        }
    }

    func push(_ c: Canned) { lock.lock(); queue.append(c); lock.unlock() }

    var bodies: [JSONValue] {
        lock.lock(); defer { lock.unlock() }
        return requests.compactMap { $0.httpBody.flatMap { try? JSONValue.parse($0) } }
    }
    var models: [String] { bodies.compactMap { $0["model"]?.stringValue } }

    func open(_ request: URLRequest) async throws -> (status: Int, headers: [String: String], lines: AsyncThrowingStream<String, any Error>) {
        let next = pop(request)
        guard let c = next else { throw URLError(.badServerResponse) }
        if let e = c.error { throw e }
        let lines = AsyncThrowingStream<String, any Error> { cont in
            for (i, l) in c.lines.enumerated() {
                if let f = c.failAfter, i == f { cont.finish(throwing: URLError(.networkConnectionLost)); return }
                cont.yield(l)
            }
            cont.finish()
        }
        return (c.status, c.headers, lines)
    }
}

/// SSE fixtures in the Messages API's shape.
enum SSE {
    static func event(_ name: String, _ data: JSONValue) -> [String] { ["event: \(name)", "data: \(data.jsonText)", ""] }

    static func start(input: Int = 1200, cacheRead: Int = 0, cacheWrite: Int = 0, model: String = "claude-haiku-5-5") -> [String] {
        event("message_start", ["type": "message_start", "message": ["id": "msg_1", "type": "message", "role": "assistant", "model": .string(model), "content": [],
                                                                       "usage": ["input_tokens": .int(input), "cache_read_input_tokens": .int(cacheRead), "cache_creation_input_tokens": .int(cacheWrite), "output_tokens": 1]]])
    }
    static func text(_ index: Int, _ chunks: [String]) -> [String] {
        var out = event("content_block_start", ["type": "content_block_start", "index": .int(index), "content_block": ["type": "text", "text": ""]])
        for c in chunks { out += event("content_block_delta", ["type": "content_block_delta", "index": .int(index), "delta": ["type": "text_delta", "text": .string(c)]]) }
        return out + event("content_block_stop", ["type": "content_block_stop", "index": .int(index)])
    }
    static func thinking(_ index: Int) -> [String] {
        event("content_block_start", ["type": "content_block_start", "index": .int(index), "content_block": ["type": "thinking", "thinking": "", "signature": ""]])
            + event("content_block_delta", ["type": "content_block_delta", "index": .int(index), "delta": ["type": "signature_delta", "signature": "sig-abc"]])
            + event("content_block_stop", ["type": "content_block_stop", "index": .int(index)])
    }
    static func tool(_ index: Int, id: String, name: String, input: JSONValue) -> [String] {
        let json = input.jsonText
        let mid = json.index(json.startIndex, offsetBy: json.count / 2)
        return event("content_block_start", ["type": "content_block_start", "index": .int(index), "content_block": ["type": "tool_use", "id": .string(id), "name": .string(name), "input": [:]]])
            + event("content_block_delta", ["type": "content_block_delta", "index": .int(index), "delta": ["type": "input_json_delta", "partial_json": .string(String(json[..<mid]))]])
            + event("content_block_delta", ["type": "content_block_delta", "index": .int(index), "delta": ["type": "input_json_delta", "partial_json": .string(String(json[mid...]))]])
            + event("content_block_stop", ["type": "content_block_stop", "index": .int(index)])
    }
    static func end(_ reason: String, output: Int = 80) -> [String] {
        event("message_delta", ["type": "message_delta", "delta": ["stop_reason": .string(reason), "stop_sequence": .null], "usage": ["output_tokens": .int(output)]])
            + event("message_stop", ["type": "message_stop"])
    }

    /// A whole response: text, then tool calls.
    static func reply(_ message: String? = nil, tools: [(id: String, name: String, input: JSONValue)] = [], model: String = "claude-haiku-5-5") -> MockTransport.Canned {
        var lines = start(model: model)
        var i = 0
        if let message { lines += text(i, [message]); i += 1 }
        for t in tools { lines += tool(i, id: t.id, name: t.name, input: t.input); i += 1 }
        lines += end(tools.isEmpty ? "end_turn" : "tool_use")
        return MockTransport.Canned(lines: lines)
    }
}

@MainActor
func readySettings(budget: Double = 0) -> AISettings {
    let d = UserDefaults(suiteName: "arcus.ai.tests.\(UUID().uuidString)")!
    let s = AISettings(defaults: d, keys: MemoryKeyStore("sk-ant-test-0123456789abcdef"))
    s.enabled = true
    s.monthlyBudget = budget
    return s
}

func client(_ t: MockTransport, _ s: AISettings) async -> AnthropicClient {
    let access = await MainActor.run { AISettings.access(s) }
    return AnthropicClient(transport: t, access: access, sleep: { _ in })
}
