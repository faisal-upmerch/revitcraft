import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusCAD
import ArcusIFC

// AITOOLS: schedules (read rows, add/remove fields, filters and sorting; furniture and component schedules) and
// exports beyond PDF/DWG: images, IFC, schedule CSV and furniture CNC. Exports never overwrite a file unless
// overwrite is true; otherwise they write "Name (2)".

extension ArcusToolCatalog {
    static let scheduleTools: [ToolSpec] = [
        ToolSpec("get_schedule", "Read Schedule", "The rows of a schedule as a table (headings + cells), with totals. Use it to check counts, areas and costs.",
                 risk: .read, group: .schedules, modes: .model, properties: ["schedule": S.ref("Name or id"), "limit": S.int("Rows, default 100")], required: ["schedule"]),
        ToolSpec("edit_schedule", "Schedule Properties",
                 "Change a schedule: add fields (parameter names, e.g. 'Width', 'Fire Rating', 'Area', or 'Count'), remove fields, filter (field op value), sort and group by fields, itemize or not, grand totals.",
                 risk: .edit, group: .schedules, modes: .model,
                 properties: ["schedule": S.ref(), "add_fields": S.array(S.str()), "remove_fields": S.array(S.str()),
                              "filters": S.array(S.object(["field": S.str(), "op": S.oneOf(["equals", "not_equals", "greater", "less", "contains"]), "value": S.anyValue], required: ["field"])),
                              "clear_filters": S.bool(), "sort_by": S.array(S.str(), "Fields, first = primary"), "group_headers": S.bool("Header row per group of the first sort field"),
                              "itemize": S.bool(), "grand_totals": S.bool(), "name": S.str()],
                 required: ["schedule"]),
    ]
    static let exportTools: [ToolSpec] = [
        ToolSpec("export_image", "Export Image", "Export views or sheets to PNG or JPEG files in a folder (one per view), at a pixel width.",
                 risk: .file, group: .exports, modes: .model,
                 properties: ["views": S.array(S.ref(), "View names/ids or sheet numbers (default the active view)"), "folder": S.str(), "format": S.oneOf(["png", "jpeg"], "Default png"),
                              "width": S.int("Pixels, default 2400"), "overwrite": S.bool("Replace existing files (ask the user first)")], required: ["folder"]),
        ToolSpec("export_ifc", "Export IFC", "Export the model to IFC (IFC4 Reference View or IFC2x3 Coordination View), optionally only what a view shows.",
                 risk: .file, group: .exports, modes: .project,
                 properties: ["path": S.str(".ifc path"), "schema": S.oneOf(["ifc4", "ifc2x3"], "Default ifc4"), "view": S.ref("Only elements visible in this view"),
                              "overwrite": S.bool()], required: ["path"]),
        ToolSpec("export_schedule_csv", "Export Schedule CSV", "Export a schedule's rows to a CSV file (opens in Numbers or Excel).",
                 risk: .file, group: .exports, modes: .model,
                 properties: ["schedule": S.ref(), "path": S.str(".csv path"), "overwrite": S.bool()], required: ["schedule", "path"]),
        ToolSpec("export_cnc", "CNC Export", "Furniture: write CNC files (DXF, or DWG with the bundled engine) per part or per nested sheet, with layers OUTLINE/INNER/DRILL/GROOVE…, plus a CSV cut list.",
                 risk: .file, group: .exports, modes: .furniture,
                 properties: ["folder": S.str(), "layout": S.oneOf(["per_part", "per_sheet"], "Default per_part"), "format": S.oneOf(["dxf", "dwg"], "Default dxf"), "csv": S.bool("Default true")],
                 required: ["folder"]),
    ]
}

extension ArcusToolbox {
    static let scheduleHandlers: [String: ToolHandler] = [
        "get_schedule": { b, c in try b.getSchedule(c) },
        "edit_schedule": { b, c in try b.editSchedule(c) },
    ]
    static let exportHandlers: [String: ToolHandler] = [
        "export_image": { b, c in try b.exportImage(c) },
        "export_ifc": { b, c in try b.exportIFC(c) },
        "export_schedule_csv": { b, c in try b.exportScheduleCSV(c) },
        "export_cnc": { b, c in try b.exportCNC(c) },
    ]

    // MARK: Schedules

    func schedule(_ v: JSONValue?, _ m: BIMModel) throws(ToolError) -> Element {
        guard let v else { throw ToolError("Missing schedule.") }
        if let i = v.intValue, let e = m[ElementID(UInt64(max(0, i)))], e.schedule != nil { return e }
        let s = v.stringValue ?? ""
        if let e = m.schedules.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) ?? m.schedules.first(where: { $0.name.localizedCaseInsensitiveContains(s) }) { return e }
        throw ToolError("No schedule “\(s)”. Schedules: \(m.schedules.map(\.name).joined(separator: ", ")). create_schedule makes one.")
    }

    func getSchedule(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let s = try schedule(c.args["schedule"], m)
        let t = ScheduleEngine.compute(s, m)
        let limit = max(1, c.args.int("limit") ?? 100)
        let rows = t.rows.filter { $0.kind != .blank }
        var o: [String: JSONValue] = ["schedule": .string(s.name), "columns": .array(t.columns.filter { !$0.hidden }.map { .string($0.heading) }),
                                      "rows": .array(rows.prefix(limit).map { r in .array(r.cells.map { .string($0.text) }) }), "row_count": .int(rows.count), "elements": .int(t.elementCount)]
        if rows.count > limit { o["truncated"] = .string("Showing \(limit) of \(rows.count); pass limit.") }
        if t.rows.isEmpty { o["note"] = "The schedule has no rows: nothing in the model matches its categories and filters." }
        return ToolOutput(.object(o))
    }

    /// A schedule field for a parameter name, from the parameters elements of the schedule's categories have.
    func scheduleField(_ name: String, _ def: ScheduleDefinition, _ m: BIMModel) throws(ToolError) -> ScheduleField {
        if name.lowercased() == "count" { var f = ScheduleField(source: .count, heading: "Count", width: 0.012, alignment: .right); f.total = .total; return f }
        let sample = def.categories.flatMap { m.elements($0).filter { !$0.isType }.prefix(3) }
        var known: [String: (ParameterID, ParamType)] = [:]
        for e in sample { for p in Parameters.allEntries(e, m) { known[p.name] = (p.id, p.type) } }
        if let k = known.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
            var f = ScheduleField(source: .parameter(k.value.0), heading: k.key, alignment: k.value.1.isNumeric ? .right : .left)
            if [.area, .volume, .length].contains(k.value.1), k.key != "Width" && k.key != "Height" { f.total = .total }
            return f
        }
        if sample.isEmpty { return ScheduleField(source: .parameter(ParameterID(name.lowercased())), heading: name) }
        throw ToolError("No parameter “\(name)” on \(def.categories.map(\.displayName).joined(separator: ", ")). Parameters: \(known.keys.sorted().prefix(40).joined(separator: ", ")).")
    }

    func editSchedule(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let s = try schedule(c.args["schedule"], m)
        guard var def = s.schedule else { throw ToolError("Not a schedule.") }
        if def.kind.isFabrication, c.args["add_fields"] != nil { throw ToolError("“\(s.name)” is a fabrication schedule with fixed fields.") }
        func field(_ name: String) throws(ToolError) -> ScheduleField {
            guard let f = def.fields.first(where: { $0.heading.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ToolError("“\(s.name)” has no field “\(name)”. Fields: \(def.fields.map(\.heading).joined(separator: ", ")).")
            }
            return f
        }
        for n in c.args.array("add_fields")?.compactMap(\.stringValue) ?? [] where !def.fields.contains(where: { $0.heading.caseInsensitiveCompare(n) == .orderedSame }) {
            def.fields.append(try scheduleField(n, def, m))
        }
        for n in c.args.array("remove_fields")?.compactMap(\.stringValue) ?? [] {
            let f = try field(n)
            def.fields.removeAll { $0.id == f.id }
            def.sorting.removeAll { $0.fieldID == f.id }
            def.filters.removeAll { $0.fieldID == f.id }
        }
        if c.args.bool("clear_filters", default: false) { def.filters = [] }
        for (k, fv) in (c.args.array("filters") ?? []).enumerated() {
            guard let fn = fv["field"]?.stringValue else { throw ToolError("filters[\(k)] needs field.") }
            let f = try field(fn)
            let op: FilterRule.Op = switch fv["op"]?.stringValue?.lowercased() ?? "equals" {
            case "not_equals": .notEquals
            case "greater": .greater
            case "less": .less
            case "contains": .contains
            default: .equals
            }
            var value: ParamValue = .text(fv["value"]?.stringValue ?? fv["value"]?.jsonText ?? "")
            if case .parameter(let pid) = f.source, let sample = def.categories.lazy.compactMap({ m.elements($0).first { !$0.isType } }).first,
               let d = Parameters.allEntries(sample, m).first(where: { $0.id == pid }), let text = fv["value"].map({ $0.stringValue ?? $0.jsonText }) {
                value = (try? Parameters.parse(text, type: d.type, model: m)) ?? value
            }
            def.filters.append(ScheduleFilter(fieldID: f.id, op: op, value: value))
        }
        if let sorts = c.args.array("sort_by")?.compactMap(\.stringValue) {
            def.sorting = try sorts.enumerated().map { k, n throws(ToolError) in ScheduleSort(fieldID: try field(n).id, header: k == 0 && c.args.bool("group_headers", default: false)) }
        }
        if let b = c.args["itemize"]?.boolValue { def.itemizeEveryInstance = b }
        if let b = c.args["grand_totals"]?.boolValue { def.grandTotals = b }
        let newName = c.args.string("name")
        if let n = newName, m.schedules.contains(where: { $0.name == n && $0.id != s.id }) { throw ToolError("A schedule named “\(n)” exists.") }
        let final = def
        try c.edit("Schedule Properties") { tx in tx.update(s.id) { $0.schedule = final; if let n = newName { $0.name = n } } }
        let nm = try c.model()
        let t = ScheduleEngine.compute(nm[s.id]!, nm)
        return result(c, ["schedule": .string(nm[s.id]?.name ?? s.name), "fields": .array(final.fields.map { .string($0.heading) }), "rows": .int(t.rows.filter { $0.kind == .data }.count)],
                      ids: [s.id], problems: t.rows.isEmpty ? ["The schedule shows no rows now; check the filters."] : [])
    }

    // MARK: Exports

    /// A destination file that doesn't overwrite unless asked: "Name (2).ext" when it exists.
    static func destination(_ url: URL, overwrite: Bool) -> URL {
        guard !overwrite, FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension, dir = url.deletingLastPathComponent()
        var k = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(base) (\(k)).\(ext)").path) { k += 1 }
        return dir.appendingPathComponent("\(base) (\(k)).\(ext)")
    }

    func exportImage(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let folder = Self.url(try c.args.requireString("folder"))
        var items: [Element] = []
        if let list = c.args.array("views") { for (k, v) in list.enumerated() { items.append(try c.view(v, what: "views[\(k)]", allowSheets: true)) } } else { items = [try c.viewOrActive(allowSheets: true)] }
        let jpeg = c.args.string("format")?.lowercased().hasPrefix("j") == true
        let width = min(max(c.args.int("width") ?? 2400, 200), 10_000)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { throw ToolError("Can't create \(folder.path).") }
        var files: [JSONValue] = []
        for e in items {
            let (g, paper) = graphics(e, m)
            guard !g.items.isEmpty else { throw ToolError("“\(e.name)” shows nothing.") }
            guard let img = RasterExporter.render(g, paper: paper, pixelWidth: width), let data = RasterExporter.encode(img, as: jpeg ? .jpeg : .png) else { throw ToolError("“\(e.name)” could not be rendered.") }
            let title = e.sheet.map { "\($0.number) - \(e.name)" } ?? e.name
            let url = Self.destination(folder.appendingPathComponent(String(DWGExporter.fileName(title).dropLast(4)) + (jpeg ? ".jpg" : ".png")), overwrite: c.args.bool("overwrite", default: false))
            do { try data.write(to: url, options: .atomic) } catch { throw ToolError("Could not write \(url.path).") }
            files.append(["path": .string(url.path), "pixels": [.int(img.width), .int(img.height)]])
        }
        return ToolOutput(["files": .array(files)])
    }

    func exportIFC(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var url = Self.url(try c.args.requireString("path"))
        if url.pathExtension.lowercased() != "ifc" { url = url.appendingPathExtension("ifc") }
        url = Self.destination(url, overwrite: c.args.bool("overwrite", default: false))
        var o = IFCExportOptions()
        o.schema = c.args.string("schema")?.lowercased() == "ifc2x3" ? .ifc2x3 : .ifc4
        if c.args["view"] != nil { o.visibleInViewID = try c.view(c.args["view"]).id }
        o.fileName = url.lastPathComponent
        o.authorName = m.projectInfo.author
        o.organization = m.projectInfo.organization
        let out: (files: [(name: String, data: Data)], report: IFCExportReport)
        do { out = try IFCExporter.export(m, options: o) } catch { throw ToolError("IFC export failed: \(error.localizedDescription)") }
        guard let first = out.files.first else { throw ToolError("IFC export wrote nothing.") }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try first.data.write(to: url, options: .atomic)
        } catch { throw ToolError("Could not write \(url.path).") }
        return ToolOutput(["path": .string(url.path), "schema": .string(o.schema.rawValue), "elements": .int(out.report.exportedElements),
                           "skipped": .int(out.report.skipped.count), "warnings": .array(out.report.warnings.prefix(8).map { .string($0) })])
    }

    func exportScheduleCSV(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let s = try schedule(c.args["schedule"], m)
        var url = Self.url(try c.args.requireString("path"))
        if url.pathExtension.lowercased() != "csv" { url = url.appendingPathExtension("csv") }
        url = Self.destination(url, overwrite: c.args.bool("overwrite", default: false))
        let t = ScheduleEngine.compute(s, m)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ScheduleCSV.export(t).write(to: url, options: .atomic)
        } catch { throw ToolError("Could not write \(url.path).") }
        return ToolOutput(["path": .string(url.path), "rows": .int(t.rows.count)])
    }

    func exportCNC(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let folder = Self.url(try c.args.requireString("folder"))
        let dwg = c.args.string("format")?.lowercased() == "dwg"
        var note: String?
        if dwg && dwgHelper == nil { note = "The DWG engine isn't bundled here; wrote DXF." }
        let o = CNCExport.Options(layout: c.args.string("layout")?.lowercased() == "per_sheet" ? .perSheet : .perPart, format: dwg && dwgHelper != nil ? .dwg : .dxf,
                                  includeCSV: c.args.bool("csv", default: true))
        guard !FurnitureFabrication.parts(m).isEmpty else { throw ToolError("The piece has no parts to cut.") }
        let files: [URL]
        do { files = try CNCExport.write(m, to: folder, options: o, dwgHelper: dwgHelper) } catch { throw ToolError("CNC export failed: \(error.localizedDescription)") }
        var out: [String: JSONValue] = ["files": .int(files.count), "folder": .string(folder.path), "sample": .array(files.prefix(6).map { .string($0.lastPathComponent) })]
        if let note { out["note"] = .string(note) }
        return ToolOutput(.object(out))
    }
}
