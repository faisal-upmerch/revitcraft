import Foundation

// MCP: the live-mode request format on both ends (Docs/MCP.md §3) and the router arcus-mcp uses to pick file or live
// mode per call (§2).

/// Turns live-socket requests into tool calls (the app side).
@MainActor
public enum LiveProtocol {
    /// Answers one request: `hello` with `hello()`'s info, `call` by running the tool on `backend`.
    public static func reply(to req: JSONValue, backend: any ToolBackend, hello: () -> JSONValue) async -> JSONValue {
        let id = req["id"] ?? .null
        func fail(_ s: String) -> JSONValue { ["v": .int(LiveSocket.protocolVersion), "id": id, "ok": false, "error": .string(s)] }
        guard req["v"]?.intValue == LiveSocket.protocolVersion else { return fail("Unsupported protocol version; update arcus-mcp to match this Arcus.") }
        switch req["op"]?.stringValue {
        case "hello":
            return ["v": .int(LiveSocket.protocolVersion), "id": id, "ok": true, "result": hello()]
        case "call":
            guard let tool = req["tool"]?.stringValue, ArcusToolCatalog.all.contains(where: { $0.name == tool }) else { return fail("Unknown tool.") }
            let args = req["arguments"]?.objectValue ?? [:]
            let r = await backend.callTool(tool, arguments: args)
            return ["v": .int(LiveSocket.protocolVersion), "id": id, "ok": true, "result": r.json]
        default:
            return fail("Unknown op; expected hello or call.")
        }
    }
}

/// arcus-mcp's backend: file mode in this process, or live mode in the running app.
@MainActor
public final class RoutingBackend: ToolBackend {
    public enum Mode: String, Sendable { case auto, file, live }
    public let mode: Mode
    public let fileHost: FileDocumentHost
    public let fileToolbox: ArcusToolbox
    public let socketPath: String
    var nextID = 1

    public init(mode: Mode, socketPath: String = LiveSocket.defaultPath, dwgHelper: URL? = nil) {
        self.mode = mode
        self.socketPath = socketPath
        fileHost = FileDocumentHost()
        fileToolbox = ArcusToolbox(host: fileHost, dwgHelper: dwgHelper)
        fileToolbox.statusExtras = { [socketPath, mode] in
            ["mode": .string(mode.rawValue), "app_listening": .bool(mode != .file && LiveSocket.isReachable(path: socketPath))]
        }
    }

    /// Live when asked, or (auto) when no file-mode document is open and the app answers.
    func useLive() -> Bool {
        switch mode {
        case .file: return false
        case .live: return true
        case .auto: return fileHost.session == nil && LiveSocket.isReachable(path: socketPath)
        }
    }

    public func callTool(_ name: String, arguments: [String: JSONValue]) async -> ToolResult {
        guard useLive() else { return await fileToolbox.callTool(name, arguments: arguments) }
        nextID += 1
        let req: JSONValue = ["v": .int(LiveSocket.protocolVersion), "id": .int(nextID), "op": "call", "tool": .string(name), "arguments": .object(arguments)]
        do {
            let reply = try LiveSocket.request(req, path: socketPath, timeout: 120)
            guard reply["ok"]?.boolValue == true, let r = reply["result"].flatMap(ToolResult.init(json:)) else {
                return .error(reply["error"]?.stringValue ?? "Arcus refused the call.")
            }
            return r
        } catch {
            return .error("Live mode: \(error.description)")
        }
    }
}
