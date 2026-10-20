import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: selection (read it, select by query), temporary and permanent hide/isolate, navigation (open a view, zoom,
// orient a 3D view), and the commands fallback (list_commands, run_command) so nothing in the app is out of reach.

extension ArcusToolCatalog {
    static let selectionTools: [ToolSpec] = [
        ToolSpec("get_selection", "Get Selection", "The selected elements with a short summary each (category, type, level, key sizes), and counts by category. Use it when the user says “these”, “the selected walls”.",
                 risk: .read, group: .selection, modes: .model, properties: ["limit": S.int("Default 50")]),
        ToolSpec("select_elements", "Select Elements",
                 "Select elements (the app highlights them; later tools default to the selection): by ids, or by category plus optional type, level, view (visible in it) and parameter filters, e.g. {category:'doors', where:{Width:'36\"'}} or {category:'walls', level:'Level 1', type:'Generic'}.",
                 risk: .read, group: .selection, modes: .model,
                 properties: ["ids": S.ids(), "category": S.str(), "type": S.str("Type name words"), "level": S.ref(), "view": S.ref("Only elements visible in this view ('active' for the active view)"),
                              "where": S.object([:], "{parameter: value} (equal) or {parameter: {op: '>'|'<'|'contains'|'!=', value}}"),
                              "mode": S.oneOf(["replace", "add", "remove", "clear"], "Default replace")]),
        ToolSpec("hide_isolate", "Hide/Isolate",
                 "Temporary Hide/Isolate (the glasses icon; not saved): hide or isolate elements or categories in a view, or reset. permanent: Hide in View / Unhide (saved, undoable). " + selNote,
                 risk: .edit, group: .selection, modes: .model,
                 properties: ["action": S.oneOf(["hide", "isolate", "hide_category", "isolate_category", "reset"]), "elements": S.ids(), "categories": S.array(S.str()),
                              "view": S.ref("Default the active view"), "permanent": S.bool("Hide in View (saved) instead of temporary"), "unhide": S.bool("With permanent: unhide")],
                 required: ["action"]),
    ]
    static let navigationTools: [ToolSpec] = [
        ToolSpec("open_view", "Open View", "Open (activate) a view, sheet or schedule by name, number or id, so the user sees it and later tools default to it.",
                 risk: .read, group: .navigation, modes: .model, properties: ["view": S.ref("View name/id, sheet number or schedule name")], required: ["view"]),
        ToolSpec("zoom_to", "Zoom", "Zoom the active view to elements (Zoom to selection) or to fit everything.",
                 risk: .read, group: .navigation, modes: .model, properties: ["elements": S.ids("Default: fit all")]),
        ToolSpec("set_3d_view", "Orient 3D View",
                 "Orient a 3D view: iso_sw/iso_se/iso_ne/iso_nw, top, front, back, left, right; optionally a section box around elements or a level (or off). Creates the 3D view if `name` is new.",
                 risk: .edit, group: .navigation, modes: .model,
                 properties: ["view": S.ref("3D view (default the active one, or {3D})"), "name": S.str("New 3D view name"),
                              "orientation": S.oneOf(["iso_sw", "iso_se", "iso_ne", "iso_nw", "top", "front", "back", "left", "right"]),
                              "section_box": S.oneOf(["elements", "level", "off"]), "elements": S.ids(), "level": S.ref()]),
    ]
    static let commandTools: [ToolSpec] = [
        ToolSpec("find_tools", "Find Tools", "Find more Arcus tools by words or group (Architecture, Annotation, Views & Sheets, Schedules, Exports, Furniture, Edit, Model Checks…) with their input schemas, e.g. 'curtain grid', 'revision', 'joint'.",
                 risk: .read, group: .commands,
                 properties: ["search": S.str(), "group": S.str(), "limit": S.int("Default 8")]),
        ToolSpec("list_commands", "List Commands",
                 "Every Arcus command (ribbon, menus) with whether it can run now and why not. Search by words. For anything no other tool covers.",
                 risk: .read, group: .commands, properties: ["search": S.str("Words, e.g. 'wall sweep' or 'color fill'"), "available_only": S.bool("Default false"), "limit": S.int("Default 30")]),
        ToolSpec("run_command", "Run Command",
                 "Run any command like its menu item, by id or title (list_commands). Commands that wait for clicks start their tool for the user. Saving, exporting, deleting, purging and project-wide settings need confirm: true (ask the user first).",
                 risk: .edit, group: .commands,
                 properties: ["command": S.str("Command id (e.g. 'tagAll') or title (e.g. 'Tag All')"), "confirm": S.bool("Required for file, delete and project-wide commands")],
                 required: ["command"]),
    ]
}

extension ArcusToolbox {
    static let selectionHandlers: [String: ToolHandler] = [
        "get_selection": { b, c in try b.getSelection(c) },
        "select_elements": { b, c in try b.selectElements(c) },
        "hide_isolate": { b, c in try b.hideIsolate(c) },
    ]
    static let navigationHandlers: [String: ToolHandler] = [
        "open_view": { b, c in try b.openView(c) },
        "zoom_to": { b, c in try b.zoomTo(c) },
        "set_3d_view": { b, c in try b.set3DView(c) },
    ]
    static let commandHandlers: [String: ToolHandler] = [
        "find_tools": { b, c in try b.findTools(c) },
        "list_commands": { b, c in try b.listCommands(c) },
        "run_command": { b, c in try await b.runCommand(c) },
    ]

    // MARK: Selection

    func getSelection(_ c: ToolContext) throws -> ToolOutput {
        let s = try c.session()
        let m = s.model
        let sel = s.selection.ids.compactMap { m[$0] }
        let limit = max(1, c.args.int("limit") ?? 50)
        var counts: [String: JSONValue] = [:]
        for (cat, es) in Dictionary(grouping: sel, by: \.category) { counts[cat.rawValue] = .int(es.count) }
        var o: [String: JSONValue] = ["count": .int(sel.count), "categories": .object(counts), "unit": .string(ToolContext.unitScale(m).symbol),
                                      "elements": .array(sel.prefix(limit).map { describe($0, c, m) })]
        if sel.isEmpty { o["note"] = "Nothing is selected. select_elements selects by category, type, level or parameter." }
        return ToolOutput(.object(o))
    }

    /// Elements matching a query (category, type words, level, visible in a view, parameter filters).
    func query(elements c: ToolContext) throws(ToolError) -> [ElementID] {
        let m = try c.model()
        if c.args["ids"] != nil { return try c.elementIDs("ids") }
        guard let cs = c.args.string("category") else { throw ToolError("Give ids or a category (walls, doors, windows, rooms, furniture, furniturePanels…).") }
        let cat = try Self.category(cs)
        var list = m.elements(cat).filter { !$0.isType }
        if let lv = c.args["level"] { let l = try c.level(lv); list = list.filter { $0.levelID == l.id } }
        if let t = c.args.string("type") {
            let q = ToolContext.tokens(t)
            list = list.filter { e in
                guard let ty = m.type(of: e) else { return false }
                let hay = ToolContext.tokens(ToolContext.typeLabel(ty, m))
                return q.allSatisfy { w in hay.contains { $0.hasPrefix(w) } }
            }
        }
        if let vv = c.args["view"] {
            let view = vv.stringValue?.lowercased() == "active" ? try c.viewOrActive("__none__") : try c.view(vv)
            let visible = Set(ViewGraphicsBuilder(model: m, view: view).build().items.compactMap(\.elementID))
            list = list.filter { visible.contains($0.id) }
        }
        for (name, cond) in c.args["where"]?.objectValue ?? [:] {
            let op = cond.objectValue?["op"]?.stringValue ?? "="
            let want = cond.objectValue?["value"] ?? cond
            list = list.filter { e in
                guard let d = Parameters.descriptor(named: name, for: e, m), let v = Parameters.value(d.id, of: e, m) else { return name == "Name" && e.name == want.stringValue }
                let text = Parameters.format(v, type: d.type, model: m)
                if let wantNum = (try? want.stringValue.map { try Parameters.parse($0, type: d.type, model: m) } ?? nil)?.doubleValue ?? want.doubleValue.map({ d.type == .length ? $0 * ToolContext.unitScale(m).meters : $0 }),
                   let have = v.doubleValue {
                    switch op {
                    case ">": return have > wantNum + 1e-9
                    case "<": return have < wantNum - 1e-9
                    case ">=": return have >= wantNum - 1e-9
                    case "<=": return have <= wantNum + 1e-9
                    case "!=": return abs(have - wantNum) > 1e-6
                    default: return abs(have - wantNum) < 1e-6
                    }
                }
                let w = want.stringValue ?? want.jsonText
                switch op {
                case "contains": return text.localizedCaseInsensitiveContains(w)
                case "!=": return text.caseInsensitiveCompare(w) != .orderedSame
                default: return text.caseInsensitiveCompare(w) == .orderedSame
                }
            }
        }
        return list.map(\.id)
    }

    func selectElements(_ c: ToolContext) throws -> ToolOutput {
        let s = try c.session()
        let mode = c.args.string("mode")?.lowercased() ?? "replace"
        if mode == "clear" { s.selection.clear(); return ToolOutput(["count": 0]) }
        let ids = try query(elements: c)
        switch mode {
        case "add": s.selection.add(ids)
        case "remove": s.selection.remove(ids)
        default: s.selection.select(ids)
        }
        let m = s.model
        var o: [String: JSONValue] = ["count": .int(s.selection.count), "matched": .int(ids.count), "ids": .array(s.selection.ids.prefix(200).map(\.json))]
        if ids.isEmpty { o["note"] = "Nothing matched. Check the category name and filters (query_model lists elements with their parameters)." }
        else { o["sample"] = .array(ids.prefix(5).compactMap { m[$0] }.map { describe($0, c, m) }) }
        return ToolOutput(.object(o))
    }

    func hideIsolate(_ c: ToolContext) throws -> ToolOutput {
        let s = try c.session()
        let view = try c.viewOrActive(kinds: nil)
        let action = try c.args.requireString("action").lowercased()
        let cats = try (c.args.array("categories") ?? []).compactMap(\.stringValue).map { s throws(ToolError) in try Self.category(s) }
        if c.args.bool("permanent", default: false) {
            let ids = try c.idsOrSelection()
            let unhide = c.args.bool("unhide", default: false)
            try c.edit(unhide ? "Unhide in View" : "Hide in View") { tx in
                tx.update(view.id) { e in
                    for id in ids { if unhide { e.view?.visibility.hiddenElements.remove(id) } else { e.view?.visibility.hiddenElements.insert(id) } }
                    for cat in cats { if unhide { e.view?.visibility.hiddenCategories.remove(cat) } else { e.view?.visibility.hiddenCategories.insert(cat) } }
                }
            }
            return result(c, [unhide ? "unhidden" : "hidden": .int(ids.count), "view": .string(view.name)], ids: [view.id])
        }
        var tv = s.temporaryVisibility[view.id] ?? TemporaryVisibility()
        switch action {
        case "hide": tv.hiddenElements.formUnion(try c.idsOrSelection())
        case "isolate": tv.isolatedElements = Set(try c.idsOrSelection())
        case "hide_category":
            guard !cats.isEmpty else { throw ToolError("Give categories to hide.") }
            tv.hiddenCategories.formUnion(cats)
        case "isolate_category":
            guard !cats.isEmpty else { throw ToolError("Give categories to isolate.") }
            tv.isolatedCategories = Set(cats)
        case "reset": tv = TemporaryVisibility()
        default: throw ToolError("action must be hide, isolate, hide_category, isolate_category or reset.")
        }
        s.temporaryVisibility[view.id] = tv.isActive ? tv : nil
        if action != "reset" { s.selection.clear() }
        (host as? any DocumentUIHost)?.zoom(to: nil)
        return ToolOutput(["view": .string(view.name), "temporary": .bool(tv.isActive), "note": "Temporary: not saved. reset clears it."])
    }

    // MARK: Navigation

    func openView(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let e = try c.viewOrActive(allowSheets: true, allowSchedules: true)
        guard let ui = host as? any DocumentUIHost, ui.activateView(e.id) else { throw ToolError("“\(e.name)” could not be opened.") }
        var o: [String: JSONValue] = ["view": .string(e.name), "id": e.id.json]
        if let v = e.view { o["kind"] = .string(v.kind.rawValue); o["scale"] = .int(v.scale); o["level"] = m[e.levelID].map { .string($0.name) } ?? .null }
        if let sh = e.sheet { o["sheet"] = .string(sh.number) }
        return ToolOutput(.object(o))
    }

    func zoomTo(_ c: ToolContext) throws -> ToolOutput {
        let ids = c.args["elements"] != nil ? try c.elementIDs("elements") : nil
        (host as? any DocumentUIHost)?.zoom(to: ids)
        return ToolOutput(["zoomed": ids.map { .int($0.count) } ?? "fit"])
    }

    func set3DView(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var view: Element?
        if let n = c.args.string("name"), m.views.first(where: { $0.name == n && $0.view?.kind == .threeD }) == nil { view = nil } else {
            view = c.args["view"] != nil ? try c.view(c.args["view"], kinds: [.threeD]) : activeViewID.flatMap { m[$0] }.flatMap { $0.view?.kind == .threeD ? $0 : nil }
                ?? m.views.first { $0.view?.kind == .threeD && $0.name == "{3D}" } ?? m.views.first { $0.view?.kind == .threeD }
        }
        var box: Box3?
        switch c.args.string("section_box")?.lowercased() {
        case "elements":
            let ids = try c.idsOrSelection()
            box = Self.box(of: ids, m)
            guard box != nil else { throw ToolError("Those elements have no 3D extents.") }
        case "level":
            let l = try c.levelOrViewLevel()
            let ext = Self.modelExtents(m) ?? Rect2(min: .zero, max: Vec2(10, 10))
            let z = l.level?.elevation ?? 0
            let top = m.levelAbove(l.id)?.level?.elevation ?? z + 3
            box = Box3(min: Vec3(ext.min - Vec2(1, 1), z: z - 0.3), max: Vec3(ext.max + Vec2(1, 1), z: top - 0.05))
        default: break
        }
        let orient = c.args.string("orientation")?.lowercased() ?? "iso_sw"
        let dirs: [String: Vec3] = ["iso_sw": Vec3(-1, -1.2, 0.9), "iso_se": Vec3(1, -1.2, 0.9), "iso_ne": Vec3(1, 1.2, 0.9), "iso_nw": Vec3(-1, 1.2, 0.9),
                                    "top": Vec3(0.0001, -0.0001, 1), "front": Vec3(0, -1, 0.0001), "back": Vec3(0, 1, 0.0001), "left": Vec3(-1, 0, 0.0001), "right": Vec3(1, 0, 0.0001)]
        guard let dir = dirs[orient] else { throw ToolError("orientation must be one of \(dirs.keys.sorted().joined(separator: ", ")).") }
        var cam = Self.fitCamera(m, box: box)
        let size = max(cam.orthoHeight, 1)
        cam.eye = cam.target + dir.normalized * (size * 2.5)
        let off = c.args.string("section_box")?.lowercased() == "off"
        var id = view?.id
        try c.edit("Orient 3D View") { tx in
            if let vid = id {
                tx.update(vid) { e in
                    e.view?.camera = cam
                    if let box { e.view?.sectionBox = box; e.view?.sectionBoxActive = true }
                    if off { e.view?.sectionBoxActive = false }
                }
            } else {
                var vd = ViewData(kind: .threeD, scale: m.isFurniture ? 12 : 100)
                vd.camera = cam; vd.phaseID = m.latestPhase?.id
                if let box { vd.sectionBox = box; vd.sectionBoxActive = true }
                id = tx.create(.views, name: c.args.string("name") ?? "3D View", data: .view(vd))
            }
        }
        if let id { _ = (host as? any DocumentUIHost)?.activateView(id) }
        return result(c, ["view": id?.json ?? .null, "orientation": .string(orient), "section_box": .bool(box != nil)], ids: id.map { [$0] } ?? [])
    }

    /// The 3D extents of elements (plan footprint and level range when no solid box is known).
    static func box(of ids: [ElementID], _ m: BIMModel) -> Box3? {
        var pts: [Vec3] = []
        for id in ids {
            guard let e = m[id] else { continue }
            if let b = FurniturePartSolids.partBox(e, m)?.box { pts += [b.min, b.max]; continue }
            let z0 = m.elevation(ofLevel: e.levelID)
            let z1 = m.levelAbove(e.levelID)?.level?.elevation ?? z0 + 3
            var plan: [Vec2] = []
            if let w = e.wall { plan += [w.location.start, w.location.end] }
            if let p = e.component?.location ?? e.column?.location ?? e.insert?.location ?? e.room?.point { plan.append(p) }
            if let s = e.slab { plan += s.boundary.loops.first?.map(\.start) ?? [] }
            if let r = e.roof { plan += r.footprint.loops.first?.map(\.start) ?? [] }
            for p in plan { pts += [Vec3(p, z: z0), Vec3(p, z: z1)] }
        }
        guard let f = pts.first else { return nil }
        var lo = f, hi = f
        for p in pts { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
        let pad = 0.6
        return Box3(min: lo - Vec3(pad, pad, 0.1), max: hi + Vec3(pad, pad, 0.3))
    }

    // MARK: Commands

    func findTools(_ c: ToolContext) throws -> ToolOutput {
        let q = c.args.string("search").map { ToolContext.tokens($0) } ?? []
        let g = c.args.string("group")?.lowercased()
        guard !q.isEmpty || g != nil else { throw ToolError("Give search words or a group (\(ToolGroup.allCases.map(\.rawValue).joined(separator: ", "))).") }
        let limit = max(1, min(c.args.int("limit") ?? 8, 30))
        let pool = ArcusToolCatalog.tools(for: mode)
        let hits = pool.map { t -> (ToolSpec, Int) in
            let hay = ToolContext.tokens(t.name.replacingOccurrences(of: "_", with: " ") + " " + t.title + " " + t.description)
            let score = q.filter { w in hay.contains { $0.hasPrefix(w) } }.count
            return (t, score)
        }.filter { (t, s) in (g == nil || t.group.rawValue.lowercased().hasPrefix(g!)) && (q.isEmpty || s > 0) }
            .sorted { $0.1 > $1.1 }.prefix(limit)
        return ToolOutput(["tools": .array(hits.map { t, _ in ["name": .string(t.name), "description": .string(t.description), "risk": .string(t.risk.rawValue), "input_schema": t.inputSchema] }),
                           "note": "Call these by name with the schema shown."])
    }

    func listCommands(_ c: ToolContext) throws -> ToolOutput {
        let ui = host as? any DocumentUIHost
        let q = c.args.string("search").map { ToolContext.tokens($0) } ?? []
        let onlyAvailable = c.args.bool("available_only", default: false)
        let limit = max(1, min(c.args.int("limit") ?? 30, 200))
        var out: [JSONValue] = []
        var total = 0
        for info in CommandCatalog.all {
            let hay = ToolContext.tokens(info.title + " " + info.help + " " + info.keywords.joined(separator: " ") + " " + info.id.rawValue)
            guard q.allSatisfy({ w in hay.contains { $0.hasPrefix(w) } }) else { continue }
            let reason = host.session == nil ? "No document is open." : ui?.commandDisabledReason(info.id)
            if onlyAvailable && reason != nil { continue }
            total += 1
            guard out.count < limit else { continue }
            var o: [String: JSONValue] = ["id": .string(info.id.rawValue), "title": .string(info.title), "group": .string(info.group.rawValue), "help": .string(info.help)]
            if let reason { o["unavailable"] = .string(reason) }
            let r = CommandResolver.risk(info.id)
            if r != .edit { o["risk"] = .string(r.rawValue) }
            if let tool = CommandResolver.toolFor[info.id] { o["prefer_tool"] = .string(tool) }
            out.append(.object(o))
        }
        return ToolOutput(["commands": .array(out), "matched": .int(total), "backend": .string(host.backendName)])
    }

    func runCommand(_ c: ToolContext) async throws -> ToolOutput {
        let name = try c.args.requireString("command")
        guard let id = CommandResolver.resolve(name) else {
            let q = ToolContext.tokens(name)
            let near = CommandCatalog.all.filter { info in
                let hay = ToolContext.tokens(info.title + " " + info.id.rawValue)
                return q.contains { w in hay.contains { $0.hasPrefix(w) } }
            }.prefix(8).map { "\($0.id.rawValue) (\($0.title))" }
            throw ToolError("No command “\(name)”.\(near.isEmpty ? "" : " Close: \(near.joined(separator: "; ")).") list_commands searches them all.")
        }
        let risk = CommandResolver.risk(id)
        if risk != .edit && risk != .read && !c.args.bool("confirm", default: false) {
            throw ToolError("\(CommandCatalog.info(id).title) is a \(risk.rawValue.replacingOccurrences(of: "_", with: "-")) command. Ask the user, then call again with confirm: true.")
        }
        let title = CommandCatalog.info(id).title
        if host is FileDocumentHost {
            let text = try await runHeadless(id, c)
            return result(c, ["command": .string(id.rawValue), "title": .string(title), "done": .string(text)], ids: [])
        }
        guard let ui = host as? any DocumentUIHost else { throw ToolError("This host can't run commands.") }
        if let reason = ui.commandDisabledReason(id) { throw ToolError("\(title) can't run now: \(reason)") }
        let undoBefore = host.session?.undoManager.undoActionName
        switch ui.runCommand(id) {
        case .done(let s):
            var o: [String: JSONValue] = ["command": .string(id.rawValue), "title": .string(title), "done": .string(s)]
            if let u = host.session?.undoManager.undoActionName, u != undoBefore { o["undo"] = .string(u) }
            return ToolOutput(.object(o))
        case .startedTool(let s):
            return ToolOutput(["command": .string(id.rawValue), "title": .string(title), "started_tool": .string(s),
                               "note": "The tool now waits for the user's clicks in the view. Tell the user what to click, or use a dedicated tool instead."])
        case .unavailable(let s): throw ToolError("\(title) can't run now: \(s)")
        }
    }

    /// File mode's commands: the few that need no window, run through the matching tools.
    func runHeadless(_ id: CommandID, _ c: ToolContext) async throws -> String {
        let s = try c.session()
        let sel: JSONValue = .array(s.selection.ids.map(\.json))
        func call(_ tool: String, _ args: [String: JSONValue]) async throws -> String {
            let sub = ToolContext(host: host, args: ToolArgs(args))
            sub.toolbox = self
            sub.groupsUndo = false
            let out = try await handle(tool, sub)
            c.records += sub.records
            if c.healthBefore == nil { c.healthBefore = sub.healthBefore }
            return out.json.jsonText.count > 300 ? String(out.json.jsonText.prefix(300)) + "…" : out.json.jsonText
        }
        switch id {
        case .delete: return try await call("delete_elements", ["elements": sel, "confirm": true])
        case .pin: return try await call("pin_elements", ["elements": sel])
        case .unpin: return try await call("pin_elements", ["elements": sel, "unpin": true])
        case .flipFacing: return try await call("flip_elements", ["elements": sel, "what": "facing"])
        case .flipHand: return try await call("flip_elements", ["elements": sel, "what": "hand"])
        case .flipWall: return try await call("flip_elements", ["elements": sel, "what": "wall"])
        case .detachTop: return try await call("attach_walls", ["elements": sel, "detach": true])
        case .joinSolids: return try await call("join_geometry", ["elements": sel])
        case .unjoinSolids: return try await call("join_geometry", ["elements": sel, "unjoin": true])
        case .ungroup:
            guard let g = s.selection.ids.first(where: { s.model[$0]?.group != nil }) else { throw ToolError("Select a group.") }
            return try await call("group_elements", ["ungroup": g.json])
        case .selectAll:
            let view = try c.viewOrActive()
            let visible = Set(ViewGraphicsBuilder(model: s.model, view: view).build().items.compactMap(\.elementID)).filter { s.model[$0]?.category.isModel == true }
            s.selection.select(visible.sorted())
            return "Selected \(visible.count) elements in \(view.name)."
        case .zoomExtents: return "Zoomed to fit."
        case .placeRoomsAutomatically: return try await call("place_rooms", ["auto": true, "level": .int(Int(try c.levelOrViewLevel().id.raw))])
        case .tagAll: return try await call("add_tags", ["view": .int(Int(try c.viewOrActive().id.raw))])
        case .modelHealth: return try await call("model_health", [:])
        case .undo, .redo: return try await call(id == .undo ? "undo" : "redo", [:])
        default: throw ToolError("\(CommandCatalog.info(id).title) runs in the Arcus app only.\(CommandResolver.toolFor[id].map { " Use the \($0) tool instead." } ?? "")")
        }
    }
}
