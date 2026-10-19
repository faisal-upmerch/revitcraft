// arcus-mcp: the Arcus MCP server (Docs/MCP.md). Speaks MCP over stdio to Claude Desktop or Claude Code and builds
// Arcus documents in this process (file mode) or in the running app (live mode). No network.
//
//   arcus-mcp                         serve MCP on stdin/stdout (what Claude runs)
//   arcus-mcp --mode file|live|auto   force a backend (default auto; ARCUS_MCP_MODE works too)
//   arcus-mcp --install-claude-desktop / --install-claude-code   print the configuration to add (writes nothing)

import Foundation
import ArcusMCP
import ArcusCAD

let args = CommandLine.arguments
let selfURL = URL(fileURLWithPath: args[0]).resolvingSymlinksInPath()
let selfPath = (selfURL.path.hasPrefix("/") ? selfURL : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(args[0]).standardizedFileURL).path
let version = "1.0.0"

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

if args.contains("--help") || args.contains("-h") {
    print("""
    arcus-mcp \(version): lets Claude create and edit Arcus designs (Model Context Protocol over stdio).

      arcus-mcp                          serve MCP on stdin/stdout (Claude starts it)
      --mode auto|file|live              auto (default): the running Arcus app when its MCP setting is on, else files
      --install-claude-desktop           print the Claude Desktop configuration snippet
      --install-claude-code              print the Claude Code command
      --version
    """)
    exit(0)
}
if args.contains("--version") { print(version); exit(0) }
if args.contains("--install-claude-desktop") {
    let snippet: JSONValue = ["mcpServers": ["arcus": ["command": .string(selfPath), "args": []]]]
    print("""
    Add this to ~/Library/Application Support/Claude/claude_desktop_config.json (merge into "mcpServers" if the file
    already has one), then quit and reopen Claude Desktop:

    \(snippet.jsonText)

    To let Claude edit documents open in Arcus, turn on Arcus ▸ Settings ▸ Claude (MCP) ▸ Allow Claude to edit open documents.
    """)
    exit(0)
}
if args.contains("--install-claude-code") {
    print("""
    Run:

      \(ClaudeClientConfig.codeCommand(serverPath: selfPath))

    Then /mcp in Claude Code shows the arcus tools. (Drop --scope user to add it to the current project only.)
    """)
    exit(0)
}

var mode = RoutingBackend.Mode(rawValue: ProcessInfo.processInfo.environment["ARCUS_MCP_MODE"] ?? "") ?? .auto
if let i = args.firstIndex(of: "--mode"), i + 1 < args.count {
    guard let m = RoutingBackend.Mode(rawValue: args[i + 1]) else { stderr("--mode must be auto, file or live"); exit(64) }
    mode = m
}

// DWG engine: beside this binary (Arcus.app/Contents/Helpers), else wherever the app's lookup finds it.
let helperDir = selfURL.deletingLastPathComponent()
let dwg = BundledDWGHelpers.in(helperDir).acadrust ?? BundledDWGHelpers.standard.acadrust

let backend = RoutingBackend(mode: mode, dwgHelper: dwg)
let server = MCPServer(tools: ArcusToolCatalog.all, backend: backend)
server.serverVersion = version
stderr("arcus-mcp \(version) ready (mode \(mode.rawValue))")

// MCP stdio: one JSON-RPC message per line in, one per line out. Nothing else may go to stdout.
while let line = readLine(strippingNewline: true) {
    if let out = await server.handle(line) {
        FileHandle.standardOutput.write(Data((out + "\n").utf8))
    }
}
