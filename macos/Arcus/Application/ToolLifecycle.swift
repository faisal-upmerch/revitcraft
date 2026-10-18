import Foundation
import ArcusGeometry
import ArcusDomain

// BL-KEYS: tool lifecycle rules shared by the keyboard, the context menus and the ribbon: two-stage Esc, Repeat and
// Recent Commands, the Modify pre-selection flow, Select All scope, where tool options are shown and which Modify tool
// settings are remembered, and Find Referring Views.

/// What one Esc (or context-menu Cancel) did.
public enum EscapeOutcome: Sendable, Equatable {
    /// The current step was cancelled (open chain, pending second point, Move preview); the tool stays active.
    case cancelledStep
    /// The tool ended; back to Modify with the selection kept.
    case exitedTool
    /// In Modify: the selection was cleared (Select Previous restores it).
    case clearedSelection
    /// Nothing to cancel.
    case none
}

@MainActor
public enum ToolLifecycle {
    /// Two-stage cancel. Stage 1 cancels the tool's current step; stage 2 exits the tool; in Modify the selection is
    /// cleared. Sketch mode never ends on Esc (only Finish or Cancel Edit Mode end it).
    public static func escape(tool: (any InteractiveTool)?, selection: SelectionModel) -> EscapeOutcome {
        guard let tool else {
            guard !selection.isEmpty else { return .none }
            selection.clear()
            return .clearedSelection
        }
        let r = tool.escape()
        if tool.isSketchMode { return .cancelledStep }
        return r == .exitTool ? .exitedTool : .cancelledStep
    }

    /// Commands that act on a selection and, run with nothing selected, first let the user select elements and then
    /// continue with Enter or Finish (the Modify pre-selection flow).
    public static let preselectionCommands: Set<CommandID> = [.move, .copy, .rotate, .mirrorPickAxis, .mirrorDrawAxis, .array, .scale,
                                                               .pin, .unpin, .delete]

    /// Whether Repeat, Enter in Modify and Recent Commands offer a command: tools that create or modify elements.
    /// View navigation, undo, clipboard, selection, snap overrides, dialogs and file commands are left out.
    public static func isRepeatable(_ id: CommandID) -> Bool {
        let excluded: Set<CommandID> = [.modify, .selectAll, .selectAllInstancesInView, .selectAllInstancesInProject, .selectByCategory, .filterSelection,
                                        .selectPrevious, .finishSketch, .cancelSketch, .typeProperties, .undo, .redo, .cut, .copyClipboard, .paste,
                                        .pasteAlignedSameLevel, .pasteAlignedSelectedLevels, .pasteAlignedCurrentView, .snapsOff, .snapEndpoint,
                                        .snapMidpoint, .snapIntersection, .snapNearest, .snapCenter, .snapPerpendicular, .snapTangent, .snapQuadrant,
                                        .snapWorkPlaneGrid, .snapPoints, .snapRemote, .snapClose, .snapOverrideOff, .repeatLastCommand,
                                        .finishEditGroup, .editGroup, .ungroup, .arrayNumber, .familyEditor, .findReferringViews,
                                        .hideCategoryInView, .hideByFilter, .overrideByCategory, .overrideByFilter, .viewProperties]
        if excluded.contains(id) { return false }
        switch CommandCatalog.info(id).group {
        case .build, .structure, .annotate, .modify: return true
        case .view: return [.section, .elevation, .callout, .cameraView, .scopeBox].contains(id)
        case .insert, .manage, .file, .app: return false
        }
    }

    /// Recent Commands: the most recent repeatable commands, newest first, without duplicates.
    public static func recentRepeatable(_ recent: [CommandID], limit: Int = 5) -> [CommandID] {
        var seen = Set<CommandID>()
        return Array(recent.filter { isRepeatable($0) && seen.insert($0).inserted }.prefix(limit))
    }

    /// Repeat [command]: the last repeatable command.
    public static func lastRepeatable(_ recent: [CommandID]) -> CommandID? { recent.first(where: isRepeatable) }
}

/// ⌘A on the canvas (an Arcus extension; there is no model Select All in mainstream BIM tools). It selects the model
/// elements visible in the view; view markers, datums, scope boxes, cameras, links and annotations are never included.
/// Views without model elements (drafting views, legends, sheets) select their detail and annotation elements instead,
/// still without view markers.
public enum SelectAllScope {
    public static func filter(_ ids: [ElementID], in model: BIMModel) -> [ElementID] {
        let elements = ids.compactMap { model[$0] }
        let modelOnly = elements.filter { isModelTarget($0.category) }
        let chosen = modelOnly.isEmpty ? elements.filter { isAnnotationTarget($0.category) } : modelOnly
        return chosen.map(\.id)
    }

    static func isModelTarget(_ c: Category) -> Bool { c.isModel && ![.importedCAD, .ifcReference].contains(c) }

    static func isAnnotationTarget(_ c: Category) -> Bool {
        c.isAnnotation && ![.sectionMarks, .elevationMarks, .callouts].contains(c)
    }
}

/// Where the active tool's options are shown, following the 2026 arrangement of mainstream BIM tools: Modify-tool
/// options (Move/Copy/Rotate/Mirror/Array/Scale), Tag on Placement, tag orientation and leader, dimension Prefer/Pick
/// and a level's Make Plan Views sit on the contextual ribbon; placement values (wall height, location line, chain,
/// offset, join status, sill height, …) stay on the floating Options Bar.
public enum ToolOptionPlacement {
    static let modifyTools: Set<CommandID> = [.move, .copy, .rotate, .mirrorPickAxis, .mirrorDrawAxis, .array, .scale]
    static let dimensionTools: Set<CommandID> = [.alignedDimension, .linearDimension, .angularDimension, .radialDimension, .diameterDimension, .arcLengthDimension]
    static let tagTools: Set<CommandID> = [.tagByCategory, .roomTag, .multiCategoryTag, .areaTag]

    /// Option ids of `tool` shown on the ribbon (the Options Bar shows the rest, except the draw mode).
    public static func ribbonOptionIDs(_ tool: CommandID) -> Set<String> {
        if modifyTools.contains(tool) { return ["constrain", "multiple", "disjoin", "copy", "arrayMode", "associate", "count", "last", "scaleMethod"] }
        if dimensionTools.contains(tool) { return ["pref", "pick"] }
        if tagTools.contains(tool) { return ["orientation", "leader", "length"] }
        switch tool {
        case .door, .window, .room, .area: return ["tag"]
        case .level: return ["plans"]
        default: return []
        }
    }

    public static func isOnRibbon(_ option: ToolOption, of tool: CommandID) -> Bool { ribbonOptionIDs(tool).contains(option.id) }

    /// The contextual ribbon panel title for a tool's options.
    public static func panelTitle(_ tool: CommandID) -> String {
        if dimensionTools.contains(tool) { return "Dimension" }
        if tagTools.contains(tool) { return "Tag" }
        switch tool {
        case .move: return "Move"
        case .copy: return "Copy"
        case .rotate: return "Rotate"
        case .mirrorPickAxis, .mirrorDrawAxis: return "Mirror"
        case .array: return "Array"
        case .scale: return "Scale"
        case .door, .window, .room, .area: return "Tag"
        case .level: return "Plan Views"
        default: return "Options"
        }
    }

    /// While a Modify tool runs, the contextual tab keeps the selection's name ("Modify | Walls").
    public static func keepsSelectionTab(_ tool: CommandID) -> Bool { modifyTools.contains(tool) || [.pin, .unpin, .delete].contains(tool) }
}

/// Last-used Modify tool settings (Constrain, Multiple, Disjoin, Copy, array mode/number/…, scale method), remembered
/// across launches per user. Only simple values of the Modify tools' ribbon options are kept.
@MainActor
public final class ModifyToolSettings {
    public static let shared = ModifyToolSettings(defaults: .standard)
    let defaults: UserDefaults
    static let key = "modifyToolSettings.v1"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    private var stored: [String: [String: String]] {
        get { (defaults.dictionary(forKey: Self.key) as? [String: [String: String]]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    static func remembered(_ tool: CommandID) -> Bool { ToolOptionPlacement.modifyTools.contains(tool) }

    /// Remembers the current values of the tool's ribbon options.
    public func record(_ tool: any InteractiveTool) {
        guard Self.remembered(tool.commandID) else { return }
        let ids = ToolOptionPlacement.ribbonOptionIDs(tool.commandID)
        var values: [String: String] = [:]
        for o in tool.options where ids.contains(o.id) {
            switch o.kind {
            case .bool: values[o.id] = (o.value.boolValue ?? false) ? "1" : "0"
            case .choice: if let t = o.value.textValue { values[o.id] = "t:" + t }
            case .integer: if let n = o.value.intValue { values[o.id] = "i:\(n)" }
            default: break
            }
        }
        var s = stored
        s[tool.commandID.rawValue] = values
        stored = s
    }

    /// Applies remembered values to a newly started tool.
    public func restore(into tool: any InteractiveTool) {
        guard Self.remembered(tool.commandID), let values = stored[tool.commandID.rawValue] else { return }
        // Mode-like choices first: they can change which other options exist.
        for (id, v) in values.sorted(by: { ($0.value.hasPrefix("t:") ? 0 : 1, $0.key) < ($1.value.hasPrefix("t:") ? 0 : 1, $1.key) }) {
            if v == "1" || v == "0" { tool.setOption(id, .bool(v == "1")) }
            else if v.hasPrefix("t:") { tool.setOption(id, .text(String(v.dropFirst(2)))) }
            else if v.hasPrefix("i:"), let n = Int(v.dropFirst(2)) { tool.setOption(id, .int(n)) }
        }
    }
}

/// Find Referring Views: the views (plans, sections, elevations, 3D, drafting and legends) whose display list shows
/// the element. Pure function of a model snapshot, so it can run off the main actor.
public enum ReferringViews {
    public static func find(_ id: ElementID, in model: BIMModel, isCancelled: @escaping @Sendable () -> Bool = { false }) -> [ElementID] {
        guard let e = model[id] else { return [] }
        var out: [ElementID] = []
        for v in model.views where v.view != nil {
            if isCancelled() { break }
            if let owner = e.ownerViewID, owner != v.id { continue }
            let g = ViewGraphicsBuilder(model: model, view: v, isCancelled: isCancelled).build()
            if g.items.contains(where: { $0.elementID == id }) { out.append(v.id) }
        }
        return out.sorted { (model[$0]?.name ?? "").localizedStandardCompare(model[$1]?.name ?? "") == .orderedAscending }
    }
}
