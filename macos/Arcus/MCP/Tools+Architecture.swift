import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: the rest of the Architecture tab: curtain walls and grids, columns, beams, component stairs (runs and
// landings), ramps, openings, areas, room separators, model lines and reference planes, toposolids, building pads and
// masses. Each creates its elements in one transaction like the ribbon tool.

extension ArcusToolCatalog {
    static let architectureTools: [ToolSpec] = [
        ToolSpec("create_curtain_wall", "Create Curtain Wall",
                 "Curtain walls along a polyline like create_walls, with the type's grid layout or explicit grid spacing (vertical every x, horizontal every z) and mullions. Types: 'Curtain Wall', 'Exterior Glazing', 'Storefront'. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "type": S.ref("Default Curtain Wall"), "points": S.points(), "closed": S.bool(), "top_level": S.ref(), "height": S.len(),
                              "vertical_spacing": S.len("Vertical grid every … along the wall"), "horizontal_spacing": S.len("Horizontal grid every … up the wall")],
                 required: ["points"]),
        ToolSpec("add_curtain_grids", "Curtain Grid", "Add curtain grid lines to a curtain wall: vertical at distances from its start, horizontal at heights above its base (mullions follow the type). replace:true clears the wall's own grids first. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["wall": S.int(), "vertical": S.array(S.len()), "horizontal": S.array(S.len()), "replace": S.bool()], required: ["wall"]),
        ToolSpec("place_columns", "Place Columns", "Place architectural or structural columns at points, or at every grid intersection (at_grids), from a base level to a top level. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["points": S.points(), "at_grids": S.bool(), "level": S.ref(), "top_level": S.ref(), "height": S.len("When no level is above"), "type": S.ref(),
                              "structural": S.bool("Default false (architectural)"), "rotation": S.num("Degrees")]),
        ToolSpec("create_beams", "Create Beams", "Structural beams along segments at a level (top of beam at the level plus offset). " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["segments": S.array(S.points(), "[[[x1,y1],[x2,y2]], …]"), "level": S.ref(), "type": S.ref(), "offset": S.len("z offset from the level"),
                              "justification": S.oneOf(["top", "center", "bottom"])], required: ["segments"]),
        ToolSpec("create_stair", "Create Stair (Runs)",
                 "Component stair: one or more runs, each from its first-riser centre in a direction with a riser count (straight, spiral, l_winder, u_winder); landings join consecutive runs automatically. Risers are spread to reach the top level. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["base_level": S.ref(), "top_level": S.ref(), "runs": S.array(S.object(["start": S.point(), "direction": S.ref("Degrees or north/south/east/west"), "risers": S.int(),
                                                                                                       "width": S.len(), "shape": S.oneOf(["straight", "spiral", "l_winder", "u_winder"])], required: ["start", "direction"])),
                              "type": S.ref(), "railings": S.bool("Default true")], required: ["runs"]),
        ToolSpec("create_ramp", "Create Ramp", "A ramp along a run path (points) between levels, with width and railings. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "top_level": S.ref(), "path": S.points(), "width": S.len("Default 4' / 1200 mm"), "railings": S.bool("Default true")], required: ["path"]),
        ToolSpec("create_opening", "Create Opening",
                 "Openings: wall (a rectangular cut in a wall: center offset from its start, width, sill and head heights), shaft (a boundary cut through every floor, roof and ceiling between levels) or vertical (a boundary cut through one floor, ceiling or roof). " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["kind": S.oneOf(["wall", "shaft", "vertical"]), "wall": S.int(), "offset": S.len("Wall: centre distance from the wall start"), "width": S.len(),
                              "bottom": S.len("Wall: sill height above the wall base"), "top": S.len("Wall: head height above the wall base"),
                              "boundary": S.points(), "level": S.ref(), "top_level": S.ref(), "host": S.int("Vertical: the floor, ceiling or roof id")],
                 required: ["kind"]),
        ToolSpec("place_areas", "Place Areas", "Make an area plan for a level (Gross Building or Rentable scheme) with its automatic boundary and place an area in each region. Returns the areas.",
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "scheme": S.oneOf(["gross", "rentable"], "Default gross")]),
        ToolSpec("add_room_separators", "Room Separator", "Room separation lines (or area boundary lines in an area plan) along segments, to split open spaces into rooms. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "segments": S.array(S.points()), "kind": S.oneOf(["room", "area"], "Default room"), "view": S.ref("Area plan for area lines")],
                 required: ["segments"]),
        ToolSpec("add_model_lines", "Model Lines / Reference Planes", "Model lines on a level, or project reference planes (named), along segments. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .model,
                 properties: ["segments": S.array(S.points()), "kind": S.oneOf(["model_line", "reference_plane"], "Default model_line"), "level": S.ref(), "names": S.array(S.str(), "Reference plane names")],
                 required: ["segments"]),
        ToolSpec("create_toposolid", "Create Toposolid", "Site terrain: a toposolid from an outline at an elevation, or from survey points [[x, y, z], …]. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["outline": S.points(), "elevation": S.len(), "points": S.array(S.array(S.len()), "[[x, y, z], …]"), "name": S.str()]),
        ToolSpec("create_building_pad", "Building Pad", "A building pad (a slab that cuts the terrain) from a boundary on a level. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "boundary": S.points(), "offset": S.len(), "type": S.ref()], required: ["boundary"]),
        ToolSpec("create_mass", "In-Place Mass", "A conceptual mass extruded from a plan boundary to a height (optionally tapering by top_inset); floors, walls and roofs can be made by face later. " + lengthNote,
                 risk: .edit, group: .architecture, modes: .project,
                 properties: ["level": S.ref(), "boundary": S.points(), "height": S.len(), "top_inset": S.len()], required: ["boundary"]),
    ]
}

extension ArcusToolbox {
    static let architectureHandlers: [String: ToolHandler] = [
        "create_curtain_wall": { b, c in try b.createCurtainWall(c) },
        "add_curtain_grids": { b, c in try b.addCurtainGrids(c) },
        "place_columns": { b, c in try b.placeColumns(c) },
        "create_beams": { b, c in try b.createBeams(c) },
        "create_stair": { b, c in try b.createStair(c) },
        "create_ramp": { b, c in try b.createRamp(c) },
        "create_opening": { b, c in try b.createOpening(c) },
        "place_areas": { b, c in try b.placeAreas(c) },
        "add_room_separators": { b, c in try b.addRoomSeparators(c) },
        "add_model_lines": { b, c in try b.addModelLines(c) },
        "create_toposolid": { b, c in try b.createToposolid(c) },
        "create_building_pad": { b, c in try b.createBuildingPad(c) },
        "create_mass": { b, c in try b.createMass(c) },
    ]

    /// Loads the standard content when the document has no types of `cat` (columns, pads…).
    func ensureTypes(_ c: ToolContext, _ cat: Category) throws(ToolError) {
        guard try c.model().types(for: cat).isEmpty else { return }
        try c.edit("Load Standard Types") { tx in _ = StandardContent.loadMissing(into: tx) }
    }

    func segments(_ c: ToolContext, _ key: String = "segments") throws(ToolError) -> [Segment2] {
        var out: [Segment2] = []
        for (k, s) in try c.args.requireArray(key).enumerated() {
            let p = try c.points(s, "\(key)[\(k)]")
            guard p[0].distance(to: p[1]) > 1e-3 else { throw ToolError("\(key)[\(k)] has zero length.") }
            out.append(Segment2(p[0], p[1]))
        }
        return out
    }

    // MARK: Curtain walls

    func createCurtainWall(_ c: ToolContext) throws -> ToolOutput {
        var m = try c.model()
        if !m.types(for: .walls).contains(where: { $0.typeData?.systemFamily == .curtainWall }) {
            try c.edit("Curtain Wall Types") { tx in _ = CurtainWallDefaults.populate(tx) }
            m = try c.model()
        }
        let level = try c.levelOrViewLevel()
        let curtains = m.types(for: .walls).filter { $0.typeData?.systemFamily == .curtainWall }
        let type: Element
        if let tv = c.args["type"] {
            type = try c.type(tv, category: .walls)
            guard type.typeData?.systemFamily == .curtainWall else { throw ToolError("“\(ToolContext.typeLabel(type, m))” is not a curtain wall type. Curtain types: \(curtains.map { ToolContext.typeLabel($0, m) }.joined(separator: "; ")).") }
        } else { guard let t = curtains.first(where: { $0.name == "Curtain Wall" }) ?? curtains.first else { throw ToolError("No curtain wall types.") }; type = t }
        let pts = try c.points(c.args["points"] ?? .null, "points")
        var segs = (0..<(pts.count - 1)).map { Segment2(pts[$0], pts[$0 + 1]) }
        if c.args.bool("closed", default: false), pts.count >= 3 { segs.append(Segment2(pts[pts.count - 1], pts[0])) }
        let top: Element? = try c.args["top_level"].map { try c.level($0, "top_level") } ?? (c.args["height"] == nil ? m.levelAbove(level.id) : nil)
        let height = try c.length("height") ?? (m.units.system == .imperial ? 10 * 0.3048 : 3.0)
        let vs = try c.length("vertical_spacing"), hs = try c.length("horizontal_spacing")
        if let vs, vs < 0.1 { throw ToolError("vertical_spacing is too small.") }
        if let hs, hs < 0.1 { throw ToolError("horizontal_spacing is too small.") }
        let wallHeight = top.map { ($0.level?.elevation ?? 0) - (level.level?.elevation ?? 0) } ?? height
        let r = try c.edit("Create Curtain Wall") { tx in
            for s in segs {
                var wd = WallData(location: .line(s), topLevelID: top?.id, unconnectedHeight: height)
                if vs != nil || hs != nil {
                    let v = vs.map { sp in stride(from: sp, to: s.length - 1e-3, by: sp).map { $0 } } ?? []
                    let h = hs.map { sp in stride(from: sp, to: wallHeight - 1e-3, by: sp).map { $0 } } ?? []
                    wd.curtain = CurtainInstanceData(verticalGrids: v, horizontalGrids: h)
                }
                tx.create(.walls, data: .wall(wd), typeID: type.id, levelID: level.id)
            }
            Self.fitTemplateElevations(in: tx)
        }
        let nm = try c.model()
        let ids = ToolContext.created(r).filter { nm[$0]?.category == .walls }
        return result(c, ["walls": .array(ids.compactMap { nm[$0] }.map { describe($0, c, nm) }), "type": .string(ToolContext.typeLabel(type, nm))], ids: ids)
    }

    func addCurtainGrids(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard let wv = c.args["wall"] else { throw ToolError("Missing wall.") }
        let w = try c.element(wv, "wall")
        guard let wd = w.wall, CurtainWallGeometry.isCurtain(w, m) else { throw ToolError("Element \(w.id.raw) is not a curtain wall.") }
        let len = wd.location.length
        let height = WallGeometry.frame(w, m)?.height ?? 3
        var v: [Double] = [], h: [Double] = []
        for (k, x) in (c.args.array("vertical") ?? []).enumerated() {
            let d = try c.length(x, "vertical[\(k)]")
            guard d > 0, d < len else { throw ToolError("vertical[\(k)] \(c.formatLength(d, m)) is outside the wall (length \(c.formatLength(len, m))).") }
            v.append(d)
        }
        for (k, z) in (c.args.array("horizontal") ?? []).enumerated() {
            let d = try c.length(z, "horizontal[\(k)]")
            guard d > 0, d < height else { throw ToolError("horizontal[\(k)] \(c.formatLength(d, m)) is outside the wall (height \(c.formatLength(height, m))).") }
            h.append(d)
        }
        guard !v.isEmpty || !h.isEmpty || c.args.bool("replace", default: false) else { throw ToolError("Give vertical and/or horizontal grid positions.") }
        let replace = c.args.bool("replace", default: false)
        try c.edit("Curtain Grid") { tx in
            tx.update(w.id) { e in
                var ci = e.wall?.curtain ?? CurtainInstanceData()
                if replace { ci.verticalGrids = []; ci.horizontalGrids = [] }
                ci.verticalGrids = Array(Set(ci.verticalGrids + v)).sorted()
                ci.horizontalGrids = Array(Set(ci.horizontalGrids + h)).sorted()
                e.wall?.curtain = ci
            }
        }
        let ci = try c.model()[w.id]?.wall?.curtain
        return result(c, ["wall": w.id.json, "vertical": .int(ci?.verticalGrids.count ?? 0), "horizontal": .int(ci?.horizontalGrids.count ?? 0)], ids: [w.id])
    }

    // MARK: Structure

    func placeColumns(_ c: ToolContext) throws -> ToolOutput {
        let structural = c.args.bool("structural", default: false)
        let cat: Category = structural ? .structuralColumns : .columns
        try ensureTypes(c, cat)
        let m = try c.model()
        let level = try c.levelOrViewLevel()
        let type = try c.type(c.args["type"], category: cat)
        var pts: [Vec2] = []
        if let pv = c.args["points"] { pts = try c.points(pv, "points", min: 1) }
        if c.args.bool("at_grids", default: false) {
            let lines = m.elements(.grids).compactMap { $0.grid?.curve.asSegment }
            for i in lines.indices { for j in lines.indices where j > i { if let p = lines[i].intersection(lines[j]) { pts.append(p) } } }
            guard !pts.isEmpty else { throw ToolError("No grid intersections. add_grid first, or give points.") }
        }
        guard !pts.isEmpty else { throw ToolError("Give points or at_grids: true.") }
        let top: Element? = try c.args["top_level"].map { try c.level($0, "top_level") } ?? m.levelAbove(level.id)
        let height = try c.length("height") ?? (m.units.system == .imperial ? 10 * 0.3048 : 3.0)
        let rot = (c.args.double("rotation") ?? 0) * .pi / 180
        let r = try c.edit("Place Columns") { tx in
            for p in pts { tx.create(cat, data: .column(ColumnData(location: p, rotation: rot, topLevelID: top?.id, unconnectedHeight: height)), typeID: type.id, levelID: level.id) }
        }
        let nm = try c.model()
        let ids = ToolContext.created(r).filter { nm[$0]?.category == cat }
        return result(c, ["columns": .array(ids.compactMap { nm[$0] }.map { ["id": $0.id.json, "point": c.out($0.column?.location ?? .zero, nm)] }), "type": .string(ToolContext.typeLabel(type, nm))], ids: ids)
    }

    func createBeams(_ c: ToolContext) throws -> ToolOutput {
        try ensureTypes(c, .structuralFraming)
        let level = try c.levelOrViewLevel()
        let type = try c.type(c.args["type"], category: .structuralFraming)
        let segs = try segments(c)
        let off = try c.length("offset") ?? 0
        let just: BeamZJustification = switch c.args.string("justification")?.lowercased() { case "center": .center; case "bottom": .bottom; default: .top }
        let r = try c.edit("Create Beams") { tx in
            for s in segs { tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(s), startOffset: off, endOffset: off, zJustification: just)), typeID: type.id, levelID: level.id) }
        }
        let nm = try c.model()
        let ids = ToolContext.created(r).filter { nm[$0]?.category == .structuralFraming }
        return result(c, ["beams": .array(ids.map(\.json)), "type": .string(ToolContext.typeLabel(type, nm))], ids: ids)
    }

    // MARK: Circulation

    func createStair(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let base = try c.args["base_level"].map { try c.level($0, "base_level") } ?? (try c.levelOrViewLevel())
        let top = try c.args["top_level"].map { try c.level($0, "top_level") } ?? m.levelAbove(base.id)
        guard let top, (top.level?.elevation ?? 0) > (base.level?.elevation ?? 0) else { throw ToolError("top_level must be above base_level “\(base.name)”.") }
        let type = try c.type(c.args["type"], category: .stairs)
        let defW = m.units.system == .imperial ? 3 * 0.3048 : 1.0
        var runs: [StairRun] = []
        for (k, r) in try c.args.requireArray("runs").enumerated() {
            let what = "runs[\(k)]"
            guard let sv = r["start"], let dv = r["direction"] else { throw ToolError("\(what) needs start and direction.") }
            let shape: StairRunShape
            switch r["shape"]?.stringValue?.lowercased() ?? "straight" {
            case "straight": shape = .straight
            case "spiral": shape = .spiral
            case "l_winder": shape = .lWinder
            case "u_winder": shape = .uWinder
            default: throw ToolError("\(what).shape must be straight, spiral, l_winder or u_winder.")
            }
            let risers = r["risers"]?.intValue ?? 0
            runs.append(StairRun(shape: shape, start: try c.point(sv, what + ".start"), direction: try c.angle(dv, what + ".direction"), risers: risers,
                                 width: try r["width"].map { try c.length($0, what + ".width") } ?? defW))
        }
        let rise = (top.level?.elevation ?? 0) - (base.level?.elevation ?? 0)
        // The riser count the type's Maximum Riser Height asks for (as Desired Number of Risers).
        let probe = Element(id: ElementID(UInt64.max - 5), category: .stairs, data: .stair(StairData(origin: runs[0].start, direction: runs[0].direction, width: runs[0].width, topLevelID: top.id)),
                            typeID: type.id, levelID: base.id)
        let total = max(3, StairGeometry.numbers(probe, m)?.desired ?? Int((rise / (m.units.system == .imperial ? 7 * 0.0254 : 0.18)).rounded(.up)))
        if runs.allSatisfy({ $0.risers <= 0 }) {
            let each = total / runs.count
            for i in runs.indices { runs[i].risers = i == runs.count - 1 ? total - each * (runs.count - 1) : each }
        } else if runs.contains(where: { $0.risers <= 0 }) {
            throw ToolError("Give risers for every run, or for none (they are spread to reach \(top.name)).")
        }
        runs = StairComponents.redistribute(runs, to: max(total, runs.reduce(0) { $0 + $1.risers }))
        let railType = c.args.bool("railings", default: true) ? m.types(for: .railings).first { $0.name.lowercased().contains("handrail") } ?? m.types(for: .railings).first : nil
        let r = try c.edit("Create Stair") { tx in
            var sd = StairData(shape: .straight, origin: runs[0].start, direction: runs[0].direction, width: runs[0].width, topLevelID: top.id)
            sd.runs = runs
            let sid = tx.create(.stairs, data: .stair(sd), typeID: type.id, levelID: base.id)
            if let railType {
                for side in [true, false] {
                    var rd = RailingData(path: [])
                    rd.followsHost = true; rd.hostSideLeft = side
                    tx.create(.railings, data: .railing(rd), typeID: railType.id, levelID: base.id, hostID: sid)
                }
            }
        }
        let nm = try c.model()
        let ids = ToolContext.created(r)
        let stair = ids.compactMap { nm[$0] }.first { $0.category == .stairs }
        var o: [String: JSONValue] = ["stair": stair?.id.json ?? .null, "runs": .array(runs.map { .int($0.risers) }), "rise": .string(c.formatLength(rise, nm))]
        if let s = stair { for n in ["Actual Number of Risers", "Actual Riser Height", "Actual Tread Depth"] { if let v = paramText(s, n, nm) { o[n.lowercased().replacingOccurrences(of: " ", with: "_")] = .string(v) } } }
        return result(c, o, ids: ids)
    }

    func createRamp(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let level = try c.levelOrViewLevel()
        let top = try c.args["top_level"].map { try c.level($0, "top_level") } ?? m.levelAbove(level.id)
        let path = try c.points(c.args["path"] ?? .null, "path")
        let width = try c.length("width") ?? (m.units.system == .imperial ? 4 * 0.3048 : 1.2)
        let rd = RampData(path: path, width: width, topLevelID: top?.id)
        let probe = Element(id: ElementID(UInt64.max - 3), category: .ramps, data: .ramp(rd), typeID: m.types(for: .ramps).first?.id, levelID: level.id)
        if let reason = RampGeometry.invalidReason(probe, m) { throw ToolError(reason) }
        let existing = m.types(for: .ramps).first?.id
        let concrete = m.material(named: "Concrete, Cast-in-Place")?.id
        let railType = c.args.bool("railings", default: true) ? m.types(for: .railings).first?.id : nil
        let r = try c.edit("Create Ramp") { tx in
            let type = existing ?? tx.create(.elementTypes, name: RampGeometry.defaultTypeName, data: .type(RampGeometry.defaultType(material: concrete)))
            let rid = tx.create(.ramps, data: .ramp(rd), typeID: type, levelID: level.id)
            if let railType {
                for left in [true, false] {
                    var rail = RailingData(path: [])
                    rail.followsHost = true; rail.hostSideLeft = left
                    tx.create(.railings, data: .railing(rail), typeID: railType, levelID: level.id, hostID: rid)
                }
            }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        return result(c, ["ramp": ids.first { nm[$0]?.category == .ramps }?.json ?? .null, "railings": .int(ids.filter { nm[$0]?.category == .railings }.count)], ids: ids)
    }

    // MARK: Openings

    func createOpening(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let kind = try c.args.requireString("kind").lowercased()
        let r: TransactionRecord?
        switch kind {
        case "wall":
            guard let wv = c.args["wall"] else { throw ToolError("A wall opening needs wall (id).") }
            let w = try c.element(wv, "wall")
            guard let wd = w.wall else { throw ToolError("Element \(w.id.raw) is not a wall.") }
            let len = wd.location.length
            let width = try c.length("width") ?? (m.units.system == .imperial ? 3 * 0.3048 : 0.9)
            let center = try c.length("offset") ?? len / 2
            let s = center - width / 2, e = center + width / 2
            guard s >= 0, e <= len else { throw ToolError("The opening (\(c.formatLength(s, m)) to \(c.formatLength(e, m)) from the start) runs off the wall (length \(c.formatLength(len, m))).") }
            let bottom = try c.length("bottom") ?? 0, top = try c.length("top") ?? (m.units.system == .imperial ? 7 * 0.3048 : 2.1)
            guard top > bottom else { throw ToolError("top must be above bottom.") }
            r = try c.edit("Wall Opening") { tx in tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: s, end: e, bottom: bottom, top: top))), levelID: w.levelID, hostID: w.id) }
        case "shaft":
            guard let b = try boundary(c) else { throw ToolError("A shaft needs boundary points.") }
            let level = try c.levelOrViewLevel()
            let top = try c.args["top_level"].map { try c.level($0, "top_level") } ?? m.levels.max { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
            r = try c.edit("Shaft Opening") { tx in tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(polygon: b), topLevelID: top?.id))), levelID: level.id) }
        case "vertical":
            guard let hv = c.args["host"] else { throw ToolError("A vertical opening needs host (a floor, ceiling or roof id).") }
            let host = try c.element(hv, "host")
            guard [.floors, .ceilings, .roofs].contains(host.category) else { throw ToolError("host must be a floor, ceiling or roof.") }
            guard let b = try boundary(c) else { throw ToolError("A vertical opening needs boundary points.") }
            r = try c.edit("Vertical Opening") { tx in
                tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(polygon: b), hosted: .vertical))), levelID: host.levelID, hostID: host.id)
            }
        default: throw ToolError("kind must be wall, shaft or vertical.")
        }
        let ids = ToolContext.created(r)
        return result(c, ["opening": ids.first?.json ?? .null, "kind": .string(kind)], ids: ids)
    }

    // MARK: Areas, separators, lines

    func placeAreas(_ c: ToolContext) throws -> ToolOutput {
        let level = try c.levelOrViewLevel()
        let rentable = c.args.string("scheme")?.lowercased() == "rentable"
        var planID: ElementID?
        try c.edit("Area Plan") { tx in
            let schemes = AreaPlans.ensureDefaultSchemes(in: tx)
            let sorted = AreaPlans.sortedSchemes(tx.model)
            guard let scheme = (rentable ? sorted.first { $0.name.lowercased().contains("rentable") } : sorted.first { $0.name.lowercased().contains("gross") })?.id ?? schemes.first else {
                throw TransactionError("No area schemes.")
            }
            let plan = AreaPlans.createAreaPlan(level: level.id, scheme: scheme, scale: tx.model.units.system == .imperial ? 96 : 100, automaticBoundary: true, in: tx)
            _ = RoomPlacement.placeAutomatically(level: level.id, in: tx, areaScheme: scheme, tagType: TagTool.defaultTagType(for: .areas, tx.model), tagView: plan)
            planID = plan
        }
        let nm = try c.model()
        let areas = nm.elements(.areas).filter { $0.levelID == level.id }
        var total = 0.0
        let out: [JSONValue] = areas.map { a in
            let b = RoomGeometry.boundary(a, nm)
            total += b.area
            return ["id": a.id.json, "name": .string(a.name), "area": c.areaNumber(b.area, nm), "bounded": .bool(b.state == .bounded)]
        }
        if let planID { _ = (host as? any DocumentUIHost)?.activateView(planID) }
        return result(c, ["area_plan": planID?.json ?? .null, "areas": .array(out), "total_area": .string(c.formatArea(total, nm))], ids: areas.map(\.id))
    }

    func addRoomSeparators(_ c: ToolContext) throws -> ToolOutput {
        let segs = try segments(c)
        let area = c.args.string("kind")?.lowercased() == "area"
        let level = try c.levelOrViewLevel()
        let r = try c.edit(area ? "Area Boundary" : "Room Separator") { tx in
            for s in segs { tx.create(area ? .areaBoundaryLines : .roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(s))), levelID: level.id) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let rooms = nm.elements(area ? .areas : .rooms).filter { $0.levelID == level.id }
        let unbounded = rooms.filter { RoomGeometry.boundary($0, nm).state != .bounded }
        return result(c, ["lines": .array(ids.map(\.json)), "rooms_on_level": .int(rooms.count)], ids: ids,
                      problems: unbounded.map { "\(area ? "Area" : "Room") \($0.room?.number ?? "") \($0.name) is not enclosed." })
    }

    func addModelLines(_ c: ToolContext) throws -> ToolOutput {
        let segs = try segments(c)
        let planes = c.args.string("kind")?.lowercased() == "reference_plane"
        let names = c.args.array("names")?.compactMap(\.stringValue) ?? []
        let level = planes ? nil : try c.levelOrViewLevel()
        let r = try c.edit(planes ? "Reference Plane" : "Model Line") { tx in
            for (k, s) in segs.enumerated() {
                if planes {
                    tx.create(.referencePlanes, name: k < names.count ? names[k] : "Reference Plane \(tx.model.elements(.referencePlanes).count + 1)", data: .referencePlane(ReferencePlaneData(line: s)))
                } else {
                    tx.create(.genericModels, data: .modelLine(ModelLineData(curve: .line(s))), levelID: level?.id)
                }
            }
        }
        let ids = ToolContext.created(r)
        return result(c, [planes ? "reference_planes" : "model_lines": .array(ids.map(\.json))], ids: ids)
    }

    // MARK: Site and mass

    func createToposolid(_ c: ToolContext) throws -> ToolOutput {
        var id: ElementID?
        if let pv = c.args.array("points") {
            var pts: [Vec3] = []
            for (k, p) in pv.enumerated() {
                guard let a = p.arrayValue, a.count == 3 else { throw ToolError("points[\(k)] must be [x, y, z].") }
                pts.append(Vec3(try c.length(a[0], "x"), try c.length(a[1], "y"), try c.length(a[2], "z")))
            }
            guard pts.count >= 3 else { throw ToolError("Give at least 3 survey points.") }
            try c.edit("Create Toposolid") { tx in id = try ToposolidOperations.create(points: pts, name: c.args.string("name") ?? "Toposolid", in: tx).0 }
        } else if let b = try boundary(c, "outline") {
            let z = try c.length("elevation") ?? 0
            try c.edit("Create Toposolid") { tx in id = try ToposolidOperations.create(outline: b, elevation: z, name: c.args.string("name") ?? "Toposolid", in: tx) }
        } else { throw ToolError("Give outline (plan points) with elevation, or points [[x, y, z], …].") }
        return result(c, ["toposolid": id?.json ?? .null], ids: id.map { [$0] } ?? [])
    }

    func createBuildingPad(_ c: ToolContext) throws -> ToolOutput {
        try ensureTypes(c, .buildingPads)
        let level = try c.levelOrViewLevel()
        guard let b = try boundary(c) else { throw ToolError("Missing boundary.") }
        let type = try c.type(c.args["type"], category: .buildingPads)
        let off = try c.length("offset") ?? 0
        let r = try c.edit("Building Pad") { tx in tx.create(.buildingPads, data: .slab(SlabData(boundary: Sketch(polygon: b), offset: off)), typeID: type.id, levelID: level.id) }
        let ids = ToolContext.created(r)
        let m = try c.model()
        return result(c, ["pad": ids.first?.json ?? .null, "area": .string(c.formatArea(b.area, m))], ids: ids)
    }

    func createMass(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let level = try c.levelOrViewLevel()
        guard let b = try boundary(c) else { throw ToolError("Missing boundary.") }
        let h = try c.length("height") ?? MassGeometry.defaultHeight(m.units)
        let inset = try c.length("top_inset")
        var id: ElementID?
        try c.edit("In-Place Mass") { tx in id = try MassGeometry.create(boundary: b.points, height: h, topInset: inset, level: level.id, in: tx) }
        return result(c, ["mass": id?.json ?? .null, "height": .string(c.formatLength(h, m))], ids: id.map { [$0] } ?? [])
    }
}
