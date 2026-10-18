import Foundation
import ArcusGeometry
import ArcusDomain

/// A temporary dimension shown on a single selected element: from the element to the nearest parallel reference
/// (wall centerline, grid, reference plane, another opening on the same wall), or a wall's length. Typing a new
/// value moves the element so the distance becomes that value; the other reference stays put.
public struct SelectionDimension: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// Distance to another reference; a new value translates the element along `direction`.
        case offset
        /// Length of a wall; a new value moves its end point along `direction`.
        case length
    }
    public var elementID: ElementID
    public var role: Role
    /// Point on the selected element's reference and the matching point on the other reference (view coordinates).
    public var from: Vec2
    public var to: Vec2
    public var value: Double
    /// Unit vector the element (or its end) moves along as the value grows.
    public var direction: Vec2
    /// The references measured, for making the dimension permanent: the selected element's first, then the other.
    public var elementReference: GeometryReference
    public var otherReference: GeometryReference
}

public enum SelectionDimensions {
    /// A reference line an element can be dimensioned to.
    struct RefLine {
        var seg: Segment2
        var ref: GeometryReference
    }

    /// Parallel within about half a degree.
    static let parallelTolerance = 0.01

    /// Temporary dimensions for `id` in a plan view. Walls get their length and the distance to the nearest parallel
    /// reference on each side; doors and windows the distance along the host to the nearest reference on each side;
    /// grids and reference planes the distance to their parallel neighbours; columns and components one dimension
    /// per axis. Other elements and non-plan views get none.
    public static func compute(for id: ElementID, in model: BIMModel, view: Element?) -> [SelectionDimension] {
        guard view?.view?.kind.isPlan == true, let e = model[id] else { return [] }
        let level = e.levelID ?? view?.levelID
        switch e.data {
        case .wall(let w):
            guard let f = WallGeometry.frame(e, model), let loc = w.location.asSegment, loc.length > Tolerance.shortCurve,
                  let left = f.location.offset(by: f.leftOffset).asSegment, let right = f.location.offset(by: f.rightOffset).asSegment else { return [] }
            // Face to face: each face of the wall to the nearest face (or datum) on its side.
            let refs = wallFaceLines(model, level: level, excluding: [id]) + datumLines(model) + planeLines(model)
            if TemporaryDimensionSettings.walls == .centerlines { // BL-VG: centerline to centerline
                guard let center = f.location.offset(by: f.centerOffset).asSegment else { return [] }
                return offsets(id, GeometryReference(id, .location), line: center, margin: 0, along: 0.4, candidates: refs)
                    + [SelectionDimension(elementID: id, role: .length, from: loc.start, to: loc.end, value: loc.length, direction: loc.direction,
                                          elementReference: GeometryReference(id, .startPoint), otherReference: GeometryReference(id, .endPoint))]
            }
            let leftKind: GeometryReference.Kind = f.leftOffset == f.exteriorOffset ? .exteriorFace : .interiorFace
            let rightKind: GeometryReference.Kind = leftKind == .exteriorFace ? .interiorFace : .exteriorFace
            var out = offsets(id, GeometryReference(id, leftKind), line: left, margin: 0, along: 0.4, candidates: refs, sides: [true])
                + offsets(id, GeometryReference(id, rightKind), line: right, margin: 0, along: 0.4, candidates: refs, sides: [false])
            out.append(SelectionDimension(elementID: id, role: .length, from: loc.start, to: loc.end, value: loc.length, direction: loc.direction,
                                          elementReference: GeometryReference(id, .startPoint), otherReference: GeometryReference(id, .endPoint)))
            return out
        case .insert:
            guard let host = model[e.hostID], let f = WallGeometry.frame(host, model), f.isStraight,
                  let l = DimensionQueries.resolve(GeometryReference(id, .openingLeft), model),
                  let r = DimensionQueries.resolve(GeometryReference(id, .openingRight), model) else { return [] }
            return insertDimensions(id: id, jambs: [(l.point, GeometryReference(id, .openingLeft)), (r.point, GeometryReference(id, .openingRight))],
                                    host: host, frame: f, model: model)
        case .grid(let g):
            guard let s = g.curve.asSegment else { return [] }
            let refs = datumLines(model).filter { $0.ref.elementID != id }
            return offsets(id, GeometryReference(id, .location), line: s, margin: 0, along: 0.5, candidates: refs)
        case .referencePlane(let r):
            let refs = wallFaceLines(model, level: level, excluding: []) + datumLines(model) + planeLines(model).filter { $0.ref.elementID != id }
            return offsets(id, GeometryReference(id, .location), line: r.line, margin: 0, along: 0.5, candidates: refs)
        case .column, .component:
            guard let pl = ComponentGeometry.placement(e, model) else { return [] }
            let p = pl.plan.apply(.zero)
            let reach = 0.3
            let refs = wallFaceLines(model, level: level, excluding: []) + datumLines(model) + planeLines(model)
            var out: [SelectionDimension] = []
            // One dimension per axis: the nearer of the two sides.
            for axis in [Vec2(0, 1), Vec2(1, 0)] {
                let line = Segment2(p - axis * reach, p + axis * reach)
                let both = offsets(id, GeometryReference(id, .center), line: line, margin: 0, along: 0.5, candidates: refs)
                if let nearest = both.min(by: { $0.value < $1.value }) { out.append(nearest) }
            }
            return out
        default:
            return []
        }
    }

    /// Nearest parallel candidate on each side of `line`, measured perpendicular to it. A candidate counts only when
    /// its extent along `line` overlaps the element's (widened by `margin`). `along` places the dimension within the
    /// overlap (0 = start, 1 = end) so it does not sit on top of the length dimension.
    /// A door or window: from each opening edge (jamb) to the nearest wall face, other opening edge or host end on
    /// that side, measured along the host. `jambs` are the two edge points on the host's location line.
    static func insertDimensions(id: ElementID, jambs: [(point: Vec2, ref: GeometryReference)], host: Element, frame f: WallFrame,
                                 model: BIMModel) -> [SelectionDimension] {
        guard jambs.count == 2, let hostSeg = f.location.asSegment else { return [] }
        let across = hostSeg.direction.perpendicular
        let lo = f.rightOffset, hi = f.leftOffset
        var refs = wallFaceLines(model, level: host.levelID, excluding: [host.id]) + datumLines(model) + planeLines(model)
        for other in model.hosted(by: host.id) where other.id != id && other.insert != nil {
            for k in [GeometryReference.Kind.openingLeft, .openingRight] {
                guard let p = DimensionQueries.resolve(GeometryReference(other.id, k), model)?.point else { continue }
                refs.append(RefLine(seg: Segment2(p + across * lo, p + across * hi), ref: GeometryReference(other.id, k)))
            }
        }
        for (end, kind) in [(hostSeg.start, GeometryReference.Kind.startPoint), (hostSeg.end, .endPoint)] {
            refs.append(RefLine(seg: Segment2(end + across * lo, end + across * hi), ref: GeometryReference(host.id, kind)))
        }
        // Order the jambs along the host; each measures to its own side only.
        let sorted = jambs.sorted { ($0.point - hostSeg.start).dot(hostSeg.direction) < ($1.point - hostSeg.start).dot(hostSeg.direction) }
        var out: [SelectionDimension] = []
        for (j, towardsStart) in [(sorted[0], true), (sorted[1], false)] {
            // A line across the wall at the jamb; its positive side (left of `across`) points back along the host.
            let line = Segment2(j.point + across * lo, j.point + across * hi)
            out += offsets(id, j.ref, line: line, margin: 0.05, along: 0.5, candidates: refs, sides: [towardsStart])
        }
        return out
    }

    static func offsets(_ id: ElementID, _ ref: GeometryReference, line: Segment2, margin: Double, along: Double, candidates: [RefLine],
                        sides: [Bool] = [true, false]) -> [SelectionDimension] {
        let len = line.length
        guard len > 1e-9 else { return [] }
        let t = line.direction
        let n = t.perpendicular
        var best: [Bool: (d: Double, s: Double, ref: GeometryReference)] = [:]
        for c in candidates {
            guard c.seg.length > 1e-9, abs(t.cross(c.seg.direction)) <= parallelTolerance else { continue }
            let d = (c.seg.start - line.start).dot(n)
            guard abs(d) > Tolerance.length * 10 else { continue }
            let a = (c.seg.start - line.start).dot(t), b = (c.seg.end - line.start).dot(t)
            let lo = max(min(a, b), -margin), hi = min(max(a, b), len + margin)
            guard hi >= lo else { continue }
            let s = min(max(lo + (hi - lo) * along, 0), len)
            let positive = d > 0
            if abs(d) < abs(best[positive]?.d ?? .infinity) { best[positive] = (d, s, c.ref) }
        }
        return sides.compactMap { side in
            guard let b = best[side] else { return nil }
            let from = line.start + t * b.s
            // Growing the value moves the element away from the reference.
            return SelectionDimension(elementID: id, role: .offset, from: from, to: from + n * b.d, value: abs(b.d),
                                      direction: n * (b.d > 0 ? -1 : 1), elementReference: ref, otherReference: b.ref)
        }
    }

    static func wallLines(_ model: BIMModel, level: ElementID?, excluding: Set<ElementID>) -> [RefLine] {
        model.elements(.walls).compactMap { w in
            guard !excluding.contains(w.id), level == nil || w.levelID == level, let f = WallGeometry.frame(w, model),
                  let s = f.location.offset(by: f.centerOffset).asSegment else { return nil }
            return RefLine(seg: s, ref: GeometryReference(w.id, .location))
        }
    }
    /// Both finish faces of each straight wall on the level (temporary dimensions measure to faces).
    static func wallFaceLines(_ model: BIMModel, level: ElementID?, excluding: Set<ElementID>) -> [RefLine] {
        model.elements(.walls).flatMap { w -> [RefLine] in
            guard !excluding.contains(w.id), level == nil || w.levelID == level, let f = WallGeometry.frame(w, model),
                  let ext = f.exteriorFace.asSegment, let int = f.interiorFace.asSegment else { return [] }
            if TemporaryDimensionSettings.walls == .centerlines { return f.location.offset(by: f.centerOffset).asSegment.map { [RefLine(seg: $0, ref: GeometryReference(w.id, .location))] } ?? [] } // BL-VG
            return [RefLine(seg: ext, ref: GeometryReference(w.id, .exteriorFace)), RefLine(seg: int, ref: GeometryReference(w.id, .interiorFace))]
        }
    }
    static func datumLines(_ model: BIMModel) -> [RefLine] {
        model.elements(.grids).compactMap { g in g.grid?.curve.asSegment.map { RefLine(seg: $0, ref: GeometryReference(g.id, .location)) } }
    }
    static func planeLines(_ model: BIMModel) -> [RefLine] {
        model.elements(.referencePlanes).compactMap { r in r.referencePlane.map { RefLine(seg: $0.line, ref: GeometryReference(r.id, .location)) } }
    }

    // MARK: Editing

    /// Moves the element so the dimension reads `value` (exactly what dragging it to that position does: hosted
    /// elements follow and joined walls stay joined).
    public static func apply(_ d: SelectionDimension, value: Double, in tx: TransactionContext, viewID: ElementID?) throws(TransactionError) {
        guard let e = tx.model[d.elementID] else { throw TransactionError("The element no longer exists.") }
        if e.pinned { throw TransactionError("The element is pinned. Unpin it to edit.", elements: [e.id]) }
        switch d.role {
        case .offset:
            guard value >= 0 else { throw TransactionError("Enter a distance of zero or more.") }
            let delta = value - d.value
            guard abs(delta) > Tolerance.length else { return }
            try ElementOperations.transform([d.elementID], by: .translation(d.direction * delta), in: tx, viewID: viewID)
        case .length:
            guard value > Tolerance.shortCurve else { throw TransactionError("Enter a length greater than zero.") }
            guard let c = ElementOperations.curveOf(e), c.asSegment != nil else { return }
            GripService.apply(Grip(elementID: e.id, kind: .end, position: c.end), to: c.start + d.direction * value, in: tx)
        }
    }

    /// A permanent aligned dimension measuring the same thing. A line reference goes first so the dimension measures
    /// perpendicular to it. `offset` shifts the dimension line off a length dimension's element (view units).
    public static func permanent(_ d: SelectionDimension, in model: BIMModel, offset: Double) -> DimensionData {
        switch d.role {
        case .length:
            let side = d.direction.perpendicular * offset
            return DimensionData(kind: .aligned, references: [d.elementReference, d.otherReference], linePoint: (d.from + d.to) * 0.5 + side,
                                 fallbackPoints: [d.from, d.to])
        case .offset:
            let elementIsLine = DimensionQueries.resolve(d.elementReference, model)?.direction != nil
            let refs = elementIsLine ? [d.elementReference, d.otherReference] : [d.otherReference, d.elementReference]
            let pts = elementIsLine ? [d.from, d.to] : [d.to, d.from]
            return DimensionData(kind: .aligned, references: refs, linePoint: (d.from + d.to) * 0.5, fallbackPoints: pts)
        }
    }
}
