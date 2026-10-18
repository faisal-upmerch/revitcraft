import Foundation
import ArcusGeometry
import ArcusDomain

/// Copy/transform helpers shared by Move/Copy/Rotate/Mirror/Array, clipboard paste and group editing.
public enum ElementOperations {
    /// Elements that follow a set when it is moved: hosted inserts, hosted railings and view tags whose target moves.
    public static func dependentsToCarry(_ ids: Set<ElementID>, _ model: BIMModel, viewID: ElementID?) -> Set<ElementID> {
        var out = ids
        for id in ids {
            for h in model.hosted(by: id) where h.insert != nil || h.railing != nil || h.opening != nil || h.decal != nil { out.insert(h.id) } // F67: decals
            for t in model.tags(of: id) where t.ownerViewID == viewID || viewID == nil { out.insert(t.id) }
        }
        return out
    }

    /// Moves/rotates/mirrors elements in place. Pinned elements are refused.
    /// `disjoin`: walls that did not move are left where they are (the moved walls come apart from them), and moved
    /// doors and windows whose wall stays behind are re-hosted on the wall at their new location.
    public static func transform(_ ids: [ElementID], by t: Transform2, in tx: TransactionContext, viewID: ElementID?,
                                 disjoin: Bool = false) throws(TransactionError) {
        var set = dependentsToCarry(Set(ids), tx.model, viewID: viewID)
        for id in set { for h in tx.model.hosted(by: id) where h.cutProfile != nil { set.insert(h.id) } } // F810: cut profiles move with their wall
        let pinned = set.filter { tx.model[$0]?.pinned == true }
        if !pinned.isEmpty { throw TransactionError("Pinned elements can't be moved. Unpin them first.", elements: Array(pinned)) }
        let before = tx.model
        for id in set.sorted() {
            guard let e = tx.model[id], ElementTransform.isTransformable(e) else { continue }
            tx.update(id) { ElementTransform.apply(t, to: &$0) }
        }
        if disjoin { try rehostMovedInserts(set, in: tx) } else { keepWallJoins(moved: set, before: before, in: tx) }
    }

    /// Walls joined to moved walls stay joined: the joined end of each neighbour that did not move follows to where
    /// its own line meets the moved wall's new centerline (corner and tee joins), as when dragging a joined wall.
    static func keepWallJoins(moved: Set<ElementID>, before: BIMModel, in tx: TransactionContext) {
        let tol = 1e-3
        for id in moved.sorted() {
            guard let old = before[id], let oldSeg = old.wall?.location.asSegment, let newSeg = tx.model[id]?.wall?.location.asSegment else { continue }
            for cand in WallGeometry.joinCandidates(old, before) where !moved.contains(cand.id) && !cand.pinned {
                // Current state: another moved wall may already have adjusted this neighbour's other end.
                guard let n = tx.model[cand.id], let nw = n.wall, let nSeg = nw.location.asSegment else { continue }
                for atEnd in [false, true] {
                    let p = atEnd ? nSeg.end : nSeg.start
                    guard atEnd ? nw.allowJoinAtEnd : nw.allowJoinAtStart, oldSeg.distance(to: p) <= tol else { continue }
                    let q: Vec2
                    if let hit = nSeg.lineIntersection(newSeg), !nSeg.isParallel(to: newSeg) {
                        q = hit.point
                    } else if p.distance(to: oldSeg.start) <= tol || p.distance(to: oldSeg.end) <= tol {
                        // Collinear continuation: the shared end moves with the wall.
                        q = p.distance(to: oldSeg.start) <= tol ? newSeg.start : newSeg.end
                    } else { continue }
                    let other = atEnd ? nSeg.start : nSeg.end
                    guard other.distance(to: q) > Tolerance.shortCurve * 10 else { continue }
                    tx.update(n.id) { e in
                        guard var w = e.wall, var seg = w.location.asSegment else { return }
                        if atEnd { seg = Segment2(seg.start, q) } else { seg = Segment2(q, seg.end) }
                        w.location = .line(seg)
                        e.wall = w
                    }
                }
            }
        }
    }

    /// Copies elements (and dependents that should travel with them) applying a transform.
    /// References among copied elements are remapped; external references are kept. Returns old → new ids.
    @discardableResult
    public static func copy(_ ids: [ElementID], by t: Transform2, in tx: TransactionContext, viewID: ElementID?,
                            targetLevel: ElementID? = nil, levelDelta: Double = 0, targetView: ElementID? = nil) -> [ElementID: ElementID] {
        // `levelDelta` is kept for source compatibility; vertical placement follows `targetLevel` (see remapTopConstraint).
        let src = tx.model
        var set = dependentsToCarry(Set(ids), src, viewID: viewID)
        // Never copy views/types/etc.
        set = set.filter { src[$0].map { ElementTransform.isTransformable($0) || $0.category == .rooms } ?? false }
        // Create copies first (references still point at the originals), then remap references among copies.
        var real: [ElementID: ElementID] = [:]
        for id in set.sorted() {
            guard var e = src[id] else { continue }
            e.ifcGUID = .random()
            e.pinned = false
            e.mark = ""
            if let tl = targetLevel, let sl = e.levelID, src[sl]?.level != nil {
                e.levelID = tl
                remapTopConstraint(&e, from: sl, to: tl, in: src)
            }
            if let tv = targetView, e.ownerViewID != nil { e.ownerViewID = tv }
            ElementTransform.apply(t, to: &e)
            let data = e.data
            let newID = tx.create(e.category, name: e.name, data: data, typeID: e.typeID, levelID: e.levelID, hostID: e.hostID, ownerViewID: e.ownerViewID) { ne in
                ne.params = e.params
                ne.params[.mark] = nil
                ne.phaseCreated = e.phaseCreated
                ne.designOptionID = e.designOptionID
                ne.classification = e.classification
            }
            real[id] = newID
        }
        // Fix references to placeholder ids now that real ids are known.
        for (old, new) in real {
            guard let e = tx.model[new] else { continue }
            var changed = e
            if let h = src[old]?.hostID, let nh = real[h] { changed.hostID = nh }
            if case .tag(var td) = changed.data, let target = src[old]?.tag?.taggedID, let nt = real[target] { td.taggedID = nt; changed.data = .tag(td) }
            if case .group(var g) = changed.data, let members = src[old]?.group?.members { g.members = members.map { real[$0] ?? $0 }; changed.data = .group(g) }
            if case .group(var g) = changed.data, let spec = g.arraySpec { g.arraySpec?.sourceMembers = spec.sourceMembers.map { real[$0] ?? $0 }; changed.data = .group(g) }
            if changed != e { tx.update(new) { $0 = changed } }
        }
        return real
    }

    /// Paste to another level keeps each element's vertical extent relative to its base level. A top constraint
    /// (or room upper limit) moves to the level at the same elevation offset from the target level; when no such
    /// level exists the element becomes unconnected with its original height.
    static func remapTopConstraint(_ e: inout Element, from source: ElementID, to target: ElementID, in m: BIMModel) {
        let delta = m.elevation(ofLevel: target) - m.elevation(ofLevel: source)
        func mapped(_ top: ElementID) -> ElementID? {
            let want = m.elevation(ofLevel: top) + delta
            return m.levels.first { abs(($0.level?.elevation ?? .nan) - want) < 1e-6 }?.id
        }
        switch e.data {
        case .wall(var w):
            if let top = w.topLevelID {
                if let t = mapped(top) { w.topLevelID = t } else {
                    w.unconnectedHeight = max(0.1, m.elevation(ofLevel: top) + w.topOffset - m.elevation(ofLevel: source) - w.baseOffset)
                    w.topLevelID = nil; w.topOffset = 0
                }
            }
            e.data = .wall(w)
        case .column(var c):
            if let top = c.topLevelID {
                if let t = mapped(top) { c.topLevelID = t } else {
                    c.unconnectedHeight = max(0.1, m.elevation(ofLevel: top) + c.topOffset - m.elevation(ofLevel: source) - c.baseOffset)
                    c.topLevelID = nil; c.topOffset = 0
                }
            }
            e.data = .column(c)
        case .stair(var st):
            if let top = st.topLevelID {
                if let t = mapped(top) { st.topLevelID = t } else {
                    st.unconnectedHeight = max(0.1, m.elevation(ofLevel: top) + st.topOffset - m.elevation(ofLevel: source) - st.baseOffset)
                    st.topLevelID = nil; st.topOffset = 0
                }
            }
            e.data = .stair(st)
        case .ramp(var rp):
            if let top = rp.topLevelID {
                if let t = mapped(top) { rp.topLevelID = t } else {
                    rp.unconnectedHeight = max(0.1, m.elevation(ofLevel: top) + rp.topOffset - m.elevation(ofLevel: source) - rp.baseOffset)
                    rp.topLevelID = nil; rp.topOffset = 0
                }
            }
            e.data = .ramp(rp)
        case .room(var r):
            if let up = r.upperLimitLevelID {
                if let t = mapped(up) { r.upperLimitLevelID = t } else {
                    r.limitOffset += m.elevation(ofLevel: up) - m.elevation(ofLevel: source)
                    r.upperLimitLevelID = nil
                }
            }
            e.data = .room(r)
        default: break
        }
    }

    /// Splits a wall or line at a point into two elements; hosted inserts move to the piece that contains them.
    public static func split(_ id: ElementID, at p: Vec2, in tx: TransactionContext) throws(TransactionError) {
        guard let e = tx.model[id] else { return }
        let curve: Curve2?
        switch e.data {
        case .wall(let w): curve = w.location
        case .modelLine(let l): curve = l.freeform == nil ? l.curve : nil // F1: splines and ellipses aren't split
        case .beam(let b): curve = b.curve
        default: curve = nil
        }
        guard let c = curve else { throw TransactionError("Only walls, lines and beams can be split.", elements: [id]) }
        let t = c.parameter(of: c.closestPoint(to: p))
        guard let (a, b) = c.split(at: t) else { throw TransactionError("Pick a point away from the ends to split.", elements: [id]) }
        func setCurve(_ el: inout Element, _ nc: Curve2) {
            switch el.data {
            case .wall(var w): w.location = nc; el.data = .wall(w)
            case .modelLine(var l): l.curve = nc; el.data = .modelLine(l)
            case .beam(var bm): bm.curve = nc; el.data = .beam(bm)
            default: break
            }
        }
        tx.update(id) { setCurve(&$0, a) }
        var second = e
        setCurve(&second, b)
        let newID = tx.create(e.category, name: e.name, data: second.data, typeID: e.typeID, levelID: e.levelID, hostID: e.hostID, ownerViewID: e.ownerViewID) { ne in
            ne.params = e.params; ne.params[.mark] = nil; ne.phaseCreated = e.phaseCreated
        }
        // Reassign hosted inserts beyond the split point.
        if e.wall != nil {
            for h in tx.model.hosted(by: id) where h.insert != nil {
                if let loc = h.insert?.location, b.distance(to: loc) < a.distance(to: loc) {
                    tx.update(h.id) { $0.hostID = newID }
                }
            }
        }
    }

    /// Trims/extends the end of `id`'s curve nearest `pickPoint` to meet `boundary`'s curve.
    public static func trimExtend(_ id: ElementID, keepNear pickPoint: Vec2, to boundary: Curve2, in tx: TransactionContext) throws(TransactionError) {
        guard let e = tx.model[id], let c = curveOf(e) else { throw TransactionError("That element can't be trimmed or extended.", elements: [id]) }
        // Intersection of infinite extensions.
        guard let seg = c.asSegment, let bseg = boundary.asSegment, let hit = seg.lineIntersection(bseg) else {
            if let r = c.trimmedOrExtended(toMeet: boundary, atEnd: c.end.distance(to: pickPoint) > c.start.distance(to: pickPoint)) {
                tx.update(id) { setCurveOf(&$0, r) }
                return
            }
            throw TransactionError("The elements are parallel and can't meet.", elements: [id])
        }
        let x = hit.point
        // Keep the side of the curve containing the pick point.
        let tPick = seg.parameter(of: pickPoint)
        let tX = hit.t
        let newSeg: Segment2
        if tX >= 0 && tX <= 1 {
            // Trim: keep the portion on the picked side.
            newSeg = tPick < tX ? Segment2(seg.start, x) : Segment2(x, seg.end)
        } else if tX > 1 {
            newSeg = Segment2(seg.start, x)
        } else {
            newSeg = Segment2(x, seg.end)
        }
        guard newSeg.length > Tolerance.shortCurve else { throw TransactionError("The result would be too short.", elements: [id]) }
        tx.update(id) { setCurveOf(&$0, .line(newSeg)) }
    }

    public static func curveOf(_ e: Element) -> Curve2? {
        switch e.data {
        case .wall(let w): w.location
        case .modelLine(let l): l.freeform == nil ? l.curve : nil // F1: splines and ellipses are not trimmed, split or offset
        case .beam(let b): b.curve
        case .grid(let g): g.isMultiSegment ? nil : g.curve // F2: multi-segment grids are not trimmed, split or offset
        case .referencePlane(let r): .line(r.line)
        default: nil
        }
    }
    public static func setCurveOf(_ e: inout Element, _ c: Curve2) {
        switch e.data {
        case .wall(var w): w.location = c; e.data = .wall(w)
        case .modelLine(var l): l.curve = c; e.data = .modelLine(l)
        case .beam(var b): b.curve = c; e.data = .beam(b)
        case .grid(var g): g.curve = c; e.data = .grid(g)
        case .referencePlane(var r): if let s = c.asSegment { r.line = s; e.data = .referencePlane(r) }
        default: break
        }
    }

    /// Selection center in plan (bounds center of plan-transformable elements).
    public static func center(of ids: [ElementID], _ model: BIMModel) -> Vec2 {
        var r = Rect2.empty
        for id in ids { if let e = model[id] { r.include(ElementMeshes.bounds(e, model).xy) } }
        return r.isEmpty ? .zero : r.center
    }
}

