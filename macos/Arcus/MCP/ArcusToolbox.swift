import Foundation
import ArcusDomain
import ArcusApplication

// MCP: runs Arcus tools against a DocumentHost. The same toolbox serves file mode (arcus-mcp) and live mode (the app),
// so a tool behaves the same in both (Docs/MCP.md §1).

/// What a handler returns: the JSON result and optional image blocks.
public struct ToolOutput: Sendable {
    public var json: JSONValue
    public var images: [JSONValue] = []
    public init(_ json: JSONValue, images: [JSONValue] = []) { self.json = json; self.images = images }
}

/// AITOOLS: a tool's implementation.
public typealias ToolHandler = @MainActor @Sendable (ArcusToolbox, ToolContext) async throws -> ToolOutput

@MainActor
public final class ArcusToolbox: ToolBackend {
    public let host: any DocumentHost
    /// The DWG writer (`arcus-dwg`), when bundled.
    public var dwgHelper: URL?
    /// Extra status lines (the router adds whether the app is reachable).
    public var statusExtras: () -> [String: JSONValue] = { [:] }
    /// AITOOLS: the Family Editor's family when its window is in front (the in-app assistant's adapter over
    /// FamilyEditorModel). Asked before the host's own `familyHost`.
    public var familyHostProvider: (() -> (any FamilyEditingHost)?)?

    public init(host: any DocumentHost, dwgHelper: URL? = nil) {
        self.host = host
        self.dwgHelper = dwgHelper
    }

    static let readOnly: Set<String> = Set(ArcusToolCatalog.all.filter(\.readOnly).map(\.name))
    /// Tools that make or replace the document (not undoable steps on it).
    static let documentLevel: Set<String> = ["create_project", "create_furniture", "create_family", "open_document", "save", "undo", "redo"]

    // MARK: Mode

    /// The family being edited, when the front document is a family.
    public var familyHost: (any FamilyEditingHost)? { familyHostProvider?() ?? (host as? any DocumentUIHost)?.familyHost }

    /// The kind of the front document.
    public var mode: DocumentMode {
        if familyHost != nil { return .family }
        guard let m = host.session?.model else { return .none }
        return m.isFurniture ? .furniture : .project
    }

    /// The active view, when the host has one (file mode: the last view a tool opened or worked in).
    public var activeViewID: ElementID? {
        guard let id = (host as? any DocumentUIHost)?.activeViewID, host.session?.model[id] != nil else { return nil }
        return id
    }

    /// The active view and selection as the catalog filters them.
    public var catalogContext: ToolCatalogContext {
        let m = host.session?.model
        let v = activeViewID.flatMap { m?[$0] }
        return ToolCatalogContext(viewKind: v?.view?.kind, isSheet: v?.sheet != nil, isSchedule: v?.schedule != nil,
                                  hasSelection: !(host.session?.selection.isEmpty ?? true))
    }

    /// The tools that apply to the front document now (the in-app assistant's tool list).
    public func availableTools(filterByView: Bool = false) -> [ToolSpec] {
        ArcusToolCatalog.tools(for: mode, context: filterByView ? catalogContext : nil)
    }

    /// AITOOLS: the risk of one call, which can be higher than the tool's class (type parameters, deleting many,
    /// commands that save or purge).
    public static func risk(of name: String, arguments: [String: JSONValue]) -> ToolRisk {
        let base = ArcusToolCatalog.spec(name)?.risk ?? .edit
        switch name {
        case "set_parameters": return arguments["type"]?.boolValue == true ? .projectWide : base
        case "run_command":
            guard let s = arguments["command"]?.stringValue, let id = CommandResolver.resolve(s) else { return .edit }
            return CommandResolver.risk(id)
        case "set_family_type": return arguments["delete"] != nil ? .destructive : base
        default: return base
        }
    }

    // MARK: Calls

    public func callTool(_ name: String, arguments: [String: JSONValue]) async -> ToolResult {
        let ctx = ToolContext(host: host, args: ToolArgs(arguments))
        ctx.toolbox = self
        ctx.groupsUndo = !Self.documentLevel.contains(name) // read-only tools never edit, so they never open a group
        if let spec = ArcusToolCatalog.spec(name) {
            if !spec.modes.isEmpty, !spec.modes.contains(mode) { return .error(Self.modeMessage(spec, mode)) }
            // AITOOLS: required arguments first, so the message names what to give.
            let missing = spec.requiredNames.filter { ctx.args[$0] == nil }
            if !missing.isEmpty {
                return .error("Missing \(missing.map { "“\($0)”" }.joined(separator: " and ")). \(name) needs \(spec.requiredNames.joined(separator: ", ")); see its schema.")
            }
        }
        // One undo step per call, opened by its first edit; nests inside the assistant's prompt group.
        defer {
            if ctx.undoGroupOpen, let um = host.session?.undoManager {
                // Named while the group is open: the menu then reads "Undo Create Walls".
                if let title = ArcusToolCatalog.spec(name)?.title { um.setActionName(title) }
                um.endUndoGrouping()
            }
        }
        do {
            let out = try await handle(name, ctx)
            var content: [JSONValue] = [["type": "text", "text": .string(out.json.jsonText)]]
            content += out.images
            return ToolResult(content: content)
        } catch let e as ToolError {
            return .error(e.message)
        } catch let e as TransactionError {
            return .error(e.message + (e.resolution.map { " " + $0 } ?? ""))
        } catch {
            return .error("\(error)")
        }
    }

    /// Why a tool doesn't apply to the front document, and what to do instead.
    static func modeMessage(_ spec: ToolSpec, _ mode: DocumentMode) -> String {
        let label: [DocumentMode: String] = [.project: "project", .furniture: "Furniture", .family: "Family Editor", .none: "no"]
        let wants = spec.modes.map { label[$0] ?? $0.rawValue }.sorted().joined(separator: " or ")
        switch mode {
        case .none: return "\(spec.name) needs an open \(wants) document. Call create_project, create_furniture or open_document first."
        case .family: return "\(spec.name) works in \(wants) documents; the front window is the Family Editor. Use the family tools (family_info, add_family_parameter, add_form…), or load_family_into_project."
        default: return "\(spec.name) works in \(wants) documents; the front document is a \(label[mode] ?? mode.rawValue) document. \(mode == .furniture ? "Use the furniture tools (add_furniture_parts, add_fronts…)." : "Use create_furniture for a piece of furniture.")"
        }
    }

    func handle(_ name: String, _ c: ToolContext) async throws -> ToolOutput {
        switch name {
        case "arcus_status": return try status(c)
        case "create_project": return try await createProject(c)
        case "create_furniture": return try await createFurniture(c)
        case "open_document": return try openDocument(c)
        case "save": return try await save(c)
        case "set_project_info": return try setProjectInfo(c)
        case "add_level": return try addLevels(c)
        case "add_grid": return try addGrids(c)
        case "create_walls": return try createWalls(c)
        case "place_doors": return try placeInserts(c, doors: true)
        case "place_windows": return try placeInserts(c, doors: false)
        case "create_floor": return try createFloor(c)
        case "create_ceiling": return try createCeiling(c)
        case "create_roof": return try createRoof(c)
        case "add_stair": return try addStair(c)
        case "add_railing": return try addRailing(c)
        case "place_rooms": return try placeRooms(c)
        case "place_components": return try placeComponents(c)
        case "set_parameters": return try setParameters(c)
        case "move_elements": return try moveElements(c)
        case "delete_elements": return try deleteElements(c)
        case "undo": return try undoRedo(c, undo: true)
        case "redo": return try undoRedo(c, undo: false)
        case "create_views": return try createViews(c)
        case "create_sheet": return try createSheet(c)
        case "create_schedule": return try createSchedule(c)
        case "add_dimensions": return try addDimensions(c)
        case "add_tags": return try addTags(c)
        case "query_model": return try query(c)
        case "list_types": return try listTypes(c)
        case "list_families": return try listFamilies(c)
        case "render_view": return try renderView(c)
        case "export_pdf": return try await exportPDF(c)
        case "export_dwg": return try exportDWG(c)
        case "set_furniture_size": return try setFurnitureSize(c)
        case "add_furniture_parts": return try addFurnitureParts(c)
        default:
            guard let h = Self.handlers[name] else { throw ToolError("Unknown tool \(name).") }
            return try await h(self, c)
        }
    }

    /// AITOOLS: the batch's handlers by tool name (Tools+*.swift).
    static let handlers: [String: ToolHandler] = [contextHandlers, architectureHandlers, annotationHandlers, viewHandlers, scheduleHandlers,
                                                  exportHandlers, familyHandlers, furnitureHandlers, editHandlers, selectionHandlers,
                                                  navigationHandlers, checkHandlers, commandHandlers]
        .reduce(into: [:]) { $0.merge($1) { a, _ in a } }

    /// `path` argument with `~` expanded, made absolute.
    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    /// Adds the checks, the unit and the verification block to an editing result. `problems` are the tool's own
    /// findings (a dimension that overlaps, a part that doesn't flex…).
    func result(_ c: ToolContext, _ fields: [String: JSONValue], ids: [ElementID], problems: [String] = []) -> ToolOutput {
        var o = fields
        for (k, v) in c.checks(ids) { o[k] = v }
        if let m = host.session?.model { o["unit"] = .string(ToolContext.unitScale(m).symbol) }
        o["verification"] = c.verification(ids: ids, extra: problems)
        return ToolOutput(.object(o))
    }
}
