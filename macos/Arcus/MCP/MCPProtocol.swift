import Foundation

// MCP: the Model Context Protocol over JSON-RPC 2.0 (Docs/MCP.md §1). Transport-agnostic: `handle` takes one message
// (a line from stdin) and returns the response line, or nil for notifications.

/// One tool as listed by `tools/list`.
public struct ToolSpec: Sendable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: JSONValue
    /// True for tools that never change the document (query, list, render, export).
    public var readOnly: Bool
    /// True for tools that remove content (delete, undo).
    public var destructive: Bool

    public init(_ name: String, _ title: String, _ description: String, readOnly: Bool = false, destructive: Bool = false,
                properties: [String: JSONValue] = [:], required: [String] = []) {
        self.name = name; self.title = title; self.description = description; self.readOnly = readOnly; self.destructive = destructive
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        inputSchema = .object(schema)
    }

    public var listing: JSONValue {
        ["name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": inputSchema,
         "annotations": ["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                         "idempotentHint": .bool(readOnly), "openWorldHint": false]]
    }
}

/// The result of `tools/call`: MCP content blocks plus the error flag.
public struct ToolResult: Sendable {
    public var content: [JSONValue]
    public var isError: Bool

    public init(content: [JSONValue], isError: Bool = false) { self.content = content; self.isError = isError }
    public static func text(_ s: String, isError: Bool = false) -> ToolResult { ToolResult(content: [["type": "text", "text": .string(s)]], isError: isError) }
    public static func json(_ v: JSONValue) -> ToolResult { .text(v.jsonText) }
    public static func error(_ message: String) -> ToolResult { .text(message, isError: true) }

    public var json: JSONValue { ["content": .array(content), "isError": .bool(isError)] }
    public init?(json: JSONValue) {
        guard let c = json["content"]?.arrayValue else { return nil }
        content = c
        isError = json["isError"]?.boolValue ?? false
    }
    /// The text of the first text block (tests and the demo read results this way).
    public var text: String { content.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue ?? "" }
}

/// Runs tool calls. File mode, live mode and the router all implement it.
@MainActor
public protocol ToolBackend: AnyObject {
    func callTool(_ name: String, arguments: [String: JSONValue]) async -> ToolResult
}

/// JSON-RPC 2.0 error codes used by MCP.
public enum RPCError {
    public static let parse = -32700, invalidRequest = -32600, methodNotFound = -32601, invalidParams = -32602, internalError = -32603
}

@MainActor
public final class MCPServer {
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public let tools: [ToolSpec]
    public let backend: any ToolBackend
    public var serverName = "arcus"
    public var serverVersion = "1.0.0"
    public var instructions = """
        Arcus is a native macOS BIM app (Revit-like). Start with arcus_status. Create or open a document, then build \
        with coarse tools (walls by polyline, all doors at once, rooms automatically). Lengths are in the document's unit \
        (ft for Imperial projects, mm for Metric, in for Furniture) or strings like 12'-6". Check work with query_model \
        (rooms with areas, warnings) and render_view; save when done.
        """
    /// Set once the client has sent `initialize`.
    public private(set) var clientName: String?
    private let byName: [String: ToolSpec]

    public init(tools: [ToolSpec], backend: any ToolBackend) {
        self.tools = tools
        self.backend = backend
        byName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Handles one JSON-RPC message (or batch). Returns the response text, or nil when nothing is to be sent.
    public func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let msg: JSONValue
        do { msg = try JSONValue.parse(trimmed) } catch {
            return Self.errorResponse(id: .null, code: RPCError.parse, message: "Parse error: \(error.description)").jsonText
        }
        if let batch = msg.arrayValue {
            guard !batch.isEmpty else { return Self.errorResponse(id: .null, code: RPCError.invalidRequest, message: "Empty batch.").jsonText }
            var out: [JSONValue] = []
            for m in batch { if let r = await handleMessage(m) { out.append(r) } }
            return out.isEmpty ? nil : JSONValue.array(out).jsonText
        }
        return await handleMessage(msg)?.jsonText
    }

    func handleMessage(_ msg: JSONValue) async -> JSONValue? {
        guard msg.objectValue != nil, msg["jsonrpc"]?.stringValue == "2.0" else {
            return Self.errorResponse(id: msg["id"] ?? .null, code: RPCError.invalidRequest, message: "Not a JSON-RPC 2.0 message.")
        }
        guard let method = msg["method"]?.stringValue else {
            // A response from the client (we never send requests): ignore.
            return nil
        }
        let id = msg["id"]
        let params = msg["params"]?.objectValue ?? [:]
        // Notifications get no response.
        guard let id, !id.isNull else { return nil }
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? ""
            clientName = params["clientInfo"]?["name"]?.stringValue ?? "client"
            let version = Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(serverName), "title": "Arcus", "version": .string(serverVersion)],
                "instructions": .string(instructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(tools.map(\.listing))])
        case "resources/list":
            return Self.result(id: id, ["resources": []])
        case "resources/templates/list":
            return Self.result(id: id, ["resourceTemplates": []])
        case "prompts/list":
            return Self.result(id: id, ["prompts": []])
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return Self.errorResponse(id: id, code: RPCError.invalidParams, message: "tools/call needs a tool name.")
            }
            guard byName[name] != nil else {
                return Self.errorResponse(id: id, code: RPCError.invalidParams, message: "Unknown tool: \(name). Call tools/list for the \(tools.count) Arcus tools.")
            }
            let argValue = params["arguments"] ?? .object([:])
            guard let args = argValue.objectValue ?? (argValue.isNull ? [:] : nil) else {
                return Self.errorResponse(id: id, code: RPCError.invalidParams, message: "Tool arguments must be a JSON object.")
            }
            let r = await backend.callTool(name, arguments: args)
            return Self.result(id: id, r.json)
        default:
            return Self.errorResponse(id: id, code: RPCError.methodNotFound, message: "Method not found: \(method)")
        }
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]
    }
}
