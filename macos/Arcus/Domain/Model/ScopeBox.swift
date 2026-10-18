import Foundation
import ArcusGeometry

/// A scope box: a named, possibly rotated plan rectangle with a height range. Levels, grids and reference planes
/// assigned to it appear only in views that intersect it (and are trimmed to it); plan views assigned to it crop to it.
public struct ScopeBoxData: Hashable, Codable, Sendable {
    /// Plan centre of the box.
    public var center: Vec2
    /// Half the width (along the box's local x axis) and half the depth (local y).
    public var halfSize: Vec2
    /// Rotation of the local x axis from project east (radians, counter-clockwise).
    public var rotation: Double
    /// Absolute elevations of the bottom and top faces.
    public var bottomElevation: Double
    public var topElevation: Double

    public init(center: Vec2, halfSize: Vec2, rotation: Double = 0, bottomElevation: Double, topElevation: Double) {
        self.center = center; self.halfSize = Vec2(abs(halfSize.x), abs(halfSize.y)); self.rotation = rotation
        self.bottomElevation = min(bottomElevation, topElevation); self.topElevation = max(bottomElevation, topElevation)
    }

    /// An axis-aligned box spanning a plan rectangle.
    public init(rect: Rect2, bottomElevation: Double, topElevation: Double) {
        self.init(center: rect.center, halfSize: rect.size * 0.5, bottomElevation: bottomElevation, topElevation: topElevation)
    }

    public var xAxis: Vec2 { Vec2.fromAngle(rotation) }
    public var yAxis: Vec2 { xAxis.perpendicular }
    public var width: Double { halfSize.x * 2 }
    public var depth: Double { halfSize.y * 2 }

    /// Corners counter-clockwise, starting at the local (−x, −y) corner.
    public var corners: [Vec2] {
        let x = xAxis * halfSize.x, y = yAxis * halfSize.y
        return [center - x - y, center + x - y, center + x + y, center - x + y]
    }
    public var polygon: Polygon2 { Polygon2(corners) }
    /// Axis-aligned plan bounds.
    public var bounds: Rect2 { Rect2(points: corners) }

    /// Plan point in the box's local frame (origin at the centre).
    public func local(_ p: Vec2) -> Vec2 { let d = p - center; return Vec2(d.dot(xAxis), d.dot(yAxis)) }
    public func world(_ l: Vec2) -> Vec2 { center + xAxis * l.x + yAxis * l.y }

    public func contains(_ p: Vec2, tolerance: Double = 1e-9) -> Bool {
        let l = local(p)
        return abs(l.x) <= halfSize.x + tolerance && abs(l.y) <= halfSize.y + tolerance
    }

    public func containsElevation(_ z: Double, tolerance: Double = 1e-6) -> Bool {
        z >= bottomElevation - tolerance && z <= topElevation + tolerance
    }

    /// The part of a segment inside the box (Liang–Barsky in the box frame), or nil when it misses the box.
    public func clip(_ s: Segment2) -> Segment2? {
        let a = local(s.start), b = local(s.end)
        let d = b - a
        var t0 = 0.0, t1 = 1.0
        for (p, q) in [(-d.x, a.x + halfSize.x), (d.x, halfSize.x - a.x), (-d.y, a.y + halfSize.y), (d.y, halfSize.y - a.y)] {
            if abs(p) < 1e-15 {
                if q < -1e-9 { return nil }
                continue
            }
            let r = q / p
            if p < 0 { t0 = max(t0, r) } else { t1 = min(t1, r) }
            if t0 > t1 + 1e-12 { return nil }
        }
        let c = Segment2(world(a + d * t0), world(a + d * t1))
        return c.length > 1e-9 ? c : nil
    }

    /// Whether the box overlaps an axis-aligned rectangle (separating-axis test).
    public func intersects(_ r: Rect2) -> Bool {
        guard !r.isEmpty else { return false }
        guard bounds.intersects(r) else { return false }
        // Project the rectangle onto the box axes.
        for axis in [xAxis, yAxis] {
            let ext = axis == xAxis ? halfSize.x : halfSize.y
            let c = center.dot(axis)
            let ps = r.corners.map { $0.dot(axis) }
            if (ps.max() ?? 0) < c - ext - 1e-9 || (ps.min() ?? 0) > c + ext + 1e-9 { return false }
        }
        return true
    }

    /// Range of the box projected onto a line direction through `origin` (for elevations and sections).
    public func projectedRange(origin: Vec2, direction: Vec2) -> ClosedRange<Double> {
        let us = corners.map { ($0 - origin).dot(direction) }
        return (us.min() ?? 0)...(us.max() ?? 0)
    }

    /// Plan transform (move, rotate, mirror). The box stays a rectangle, so a mirror only moves and turns it.
    public func transformed(_ t: Transform2) -> ScopeBoxData {
        var b = self
        b.center = t.apply(center)
        b.rotation = t.applyVector(xAxis).angle
        return b
    }
}

extension Element {
    public var scopeBox: ScopeBoxData? {
        get { if case .scopeBox(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .scopeBox(v) } }
    }

    /// The scope box a datum (level, grid or reference plane) is assigned to.
    public var datumScopeBoxID: ElementID? {
        switch data {
        case .level(let l): l.scopeBoxID
        case .grid(let g): g.scopeBoxID
        case .referencePlane(let r): r.scopeBoxID
        default: nil
        }
    }
}

/// How scope boxes limit datums and crop views.
public enum ScopeBoxes {
    public static func box(_ id: ElementID?, _ model: BIMModel) -> ScopeBoxData? { model[id]?.scopeBox }

    /// Unique default name ("Scope Box 1", "Scope Box 2", …).
    public static func nextName(_ model: BIMModel) -> String {
        let names = Set(model.elements(.scopeBoxes).map(\.name))
        var n = model.elements(.scopeBoxes).count + 1
        while names.contains("Scope Box \(n)") { n += 1 }
        return "Scope Box \(n)"
    }

    /// Default vertical extent for a new scope box: from just below the lowest level to well above the highest.
    public static func defaultElevations(_ model: BIMModel) -> (Double, Double) {
        let zs = model.levels.compactMap { $0.level?.elevation }
        return ((zs.min() ?? 0) - 1, (zs.max() ?? 0) + 4)
    }

    /// Clears references to deleted scope boxes. Views keep the deleted box's extent as an ordinary crop.
    static func repairDanglingReferences(_ tx: TransactionContext) {
        let m = tx.model
        guard tx.originalModel.elements(.scopeBoxes).contains(where: { m[$0.id] == nil }) else { return }
        for e in m.levels + m.elements(.grids) + m.elements(.referencePlanes) {
            guard let id = e.datumScopeBoxID, m[id] == nil else { continue }
            tx.propagate(e.id) { el in
                switch el.data {
                case .level(var l): l.scopeBoxID = nil; el.data = .level(l)
                case .grid(var g): g.scopeBoxID = nil; el.data = .grid(g)
                case .referencePlane(var r): r.scopeBoxID = nil; el.data = .referencePlane(r)
                default: break
                }
            }
        }
        for v in m.views {
            guard let id = v.view?.scopeBoxID, m[id] == nil else { continue }
            let last = tx.originalModel[id]?.scopeBox?.bounds
            tx.propagate(v.id) { el in
                el.view?.scopeBoxID = nil
                if let last { el.view?.cropRegion = last }
            }
        }
    }

    /// Plan views assigned to a scope box crop to its plan bounds.
    public static func applyViewCrop(_ d: inout ViewData, _ model: BIMModel) {
        guard d.kind.isPlan, let b = box(d.scopeBoxID, model) else { return }
        d.cropRegion = b.bounds
        d.cropActive = true
    }

    /// Whether a plan view sees a scope box: its cut plane lies inside the box's height range and, when the view is
    /// cropped, the crop overlaps the box.
    static func planSees(_ b: ScopeBoxData, builder: ViewGraphicsBuilder) -> Bool {
        let cutZ = builder.model.elevation(ofLevel: builder.view.levelID) + builder.data.viewRange.cutOffset
        guard b.containsElevation(cutZ) else { return false }
        if builder.data.cropActive, let crop = builder.data.cropRegion { return b.intersects(crop) }
        return true
    }

    /// Plan: limits a grid to its scope box. Returns false when the grid is hidden in this view.
    static func limitPlan(_ gd: inout GridData, builder: ViewGraphicsBuilder) -> Bool {
        guard let id = gd.scopeBoxID else { return true }
        guard let b = box(id, builder.model) else { return true }
        guard planSees(b, builder: builder) else { return false }
        switch gd.curve {
        case .line(let s):
            guard let c = b.clip(s) else { return false }
            gd.curve = .line(c)
            return true
        case .arc(let a):
            return b.intersects(a.bounds)
        }
    }

    /// Plan: limits a reference plane to its scope box. Returns false when it is hidden in this view.
    static func limitPlan(_ rp: inout ReferencePlaneData, builder: ViewGraphicsBuilder) -> Bool {
        guard let id = rp.scopeBoxID, let b = box(id, builder.model) else { return true }
        guard planSees(b, builder: builder), let c = b.clip(rp.line) else { return false }
        rp.line = c
        return true
    }

    /// Elevations and sections: whether the view sees the box (its slab from the view plane to the far clip, and
    /// the crop if any, overlap the box) and the box's range along the view.
    static func verticalRange(_ b: ScopeBoxData, origin: Vec2, right: Vec2, forward: Vec2, builder: ViewGraphicsBuilder) -> ClosedRange<Double>? {
        let depth = b.projectedRange(origin: origin, direction: forward)
        guard depth.upperBound >= -0.001, depth.lowerBound <= builder.data.farClip else { return nil }
        let u = b.projectedRange(origin: origin, direction: right)
        if builder.data.cropActive, let crop = builder.data.cropRegion {
            guard u.upperBound >= crop.min.x, u.lowerBound <= crop.max.x,
                  b.topElevation >= crop.min.y, b.bottomElevation <= crop.max.y else { return nil }
        }
        return u
    }

    /// Vertical views: the horizontal extent of a level line, limited to its scope box; nil when hidden.
    static func levelExtent(_ l: Element, from u0: Double, to u1: Double, origin: Vec2, right: Vec2, forward: Vec2,
                            builder: ViewGraphicsBuilder) -> (Double, Double)? {
        guard let b = box(l.level?.scopeBoxID, builder.model) else { return (u0, u1) }
        guard let u = verticalRange(b, origin: origin, right: right, forward: forward, builder: builder) else { return nil }
        let lo = max(u0, u.lowerBound), hi = min(u1, u.upperBound)
        return hi > lo ? (lo, hi) : nil
    }

    /// Vertical views: the vertical extent of a grid line, limited to its scope box; nil when hidden.
    static func gridExtent(_ g: Element, z0: Double, z1: Double, origin: Vec2, right: Vec2, forward: Vec2,
                           builder: ViewGraphicsBuilder) -> (Double, Double)? {
        guard let b = box(g.grid?.scopeBoxID, builder.model) else { return (z0, z1) }
        guard verticalRange(b, origin: origin, right: right, forward: forward, builder: builder) != nil else { return nil }
        let lo = max(z0, b.bottomElevation), hi = min(z1, b.topElevation)
        return hi > lo ? (lo, hi) : nil
    }

    /// Scope boxes drawn in a plan view (dash-dot outline with the name), where the cut plane passes through them.
    static func planItems(builder: ViewGraphicsBuilder) -> [GItem] {
        var items: [GItem] = []
        for e in builder.model.elements(.scopeBoxes) {
            guard let b = e.scopeBox, let o = builder.resolver.resolve(e) else { continue }
            let cutZ = builder.model.elevation(ofLevel: builder.view.levelID) + builder.data.viewRange.cutOffset
            guard b.containsElevation(cutZ) else { continue }
            var st = builder.stroke(.scopeBoxes, cut: false, o)
            if o.projectionLinePattern == nil { st.pattern = .dashDot }
            if o.projectionLineColor == nil { st.color = RGBColor(0.42, 0.33, 0.66) }
            let corners = b.corners
            let label = GText(position: corners[3] + b.xAxis * builder.paper(0.002) - b.yAxis * builder.paper(0.004), height: 0.0022,
                              string: e.name, rotation: textAngle(b.rotation), color: st.color, halftone: st.halftone)
            items.append(GItem(elementID: e.id, category: .scopeBoxes, layer: .annotation,
                               primitives: [.polyline(corners, closed: true, st), .text(label)]))
        }
        return items
    }

    /// Keeps text readable (never upside down).
    static func textAngle(_ a: Double) -> Double {
        var r = Angle.normalize(a)
        if r > .pi / 2 + 1e-6 && r <= 3 * .pi / 2 + 1e-6 { r -= .pi }
        return r
    }
}
