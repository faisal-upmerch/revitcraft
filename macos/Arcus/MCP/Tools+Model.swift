import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

// MCP: building tools: levels, grids, walls, doors and windows, floors, ceilings, roofs, stairs, railings, rooms,
// components, and generic edits (parameters, move, delete, undo).

extension ArcusToolbox {
    // MARK: Datums

    func addLevels(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var specs: [(String, Double, Bool)] = []
        for (k, s) in try c.args.requireArray("levels").enumerated() {
            guard let n = s["name"]?.stringValue, let ev = s["elevation"] else { throw ToolError("levels[\(k)] needs name and elevation.") }
            if m.level(named: n) != nil { throw ToolError("A level named “\(n)” already exists. Use set_parameters to move it.") }
            specs.append((n, try c.length(ev, "levels[\(k)].elevation"), s["ceiling_plan"]?.boolValue ?? false))
        }
        let phase = m.latestPhase?.id
        let scale = m.units.system == .imperial ? 48 : 100
        let r = try c.edit("Create Level") { tx in
            for (n, z, rcp) in specs {
                let lid = tx.create(.levels, name: n, data: .level(LevelData(elevation: z)))
                for k in rcp ? [ViewKind.floorPlan, .ceilingPlan] : [.floorPlan] {
                    var v = ViewData(kind: k, scale: scale); v.phaseID = phase
                    tx.create(.views, name: n, data: .view(v), levelID: lid)
                }
            }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let levels = ids.compactMap { nm[$0] }.filter { $0.level != nil }
        return result(c, ["levels": .array(levels.map { ["id": $0.id.json, "name": .string($0.name), "elevation": c.out($0.level?.elevation ?? 0, nm)] })], ids: ids)
    }

    func addGrids(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        var lines: [(String?, Segment2)] = []
        for (k, l) in (c.args.array("lines") ?? []).enumerated() {
            guard let s = l["start"], let e = l["end"] else { throw ToolError("lines[\(k)] needs start and end.") }
            lines.append((l["name"]?.stringValue, Segment2(try c.point(s, "lines[\(k)].start"), try c.point(e, "lines[\(k)].end"))))
        }
        var xs: [Double] = [], ys: [Double] = []
        for (k, v) in (c.args.array("x") ?? []).enumerated() { xs.append(try c.length(v, "x[\(k)]")) }
        for (k, v) in (c.args.array("y") ?? []).enumerated() { ys.append(try c.length(v, "y[\(k)]")) }
        guard !lines.isEmpty || !xs.isEmpty || !ys.isEmpty else { throw ToolError("Give lines, or x and/or y positions.") }
        let pad = 5 * ToolContext.unitScale(m).meters * (m.units.system == .imperial ? 1 : 200)
        var lo = (xs + ys).min() ?? 0, hi = (xs + ys).max() ?? 0
        if let ext = c.args.array("extent"), ext.count == 2 { lo = try c.length(ext[0], "extent[0]") + pad; hi = try c.length(ext[1], "extent[1]") - pad }
        let xr = (ys.min().map { min($0, lo) } ?? lo) - pad, xr2 = (ys.max().map { max($0, hi) } ?? hi) + pad
        let yr = (xs.min().map { min($0, lo) } ?? lo) - pad, yr2 = (xs.max().map { max($0, hi) } ?? hi) + pad
        for (k, x) in xs.sorted().enumerated() { lines.append(("\(k + 1)", Segment2(Vec2(x, xr), Vec2(x, xr2)))) }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        for (k, y) in ys.sorted().enumerated() { lines.append((k < letters.count ? String(letters[k]) : "A\(k)", Segment2(Vec2(yr, y), Vec2(yr2, y)))) }
        let taken = Set(m.elements(.grids).map(\.name))
        for (n, _) in lines { if let n, taken.contains(n) { throw ToolError("A grid named “\(n)” already exists.") } }
        let r = try c.edit("Create Grid") { tx in
            for (n, s) in lines { tx.create(.grids, name: n ?? GridNaming.next(after: tx.model.elements(.grids).map(\.name)), data: .grid(GridData(curve: .line(s)))) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        return result(c, ["grids": .array(ids.compactMap { nm[$0] }.map { ["id": $0.id.json, "name": .string($0.name)] })], ids: ids)
    }

    // MARK: Walls

    static func locationLine(_ s: String?) throws(ToolError) -> WallLocationLine {
        switch s?.lowercased().replacingOccurrences(of: " ", with: "_") {
        case nil, "centerline", "wall_centerline", "center": return .wallCenterline
        case "core_centerline": return .coreCenterline
        case "exterior_face", "finish_face_exterior": return .finishFaceExterior
        case "interior_face", "finish_face_interior": return .finishFaceInterior
        case "core_exterior", "core_face_exterior": return .coreFaceExterior
        case "core_interior", "core_face_interior": return .coreFaceInterior
        default: throw ToolError("location_line must be centerline, core_centerline, exterior_face, interior_face, core_exterior or core_interior.")
        }
    }

    func createWalls(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard !m.isFurniture else { throw ToolError("Walls go in projects. In a Furniture document use add_furniture_parts (panels).") }
        let level = try c.level(c.args["level"])
        let type = try c.type(c.args["type"], category: .walls) { ts in
            ts.first { $0.typeData?.systemFamily == .basicWall && $0.name.hasPrefix("Generic") } ?? ts.first { $0.typeData?.systemFamily == .basicWall }
        }
        var segs: [Segment2] = []
        if let pv = c.args["points"] {
            let pts = try c.points(pv, "points")
            for k in 0..<(pts.count - 1) { segs.append(Segment2(pts[k], pts[k + 1])) }
            if c.args.bool("closed", default: false), pts.count >= 3, !pts[0].isAlmostEqual(pts[pts.count - 1], tolerance: 1e-6) { segs.append(Segment2(pts[pts.count - 1], pts[0])) }
        }
        for (k, s) in (c.args.array("segments") ?? []).enumerated() {
            let p = try c.points(s, "segments[\(k)]")
            segs.append(Segment2(p[0], p[1]))
        }
        guard !segs.isEmpty else { throw ToolError("Give points (a polyline) or segments.") }
        for (k, s) in segs.enumerated() where s.length < 0.05 { throw ToolError("Wall \(k + 1) is too short (\(c.formatLength(s.length, m))). Check the points.") }
        let top: Element? = try c.args["top_level"].map { try c.level($0, "top_level") }
            ?? (c.args["height"] == nil ? m.levelAbove(level.id) : nil)
        if let top, (top.level?.elevation ?? 0) <= (level.level?.elevation ?? 0) { throw ToolError("top_level “\(top.name)” must be above “\(level.name)”.") }
        let height = try c.length("height") ?? (m.units.system == .imperial ? 10 * 0.3048 : 3.0)
        let topOffset = try c.length("top_offset") ?? 0, baseOffset = try c.length("base_offset") ?? 0
        let ll = try Self.locationLine(c.args.string("location_line"))
        let structural = c.args.bool("structural", default: false), bounding = c.args.bool("room_bounding", default: true)
        let r = try c.edit("Create Walls") { tx in
            for s in segs {
                var wd = WallData(location: .line(s), locationLine: ll, baseOffset: baseOffset, topLevelID: top?.id, topOffset: topOffset, unconnectedHeight: height)
                wd.structural = structural
                wd.roomBounding = bounding
                tx.create(.walls, data: .wall(wd), typeID: type.id, levelID: level.id)
            }
            Self.fitTemplateElevations(in: tx)
        }
        let ids = ToolContext.created(r).filter { (try? c.model())?[$0]?.category == .walls }
        let nm = try c.model()
        let walls: [JSONValue] = ids.compactMap { nm[$0] }.map { w in
            let seg = w.wall.map { ($0.location.start, $0.location.end) }
            return ["id": w.id.json, "start": c.out(seg?.0 ?? .zero, nm), "end": c.out(seg?.1 ?? .zero, nm), "length": .string(c.formatLength(w.wall?.location.length ?? 0, nm))]
        }
        let thickness = WallGeometry.frame(nm[ids.first]!, nm)?.thickness ?? 0
        return result(c, ["walls": .array(walls), "type": .string(ToolContext.typeLabel(type, nm)), "thickness": .string(c.formatLength(thickness, nm)),
                          "level": .string(level.name), "top": .string(top.map { "\($0.name)\(topOffset == 0 ? "" : " + " + c.formatLength(topOffset, nm))" } ?? "unconnected \(c.formatLength(height, nm))")],
                      ids: ids)
    }

    // MARK: Doors and windows

    func placeInserts(_ c: ToolContext, doors: Bool) throws -> ToolOutput {
        let key = doors ? "doors" : "windows"
        let cat: Category = doors ? .doors : .windows
        let m = try c.model()
        struct Spec { var host: Element; var at: Vec2; var type: Element; var sill: Double; var mark: String?; var flipF: Bool; var flipH: Bool }
        var specs: [Spec] = []
        for (k, d) in try c.args.requireArray(key).enumerated() {
            let what = "\(key)[\(k)]"
            guard let hv = d["wall"] else { throw ToolError("\(what) needs its host wall id.") }
            let host = try c.element(hv, what + ".wall")
            guard let wd = host.wall else { throw ToolError("\(what).wall: element \(host.id.raw) is a \(host.category.singularName.lowercased()), not a wall.") }
            let len = wd.location.length
            var station: Double
            if let o = d["offset"] { station = try c.length(o, what + ".offset") } else if let p = d["point"] {
                station = WallGeometry.station(of: try c.point(p, what + ".point"), on: wd.location)
            } else { station = len / 2 }
            guard station > 0, station < len else {
                throw ToolError("\(what): offset \(c.formatLength(station, m)) is outside wall \(host.id.raw) (length \(c.formatLength(len, m))).")
            }
            let type = try c.type(d["type"], category: cat, what: what + ".type") { ts in
                let word = doors ? "Single Flush" : "Casement"
                return ts.first { ToolContext.typeLabel($0, m).contains(word) && ToolContext.typeLabel($0, m).contains("36") } ?? ts.first { ToolContext.typeLabel($0, m).contains(word) }
            }
            let defSill = doors ? 0 : (m.units.system == .imperial ? 3 * 0.3048 : 0.9)
            let sill = try d["sill_height"].map { try c.length($0, what + ".sill_height") } ?? (type.typeData?.params[Parameters.familyParamID("Default Sill Height")]?.doubleValue ?? defSill)
            specs.append(Spec(host: host, at: WallGeometry.point(atStation: station, on: wd.location), type: type, sill: doors ? 0 : sill, mark: d["mark"]?.stringValue,
                              flipF: d["flip_facing"]?.boolValue ?? false, flipH: d["flip_hand"]?.boolValue ?? false))
        }
        let r = try c.edit(doors ? "Place Doors" : "Place Windows") { tx in
            for s in specs {
                tx.create(cat, data: .insert(InsertData(location: s.at, sillHeight: s.sill)), typeID: s.type.id, levelID: s.host.levelID, hostID: s.host.id) { e in
                    if let mk = s.mark { e.mark = mk }
                    e.insert?.facingFlipped = s.flipF
                    e.insert?.handFlipped = s.flipH
                }
            }
        }
        let ids = ToolContext.created(r).filter { (try? c.model())?[$0]?.category == cat }
        let nm = try c.model()
        let out: [JSONValue] = ids.compactMap { nm[$0] }.map { e in
            var o: [String: JSONValue] = ["id": e.id.json, "wall": e.hostID.map(\.json) ?? .null, "type": .string(nm.type(of: e).map { ToolContext.typeLabel($0, nm) } ?? "")]
            if !e.mark.isEmpty { o["mark"] = .string(e.mark) }
            if let w = nm[e.hostID]?.wall, let p = e.insert?.location { o["offset"] = c.out(WallGeometry.station(of: p, on: w.location), nm) }
            return .object(o)
        }
        return result(c, [key: .array(out)], ids: ids)
    }

    // MARK: Floors, ceilings, roofs

    /// The outline of a level's walls: their outer faces (exterior) or the inside of the exterior walls (interior).
    func wallOutline(_ c: ToolContext, level: ElementID, exterior: Bool) throws(ToolError) -> Polygon2 {
        let m = try c.model()
        let walls = m.elements(.walls).filter { $0.levelID == level }
        let prints = walls.compactMap { WallGeometry.footprint($0, m) }
        guard !prints.isEmpty else { throw ToolError("Level “\(m[level]?.name ?? "")” has no walls. Give a boundary instead.") }
        guard let u = PolygonBoolean.union(prints.map { Profile2(outer: $0) }).max(by: { $0.outer.area < $1.outer.area }), !u.holes.isEmpty else {
            throw ToolError("The walls on “\(m[level]?.name ?? "")” don't enclose an area. Close the exterior loop (create_walls with closed: true) or give a boundary.")
        }
        let outer = u.outer.counterClockwise.simplified()
        if exterior { return outer }
        // The exterior walls are the ones whose outer face lies on the outline: shrink by their thickness.
        let edges = outer.edges
        let t = walls.compactMap { w -> Double? in
            guard let f = WallGeometry.frame(w, m) else { return nil }
            let mid = f.location.point(at: 0.5)
            return edges.contains { $0.distance(to: mid) < f.thickness / 2 + 0.01 } ? f.thickness : nil
        }.max() ?? 0
        guard let inner = outer.offset(by: -t).max(by: { $0.area < $1.area }) else { throw ToolError("The walls leave no interior area.") }
        return inner.counterClockwise.simplified()
    }

    func boundary(_ c: ToolContext, _ key: String = "boundary") throws(ToolError) -> Polygon2? {
        guard let v = c.args[key] else { return nil }
        let poly = Polygon2(try c.points(v, key, min: 3)).simplified()
        guard poly.count >= 3, poly.area > 0.01 else { throw ToolError("\(key) must enclose an area (at least 3 points, not in a line).") }
        return poly.counterClockwise
    }

    func createFloor(_ c: ToolContext) throws -> ToolOutput {
        let level = try c.level(c.args["level"])
        let type = try c.type(c.args["type"], category: .floors) { ts in ts.first { $0.name.lowercased().contains("generic") } ?? ts.first }
        let poly: Polygon2
        if let b = try boundary(c) { poly = b } else if c.args.bool("from_walls", default: true) {
            poly = try wallOutline(c, level: level.id, exterior: c.args.string("edge")?.lowercased() == "exterior")
        } else { throw ToolError("Give a boundary or from_walls: true.") }
        let offset = try c.length("offset") ?? 0
        let name = c.args.string("name") ?? ""
        let structural = c.args.bool("structural", default: false)
        let r = try c.edit("Create Floor") { tx in
            var sd = SlabData(boundary: Sketch(polygon: poly), offset: offset)
            sd.structural = structural
            tx.create(.floors, name: name, data: .slab(sd), typeID: type.id, levelID: level.id)
        }
        let ids = ToolContext.created(r)
        let m = try c.model()
        return result(c, ["floor": ids.first(where: { m[$0]?.category == .floors })?.json ?? .null, "type": .string(ToolContext.typeLabel(type, m)),
                          "area": .string(c.formatArea(poly.area, m)), "boundary": .array(poly.points.map { c.out($0, m) })], ids: ids)
    }

    func createCeiling(_ c: ToolContext) throws -> ToolOutput {
        let level = try c.level(c.args["level"])
        let m = try c.model()
        let type = try c.type(c.args["type"], category: .ceilings)
        let height = try c.length("height") ?? (m.units.system == .imperial ? 8 * 0.3048 : 2.7)
        var polys: [Polygon2] = []
        if let b = try boundary(c) { polys = [b] }
        var rooms: [Element] = []
        if c.args["rooms"] != nil { rooms = try c.elementIDs("rooms").compactMap { m[$0] } }
        if c.args.bool("all_rooms", default: false) { rooms += m.elements(.rooms).filter { $0.levelID == level.id } }
        for r in rooms {
            guard r.category == .rooms else { throw ToolError("Element \(r.id.raw) is not a room.") }
            let b = RoomGeometry.boundary(r, m)
            guard b.state == .bounded, let p = b.profile else { throw ToolError("Room \(r.room?.number ?? "") \(r.name) is not bounded; it can't take a ceiling.") }
            polys.append(p.outer)
        }
        guard !polys.isEmpty else { throw ToolError("Give a boundary, rooms, or all_rooms: true.") }
        let r = try c.edit("Create Ceiling") { tx in
            for p in polys { tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(polygon: p), offset: height)), typeID: type.id, levelID: level.id) }
        }
        let ids = ToolContext.created(r).filter { (try? c.model())?[$0]?.category == .ceilings }
        return result(c, ["ceilings": .array(ids.map(\.json)), "height": .string(c.formatLength(height, m)), "type": .string(ToolContext.typeLabel(type, m))], ids: ids)
    }

    func createRoof(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let level = try c.level(c.args["level"] ?? m.levels.max { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }.map { .int(Int($0.id.raw)) })
        let type = try c.type(c.args["type"], category: .roofs)
        let shape = c.args.string("shape")?.lowercased() ?? "flat"
        guard ["flat", "shed", "gable", "hip"].contains(shape) else { throw ToolError("shape must be flat, shed, gable or hip.") }
        let slope = (c.args.double("slope") ?? 22.62) * .pi / 180
        guard shape == "flat" || (slope > 0.01 && slope < 1.4) else { throw ToolError("slope must be between 1° and 80°.") }
        let defaultOverhang = shape == "flat" ? 0 : (m.units.system == .imperial ? 1.5 * 0.3048 : 0.45)
        let overhang = try c.length("overhang") ?? defaultOverhang
        var poly: Polygon2
        if let b = try boundary(c) { poly = b } else {
            let wl = try c.args["from_walls_of"].map { try c.level($0, "from_walls_of") }
                ?? m.levels.filter { ($0.level?.elevation ?? 0) < (level.level?.elevation ?? 0) }.max { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
            guard let wl else { throw ToolError("Give a boundary, or from_walls_of a level with walls.") }
            poly = try wallOutline(c, level: wl.id, exterior: shape != "flat")
            if shape == "flat", overhang == 0 { poly = try wallOutline(c, level: wl.id, exterior: false) }
        }
        if overhang > 0, let o = poly.offset(by: overhang).max(by: { $0.area < $1.area }) { poly = o.counterClockwise.simplified() }
        let edges = poly.edges
        var slopes: [Double?] = Array(repeating: nil, count: edges.count)
        switch shape {
        case "hip": slopes = Array(repeating: slope, count: edges.count)
        case "shed": if !edges.isEmpty { slopes[0] = slope }
        case "gable":
            // The two longest edges (eaves) slope; the short ends are gables.
            let order = edges.indices.sorted { edges[$0].length > edges[$1].length }
            for i in order.prefix(2) { slopes[i] = slope }
        default: break
        }
        let baseOffset = try c.length("base_offset") ?? 0
        let r = try c.edit("Create Roof") { tx in
            tx.create(.roofs, name: "Roof", data: .roof(RoofData(footprint: Sketch(polygon: poly), edgeSlopes: slopes, baseOffset: baseOffset, overhang: overhang)), typeID: type.id, levelID: level.id)
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        return result(c, ["roof": ids.first(where: { nm[$0]?.category == .roofs })?.json ?? .null, "shape": .string(shape), "level": .string(level.name),
                          "type": .string(ToolContext.typeLabel(type, nm)), "footprint_area": .string(c.formatArea(poly.area, nm))], ids: ids)
    }

    // MARK: Circulation

    func addStair(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let base = try c.level(c.args["base_level"])
        let top = try c.args["top_level"].map { try c.level($0, "top_level") } ?? m.levelAbove(base.id)
        guard let top, (top.level?.elevation ?? 0) > (base.level?.elevation ?? 0) else { throw ToolError("top_level must be a level above base_level “\(base.name)”.") }
        guard let sv = c.args["start"], let dv = c.args["direction"] else { throw ToolError("Give start and direction.") }
        let start = try c.point(sv, "start")
        let dir = try c.angle(dv, "direction")
        let shape: StairShape
        switch c.args.string("shape")?.lowercased() {
        case nil, "straight": shape = .straight
        case "l_shaped", "l", "l-shaped": shape = .lShaped
        case "u_shaped", "u", "u-shaped": shape = .uShaped
        default: throw ToolError("shape must be straight, l_shaped or u_shaped.")
        }
        let width = try c.length("width") ?? (m.units.system == .imperial ? 3 * 0.3048 : 1.0)
        let type = try c.type(c.args["type"], category: .stairs)
        let railType = c.args.bool("railings", default: true)
            ? try c.type(c.args["railing_type"], category: .railings) { ts in ts.first { $0.name.lowercased().contains("handrail") } ?? ts.first } : nil
        let risers = c.args.int("risers"), first = c.args.int("first_run_risers")
        if let risers, risers < 3 || risers > 40 { throw ToolError("risers must be between 3 and 40.") }
        let left = c.args.string("turn")?.lowercased() != "right"
        let r = try c.edit("Create Stair") { tx in
            var sd = StairData(shape: shape, origin: start, direction: dir, width: width, topLevelID: top.id)
            sd.desiredRiserCount = risers
            sd.firstRunRisers = first
            sd.turnsLeft = left
            let sid = tx.create(.stairs, data: .stair(sd), typeID: type.id, levelID: base.id)
            if let railType {
                for side in [true, false] {
                    var rd = RailingData(path: [])
                    rd.followsHost = true; rd.hostSideLeft = side
                    tx.create(.railings, data: .railing(rd), typeID: railType.id, levelID: base.id, hostID: sid)
                }
            }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let stair = ids.compactMap { nm[$0] }.first { $0.category == .stairs }
        var o: [String: JSONValue] = ["stair": stair?.id.json ?? .null, "railings": .array(ids.filter { nm[$0]?.category == .railings }.map(\.json)),
                                      "type": .string(ToolContext.typeLabel(type, nm)), "rise": .string(c.formatLength((top.level?.elevation ?? 0) - (base.level?.elevation ?? 0), nm))]
        if let s = stair { for n in ["Actual Number of Risers", "Actual Riser Height", "Actual Tread Depth"] { if let v = paramText(s, n, nm) { o[n.lowercased().replacingOccurrences(of: " ", with: "_")] = .string(v) } } }
        return result(c, o, ids: ids)
    }

    func addRailing(_ c: ToolContext) throws -> ToolOutput {
        let type = try c.type(c.args["type"], category: .railings)
        if c.args["stair"] != nil {
            let stair = try c.element(c.args["stair"]!, "stair")
            guard stair.category == .stairs else { throw ToolError("stair: element \(stair.id.raw) is not a stair.") }
            let r = try c.edit("Create Railing") { tx in
                for side in [true, false] {
                    var rd = RailingData(path: [])
                    rd.followsHost = true; rd.hostSideLeft = side
                    tx.create(.railings, data: .railing(rd), typeID: type.id, levelID: stair.levelID, hostID: stair.id)
                }
            }
            let ids = ToolContext.created(r)
            return result(c, ["railings": .array(ids.map(\.json))], ids: ids)
        }
        let level = try c.level(c.args["level"])
        guard let pv = c.args["path"] else { throw ToolError("Give a path (points) or a stair id.") }
        let pts = try c.points(pv, "path")
        let base = try c.length("base_offset") ?? 0
        let r = try c.edit("Create Railing") { tx in
            let curves: [Curve2] = (0..<(pts.count - 1)).map { .line(Segment2(pts[$0], pts[$0 + 1])) }
            tx.create(.railings, data: .railing(RailingData(path: curves, baseOffset: base)), typeID: type.id, levelID: level.id)
        }
        let ids = ToolContext.created(r)
        let m = try c.model()
        return result(c, ["railing": ids.first.map(\.json) ?? .null, "type": .string(ToolContext.typeLabel(type, m))], ids: ids)
    }

    // MARK: Rooms

    func placeRooms(_ c: ToolContext) throws -> ToolOutput {
        let level = try c.level(c.args["level"])
        let m = try c.model()
        let tag = c.args.bool("tag", default: true)
        let plan = c.planView(of: level.id, m)
        let tagType = tag ? TagTool.defaultTagType(for: .rooms, m) : nil
        struct Spec { var name: String; var point: Vec2; var number: String?; var dept: String?; var finish: String? }
        var specs: [Spec] = []
        for (k, r) in (c.args.array("rooms") ?? []).enumerated() {
            guard let p = r["point"] else { throw ToolError("rooms[\(k)] needs a point.") }
            specs.append(Spec(name: r["name"]?.stringValue ?? "Room", point: try c.point(p, "rooms[\(k)].point"), number: r["number"]?.stringValue,
                              dept: r["department"]?.stringValue, finish: r["floor_finish"]?.stringValue))
        }
        let auto = c.args.bool("auto", default: specs.isEmpty)
        let limit = m.levelAbove(level.id).map { ($0.level?.elevation ?? 0) - (level.level?.elevation ?? 0) } ?? (m.units.system == .imperial ? 9 * 0.3048 : 2.7)
        let r = try c.edit(auto ? "Place Rooms Automatically" : "Place Rooms") { tx in
            var next = RoomPlacement.nextNumber(level: level.id, tx.model)
            for s in specs {
                let number = s.number ?? String(next)
                next = max(next, (Int(number) ?? next) + 1)
                let id = tx.create(.rooms, name: s.name, data: .room(RoomData(point: s.point, number: number, limitOffset: limit)), levelID: level.id) { e in
                    if let d = s.dept { e.params[ParameterID("room.department")] = .text(d) }
                    if let f = s.finish { e.params[ParameterID("room.floorFinish")] = .text(f) }
                }
                if let tagType, let plan { tx.create(.tags, data: .tag(TagData(taggedID: id, head: s.point)), typeID: tagType, ownerViewID: plan.id) }
            }
            if auto { RoomPlacement.placeAutomatically(level: level.id, in: tx, tagType: tagType, tagView: tagType == nil ? nil : plan?.id) }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let bounds = RoomGeometry.boundaries(level: level.id, nm)
        let rooms = ids.compactMap { nm[$0] }.filter { $0.category == .rooms }
        var total = 0.0
        let out: [JSONValue] = rooms.map { e in
            let b = bounds[e.id]
            total += b?.area ?? 0
            return ["id": e.id.json, "name": .string(e.name), "number": .string(e.room?.number ?? ""), "area": c.areaNumber(b?.area ?? 0, nm),
                    "bounded": .bool(b?.state == .bounded), "point": c.out(e.room?.point ?? .zero, nm)]
        }
        var o: [String: JSONValue] = ["rooms": .array(out), "area_unit": .string(nm.units.system == .imperial ? "SF" : "m²"), "total_area": .string(c.formatArea(total, nm))]
        if auto && rooms.isEmpty { o["note"] = "No new enclosed regions: every region already has a room, or the walls don't enclose any (check that wall ends meet)." }
        let unbounded = rooms.filter { bounds[$0.id]?.state != .bounded }
        if !unbounded.isEmpty { o["fix"] = .string("Rooms \(unbounded.map { $0.room?.number ?? "" }.joined(separator: ", ")) are not enclosed: add walls or room separation lines, or move them with set_parameters / delete them.") }
        return result(c, o, ids: ids)
    }

    // MARK: Components

    func placeComponents(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard !m.isFurniture else { throw ToolError("Components go in projects. In a Furniture document use add_furniture_parts.") }
        struct Spec { var item: ComponentLibraryItem?; var loadedType: Element?; var typeName: String; var point: Vec2; var level: Element; var rotation: Double; var offset: Double }
        var specs: [Spec] = []
        for (k, d) in try c.args.requireArray("components").enumerated() {
            let what = "components[\(k)]"
            guard let fam = d["family"]?.stringValue, let pv = d["point"] else { throw ToolError("\(what) needs family and point.") }
            let level = try c.level(d["level"])
            let rot: Double
            if let r = d["rotation"]?.doubleValue { rot = r * .pi / 180 } else if let f = d["facing"] { rot = try c.angle(f, what + ".facing") + .pi / 2 } else { rot = 0 }
            let offset = try d["offset"].map { try c.length($0, what + ".offset") } ?? 0
            let point = try c.point(pv, what + ".point")
            // A family already in the document (loaded component, or a family name like "Desk")?
            if let item = ComponentLibrary.item(named: fam) ?? ComponentLibrary.items.first(where: { $0.name.caseInsensitiveCompare(fam) == .orderedSame })
                ?? Self.uniqueSearch(fam) {
                let wanted = d["type"]?.stringValue
                let tn: String
                if let wanted {
                    guard let t = item.types.first(where: { $0.name == wanted }) ?? item.types.first(where: { $0.name.lowercased().contains(wanted.lowercased()) })
                        ?? item.types.first(where: { ToolContext.tokens($0.name).joined(separator: " ").contains(ToolContext.tokens(wanted).joined(separator: " ")) }) else {
                        throw ToolError("\(what): “\(item.name)” has no type “\(wanted)”. Types: \(item.types.map(\.name).joined(separator: "; ")).")
                    }
                    tn = t.name
                } else { tn = item.defaultType(for: m.units.system).name }
                specs.append(Spec(item: item, loadedType: nil, typeName: tn, point: point, level: level, rotation: rot, offset: offset))
            } else {
                let cats: [Category] = ComponentLibrary.categories
                let loaded = cats.flatMap { m.types(for: $0) }.first { ToolContext.typeLabel($0, m).lowercased().contains(fam.lowercased()) }
                guard let loaded else {
                    let near = ComponentLibrary.search(fam.split(separator: " ").first.map(String.init) ?? fam).prefix(8).map(\.name)
                    throw ToolError("\(what): no library family “\(fam)”.\(near.isEmpty ? "" : " Similar: \(near.joined(separator: "; ")).") list_families searches the library.")
                }
                specs.append(Spec(item: nil, loadedType: loaded, typeName: loaded.name, point: point, level: level, rotation: rot, offset: offset))
            }
        }
        let r = try c.edit("Place Components") { tx in
            for s in specs {
                let tid: ElementID
                if let t = s.loadedType { tid = t.id } else {
                    guard let item = s.item, let t = ComponentLibraryLoader.load(item, typeName: s.typeName, in: tx) else { throw ToolError("Could not load \(s.item?.name ?? "") \(s.typeName).") }
                    tid = t
                }
                let cat = tx.model[tid]?.typeData?.instanceCategory ?? s.item?.category ?? .furniture
                tx.create(cat, data: .component(ComponentData(location: s.point, rotation: s.rotation, offset: s.offset)), typeID: tid, levelID: s.level.id)
            }
        }
        let ids = ToolContext.created(r)
        let nm = try c.model()
        let placed = ids.compactMap { nm[$0] }.filter { $0.component != nil }
        return result(c, ["components": .array(placed.map { e in
            ["id": e.id.json, "family": .string(nm.type(of: e).map { ToolContext.typeLabel($0, nm) } ?? ""), "category": .string(e.category.rawValue), "point": c.out(e.component?.location ?? .zero, nm)]
        })], ids: placed.map(\.id))
    }

    static func uniqueSearch(_ q: String) -> ComponentLibraryItem? {
        let hits = ComponentLibrary.search(q)
        return hits.count == 1 ? hits[0] : hits.first { $0.name.lowercased().hasPrefix(q.lowercased()) }
    }

    // MARK: Generic edits

    func paramText(_ e: Element, _ name: String, _ m: BIMModel) -> String? {
        guard let d = Parameters.descriptor(named: name, for: e, m), let v = Parameters.value(d.id, of: e, m) else { return nil }
        return Parameters.format(v, type: d.type, model: m)
    }

    func setParameters(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        guard let params = c.args["parameters"]?.objectValue, !params.isEmpty else { throw ToolError("parameters must be an object {name: value}.") }
        let onType = c.args.bool("type", default: false)
        let m = try c.model()
        let scale = ToolContext.unitScale(m).meters
        struct Change { var target: ElementID; var id: ParameterID?; var value: ParamValue?; var rename: String? }
        var changes: [Change] = []
        for id in ids {
            guard var e = m[id] else { continue }
            if onType {
                guard let t = m.type(of: e) else { throw ToolError("Element \(id.raw) has no type.") }
                e = t
            }
            for (name, v) in params.sorted(by: { $0.key < $1.key }) {
                guard let d = Parameters.descriptor(named: name, for: e, m) else {
                    if name == "Name" { changes.append(Change(target: e.id, rename: v.stringValue ?? v.jsonText)); continue }
                    let names = Parameters.allEntries(e, m).filter { !$0.isReadOnly }.map(\.name)
                    throw ToolError("\(e.category.singularName) \(e.id.raw) has no parameter “\(name)”. Editable: \(names.prefix(30).joined(separator: ", ")).")
                }
                let value: ParamValue
                if case .length = d.type, let n = v.doubleValue { value = .double(n * scale) } else if let b = v.boolValue, case .bool = d.type { value = .bool(b) } else {
                    let text = v.stringValue ?? v.doubleValue.map { String($0) } ?? v.jsonText
                    do { value = try Parameters.parse(text, type: d.type, model: m) } catch { throw ToolError("\(name): \(error.message)") }
                }
                changes.append(Change(target: e.id, id: d.id, value: value))
            }
        }
        try c.edit("Change Parameters") { tx in
            for ch in changes {
                if let n = ch.rename { tx.update(ch.target) { $0.name = n } } else if let pid = ch.id, let v = ch.value { try Parameters.set(pid, to: v, on: ch.target, in: tx) }
            }
        }
        let nm = try c.model()
        let out: [JSONValue] = Set(changes.map(\.target)).sorted().compactMap { nm[$0] }.map { e in
            var vals: [String: JSONValue] = [:]
            for name in params.keys { vals[name] = paramText(e, name, nm).map { .string($0) } ?? (name == "Name" ? .string(e.name) : .null) }
            return ["id": e.id.json, "values": .object(vals)]
        }
        return result(c, ["changed": .array(out)], ids: ids)
    }

    func moveElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        guard let bv = c.args["by"] else { throw ToolError("Missing “by” [dx, dy].") }
        let d = try c.point(bv, "by")
        try c.edit("Move") { tx in try ElementOperations.transform(ids, by: .translation(d), in: tx, viewID: nil) }
        return result(c, ["moved": .array(ids.map(\.json))], ids: ids)
    }

    /// AITOOLS: deletes given ids (or the selection). More than 5 elements in all (with what depends on them) need
    /// confirm: true; without it the result previews what would go and deletes nothing.
    func deleteElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let m = try c.model()
        let pinned = ids.filter { m[$0]?.pinned == true }
        let ok = ids.filter { !pinned.contains($0) }
        // Dry run: what the deletion takes with it.
        let probe = TransactionContext(model: m, name: "Delete")
        for id in ok { probe.delete(id) }
        let gone = m.elements.keys.filter { probe.model[$0] == nil }
        if gone.count > 5 && !c.args.bool("confirm", default: false) {
            var byCat: [String: JSONValue] = [:]
            for (cat, es) in Dictionary(grouping: gone.compactMap { m[$0] }, by: \.category) { byCat[cat.rawValue] = .int(es.count) }
            return ToolOutput(["confirm_required": true, "would_delete": .int(gone.count), "by_category": .object(byCat),
                               "note": .string("Nothing was deleted. Ask the user, then call delete_elements again with confirm: true.")])
        }
        let before = m.count
        if !ok.isEmpty { try c.edit("Delete") { tx in for id in ok { tx.delete(id) } } }
        var o: [String: JSONValue] = ["deleted": .array(ok.map(\.json)), "removed_total": .int(before - (try c.model().count))]
        if !pinned.isEmpty { o["pinned_not_deleted"] = .array(pinned.map(\.json)) }
        return result(c, o, ids: [])
    }

    func undoRedo(_ c: ToolContext, undo: Bool) throws -> ToolOutput {
        let s = try c.session()
        let steps = max(1, min(c.args.int("steps") ?? 1, 50))
        var names: [String] = []
        for _ in 0..<steps {
            if undo {
                guard s.undoManager.canUndo else { break }
                names.append(s.undoManager.undoActionName)
                s.undoManager.undo()
            } else {
                guard s.undoManager.canRedo else { break }
                names.append(s.undoManager.redoActionName)
                s.undoManager.redo()
            }
        }
        if names.isEmpty { throw ToolError(undo ? "Nothing to undo." : "Nothing to redo.") }
        return result(c, [undo ? "undone" : "redone": .array(names.map { .string($0) }), "can_undo": .bool(s.canUndo), "can_redo": .bool(s.canRedo)], ids: [])
    }
}
