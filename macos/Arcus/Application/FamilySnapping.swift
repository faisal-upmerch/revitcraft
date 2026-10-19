import Foundation
import ArcusGeometry
import ArcusDomain

// SFE: object snapping in the Family Editor's 2D views (Ref. Level plan and the Front, Back, Left and Right elevations),
// the same engine as the project's 2D views: endpoint, midpoint, intersection (reference-plane crossings included), centre,
// quadrant, perpendicular, tangent and nearest snaps; extension and alignment tracking; angle snaps with the adaptive
// increment; Tab cycling and the typed next-pick overrides (SE, SM, SI, …). The family's view geometry is loaded into a
// `SnapIndex` and resolved by a private `ToolContext`, so the priorities, guides and labels are exactly the project's.
// A point snapped onto a reference plane (or a crossing of two) still locks to it (`vertex(_:frame:)`).

/// What a 2D family view offers to snap to, in view coordinates (metres; u right, v up).
public struct FamilySnapScene: Sendable {
    /// A drawn polyline: form edges as the view draws them, symbolic, model and reference lines, region boundaries, nested
    /// family geometry and the sketch in progress.
    public struct Curve: Sendable {
        public var points: [Vec2]
        public var closed: Bool
        /// The family item the curve belongs to (nil for the sketch in progress and other unselectable geometry).
        public var item: FamilyEditing.Item?
        /// Status-bar name of what it is, e.g. "Generic Models : Extrusion 1", "Lines : Reference Lines".
        public var label: String
        /// Drawn only because visibility settings are shown (halftone): snaps only where nothing visible is in reach.
        public var hidden: Bool
        public init(points: [Vec2], closed: Bool, item: FamilyEditing.Item?, label: String, hidden: Bool = false) {
            self.points = points; self.closed = closed; self.item = item; self.label = label; self.hidden = hidden
        }
    }
    /// A true arc or circle (symbolic arcs, which the view tessellates).
    public struct ArcCurve: Sendable {
        public var arc: Arc2
        public var item: FamilyEditing.Item?
        public var label: String
        public init(arc: Arc2, item: FamilyEditing.Item?, label: String) { self.arc = arc; self.item = item; self.label = label }
    }
    public var curves: [Curve]
    public var arcs: [ArcCurve]
    /// Reference planes seen edge-on in the view (infinite lines).
    public var planes: [FamilyEditing.PlaneLine]
    public init(curves: [Curve] = [], arcs: [ArcCurve] = [], planes: [FamilyEditing.PlaneLine] = []) {
        self.curves = curves; self.arcs = arcs; self.planes = planes
    }
}

/// Snapping for one family view (see the file comment). Load the view's scene, keep `pixel` current, then `snap`.
@MainActor
public final class FamilySnapper {
    /// The project's snap engine, on an empty scratch document: `snapIndex` holds the family view's geometry.
    public let context: ToolContext
    public private(set) var scene = FamilySnapScene()
    private var items: [ElementID: FamilyEditing.Item] = [:]
    private var labels: [ElementID: String] = [:]
    private var planeIDs: [String: ElementID] = [:]
    private var planeNames: [ElementID: String] = [:]
    private var itemIDs: [FamilyEditing.Item: ElementID] = [:]
    /// Synthetic ids, far above any project element's.
    private var nextRaw: UInt64 = 1 << 52

    /// Reference planes are infinite: they are indexed as lines from −1 km to +10 km along their direction, so their ends
    /// and midpoints are never within reach of the pointer (the family camera can't zoom out that far).
    static let planeStart = -1_000.0, planeEnd = 10_000.0

    /// `projectInfo`: the project's Project Information element, so lengths along guides round in the project's units.
    public init(projectInfo: Element? = nil) {
        let model = BIMModel(elements: projectInfo.map { [$0] } ?? [], nextID: (projectInfo?.id.raw ?? 0) + 1)
        context = ToolContext(session: DocumentSession(model: model), viewID: ElementID(0))
        context.elementLabelProvider = { [weak self] id in self?.labels[id] }
    }

    public var settings: SnapSettings {
        get { context.snapSettings }
        set { context.snapSettings = newValue }
    }
    /// View units (metres) per screen point.
    public var pixel: Double {
        get { context.pixel }
        set { context.pixel = newValue }
    }
    /// The one-shot override typed for the next pick (SE, SM, …); cleared by `pickDone()`.
    public var snapOverride: ToolContext.SnapOverride? {
        get { context.snapOverride }
        set { context.snapOverride = newValue }
    }
    /// A pick was made: a typed override applied to it only.
    public func pickDone() { context.snapOverride = nil }
    /// The tool changed: lines tracked for parallel/perpendicular guides are forgotten.
    public func resetTracking() { context.acquiredLines = [] }

    /// What is being dragged or edited: it never snaps to itself (kept across reloads).
    public func exclude(_ excluded: [FamilyEditing.Item]) {
        excludedItems = excluded
        context.snapExclusions = Set(excluded.compactMap { item in
            if case .plane(let n) = item { return planeIDs[n] }
            return itemIDs[item]
        })
    }
    private var excludedItems: [FamilyEditing.Item] = []

    public func item(for id: ElementID) -> FamilyEditing.Item? {
        if let n = planeNames[id] { return .plane(n) }
        return items[id]
    }

    // MARK: Loading

    /// Replaces the snappable geometry.
    public func load(_ scene: FamilySnapScene) {
        self.scene = scene
        items = [:]; labels = [:]; planeIDs = [:]; planeNames = [:]; itemIDs = [:]
        var nilOwners: [String: ElementID] = [:]
        func newID() -> ElementID { defer { nextRaw += 1 }; return ElementID(nextRaw) }
        func owner(_ item: FamilyEditing.Item?, _ label: String) -> ElementID {
            if let item {
                if let id = itemIDs[item] { return id }
                let id = newID(); itemIDs[item] = id; items[id] = item; labels[id] = label
                return id
            }
            if let id = nilOwners[label] { return id }
            let id = newID(); nilOwners[label] = id; labels[id] = label
            return id
        }

        var extent = Rect2.empty
        for c in scene.curves { for p in c.points { extent.include(p) } }
        for a in scene.arcs { extent.include(a.arc.bounds) }
        let size = extent.isEmpty ? 1 : max(extent.width, extent.height)
        var index = SnapIndex()
        let cell = max(1e-3, size / 40)
        index.segGrid = SpatialGrid(cellSize: cell)
        index.arcGrid = SpatialGrid(cellSize: cell * 2)
        index.ptGrid = SpatialGrid(cellSize: cell)

        for pl in scene.planes {
            let id = newID()
            planeIDs[pl.name] = id; planeNames[id] = pl.name; labels[id] = "Reference Planes : \(pl.name)"
            let s = pl.vertical ? Segment2(Vec2(pl.value, Self.planeStart), Vec2(pl.value, Self.planeEnd))
                                : Segment2(Vec2(Self.planeStart, pl.value), Vec2(Self.planeEnd, pl.value))
            // No category: planes give no extension or end-alignment guides (their "ends" are far away).
            index.addSeg(s, id, isGrid: false)
        }

        // Edges as drawn: pieces of one item are chained (hidden-line output is one segment per piece), redundant
        // collinear vertices dropped, and tessellated arcs and circles turned back into arcs.
        var groups: [(id: ElementID, hidden: Bool, curves: [FamilySnapScene.Curve])] = []
        var groupIndex: [String: Int] = [:]
        for c in scene.curves where c.points.count >= 2 {
            let id = owner(c.item, c.label)
            let key = "\(id.raw)-\(c.hidden)"
            if let i = groupIndex[key] { groups[i].curves.append(c) } else { groupIndex[key] = groups.count; groups.append((id, c.hidden, [c])) }
        }
        for g in groups {
            for poly in Self.polylines(g.curves) {
                for piece in Self.split(poly.points, closed: poly.closed) {
                    switch piece {
                    case .segment(let s): if s.length > 1e-9 { index.addSeg(s, g.id, isGrid: false, reference: g.hidden, category: .detailLines) }
                    case .arc(let a): index.addArc(a, g.id, reference: g.hidden)
                    }
                }
            }
        }
        for a in scene.arcs {
            let id = owner(a.item, a.label)
            index.addArc(a.arc, id)
        }
        context.snapIndex = index
        context.acquiredLines = []
        exclude(excludedItems)
    }

    // MARK: Snapping

    /// The snapped point for `raw` (view coordinates). `from`: the start of the line being drawn (perpendicular, tangent,
    /// angle and length snaps). `constrainOrtho`: Shift held, the point stays horizontal or vertical from `from`.
    /// A free point (nothing to snap to, no start point) is rounded to the millimetre, as the Family Editor always did.
    public func snap(_ raw: Vec2, from: Vec2? = nil, constrainOrtho: Bool = false) -> (point: Vec2, snap: SnapResult?) {
        let (p, s) = context.snap(raw, from: from, constrainOrtho: constrainOrtho && from != nil)
        if s == nil && from == nil { return (Vec2((p.x * 1000).rounded() / 1000, (p.y * 1000).rounded() / 1000), nil) }
        return (p, s)
    }

    /// Every object snap within reach of `raw`, best first (Tab steps through them).
    public func candidates(_ raw: Vec2, from: Vec2? = nil) -> [SnapResult] {
        context.snapCandidates(raw, from: from)
    }

    /// The reference planes a snap was made to.
    public func planes(of s: SnapResult) -> [String] { s.elementIDs.compactMap { planeNames[$0] } }

    /// A snapped view point as a sketch vertex on `frame`: each coordinate that lies on a reference plane seen edge-on
    /// locks to it (so a point snapped onto a plane, or onto a crossing of two, follows the planes when they move).
    public func vertex(_ p: Vec2, frame: FamilyEditing.ViewFrame) -> FamilyEditing.SketchVertex {
        var u = p.x, v = p.y
        var up: String?, vp: String?
        var bu = 1e-6, bv = 1e-6
        for pl in scene.planes {
            if pl.vertical, abs(p.x - pl.value) <= bu { bu = abs(p.x - pl.value); u = pl.value; up = pl.name }
            if !pl.vertical, abs(p.y - pl.value) <= bv { bv = abs(p.y - pl.value); v = pl.value; vp = pl.name }
        }
        let s = frame.sketch(Vec2(u, v))
        return FamilyEditing.SketchVertex(u: s.x, v: s.y, uPlane: up, vPlane: vp)
    }

    // MARK: Typed overrides

    /// The next-pick snap overrides the Family Editor accepts by alias (Snap to Work Plane Grid has nothing to snap to
    /// in a family view, so SW is left out).
    static let overrideCommands: [CommandID] = [.snapsOff, .snapEndpoint, .snapMidpoint, .snapIntersection, .snapNearest, .snapCenter,
                                                 .snapPerpendicular, .snapTangent, .snapQuadrant, .snapPoints, .snapRemote,
                                                 .snapClose, .snapOverrideOff]
    /// Alias → override command, from the default alias table.
    public static var overrideAliases: [String: CommandID] {
        let ids = Set(overrideCommands)
        return CommandCatalog.defaultAliases.filter { ids.contains($0.value) }
    }

    /// The override a snap command sets (nil override: back to the normal snaps) and the message to show; nil when `id`
    /// isn't a snap override. Same meanings as in the project's views.
    public static func override(for id: CommandID) -> (override: ToolContext.SnapOverride?, message: String)? {
        switch id {
        case .snapsOff: (.off, "Snaps are off for the next pick.")
        case .snapEndpoint: (.only(.endpoint), "Next pick snaps to endpoint only.")
        case .snapMidpoint: (.only(.midpoint), "Next pick snaps to midpoint only.")
        case .snapIntersection: (.only(.intersection), "Next pick snaps to intersection only.")
        case .snapNearest: (.only(.nearest), "Next pick snaps to nearest only.")
        case .snapCenter: (.only(.center), "Next pick snaps to center only.")
        case .snapPerpendicular: (.only(.perpendicular), "Next pick snaps to perpendicular only.")
        case .snapTangent: (.only(.tangent), "Next pick snaps to tangent only.")
        case .snapQuadrant: (.only(.quadrant), "Next pick snaps to quadrant only.")
        case .snapPoints: (.kinds([.endpoint, .center]), "Next pick snaps to points (end and centre points) only.")
        case .snapRemote: (.remote, "Next pick snaps to objects farther from the pointer.")
        case .snapClose: (.only(.endpoint), "Next pick snaps to endpoints only; pick the loop's first point to close it.")
        case .snapOverrideOff: (nil, "Snap override off.")
        default: nil
        }
    }

    // MARK: Geometry clean-up

    /// Curves of one item as polylines: open two-point pieces that meet end to end (and nowhere else) are chained.
    static func polylines(_ curves: [FamilySnapScene.Curve]) -> [(points: [Vec2], closed: Bool)] {
        var out: [(points: [Vec2], closed: Bool)] = []
        var pieces: [Segment2] = []
        for c in curves {
            if c.points.count == 2 && !c.closed { pieces.append(Segment2(c.points[0], c.points[1])) } else { out.append((c.points, c.closed)) }
        }
        guard !pieces.isEmpty else { return out }
        // Degree-2 chaining on quantized end points (0.1 µm).
        struct Key: Hashable { var x: Int64, y: Int64 }
        func key(_ p: Vec2) -> Key { Key(x: Int64((p.x * 1e7).rounded()), y: Int64((p.y * 1e7).rounded())) }
        var at: [Key: [Int]] = [:]
        for (i, s) in pieces.enumerated() { at[key(s.start), default: []].append(i); at[key(s.end), default: []].append(i) }
        var used = [Bool](repeating: false, count: pieces.count)
        func next(from p: Vec2, after i: Int) -> (Int, Vec2)? {
            guard let list = at[key(p)], list.count == 2 else { return nil }
            let j = list[0] == i ? list[1] : list[0]
            guard j != i, !used[j] else { return nil }
            let s = pieces[j]
            return key(s.start) == key(p) ? (j, s.end) : (j, s.start)
        }
        for i in pieces.indices where !used[i] {
            used[i] = true
            var pts = [pieces[i].start, pieces[i].end]
            var last = i
            while let (j, p) = next(from: pts[pts.count - 1], after: last) { used[j] = true; pts.append(p); last = j }
            last = i
            while let (j, p) = next(from: pts[0], after: last) { used[j] = true; pts.insert(p, at: 0); last = j }
            let closed = pts.count > 3 && key(pts[0]) == key(pts[pts.count - 1])
            if closed { pts.removeLast() }
            out.append((pts, closed))
        }
        return out
    }

    enum Piece { case segment(Segment2), arc(Arc2) }

    /// A polyline as snap curves: interior vertices where the line runs straight on are dropped (an edge split by hidden-line
    /// removal snaps as one edge), and runs of short, even chords on a common circle become arcs (a full circle when the
    /// whole closed loop is one), so they snap by centre, quadrant and tangent instead of at every tessellation vertex.
    static func split(_ input: [Vec2], closed: Bool) -> [Piece] {
        var pts: [Vec2] = []
        for p in input where pts.last.map({ !$0.isAlmostEqual(p, tolerance: 1e-9) }) ?? true { pts.append(p) }
        if closed, pts.count > 1, pts[0].isAlmostEqual(pts[pts.count - 1], tolerance: 1e-9) { pts.removeLast() }
        guard pts.count >= 2 else { return [] }
        if closed, pts.count >= 12, let c = circle(pts) { return [.arc(c)] }
        pts = dropCollinear(pts, closed: closed)
        var out: [Piece] = []
        var i = 0
        let n = pts.count
        while i < n - 1 {
            if let (j, arc) = arcRun(pts, from: i) {
                out.append(.arc(arc)); i = j
            } else {
                out.append(.segment(Segment2(pts[i], pts[i + 1]))); i += 1
            }
        }
        if closed, n >= 3 { out.append(.segment(Segment2(pts[n - 1], pts[0]))) }
        return out
    }

    static func dropCollinear(_ pts: [Vec2], closed: Bool) -> [Vec2] {
        guard pts.count >= 3 else { return pts }
        var out: [Vec2] = []
        let n = pts.count
        for i in 0..<n {
            let isEnd = !closed && (i == 0 || i == n - 1)
            if !isEnd {
                let a = pts[(i + n - 1) % n], b = pts[i], c = pts[(i + 1) % n]
                let u = b - a, v = c - b
                if u.length > 0, v.length > 0, abs(u.normalized.cross(v.normalized)) < 1e-9, u.dot(v) > 0 { continue }
            }
            out.append(pts[i])
        }
        return out.count >= 2 ? out : pts
    }

    /// Whether `pts[i...j]` lie on `arc` with even chords no longer than ~50° each.
    static func onArc(_ pts: ArraySlice<Vec2>, _ c: Vec2, _ r: Double) -> Bool {
        let tol = max(1e-6, r * 2e-3)
        var lo = Double.infinity, hi = 0.0
        var prev: Vec2?
        for p in pts {
            guard abs(p.distance(to: c) - r) <= tol else { return false }
            if let q = prev { let l = q.distance(to: p); lo = min(lo, l); hi = max(hi, l) }
            prev = p
        }
        return hi <= r * 0.85 && hi <= lo * 1.35 + 1e-9
    }

    /// A closed loop that is a tessellated circle.
    static func circle(_ pts: [Vec2]) -> Arc2? {
        let n = pts.count
        guard let a = Arc2(through: pts[0], pts[n / 3], pts[2 * n / 3]), onArc(pts[...], a.center, a.radius) else { return nil }
        return Arc2(center: a.center, radius: a.radius, startAngle: 0, sweep: Angle.twoPi)
    }

    /// The longest arc of at least four chords starting at `pts[i]`, and the index it ends at.
    static func arcRun(_ pts: [Vec2], from i: Int) -> (Int, Arc2)? {
        var best: (Int, Arc2)?
        var j = i + 4
        while j < pts.count {
            guard let a = Arc2(through: pts[i], pts[(i + j) / 2], pts[j]), onArc(pts[i...j], a.center, a.radius) else { break }
            // The turn must keep one direction (a zig-zag on a circle is not an arc).
            var sign = 0.0, ok = true
            for k in (i + 1)..<j {
                let t = (pts[k] - pts[k - 1]).cross(pts[k + 1] - pts[k])
                if sign == 0 { sign = t } else if t * sign <= 0 { ok = false; break }
            }
            guard ok else { break }
            best = (j, a)
            j += 1
        }
        return best
    }
}
