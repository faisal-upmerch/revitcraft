import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence

// AITOOLS: what the assistant knows before it acts: context_summary (the system prompt's document section, kept under
// ~1.5k tokens), create_family, and the shared helpers the batch's tools use (active view, element summaries).

extension ArcusToolCatalog {
    static let contextTools: [ToolSpec] = [
        ToolSpec("context_summary", "Context Summary",
                 "Compact summary of the front document: kind, units, active view, levels, selection (ids, categories, types), element counts, sheets and model health. Cheap; call it after a big change to re-orient.",
                 risk: .read, group: .document),
        ToolSpec("create_family", "Create Family",
                 "Start a new family in the Family Editor (file mode: a .arcusfamily document). Templates: generic_model, furniture, casework, door, window, plumbing_fixture, lighting_fixture, specialty_equipment, column, detail_component, generic_annotation, tag, title_block, profile.",
                 risk: .file, group: .document, changesDocument: true,
                 properties: ["name": S.str(), "template": S.str("Default generic_model"), "path": S.str("Optional .arcusfamily path to save to now")],
                 required: ["name"]),
    ]

    static func familyTemplate(_ s: String?) throws(ToolError) -> FamilyTemplate {
        guard let s, !s.isEmpty else { return .genericModel }
        let k = s.lowercased().replacingOccurrences(of: "_", with: " ")
        if let t = FamilyTemplate.allCases.first(where: { $0.rawValue.lowercased() == k || $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == k.replacingOccurrences(of: " ", with: "") }) { return t }
        throw ToolError("template “\(s)”: use one of \(FamilyTemplate.allCases.map { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "_") }.joined(separator: ", ")).")
    }
}

extension ArcusToolbox {
    static let contextHandlers: [String: ToolHandler] = [
        "context_summary": { b, c in ToolOutput(b.contextSummaryJSON()) },
        "create_family": { b, c in try await b.createFamily(c) },
    ]

    // MARK: Context summary

    /// The context summary as one short text for the assistant's system prompt (AICORE puts it there each turn).
    public func contextSummaryText() -> String { contextSummaryJSON()["text"]?.stringValue ?? "" }

    /// The context summary: `text` plus the same facts as fields.
    public func contextSummaryJSON() -> JSONValue {
        var o: [String: JSONValue] = ["mode": .string(mode.rawValue), "backend": .string(host.backendName)]
        var lines: [String] = []
        if let fam = familyHost {
            let f = fam.family
            o["document"] = .string(f.name)
            o["family"] = ["template": .string(f.template.rawValue), "current_type": .string(fam.currentType), "types": .array(f.types.prefix(12).map { .string($0.name) }),
                           "parameters": .array(f.parameters.prefix(30).map { .string($0.name) }), "planes": .array(f.referencePlanes.prefix(30).map { .string($0.name) }),
                           "forms": .int(f.solids.count), "dimensions": .int(f.dimensions.count), "nested": .int(f.nestedInstances.count)]
            lines.append("Family Editor: “\(f.name)” (\(f.template.rawValue) family), type “\(fam.currentType)” of \(f.types.count).")
            lines.append("Parameters: \(f.parameters.prefix(20).map(\.name).joined(separator: ", ")).")
            lines.append("Reference planes: \(f.referencePlanes.prefix(20).map(\.name).joined(separator: ", ")). Forms \(f.solids.count), dimensions \(f.dimensions.count).")
            lines.append("Lengths: \(fam.units.system == .imperial ? "numbers in feet or text like 2'-6\" / 30\"" : "numbers in mm or text like 750 mm").")
            o["text"] = .string(lines.joined(separator: "\n"))
            return .object(o)
        }
        guard let s = host.session else {
            o["text"] = "No document is open. Create or open one first."
            return .object(o)
        }
        let m = s.model
        let unit = ToolContext.unitScale(m).symbol
        o["document"] = .string(host.documentName)
        o["unit"] = .string(unit)
        let kind = m.isFurniture ? "Furniture document" : "Project"
        lines.append("\(kind) “\(host.documentName)”, \(m.isFurniture ? "inches" : m.units.system == .imperial ? "Imperial (numbers in feet; text like 12'-6\")" : "Metric (numbers in mm)").")
        let c = ToolContext(host: host, args: ToolArgs([:]))
        if let v = activeViewID.flatMap({ m[$0] }) {
            let kindName = v.view?.kind.rawValue ?? (v.sheet != nil ? "Sheet" : v.schedule != nil ? "Schedule" : "")
            o["active_view"] = ["id": v.id.json, "name": .string(v.name), "kind": .string(kindName), "scale": v.view.map { .int($0.scale) } ?? .null]
            lines.append("Active view: \(v.sheet.map { "\($0.number) " } ?? "")\(v.name) (\(kindName)\(v.view.map { ", 1:\($0.scale)" } ?? ""), id \(v.id.raw)).")
        }
        if m.isFurniture {
            var size: [String] = []
            for n in ["Width", "Depth", "Height"] { if let v = FurnitureParameters.value(n, m)?.quantityValue { size.append("\(n) \(c.formatLength(v, m))") } }
            lines.append("Size: \(size.joined(separator: ", ")). Planes Left/Right (x), Front/Back (y, front at −y), Bottom/Top (z).")
        } else {
            let levels = m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
            o["levels"] = .array(levels.map { ["id": $0.id.json, "name": .string($0.name), "elevation": c.out($0.level?.elevation ?? 0, m)] })
            lines.append("Levels: \(levels.prefix(12).map { "\($0.name) \(c.formatLength($0.level?.elevation ?? 0, m))" }.joined(separator: ", ")).")
        }
        // Selection.
        let sel = s.selection.ids.compactMap { m[$0] }
        if !sel.isEmpty {
            let byCat = Dictionary(grouping: sel, by: { $0.category })
            o["selection"] = ["count": .int(sel.count), "ids": .array(sel.prefix(40).map(\.id.json)),
                              "categories": .object(byCat.mapValues { .int($0.count) }.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })]
            let shown = sel.prefix(6).map { e in "\(e.id.raw) \(e.category.singularName)\(m.type(of: e).map { " “\(ToolContext.typeLabel($0, m))”" } ?? "")" }
            lines.append("Selected \(sel.count): \(byCat.map { "\($0.value.count) \($0.key.displayName.lowercased())" }.sorted().joined(separator: ", ")) — \(shown.joined(separator: "; "))\(sel.count > 6 ? "…" : "").")
        } else {
            lines.append("Nothing selected.")
        }
        // Counts.
        var counts: [String: JSONValue] = [:]
        let cats: [Category] = m.isFurniture
            ? [.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureEdgeProfiles, .furnitureBays, .furnitureFronts, .furnitureHardware]
            : [.walls, .doors, .windows, .floors, .ceilings, .roofs, .stairs, .railings, .rooms, .columns, .furniture, .casework, .plumbingFixtures, .grids, .dimensions, .tags]
        var countText: [String] = []
        for cat in cats {
            let n = m.elements(cat).filter { !$0.isType }.count
            if n > 0 { counts[cat.rawValue] = .int(n); countText.append("\(n) \(cat.displayName.lowercased())") }
        }
        o["counts"] = .object(counts)
        if !countText.isEmpty { lines.append("Model: \(countText.joined(separator: ", ")).") }
        let sheets = m.sheets.sorted { ($0.sheet?.number ?? "").localizedStandardCompare($1.sheet?.number ?? "") == .orderedAscending }
        o["views"] = .int(m.views.count)
        o["sheets"] = .array(sheets.prefix(20).map { .string("\($0.sheet?.number ?? "") \($0.name)") })
        lines.append("\(m.views.count) views; sheets: \(sheets.isEmpty ? "none" : sheets.prefix(10).map { "\($0.sheet?.number ?? "") \($0.name)" }.joined(separator: ", ")).")
        let health = ModelHealth.check(m)
        o["health"] = .int(health.count)
        if !health.isEmpty { lines.append("Model health: \(health.count) warning(s), e.g. \(health[0].message)") }
        o["text"] = .string(lines.joined(separator: "\n"))
        return .object(o)
    }

    // MARK: Create family

    func createFamily(_ c: ToolContext) async throws -> ToolOutput {
        let name = try c.args.requireString("name")
        let template = try ArcusToolCatalog.familyTemplate(c.args.string("template"))
        var f = StarterFamilies.make(template)
        f.name = name
        guard let fh = host as? FileDocumentHost else {
            throw ToolError("In the app, start a family from Home ▸ Family or File ▸ New ▸ Family; the family tools then work on the Family Editor window.")
        }
        let units = fh.session?.model.units ?? .imperial
        let fam = FileFamilyHost(family: f, units: units)
        fam.project = fh.session
        fh.family = fam
        var o: [String: JSONValue] = ["family": .string(name), "template": .string(template.rawValue), "types": .array(f.types.map { .string($0.name) }),
                                      "planes": .array(f.referencePlanes.map { .string($0.name) }), "parameters": .array(f.parameters.map { .string($0.name) })]
        if let p = c.args.string("path") {
            var url = Self.url(p)
            if url.pathExtension != "arcusfamily" { url = url.deletingPathExtension().appendingPathExtension("arcusfamily") }
            try saveFamily(fam, to: url)
            o["path"] = .string(url.path)
        }
        o["next"] = "add_family_parameter, add_reference_plane, add_form, add_family_dimension (label it with a parameter), then flex_family."
        return ToolOutput(.object(o))
    }

    func saveFamily(_ fam: FileFamilyHost, to url: URL) throws(ToolError) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FamilyPackage.write(fam.family, thumbnailPNG: nil, to: url, appVersion: "1.0.0", build: "mcp")
        } catch { throw ToolError("Could not save the family to \(url.path): \(error.localizedDescription)") }
        fam.url = url
    }
}

/// Starter content for new families (the Family Editor's templates, headless).
enum StarterFamilies {
    static func make(_ t: FamilyTemplate) -> FamilyDefinition {
        var f: FamilyDefinition
        switch t {
        case .door: f = StarterLibrary.singleDoor()
        case .window: f = StarterLibrary.casementWindow()
        case .casework: f = StarterLibrary.baseCabinet()
        case .plumbingFixture: f = StarterLibrary.basin()
        case .tag: f = StarterLibrary.tagFamily("Tag", categories: [.genericModels], label: "Mark", shape: "rect")
        case .titleBlock: f = StarterLibrary.titleBlock("Title Block", width: 0.42, height: 0.297)
        case .genericAnnotation: f = StarterLibrary.northArrow()
        case .profile: f = StarterLibrary.handrailProfile()
        case .detailComponent: f = StarterLibrary.woodBlocking()
        default: f = StarterLibrary.genericBox()
        }
        f.template = t
        f.types = [f.types.first ?? FamilyTypeDefinition(name: "Type 1", values: [:])]
        if t.is3D { f.addTemplateOriginConstraints() }
        return f
    }
}

// MARK: Shared helpers

extension ToolContext {
    /// A view by name or id, or the active view when `key` is missing.
    public func viewOrActive(_ key: String = "view", kinds: Set<ViewKind>? = nil, allowSheets: Bool = false, allowSchedules: Bool = false) throws(ToolError) -> Element {
        let m = try model()
        if let v = args[key] {
            if allowSchedules, let s = v.stringValue, let sc = m.schedules.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return sc }
            return try view(v, what: key, kinds: kinds, allowSheets: allowSheets)
        }
        if let id = toolbox?.activeViewID, let e = m[id] {
            if let kinds, let k = e.view?.kind, kinds.contains(k) { return e }
            if kinds == nil, e.view != nil || (allowSheets && e.sheet != nil) || (allowSchedules && e.schedule != nil) { return e }
        }
        return try view(nil, what: key, kinds: kinds, allowSheets: allowSheets)
    }

    /// Element ids from `key`, or the selection when `key` is missing ("the selected walls").
    public func idsOrSelection(_ key: String = "elements") throws(ToolError) -> [ElementID] {
        if args[key] != nil { return try elementIDs(key) }
        let sel = try session().selection.ids
        guard !sel.isEmpty else { throw ToolError("Give “\(key)” (element ids), or select elements first. get_selection shows the selection; select_elements selects by category.") }
        return sel
    }

    /// The level a view works on, else the lowest.
    public func levelOrViewLevel(_ key: String = "level") throws(ToolError) -> Element {
        if let v = args[key] { return try level(v, key) }
        let m = try model()
        if let id = toolbox?.activeViewID, let l = m[m[id]?.levelID], l.level != nil { return l }
        return try level(nil)
    }

    /// A required array of objects under `key`, or the arguments themselves as one item (`{"point":…}` for `{"items":[…]}`).
    public func items(_ key: String) throws(ToolError) -> [JSONValue] {
        if let a = args.array(key), !a.isEmpty { return a }
        throw ToolError("“\(key)” must be a non-empty array of objects.")
    }

    /// A unit-aware length, else a default.
    public func length(_ key: String, default d: Double) throws(ToolError) -> Double { try length(key) ?? d }

    /// One foot, or 300 mm in Metric projects (meters): the scale of default offsets.
    public func unitStep() throws(ToolError) -> Double {
        let m = try model()
        return m.isFurniture ? 0.0254 * 6 : m.units.system == .imperial ? 0.3048 : 0.3
    }
}
