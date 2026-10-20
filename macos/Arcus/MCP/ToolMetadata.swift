import Foundation
import ArcusDomain

// AITOOLS: what each tool is (group, risk, the documents and views it applies to), so the in-app assistant lists only
// the tools that fit the front document and asks before risky ones (Docs/MCP.md §5).

/// What a tool can change. The assistant asks before `destructive`, `projectWide` and `file` calls.
public enum ToolRisk: String, Sendable, CaseIterable, Codable {
    /// Reads the document; changes nothing.
    case read
    /// Adds or changes elements; one undo step.
    case edit
    /// Deletes elements or undoes work.
    case destructive
    /// Changes settings or types that affect the whole document (units, project info, type parameters, templates).
    case projectWide = "project_wide"
    /// Writes, opens or replaces files or documents (save, export, open, new document).
    case file
}

/// Catalog groups, in the order the tools are listed.
public enum ToolGroup: String, Sendable, CaseIterable, Codable {
    case document = "Document"
    case architecture = "Architecture"
    case annotation = "Annotation"
    case views = "Views & Sheets"
    case schedules = "Schedules"
    case exports = "Exports"
    case family = "Family Editor"
    case furniture = "Furniture"
    case edit = "Edit"
    case selection = "Selection"
    case navigation = "Navigation"
    case query = "Query"
    case checks = "Model Checks"
    case commands = "Commands"
}

/// The kind of document a tool works on.
public enum DocumentMode: String, Sendable, CaseIterable, Codable {
    /// No document is open.
    case none
    /// A building project (.arcus).
    case project
    /// A Furniture or Casework document (.arcusfurniture).
    case furniture
    /// A family open in the Family Editor (.arcusfamily).
    case family
}

/// The front document's state that decides which tools apply.
public struct ToolCatalogContext: Sendable, Hashable {
    /// The active view's kind (nil: no view, a sheet or a schedule).
    public var viewKind: ViewKind?
    public var isSheet: Bool
    public var isSchedule: Bool
    public var hasSelection: Bool
    public init(viewKind: ViewKind? = nil, isSheet: Bool = false, isSchedule: Bool = false, hasSelection: Bool = false) {
        self.viewKind = viewKind; self.isSheet = isSheet; self.isSchedule = isSchedule; self.hasSelection = hasSelection
    }
    /// Every tool of the mode, whatever the view and selection.
    public static let any = ToolCatalogContext(viewKind: nil)
}

extension ToolSpec {
    /// Whether the tool applies to `mode` with the front document in `context`.
    public func applies(to mode: DocumentMode, context: ToolCatalogContext?) -> Bool {
        if !modes.isEmpty && !modes.contains(mode) { return false }
        guard let context else { return true }
        if needsSelection && !context.hasSelection { return false }
        if let kinds = viewKinds {
            guard let k = context.viewKind, kinds.contains(k) else { return false }
        }
        return true
    }
}

extension ArcusToolCatalog {
    /// The tools that apply to `mode` (and, when given, to the active view and selection), in catalog order.
    /// The in-app assistant sends only these to keep prompts small.
    public static func tools(for mode: DocumentMode, context: ToolCatalogContext? = nil) -> [ToolSpec] {
        all.filter { $0.applies(to: mode, context: context) }
    }

    /// The spec of a tool by name.
    public static func spec(_ name: String) -> ToolSpec? { byName[name] }
    static let byName: [String: ToolSpec] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    /// Tool counts per group (Docs/MCP.md §5).
    public static var countsByGroup: [(ToolGroup, Int)] {
        ToolGroup.allCases.map { g in (g, all.filter { $0.group == g }.count) }.filter { $0.1 > 0 }
    }
}

/// Mode sets used by the catalog.
extension Set where Element == DocumentMode {
    static let project: Set<DocumentMode> = [.project]
    static let furniture: Set<DocumentMode> = [.furniture]
    static let family: Set<DocumentMode> = [.family]
    /// Documents with a BIM model (projects and furniture).
    static let model: Set<DocumentMode> = [.project, .furniture]
    /// Any open document.
    static let open: Set<DocumentMode> = [.project, .furniture, .family]
}
