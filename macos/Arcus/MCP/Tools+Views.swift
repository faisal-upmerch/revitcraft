import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: views and sheets beyond create_views/create_sheet: duplicate views, view properties (scale, detail level,
// crop, view range, discipline…), view templates, Visibility/Graphics and filters, placing views on existing sheets,
// title block fields, revisions, duplicate sheets and sheet sets.

extension ArcusToolCatalog {
    static let overrideSchema = S.object(["visible": S.bool(), "color": S.str("#RRGGBB lines and surface"), "line_weight": S.int("1–16"), "halftone": S.bool(),
                                          "transparency": S.num("0–100"), "surface_color": S.str("#RRGGBB solid fill")])
    static let viewTools: [ToolSpec] = [
        ToolSpec("duplicate_view", "Duplicate View", "Duplicate a view: duplicate (model only), with_detailing (copies its dimensions, tags, text), or dependent (follows the parent, with its own crop).",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["view": S.ref("Default the active view"), "mode": S.oneOf(["duplicate", "with_detailing", "dependent"], "Default duplicate"), "name": S.str()]),
        ToolSpec("set_view_properties", "View Properties",
                 "Change a view's Properties: name, scale (1:n, e.g. 48 = 1/4\"), detail level, visual style, discipline, crop on/off/visible, crop region (rect or around elements with margin), annotation crop, view range (cut plane, top, bottom, depth as offsets from the level), title on sheet. " + lengthNote,
                 risk: .edit, group: .views, modes: .model,
                 properties: ["view": S.ref(), "name": S.str(), "scale": S.int(), "detail_level": S.oneOf(["coarse", "medium", "fine"]),
                              "visual_style": S.oneOf(["wireframe", "hidden_line", "shaded", "consistent_colors", "realistic"]), "discipline": S.oneOf(["architectural", "structural", "coordination"]),
                              "crop": S.bool(), "crop_visible": S.bool(), "crop_region": S.points("[[x0,y0],[x1,y1]]"), "crop_to_elements": S.ids(), "crop_margin": S.len(),
                              "annotation_crop": S.bool(), "cut_plane": S.len(), "top": S.len(), "bottom": S.len(), "depth": S.len(), "title_on_sheet": S.str()]),
        ToolSpec("apply_view_template", "View Template", "Apply a view template to views (or remove it with template 'none'), or create one from a view (create_from) to apply to others.",
                 risk: .projectWide, group: .views, modes: .model,
                 properties: ["template": S.ref("Template name or id, or 'none'"), "views": S.array(S.ref(), "Default the active view"), "create_from": S.ref("Make a template from this view"), "name": S.str("Name for create_from")]),
        ToolSpec("set_visibility_graphics", "Visibility/Graphics",
                 "Visibility/Graphics Overrides for a view: show/hide categories and override their color, line weight, halftone, transparency or surface fill; or override elements (Override Graphics in View by Element). E.g. {categories:{furniture:{halftone:true}, rooms:{visible:false}}}.",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["view": S.ref(), "categories": S.object([:], "{category: override}"), "elements": S.ids("Elements for element_override"), "element_override": overrideSchema,
                              "reset": S.bool("Clear this view's overrides first")]),
        ToolSpec("add_view_filter", "View Filter", "Create a rule-based filter (categories + parameter rules) and add it to views with visibility and graphic override, e.g. walls whose Fire Rating equals 1 HR shown red.",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["name": S.str(), "categories": S.array(S.str()), "rules": S.array(S.object(["parameter": S.str(), "op": S.oneOf(["equals", "not_equals", "greater", "less", "contains", "begins_with", "has_value"]), "value": S.anyValue], required: ["parameter"])),
                              "match_all": S.bool("Default true"), "views": S.array(S.ref(), "Default the active view"), "override": overrideSchema],
                 required: ["name", "categories"]),
        ToolSpec("place_on_sheet", "Place on Sheet", "Place views, legends or schedules on an existing sheet (position [u, v] as fractions of the paper, else the next free spot), or move a view that's already on the sheet.",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["sheet": S.ref("Sheet number or name"), "views": S.array(S.object(["view": S.ref(), "position": S.array(S.num())], required: ["view"]))], required: ["sheet", "views"]),
        ToolSpec("set_sheet_info", "Sheet Properties", "Title block fields and properties of sheets: number, name, drawn/checked/designed/approved by, issue date, title block type, appears in sheet list. sheets default to all when only by/date fields are given.",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["sheets": S.array(S.ref()), "number": S.str(), "name": S.str(), "drawn_by": S.str(), "checked_by": S.str(), "designed_by": S.str(), "approved_by": S.str(),
                              "issue_date": S.str(), "title_block": S.ref(), "in_sheet_list": S.bool()]),
        ToolSpec("add_revision", "Revision", "Add a revision (sequence, date, description, issued to/by) and show it on sheets (their revision schedules list it).",
                 risk: .edit, group: .views, modes: .model,
                 properties: ["description": S.str(), "date": S.str(), "issued_to": S.str(), "issued_by": S.str(), "issued": S.bool(), "sheets": S.array(S.ref(), "Sheets to add it to")],
                 required: ["description"]),
        ToolSpec("duplicate_sheet", "Duplicate Sheet", "Duplicate a sheet with its title block (and with_detailing: its views duplicated with their annotations, placed the same way).",
                 risk: .edit, group: .views, modes: .model, properties: ["sheet": S.ref(), "with_detailing": S.bool(), "number": S.str(), "name": S.str()], required: ["sheet"]),
        ToolSpec("create_sheet_set", "Sheet Set", "Save a named set of sheets (and views) for printing and PDF export (export_pdf {sheet_set}).",
                 risk: .edit, group: .views, modes: .model, properties: ["name": S.str(), "sheets": S.array(S.ref(), "Default all sheets")], required: ["name"]),
    ]
}

extension ArcusToolbox {
    static let viewHandlers: [String: ToolHandler] = [
        "duplicate_view": { b, c in try b.duplicateView(c) },
        "set_view_properties": { b, c in try b.setViewProperties(c) },
        "apply_view_template": { b, c in try b.applyViewTemplate(c) },
        "set_visibility_graphics": { b, c in try b.setVisibilityGraphics(c) },
        "add_view_filter": { b, c in try b.addViewFilter(c) },
        "place_on_sheet": { b, c in try b.placeOnSheet(c) },
        "set_sheet_info": { b, c in try b.setSheetInfo(c) },
        "add_revision": { b, c in try b.addRevision(c) },
        "duplicate_sheet": { b, c in try b.duplicateSheet(c) },
        "create_sheet_set": { b, c in try b.createSheetSet(c) },
    ]

    // MARK: Views

    func duplicateView(_ c: ToolContext) throws -> ToolOutput {
        let e = try c.viewOrActive(allowSchedules: true)
        let m = try c.model()
        let mode = c.args.string("mode")?.lowercased() ?? "duplicate"
        var created: ElementID?
        try c.edit("Duplicate View") { tx in
            if let sched = e.schedule {
                created = tx.create(.schedules, name: c.args.string("name") ?? BrowserNaming.duplicateViewName(e, in: tx.model), data: .schedule(sched)); return
            }
            guard var vd = e.view else { throw TransactionError("“\(e.name)” can't be duplicated.") }
            var name = c.args.string("name") ?? BrowserNaming.duplicateViewName(e, in: tx.model)
            if mode == "dependent" {
                vd.parentViewID = e.id
                vd.cropActive = true
                if vd.cropRegion == nil { vd.cropRegion = Self.modelExtents(m) }
                if c.args.string("name") == nil { name = BrowserNaming.dependentName(of: e.name) { BrowserNaming.viewNameTaken($0, kind: vd.kind, in: tx.model) } }
            }
            let nv = tx.create(.views, name: name, data: .view(vd), levelID: e.levelID)
            created = nv
            if mode == "with_detailing" { ElementOperations.copy(tx.model.owned(byView: e.id).map(\.id), by: .identity, in: tx, viewID: e.id, targetView: nv) }
        }
        let nm = try c.model()
        if let created { _ = (host as? any DocumentUIHost)?.activateView(created) }
        return result(c, ["view": created?.json ?? .null, "name": .string(created.flatMap { nm[$0]?.name } ?? ""),
                          "annotations": .int(created.map { nm.owned(byView: $0).count } ?? 0)], ids: created.map { [$0] } ?? [])
    }

    func setViewProperties(_ c: ToolContext) throws -> ToolOutput {
        let e = try c.viewOrActive()
        let m = try c.model()
        guard var vd = e.view else { throw ToolError("“\(e.name)” is not a view.") }
        let a = c.args
        var name = e.name
        if let n = a.string("name") {
            if let problem = BrowserNaming.renameProblem(e.id, to: n, in: m) { throw ToolError(problem) }
            name = n
        }
        if let s = a.int("scale") { guard s >= 1, s <= 20_000 else { throw ToolError("scale must be 1…20000.") }; vd.scale = s }
        if let d = a.string("detail_level") { guard let v = DetailLevel.allCases.first(where: { $0.rawValue.lowercased() == d.lowercased() }) else { throw ToolError("detail_level: coarse, medium or fine.") }; vd.detailLevel = v }
        if let v = a.string("visual_style") {
            let k = v.lowercased().replacingOccurrences(of: "_", with: " ")
            guard let s = VisualStyle.allCases.first(where: { $0.rawValue.lowercased() == k || $0.rawValue.lowercased().hasPrefix(k.prefix(6)) }) else {
                throw ToolError("visual_style: \(VisualStyle.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            vd.visualStyle = s
        }
        if let d = a.string("discipline") { guard let v = Discipline.allCases.first(where: { $0.rawValue.lowercased() == d.lowercased() }) else { throw ToolError("discipline: architectural, structural or coordination.") }; vd.discipline = v }
        if let b = a["crop"]?.boolValue { vd.cropActive = b }
        if let b = a["crop_visible"]?.boolValue { vd.cropVisible = b }
        if let b = a["annotation_crop"]?.boolValue { vd.annotationCropActive = b }
        if let r = a["crop_region"] { let p = try c.points(r, "crop_region"); vd.cropRegion = Rect2(points: p); vd.cropActive = true }
        if a["crop_to_elements"] != nil {
            let ids = try c.elementIDs("crop_to_elements")
            let margin = try c.length("crop_margin") ?? 2 * (try c.unitStep())
            guard let box = Self.box(of: ids, m) else { throw ToolError("Those elements have no extents.") }
            vd.cropRegion = vd.kind.isPlan ? Rect2(min: box.min.xy - Vec2(margin, margin), max: box.max.xy + Vec2(margin, margin)) : vd.cropRegion
            vd.cropActive = true
        }
        if vd.kind.isPlan {
            var vr = vd.viewRange
            if let v = try c.length("cut_plane") { vr.cutOffset = v }
            if let v = try c.length("top") { vr.topOffset = v }
            if let v = try c.length("bottom") { vr.bottomOffset = v }
            if let v = try c.length("depth") { vr.depthOffset = v }
            guard vr.topOffset >= vr.cutOffset, vr.cutOffset >= vr.bottomOffset else {
                throw ToolError("View range must be top ≥ cut plane ≥ bottom (now \(c.formatLength(vr.topOffset, m)) / \(c.formatLength(vr.cutOffset, m)) / \(c.formatLength(vr.bottomOffset, m))).")
            }
            vd.viewRange = vr
        } else if ["cut_plane", "top", "bottom", "depth"].contains(where: { a[$0] != nil }) {
            throw ToolError("View range applies to plan views; “\(e.name)” is a \(vd.kind.rawValue.lowercased()).")
        }
        if let t = a.string("title_on_sheet") { vd.titleOnSheet = t }
        if let tid = vd.templateID, let t = m[tid]?.viewTemplate {
            let locked = ViewTemplates.Setting.allCases.filter { ViewTemplates.controls(t, $0) }
            let changedLocked = (a["scale"] != nil && locked.contains(.scale)) || (a["detail_level"] != nil && locked.contains(.detailLevel)) || (a["visual_style"] != nil && locked.contains(.visualStyle))
            if changedLocked { throw ToolError("“\(e.name)” uses the view template “\(m[tid]?.name ?? "")”, which controls that setting. Remove the template (apply_view_template {template:'none'}) or edit the template.") }
        }
        let final = vd
        try c.edit("View Properties") { tx in tx.update(e.id) { $0.name = name; $0.view = final } }
        return result(c, ["view": e.id.json, "name": .string(name), "scale": .int(final.scale), "detail_level": .string(final.detailLevel.rawValue), "crop": .bool(final.cropActive)], ids: [e.id])
    }

    func applyViewTemplate(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var template: ElementID?
        if let src = c.args["create_from"] {
            let v = try c.view(src, what: "create_from")
            guard let vd = v.view else { throw ToolError("create_from must be a view.") }
            let name = c.args.string("name") ?? "\(vd.kind.rawValue) - \(v.name)"
            if m.elements(.viewTemplates).contains(where: { $0.name == name }) { throw ToolError("A view template named “\(name)” exists.") }
            let r = try c.edit("Create View Template") { tx in tx.create(.viewTemplates, name: name, data: .viewTemplate(ViewTemplates.make(from: vd))) }
            template = ToolContext.created(r).first
        } else if let t = c.args.string("template"), t.lowercased() == "none" {
            template = nil
        } else if let tv = c.args["template"] {
            let all = m.elements(.viewTemplates)
            guard let t = all.first(where: { $0.name.caseInsensitiveCompare(tv.stringValue ?? "") == .orderedSame || $0.id.raw == UInt64(max(0, tv.intValue ?? -1)) })
                ?? all.first(where: { $0.name.localizedCaseInsensitiveContains(tv.stringValue ?? "\u{0}") }) else {
                throw ToolError("No view template “\(tv.stringValue ?? tv.jsonText)”. Templates: \(all.map(\.name).joined(separator: ", ")). create_from makes one.")
            }
            template = t.id
        } else { throw ToolError("Give template (name, id or 'none') or create_from.") }
        var views: [Element] = []
        if let list = c.args.array("views") { for (k, v) in list.enumerated() { views.append(try c.view(v, what: "views[\(k)]")) } }
        else if c.args["create_from"] == nil { views = [try c.viewOrActive("__none__")] }
        let nm = try c.model()
        if let t = template, let td = nm[t]?.viewTemplate {
            for v in views where !ViewTemplates.compatible(td, with: v.view?.kind ?? .floorPlan) { throw ToolError("Template “\(nm[t]?.name ?? "")” is for \(td.appliesTo.rawValue) views; “\(v.name)” is a \(v.view?.kind.rawValue ?? "view").") }
        }
        if !views.isEmpty { try c.edit("Apply View Template") { tx in for v in views { try ViewTemplates.assign(template, to: v.id, in: tx) } } }
        return result(c, ["template": template?.json ?? .null, "name": .string(template.flatMap { nm[$0]?.name } ?? "none"), "views": .array(views.map { .string($0.name) })], ids: views.map(\.id))
    }

    static func color(_ s: String?) throws(ToolError) -> RGBColor? {
        guard var s else { return nil }
        let named: [String: UInt32] = ["red": 0xE02020, "green": 0x20A040, "blue": 0x2060E0, "black": 0x000000, "gray": 0x808080, "grey": 0x808080, "orange": 0xF08020, "yellow": 0xE0C000, "purple": 0x8040C0]
        if let n = named[s.lowercased()] { return RGBColor(hex: n) }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { throw ToolError("Colors are #RRGGBB or red/green/blue/black/gray/orange/yellow/purple.") }
        return RGBColor(hex: v)
    }

    static func override(_ v: JSONValue?) throws(ToolError) -> GraphicOverride {
        var o = GraphicOverride()
        guard let v = v?.objectValue else { return o }
        if let col = try color(v["color"]?.stringValue) { o.projectionLineColor = col; o.cutLineColor = col }
        if let w = v["line_weight"]?.intValue { guard (1...16).contains(w) else { throw ToolError("line_weight must be 1…16.") }; o.projectionLineWeight = w; o.cutLineWeight = w }
        if let h = v["halftone"]?.boolValue { o.halftone = h }
        if let t = v["transparency"]?.doubleValue { guard (0...100).contains(t) else { throw ToolError("transparency must be 0…100.") }; o.transparency = t / 100 }
        if let sc = try color(v["surface_color"]?.stringValue) { o.surfaceColor = sc; o.surfacePattern = .solid }
        return o
    }

    func setVisibilityGraphics(_ c: ToolContext) throws -> ToolOutput {
        let view = try c.viewOrActive()
        var changes: [(Category, Bool?, GraphicOverride)] = []
        for (name, v) in c.args["categories"]?.objectValue ?? [:] {
            changes.append((try Self.category(name), v["visible"]?.boolValue, try Self.override(v)))
        }
        let elementIDs = c.args["elements"] != nil ? try c.elementIDs("elements") : []
        let eo = try Self.override(c.args["element_override"])
        guard !changes.isEmpty || !elementIDs.isEmpty || c.args.bool("reset", default: false) else { throw ToolError("Give categories {name: {visible, color, halftone…}} and/or elements with element_override.") }
        let reset = c.args.bool("reset", default: false)
        try c.edit("Visibility/Graphics") { tx in
            tx.update(view.id) { e in
                guard var vg = e.view?.visibility else { return }
                if reset { vg.categoryOverrides = [:]; vg.elementOverrides = [:]; vg.hiddenCategories = [] }
                for (cat, vis, o) in changes {
                    if let vis { if vis { vg.hiddenCategories.remove(cat) } else { vg.hiddenCategories.insert(cat) } }
                    if !o.isEmpty { vg.categoryOverrides[cat] = (vg.categoryOverrides[cat] ?? GraphicOverride()).merged(with: o) }
                }
                for id in elementIDs { vg.elementOverrides[id] = eo.isEmpty ? nil : (vg.elementOverrides[id] ?? GraphicOverride()).merged(with: eo) }
                e.view?.visibility = vg
            }
        }
        let vd = try c.model()[view.id]?.view
        var o: [String: JSONValue] = ["view": .string(view.name), "hidden_categories": .array((vd?.visibility.hiddenCategories ?? []).map { .string($0.rawValue) }.sorted { $0.stringValue! < $1.stringValue! }),
                                      "overridden_categories": .int(vd?.visibility.categoryOverrides.count ?? 0), "overridden_elements": .int(vd?.visibility.elementOverrides.count ?? 0)]
        if let t = vd?.templateID { o["note"] = .string("The view uses template \(t.raw); if it controls V/G Overrides the template's settings win.") }
        return result(c, o, ids: [view.id])
    }

    func addViewFilter(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let name = try c.args.requireString("name")
        if m.elements(.filters).contains(where: { $0.name == name }) { throw ToolError("A filter named “\(name)” exists.") }
        let cats = try (c.args.requireArray("categories")).compactMap(\.stringValue).map { s throws(ToolError) in try Self.category(s) }
        let params = FilterEvaluation.parameters(for: cats, m)
        var rules: [FilterRule] = []
        for (k, r) in (c.args.array("rules") ?? []).enumerated() {
            guard let pn = r["parameter"]?.stringValue else { throw ToolError("rules[\(k)] needs parameter.") }
            guard let p = params.first(where: { $0.name.caseInsensitiveCompare(pn) == .orderedSame }) else {
                throw ToolError("rules[\(k)]: no parameter “\(pn)” common to these categories. Parameters: \(params.prefix(30).map(\.name).joined(separator: ", ")).")
            }
            let op: FilterRule.Op = switch r["op"]?.stringValue?.lowercased() ?? "equals" {
            case "not_equals", "!=": .notEquals
            case "greater", ">": .greater
            case "less", "<": .less
            case "contains": .contains
            case "begins_with": .beginsWith
            case "has_value": .hasValue
            default: .equals
            }
            var value: ParamValue = .text("")
            if let v = r["value"] {
                if case .length = p.type, let d = v.doubleValue { value = .double(d * ToolContext.unitScale(m).meters) } else {
                    let text = v.stringValue ?? v.doubleValue.map { String($0) } ?? v.jsonText
                    do { value = try Parameters.parse(text, type: p.type, model: m) } catch { value = .text(text) }
                }
            }
            rules.append(FilterRule(parameter: p.id, op: op, value: value))
        }
        var views: [Element] = []
        if let list = c.args.array("views") { for (k, v) in list.enumerated() { views.append(try c.view(v, what: "views[\(k)]")) } } else { views = [try c.viewOrActive()] }
        let o = try Self.override(c.args["override"])
        let visible = c.args["override"]?["visible"]?.boolValue ?? true
        let matchAll = c.args.bool("match_all", default: true)
        var fid: ElementID?
        try c.edit("View Filter") { tx in
            let f = tx.create(.filters, name: name, data: .filter(ViewFilterData(categories: cats, rules: rules, matchAll: matchAll)))
            fid = f
            for v in views { tx.update(v.id) { $0.view?.visibility.filters.append(AppliedFilter(filterID: f, visible: visible, override: o)) } }
        }
        let nm = try c.model()
        let matches = fid.flatMap { nm[$0]?.viewFilter }.map { f in cats.flatMap { nm.elements($0) }.filter { !$0.isType && FilterEvaluation.matches(f, $0, nm) }.count } ?? 0
        return result(c, ["filter": fid?.json ?? .null, "matches": .int(matches), "views": .array(views.map { .string($0.name) })], ids: fid.map { [$0] } ?? [],
                      problems: matches == 0 ? ["The filter matches no elements yet; check the rule values."] : [])
    }

    // MARK: Sheets

    func sheet(_ v: JSONValue?, _ m: BIMModel, what: String = "sheet") throws(ToolError) -> Element {
        guard let v else { throw ToolError("Missing \(what).") }
        let s = v.stringValue ?? v.intValue.map(String.init) ?? ""
        if let e = m.sheets.first(where: { $0.sheet?.number.caseInsensitiveCompare(s) == .orderedSame || $0.name.caseInsensitiveCompare(s) == .orderedSame || String($0.id.raw) == s }) { return e }
        throw ToolError("No sheet “\(s)”. Sheets: \(m.sheets.map { "\($0.sheet?.number ?? "") \($0.name)" }.joined(separator: ", ")).")
    }

    func placeOnSheet(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let sh = try sheet(c.args["sheet"], m)
        let paper = sh.sheet?.paper.landscapeSize ?? Vec2(0.84, 0.59)
        var plans: [(Element, Vec2?)] = []
        for (k, v) in try c.args.requireArray("views").enumerated() {
            guard let vv = v["view"] else { throw ToolError("views[\(k)] needs view.") }
            let e: Element
            if let s = vv.stringValue, let sc = m.schedules.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { e = sc } else { e = try c.view(vv, what: "views[\(k)].view") }
            var pos: Vec2?
            if let p = v["position"]?.arrayValue, p.count == 2, let u = p[0].doubleValue, let w = p[1].doubleValue {
                guard (0...1).contains(u), (0...1).contains(w) else { throw ToolError("views[\(k)].position must be fractions 0–1.") }
                pos = Vec2(u * paper.x, w * paper.y)
            }
            if e.schedule == nil, let vp = m.viewports(showing: e.id).first, vp.ownerViewID != sh.id {
                throw ToolError("“\(e.name)” is on sheet \(m[vp.ownerViewID]?.sheet?.number ?? ""). A view goes on one sheet; duplicate_view first.")
            }
            plans.append((e, pos))
        }
        var placed: [ElementID] = []
        try c.edit("Place View") { tx in
            for (e, pos) in plans {
                if let vp = tx.model.viewports(showing: e.id).first(where: { $0.ownerViewID == sh.id }), e.schedule == nil {
                    if let pos { tx.update(vp.id) { $0.viewport?.center = pos } }
                    placed.append(vp.id)
                } else {
                    placed.append(try SheetPlacement.place(e.id, onSheet: sh.id, at: pos, in: tx))
                }
            }
        }
        let nm = try c.model()
        let problems = DrawingCheck.problems(nm[sh.id] ?? sh, nm).problems.filter { $0.code.hasPrefix("sheet.") && $0.code != "sheet.empty_fields" }.map(\.message)
        return result(c, ["sheet": .string(sh.sheet?.number ?? ""), "viewports": .array(placed.map(\.json))], ids: placed, problems: problems)
    }

    func setSheetInfo(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let a = c.args
        var sheets: [Element] = []
        if let list = a.array("sheets") { for v in list { sheets.append(try sheet(v, m, what: "sheets[]")) } } else {
            guard a["number"] == nil, a["name"] == nil else { throw ToolError("Give sheets (one sheet) to change its number or name.") }
            if let id = activeViewID, let s = m[id], s.sheet != nil, a["drawn_by"] == nil && a["issue_date"] == nil { sheets = [s] } else { sheets = m.sheets }
        }
        guard !sheets.isEmpty else { throw ToolError("The document has no sheets.") }
        if a["number"] != nil, sheets.count > 1 { throw ToolError("number can only be set on one sheet at a time.") }
        if let n = a.string("number"), m.sheets.contains(where: { $0.sheet?.number == n && $0.id != sheets[0].id }) { throw ToolError("Sheet number \(n) is taken.") }
        let tb = try a["title_block"].map { try c.type($0, category: .titleBlocks, what: "title_block") }
        try c.edit("Sheet Properties") { tx in
            for s in sheets {
                tx.update(s.id) { e in
                    if let v = a.string("name") { e.name = v }
                    guard var sd = e.sheet else { return }
                    if let v = a.string("number") { sd.number = v }
                    if let v = a.string("drawn_by") { sd.drawnBy = v }
                    if let v = a.string("checked_by") { sd.checkedBy = v }
                    if let v = a.string("designed_by") { sd.designedBy = v }
                    if let v = a.string("approved_by") { sd.approvedBy = v }
                    if let v = a.string("issue_date") { sd.issueDate = v }
                    if let v = a["in_sheet_list"]?.boolValue { sd.appearsInSheetList = v }
                    e.sheet = sd
                }
                if let tb { try SheetTitleBlocks.setTitleBlock(tb.id, on: s.id, in: tx) }
            }
        }
        let nm = try c.model()
        let remaining = sheets.compactMap { nm[$0.id] }.flatMap { DrawingCheck.problems($0, nm).problems.filter { $0.code == "sheet.empty_fields" || $0.code == "sheet.no_title_block" } }.map(\.message)
        return result(c, ["sheets": .array(sheets.compactMap { nm[$0.id] }.map { .string("\($0.sheet?.number ?? "") \($0.name)") })], ids: sheets.map(\.id), problems: Array(Set(remaining)).sorted())
    }

    func addRevision(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let desc = try c.args.requireString("description")
        var sheets: [Element] = []
        for v in c.args.array("sheets") ?? [] { sheets.append(try sheet(v, m, what: "sheets[]")) }
        let seq = (m.elements(.revisions).compactMap { $0.revisionData?.sequence }.max() ?? 0) + 1
        let date = c.args.string("date") ?? ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        var rid: ElementID?
        try c.edit("Revision") { tx in
            var rd = RevisionData(sequence: seq, date: date, description: desc)
            if let v = c.args.string("issued_to") { rd.issuedTo = v }
            if let v = c.args.string("issued_by") { rd.issuedBy = v }
            if let v = c.args["issued"]?.boolValue { rd.issued = v }
            let r = tx.create(.revisions, name: "Revision \(seq)", data: .revision(rd))
            rid = r
            for s in sheets { tx.update(s.id) { $0.sheet?.additionalRevisionIDs.append(r) } }
        }
        return result(c, ["revision": rid?.json ?? .null, "sequence": .int(seq), "date": .string(date), "sheets": .array(sheets.map { .string($0.sheet?.number ?? "") })], ids: rid.map { [$0] } ?? [])
    }

    func duplicateSheet(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let sh = try sheet(c.args["sheet"], m)
        var nid: ElementID?
        try c.edit("Duplicate Sheet") { tx in
            let id = try SheetDuplication.duplicate(sh.id, withDetailing: c.args.bool("with_detailing", default: false), in: tx)
            nid = id
            if let n = c.args.string("number") {
                guard !tx.model.sheets.contains(where: { $0.sheet?.number == n && $0.id != id }) else { throw TransactionError("Sheet number \(n) is taken.") }
                tx.update(id) { $0.sheet?.number = n }
            }
            if let n = c.args.string("name") { tx.update(id) { $0.name = n } }
        }
        let nm = try c.model()
        return result(c, ["sheet": nid?.json ?? .null, "number": .string(nid.flatMap { nm[$0]?.sheet?.number } ?? ""), "views": .int(nid.map { nm.owned(byView: $0).filter { $0.viewport != nil }.count } ?? 0)],
                      ids: nid.map { [$0] } ?? [])
    }

    func createSheetSet(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let name = try c.args.requireString("name")
        var members: [ElementID] = []
        if let list = c.args.array("sheets") { for v in list { members.append(try sheet(v, m, what: "sheets[]").id) } } else { members = m.sheets.map(\.id) }
        guard !members.isEmpty else { throw ToolError("No sheets to put in the set.") }
        try c.edit("Sheet Set") { tx in
            var sets = tx.model.viewSheetSets.filter { $0.name != name }
            sets.append(ViewSheetSet(name: name, members: members))
            tx.setViewSheetSets(sets)
        }
        return result(c, ["set": .string(name), "sheets": .int(members.count)], ids: [])
    }
}
