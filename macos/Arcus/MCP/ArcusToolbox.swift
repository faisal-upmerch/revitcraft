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

@MainActor
public final class ArcusToolbox: ToolBackend {
    public let host: any DocumentHost
    /// The DWG writer (`arcus-dwg`), when bundled.
    public var dwgHelper: URL?
    /// Extra status lines (the router adds whether the app is reachable).
    public var statusExtras: () -> [String: JSONValue] = { [:] }

    public init(host: any DocumentHost, dwgHelper: URL? = nil) {
        self.host = host
        self.dwgHelper = dwgHelper
    }

    static let readOnly: Set<String> = Set(ArcusToolCatalog.all.filter(\.readOnly).map(\.name))
    /// Tools that make or replace the document (not undoable steps on it).
    static let documentLevel: Set<String> = ["create_project", "create_furniture", "open_document", "save", "undo", "redo"]

    public func callTool(_ name: String, arguments: [String: JSONValue]) async -> ToolResult {
        let ctx = ToolContext(host: host, args: ToolArgs(arguments))
        ctx.groupsUndo = !Self.readOnly.contains(name) && !Self.documentLevel.contains(name)
        // One undo step per call, opened by its first edit.
        defer {
            if ctx.undoGroupOpen, let um = host.session?.undoManager {
                // Named while the group is open: the menu then reads "Undo Create Walls".
                if let title = ArcusToolCatalog.all.first(where: { $0.name == name })?.title { um.setActionName(title) }
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
        default: throw ToolError("Unknown tool \(name).")
        }
    }

    /// `path` argument with `~` expanded, made absolute.
    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    /// Adds the checks and unit to an editing result.
    func result(_ c: ToolContext, _ fields: [String: JSONValue], ids: [ElementID]) -> ToolOutput {
        var o = fields
        for (k, v) in c.checks(ids) { o[k] = v }
        if let m = host.session?.model { o["unit"] = .string(ToolContext.unitScale(m).symbol) }
        return ToolOutput(.object(o))
    }
}
