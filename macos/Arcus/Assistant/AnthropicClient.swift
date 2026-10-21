import Foundation
import ArcusMCP

// AICORE: a small client for Anthropic's Messages API (POST /v1/messages, `anthropic-version: 2023-06-01`) on
// URLSession: streaming (SSE), client tools, base64 images, prompt caching and retries. No SDK, no third-party code.
// It refuses to send anything unless Settings ▸ AI is on and a key is in the Keychain (`AIAccess`).

/// One Messages API request. Messages and content are kept as raw JSON so thinking blocks round-trip unchanged.
public struct AIRequest: Sendable {
    public var model: AIModel
    public var maxTokens: Int
    /// System text blocks (stable per document kind: the cached prefix).
    public var system: [String]
    /// Tool definitions (`name`, `description`, `input_schema`), in a fixed order.
    public var tools: [JSONValue]
    public var messages: [JSONValue]
    /// The block that ends the current prompt's context summary, as (message index, block index): it gets a cache
    /// breakpoint so every step of the prompt re-reads tools + system + history + context from the cache.
    public var contextBreakpoint: (message: Int, block: Int)?

    public init(model: AIModel, maxTokens: Int = 64_000, system: [String], tools: [JSONValue], messages: [JSONValue], contextBreakpoint: (message: Int, block: Int)? = nil) {
        self.model = model; self.maxTokens = maxTokens; self.system = system; self.tools = tools; self.messages = messages
        self.contextBreakpoint = contextBreakpoint
    }

    static let ephemeral: JSONValue = ["type": "ephemeral"]

    /// The JSON body. Prompt caching uses all four breakpoints:
    /// 1. the last tool definition (tools are identical for every request of a document kind);
    /// 2. the last system block (tools + system);
    /// 3. the current prompt's context summary block (tools + system + earlier turns + this prompt's context);
    /// 4. top-level automatic caching, which moves with the growing tool loop.
    /// Any `cache_control` left in stored messages is removed first, so there are never more than four.
    public var body: JSONValue {
        var tools = self.tools
        if var last = tools.last?.objectValue {
            last["cache_control"] = Self.ephemeral
            tools[tools.count - 1] = .object(last)
        }
        var sys: [JSONValue] = system.map { ["type": "text", "text": .string($0)] }
        if var last = sys.last?.objectValue {
            last["cache_control"] = Self.ephemeral
            sys[sys.count - 1] = .object(last)
        }
        var msgs = messages.map(Self.strippingCacheControl)
        if let bp = contextBreakpoint, bp.message < msgs.count, var m = msgs[bp.message].objectValue, var content = m["content"]?.arrayValue,
           bp.block < content.count, var block = content[bp.block].objectValue {
            block["cache_control"] = Self.ephemeral
            content[bp.block] = .object(block)
            m["content"] = .array(content)
            msgs[bp.message] = .object(m)
        }
        var o: [String: JSONValue] = [
            "model": .string(model.id),
            "max_tokens": .int(maxTokens),
            "stream": true,
            "system": .array(sys),
            "messages": .array(msgs),
            "output_config": ["effort": .string(model.effort)],
            "cache_control": Self.ephemeral,
        ]
        if !tools.isEmpty { o["tools"] = .array(tools) }
        return .object(o)
    }

    static func strippingCacheControl(_ message: JSONValue) -> JSONValue {
        guard var m = message.objectValue, let content = m["content"]?.arrayValue else { return message }
        m["content"] = .array(content.map { b in
            guard var o = b.objectValue, o["cache_control"] != nil else { return b }
            o.removeValue(forKey: "cache_control")
            return .object(o)
        })
        return .object(m)
    }
}

/// The HTTP layer, so tests run the client against recorded streams with no network.
public protocol AITransport: Sendable {
    /// Sends `request` and returns the status, the headers (lower-cased names) and the body as lines (blank lines kept).
    func open(_ request: URLRequest) async throws -> (status: Int, headers: [String: String], lines: AsyncThrowingStream<String, any Error>)
}

/// The real transport: URLSession, with an idle timeout of 90 s between bytes and 10 minutes for a whole response.
public struct URLSessionTransport: AITransport {
    let session: URLSession

    public init() {
        let c = URLSessionConfiguration.ephemeral // no cookies, no URL cache on disk
        c.timeoutIntervalForRequest = 90
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = false
        c.urlCache = nil
        session = URLSession(configuration: c)
    }

    public func open(_ request: URLRequest) async throws -> (status: Int, headers: [String: String], lines: AsyncThrowingStream<String, any Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { headers[String(describing: k).lowercased()] = String(describing: v) }
        let lines = AsyncThrowingStream<String, any Error> { cont in
            let task = Task {
                // `bytes.lines` skips blank lines, which end SSE events, so split the bytes here.
                var buffer: [UInt8] = []
                buffer.reserveCapacity(4096)
                do {
                    for try await b in bytes {
                        if b == 0x0A {
                            cont.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(b)
                        }
                    }
                    if !buffer.isEmpty { cont.yield(String(decoding: buffer, as: UTF8.self)) }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
        return (http?.statusCode ?? 0, headers, lines)
    }
}

/// Whether the assistant may use the network now, and the key to use. Read on every request.
public struct AIAccess: Sendable {
    public var enabled: @Sendable () -> Bool
    public var key: @Sendable () -> String?
    public init(enabled: @escaping @Sendable () -> Bool, key: @escaping @Sendable () -> String?) { self.enabled = enabled; self.key = key }
}

/// The Messages API client.
public final class AnthropicClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2023-06-01"

    let transport: any AITransport
    let access: AIAccess
    /// Retries after the first attempt for 429, 5xx, 529 and connection failures (only before any output arrived).
    let maxRetries: Int
    let sleep: @Sendable (Double) async throws -> Void

    public init(transport: any AITransport = URLSessionTransport(), access: AIAccess, maxRetries: Int = 3,
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.transport = transport; self.access = access; self.maxRetries = maxRetries; self.sleep = sleep
    }

    /// The key, or the reason there is none. No request is built without both the switch and a key.
    func checkedKey() throws(AIError) -> String {
        guard access.enabled() else { throw AIError(.disabled, "Turn on the AI assistant in Settings ▸ AI to use it.") }
        guard let k = access.key()?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else {
            throw AIError(.noKey, "Add your Anthropic API key in Settings ▸ AI.")
        }
        return k
    }

    static func urlRequest(_ url: URL, key: String, body: Data?, method: String = "POST") -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("text/event-stream", forHTTPHeaderField: "accept")
            r.httpBody = body
        }
        return r
    }

    /// Builds the URLRequest for `request` (tests inspect it).
    public func makeURLRequest(_ request: AIRequest) throws(AIError) -> URLRequest {
        let key = try checkedKey()
        return Self.urlRequest(Self.endpoint, key: key, body: Data(request.body.jsonText.utf8))
    }

    /// Streams one request. `onDelta` gets text as it arrives. Retries transient failures with backoff as long as
    /// nothing has been shown yet; cancelling the task stops the request.
    public func stream(_ request: AIRequest, onDelta: @escaping @Sendable (AIStreamDelta) async -> Void = { _ in }) async throws(AIError) -> AIResponseMessage {
        let urlRequest = try makeURLRequest(request)
        var attempt = 0
        while true {
            var emitted = false
            do {
                return try await once(urlRequest) { d in emitted = true; await onDelta(d) }
            } catch let e {
                if Task.isCancelled || e.kind == .cancelled { throw AIError(.cancelled, "Stopped.") }
                guard e.retryable, !emitted, attempt < maxRetries else { throw e }
                attempt += 1
                let wait = min(20, e.retryAfter ?? pow(2, Double(attempt - 1)) + Double.random(in: 0...0.25))
                do { try await sleep(wait) } catch { throw AIError(.cancelled, "Stopped.") }
            }
        }
    }

    private func once(_ urlRequest: URLRequest, onDelta: (AIStreamDelta) async -> Void) async throws(AIError) -> AIResponseMessage {
        let opened: (status: Int, headers: [String: String], lines: AsyncThrowingStream<String, any Error>)
        do { opened = try await transport.open(urlRequest) } catch { throw AIError.transport(error) }
        if opened.status != 200 {
            var body = ""
            do { for try await l in opened.lines { body += l + "\n" } } catch {}
            throw AIError.http(opened.status, body: Data(body.utf8), retryAfter: opened.headers["retry-after"].flatMap(Double.init))
        }
        var parser = SSEParser()
        var acc = AIStreamAccumulator()
        do {
            for try await line in opened.lines {
                if Task.isCancelled { throw AIError(.cancelled, "Stopped.") }
                if let e = parser.feed(line), let d = try acc.apply(e) { await onDelta(d) }
            }
            if let e = parser.flush(), let d = try acc.apply(e) { await onDelta(d) }
        } catch let e as AIError {
            throw e
        } catch {
            throw AIError.transport(error)
        }
        guard acc.finished || acc.message.stopReason != nil else {
            throw AIError(.badResponse, "The response ended early. Try again.", retryable: true)
        }
        return acc.result()
    }

    /// Settings ▸ AI ▸ Test: reads the Haiku model's record (`GET /v1/models/claude-haiku-5-5`), which checks the key
    /// and model access without generating tokens (free). `key` is the one typed in the field, if not yet saved.
    public func test(key: String? = nil) async -> Result<String, AIError> {
        guard access.enabled() else { return .failure(AIError(.disabled, "Turn on the AI assistant first.")) }
        let k: String
        if let key, !key.isEmpty { k = key } else {
            do { k = try checkedKey() } catch { return .failure(error) }
        }
        let url = URL(string: "https://api.anthropic.com/v1/models/\(AIModel.haiku.id)")!
        do {
            let r = try await transport.open(Self.urlRequest(url, key: k, body: nil, method: "GET"))
            var body = ""
            for try await l in r.lines { body += l + "\n" }
            if r.status == 200 {
                let name = (try? JSONValue.parse(body))?["display_name"]?.stringValue ?? AIModel.haiku.displayName
                return .success("Connected. \(name) is available for this key.")
            }
            return .failure(AIError.http(r.status, body: Data(body.utf8), retryAfter: nil))
        } catch {
            return .failure(AIError.transport(error))
        }
    }
}
