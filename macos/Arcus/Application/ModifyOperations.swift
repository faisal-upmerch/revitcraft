import Foundation
import ArcusGeometry
import ArcusDomain

/// Model edits behind the Modify tools that go beyond plain transforms: Disjoin re-hosting, Offset with hosted
/// inserts, Split with a removed segment, Demolish and associative arrays.
extension ElementOperations {
    // MARK: Disjoin

    /// After a Disjoin move, doors and windows that moved without their wall are hosted by the wall at their new
    /// location (on the same level). Throws when there is no wall there: a door or window can't exist on its own.
    static func rehostMovedInserts(_ moved: Set<ElementID>, in tx: TransactionContext) throws(TransactionError) {
        for id in moved.sorted() {
            guard let e = tx.model[id], let ins = e.insert, let host = e.hostID, !moved.contains(host) else { continue }
            let width = InsertGeometry.openingSize(e, tx.model)?.width ?? 0.9
            let level = e.levelID ?? tx.model[host]?.levelID
            var best: (Element, WallFrame, Double)?
            for w in tx.model.elements(.walls) where w.levelID == level {
                guard let f = WallGeometry.frame(w, tx.model) else { continue }
                let d = f.location.distance(to: ins.location)
                guard d <= f.thickness / 2 + Tolerance.length * 100, best.map({ d < $0.2 }) ?? true else { continue }
                best = (w, f, d)
            }
            guard let (wall, frame, _) = best else {
                throw TransactionError("A \(e.category.singularName.lowercased()) needs a wall at its new location.", elements: [id])
            }
            guard let p = InsertGeometry.constrainToHost(ins.location, width: width, host: frame) else {
                throw TransactionError("The wall at the new location is too short for this \(e.category.singularName.lowercased()).", elements: [id, wall.id])
            }
            tx.update(id) { $0.hostID = wall.id; $0.levelID = wall.levelID; $0.insert?.location = p }
        }
    }

    // MARK: Offset

    /// Offsets a wall, line, beam, grid or reference plane by `distance` to its left (negative: right). With `copy`
    /// the offset element is a copy and the original stays. Doors and windows hosted by the wall (and their tags in
    /// `viewID`) are carried onto the offset wall. Returns the id of the offset element.
    @discardableResult
    public static func offset(_ id: ElementID, by distance: Double, copy: Bool, in tx: TransactionContext, viewID: ElementID?) throws(TransactionError) -> ElementID {
        guard let e = tx.model[id], let c = curveOf(e) else { throw TransactionError("Only walls, lines, beams, grids and reference planes can be offset.", elements: [id]) }
        if !copy && e.pinned { throw TransactionError("Pinned elements can't be moved. Unpin them first.", elements: [id]) }
        if let a = c.asArc, (a.sweep >= 0 ? a.radius - distance : a.radius + distance) <= Tolerance.shortCurve {
            throw TransactionError("The offset is larger than the arc's radius.", elements: [id])
        }
        let nc = c.offset(by: distance)
        let before = tx.model
        let target: ElementID
        if copy {
            guard let n = ElementOperations.copy([id], by: .identity, in: tx, viewID: viewID)[id] else { throw TransactionError("That element can't be copied.", elements: [id]) }
            target = n
        } else {
            target = id
        }
        tx.update(target) { setCurveOf(&$0, nc) }
        // Hosted inserts slide perpendicular onto the offset location line; their tags follow.
        // Only tags in plan views share the plan coordinates the offset is measured in.
        func delta(_ p: Vec2) -> Vec2 { nc.closestPoint(to: p) - c.closestPoint(to: p) }
        func planTags(of x: ElementID) -> [Element] {
            tx.model.tags(of: x).filter { t in t.ownerViewID.flatMap { tx.model[$0]?.view?.kind.isPlan } ?? false }
        }
        if e.wall != nil {
            for h in tx.model.hosted(by: target) {
                guard let loc = h.insert?.location else { continue }
                let d = delta(loc)
                tx.update(h.id) { $0.insert?.location = loc + d }
                for t in planTags(of: h.id) {
                    guard let head = t.tag?.head else { continue }
                    tx.update(t.id) { $0.tag?.head = head + d }
                }
            }
        }
        for t in planTags(of: target) {
            guard let head = t.tag?.head else { continue }
            tx.update(t.id) { $0.tag?.head = head + delta(head) }
        }
        if !copy && e.wall != nil { keepWallJoins(moved: [id], before: before, in: tx) }
        return target
    }

    // MARK: Split: delete inner segment

    /// Removes the part of a wall, line or beam between two points on it. The remaining end pieces stay (as two
    /// elements when both are left); doors and windows in the removed part are deleted and the others stay on the
    /// piece that contains them. Returns the ids of the remaining pieces.
    @discardableResult
    public static func deleteSegment(_ id: ElementID, between p: Vec2, and q: Vec2, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        guard let e = tx.model[id] else { return [] }
        guard e.wall != nil || e.modelLine != nil || e.beam != nil, let c = curveOf(e) else {
            throw TransactionError("Only walls, lines and beams can be split.", elements: [id])
        }
        if e.pinned { throw TransactionError("Pinned elements can't be split. Unpin them first.", elements: [id]) }
        let len = c.length
        var t0 = min(max(c.parameter(of: c.closestPoint(to: p)), 0), 1)
        var t1 = min(max(c.parameter(of: c.closestPoint(to: q)), 0), 1)
        if t0 > t1 { swap(&t0, &t1) }
        guard (t1 - t0) * len > Tolerance.shortCurve else { throw TransactionError("Pick two different points on the element.", elements: [id]) }
        let keepFirst = t0 * len > Tolerance.shortCurve
        let keepSecond = (1 - t1) * len > Tolerance.shortCurve
        guard keepFirst || keepSecond else { throw TransactionError("That removes the whole element; use Delete instead.", elements: [id]) }
        let first = c.subcurve(from: 0, to: t0)
        let second = c.subcurve(from: t1, to: 1)
        // Inserts whose center falls in the removed range go; the rest follow their piece.
        var secondHosted: [ElementID] = []
        for h in tx.model.hosted(by: id) where h.insert != nil {
            guard let loc = h.insert?.location else { continue }
            let t = c.parameter(of: c.closestPoint(to: loc))
            if t > t0 && t < t1 { tx.delete(h.id) } else if t >= t1 { secondHosted.append(h.id) }
        }
        var out: [ElementID] = []
        if keepFirst {
            tx.update(id) { setCurveOf(&$0, first) }
            out.append(id)
            if keepSecond {
                var piece = e
                setCurveOf(&piece, second)
                let newID = tx.create(e.category, name: e.name, data: piece.data, typeID: e.typeID, levelID: e.levelID, hostID: e.hostID, ownerViewID: e.ownerViewID) { ne in
                    ne.params = e.params; ne.params[.mark] = nil; ne.phaseCreated = e.phaseCreated; ne.phaseDemolished = e.phaseDemolished
                    ne.designOptionID = e.designOptionID
                }
                for h in secondHosted { tx.update(h) { $0.hostID = newID } }
                out.append(newID)
            }
        } else {
            tx.update(id) { setCurveOf(&$0, second) }
            out.append(id)
        }
        return out
    }

    // MARK: Scale

    /// Whether Scale resizes this kind of element (lines, walls, reference planes, regions, clouds and links).
    public static func isScalable(_ e: Element) -> Bool {
        switch e.data {
        case .wall, .modelLine, .referencePlane, .filledRegion, .revisionCloud, .insulation, .link: true
        default: false
        }
    }

    /// Scales elements about `origin` by `factor`. Wall lengths and positions scale; thicknesses and heights don't.
    /// Doors and windows in scaled walls keep their relative position. Returns the number of elements scaled.
    @discardableResult
    public static func scale(_ ids: [ElementID], by factor: Double, about origin: Vec2, in tx: TransactionContext, viewID: ElementID?) throws(TransactionError) -> Int {
        guard factor.isFinite, factor > 1e-6 else { throw TransactionError("The scale factor must be greater than zero.") }
        let scalable = ids.filter { tx.model[$0].map(isScalable) ?? false }
        guard !scalable.isEmpty else { throw TransactionError("Scale works on walls, lines, reference planes, regions, revision clouds and links.", elements: ids) }
        try transform(scalable, by: .scale(factor, factor, around: origin), in: tx, viewID: viewID)
        // Edited wall profiles are stored along the wall's length.
        for id in scalable {
            guard let p = tx.model[id]?.wall?.profile else { continue }
            tx.update(id) { $0.wall?.profile = Polygon2(p.points.map { Vec2($0.x * factor, $0.y) }) }
        }
        return scalable.count
    }

    // MARK: Demolish

    /// Built model elements that can be demolished (not rooms, areas, groups or imported reference geometry).
    public static func isDemolishable(_ e: Element) -> Bool {
        e.category.isModel && !e.isType && ![.rooms, .areas, .modelGroups, .importedCAD, .ifcReference].contains(e.category)
    }

    /// Sets Phase Demolished to `phase` on the elements and on the doors, windows and railings they host.
    /// Elements created after `phase` are refused; elements already demolished in or before it are left alone.
    /// Returns the ids that changed.
    @discardableResult
    public static func demolish(_ ids: [ElementID], phase: ElementID, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        guard let order = tx.model.phaseOrder(phase) else { throw TransactionError("Choose a phase to demolish in.") }
        var changed: [ElementID] = []
        func mark(_ e: Element) {
            if let d = tx.model.phaseOrder(e.phaseDemolished), d <= order { return }
            tx.update(e.id) { $0.phaseDemolished = phase }
            changed.append(e.id)
        }
        for id in ids {
            guard let e = tx.model[id] else { continue }
            guard isDemolishable(e) else {
                throw TransactionError("Only built elements such as walls, floors, doors and furniture can be demolished.", elements: [id])
            }
            if let created = tx.model.phaseOrder(e.phaseCreated), created > order {
                throw TransactionError("This element is created in a later phase, so it can't be demolished in this one.", elements: [id])
            }
            mark(e)
            for h in tx.model.hosted(by: id) where h.insert != nil || h.railing != nil {
                if let created = tx.model.phaseOrder(h.phaseCreated), created > order { continue }
                mark(h)
            }
        }
        return changed
    }
}

// MARK: - Associative arrays

/// Array creation and regeneration shared by the Array tool and the Array Number command.
public enum ArrayOperations {
    /// Creates `spec.count − 1` copies of the source members. With `associate`, the source members and the copies are
    /// gathered in an array group whose number of members can be changed later. Returns the new group id (or nil).
    @discardableResult
    public static func create(_ spec: ArraySpec, associate: Bool, in tx: TransactionContext, viewID: ElementID?) throws(TransactionError) -> ElementID? {
        guard spec.count >= 2, spec.count <= ArraySpec.maximumCount else { throw TransactionError("The number of array members must be 2 to \(ArraySpec.maximumCount).") }
        let sources = spec.sourceMembers.filter { tx.model[$0].map(ElementTransform.isTransformable) ?? false }
        guard !sources.isEmpty else { throw TransactionError("Select elements that can be arrayed.") }
        var copies: [ElementID] = []
        for k in 1..<spec.count {
            let map = ElementOperations.copy(sources, by: spec.transform(forMember: k), in: tx, viewID: viewID)
            copies += sources.compactMap { map[$0] }
        }
        guard associate else { return nil }
        guard sources.allSatisfy({ tx.model[$0]?.groupID == nil }) else {
            throw TransactionError("Elements that already belong to a group can't be arrayed as an associated group. Turn off Group and Associate.", elements: sources)
        }
        var s = spec
        s.sourceMembers = sources
        let members = sources + copies
        let isDetail = sources.allSatisfy { tx.model[$0]?.ownerViewID != nil }
        let owner = isDetail ? tx.model[sources[0]]?.ownerViewID : nil
        let existing = tx.model.elements(.modelGroups) + tx.model.elements(.detailGroups)
        var n = existing.count + 1
        while existing.contains(where: { $0.name == "Array \(n)" }) { n += 1 }
        var g = GroupData(members: members, origin: ElementOperations.center(of: members, tx.model), groupTypeName: "Array \(n)")
        g.arraySpec = s
        let gid = tx.create(isDetail ? .detailGroups : .modelGroups, name: "Array \(n)", data: .group(g), ownerViewID: owner)
        for m in members { tx.update(m) { $0.groupID = gid } }
        return gid
    }

    /// The array group of an element: the element itself when it is an array group, else the array group it belongs to.
    public static func arrayGroup(of id: ElementID, _ model: BIMModel) -> Element? {
        guard let e = model[id] else { return nil }
        if e.group?.arraySpec != nil { return e }
        if let g = e.groupID.flatMap({ model[$0] }), g.group?.arraySpec != nil { return g }
        return nil
    }

    /// Changes the number of members of an array group: copies are deleted and made again from the current source
    /// members (so edits to the source set carry over to every member).
    public static func setCount(_ count: Int, ofArray groupID: ElementID, in tx: TransactionContext, viewID: ElementID?) throws(TransactionError) {
        guard let g = tx.model[groupID], var gd = g.group, let old = gd.arraySpec else { throw TransactionError("Select an array group.", elements: [groupID]) }
        guard count >= 2, count <= ArraySpec.maximumCount else { throw TransactionError("The number of array members must be 2 to \(ArraySpec.maximumCount).", elements: [groupID]) }
        var spec = old.withCount(count)
        let sources = spec.sourceMembers.filter { tx.model[$0] != nil }
        guard !sources.isEmpty else { throw TransactionError("The array's original elements were deleted; its number can't be changed.", elements: [groupID]) }
        let pinned = gd.members.filter { !sources.contains($0) && tx.model[$0]?.pinned == true }
        if !pinned.isEmpty { throw TransactionError("Pinned array members can't be regenerated. Unpin them first.", elements: pinned) }
        for m in gd.members where !sources.contains(m) { tx.delete(m) }
        var copies: [ElementID] = []
        for k in 1..<count {
            let map = ElementOperations.copy(sources, by: spec.transform(forMember: k), in: tx, viewID: viewID)
            copies += sources.compactMap { map[$0] }
        }
        spec.sourceMembers = sources
        gd.members = sources + copies
        gd.arraySpec = spec
        gd.origin = ElementOperations.center(of: gd.members, tx.model)
        // Deleting the old copies may have removed the group (when it had no members left); recreate it with its id.
        if tx.model[groupID] == nil {
            var restored = g
            restored.data = .group(gd)
            tx.insertPreservingID(restored)
        } else {
            tx.update(groupID) { $0.group = gd }
        }
        for m in copies { tx.update(m) { $0.groupID = groupID } }
    }
}
