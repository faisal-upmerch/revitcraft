import Foundation
import ArcusGeometry
import ArcusDomain

// S3D: 3D snaps for tools running on a work plane (see Snapping3D.swift). A tool still receives plan points; a 3D snap
// gives the plan point under (or over) the snapped geometry and, for face-hosted tools, the snapped point itself as the
// surface point.

/// The outcome of snapping a 3D pointer: the plan point a tool gets, its snap, and the 3D feature when the snap came
/// from model geometry rather than from the work plane's plan snaps.
public struct Snap3DPick: Sendable {
    public var point: Vec2
    public var snap: SnapResult?
    public var feature: Snap3DCandidate?
    public init(point: Vec2, snap: SnapResult?, feature: Snap3DCandidate? = nil) { self.point = point; self.snap = snap; self.feature = feature }

    /// Where the marker goes: on the model for 3D snaps, else on the work plane.
    public func location(planeZ: Double) -> Vec3 { feature?.point ?? Vec3(point, z: planeZ) }
}

extension ToolContext {
    /// Status label of a 3D snap, as in plan: "ENDPOINT of [Walls : Basic Wall : Generic 200mm]".
    public func label3D(_ c: Snap3DCandidate) -> (label: String, short: String) {
        let of = c.elementIDs.first.map { "[\(elementLabel($0))]" } ?? ""
        switch c.feature {
        case .point: return ("POINT of \(of)", "Point")
        case .face: return ("ON FACE of \(of)", "Face")
        case .workPlaneIntersection: return ("INTERSECTION of \(of) AND WORK PLANE", "Intersection")
        default:
            return (pointLabel(SnapResult(point: c.point.xy, kind: c.kind, elementIDs: c.elementIDs)), c.kind.rawValue)
        }
    }

    /// The pick for a 3D candidate: its plan projection (on the Shift line through `from` when constrained), labelled,
    /// with "AND HORIZONTAL/VERTICAL" when it also lines up with the start point.
    func pick3D(_ c: Snap3DCandidate, from: Vec2?, constrainOrtho: Bool) -> Snap3DPick {
        var p = c.point.xy
        if constrainOrtho, let f = from {
            let d = p - f
            p = abs(d.x) >= abs(d.y) ? Vec2(p.x, f.y) : Vec2(f.x, p.y)
        }
        var r = SnapResult(point: p, kind: c.kind, elementIDs: c.elementIDs)
        var (label, short) = label3D(c)
        if let f = from, !constrainOrtho, f.distance(to: p) > pixel * 4 {
            for (dir, name) in [(Vec2.unitX, "HORIZONTAL"), (Vec2.unitY, "VERTICAL")] where abs((p - f).cross(dir)) < pixel * 0.5 {
                label += " AND \(name)"
                short += " and \(name.capitalized)"
                let g = Guide(origin: f, direction: dir, label: name, kind: .angle, ids: [], anchor: f, throughStart: true)
                if let s = guideSegment(g, to: p) { r.guides.append(s) }
            }
        }
        r.label = label
        r.shortLabel = short
        return Snap3DPick(point: p, snap: r, feature: c)
    }

    /// Snaps a 3D pointer whose ray meets the work plane `planeZ` at `raw`. Revit's order between model geometry and the
    /// plane's own snaps: a point snap on visible geometry (endpoint, intersection, midpoint, perpendicular …) wins over
    /// a plan point snap of lower priority, else the plan snap, guide crossings and tracking apply as in plan; the
    /// nearest point on a visible edge comes before a lone tracking guide. With `faceSnap` (face-hosted tools) any
    /// visible 3D snap comes first and the face under the pointer is the last resort. `query` carries the camera and pointer; settings, exclusions and the
    /// start point come from this context.
    public func snap3D(_ raw: Vec2, planeZ: Double, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?,
                       orthoOnly: Bool = false, constrainOrtho: Bool = false, faceSnap: Bool = false) -> Snap3DPick {
        let settings = effectiveSnapSettings
        guard settings.snapsOn, let index else {
            let (p, s) = snap(raw, from: from, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
            return Snap3DPick(point: p, snap: s)
        }
        let q = configured(query, settings: settings, planeZ: planeZ, from: from)
        let found = index.candidates(q)
        let screen = { (p: Vec2) -> Double in q.camera.project(Vec3(p, z: planeZ)).map { $0.distance(to: q.pointer) } ?? .infinity }
        // On a face the model's geometry is what counts (a plan snap has no height): reveals, sweeps and hosted
        // elements take the visible corner, midpoint or edge under the pointer first.
        if faceSnap, let c = found.first { return pick3D(c, from: from, constrainOrtho: constrainOrtho) }
        if let c = found.first(where: { $0.feature != .edge }) {
            let plan = snapIndex.snap(raw, radius: settings.pixelRadius * pixel, from: from, settings: settings, exclude: snapExclusions)
            let planWins = plan.map { $0.kind != .nearest && ($0.kind.priority, screen($0.point)) < (c.kind.priority, c.screenDistance) } ?? false
            if !planWins { return pick3D(c, from: from, constrainOrtho: constrainOrtho) }
        }
        let (p, s) = snap(raw, from: from, orthoOnly: orthoOnly, constrainOrtho: constrainOrtho)
        let loneGuide = s.map { [.angle, .parallel, .extension].contains($0.kind) } ?? true
        if loneGuide, let c = found.first(where: { $0.feature == .edge }) { return pick3D(c, from: from, constrainOrtho: constrainOrtho) }
        if faceSnap, s == nil, let c = index.faceHit(q) { return pick3D(c, from: from, constrainOrtho: constrainOrtho) }
        return Snap3DPick(point: p, snap: s)
    }

    /// Every distinct snap within reach, best first, from model geometry and from the work plane: what Tab steps through
    /// in a 3D view (as `snapCandidates` in plan).
    public func snap3DCandidates(_ raw: Vec2, planeZ: Double, index: Snap3DIndex?, query: Snap3DQuery, from: Vec2?) -> [Snap3DPick] {
        let settings = effectiveSnapSettings
        guard settings.snapsOn else { return [] }
        var ranked: [(pick: Snap3DPick, key: (Int, Double))] = []
        if let index {
            let q = configured(query, settings: settings, planeZ: planeZ, from: from)
            for c in index.candidates(q) { ranked.append((pick3D(c, from: from, constrainOrtho: false), (c.kind.priority, c.screenDistance))) }
        }
        for s in snapCandidates(raw, from: from) {
            var r = s
            r.label = pointLabel(s)
            r.shortLabel = s.kind.rawValue
            let d = query.camera.project(Vec3(s.point, z: planeZ)).map { $0.distance(to: query.pointer) } ?? .infinity
            ranked.append((Snap3DPick(point: s.point, snap: r), (s.kind.priority, d)))
        }
        ranked.sort { $0.key < $1.key }
        var out: [Snap3DPick] = []
        for r in ranked where !out.contains(where: { $0.location(planeZ: planeZ).distance(to: r.pick.location(planeZ: planeZ)) <= 1e-4 }) {
            out.append(r.pick)
        }
        return out
    }

    func configured(_ query: Snap3DQuery, settings: SnapSettings, planeZ: Double, from: Vec2?) -> Snap3DQuery {
        var q = query
        q.radius = settings.pixelRadius
        q.enabled = settings.enabled
        q.exclude.formUnion(snapExclusions)
        q.from = from.map { Vec3($0, z: planeZ) }
        q.workPlaneZ = planeZ
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
