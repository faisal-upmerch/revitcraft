import Foundation
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// MCP: where the tools' document lives (Docs/MCP.md §2). File mode keeps one DocumentSession in the server process;
// the app's live host (ArcusUI, MCPLiveService.swift) wraps its NSDocuments.

/// The document a tool works on, and how documents are made, opened and saved.
@MainActor
public protocol DocumentHost: AnyObject {
    /// "file" or "live".
    var backendName: String { get }
    /// The document tools edit, or nil when none is open.
    var session: DocumentSession? { get }
    var documentURL: URL? { get }
    var documentName: String { get }
    /// Makes `model` the current document (file mode: replaces it; live mode: opens a new window).
    func adopt(_ model: BIMModel, name: String) throws(ToolError)
    func open(_ url: URL) throws(ToolError)
    /// Saves to `url` (Save As) or the current location. Returns where it was saved.
    func save(to url: URL?) async throws(ToolError) -> URL
}

/// An actionable tool failure: the message Claude sees.
public struct ToolError: Error, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// File mode: one document in this process, read and written as an `.arcus` / `.arcusfurniture` package.
@MainActor
public final class FileDocumentHost: DocumentHost {
    public let backendName = "file"
    public private(set) var session: DocumentSession?
    public private(set) var documentURL: URL?
    public private(set) var documentName = ""
    public var appVersion = "1.0.0"

    public init() {}

    public func adopt(_ model: BIMModel, name: String) throws(ToolError) {
        let s = DocumentSession(model: model)
        // No run loop drives undo grouping here; the toolbox opens one group per tool call.
        s.undoManager.groupsByEvent = false
        session = s
        documentURL = nil
        documentName = name
    }

    public func open(_ url: URL) throws(ToolError) {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError("No file at \(url.path).") }
        let model: BIMModel
        do { model = try ArcusPackage.read(from: url).model } catch {
            throw ToolError("“\(url.lastPathComponent)” could not be opened: \(error.localizedDescription)")
        }
        try adopt(model, name: url.deletingPathExtension().lastPathComponent)
        documentURL = url
    }

    public func save(to url: URL?) async throws(ToolError) -> URL {
        guard let session else { throw ToolError("No document is open. Call create_project, create_furniture or open_document first.") }
        guard let target = url ?? documentURL else {
            throw ToolError("This document hasn't been saved yet. Pass path, e.g. ~/Documents/Arcus/\(documentName.isEmpty ? "Untitled" : documentName).\(Self.fileExtension(session.model)).")
        }
        let model = session.model
        let thumb = Thumbnail.png(model)
        let info = ArcusPackage.WriteInfo(appVersion: appVersion, build: "mcp", thumbnailPNG: thumb)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Write beside the target, then swap, so a failed write never leaves half a package.
            let tmp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString)")
            try ArcusPackage.write(model, to: tmp, info: info)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }
        } catch {
            throw ToolError("Could not save to \(target.path): \(error.localizedDescription)")
        }
        documentURL = target
        documentName = target.deletingPathExtension().lastPathComponent
        return target
    }

    public static func fileExtension(_ model: BIMModel) -> String {
        model.isFurniture ? ArcusPackage.furnitureFileExtension : "arcus"
    }
}
