import Foundation
import ArcusGeometry
import ArcusDomain

// S3D: 3D snaps for tools running on a work plane (see Snapping3D.swift). A tool still receives plan points; a 3D snap
// gives the plan point under (or over) the snapped geometry and, for face-hosted tools, the snapped point itself as the
// surface point.

/// The outcome of snapping a 3D pointer: the point a tool gets (plan, or the work plane's coordinates), its snap, and the
/// 3D feature when the snap came from model geometry rather than from the work plane's own snaps.
public struct Snap3DPick: Sendable {
    public var point: Vec2
    public var snap: SnapResult?
    public var feature: Snap3DCandidate?
    public init(point: Vec2, snap: SnapResult?, feature: Snap3DCandidate? = nil) { self.point = point; self.snap = snap; self.feature = feature }

    /// Where the marker goes: on the model for 3D snaps, else on the work plane.
    public func location(planeZ: Double) -> Vec3 { feature?.point ?? Vec3(point, z: planeZ) }
    /// S3D2: as `location(planeZ:)` on any work plane.
    public func location(on f: WorkPlaneFrame) -> Vec3 { feature?.point ?? f.point(point.x, point.y) }
}

extension WorkPlaneFrame {
    /// S3D2: the horizontal plane of a level at `z`, whose coordinates are plan coordinates.
    public static func level(_ z: Double) -> WorkPlaneFrame { WorkPlaneFrame(origin: Vec3(0, 0, z), u: .unitX, v: .unitY) }
    /// S3D2: a model point in this plane's coordinates (projected along its normal).
    public func local(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(u), d.dot(v)) }
    /// S3D2: where a ray meets the plane; nil when parallel or behind.
    public func intersect(origin o: Vec3, direction d: Vec3) -> Vec3? {
        let n = normal
        let den = d.dot(n)
        guard abs(den) > 1e-9 else { return nil }
        let t = (origin - o).dot(n) / den
        guard t > 0, t.isFinite else { return nil }
        return o + d * t
    }
}

extension ToolContext {
    /// Status label of a 3D snap, as in plan: "ENDPOINT of [Walls : Basic Wall : Generic 200mm]".
    public func label3D(_ c: Snap3DCandidate) -> (label: String, short: String) {
        let of = c.elementIDs.first.map { "[\(elementLabel($0))]" } ?? ""
        switch c.feature {
        case .point: return ("POINT of \(of)", "Point")
        case .face: return ("ON FACE of \(of)", "Face")
        case .workPlaneIntersection: return ("INTERSECTION of \(of) AND WORK PLANE", "Intersection")
        case .apparentIntersection: // S3D2
            return ("APPARENT INTERSECTION of " + c.elementIDs.map { "[\(elementLabel($0))]" }.joined(separator: " AND "), "Apparent Intersection")
        default:
            return (pointLabel(SnapResult(point: c.point.xy, kind: c.kind, elementIDs: c.elementIDs)), c.kind.rawValue)
        }
    }

    /// The pick for a 3D candidate: its projection on the work plane (on the Shift line through `from` when
    /// constrained), labelled, with "AND HORIZONTAL/VERTICAL" when it also lines up with the start point.
    func pick3D(_ c: Snap3DCandidate, plane f: WorkPlaneFrame, from: Vec2?, constrainOrtho: Bool) -> Snap3DPick {
        var p = f.local(c.point)
        if constrainOrtho, let s = from {
            let d = p - s
            p = abs(d.x) >= abs(d.y) ? Vec2(p.x, s.y) : Vec2(s.x, p.y)
        }
        var r = SnapResult(point: p, kind: c.kind, elementIDs: c.elementIDs)
        var (label, short) = label3D(c)
        if let s = from, !constrainOrtho, s.distance(to: p) > pixel * 4 {
            for (dir, name) in [(Vec2.unitX, "HORIZONTAL"), (Vec2.unitY, "VERTICAL")] where abs((p - s).cross(dir)) < pixel * 0.5 {
                label += " AND \(name)"
                short += " and \(name.capitalized)"
                let g = Guide(origin: s, direction: dir, label: name, kind: .angle, ids: [], anchor: s, throughStart: true)
                if let seg = guideSegment(g, to: p) { r.guides.append(seg) }
            }
        }
        r.label = label
        r.shortLabel = short
        return Snap3DPick(point: p, snap: r, feature: c)
    }

    /// Snaps a 3D pointer whose ray meets the work plane `planeZ` at `raw` (a level: plan coordinates).
    public func snap3D(_ raw: Vec2, planeZ: Double, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?,
                       orthoOnly: Bool = false, constrainOrtho: Bool = false, faceSnap: Bool = false) -> Snap3DPick {
        snap3D(raw, plane: .level(planeZ), index: index, query: query, from: from, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho, faceSnap: faceSnap)
    }

    /// Snaps a 3D pointer whose ray meets the work plane `f` at `raw` (in its coordinates). Revit's order between model
    /// geometry and the plane's own snaps (this context's snap index, in the plane's coordinates): a point snap on
    /// visible geometry (endpoint, intersection, midpoint, perpendicular …) wins over a plane point snap of lower
    /// priority, else the plane snap, guide crossings and tracking apply as in plan; the nearest point on a visible edge
    /// comes before a lone tracking guide. With `faceSnap` (face-hosted tools) any visible 3D snap comes first,
    /// apparent intersections go onto the nearer edge, and the face under the pointer is the last resort. `query`
    /// carries the camera and pointer; settings, exclusions and the start point come from this context.
    public func snap3D(_ raw: Vec2, plane f: WorkPlaneFrame, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?,
                       orthoOnly: Bool = false, constrainOrtho: Bool = false, faceSnap: Bool = false) -> Snap3DPick {
        let settings = effectiveSnapSettings
        guard settings.snapsOn, index != nil || !query.extraLines.isEmpty else {
            let (p, s) = snap(raw, from: from, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
            return Snap3DPick(point: p, snap: s)
        }
        var q = configured(query, settings: settings, plane: f, from: from)
        q.apparentOntoNearerEdge = faceSnap
        let found = (index ?? Snap3DIndex(sources: [])).candidates(q)
        let screen = { (p: Vec2) -> Double in q.camera.project(f.point(p.x, p.y)).map { $0.distance(to: q.pointer) } ?? .infinity }
        // On a face the model's geometry is what counts (a plan snap has no height): reveals, sweeps and hosted
        // elements take the visible corner, midpoint or edge under the pointer first.
        if faceSnap, let c = found.first { return pick3D(c, plane: f, from: from, constrainOrtho: constrainOrtho) }
        if let c = found.first(where: { $0.feature != .edge }) {
            let plan = snapIndex.snap(raw, radius: settings.pixelRadius * pixel, from: from, settings: settings, exclude: snapExclusions)
            let planWins = plan.map { $0.kind != .nearest && (Double($0.kind.priority), screen($0.point)) < (c.rankPriority, c.screenDistance) } ?? false
            if !planWins { return pick3D(c, plane: f, from: from, constrainOrtho: constrainOrtho) }
        }
        let (p, s) = snap(raw, from: from, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
        let loneGuide = s.map { [.angle, .parallel, .extension].contains($0.kind) } ?? true
        if loneGuide, let c = found.first(where: { $0.feature == .edge }) { return pick3D(c, plane: f, from: from, constrainOrtho: constrainOrtho) }
        if faceSnap, s == nil, let index, let c = index.faceHit(q) { return pick3D(c, plane: f, from: from, constrainOrtho: constrainOrtho) }
        return Snap3DPick(point: p, snap: s)
    }

    /// Every distinct snap within reach on a level work plane, best first: what Tab steps through in a 3D view.
    public func snap3DCandidates(_ raw: Vec2, planeZ: Double, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?) -> [Snap3DPick] {
        snap3DCandidates(raw, plane: .level(planeZ), index: index, query: query, from: from)
    }

    /// Every distinct snap within reach, best first, from model geometry and from the work plane: what Tab steps through
    /// in a 3D view (as `snapCandidates` in plan).
    public func snap3DCandidates(_ raw: Vec2, plane f: WorkPlaneFrame, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?) -> [Snap3DPick] {
        let settings = effectiveSnapSettings
        guard settings.snapsOn else { return [] }
        var ranked: [(pick: Snap3DPick, key: (Double, Double))] = []
        if index != nil || !query.extraLines.isEmpty {
            let q = configured(query, settings: settings, plane: f, from: from)
            for c in (index ?? Snap3DIndex(sources: [])).candidates(q) {
                ranked.append((pick3D(c, plane: f, from: from, constrainOrtho: false), (c.rankPriority, c.screenDistance)))
            }
        }
        for s in snapCandidates(raw, from: from) {
            var r = s
            r.label = pointLabel(s)
            r.shortLabel = s.kind.rawValue
            let d = query.camera.project(f.point(s.point.x, s.point.y)).map { $0.distance(to: query.pointer) } ?? .infinity
            ranked.append((Snap3DPick(point: s.point, snap: r), (Double(s.kind.priority), d)))
        }
        ranked.sort { $0.key < $1.key }
        var out: [Snap3DPick] = []
        for r in ranked where !out.contains(where: { $0.location(on: f).distance(to: r.pick.location(on: f)) <= 1e-4 }) {
            out.append(r.pick)
        }
        return out
    }

    func configured(_ query: Snap3DQuery, settings: SnapSettings, plane f: WorkPlaneFrame, from: Vec2?) -> Snap3DQuery {
        var q = query
        q.radius = settings.pixelRadius
        q.enabled = settings.enabled
        q.exclude.formUnion(snapExclusions)
        q.from = from.map { f.point($0.x, $0.y) }
        q.workPlane = f
        return q
    }
}

/// S3D: `ToolInput`s for 3D pointer samples with snapping to the model geometry of the view.
public enum Snap3DInput {
    /// As `WorkPlane3D.toolInput`, with 3D snaps: the plan point is the snapped geometry's projection on the work plane
    /// and, for face-hosted tools (`preferSurface`), the surface point is the snapped point. Returns the pick too, so
    /// the host can draw its marker on the model.
    @MainActor
    public static func toolInput(_ s: WorkPlane3D.PointerSample, planeZ: Double, ctx: ToolContext, graphics: ViewGraphics?, snapFrom: Vec2?,
                                 index: Snap3DIndex?, query: Snap3DQuery, preferSurface: Bool = false, orthoOnly: Bool = false,
                                 constrainOrtho: Bool = false) -> (input: ToolInput, pick: Snap3DPick)? {
        guard let q = WorkPlane3D.planPoint(s, planeZ: planeZ, preferSurface: preferSurface) else { return nil }
        let raw = q.xy
        let pick = ctx.snap3D(raw, planeZ: planeZ, index: index, query: query, from: snapFrom, orthoOnly: orthoOnly,
                              constrainOrtho: constrainOrtho, faceSnap: preferSurface)
        return (input(s, raw: raw, pick: pick, ctx: ctx, graphics: graphics, preferSurface: preferSurface), pick)
    }

    /// S3D2: the input for a tool drawing on any work plane `f` (its context's `sketchPlane`): the pointer ray meets the
    /// plane, points are in the plane's coordinates and snapping and tracking happen in it.
    @MainActor
    public static func toolInput(_ s: WorkPlane3D.PointerSample, plane f: WorkPlaneFrame, ctx: ToolContext, snapFrom: Vec2?,
                                 index: Snap3DIndex?, query: Snap3DQuery, constrainOrtho: Bool = false) -> (input: ToolInput, pick: Snap3DPick)? {
        guard let w = f.intersect(origin: s.origin, direction: s.direction) ?? s.pickedPoint else { return nil }
        let raw = f.local(w)
        let pick = ctx.snap3D(raw, plane: f, index: index, query: query, from: snapFrom, constrainOrtho: constrainOrtho)
        var i = input(s, raw: raw, pick: pick, ctx: ctx, graphics: nil, preferSurface: false)
        i.surfacePoint = nil
        return (i, pick)
    }

    /// The tool input for a pick (also used for a snap chosen with Tab).
    @MainActor
    public static func input(_ s: WorkPlane3D.PointerSample, raw: Vec2, pick: Snap3DPick, ctx: ToolContext, graphics: ViewGraphics?,
                             preferSurface: Bool) -> ToolInput {
        var i = ToolInput(point: pick.point, rawPoint: raw, snap: pick.snap)
        i.shift = s.shift; i.command = s.command; i.option = s.option; i.clickCount = s.clickCount
        var hits: [ElementID] = []
        if let id = s.pickedID, let e = ctx.model[id], ctx.session.selection.allows(e) { hits.append(id) }
        if let id = pick.feature?.elementIDs.first, preferSurface, !hits.contains(id), let e = ctx.model[id], ctx.session.selection.allows(e) { hits.append(id) }
        if let g = graphics {
            for id in WorkPlane3D.hitCandidates(g, at: raw, tolerance: ctx.pixel * 5, model: ctx.model, allows: { ctx.session.selection.allows($0) }) where !hits.contains(id) {
                hits.append(id)
            }
        }
        i.hit = hits.first
        i.hitCandidates = hits
        if s.pickedID != nil || (preferSurface && pick.feature != nil) { i.surfacePoint = pick.feature?.point ?? s.pickedPoint }
        return i
    }
}

extension Snap3DIndex {
    /// S3D2: the 2D snap index of a work plane, in its coordinates: edges of the model lying in it (within `tolerance`),
    /// the traces of datums crossing it and the centres of curves in it, so tracking, extension, parallel and
    /// perpendicular snaps work on any plane as they do in plan.
    public func planeSnapIndex(_ f: WorkPlaneFrame, traces: [Snap3DExtraLine] = [], tolerance: Double = 0.005) -> SnapIndex {
        var idx = SnapIndex()
        let n = f.normal
        func onPlane(_ p: Vec3) -> Bool { abs((p - f.origin).dot(n)) <= tolerance }
        var touched = 0
        for (i, e) in entries.enumerated() where !e.bounds.isEmpty {
            let ds = e.bounds.corners.map { ($0 - f.origin).dot(n) }
            guard (ds.min() ?? 0) <= tolerance, (ds.max() ?? 0) >= -tolerance else { continue }
            touched += 1
            if touched > 3000 { break }
            let feat = features(i)
            for s in feat.edges where onPlane(s.a) && onPlane(s.b) {
                idx.addSeg(Segment2(f.local(s.a), f.local(s.b)), e.id, isGrid: e.category == .grids, category: e.category)
            }
            for x in feat.extras where x.kind == .center && onPlane(x.p) { idx.addPoint(f.local(x.p), e.id, .center) }
        }
        for t in traces where onPlane(t.segment.a) && onPlane(t.segment.b) {
            idx.addSeg(Segment2(f.local(t.segment.a), f.local(t.segment.b)), t.id, isGrid: t.category == .grids, category: t.category)
        }
        return idx
    }
}

extension ToolContext {
    /// S3D2: element data as placed on this context's sketch plane (model lines, components); unchanged without one.
    public func sketched(_ d: ElementData) -> ElementData {
        guard let sp = sketchPlane else { return d }
        switch d {
        case .modelLine(var l): l.sketchPlane = sp; return .modelLine(l)
        case .component(var c): c.sketchPlane = sp; return .component(c)
        case .modelText(var t): t.sketchPlane = sp; return .modelText(t)
        default: return d
        }
    }
}
