import Foundation

/// Boolean operations on profiles (simple polygons with holes).
///
/// Implemented on `PlanarArrangement`: all loop edges are arranged, every face is
/// classified by testing an interior sample point against the operands, and the
/// edges separating kept from discarded faces are re-arranged into result profiles.
/// Operands may overlap themselves (a list is treated as the union of its members).
public enum PolygonBoolean {
    /// Union of all profiles.
    public static func union(_ a: [Profile2]) -> [Profile2] {
        let sa = ProfileSet(a)
        return resolve(segments: sa.segments) { sa.contains($0) }
    }

    /// Region inside both `a` and `b`.
    public static func intersection(_ a: [Profile2], _ b: [Profile2]) -> [Profile2] {
        let sa = ProfileSet(a), sb = ProfileSet(b)
        guard sa.bounds.intersects(sb.bounds) else { return [] }
        return resolve(segments: sa.segments + sb.segments) { sa.contains($0) && sb.contains($0) }
    }

    /// Region inside `a` but not inside `b`.
    public static func difference(_ a: [Profile2], _ b: [Profile2]) -> [Profile2] {
        let sa = ProfileSet(a), sb = ProfileSet(b)
        guard sa.bounds.intersects(sb.bounds) else { return union(a) }
        return resolve(segments: sa.segments + sb.segments) { sa.contains($0) && !sb.contains($0) }
    }

    /// Profiles with grid-accelerated containment.
    struct ProfileSet {
        let profiles: [Profile2]
        let grid: SpatialGrid<Int>
        let bounds: Rect2

        init(_ profiles: [Profile2]) {
            let valid = profiles.filter { $0.outer.count >= 3 && !$0.outer.isDegenerate }
            self.profiles = valid
            var extent = Rect2.empty
            for p in valid { extent.include(p.bounds) }
            bounds = extent
            var g = SpatialGrid<Int>(cellSize: SpatialGrid<Int>.suggestedCellSize(
                extent: extent, count: max(1, valid.count),
                meanItemSize: max(extent.width, extent.height) / max(1, Double(valid.count).squareRoot())))
            for (i, p) in valid.enumerated() { g.insert(i, bounds: p.bounds) }
            grid = g
        }

        var segments: [Segment2] {
            profiles.flatMap { $0.loops.flatMap { $0.edges } }
        }

        func contains(_ p: Vec2) -> Bool {
            grid.query(point: p, radius: 0).contains { profiles[$0].contains(p) }
        }
    }

    /// Builds the region `{p : keep(p)}` whose boundary lies on `segments`.
    static func resolve(segments: [Segment2], keep: (Vec2) -> Bool) -> [Profile2] {
        guard !segments.isEmpty else { return [] }
        let arr = PlanarArrangement(segments: segments)
        let kept: [Bool] = arr.faces.map { f in f.interiorPoint().map(keep) ?? false }
        var boundary: [Segment2] = []
        let verts = arr.vertices
        for (e, ev) in arr.edgeVertices.enumerated() {
            let fl = arr.halfEdgeFace[2 * e], fr = arr.halfEdgeFace[2 * e + 1]
            guard fl != -2 else { continue }
            let kl = fl >= 0 && kept[fl], kr = fr >= 0 && kept[fr]
            if kl != kr {
                boundary.append(kl ? Segment2(verts[ev.a], verts[ev.b]) : Segment2(verts[ev.b], verts[ev.a]))
            }
        }
        guard !boundary.isEmpty else { return [] }
        let merged = PlanarArrangement(segments: boundary)
        var out: [Profile2] = []
        for f in merged.faces {
            guard let s = f.interiorPoint(), keep(s) else { continue }
            let outer = f.outer.simplified()
            let holes = f.holes.map { $0.simplified() }.filter { !$0.isDegenerate }
            guard !outer.isDegenerate else { continue }
            out.append(Profile2(outer: outer, holes: holes))
        }
        return out
    }
}

// MARK: - Clipping to rectangles

extension Polygon2 {
    /// Sutherland–Hodgman clip against an axis-aligned rectangle. Nil if nothing
    /// (or only a degenerate sliver) remains.
    public func clipped(to rect: Rect2) -> Polygon2? {
        guard !rect.isEmpty, points.count >= 3 else { return nil }
        var pts = points
        // Each boundary: inside test and intersection along x or y.
        let planes: [(axis: Int, value: Double, keepGreater: Bool)] = [
            (0, rect.min.x, true), (0, rect.max.x, false), (1, rect.min.y, true), (1, rect.max.y, false),
        ]
        for pl in planes {
            guard !pts.isEmpty else { break }
            func coord(_ p: Vec2) -> Double { pl.axis == 0 ? p.x : p.y }
            func inside(_ p: Vec2) -> Bool { pl.keepGreater ? coord(p) >= pl.value : coord(p) <= pl.value }
            var out: [Vec2] = []
            out.reserveCapacity(pts.count + 4)
            var prev = pts[pts.count - 1]
            for cur in pts {
                let ci = inside(cur), pi = inside(prev)
                if ci != pi {
                    let t = (pl.value - coord(prev)) / (coord(cur) - coord(prev))
                    var q = prev.lerp(to: cur, t: t)
                    if pl.axis == 0 { q.x = pl.value } else { q.y = pl.value }
                    out.append(q)
                }
                if ci { out.append(cur) }
                prev = cur
            }
            pts = out
        }
        let r = Polygon2(pts).simplified()
        return r.count >= 3 && !r.isDegenerate ? r : nil
    }
}

extension Segment2 {
    /// Liang–Barsky clip against an axis-aligned rectangle. Nil if the segment misses it.
    public func clipped(to rect: Rect2) -> Segment2? {
        guard !rect.isEmpty else { return nil }
        let d = vector
        var t0 = 0.0, t1 = 1.0
        let checks: [(Double, Double)] = [
            (-d.x, start.x - rect.min.x), (d.x, rect.max.x - start.x),
            (-d.y, start.y - rect.min.y), (d.y, rect.max.y - start.y),
        ]
        for (p, q) in checks {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let r = q / p
                if p < 0 { if r > t1 { return nil }; if r > t0 { t0 = r } } else { if r < t0 { return nil }; if r < t1 { t1 = r } }
            }
        }
        return Segment2(point(at: t0), point(at: t1))
    }
}
