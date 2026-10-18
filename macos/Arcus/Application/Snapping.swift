import Foundation
import ArcusGeometry
import ArcusDomain

public enum SnapKind: String, CaseIterable, Sendable, Codable {
    case endpoint = "Endpoint"
    case intersection = "Intersection"
    case midpoint = "Midpoint"
    case center = "Center"
    case quadrant = "Quadrant"
    case perpendicular = "Perpendicular"
    case tangent = "Tangent"
    case nearest = "Nearest"
    case gridIntersection = "Grid Intersection"
    case midBetweenPoints = "Middle of Two Points"
    case angle = "Angle"
    /// Drawing parallel (or, under Perpendicular, square) to a nearby line: a direction constraint, not a point.
    case parallel = "Parallel"
    /// On the extension of a line beyond its end (alignment guide): a line constraint.
    case `extension` = "Extension"

    public var priority: Int {
        switch self {
        case .midBetweenPoints: 0
        case .endpoint: 1
        case .gridIntersection: 2
        case .intersection: 3
        case .midpoint: 4
        case .center: 5
        case .quadrant: 6
        case .perpendicular: 7
        case .tangent: 8
        case .angle, .parallel, .extension: 9
        case .nearest: 10
        }
    }
    /// Marker shape drawn at the snap (distinct shapes; never color alone).
    public var markerShape: String {
        switch self {
        case .endpoint: "square"
        case .midpoint: "triangle"
        case .intersection, .gridIntersection: "cross"
        case .center: "circle"
        case .quadrant: "diamond"
        case .perpendicular: "perpendicular"
        case .tangent: "tangent"
        case .nearest: "hourglass"
        case .midBetweenPoints: "doubleTriangle"
        case .angle: "none"
        case .parallel: "parallel"
        case .extension: "none"
        }
    }
}

public struct SnapResult: Sendable, Hashable {
    public var point: Vec2
    public var kind: SnapKind
    public var elementIDs: [ElementID]
    /// Status text naming what was snapped to, e.g. "ENDPOINT of [Walls : Basic Wall : Generic 200mm] AND HORIZONTAL".
    public var label: String? = nil
    /// Short form for the cursor tooltip, e.g. "Endpoint", "Vertical and Extension".
    public var shortLabel: String? = nil
    /// Dashed alignment guides to draw (view units): extensions of lines, horizontal/vertical through the start point.
    public var guides: [Segment2] = []
    public var description: String { label ?? kind.rawValue }
}

public struct SnapSettings: Sendable, Hashable, Codable {
    public var enabled: Set<SnapKind> = Set(SnapKind.allCases)
    public var pixelRadius: Double = 10
    /// Angle increments for orthogonal/angle snapping (degrees). 0 = adaptive, as in RevitCraft: 45° while the
    /// rubber band is short on screen, then 15°, 5° and 1° as it grows (`SnapSettings.adaptiveIncrement`).
    public var angleIncrement: Double = 0
    public var snapsOn = true
    public init() {}

    /// RevitCraft's adaptive angle increment (snap.rs `angle_increment`) for a rubber band `pixels` long on screen.
    public static func adaptiveIncrement(pixels: Double) -> Double {
        pixels < 60 ? 45 : pixels < 220 ? 15 : pixels < 900 ? 5 : 1
    }
}

/// Snappable geometry of a view, built from the view's display list plus semantic plan geometry.
public struct SnapIndex: Sendable {
    /// `isReference`: hidden semantic geometry (wall location lines). It snaps only when nothing visible is in reach,
    /// so what the user sees (wall faces, lines) always wins over what they can't.
    struct Seg: Sendable { var s: Segment2; var id: ElementID?; var isGrid: Bool; var isReference = false; var category: Category? = nil }
    struct ArcItem: Sendable { var a: Arc2; var id: ElementID?; var isReference = false }
    struct Pt: Sendable { var p: Vec2; var id: ElementID?; var kind: SnapKind }
    var segs: [Seg] = []
    var arcs: [ArcItem] = []
    var points: [Pt] = []
    var segGrid = SpatialGrid<Int>(cellSize: 2)
    var arcGrid = SpatialGrid<Int>(cellSize: 4)
    var ptGrid = SpatialGrid<Int>(cellSize: 2)

    public init() {}

    public init(graphics: ViewGraphics, model: BIMModel, view: Element) {
        let scale = Double(max(graphics.scale, 1))
        segGrid = SpatialGrid(cellSize: max(0.5, scale / 50))
        arcGrid = SpatialGrid(cellSize: max(1, scale / 25))
        ptGrid = SpatialGrid(cellSize: max(0.5, scale / 50))
        var budget = 400_000
        for item in graphics.items where (item.selectable || item.category == .importedCAD) && !Self.nonSnappable.contains(item.category) {
            let isGrid = item.category == .grids
            for p in item.primitives {
                guard budget > 0 else { break }
                switch p {
                case .polyline(let pts, let closed, _):
                    let n = closed ? pts.count : pts.count - 1
                    guard n > 0 else { continue }
                    for i in 0..<n {
                        let s = Segment2(pts[i], pts[(i + 1) % pts.count])
                        if s.length < 1e-6 { continue }
                        addSeg(s, item.elementID, isGrid: isGrid, category: item.category)
                        budget -= 1
                    }
                case .arc(let a, _):
                    addArc(a, item.elementID)
                    budget -= 1
                case .fill, .text:
                    break
                }
            }
        }
        // Semantic plan geometry: wall location lines and centers of columns/components.
        if view.view?.kind.isPlan == true {
            for w in model.elements(.walls) where w.levelID == view.levelID {
                if case .line(let s)? = w.wall?.location { addSeg(s, w.id, isGrid: false, reference: true) }
                if case .arc(let a)? = w.wall?.location { addArc(a, w.id, reference: true) }
            }
            for c in model.elements(.columns) + model.elements(.structuralColumns) + model.elements(.furniture) + model.elements(.casework) where c.levelID == view.levelID {
                if let pl = ComponentGeometry.placement(c, model) { addPoint(pl.plan.apply(.zero), c.id, .center) }
            }
        }
    }

    /// Annotations that describe the model rather than being drawing geometry: like other BIM tools, nothing snaps to
    /// dimension lines, tags, text, spot annotations or symbols (detail lines, sections and callouts stay snappable).
    static let nonSnappable: Set<Category> = [.dimensions, .textNotes, .tags, .spotElevations, .spotCoordinates, .spotSlopes,
                                               .elevationMarks, .northArrows, .colorFillLegends, .cameras]

    mutating func addSeg(_ s: Segment2, _ id: ElementID?, isGrid: Bool, reference: Bool = false, category: Category? = nil) {
        segs.append(Seg(s: s, id: id, isGrid: isGrid, isReference: reference, category: category))
        segGrid.insert(segs.count - 1, bounds: s.bounds)
    }
    mutating func addArc(_ a: Arc2, _ id: ElementID?, reference: Bool = false) {
        arcs.append(ArcItem(a: a, id: id, isReference: reference))
        arcGrid.insert(arcs.count - 1, bounds: a.bounds)
    }
    /// Points `raw` lines up with horizontally or vertically (within `tolerance`, up to `reach` away): element centres
    /// and the ends of visible lines. The nearest per axis, so a placement can be held level with a neighbour.
    public func alignedPoints(with raw: Vec2, tolerance: Double, reach: Double, exclude: Set<ElementID> = [])
        -> [(p: Vec2, id: ElementID?, kind: SnapKind, vertical: Bool)] {
        var best: [Bool: (p: Vec2, id: ElementID?, kind: SnapKind, d: Double)] = [:]
        func consider(_ p: Vec2, _ id: ElementID?, _ kind: SnapKind) {
            if let id, exclude.contains(id) { return }
            let d = p.distance(to: raw)
            guard d > tolerance, d <= reach else { return }
            if abs(p.x - raw.x) <= tolerance, d < (best[true]?.d ?? .infinity) { best[true] = (p, id, kind, d) }
            if abs(p.y - raw.y) <= tolerance, d < (best[false]?.d ?? .infinity) { best[false] = (p, id, kind, d) }
        }
        let vertical = Rect2(min: Vec2(raw.x - tolerance, raw.y - reach), max: Vec2(raw.x + tolerance, raw.y + reach))
        let horizontal = Rect2(min: Vec2(raw.x - reach, raw.y - tolerance), max: Vec2(raw.x + reach, raw.y + tolerance))
        for box in [vertical, horizontal] {
            for i in ptGrid.query(box) { consider(points[i].p, points[i].id, points[i].kind) }
            for i in segGrid.query(box) where !segs[i].isReference && !Self.nonSnappable.contains(segs[i].category ?? .walls) {
                consider(segs[i].s.start, segs[i].id, .endpoint); consider(segs[i].s.end, segs[i].id, .endpoint)
            }
        }
        return best.map { ($0.value.p, $0.value.id, $0.value.kind, $0.key) }
    }

    mutating func addPoint(_ p: Vec2, _ id: ElementID?, _ kind: SnapKind) {
        points.append(Pt(p: p, id: id, kind: kind))
        ptGrid.insert(points.count - 1, bounds: Rect2(points: [p]))
    }

    /// Finds the best snap near `p` within `radius` (view units). `from` enables perpendicular/tangent snaps.
    /// `exclude`: elements being moved or edited, which must not snap to their own geometry.
    public func snap(_ p: Vec2, radius: Double, from: Vec2?, settings: SnapSettings, exclude: Set<ElementID> = []) -> SnapResult? {
        guard settings.snapsOn else { return nil }
        let box = Rect2(center: p, halfSize: Vec2(radius, radius))
        // Candidates on visible geometry and on hidden reference geometry are ranked separately: a reference snap is
        // used only when nothing visible is in reach.
        var cands: [SnapResult] = []
        var refCands: [SnapResult] = []
        let en = settings.enabled
        func keep(_ id: ElementID?) -> Bool { id.map { !exclude.contains($0) } ?? true }
        let nearSegs = segGrid.query(box).map { segs[$0] }.filter { keep($0.id) }
        let nearArcs = arcGrid.query(box).map { arcs[$0] }.filter { keep($0.id) }
        func consider(_ q: Vec2, _ k: SnapKind, _ ids: [ElementID?], reference: Bool = false) {
            guard en.contains(k), q.distance(to: p) <= radius else { return }
            let r = SnapResult(point: q, kind: k, elementIDs: ids.compactMap { $0 })
            if reference { refCands.append(r) } else { cands.append(r) }
        }
        for s in nearSegs {
            consider(s.s.start, .endpoint, [s.id], reference: s.isReference); consider(s.s.end, .endpoint, [s.id], reference: s.isReference)
            consider(s.s.midpoint, .midpoint, [s.id], reference: s.isReference)
            if let f = from {
                let t = s.s.parameter(of: f)
                if t >= 0 && t <= 1 { consider(s.s.point(at: t), .perpendicular, [s.id], reference: s.isReference) }
            }
        }
        for a in nearArcs {
            consider(a.a.center, .center, [a.id], reference: a.isReference)
            if !a.a.isFullCircle {
                consider(a.a.start, .endpoint, [a.id], reference: a.isReference); consider(a.a.end, .endpoint, [a.id], reference: a.isReference)
                consider(a.a.mid, .midpoint, [a.id], reference: a.isReference)
            }
            for q in SnapMath.quadrantPoints(of: a.a) { consider(q, .quadrant, [a.id], reference: a.isReference) }
            if let f = from { for q in SnapMath.tangentPoints(from: f, to: a.a) { consider(q, .tangent, [a.id], reference: a.isReference) } }
        }
        for i in ptGrid.query(box) where keep(points[i].id) { consider(points[i].p, points[i].kind, [points[i].id]) }
        // Intersections among nearby curves (bounded work).
        let local = Array(nearSegs.prefix(80))
        for i in 0..<local.count {
            for j in (i + 1)..<local.count {
                if let x = local[i].s.intersection(local[j].s) {
                    let k: SnapKind = local[i].isGrid && local[j].isGrid ? .gridIntersection : .intersection
                    consider(x, k, [local[i].id, local[j].id], reference: local[i].isReference || local[j].isReference)
                }
            }
            for a in nearArcs.prefix(20) {
                for x in Curve2.line(local[i].s).intersections(with: .arc(a.a)) {
                    consider(x, .intersection, [local[i].id, a.id], reference: local[i].isReference || a.isReference)
                }
            }
        }
        func best(_ c: [SnapResult]) -> SnapResult? {
            c.min(by: { ($0.kind.priority, $0.point.distance(to: p)) < ($1.kind.priority, $1.point.distance(to: p)) })
        }
        // Nearest point on a curve, visible curves first.
        func nearest(reference: Bool) -> SnapResult? {
            guard en.contains(.nearest) else { return nil }
            var bestNear: (Vec2, Double, ElementID?)?
            for s in nearSegs where s.isReference == reference {
                let q = s.s.closestPoint(to: p); let d = q.distance(to: p)
                if d <= radius, d < (bestNear?.1 ?? .infinity) { bestNear = (q, d, s.id) }
            }
            for a in nearArcs where a.isReference == reference {
                let q = a.a.closestPoint(to: p); let d = q.distance(to: p)
                if d <= radius, d < (bestNear?.1 ?? .infinity) { bestNear = (q, d, a.id) }
            }
            return bestNear.map { SnapResult(point: $0.0, kind: .nearest, elementIDs: [$0.2].compactMap { $0 }) }
        }
        return best(cands) ?? nearest(reference: false) ?? best(refCands) ?? nearest(reference: true)
    }

    /// Directions of visible straight lines near `points` (within `radius`), for parallel and perpendicular snapping.
    public func lineDirections(near points: [Vec2], radius: Double, exclude: Set<ElementID> = []) -> [(dir: Vec2, id: ElementID?)] {
        var out: [(dir: Vec2, id: ElementID?)] = []
        for c in points {
            let box = Rect2(center: c, halfSize: Vec2(radius, radius))
            for i in segGrid.query(box) {
                let s = segs[i]
                guard !s.isReference, s.id.map({ !exclude.contains($0) }) ?? true, s.s.length > radius * 0.05, s.s.distance(to: c) <= radius else { continue }
                let d = (s.s.end - s.s.start).normalized
                if out.contains(where: { abs($0.dir.x * d.y - $0.dir.y * d.x) < 1e-6 }) { continue }
                out.append((d, s.id))
            }
        }
        return out
    }

    /// Categories whose lines offer extension (alignment) guides: building elements and drafting lines, not the
    /// many short strokes of furniture, fixtures, hatching or annotation.
    static let extensionCategories: Set<Category> = [.walls, .detailLines, .grids, .referencePlanes, .floors, .roofs, .ceilings,
                                                     .columns, .structuralColumns, .structuralFraming, .roomSeparationLines,
                                                     .areaBoundaryLines, .propertyLines, .importedCAD, .stairs, .railings, .buildingPads]

    /// Visible straight lines whose extension beyond an end passes within `tolerance` of `p` (the pointer is past the
    /// end, not on the line), nearest first. `radius` bounds the search around `p`.
    public func extensionLines(near p: Vec2, radius: Double, tolerance: Double, minimumLength: Double,
                               exclude: Set<ElementID> = []) -> [(seg: Segment2, id: ElementID?, end: Vec2, distance: Double)] {
        let box = Rect2(center: p, halfSize: Vec2(radius, radius))
        var out: [(seg: Segment2, id: ElementID?, end: Vec2, distance: Double)] = []
        var seenLines: [(Vec2, Vec2)] = []
        for i in segGrid.query(box) {
            let s = segs[i]
            guard !s.isReference, let c = s.category, Self.extensionCategories.contains(c), s.id.map({ !exclude.contains($0) }) ?? true,
                  s.s.length >= minimumLength else { continue }
            let d = s.s.direction
            let n = Vec2(-d.y, d.x)
            let off = abs((p - s.s.start).dot(n))
            guard off <= tolerance else { continue }
            let t = (p - s.s.start).dot(d)
            let beyond = t < -tolerance ? s.s.start : t > s.s.length + tolerance ? s.s.end : nil
            guard let end = beyond else { continue }
            // Collinear lines (both faces of a wall end, a chain of lines) give one guide.
            if seenLines.contains(where: { abs($0.1.cross(d)) < 1e-6 && abs(($0.0 - s.s.start).dot(n)) < tolerance * 0.1 }) { continue }
            seenLines.append((s.s.start, d))
            out.append((s.s, s.id, end, off))
        }
        return out.sorted { $0.distance < $1.distance }
    }

    /// Visible straight lines of building elements and drafting lines within `rect` (for reference dimensions).
    public func visibleLines(in rect: Rect2, minimumLength: Double, exclude: Set<ElementID> = []) -> [(seg: Segment2, id: ElementID?)] {
        segGrid.query(rect).compactMap { i in
            let s = segs[i]
            guard !s.isReference, let c = s.category, Self.extensionCategories.contains(c), s.s.length >= minimumLength,
                  s.id.map({ !exclude.contains($0) }) ?? true else { return nil }
            return (s.s, s.id)
        }
    }

    /// Nearest snappable segment (for Pick Lines / pick axis), with its element.
    public func nearestSegment(_ p: Vec2, radius: Double, visibleOnly: Bool = false) -> (Segment2, ElementID?)? {
        let box = Rect2(center: p, halfSize: Vec2(radius, radius))
        var best: (Segment2, ElementID?, Double)?
        for i in segGrid.query(box) {
            let s = segs[i]
            if visibleOnly && s.isReference { continue }
            let d = s.s.distance(to: p)
            if d <= radius, d < (best?.2 ?? .infinity) { best = (s.s, s.id, d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Angle snap: constrains `p` relative to `from` to the nearest increment when within a few degrees.
    public static func angleSnap(_ p: Vec2, from: Vec2, increment: Double, toleranceDegrees: Double = 3) -> Vec2? {
        let v = p - from
        let len = v.length
        guard len > 1e-9 else { return nil }
        let deg = Angle.degrees(v.angle)
        let snapped = (deg / increment).rounded() * increment
        guard abs(snapped - deg) <= toleranceDegrees else { return nil }
        return from + Vec2.fromAngle(Angle.radians(snapped), length: len)
    }
}
