import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput

// AITOOLS: model checks the assistant runs after it builds: model health with what to do, clashes between elements,
// room enclosure, Check Parts (furniture), and verify_drawing for a view or sheet (dimensions present and apart, tags,
// title block fields, nothing clipped or off the paper) with an optional PNG for the assistant to look at.

extension ArcusToolCatalog {
    static let checkTools: [ToolSpec] = [
        ToolSpec("model_health", "Model Health", "Every warning (Revit's Review Warnings): severity, message, elements, and what to do; plus Furniture Check Parts and component collisions. Read it before you finish.",
                 risk: .read, group: .checks, modes: .model, properties: ["limit": S.int("Default 40")]),
        ToolSpec("check_clashes", "Clashes", "Find elements that occupy the same space (columns in walls, furniture through walls, beams through ducts…): by category pairs, or everything. Hosted and joined elements are not clashes.",
                 risk: .read, group: .checks, modes: .model,
                 properties: ["categories": S.array(S.str(), "Default walls, columns, structuralFraming, furniture, casework, plumbingFixtures, stairs"), "against": S.array(S.str(), "Second set (default the same)"),
                              "level": S.ref(), "tolerance": S.len("Overlap ignored below this (default 1\")"), "limit": S.int("Default 30")]),
        ToolSpec("check_rooms", "Room Enclosure", "Rooms (or areas) with their area and whether they are enclosed, redundant or not placed, and the regions bounded by walls that have no room yet.",
                 risk: .read, group: .checks, modes: .project, properties: ["level": S.ref(), "areas": S.bool("Areas instead of rooms")]),
        ToolSpec("check_parts", "Check Parts", "Furniture: parts without material, too thin or too long for stock, grain against the long side, unbanded visible edges, fronts that collide, missing hardware.",
                 risk: .read, group: .checks, modes: .furniture),
        ToolSpec("verify_drawing", "Verify Drawing",
                 "Check a view or sheet like a reviewer: dimensions present, not overlapping and not duplicated; tags on doors, windows and rooms; title block fields filled; viewports on the paper and apart; annotations not clipped. Returns ok, problems (with element ids and the tool that fixes each) and, with image: true, a PNG to look at.",
                 risk: .read, group: .checks, modes: .model,
                 properties: ["view": S.ref("View name/id or sheet number (default the active view)"), "image": S.bool("Also return a PNG (default false)"), "width": S.int("PNG pixels, default 1400")]),
    ]
}

extension ArcusToolbox {
    static let checkHandlers: [String: ToolHandler] = [
        "model_health": { b, c in try b.modelHealth(c) },
        "check_clashes": { b, c in try b.checkClashes(c) },
        "check_rooms": { b, c in try b.checkRooms(c) },
        "check_parts": { b, c in try b.checkParts(c) },
        "verify_drawing": { b, c in try b.verifyDrawing(c) },
    ]

    /// What to do about a warning, by code (small models act on these directly).
    static let fixes: [String: String] = [
        "room.unbounded": "Close the walls around it (trim_extend corner) or add_room_separators; or delete the room.",
        "room.redundant": "Two rooms share one region: delete one (delete_elements).",
        "room.unplaced": "Place it (place_rooms) or delete it.",
        "wall.overlap": "Two walls overlap: delete one or split_element / trim_extend them.",
        "host.orphan": "Its host is gone: delete it or re-host it.",
        "mark.duplicate": "Give each a unique Mark (set_parameters {\"Mark\": …}).",
        "level.missing": "The element's level was deleted: change its level (set_parameters {\"Level\": …}).",
        "type.missing": "Change its type (change_type).",
        "material.missing": "Set a material on its type (set_parameters type:true).",
        "stair.rule": "Change risers or tread (set_parameters on the stair) so riser/tread meet the rules.",
        "sketch.invalid": "Its boundary is not a closed loop: recreate it with a clean boundary.",
        "constraint.violated": "A locked dimension or alignment can't hold: unlock it or move the elements.",
        "extents.far": "Something is very far from the origin: find it (select_elements) and delete or move it.",
        "export.levelName": "Rename the level (set_parameters {\"Name\": …}).",
        "ramp.length": "Make the ramp run longer or lower its rise.",
    ]

    static func warningWithFix(_ w: ModelWarning) -> JSONValue {
        var o = ToolContext.warningJSON(w).objectValue ?? [:]
        o["code"] = .string(w.code)
        if let f = fixes[w.code] ?? fixes.first(where: { w.code.hasPrefix($0.key) })?.value { o["fix"] = .string(f) }
        return .object(o)
    }

    func modelHealth(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let limit = max(1, c.args.int("limit") ?? 40)
        var all = ModelHealth.check(m)
        if m.isFurniture { all += FurnitureCheckParts.check(m) }
        all += ComponentChecks.check(m)
        all.sort { $0.severity > $1.severity }
        var counts: [String: JSONValue] = [:]
        for (s, ws) in Dictionary(grouping: all, by: \.severity) { counts[s.rawValue] = .int(ws.count) }
        var byCode: [String: JSONValue] = [:]
        for (code, ws) in Dictionary(grouping: all, by: \.code) { byCode[code] = .int(ws.count) }
        return ToolOutput(["ok": .bool(all.allSatisfy { $0.severity < .warning }), "count": .int(all.count), "by_severity": .object(counts), "by_code": .object(byCode),
                           "warnings": .array(all.prefix(limit).map(Self.warningWithFix))])
    }

    /// An element's 3D box for clash tests (walls: their footprint between base and top).
    func clashBox(_ e: Element, _ m: BIMModel) -> Box3? {
        if let w = e.wall, let f = WallGeometry.frame(e, m), let fp = WallGeometry.footprint(e, m) {
            let r = Rect2(points: fp.points)
            let z0 = m.elevation(ofLevel: e.levelID) + w.baseOffset
            return Box3(min: Vec3(r.min, z: z0), max: Vec3(r.max, z: z0 + f.height))
        }
        return Self.box(of: [e.id], m).map { b in Box3(min: b.min + Vec3(0.6, 0.6, 0.1), max: b.max - Vec3(0.6, 0.6, 0.3)) }
    }

    func checkClashes(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let defaults: [Category] = m.isFurniture ? [.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails, .furnitureFronts, .furnitureHardware]
            : [.walls, .columns, .structuralColumns, .structuralFraming, .furniture, .casework, .plumbingFixtures, .stairs]
        func cats(_ key: String) throws(ToolError) -> [Category]? {
            guard let a = c.args.array(key) else { return nil }
            var out: [Category] = []
            for v in a { out.append(try Self.category(v.stringValue ?? "")) }
            return out
        }
        let a = try cats("categories") ?? defaults
        let b = try cats("against") ?? a
        let level = try c.args["level"].map { try c.level($0) }
        let tol = try c.length("tolerance") ?? 0.0254
        let limit = max(1, c.args.int("limit") ?? 30)
        func elements(_ cs: [Category]) -> [(Element, Box3)] {
            cs.flatMap { m.elements($0) }.filter { !$0.isType && (level == nil || $0.levelID == level?.id) }.compactMap { e in
                (m.isFurniture ? FurniturePartSolids.partBox(e, m)?.box : clashBox(e, m)).map { (e, $0) }
            }
        }
        let sa = elements(a), sb = elements(b)
        var clashes: [JSONValue] = []
        var seen = Set<String>()
        for (e1, b1) in sa {
            for (e2, b2) in sb where e1.id != e2.id {
                let key = e1.id < e2.id ? "\(e1.id.raw)-\(e2.id.raw)" : "\(e2.id.raw)-\(e1.id.raw)"
                guard !seen.contains(key) else { continue }
                // Hosted, joined or same-category walls (corners) aren't clashes.
                if e1.hostID == e2.id || e2.hostID == e1.id || (e1.category == .walls && e2.category == .walls) { continue }
                if m.isFurniture, FurnitureJoints.joint(e1.id, e2.id, m) != nil { continue }
                let ox = min(b1.max.x, b2.max.x) - max(b1.min.x, b2.min.x), oy = min(b1.max.y, b2.max.y) - max(b1.min.y, b2.min.y), oz = min(b1.max.z, b2.max.z) - max(b1.min.z, b2.min.z)
                guard ox > tol, oy > tol, oz > tol else { continue }
                seen.insert(key)
                clashes.append(["a": ["id": e1.id.json, "category": .string(e1.category.rawValue)], "b": ["id": e2.id.json, "category": .string(e2.category.rawValue)],
                                "overlap": [c.out(ox, m), c.out(oy, m), c.out(oz, m)]])
                if clashes.count >= limit { break }
            }
            if clashes.count >= limit { break }
        }
        return ToolOutput(["ok": .bool(clashes.isEmpty), "clashes": .array(clashes), "checked": .int(sa.count), "unit": .string(ToolContext.unitScale(m).symbol)])
    }

    func checkRooms(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let areas = c.args.bool("areas", default: false)
        let levels = try c.args["level"].map { [try c.level($0)] } ?? m.levels.sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
        var rooms: [JSONValue] = [], empty: [JSONValue] = []
        var problems: [String] = []
        for l in levels {
            let b = RoomGeometry.boundaries(level: l.id, m)
            for r in m.elements(areas ? .areas : .rooms).filter({ $0.levelID == l.id }) {
                let s = b[r.id]?.state ?? RoomGeometry.boundary(r, m).state
                let state: String = switch s { case .bounded: "enclosed"; case .notEnclosed: "not_enclosed"; case .notPlaced: "not_placed"; case .redundant: "redundant" }
                rooms.append(["id": r.id.json, "level": .string(l.name), "number": .string(r.room?.number ?? ""), "name": .string(r.name), "area": c.areaNumber(b[r.id]?.area ?? 0, m), "state": .string(state)])
                if state != "enclosed" { problems.append("\(r.room?.number ?? "") \(r.name) on \(l.name) is \(state.replacingOccurrences(of: "_", with: " ")).") }
            }
            if !areas {
                for region in RoomGeometry.unoccupiedRegions(level: l.id, m) {
                    empty.append(["level": .string(l.name), "area": c.areaNumber(region.area, m), "point": c.out(region.point, m)])
                }
            }
        }
        return ToolOutput(["ok": .bool(problems.isEmpty), "rooms": .array(rooms), "regions_without_room": .array(empty), "problems": .array(problems.map { .string($0) }),
                           "area_unit": .string(m.units.system == .imperial ? "SF" : "m²"), "next": empty.isEmpty ? .null : "place_rooms {auto: true} fills the regions without a room."])
    }

    func checkParts(_ c: ToolContext) throws -> ToolOutput {
        let m = try requireFurniture(c)
        let w = FurnitureCheckParts.check(m)
        return ToolOutput(["ok": .bool(w.allSatisfy { $0.severity < .warning }), "count": .int(w.count), "findings": .array(w.prefix(40).map(Self.warningWithFix))])
    }

    func verifyDrawing(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let e = try c.viewOrActive(allowSheets: true)
        let (problems, stats) = DrawingCheck.problems(e, m)
        let fixTool: [String: String] = ["dimension.overlap": "arrange_dimensions", "dimension.duplicate": "arrange_dimensions", "dimension.text_overlap": "arrange_dimensions",
                                         "dimension.crowded": "arrange_dimensions", "tags.missing": "add_tags", "dimensions.missing": "add_dimensions",
                                         "sheet.empty_fields": "set_sheet_info", "sheet.no_title_block": "set_sheet_info", "sheet.off_paper": "set_view_properties",
                                         "sheet.viewports_overlap": "place_on_sheet", "view.clipped": "set_view_properties", "sheet.empty": "place_on_sheet"]
        var o: [String: JSONValue] = ["view": .string(e.sheet.map { "\($0.number) \(e.name)" } ?? e.name), "ok": .bool(problems.isEmpty),
                                      "problems": .array(problems.prefix(30).map { p in var j = p.json.objectValue ?? [:]; if let t = fixTool[p.code] { j["fix_with"] = .string(t) }; return .object(j) }),
                                      "count": .int(problems.count)]
        for (k, v) in stats { o[k] = v }
        var images: [JSONValue] = []
        if c.args.bool("image", default: false) {
            let (g, paper) = graphics(e, m)
            if let img = RasterExporter.render(g, paper: paper, pixelWidth: min(max(c.args.int("width") ?? 1400, 300), 4000)), let png = RasterExporter.encode(img, as: .png) {
                images.append(["type": "image", "data": .string(png.base64EncodedString()), "mimeType": "image/png"])
            }
        }
        return ToolOutput(.object(o), images: images)
    }
}
