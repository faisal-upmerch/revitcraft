import Foundation
import ArcusDomain
import ArcusApplication
import ArcusMCP

// AICORE: what the agent needs from a document window: the tools it may call (the MCP tool layer, in process), their
// risk, a compact context summary, the selection, and one undo step per prompt.

/// The kind of document the assistant works in (the system prompt and tool set follow it).
public enum AIDocumentKind: String, Codable, Sendable, CaseIterable {
    case project, furniture, family

    public var title: String {
        switch self {
        case .project: "Architectural project"
        case .furniture: "Furniture document"
        case .family: "Family"
        }
    }
}

/// How much a tool call can change (owner's risk policy: ask before files, large deletes and project-wide changes).
public enum AIToolRisk: String, Sendable, Hashable {
    case read, edit, destructive, projectWide, file
}

/// One selected element, shown as a chip in the composer and sent with the prompt when "Use selection" is on.
public struct AISelectionChip: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var category: String
    public init(id: Int, title: String, category: String) { self.id = id; self.title = title; self.category = category }
}

/// Groups every edit of one prompt into a single undo step, and undoes it from the reply's Undo button.
@MainActor
public protocol AIUndoControlling: AnyObject {
    /// Opens the prompt's group (called before the first editing tool call).
    func begin() async
    /// Closes the group under `name` ("AI: Add drawers"). When the prompt changed nothing the group is dropped, so no
    /// empty step is left on the undo stack.
    func end(_ name: String, changed: Bool)
    var isOpen: Bool { get }
    /// True while the step is the next one ⌘Z would undo.
    func canUndo(_ name: String) -> Bool
    func undo(_ name: String)
}

/// The agent's view of a document window.
@MainActor
public protocol AIToolHost: AnyObject {
    var documentKind: AIDocumentKind { get }
    var documentName: String { get }
    /// "feet and inches", "millimeters", "inches".
    var unitsDescription: String { get }
    /// The tools offered to the model, in a fixed order (the order is part of the cached prefix).
    var toolSpecs: [ToolSpec] { get }
    func risk(of tool: String) -> AIToolRisk
    func call(_ name: String, arguments: [String: JSONValue]) async -> ToolResult
    /// A compact summary of the model and the active view (sent at the start of every prompt).
    func contextSummary() async -> String
    func selection() -> [AISelectionChip]
    var undo: any AIUndoControlling { get }
    /// Counts changes, so the agent knows whether a prompt edited anything.
    var changeCount: Int { get }
}

/// The prompt's undo group on an `UndoManager` (a DocumentSession's or the Family Editor's). Event grouping is
/// paused while the prompt runs, so every tool call's own group nests inside this one: ⌘Z undoes the whole prompt.
@MainActor
public final class PromptUndoGroup: AIUndoControlling {
    let manager: () -> UndoManager?
    private var open = false
    private var savedGroupsByEvent = true
    private var closed: [String: Marker] = [:]

    /// Registered last in a closed group. Undo runs it first (the group is now undone); redo runs it last, so it
    /// also restores the group's name over the names the tools' own steps set while redoing.
    final class Marker {
        var undone = false
    }

    public init(_ manager: @escaping () -> UndoManager?) { self.manager = manager }

    public var isOpen: Bool { open }

    public func begin() async {
        guard !open, let um = manager() else { return }
        // An event-driven group still open from this run loop pass would wrap ours; let it close first.
        var tries = 0
        while um.groupingLevel > 0 && um.groupsByEvent && tries < 20 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            tries += 1
        }
        savedGroupsByEvent = um.groupsByEvent
        um.groupsByEvent = false
        um.beginUndoGrouping()
        open = true
    }

    static func registerMarker(_ m: Marker, _ um: UndoManager, name: String, undone: Bool) {
        um.registerUndo(withTarget: m) { m in
            MainActor.assumeIsolated {
                m.undone = !undone
                registerMarker(m, um, name: name, undone: !undone)
                if undone { um.setActionName(name) } // redoing: the last action of the redo, so the name sticks
            }
        }
    }

    public func end(_ name: String, changed: Bool) {
        guard open else { return }
        open = false
        guard let um = manager() else { return }
        if um.groupingLevel > 0 {
            if changed {
                let m = Marker()
                Self.registerMarker(m, um, name: name, undone: false)
                closed[name] = m
                um.setActionName(name)
            }
            um.endUndoGrouping()
            // A prompt whose calls changed nothing leaves an empty group; undoing an empty group drops it silently.
            if !changed && um.canUndo && um.undoActionName.isEmpty { um.undo() }
        }
        um.groupsByEvent = savedGroupsByEvent
    }

    public func canUndo(_ name: String) -> Bool {
        guard !open, let um = manager(), let m = closed[name] else { return false }
        return !m.undone && um.canUndo && um.undoActionName == name
    }

    public func undo(_ name: String) {
        guard canUndo(name), let um = manager() else { return }
        um.undo()
    }
}

/// The tool host for a DocumentSession (project or Furniture document) over `ArcusToolbox`.
@MainActor
public final class ToolboxAIHost: AIToolHost {
    public let toolbox: ArcusToolbox
    public var selectionProvider: () -> [AISelectionChip]
    public var activeViewName: () -> String?
    public private(set) lazy var undo: any AIUndoControlling = PromptUndoGroup { [weak self] in self?.toolbox.host.session?.undoManager }

    public init(toolbox: ArcusToolbox, selection: @escaping () -> [AISelectionChip] = { [] }, activeView: @escaping () -> String? = { nil }) {
        self.toolbox = toolbox
        selectionProvider = selection
        activeViewName = activeView
    }

    var session: DocumentSession? { toolbox.host.session }
    public var documentKind: AIDocumentKind { session?.model.isFurniture == true ? .furniture : .project }
    public var documentName: String { toolbox.host.documentName }
    public var unitsDescription: String {
        guard let m = session?.model else { return "" }
        if m.isFurniture { return "inches (plain numbers are inches)" }
        return m.units.system == .imperial ? "feet and inches (plain numbers are feet)" : "millimeters (plain numbers are mm)"
    }
    public var changeCount: Int { session?.changeCounter ?? 0 }

    /// Tools the assistant never offers: they replace the document (the sidebar belongs to this one) or undo outside
    /// the prompt's undo step (the reply's Undo button does that).
    public static let hidden: Set<String> = ["create_project", "create_furniture", "open_document", "undo", "redo"]
    /// Building tools that mean nothing in a Furniture document.
    static let projectOnly: Set<String> = ["add_level", "add_grid", "create_walls", "place_doors", "place_windows", "create_floor", "create_ceiling",
                                           "create_roof", "add_stair", "add_railing", "place_rooms", "place_components", "set_project_info"]

    public var toolSpecs: [ToolSpec] {
        let furniture = documentKind == .furniture
        return ArcusToolCatalog.all.filter { s in
            if Self.hidden.contains(s.name) { return false }
            if furniture { return !Self.projectOnly.contains(s.name) }
            return !s.name.contains("furniture")
        }
    }

    public func risk(of tool: String) -> AIToolRisk {
        AIRiskPolicy.risk(of: ArcusToolCatalog.all.first { $0.name == tool }, name: tool)
    }

    public func call(_ name: String, arguments: [String: JSONValue]) async -> ToolResult {
        await toolbox.callTool(name, arguments: arguments)
    }

    public func contextSummary() async -> String {
        if ArcusToolCatalog.all.contains(where: { $0.name == "context_summary" }) {
            let r = await toolbox.callTool("context_summary", arguments: [:])
            if !r.isError { return withSelectionAndView(r.text) }
        }
        // Until the tool layer has context_summary: status plus the model summary.
        let status = await toolbox.callTool("arcus_status", arguments: [:])
        let summary = await toolbox.callTool("query_model", arguments: ["what": "summary"])
        return withSelectionAndView([status.text, summary.text].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private func withSelectionAndView(_ s: String) -> String {
        var out = s
        if let v = activeViewName() { out += "\nActive view: \(v)" }
        return out
    }

    public func selection() -> [AISelectionChip] { selectionProvider() }
}

/// The owner's risk policy for tool calls.
public enum AIRiskPolicy {
    /// Deleting more than this many elements asks first.
    public static let smallDelete = 5

    /// A tool's risk class. Uses the tool layer's own class when it has one; otherwise derives it from the annotations.
    public static func risk(of spec: ToolSpec?, name: String) -> AIToolRisk {
        if ["save", "export_pdf", "export_dwg"].contains(name) { return .file }
        if ["set_project_info"].contains(name) { return .projectWide }
        guard let spec else { return .edit }
        if spec.destructive { return .destructive }
        if spec.readOnly { return .read }
        return .edit
    }

    /// The question to ask before running a call, or nil to run it at once.
    public static func confirmation(tool: String, title: String, risk: AIToolRisk, arguments: [String: JSONValue], documentName: String) -> AIConfirmation? {
        switch risk {
        case .read, .edit:
            return nil
        case .destructive:
            let ids = arguments["elements"]?.arrayValue ?? arguments["ids"]?.arrayValue ?? []
            if !ids.isEmpty && ids.count <= smallDelete { return nil }
            let n = ids.isEmpty ? "these elements" : "\(ids.count) elements"
            return AIConfirmation(title: "Delete \(n)?", message: "The assistant wants to delete \(n) (and what depends on them, such as their doors and tags). You can undo it.", action: "Delete", destructive: true)
        case .projectWide:
            return AIConfirmation(title: "Change project-wide settings?", message: "\(title) changes settings for the whole \(documentName.isEmpty ? "project" : "“\(documentName)”")." + detail(arguments), action: "Change")
        case .file:
            let path = arguments["path"]?.stringValue ?? arguments["folder"]?.stringValue
            switch tool {
            case "save":
                return AIConfirmation(title: path == nil ? "Save “\(documentName)”?" : "Save a copy?", message: path.map { "Saves to \(abbreviate($0)). An existing file there is replaced." } ?? "Saves the document over its file.", action: "Save")
            default:
                return AIConfirmation(title: "\(title)?", message: path.map { "Writes \(abbreviate($0)). An existing file there is replaced." } ?? "Writes files on your Mac.", action: "Export")
            }
        }
    }

    static func detail(_ a: [String: JSONValue]) -> String {
        let pairs = a.keys.sorted().prefix(6).compactMap { k -> String? in
            guard let v = a[k] else { return nil }
            return "\(k.replacingOccurrences(of: "_", with: " ")): \(v.stringValue ?? v.jsonText)"
        }
        return pairs.isEmpty ? "" : " " + pairs.joined(separator: "; ") + "."
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        let p = (path as NSString).expandingTildeInPath
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

/// An inline confirmation card's text.
public struct AIConfirmation: Codable, Sendable, Hashable {
    public var title: String
    public var message: String
    public var action: String
    public var destructive = false
    public init(title: String, message: String, action: String, destructive: Bool = false) {
        self.title = title; self.message = message; self.action = action; self.destructive = destructive
    }
}
