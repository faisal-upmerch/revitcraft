import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// Model elements: walls, floors, ceilings, roofs, doors and windows, columns, beams, stairs, railings, rooms,
// components and reference meshes.
extension ExchangeImportSession {
    static let locationLines: [String: WallLocationLine] = [
        "wallcenterline": .wallCenterline, "corecenterline": .coreCenterline, "finishfaceexterior": .finishFaceExterior,
        "finishfaceinterior": .finishFaceInterior, "corefaceexterior": .coreFaceExterior, "corefaceinterior": .coreFaceInterior,
    ]

    /// Imports fallback geometry or records the object as skipped. `problem` completes the sentence "<what> …".
    func fallback(_ m: XMesh?, kind: String, category label: String, name: String?, levelID: ElementID?, reason: String,
                  id: String?, uniqueId: String?, skipCode: String, what: String, problem: String) {
        if referenceMesh(m, kind: kind, category: label, name: name, levelID: levelID, reason: reason, id: id, uniqueId: uniqueId) {
            warn(skipCode, "\(what) \(problem); it was imported as reference geometry.", id)
        } else {
            skip(kind, skipCode, "\(what) \(problem); it was skipped.", id)
        }
    }

    /// Base and top elevations for level-constrained elements; nil when the top is not above the base.
    func verticalRange(level lv: ElementID, baseOffset: Double, top: ElementID?, topOffset: Double, height: Double) -> (Double, Double) {
        let base = elevation(lv) + baseOffset
        let t = top.map { elevation($0) + topOffset } ?? base + height
        return (base, t)
    }

    // MARK: Walls

    func importWalls() {
        for w in doc.walls.items {
            let what = label("Wall", w.id)
            let lvOpt = optionalLevel(w.levelId)
            if let t = w.typeId, unsupportedWallTypes.contains(t) {
                fallback(w.mesh, kind: "walls", category: "Walls", name: systemTypes[t]?.name, levelID: lvOpt, reason: "curtain or stacked wall",
                         id: w.id, uniqueId: w.uniqueId, skipCode: "wall.unsupportedType",
                         what: what, problem: "uses a curtain or stacked wall type, which Arcus can't model natively")
                continue
            }
            guard let loc = curve(w.curve), loc.length >= Tolerance.shortCurve else {
                fallback(w.mesh, kind: "walls", category: "Walls", name: nil, levelID: lvOpt, reason: "no usable location line",
                         id: w.id, uniqueId: w.uniqueId, skipCode: "wall.curve", what: what, problem: "has no usable location line")
                continue
            }
            let lv = level(w.levelId, what, w.id)
            let type = systemType(w.typeId, .walls, what, w.id)
            var d = WallData(location: loc, locationLine: Self.locationLines[(w.locationLine ?? "").lowercased()] ?? .wallCenterline,
                             baseOffset: finite(w.baseOffset) ?? 0, topLevelID: optionalLevel(w.topLevelId), topOffset: finite(w.topOffset) ?? 0,
                             unconnectedHeight: finite(w.unconnectedHeight) ?? 3)
            if w.locationLine != nil, Self.locationLines[(w.locationLine ?? "").lowercased()] == nil {
                warn("wall.locationLine", "\(what) has an unknown location line “\(w.locationLine!)”; Wall Centerline was used.", w.id)
            }
            if w.topLevelId != nil, d.topLevelID == nil {
                warn("ref.level", "\(what) is constrained to a top level that was not imported; it uses its unconnected height instead.", w.id)
            }
            d.flipped = w.flipped ?? false
            d.structural = w.structural ?? false
            d.roomBounding = w.roomBounding ?? true
            d.allowJoinAtStart = w.joinAtStart ?? true
            d.allowJoinAtEnd = w.joinAtEnd ?? true
            let (b, t) = verticalRange(level: lv, baseOffset: d.baseOffset, top: d.topLevelID, topOffset: d.topOffset, height: d.unconnectedHeight)
            if t - b < 0.01 {
                if d.topLevelID != nil, let h = finite(w.unconnectedHeight), h >= 0.01 {
                    d.topLevelID = nil
                    d.unconnectedHeight = h
                    approximate("walls", "wall.height", "\(what) had its top below its base; it uses its unconnected height instead.", w.id)
                } else {
                    skip("walls", "wall.height", "\(what) has its top at or below its base and was skipped.", w.id)
                    continue
                }
            }
            let id = upsert("walls", .walls, data: .wall(d), typeID: type, levelID: lv, id: w.id, uniqueId: w.uniqueId, source: "Wall",
                            configure: common(mark: w.mark, comments: w.comments))
            if let x = w.id { hostIDs[x] = id }
        }
    }

    // MARK: Floors, ceilings, roofs

    func importSlabs(_ items: [XSlab], category: ArcusDomain.Category, kind: String) {
        for s in items {
            let what = label(category.singularName, s.id)
            let lvOpt = optionalLevel(s.levelId)
            guard let sk = sketch(s.boundary) else {
                fallback(s.mesh, kind: kind, category: category.displayName, name: nil, levelID: lvOpt, reason: "no usable boundary",
                         id: s.id, uniqueId: s.uniqueId, skipCode: "slab.boundary", what: what, problem: "has no usable boundary")
                continue
            }
            if case .failure(let err) = sk.profile() {
                fallback(s.mesh, kind: kind, category: category.displayName, name: nil, levelID: lvOpt, reason: "invalid boundary",
                         id: s.id, uniqueId: s.uniqueId, skipCode: "slab.boundary", what: what, problem: "has an invalid boundary (\(err))")
                continue
            }
            let lv = level(s.levelId, what, s.id)
            let type = systemType(s.typeId, category, what, s.id)
            var d = SlabData(boundary: sk, offset: finite(s.offset) ?? 0)
            if let a = s.slopeArrow {
                if let t = vec2(a.tail), let h = vec2(a.head), let sl = finite(a.slope), !t.isAlmostEqual(h, tolerance: 0.001), abs(sl) < 10 {
                    d.slopeArrow = SlopeArrow(tail: t, head: h, tailOffset: finite(a.tailOffset) ?? 0, slope: sl)
                } else {
                    approximate(kind, "slab.slope", "\(what) has an unreadable slope arrow; it was imported flat.", s.id)
                }
            }
            d.structural = s.structural ?? false
            d.roomBounding = s.roomBounding ?? true
            upsert(kind, category, data: .slab(d), typeID: type, levelID: lv, id: s.id, uniqueId: s.uniqueId, source: category.singularName,
                   configure: common(mark: s.mark, comments: s.comments))
        }
    }

    func importRoofs() {
        for r in doc.roofs.items {
            let what = label("Roof", r.id)
            let lvOpt = optionalLevel(r.levelId)
            let kind = (r.kind ?? "footprint").lowercased()
            guard kind == "footprint" else {
                fallback(r.mesh, kind: "roofs", category: "Roofs", name: nil, levelID: lvOpt, reason: "\(kind) roof", id: r.id, uniqueId: r.uniqueId,
                         skipCode: "roof.kind", what: what, problem: "is a \(kind) roof, which Arcus can't model natively")
                continue
            }
            // Loops with per-curve slope data.
            var loops: [[(Curve2, Double?)]] = []
            var bad = false
            var slopeDropped = false
            for l in r.footprint ?? [] {
                var loop: [(Curve2, Double?)] = []
                for c in l {
                    guard let cs = curves(c) else { bad = true; break }
                    var slope: Double?
                    if c.definesSlope == true {
                        if let a = finite(c.slopeAngle), a > 0.0001, a < .pi / 2 - 0.001 { slope = a } else { slopeDropped = true }
                    }
                    for x in cs { loop.append((x, slope)) }
                }
                if bad { break }
                if !loop.isEmpty { loops.append(loop) }
            }
            let total = loops.reduce(0) { $0 + $1.count }
            guard !bad, !loops.isEmpty, total <= options.maxCurvesPerSketch else {
                fallback(r.mesh, kind: "roofs", category: "Roofs", name: nil, levelID: lvOpt, reason: "no usable footprint", id: r.id, uniqueId: r.uniqueId,
                         skipCode: "roof.footprint", what: what, problem: "has no usable footprint")
                continue
            }
            // The largest loop is the eave line (loop 0).
            func area(_ l: [(Curve2, Double?)]) -> Double {
                if case .success(let p) = Sketch(loops: [l.map(\.0)]).polygons(), let f = p.first { return f.area }
                return 0
            }
            loops.sort { area($0) > area($1) }
            let sk = Sketch(loops: loops.map { $0.map(\.0) })
            if case .failure(let err) = sk.profile() {
                fallback(r.mesh, kind: "roofs", category: "Roofs", name: nil, levelID: lvOpt, reason: "invalid footprint", id: r.id, uniqueId: r.uniqueId,
                         skipCode: "roof.footprint", what: what, problem: "has an invalid footprint (\(err))")
                continue
            }
            if slopeDropped { approximate("roofs", "roof.slope", "\(what) has edges with unusable slope angles; those edges were made non-sloping.", r.id) }
            let lv = level(r.levelId, what, r.id)
            let type = systemType(r.typeId, .roofs, what, r.id)
            let d = RoofData(footprint: sk, edgeSlopes: loops[0].map(\.1), baseOffset: finite(r.baseOffset) ?? 0, overhang: finite(r.overhang) ?? 0)
            upsert("roofs", .roofs, data: .roof(d), typeID: type, levelID: lv, id: r.id, uniqueId: r.uniqueId, source: "Roof",
                   configure: common(mark: r.mark, comments: r.comments))
        }
    }

    // MARK: Doors and windows

    func importInserts() {
        for i in doc.inserts.items {
            let cat: ArcusDomain.Category = (i.category ?? "doors").lowercased() == "windows" ? .windows : .doors
            let kind = cat.rawValue
            let what = label(cat.singularName, i.id)
            let lvOpt = optionalLevel(i.levelId)
            guard let hx = i.hostId, let host = hostIDs[hx], let hostEl = tx.model[host], hostEl.wall != nil,
                  let frame = WallGeometry.frame(hostEl, tx.model), frame.length > Tolerance.shortCurve else {
                fallback(i.mesh, kind: kind, category: cat.displayName, name: nil, levelID: lvOpt, reason: "host wall not imported", id: i.id, uniqueId: i.uniqueId,
                         skipCode: "insert.host", what: what, problem: "has no host wall among the imported walls")
                continue
            }
            guard let tx_ = i.typeId, let tid = typeIDs[tx_], let info = familyOfType[tx_], info.category == cat else {
                fallback(i.mesh, kind: kind, category: cat.displayName, name: nil, levelID: lvOpt, reason: "family type not imported", id: i.id, uniqueId: i.uniqueId,
                         skipCode: "insert.type", what: what, problem: "refers to a \(cat.singularName.lowercased()) type that was not imported")
                continue
            }
            guard let p = vec2(i.location) ?? vec2(i.transform?.origin) else {
                skip(kind, "insert.location", "\(what) has no location and was skipped.", i.id); continue
            }
            let station = WallGeometry.station(of: frame.location.closestPoint(to: p), on: frame.location)
            let loc = WallGeometry.point(atStation: station, on: frame.location)
            let hostBase = tx.model.baseElevation(of: hostEl)
            let sill: Double
            if let z = (i.location?.count ?? 0) >= 3 ? finite(i.location![2]) : finite(i.transform?.origin?.count == 3 ? i.transform!.origin![2] : nil) {
                sill = z - hostBase
            } else if let s = finite(i.sillHeight) {
                sill = elevation(lvOpt ?? hostEl.levelID) + s - hostBase
            } else {
                let def = info.definition.types.first?.values["Default Sill Height"]?.doubleValue
                sill = cat == .windows ? (def ?? 0.9) : 0
                approximate(kind, "insert.sill", "\(what) has no elevation; a sill height of \(ExchangeFamilyConverter.fmt(sill)) m was used.", i.id)
            }
            var d = InsertData(location: loc, sillHeight: sill)
            if let t = i.transform, let bx = vec3(t.basisX), let by = vec3(t.basisY) {
                let u = frame.length > 0 ? min(1, max(0, station / frame.length)) : 0
                let tangent = frame.location.tangent(at: u)
                let exterior = frame.location.normal(at: u) * (frame.flipped ? -1 : 1)
                d.handFlipped = Vec2(bx.x, bx.y).dot(tangent) < 0
                d.facingFlipped = Vec2(by.x, by.y).dot(exterior) < 0
            } else {
                d.facingFlipped = i.facingFlipped ?? false
                d.handFlipped = i.handFlipped ?? false
            }
            upsert(kind, cat, data: .insert(d), typeID: tid, levelID: hostEl.levelID, hostID: host, id: i.id, uniqueId: i.uniqueId,
                   source: cat.singularName, configure: common(mark: i.mark, comments: i.comments, parameters: i.parameters, family: info.definition))
        }
    }

    // MARK: Columns and beams

    func importColumns() {
        for c in doc.columns.items {
            var cat: ArcusDomain.Category = (c.category ?? "") == "columns" ? .columns : .structuralColumns
            let what = label(cat.singularName, c.id)
            let lvOpt = optionalLevel(c.levelId)
            if c.slanted == true {
                fallback(c.mesh, kind: "columns", category: cat.displayName, name: nil, levelID: lvOpt, reason: "slanted column", id: c.id, uniqueId: c.uniqueId,
                         skipCode: "column.slanted", what: what, problem: "is slanted, which Arcus can't model natively")
                continue
            }
            guard let p = vec2(c.location) ?? vec2(c.transform?.origin) else {
                skip("columns", "column.location", "\(what) has no location and was skipped.", c.id); continue
            }
            let type: ElementID
            if let x = c.typeId, let t = typeIDs[x], let info = familyOfType[x], info.hasGeometry,
               info.category == .columns || info.category == .structuralColumns {
                type = t
                cat = info.category
            } else {
                type = systemType(c.typeId, cat, what, c.id)
                if let tc = tx.model[type]?.typeData?.instanceCategory, tc == .columns || tc == .structuralColumns, cat == .columns { cat = tc }
            }
            let lv = level(c.levelId, what, c.id)
            var rotation = finite(c.rotation) ?? 0
            if c.rotation == nil, let bx = vec3(c.transform?.basisX) { rotation = atan2(bx.y, bx.x) }
            var d = ColumnData(location: p, rotation: rotation, baseOffset: finite(c.baseOffset) ?? 0, topLevelID: optionalLevel(c.topLevelId),
                               topOffset: finite(c.topOffset) ?? 0, unconnectedHeight: finite(c.unconnectedHeight) ?? 3)
            let (b, t) = verticalRange(level: lv, baseOffset: d.baseOffset, top: d.topLevelID, topOffset: d.topOffset, height: d.unconnectedHeight)
            if t - b < 0.01 {
                d.topLevelID = nil
                d.unconnectedHeight = max(0.1, finite(c.unconnectedHeight) ?? 3)
                approximate("columns", "column.height", "\(what) had its top below its base; it uses an unconnected height instead.", c.id)
            }
            upsert("columns", cat, data: .column(d), typeID: type, levelID: lv, id: c.id, uniqueId: c.uniqueId, source: cat.singularName,
                   configure: common(mark: c.mark, comments: c.comments))
        }
    }

    func importBeams() {
        for b in doc.beams.items {
            let what = label("Beam", b.id)
            let lvOpt = optionalLevel(b.levelId)
            guard let seg = curve(b.curve)?.asSegment, seg.length > Tolerance.shortCurve else {
                fallback(b.mesh, kind: "beams", category: "Structural Framing", name: nil, levelID: lvOpt, reason: "curved or missing beam line",
                         id: b.id, uniqueId: b.uniqueId, skipCode: "beam.curve", what: what, problem: "is not a straight beam")
                continue
            }
            let lv = level(b.levelId, what, b.id)
            let type = systemType(b.typeId, .structuralFraming, what, b.id)
            var d = BeamData(curve: .line(seg), startOffset: finite(b.startOffset) ?? 0, endOffset: finite(b.endOffset) ?? 0)
            d.zJustification = BeamZJustification.allCases.first { $0.rawValue.lowercased() == (b.zJustification ?? "top").lowercased() } ?? .top
            upsert("beams", .structuralFraming, data: .beam(d), typeID: type, levelID: lv, id: b.id, uniqueId: b.uniqueId, source: "Structural Framing",
                   configure: common(mark: b.mark, comments: b.comments))
        }
    }

    // MARK: Stairs and railings

    func importStairs() {
        for s in doc.stairs.items {
            let what = label("Stair", s.id)
            let lvOpt = optionalLevel(s.levelId)
            let shape: StairShape?
            switch (s.shape ?? "").lowercased() {
            case "straight": shape = .straight
            case "lshaped", "l-shaped", "l": shape = .lShaped
            case "ushaped", "u-shaped", "u": shape = .uShaped
            default: shape = nil
            }
            guard let shape, let o = vec2(s.origin), let dir = finite(s.direction), let width = finite(s.width), width > 0.3 else {
                fallback(s.mesh, kind: "stairs", category: "Stairs", name: nil, levelID: lvOpt, reason: "stair shape without an Arcus equivalent",
                         id: s.id, uniqueId: s.uniqueId, skipCode: "stair.shape",
                         what: what, problem: "has a shape Arcus can't model natively (\(s.shape ?? "unknown"))")
                continue
            }
            let lv = level(s.levelId, what, s.id)
            let type = systemType(s.typeId, .stairs, what, s.id)
            var d = StairData(shape: shape, origin: o, direction: dir, width: width, topLevelID: optionalLevel(s.topLevelId))
            d.baseOffset = finite(s.baseOffset) ?? 0
            d.topOffset = finite(s.topOffset) ?? 0
            d.unconnectedHeight = finite(s.unconnectedHeight) ?? 3
            if let n = s.riserCount, (2...300).contains(n) { d.desiredRiserCount = n }
            d.turnsLeft = s.turnsLeft ?? true
            if let n = s.firstRunRisers, n > 0, n < (d.desiredRiserCount ?? 300) { d.firstRunRisers = n }
            let probe = Element(id: ElementID(UInt64.max), category: .stairs, data: .stair(d), typeID: type, levelID: lv)
            guard StairGeometry.layout(probe, tx.model) != nil else {
                fallback(s.mesh, kind: "stairs", category: "Stairs", name: nil, levelID: lv, reason: "stair Arcus could not lay out", id: s.id, uniqueId: s.uniqueId,
                         skipCode: "stair.layout", what: what, problem: "could not be laid out by Arcus (its top must be at least 100 mm above its base)")
                continue
            }
            let id = upsert("stairs", .stairs, data: .stair(d), typeID: type, levelID: lv, id: s.id, uniqueId: s.uniqueId, source: "Stair",
                            configure: common(mark: s.mark, comments: s.comments))
            if let x = s.id { hostIDs[x] = id }
        }
    }

    func importRailings() {
        for r in doc.railings.items {
            let what = label("Railing", r.id)
            let lvOpt = optionalLevel(r.levelId)
            var path: [Curve2] = []
            var ok = !(r.path ?? []).isEmpty && (r.path?.count ?? 0) <= options.maxCurvesPerSketch
            for c in r.path ?? [] where ok {
                if let cs = curves(c) { path.append(contentsOf: cs) } else { ok = false }
            }
            guard ok, !path.isEmpty else {
                fallback(r.mesh, kind: "railings", category: "Railings", name: nil, levelID: lvOpt, reason: "no usable path", id: r.id, uniqueId: r.uniqueId,
                         skipCode: "railing.path", what: what, problem: "has no usable path")
                continue
            }
            let lv = level(r.levelId, what, r.id)
            let type = systemType(r.typeId, .railings, what, r.id)
            var d = RailingData(path: path, baseOffset: finite(r.baseOffset) ?? 0)
            var host: ElementID?
            if let h = r.hostId {
                if let s = hostIDs[h], let sd = tx.model[s]?.stair {
                    host = s
                    d.followsHost = true
                    let dirv = Vec2(cos(sd.direction), sin(sd.direction))
                    d.hostSideLeft = dirv.cross(path[0].start - sd.origin) > 0
                } else {
                    warn("railing.host", "\(what) is hosted on an element that was not imported as a stair; it was placed free-standing.", r.id)
                }
            }
            upsert("railings", .railings, data: .railing(d), typeID: type, levelID: lv, hostID: host, id: r.id, uniqueId: r.uniqueId, source: "Railing",
                   configure: common(mark: r.mark, comments: r.comments))
        }
    }

    // MARK: Rooms

    func importRooms() {
        for r in doc.rooms.items {
            let what = label("Room", r.id)
            guard let p = vec2(r.point) else {
                skip("rooms", "room.unplaced", "\(what) is not placed and was skipped.", r.id); continue
            }
            let lv = level(r.levelId, what, r.id)
            var d = RoomData(point: p, number: clean(r.number) ?? "", limitOffset: finite(r.limitOffset) ?? 2.7)
            let upper = optionalLevel(r.upperLimitLevelId)
            d.upperLimitLevelID = upper == lv ? nil : upper
            d.baseOffset = finite(r.baseOffset) ?? 0
            let top = elevation(d.upperLimitLevelID ?? lv) + d.limitOffset
            if top - (elevation(lv) + d.baseOffset) <= 0.01 {
                d.upperLimitLevelID = nil
                d.limitOffset = 2.7
                approximate("rooms", "room.height", "\(what) had its upper limit below its base; a height of 2.7 m was used.", r.id)
            }
            let base = common(mark: nil, comments: r.comments)
            let dept = clean(r.department)
            upsert("rooms", .rooms, name: clean(r.name) ?? "Room", data: .room(d), levelID: lv, id: r.id, uniqueId: r.uniqueId, source: "Room") { e in
                base(&e)
                if let dept { e.params[ParameterID("room.department")] = .text(dept) }
            }
        }
    }

    // MARK: Components

    func importComponents() {
        for c in doc.components.items {
            let labelCat = c.revitCategory ?? c.category ?? "Generic Models"
            let what = label("Component", c.id)
            let lvOpt = optionalLevel(c.levelId)
            guard let tx_ = c.typeId, let tid = typeIDs[tx_], let info = familyOfType[tx_] else {
                fallback(c.mesh, kind: "components", category: labelCat, name: nil, levelID: lvOpt, reason: "family type not imported", id: c.id, uniqueId: c.uniqueId,
                         skipCode: "component.type", what: what, problem: "refers to a family type that was not imported")
                continue
            }
            guard info.hasGeometry, ![.doors, .windows, .structuralFraming].contains(info.category) else {
                let why = info.hasGeometry ? "it is a hosted or linear family placed without a host" : "its family geometry was not exported"
                fallback(c.mesh, kind: "components", category: labelCat, name: info.definition.name, levelID: lvOpt, reason: why, id: c.id, uniqueId: c.uniqueId,
                         skipCode: "component.native", what: what, problem: "can't be placed natively because \(why)")
                continue
            }
            var origin: Vec3
            var rotation = finite(c.rotation) ?? 0
            var mirrored = c.mirrored ?? false
            if let t = c.transform, let o = vec3(t.origin), let bx = vec3(t.basisX), let by = vec3(t.basisY) {
                origin = o
                let bz = vec3(t.basisZ) ?? Vec3(0, 0, 1)
                if abs(bz.z) < 0.999 {
                    fallback(c.mesh, kind: "components", category: labelCat, name: info.definition.name, levelID: lvOpt, reason: "tilted placement",
                             id: c.id, uniqueId: c.uniqueId, skipCode: "component.tilted",
                             what: what, problem: "is tilted out of the horizontal plane, which Arcus components don't support")
                    continue
                }
                let x2 = Vec2(bx.x, bx.y), y2 = Vec2(by.x, by.y)
                mirrored = x2.cross(y2) < 0
                rotation = atan2(-y2.x, y2.y)
                if bz.z < 0 { approximate("components", "component.upsideDown", "\(what) is placed upside down; it was imported upright.", c.id) }
            } else if let l = c.location, let p = vec2(l) {
                origin = Vec3(p, z: l.count >= 3 ? finite(l[2]) ?? 0 : 0)
            } else {
                skip("components", "component.location", "\(what) has no placement and was skipped.", c.id); continue
            }
            let lv = level(c.levelId, z: origin.z, what, c.id)
            let common = common(mark: c.mark, comments: c.comments, parameters: c.parameters, family: info.definition)
            if info.category == .columns || info.category == .structuralColumns {
                let d = ColumnData(location: origin.xy, rotation: rotation, baseOffset: origin.z - elevation(lv))
                upsert("columns", info.category, data: .column(d), typeID: tid, levelID: lv, id: c.id, uniqueId: c.uniqueId, source: labelCat, configure: common)
                continue
            }
            let d = ComponentData(location: origin.xy, rotation: rotation, offset: origin.z - elevation(lv), mirrored: mirrored)
            upsert("components", info.category, data: .component(d), typeID: tid, levelID: lv, id: c.id, uniqueId: c.uniqueId, source: labelCat, configure: common)
        }
    }

    // MARK: Reference meshes

    func importMeshElements() {
        guard options.importMeshes else {
            if !doc.meshes.items.isEmpty {
                report.skipped["reference meshes", default: 0] += doc.meshes.items.count
                warn("mesh.disabled", "\(doc.meshes.items.count) reference meshes were not imported (mesh import is turned off).")
            }
            return
        }
        for m in doc.meshes.items {
            let cat = m.revitCategory ?? m.category ?? "Generic"
            let ok = referenceMesh(XMesh(positions: m.positions ?? [], indices: m.indices ?? []), kind: "reference meshes", category: cat, name: m.name,
                                   levelID: m.levelId.flatMap { levelIDs[$0] }, reason: m.reason ?? "no Arcus equivalent", id: m.id, uniqueId: m.uniqueId,
                                   materialID: m.materialId, parameters: m.parameters)
            if !ok {
                skip("reference meshes", "mesh.invalid", "\(label("Mesh", m.id)) is empty, malformed or over the size limit and was skipped.", m.id)
            }
        }
    }
}
