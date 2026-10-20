import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// AITOOLS: the Modify tab: copy, rotate, mirror, array, align, offset, trim/extend, split, join, change type, pin,
// flip, attach, group. Each works on given ids or the selection, through the same operations the Modify tools use.

extension ArcusToolCatalog {
    static let selNote = "elements: ids, or omit to use the selection. "
    static let editTools: [ToolSpec] = [
        ToolSpec("copy_elements", "Copy", "Copy elements by a plan vector (count > 1 makes a row of copies, like Copy ▸ Multiple), or to another level. " + selNote + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["elements": S.ids(), "by": S.point("[dx, dy] between copies"), "count": S.int("Copies, default 1"), "to_level": S.ref("Copy to this level (Paste Aligned: same place)")]),
        ToolSpec("rotate_elements", "Rotate", "Rotate elements by an angle (degrees, counter-clockwise) about a point (default their centre). copy:true keeps the originals. " + selNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["elements": S.ids(), "angle": S.num("Degrees CCW"), "center": S.point(), "copy": S.bool()], required: ["angle"]),
        ToolSpec("mirror_elements", "Mirror", "Mirror elements about an axis line through two points (or a wall/grid/line id), keeping the originals unless copy is false (Mirror ▸ Draw Axis / Pick Axis). " + selNote + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["elements": S.ids(), "axis": S.points("[[x1,y1],[x2,y2]]"), "axis_element": S.int("Pick Axis: a wall, grid, line or reference plane id"), "copy": S.bool("Default true")]),
        ToolSpec("array_elements", "Array", "Linear array (count members spaced by `by`, or spread to `last` with Move To Last) or radial array (count members over `angle` degrees about `center`). group:true makes an associative array group whose count can change later. " + selNote + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["elements": S.ids(), "kind": S.oneOf(["linear", "radial"], "Default linear"), "count": S.int("Members including the original (≥2)"),
                              "by": S.point("Linear: [dx, dy] between members"), "last": S.point("Linear: [dx, dy] of the last member (Move To Last)"),
                              "center": S.point("Radial centre"), "angle": S.num("Radial: total angle, degrees (default 360)"), "group": S.bool("Group and Associate (default false)")],
                 required: ["count"]),
        ToolSpec("align_elements", "Align", "Align elements to a reference: walls/lines/grids parallel to the reference line move onto it (face or centre line); points (columns, components) move onto it. lock:true adds the padlock constraint. " + selNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["reference": S.int("Element to align to (wall, grid, line, reference plane)"), "elements": S.ids(),
                              "reference_face": S.oneOf(["centerline", "exterior_face", "interior_face"], "Wall reference (default centerline)"),
                              "element_face": S.oneOf(["centerline", "exterior_face", "interior_face"], "Wall face of the moving walls (default same as reference_face)"), "lock": S.bool()],
                 required: ["reference"]),
        ToolSpec("offset_elements", "Offset", "Offset walls, lines, beams, grids or reference planes sideways by a distance (positive: to the left of start→end). copy:true (default) keeps the original. " + selNote + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["elements": S.ids(), "distance": S.len(), "copy": S.bool("Default true")], required: ["distance"]),
        ToolSpec("trim_extend", "Trim/Extend", "corner: trim or extend two walls/lines to meet at a corner (keeps each element's longer side). to_boundary: trim or extend elements to a boundary element (the end nearest the boundary moves). " + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["mode": S.oneOf(["corner", "to_boundary"], "Default corner"), "elements": S.ids("corner: two ids; to_boundary: the ids to trim"), "boundary": S.int(),
                              "keep": S.points("Optional: a point on the part of each element to keep")], required: ["elements"]),
        ToolSpec("split_element", "Split Element", "Split a wall, line or beam at a point or at a distance from its start; gap leaves an opening between the pieces (Split with Gap). Hosted doors and windows stay on their piece. " + lengthNote,
                 risk: .edit, group: .edit, modes: .model,
                 properties: ["element": S.int(), "point": S.point(), "offset": S.len("Distance from the start"), "gap": S.len("Optional gap width")], required: ["element"]),
        ToolSpec("join_geometry", "Join Geometry", "Join (or unjoin) the solids of walls, floors, roofs, columns and beams so the one cuts the other. " + selNote,
                 risk: .edit, group: .edit, modes: .model, properties: ["elements": S.ids(), "unjoin": S.bool()]),
        ToolSpec("change_type", "Change Type", "Change elements to another type of their category (Type Selector), e.g. walls to 'Exterior - Brick on CMU' or doors to 'Single Flush 34\" x 84\"'. " + selNote,
                 risk: .edit, group: .edit, modes: .model, properties: ["elements": S.ids(), "type": S.ref("Type name or id (list_types)")], required: ["type"]),
        ToolSpec("pin_elements", "Pin", "Pin (or unpin) elements so they can't move or be deleted by accident. " + selNote,
                 risk: .edit, group: .edit, modes: .model, properties: ["elements": S.ids(), "unpin": S.bool()]),
        ToolSpec("flip_elements", "Flip", "Flip doors/windows (facing: swing side; hand: hinge side) or walls (exterior side), like the flip arrows. " + selNote,
                 risk: .edit, group: .edit, modes: .model, properties: ["elements": S.ids(), "what": S.oneOf(["facing", "hand", "wall"], "Default facing (doors/windows) or wall")]),
        ToolSpec("attach_walls", "Attach Top/Base", "Attach the tops of walls to a roof, floor or ceiling (they follow its underside), or detach them. " + selNote,
                 risk: .edit, group: .edit, modes: .project, properties: ["elements": S.ids("Walls"), "to": S.int("Roof, floor or ceiling id"), "detach": S.bool()]),
        ToolSpec("group_elements", "Create Group", "Group elements (model or detail group) with a name, or ungroup a group (its members stay). " + selNote,
                 risk: .edit, group: .edit, modes: .model, properties: ["elements": S.ids(), "name": S.str(), "ungroup": S.int("Group id to ungroup")]),
    ]
}

extension ArcusToolbox {
    static let editHandlers: [String: ToolHandler] = [
        "copy_elements": { b, c in try b.copyElements(c) },
        "rotate_elements": { b, c in try b.rotateElements(c) },
        "mirror_elements": { b, c in try b.mirrorElements(c) },
        "array_elements": { b, c in try b.arrayElements(c) },
        "align_elements": { b, c in try b.alignElements(c) },
        "offset_elements": { b, c in try b.offsetElements(c) },
        "trim_extend": { b, c in try b.trimExtend(c) },
        "split_element": { b, c in try b.splitElement(c) },
        "join_geometry": { b, c in try b.joinGeometry(c) },
        "change_type": { b, c in try b.changeType(c) },
        "pin_elements": { b, c in try b.pinElements(c) },
        "flip_elements": { b, c in try b.flipElements(c) },
        "attach_walls": { b, c in try b.attachWalls(c) },
        "group_elements": { b, c in try b.groupElements(c) },
    ]

    /// Summaries of `ids` after an edit.
    func summaries(_ ids: [ElementID], _ c: ToolContext, limit: Int = 30) throws(ToolError) -> JSONValue {
        let m = try c.model()
        return .array(ids.prefix(limit).compactMap { m[$0] }.map { describe($0, c, m) })
    }

    func copyElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let count = max(1, min(c.args.int("count") ?? 1, 200))
        let by = try c.args["by"].map { try c.point($0, "by") } ?? .zero
        let level = try c.args["to_level"].map { try c.level($0, "to_level") }
        guard by.length > 1e-6 || level != nil else { throw ToolError("Give by [dx, dy] (not zero) or to_level.") }
        let m = try c.model()
        var made: [ElementID] = []
        let viewID = activeViewID
        try c.edit("Copy") { tx in
            for k in 1...count {
                var delta = 0.0
                if let level, let src = ids.compactMap({ m[$0]?.levelID }).first {
                    delta = (level.level?.elevation ?? 0) - m.elevation(ofLevel: src)
                }
                let map = ElementOperations.copy(ids, by: .translation(by * Double(k)), in: tx, viewID: viewID, targetLevel: level?.id, levelDelta: delta)
                made += ids.compactMap { map[$0] }
            }
        }
        return result(c, ["copies": try summaries(made, c), "count": .int(made.count)], ids: made)
    }

    func rotateElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        guard let deg = c.args.double("angle") else { throw ToolError("Missing angle (degrees, counter-clockwise).") }
        let m = try c.model()
        let center = try c.args["center"].map { try c.point($0, "center") } ?? ElementOperations.center(of: ids, m)
        let t = Transform2.rotation(deg * .pi / 180, around: center)
        let copy = c.args.bool("copy", default: false)
        var out = ids
        let viewID = activeViewID
        try c.edit("Rotate") { tx in
            if copy { let map = ElementOperations.copy(ids, by: t, in: tx, viewID: viewID); out = ids.compactMap { map[$0] } } else {
                try ElementOperations.transform(ids, by: t, in: tx, viewID: viewID)
            }
        }
        return result(c, ["elements": try summaries(out, c), "center": c.out(center, m)], ids: out)
    }

    /// An axis line from `axis` points or a picked element.
    func axisLine(_ c: ToolContext) throws(ToolError) -> Segment2 {
        if let a = c.args["axis"] {
            let p = try c.points(a, "axis")
            guard p[0].distance(to: p[1]) > 1e-4 else { throw ToolError("axis points are the same point.") }
            return Segment2(p[0], p[1])
        }
        if let v = c.args["axis_element"] {
            let e = try c.element(v, "axis_element")
            if let s = ElementOperations.curveOf(e)?.asSegment { return s }
            if let g = e.grid, let s = g.curve.asSegment { return s }
            if let r = e.referencePlane { return r.line }
            throw ToolError("Element \(e.id.raw) has no straight line to mirror about.")
        }
        throw ToolError("Give axis [[x1,y1],[x2,y2]] or axis_element.")
    }

    func mirrorElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let axis = try axisLine(c)
        let t = Transform2.mirror(through: axis.start, direction: axis.direction)
        let copy = c.args.bool("copy", default: true)
        var out = ids
        let viewID = activeViewID
        try c.edit("Mirror") { tx in
            if copy { let map = ElementOperations.copy(ids, by: t, in: tx, viewID: viewID); out = ids.compactMap { map[$0] } } else {
                try ElementOperations.transform(ids, by: t, in: tx, viewID: viewID)
            }
        }
        return result(c, ["elements": try summaries(out, c), "copied": .bool(copy)], ids: out)
    }

    func arrayElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        guard let count = c.args.int("count"), count >= 2, count <= ArraySpec.maximumCount else { throw ToolError("count must be 2…\(ArraySpec.maximumCount) (members including the original).") }
        let m = try c.model()
        let radial = c.args.string("kind")?.lowercased() == "radial"
        var spec: ArraySpec
        if radial {
            guard let cv = c.args["center"] else { throw ToolError("A radial array needs center [x, y].") }
            let total = (c.args.double("angle") ?? 360) * .pi / 180
            let full = abs(abs(total) - 2 * .pi) < 1e-6
            spec = ArraySpec(kind: .radial, count: count, center: try c.point(cv, "center"), stepAngle: total / Double(full ? count : count - 1), sourceMembers: ids, fixedExtent: c.args["angle"] != nil)
        } else {
            if let l = c.args["last"] {
                spec = ArraySpec(kind: .linear, count: count, step: try c.point(l, "last") / Double(count - 1), sourceMembers: ids, fixedExtent: true)
            } else if let bv = c.args["by"] {
                spec = ArraySpec(kind: .linear, count: count, step: try c.point(bv, "by"), sourceMembers: ids)
            } else { throw ToolError("A linear array needs by [dx, dy] (spacing) or last [dx, dy] (Move To Last).") }
            guard spec.step.length > 1e-5 else { throw ToolError("The array spacing is zero.") }
        }
        let before = Set(m.elements.keys)
        var gid: ElementID?
        let viewID = activeViewID
        try c.edit("Array") { tx in gid = try ArrayOperations.create(spec, associate: c.args.bool("group", default: false), in: tx, viewID: viewID) }
        let nm = try c.model()
        let made = nm.elements.keys.filter { !before.contains($0) }.sorted()
        var o: [String: JSONValue] = ["members": .int(count), "created": .int(made.count)]
        if let gid { o["group"] = gid.json }
        _ = nm
        return result(c, o, ids: made)
    }

    /// The line an element offers as an alignment reference (walls: centre line or a face).
    func referenceLine(_ e: Element, face: String?, _ m: BIMModel) -> Segment2? {
        if e.wall != nil, let f = WallGeometry.frame(e, m) {
            switch face {
            case "exterior_face": return f.exteriorFace.asSegment
            case "interior_face": return f.interiorFace.asSegment
            default: return f.location.asSegment
            }
        }
        if let s = ElementOperations.curveOf(e)?.asSegment { return s }
        if let g = e.grid { return g.curve.asSegment }
        if let r = e.referencePlane { return r.line }
        return nil
    }

    func alignElements(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard let rv = c.args["reference"] else { throw ToolError("Missing reference (the element to align to).") }
        let ref = try c.element(rv, "reference")
        let refFace = c.args.string("reference_face")
        guard let line = referenceLine(ref, face: refFace, m) else { throw ToolError("Element \(ref.id.raw) (\(ref.category.singularName)) has no straight line to align to.") }
        let ids = try c.idsOrSelection().filter { $0 != ref.id }
        guard !ids.isEmpty else { throw ToolError("Give elements to align (not the reference).") }
        var moves: [(ElementID, Vec2)] = []
        var skipped: [String] = []
        for id in ids {
            guard let e = m[id] else { continue }
            if let seg = referenceLine(e, face: c.args.string("element_face") ?? refFace, m) {
                guard seg.isParallel(to: line) else { skipped.append("\(id.raw) isn't parallel to the reference"); continue }
                moves.append((id, line.normal * -line.signedDistance(to: seg.midpoint)))
            } else if let p = e.component?.location ?? e.column?.location {
                moves.append((id, line.normal * -line.signedDistance(to: p)))
            } else { skipped.append("\(id.raw) (\(e.category.singularName)) has nothing to align") }
        }
        guard !moves.isEmpty else { throw ToolError("Nothing could be aligned: \(skipped.joined(separator: "; ")).") }
        let lock = c.args.bool("lock", default: false)
        let viewID = activeViewID
        try c.edit("Align") { tx in
            for (id, v) in moves where v.length > 1e-7 { try ElementOperations.transform([id], by: .translation(v), in: tx, viewID: viewID) }
            if lock {
                for (id, _) in moves {
                    tx.create(.constraints, data: .constraint(ConstraintData(kind: .alignment, references: [GeometryReference(ref.id, .location), GeometryReference(id, .location)])))
                }
            }
        }
        var o: [String: JSONValue] = ["aligned": .array(moves.map { ["id": $0.0.json, "moved": .string(c.formatLength($0.1.length, m))] }), "locked": .bool(lock)]
        if !skipped.isEmpty { o["skipped"] = .array(skipped.map { .string($0) }) }
        return result(c, o, ids: moves.map(\.0))
    }

    func offsetElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let d = try c.requireLength("distance")
        let copy = c.args.bool("copy", default: true)
        var out: [ElementID] = []
        let viewID = activeViewID
        try c.edit("Offset") { tx in for id in ids { out.append(try ElementOperations.offset(id, by: d, copy: copy, in: tx, viewID: viewID)) } }
        return result(c, ["elements": try summaries(out, c)], ids: out)
    }

    func trimExtend(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let ids = try c.elementIDs("elements")
        let keep = try c.args["keep"].map { try c.points($0, "keep", min: 1) }
        func curve(_ id: ElementID) throws(ToolError) -> Curve2 {
            guard let e = m[id], let cv = ElementOperations.curveOf(e) else { throw ToolError("Element \(id.raw) can't be trimmed (walls, lines and beams can).") }
            return cv
        }
        /// The end of `cv` farther from where it meets `other`: the side Revit keeps when you pick the longer part.
        func keepPoint(_ cv: Curve2, _ other: Curve2, _ k: Int) -> Vec2 {
            if let keep, k < keep.count { return keep[k] }
            guard let s = cv.asSegment, let o = other.asSegment, let hit = s.lineIntersection(o)?.point else { return cv.midpoint }
            return s.start.distance(to: hit) > s.end.distance(to: hit) ? s.start.lerp(to: hit, t: 0.5) : s.end.lerp(to: hit, t: 0.5)
        }
        if c.args.string("mode")?.lowercased() == "to_boundary" {
            guard let bv = c.args["boundary"] else { throw ToolError("to_boundary needs boundary (an element id).") }
            let boundary = try curve(try c.element(bv, "boundary").id)
            var plans: [(ElementID, Vec2)] = []
            for (k, id) in ids.enumerated() { plans.append((id, keepPoint(try curve(id), boundary, k))) }
            try c.edit("Trim/Extend") { tx in for (id, p) in plans { try ElementOperations.trimExtend(id, keepNear: p, to: boundary, in: tx) } }
        } else {
            guard ids.count == 2 else { throw ToolError("corner needs exactly two elements.") }
            let a = try curve(ids[0]), b = try curve(ids[1])
            let pa = keepPoint(a, b, 0), pb = keepPoint(b, a, 1)
            try c.edit("Trim/Extend to Corner") { tx in
                try ElementOperations.trimExtend(ids[0], keepNear: pa, to: b, in: tx)
                guard let nb = tx.model[ids[0]].flatMap(ElementOperations.curveOf) else { return }
                try ElementOperations.trimExtend(ids[1], keepNear: pb, to: nb, in: tx)
            }
        }
        return result(c, ["elements": try summaries(ids, c)], ids: ids)
    }

    func splitElement(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        guard let ev = c.args["element"] else { throw ToolError("Missing element.") }
        let e = try c.element(ev, "element")
        guard let cv = ElementOperations.curveOf(e), let seg = cv.asSegment else { throw ToolError("Element \(e.id.raw) can't be split (straight walls, lines and beams can).") }
        let p: Vec2
        if let pv = c.args["point"] { p = seg.closestPoint(to: try c.point(pv, "point")) } else if let o = try c.length("offset") {
            guard o > 0, o < seg.length else { throw ToolError("offset must be between 0 and the length (\(c.formatLength(seg.length, m))).") }
            p = seg.point(at: o / seg.length)
        } else { p = seg.midpoint }
        let before = Set(m.elements.keys)
        if let gap = try c.length("gap"), gap > 0 {
            let d = seg.direction * (gap / 2)
            try c.edit("Split with Gap") { tx in _ = try ElementOperations.deleteSegment(e.id, between: p - d, and: p + d, in: tx) }
        } else {
            try c.edit("Split Element") { tx in try ElementOperations.split(e.id, at: p, in: tx) }
        }
        let nm = try c.model()
        let pieces = [e.id] + nm.elements.keys.filter { !before.contains($0) && nm[$0]?.category == e.category }.sorted()
        return result(c, ["pieces": try summaries(pieces.filter { nm[$0] != nil }, c)], ids: pieces)
    }

    func joinGeometry(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let unjoin = c.args.bool("unjoin", default: false)
        let m = try c.model()
        if !unjoin && SolidJoins.joinablePairs(ids, m).isEmpty { throw ToolError("None of these elements overlap in a way that can join (walls, floors, roofs, columns, beams that touch).") }
        var n = 0
        try c.edit(unjoin ? "Unjoin Geometry" : "Join Geometry") { tx in n = unjoin ? SolidJoins.unjoin(ids, in: tx) : SolidJoins.join(ids, in: tx) }
        return result(c, [unjoin ? "unjoined" : "joined": .int(n)], ids: ids)
    }

    func changeType(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let m = try c.model()
        let cats = Set(ids.compactMap { m[$0]?.category })
        guard cats.count == 1, let cat = cats.first else { throw ToolError("Change Type works on one category at a time; these are \(cats.map(\.displayName).sorted().joined(separator: ", ")). Filter with select_elements.") }
        let t = try c.type(c.args["type"], category: cat)
        try c.edit("Change Type") { tx in for id in ids { try Parameters.set(ParameterID("familyAndType"), to: .ref(t.id), on: id, in: tx) } }
        return result(c, ["type": .string(ToolContext.typeLabel(t, try c.model())), "elements": .array(ids.map(\.json))], ids: ids)
    }

    func pinElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let pin = !c.args.bool("unpin", default: false)
        try c.edit(pin ? "Pin" : "Unpin") { tx in for id in ids { tx.update(id) { $0.pinned = pin } } }
        return result(c, [pin ? "pinned" : "unpinned": .array(ids.map(\.json))], ids: ids)
    }

    func flipElements(_ c: ToolContext) throws -> ToolOutput {
        let ids = try c.idsOrSelection()
        let m = try c.model()
        let what = c.args.string("what")?.lowercased()
        var flipped: [ElementID] = []
        try c.edit("Flip") { tx in
            for id in ids {
                guard let e = m[id] else { continue }
                if e.insert != nil, what != "wall" {
                    tx.update(id) { if what == "hand" { $0.insert?.handFlipped.toggle() } else { $0.insert?.facingFlipped.toggle() } }
                    flipped.append(id)
                } else if e.wall != nil {
                    tx.update(id) { $0.wall?.flipped.toggle() }
                    flipped.append(id)
                } else if e.furnitureFront != nil {
                    tx.update(id) { $0.furnitureFront?.hingeFlipped.toggle() }
                    flipped.append(id)
                }
            }
        }
        guard !flipped.isEmpty else { throw ToolError("Nothing to flip: give doors, windows, walls or furniture doors.") }
        return result(c, ["flipped": .array(flipped.map(\.json))], ids: flipped)
    }

    func attachWalls(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        let walls = try c.idsOrSelection().filter { m[$0]?.wall != nil }
        guard !walls.isEmpty else { throw ToolError("Give walls (or select them).") }
        if c.args.bool("detach", default: false) {
            try c.edit("Detach Top/Base") { tx in for w in walls { tx.update(w) { $0.wall?.attachedTopIDs = []; $0.wall?.attachedBaseIDs = [] } } }
            return result(c, ["detached": .array(walls.map(\.json))], ids: walls)
        }
        guard let tv = c.args["to"] else { throw ToolError("Give to (a roof, floor or ceiling id), or detach: true.") }
        let host = try c.element(tv, "to")
        guard [.roofs, .floors, .ceilings].contains(host.category) else { throw ToolError("to must be a roof, floor or ceiling; \(host.id.raw) is a \(host.category.singularName.lowercased()).") }
        let ok = Set(WallAttachment.candidates(for: host, m))
        let usable = walls.filter { ok.contains($0) }
        guard !usable.isEmpty else { throw ToolError("None of these walls lie under \(host.category.singularName.lowercased()) \(host.id.raw).") }
        try c.edit("Attach Top/Base") { tx in WallAttachment.attach(usable, to: host.id, in: tx) }
        var o: [String: JSONValue] = ["attached": .array(usable.map(\.json)), "to": host.id.json]
        let left = walls.filter { !ok.contains($0) }
        if !left.isEmpty { o["not_under_host"] = .array(left.map(\.json)) }
        return result(c, o, ids: usable)
    }

    func groupElements(_ c: ToolContext) throws -> ToolOutput {
        let m = try c.model()
        if let gv = c.args["ungroup"] {
            let g = try c.element(gv, "ungroup")
            guard let gd = g.group else { throw ToolError("Element \(g.id.raw) is not a group.") }
            try c.edit("Ungroup") { tx in
                for mm in gd.members { tx.update(mm) { $0.groupID = nil } }
                tx.delete(g.id)
            }
            return result(c, ["ungrouped": .array(gd.members.map(\.json))], ids: gd.members)
        }
        let members = try c.idsOrSelection().filter { m[$0].map { ElementTransform.isTransformable($0) && $0.groupID == nil } ?? false }
        guard !members.isEmpty else { throw ToolError("These elements can't be grouped (or are already grouped).") }
        let origin = ElementOperations.center(of: members, m)
        let name = c.args.string("name") ?? "Group \(m.elements(.modelGroups).count + m.elements(.detailGroups).count + 1)"
        let isDetail = members.allSatisfy { m[$0]?.ownerViewID != nil }
        var gid: ElementID?
        try c.edit("Create Group") { tx in
            let id = tx.create(isDetail ? .detailGroups : .modelGroups, name: name, data: .group(GroupData(members: members, origin: origin, groupTypeName: name)),
                               ownerViewID: isDetail ? m[members[0]]?.ownerViewID : nil)
            for mm in members { tx.update(mm) { $0.groupID = id } }
            gid = id
        }
        return result(c, ["group": gid?.json ?? .null, "name": .string(name), "members": .int(members.count)], ids: gid.map { [$0] } ?? [])
    }
}
