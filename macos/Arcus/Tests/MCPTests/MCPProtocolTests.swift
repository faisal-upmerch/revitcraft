import Foundation
import Testing
@testable import ArcusMCP

// MCP: JSON-RPC / MCP protocol behaviour of MCPServer (initialize, tools/list, tools/call, errors).

@MainActor
@Suite("MCP protocol")
struct MCPProtocolTests {
    func server() -> MCPServer { MCPServer(tools: ArcusToolCatalog.all, backend: ArcusToolbox(host: FileDocumentHost())) }

    func send(_ s: MCPServer, _ text: String) async throws -> JSONValue {
        let out = try #require(await s.handle(text))
        #expect(!out.contains("\n"), "stdio messages are single lines")
        return try JSONValue.parse(out)
    }

    @Test func initializeNegotiatesVersionAndCapabilities() async throws {
        let s = server()
        let r = try await send(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-ai","version":"1"}}}"#)
        #expect(r["id"]?.intValue == 1)
        #expect(r["result"]?["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(r["result"]?["capabilities"]?["tools"] != nil)
        #expect(r["result"]?["serverInfo"]?["name"]?.stringValue == "arcus")
        #expect(s.clientName == "claude-ai")
        // An unknown version gets the server's latest.
        let old = try await send(s, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(old["id"]?.stringValue == "a")
        #expect(old["result"]?["protocolVersion"]?.stringValue == MCPServer.protocolVersions[0])
        // Notifications get no answer; ping answers empty.
        #expect(await s.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        let ping = try await send(s, #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect(ping["result"]?.objectValue?.isEmpty == true)
    }

    @Test func toolsListDescribesEveryToolWithASchema() async throws {
        let r = try await send(server(), #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try #require(r["result"]?["tools"]?.arrayValue)
        #expect(tools.count == ArcusToolCatalog.all.count)
        #expect(tools.count >= 35)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        for n in ["create_project", "create_walls", "place_doors", "place_windows", "create_floor", "create_roof", "add_stair", "place_rooms",
                  "place_components", "create_views", "create_sheet", "add_dimensions", "add_tags", "query_model", "set_parameters",
                  "delete_elements", "undo", "render_view", "export_pdf", "export_dwg", "save", "create_furniture", "add_furniture_parts"] {
            #expect(names.contains(n), "missing \(n)")
        }
        for t in tools {
            #expect(t["inputSchema"]?["type"]?.stringValue == "object")
            #expect((t["description"]?.stringValue?.count ?? 0) > 20)
        }
        #expect(tools.first { $0["name"]?.stringValue == "query_model" }?["annotations"]?["readOnlyHint"]?.boolValue == true)
    }

    @Test func errorsFollowJSONRPC() async throws {
        let s = server()
        let parse = try await send(s, "{not json")
        #expect(parse["error"]?["code"]?.intValue == RPCError.parse)
        let unknownMethod = try await send(s, #"{"jsonrpc":"2.0","id":4,"method":"sampling/createMessage"}"#)
        #expect(unknownMethod["error"]?["code"]?.intValue == RPCError.methodNotFound)
        let unknownTool = try await send(s, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"launch_rocket","arguments":{}}}"#)
        #expect(unknownTool["error"]?["code"]?.intValue == RPCError.invalidParams)
        let badArgs = try await send(s, #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"save","arguments":[1,2]}}"#)
        #expect(badArgs["error"]?["code"]?.intValue == RPCError.invalidParams)
        let notRPC = try await send(s, #"{"id":7,"method":"ping"}"#)
        #expect(notRPC["error"]?["code"]?.intValue == RPCError.invalidRequest)
    }

    @Test func toolFailuresAreResultsWithActionableText() async throws {
        let s = server()
        // No document yet: the tool runs and reports how to start.
        let r = try await send(s, #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"create_walls","arguments":{"points":[[0,0],[10,0]]}}}"#)
        #expect(r["error"] == nil)
        #expect(r["result"]?["isError"]?.boolValue == true)
        let text = r["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text.contains("create_project"))
        // Batches answer each request.
        let batch = try #require(await s.handle(#"[{"jsonrpc":"2.0","id":9,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"arcus_status"}}]"#))
        let arr = try #require(try JSONValue.parse(batch).arrayValue)
        #expect(arr.count == 2)
        #expect(arr[1]["result"]?["isError"]?.boolValue == false)
    }

    @Test func jsonRoundTripsAndEscapes() throws {
        let v: JSONValue = ["a": [1, 2.5, "x\"y\n", true, nil], "big": .int(9_007_199_254_740_000)]
        let back = try JSONValue.parse(v.jsonText)
        #expect(back == v)
        #expect(!v.jsonText.contains("\n"))
    }
}
