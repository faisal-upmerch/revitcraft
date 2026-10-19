import Foundation
import Testing
import ArcusDomain
@testable import ArcusMCP

// MCP: live mode's socket (Docs/MCP.md §3): permissions, hello, a forwarded tool call editing the served document, and
// refusal of a second server on the same path.

@MainActor
@Suite("MCP live socket")
struct MCPLiveSocketTests {
    @Test func servesToolCallsToTheOpenDocument() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("amcp-\(UUID().uuidString.prefix(6))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("s.sock").path
        // The "app": a toolbox on its own document, answering on the socket.
        let host = FileDocumentHost()
        let toolbox = ArcusToolbox(host: host)
        let server = LiveSocketServer(path: path) { req in
            await LiveProtocol.reply(to: req, backend: toolbox, hello: { ["app": "Arcus", "documents": []] })
        }
        try server.start()
        defer { server.stop() }

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((dirAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(throws: LiveSocket.Failure.self) { try LiveSocketServer(path: path) { _ in .null }.start() }

        // The client runs off the main actor, as arcus-mcp runs in another process.
        let hello = try await Task.detached { try LiveSocket.request(["v": 1, "id": 1, "op": "hello"], path: path, timeout: 5) }.value
        #expect(hello["ok"]?.boolValue == true)
        #expect(hello["result"]?["app"]?.stringValue == "Arcus")
        let created = try await Task.detached {
            try LiveSocket.request(["v": 1, "id": 2, "op": "call", "tool": "create_project", "arguments": ["name": "Live"]], path: path, timeout: 30)
        }.value
        #expect(ToolResult(json: created["result"] ?? .null)?.isError == false)
        let walls = try await Task.detached {
            try LiveSocket.request(["v": 1, "id": 3, "op": "call", "tool": "create_walls", "arguments": ["points": [[0, 0], [10, 0]]]], path: path, timeout: 30)
        }.value
        let r = try #require(ToolResult(json: walls["result"] ?? .null))
        #expect(!r.isError, "\(r.text)")
        #expect(host.session?.model.elements(.walls).count == 1, "the edit landed in the served document")
        let bad = try await Task.detached { try LiveSocket.request(["v": 9, "id": 4, "op": "hello"], path: path, timeout: 5) }.value
        #expect(bad["ok"]?.boolValue == false)

        // What the router checks before sending calls to the app (from another thread: the app's main actor must be free).
        let reachable = await Task.detached { LiveSocket.isReachable(path: path) }.value
        #expect(reachable)
        #expect(RoutingBackend(mode: .file, socketPath: path).useLive() == false)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path), "stop removes the socket")
        #expect(!LiveSocket.isReachable(path: path))
    }
}
