import Foundation

// MCP: Claude Desktop and Claude Code configuration for the arcus server (Docs/MCP.md §6). Reads the user's config to
// show whether Arcus is set up, and merges the "arcus" entry into Claude Desktop's config only when the user asks
// (Design with Claude ▸ Add to Claude Desktop), after backing the file up. Never touches other servers or settings.

public enum ClaudeClientConfig {
    public static let serverName = "arcus"

    /// Whether a client's config has the arcus server.
    public enum Status: Equatable, Sendable {
        /// The client isn't installed (no config folder).
        case clientMissing
        /// Installed, no arcus entry.
        case notConfigured
        /// An arcus entry pointing at `path`.
        case configured(path: String)
        /// The config can't be read as JSON.
        case unreadable
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public var description: String
        init(_ s: String) { description = s }
    }

    /// `~/Library/Application Support/Claude/claude_desktop_config.json`.
    public static var desktopConfigURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Claude/claude_desktop_config.json")
    }
    /// Claude Code's user config (`~/.claude.json`), where `claude mcp add --scope user` writes.
    public static var codeConfigURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json") }

    /// The Claude Desktop snippet for `serverPath`.
    public static func desktopSnippet(serverPath: String) -> String {
        """
        {
          "mcpServers": {
            "arcus": {
              "command": "\(serverPath)"
            }
          }
        }
        """
    }

    /// The Claude Code command for `serverPath` (user scope, so it works in every folder).
    public static func codeCommand(serverPath: String) -> String {
        "claude mcp add --scope user arcus -- \"\(serverPath)\""
    }

    /// The arcus entry's command in a config, from its JSON text.
    public static func status(of data: Data?, clientInstalled: Bool) -> Status {
        guard let data, !data.isEmpty else { return clientInstalled ? .notConfigured : .clientMissing }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreadable }
        guard let servers = root["mcpServers"] as? [String: Any], let arcus = servers[serverName] as? [String: Any] else { return .notConfigured }
        return .configured(path: arcus["command"] as? String ?? "")
    }

    public static func desktopStatus() -> Status {
        let url = desktopConfigURL
        let installed = FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
        return status(of: try? Data(contentsOf: url), clientInstalled: installed)
    }

    public static func codeStatus() -> Status {
        let url = codeConfigURL
        return status(of: try? Data(contentsOf: url), clientInstalled: FileManager.default.fileExists(atPath: url.path))
    }

    /// `data` (a Claude Desktop config, or nil for none) with `mcpServers.arcus` set to `serverPath`; every other key
    /// and server is kept.
    public static func merged(_ data: Data?, serverPath: String) throws(Failure) -> Data {
        var root: [String: Any] = [:]
        if let data, !data.isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
                throw Failure("Claude Desktop's configuration isn't valid JSON, so Arcus left it alone. Fix it or use Copy Configuration.")
            }
            root = dict
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        if root["mcpServers"] != nil && !(root["mcpServers"] is [String: Any]) {
            throw Failure("Claude Desktop's “mcpServers” isn't an object, so Arcus left the file alone.")
        }
        servers[serverName] = ["command": serverPath, "args": [String]()]
        root["mcpServers"] = servers
        do {
            return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw Failure("Could not write the configuration: \(error.localizedDescription)")
        }
    }

    /// Adds arcus to Claude Desktop's config at `url`: backs the old file up beside it
    /// (`claude_desktop_config.backup-<date>.json`), then writes the merged file atomically. Returns the backup, if any.
    @discardableResult
    public static func installDesktop(serverPath: String, at url: URL = desktopConfigURL, now: Date = Date()) throws(Failure) -> URL? {
        let fm = FileManager.default
        let old = try? Data(contentsOf: url)
        let new = try merged(old, serverPath: serverPath)
        var backup: URL?
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let old {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd-HHmmss"
                let b = url.deletingLastPathComponent().appendingPathComponent("claude_desktop_config.backup-\(f.string(from: now)).json")
                try old.write(to: b, options: .atomic)
                backup = b
            }
            try new.write(to: url, options: .atomic)
        } catch {
            throw Failure("Could not update \(url.path): \(error.localizedDescription)")
        }
        return backup
    }

    /// Runs the server binary once and asks it for its tools: proves Claude will be able to start it.
    public static func probe(serverPath: String, timeout: TimeInterval = 10) -> Result<Int, Failure> {
        guard FileManager.default.isExecutableFile(atPath: serverPath) else {
            return .failure(Failure("The Arcus server isn't at \(serverPath). Reinstall Arcus, or use the path of your copy."))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverPath)
        p.arguments = ["--mode", "file"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(Failure("The Arcus server didn't start: \(error.localizedDescription)")) }
        let lines = [#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"arcus-setup"}}}"#,
                     #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#]
        input.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        try? input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); return .failure(Failure("The Arcus server didn't answer within \(Int(timeout)) s.")) }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in text.split(separator: "\n") {
            if let v = try? JSONValue.parse(String(line)), v["id"]?.intValue == 2, let tools = v["result"]?["tools"]?.arrayValue { return .success(tools.count) }
        }
        return .failure(Failure("The Arcus server started but didn't list its tools."))
    }
}
