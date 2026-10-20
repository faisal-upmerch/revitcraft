import Foundation
import ArcusMCP

// AICORE: Server-Sent Events as the Messages API streams them (`event:` + `data:` lines, a blank line ends an event),
// and the accumulator that rebuilds the final message from the deltas.

/// One server-sent event.
public struct SSEEvent: Sendable, Hashable {
    public var event: String
    public var data: String
}

/// Incremental SSE parser: feed lines (without their line break, blank lines included), get events.
public struct SSEParser: Sendable {
    private var event = ""
    private var data: [String] = []

    public init() {}

    /// Feeds one line; returns an event when the line completes one.
    public mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return nil } // comment / keep-alive
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line); value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break // id, retry: unused
        }
        return nil
    }

    /// Ends the stream: returns a final event that had no trailing blank line.
    public mutating func flush() -> SSEEvent? {
        defer { event = ""; data = [] }
        guard !data.isEmpty || !event.isEmpty else { return nil }
        let joined = data.joined(separator: "\n")
        var name = event
        if name.isEmpty, let t = (try? JSONValue.parse(joined))?["type"]?.stringValue { name = t }
        return SSEEvent(event: name, data: joined)
    }
}

/// What a stream reports while it runs.
public enum AIStreamDelta: Sendable {
    case text(String)
    /// A tool call started (its input arrives later).
    case toolStart(name: String)
}

/// The final message rebuilt from a stream: content blocks exactly as the API sent them (thinking blocks keep their
/// signatures, so they can be passed back unchanged), the stop reason and the usage.
public struct AIResponseMessage: Sendable {
    public var id = ""
    public var model = ""
    public var content: [JSONValue] = []
    public var stopReason: String?
    public var usage = AIUsage()

    public init() {}

    public var text: String { content.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }.joined() }
    public var toolUses: [(id: String, name: String, input: [String: JSONValue])] {
        content.compactMap { b in
            guard b["type"]?.stringValue == "tool_use", let id = b["id"]?.stringValue, let name = b["name"]?.stringValue else { return nil }
            return (id, name, b["input"]?.objectValue ?? [:])
        }
    }
}

/// Builds an `AIResponseMessage` from stream events.
public struct AIStreamAccumulator: Sendable {
    public private(set) var message = AIResponseMessage()
    private var blocks: [Int: [String: JSONValue]] = [:]
    private var partialJSON: [Int: String] = [:]
    private var order: [Int] = []
    public private(set) var finished = false

    public init() {}

    /// Applies one event. Returns a delta for the UI, or nil. Throws on an `error` event.
    public mutating func apply(_ e: SSEEvent) throws(AIError) -> AIStreamDelta? {
        guard let v = try? JSONValue.parse(e.data) else {
            if e.event == "ping" { return nil }
            throw AIError(.badResponse, "The response stream had an unreadable event.")
        }
        let type = v["type"]?.stringValue ?? e.event
        switch type {
        case "message_start":
            message.id = v["message"]?["id"]?.stringValue ?? ""
            message.model = v["message"]?["model"]?.stringValue ?? ""
            if let u = v["message"]?["usage"] { message.usage = Self.usage(u, base: AIUsage()) }
        case "content_block_start":
            guard let i = v["index"]?.intValue, let b = v["content_block"]?.objectValue else { return nil }
            blocks[i] = b
            order.append(i)
            if b["type"]?.stringValue == "tool_use" {
                partialJSON[i] = ""
                return .toolStart(name: b["name"]?.stringValue ?? "")
            }
        case "content_block_delta":
            guard let i = v["index"]?.intValue, let d = v["delta"], var b = blocks[i] else { return nil }
            switch d["type"]?.stringValue {
            case "text_delta":
                let t = d["text"]?.stringValue ?? ""
                b["text"] = .string((b["text"]?.stringValue ?? "") + t)
                blocks[i] = b
                return .text(t)
            case "input_json_delta":
                partialJSON[i, default: ""] += d["partial_json"]?.stringValue ?? ""
            case "thinking_delta":
                b["thinking"] = .string((b["thinking"]?.stringValue ?? "") + (d["thinking"]?.stringValue ?? ""))
                blocks[i] = b
            case "signature_delta":
                b["signature"] = .string((b["signature"]?.stringValue ?? "") + (d["signature"]?.stringValue ?? ""))
                blocks[i] = b
            case "citations_delta":
                var c = b["citations"]?.arrayValue ?? []
                if let cit = d["citation"] { c.append(cit) }
                b["citations"] = .array(c)
                blocks[i] = b
            default:
                break
            }
        case "content_block_stop":
            guard let i = v["index"]?.intValue, var b = blocks[i] else { return nil }
            if let json = partialJSON.removeValue(forKey: i) {
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    b["input"] = .object([:])
                } else if let parsed = try? JSONValue.parse(trimmed), parsed.objectValue != nil {
                    b["input"] = parsed
                } else {
                    // A cut-off tool input (max_tokens mid-call): keep it as an empty object and let the loop report it.
                    b["input"] = .object([:])
                    b["arcus_invalid_input"] = .bool(true)
                }
            }
            blocks[i] = b
        case "message_delta":
            if let r = v["delta"]?["stop_reason"]?.stringValue { message.stopReason = r }
            if let u = v["usage"] { message.usage = Self.usage(u, base: message.usage) }
        case "message_stop":
            finished = true
        case "ping":
            break
        case "error":
            let kind = v["error"]?["type"]?.stringValue ?? ""
            let msg = v["error"]?["message"]?.stringValue ?? "The service reported an error."
            throw AIError(kind == "overloaded_error" ? .overloaded : .server, msg, retryable: kind == "overloaded_error" || kind == "api_error")
        default:
            break
        }
        return nil
    }

    /// The finished message, content in index order.
    public func result() -> AIResponseMessage {
        var m = message
        m.content = order.compactMap { i in
            guard var b = blocks[i] else { return nil }
            b.removeValue(forKey: "arcus_invalid_input")
            return .object(b)
        }
        return m
    }

    /// Tool-use block ids whose streamed input couldn't be parsed.
    public var invalidToolInputs: Set<String> {
        Set(order.compactMap { i in blocks[i].flatMap { $0["arcus_invalid_input"] != nil ? $0["id"]?.stringValue : nil } })
    }

    /// Reads `usage`, keeping fields a later event leaves out (message_delta only repeats some of them).
    static func usage(_ u: JSONValue, base: AIUsage) -> AIUsage {
        var r = base
        if let n = u["input_tokens"]?.intValue { r.input = n }
        if let n = u["cache_creation_input_tokens"]?.intValue { r.cacheWrite = n }
        if let n = u["cache_read_input_tokens"]?.intValue { r.cacheRead = n }
        if let n = u["output_tokens"]?.intValue { r.output = n }
        return r
    }
}
