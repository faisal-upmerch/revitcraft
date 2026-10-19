import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// MCP: read-only tools: query_model, list_types, list_families.

extension ArcusToolbox {
    static func category(_ s: String) throws(ToolError) -> Category {
        if let c = Category(rawValue: s) { return c }
        let l = s.lowercased().replacingOccurrences(of: "_", with: " ")
        if let c = Category.allCases.first(where: { $0.rawValue.lowercased() == l.replacingOccurrences(of: " ", with: "") || $0.displayName.lowercased() == l || $0.singularName.lowercased() == l }) { return c }
        throw ToolError("Unknown category “\(s)”. Examples: walls, doors, windows, floors, ceilings, roofs, stairs, railings, rooms, furniture, casework, plumbingFixtures, furniturePanels, furnitureShelves.")
    }

    func query(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let limit = max(1, c.args.int("limit") ?? 200)
        let levelFilter = try c.args["level"].map { try c.level($0) }
        switch try c.args.requireString("what").lowercased() {
        case "summary":
            return try status(c)
        case "levels":
            return ToolOutput(["unit": .string(ToolContext.unitScale(m).symbol), "levels": .array(m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }.map { l in
                ["id": l.id.json, "name": .string(l.name), "elevation": c.out(l.level?.elevation ?? 0, m),
                 "views": .array(m.views.filter { $0.levelID == l.id }.map { .string("\($0.name) (\($0.view?.kind.rawValue ?? ""))") }),
                 "walls": .int(m.elements(.walls).filter { $0.levelID == l.id }.count), "rooms": .int(m.elements(.rooms).filter { $0.levelID == l.id }.count)]
            })])
        case "elements":
            let cat = try Self.category(try c.args.requireString("category"))
            var list = m.elements(cat).filter { !$0.isType }
            if let l = levelFilter { list = list.filter { $0.levelID == l.id } }
            let shown = list.prefix(limit)
            var o: [String: JSONValue] = ["category": .string(cat.rawValue), "count": .int(list.count), "unit": .string(ToolContext.unitScale(m).symbol),
                                          "elements": .array(shown.map { describe($0, c, m) })]
            if list.count > shown.count { o["truncated"] = .string("Showing \(shown.count) of \(list.count); pass limit or level.") }
            return ToolOutput(.object(o))
        case "rooms":
            var out: [JSONValue] = []
            var total = 0.0
            for l in m.levels.sorted(by: { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }) where levelFilter == nil || levelFilter?.id == l.id {
                let b = RoomGeometry.boundaries(level: l.id, m)
                for r in m.elements(.rooms).filter({ $0.levelID == l.id }).sorted(by: { ($0.room?.number ?? "") < ($1.room?.number ?? "") }) {
                    let a = b[r.id]?.area ?? 0
                    total += a
                    out.append(["id": r.id.json, "level": .string(l.name), "number": .string(r.room?.number ?? ""), "name": .string(r.name),
                                "area": c.areaNumber(a, m), "bounded": .bool(b[r.id]?.state == .bounded)])
                }
            }
            return ToolOutput(["area_unit": .string(m.units.system == .imperial ? "SF" : "m²"), "rooms": .array(out), "total_area": .string(c.formatArea(total, m))])
        case "views":
            return ToolOutput(["views": .array(m.views.sorted { $0.name < $1.name }.prefix(limit).map { v in
                var o: [String: JSONValue] = ["id": v.id.json, "name": .string(v.name), "kind": .string(v.view?.kind.rawValue ?? ""), "scale": .int(v.view?.scale ?? 0)]
                if let l = m[v.levelID] { o["level"] = .string(l.name) }
                if let s = m.sheet(containing: v.id) { o["sheet"] = .string(s.sheet?.number ?? "") }
                return .object(o)
            })])
        case "sheets":
            return ToolOutput(["sheets": .array(m.sheets.map { s in
                ["id": s.id.json, "number": .string(s.sheet?.number ?? ""), "name": .string(s.name), "paper": .string(s.sheet?.paper.rawValue ?? ""),
                 "views": .array(m.owned(byView: s.id).compactMap { $0.viewport.flatMap { m[$0.viewID] }.map { .string($0.name) } })]
            })])
        case "schedules":
            return ToolOutput(["schedules": .array(m.schedules.map { s in
                let t = ScheduleEngine.compute(s, m)
                return ["id": s.id.json, "name": .string(s.name), "rows": .int(t.rows.count)]
            })])
        case "warnings":
            let h = ModelHealth.check(m)
            return ToolOutput(["count": .int(h.count), "warnings": .array(h.prefix(limit).map(ToolContext.warningJSON))])
        case "element":
            let ids = try c.elementIDs("ids")
            return ToolOutput(["elements": .array(ids.compactMap { m[$0] }.map { e in
                var params: [String: JSONValue] = [:]
                for p in Parameters.allEntries(e, m) where p.value != nil {
                    params[p.name] = .string(Parameters.format(p.value, type: p.type, model: m) + (p.isReadOnly ? "" : "") )
                }
                var o = describe(e, c, m).objectValue ?? [:]
                o["parameters"] = .object(params)
                o["editable"] = .array(Parameters.allEntries(e, m).filter { !$0.isReadOnly }.map { .string($0.name) })
                return .object(o)
            })])
        default:
            throw ToolError("what must be summary, levels, elements, rooms, views, sheets, schedules, warnings or element.")
        }
    }

    /// Key facts of one element.
    func describe(_ e: Element, _ c: ToolContext, _ m: BIMModel) -> JSONValue {
        var o: [String: JSONValue] = ["id": e.id.json]
        if !e.name.isEmpty { o["name"] = .string(e.name) }
        if let t = m.type(of: e) { o["type"] = .string(ToolContext.typeLabel(t, m)) }
        if let l = m[e.levelID], l.level != nil { o["level"] = .string(l.name) }
        if !e.mark.isEmpty { o["mark"] = .string(e.mark) }
        if let w = e.wall {
            o["start"] = c.out(w.location.start, m); o["end"] = c.out(w.location.end, m)
            o["length"] = .string(c.formatLength(w.location.length, m))
            if let f = WallGeometry.frame(e, m) { o["height"] = .string(c.formatLength(f.height, m)); o["thickness"] = .string(c.formatLength(f.thickness, m)) }
            o["openings"] = .array(m.hosted(by: e.id).filter { $0.insert != nil }.map(\.id.json))
        }
        if let i = e.insert {
            o["wall"] = e.hostID.map(\.json) ?? .null
            o["point"] = c.out(i.location, m)
            if let w = m[e.hostID]?.wall { o["offset"] = c.out(WallGeometry.station(of: i.location, on: w.location), m) }
            for n in ["Width", "Height"] { if let v = paramText(e, n, m) { o[n.lowercased()] = .string(v) } }
            if e.category == .windows { o["sill"] = .string(c.formatLength(i.sillHeight, m)) }
        }
        if let s = e.slab, let loop = s.boundary.loops.first {
            o["area"] = .string(c.formatArea(Polygon2(loop.map(\.start)).area, m))
        }
        if let r = e.room {
            o["number"] = .string(r.number)
            let b = RoomGeometry.boundary(e, m)
            o["area"] = c.areaNumber(b.area, m); o["bounded"] = .bool(b.state == .bounded)
        }
        if let comp = e.component { o["point"] = c.out(comp.location, m); o["rotation"] = .double((comp.rotation * 180 / .pi * 10).rounded() / 10) }
        if e.stair != nil { for n in ["Actual Number of Risers", "Actual Riser Height", "Actual Tread Depth"] { if let v = paramText(e, n, m) { o[n] = .string(v) } } }
        if let p = e.furniturePanel { o["start"] = c.out(p.start, m); o["end"] = c.out(p.end, m); o["base"] = c.out(p.base, m); o["top"] = c.out(p.top, m); o["role"] = .string(p.role.rawValue) }
        if let s = e.furnitureShelf { o["z"] = c.out(s.elevation, m); o["role"] = .string(s.role.rawValue) }
        if let b = FurniturePartSolids.partBox(e, m)?.box, m.isFurniture {
            o["box"] = ["min": [c.out(b.min.x, m), c.out(b.min.y, m), c.out(b.min.z, m)], "max": [c.out(b.max.x, m), c.out(b.max.y, m), c.out(b.max.z, m)]]
        }
        return .object(o)
    }

    func listTypes(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        if let s = c.args.string("category") {
            let cat = try Self.category(s)
            let types = m.types(for: cat)
            return ToolOutput(["category": .string(cat.rawValue), "types": .array(types.map { t in
                var o: [String: JSONValue] = ["id": t.id.json, "name": .string(ToolContext.typeLabel(t, m)), "instances": .int(m.instanceCount(ofType: t.id))]
                if let a = t.typeData?.assembly, a.totalThickness > 0 { o["thickness"] = .string(c.formatLength(a.totalThickness, m)) }
                return .object(o)
            })])
        }
        var cats: [String: JSONValue] = [:]
        let byCat = Dictionary(grouping: m.elements(.elementTypes), by: { $0.typeData?.instanceCategory ?? .genericModels })
        for (cat, ts) in byCat where cat.isModel || [.tags, .dimensions, .textNotes, .titleBlocks].contains(cat) {
            cats[cat.rawValue] = ["count": .int(ts.count), "examples": .array(ts.prefix(4).map { .string(ToolContext.typeLabel($0, m)) })]
        }
        return ToolOutput(["categories": .object(cats), "next": "list_types with a category lists every type."])
    }

    func listFamilies(_ c: ToolContext) throws -> ToolOutput {
        let system = (try? c.model())?.units.system ?? .imperial
        var items = ComponentLibrary.items
        if let s = c.args.string("category") {
            let cat = try Self.category(s)
            if cat == .doors || cat == .windows { return try listTypes(ToolContext(host: host, args: ToolArgs(["category": .string(cat.rawValue)]))) }
            items = items.filter { $0.category == cat }
        }
        if let q = c.args.string("search") { items = items.filter { $0.matches(q) } }
        let shown = items.prefix(80)
        var o: [String: JSONValue] = ["families": .array(shown.map { i in
            ["family": .string(i.name), "category": .string(i.category.rawValue), "group": .string(i.group),
             "types": .array(i.types(for: system).prefix(12).map { .string($0.name) })]
        }), "count": .int(items.count)]
        if items.count > shown.count { o["truncated"] = .string("Showing \(shown.count) of \(items.count); narrow with category or search.") }
        if items.isEmpty { o["categories"] = .array(ComponentLibrary.categories.map { .string($0.rawValue) }) }
        return ToolOutput(.object(o))
    }
}
