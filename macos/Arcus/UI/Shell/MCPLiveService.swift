import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusCAD
import ArcusServices
import ArcusMCP

// MCP: live mode (Docs/MCP.md §3). While Settings ▸ Claude (MCP) is on, arcus-mcp's tool calls arrive on a Unix
// domain socket in Application Support (0600, same user only) and run on the front document's DocumentSession, so
// each call is one ⌘Z step and shows as it happens. Off by default; nothing listens otherwise.

@MainActor
final class MCPLiveService {
    static let shared = MCPLiveService()
    static let defaultsKey = "mcp.liveEnabled"

    private var server: LiveSocketServer?
    private(set) var lastError: String?
    let host = AppDocumentHost()
    private(set) lazy var toolbox = ArcusToolbox(host: host, dwgHelper: BundledDWGHelpers.standard.acadrust)

    var isRunning: Bool { server?.isRunning == true }
    var socketPath: String { LiveSocket.defaultPath }
    /// The bundled server binary, for the setup snippets.
    var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/arcus-mcp").path }

    /// Starts or stops the listener to match the setting (called at launch and when the toggle changes).
    func applySetting() {
        setEnabled(UserDefaults.standard.bool(forKey: Self.defaultsKey))
    }

    func setEnabled(_ on: Bool) {
        if on {
            guard server == nil else { return }
            let s = LiveSocketServer(path: socketPath) { req in await MCPLiveService.shared.handle(req) }
            do {
                try s.start()
                server = s
                lastError = nil
                DiagnosticsLog.shared.log("mcp", "Listening for Claude on \(socketPath)")
            } catch {
                lastError = error.description
                DiagnosticsLog.shared.log("mcp", "Could not start: \(error.description)")
            }
            ClaudeIntegration.shared.refresh()
        } else {
            server?.stop()
            server = nil
            DiagnosticsLog.shared.log("mcp", "Stopped")
            ClaudeIntegration.shared.refresh()
        }
    }

    func handle(_ req: JSONValue) async -> JSONValue {
        // Design with Claude: the bottom bar pill shows the call while it runs and lists it afterwards.
        let tool = req["op"]?.stringValue == "call" ? req["tool"]?.stringValue : nil
        if let tool { ClaudeIntegration.shared.begin(tool) }
        let reply = await LiveProtocol.reply(to: req, backend: toolbox) {
            ["app": "Arcus", "version": .string(AppVersionInfo.current.marketingVersion),
             "documents": .array(NSApp.orderedDocuments.compactMap { $0 as? ArcusDocument }.map { d in
                 ["name": .string(d.displayName ?? ""), "path": d.fileURL.map { .string($0.path) } ?? .null,
                  "furniture": .bool(d.session.model.isFurniture), "front": .bool(d === host.target)]
             })]
        }
        if let tool {
            ClaudeIntegration.shared.finish(tool, document: host.documentName, result: reply["result"].flatMap(ToolResult.init(json:)) ?? .error(reply["error"]?.stringValue ?? ""))
        }
        return reply
    }
}

/// Live mode's documents: the document Claude last made or opened while it is open, else the frontmost one.
@MainActor
final class AppDocumentHost: DocumentHost {
    let backendName = "live"
    private weak var pinned: ArcusDocument?

    var target: ArcusDocument? {
        if let p = pinned, NSDocumentController.shared.documents.contains(where: { $0 === p }) { return p }
        return NSApp.orderedDocuments.compactMap { $0 as? ArcusDocument }.first
            ?? NSDocumentController.shared.documents.compactMap { $0 as? ArcusDocument }.first
    }
    var session: DocumentSession? { target?.session }
    var documentURL: URL? { target?.fileURL }
    var documentName: String { target?.displayName ?? "" }

    func adopt(_ model: BIMModel, name: String) throws(ToolError) {
        let doc = ArcusDocument(model: model, displayName: name)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        doc.updateChangeCount(.changeDone)
        pinned = doc
    }

    func open(_ url: URL) throws(ToolError) {
        if let open = NSDocumentController.shared.document(for: url) as? ArcusDocument {
            open.showWindows()
            pinned = open
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No file at \(url.path).") }
        let type = (url.pathExtension == ArcusPackage.furnitureFileExtension ? UTType.arcusFurniture : UTType.arcusProject).identifier
        do {
            let doc = try NSDocumentController.shared.makeDocument(withContentsOf: url, ofType: type)
            guard let ad = doc as? ArcusDocument else { throw ToolError("“\(url.lastPathComponent)” isn't an Arcus document.") }
            NSDocumentController.shared.addDocument(ad)
            ad.makeWindowControllers()
            ad.showWindows()
            pinned = ad
        } catch let e as ToolError {
            throw e
        } catch {
            throw ToolError("Arcus could not open “\(url.lastPathComponent)”: \(error.localizedDescription)")
        }
    }

    func save(to url: URL?) async throws(ToolError) -> URL {
        guard let doc = target else { throw ToolError("No document is open in Arcus. Call create_project or open_document.") }
        guard let dest = url ?? doc.fileURL else {
            throw ToolError("“\(doc.displayName ?? "This document")” hasn't been saved yet. Pass path, e.g. ~/Documents/Arcus/\(doc.displayName ?? "Untitled").\(FileDocumentHost.fileExtension(doc.session.model)).")
        }
        let op: NSDocument.SaveOperationType = url == nil || url == doc.fileURL ? .saveOperation : .saveAsOperation
        let type = ArcusDocument.documentType(doc.session.model).identifier
        let error: (any Error)? = await withCheckedContinuation { cont in
            doc.save(to: dest, ofType: type, for: op) { cont.resume(returning: $0) }
        }
        if let error { throw ToolError("Arcus could not save to \(dest.path): \(error.localizedDescription)") }
        return dest
    }
}
