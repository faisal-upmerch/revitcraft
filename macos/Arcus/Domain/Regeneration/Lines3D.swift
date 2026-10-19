import Foundation
import ArcusGeometry

// S3D2: what a 3D view draws as lines (Revit shows datums and 2D CAD in 3D views): grids as the outline of their
// vertical extent, levels as a rectangle at their elevation over the model, reference planes as their outline and
// centre line, model lines (on their level or work plane), and the linework of 2D CAD links and imports at the
// elevation of the level or view they belong to. Each follows the 3D view's visibility (categories, hidden elements,
// filters, temporary hide/isolate, Show Links and hidden link layers). The viewport draws them as edges, and 3D
// snapping indexes them like model geometry.

public enum Lines3D {
    /// One element's lines: a mesh with feature edges and no faces.
    public struct Item: Sendable {
        public var id: ElementID
        public var category: Category
        public var mesh: Mesh
        public var color: RGBColor
    }

    /// Segments each CAD link contributes at most (huge drawings are drawn partially rather than stalling the build).
    static let maxCADSegments = 200_000

    /// The line elements `view` shows.
    public static func items(model: BIMModel, view: Element, resolver: VisibilityResolver) -> [Item] {
        var out: [Item] = []
        let box = extentBox(model)
        func add(_ e: Element, _ segs: [Segment3], _ color: RGBColor) {
            let m = mesh(segs)
            if !m.featureEdges.isEmpty { out.append(Item(id: e.id, category: e.category, mesh: m, color: color)) }
        }
        for e in model.elements(.grids) where resolver.resolve(e) != nil {
            if let g = e.grid { add(e, gridOutline(g, model), RGBColor(0.32, 0.32, 0.34)) }
        }
        for e in model.levels where resolver.resolve(e) != nil {
            if let l = e.level { add(e, levelOutline(l.elevation, box), RGBColor(0.18, 0.42, 0.72)) }
        }
        for e in model.elements(.referencePlanes) where e.ownerViewID == nil && resolver.resolve(e) != nil {
            if let r = e.referencePlane { add(e, referencePlaneLines(r, box), RGBColor(0.15, 0.55, 0.3)) }
        }
        for e in model.elements(.detailLines) where e.ownerViewID == nil && resolver.resolve(e) != nil {
            guard let l = e.modelLine else { continue }
            let pts = l.worldPolyline(baseZ: model.elevation(ofLevel: e.levelID))
            let color = model[l.styleID]?.lineStyle?.color ?? RGBColor(0.1, 0.1, 0.1)
            add(e, zip(pts, pts.dropFirst()).map { Segment3($0, $1) }, color)
        }
        if resolver.vg.showLinks {
            for e in model.elements(.importedCAD) where resolver.resolve(e) != nil {
                if let owner = e.ownerViewID, owner != view.id, model[owner]?.view?.kind.isPlan != true { continue }
                if let segs = cadLines(e, model, resolver: resolver) { add(e, segs, RGBColor(0.36, 0.36, 0.4)) }
            }
        }
        return out
    }

    /// A mesh of line segments only (normals filled so the viewport can upload it like any mesh).
    static func mesh(_ segs: [Segment3]) -> Mesh {
        var m = Mesh()
        for s in segs where s.length > Tolerance.length {
            let k = UInt32(m.positions.count)
            m.positions += [s.a, s.b]
            m.normals += [.unitZ, .unitZ]
            m.featureEdges += [k, k + 1]
        }
        return m
    }

    /// The model's extents with a margin: how far levels and vertical reference planes reach in 3D.
    public static func extentBox(_ model: BIMModel) -> Box3 {
        let b = WorkPlanes.modelBounds(model)
        return Box3(min: b.min - Vec3(2, 2, 1), max: b.max + Vec3(2, 2, 1))
    }

    /// Elevations a grid spans in 3D: its own extents, else the lowest to the highest level.
    public static func gridRange(_ g: GridData, _ model: BIMModel) -> ClosedRange<Double> {
        let zs = model.levels.compactMap { $0.level?.elevation }
        var lo = g.bottomElevation ?? zs.min() ?? 0
        var hi = g.topElevation ?? zs.max() ?? 3
        if hi < lo { swap(&lo, &hi) }
        if hi - lo < 1 { hi = lo + 3 }
        return lo...hi
    }

    /// A grid's plan path (arcs flattened).
    public static func gridPath(_ g: GridData) -> [Vec2] {
        if g.isMultiSegment { return g.polyline }
        switch g.curve {
        case .line(let s): return [s.start, s.end]
        case .arc(let a): return a.tessellate(chordTolerance: 0.003)
        }
    }

    /// The grid's path at its bottom and top elevations and the verticals at its ends and bends.
    static func gridOutline(_ g: GridData, _ model: BIMModel) -> [Segment3] {
        let r = gridRange(g, model)
        let path = gridPath(g)
        guard path.count >= 2 else { return [] }
        var segs: [Segment3] = []
        for z in [r.lowerBound, r.upperBound] { segs += zip(path, path.dropFirst()).map { Segment3(Vec3($0, z: z), Vec3($1, z: z)) } }
        let verticals = g.isMultiSegment ? path : [path[0], path[path.count - 1]]
        segs += verticals.map { Segment3(Vec3($0, z: r.lowerBound), Vec3($0, z: r.upperBound)) }
        return segs
    }

    static func levelOutline(_ z: Double, _ box: Box3) -> [Segment3] {
        let c = [Vec2(box.min.x, box.min.y), Vec2(box.max.x, box.min.y), Vec2(box.max.x, box.max.y), Vec2(box.min.x, box.max.y)].map { Vec3($0, z: z) }
        return (0..<4).map { Segment3(c[$0], c[($0 + 1) % 4]) }
    }

    /// Outline and centre line of a reference plane: a vertical one over the model's height, with its vertical centre
    /// line; one drawn on another work plane as drawn, with the line it was drawn along.
    static func referencePlaneLines(_ r: ReferencePlaneData, _ box: Box3) -> [Segment3] {
        if let p = r.plane3D {
            let h = max(p.start.distance(to: p.end) / 2, 1)
            let e = p.extrusion.normalized * h
            let c = [p.start - e, p.end - e, p.end + e, p.start + e]
            return (0..<4).map { Segment3(c[$0], c[($0 + 1) % 4]) } + [Segment3(p.start, p.end)]
        }
        let a = r.line.start, b = r.line.end, z0 = box.min.z, z1 = box.max.z
        let c = [Vec3(a, z: z0), Vec3(b, z: z0), Vec3(b, z: z1), Vec3(a, z: z1)]
        let m = r.line.midpoint
        return (0..<4).map { Segment3(c[$0], c[($0 + 1) % 4]) } + [Segment3(Vec3(m, z: z0), Vec3(m, z: z1))]
    }

    /// Elevation a CAD link or import is drawn at: its level (or its plan view's level) plus its offset.
    public static func cadElevation(_ e: Element, _ model: BIMModel) -> Double {
        let level = e.levelID ?? e.ownerViewID.flatMap { model[$0]?.levelID }
        return model.elevation(ofLevel: level) + (e.link?.elevationOffset ?? 0)
    }

    /// The visible linework of a 2D CAD link or import (layers that are off, frozen or hidden in the view are left out).
    static func cadLines(_ e: Element, _ model: BIMModel, resolver: VisibilityResolver) -> [Segment3]? {
        guard let ld = e.link, ld.isLoaded, let d = model.referenceDrawings[ld.contentKey] else { return nil }
        let hidden = Set(ld.layers.filter { !$0.visible }.map(\.name)).union(resolver.vg.hiddenLinkLayers[e.id] ?? [])
        let z = cadElevation(e, model)
        var segs: [Segment3] = []
        func line(_ p: [Vec2], closed: Bool) {
            guard p.count >= 2 else { return }
            for k in 0..<(closed ? p.count : p.count - 1) { segs.append(Segment3(Vec3(p[k], z: z), Vec3(p[(k + 1) % p.count], z: z))) }
        }
        for ent in d.flattened() {
            if segs.count >= maxCADSegments { break }
            let s = ent.style
            if s.layer >= 0, s.layer < d.layers.count {
                let layer = d.layers[s.layer]
                if hidden.contains(layer.name) || !layer.isOn || layer.isFrozen { continue }
            }
            switch ent.transformed(ld.placement) {
            case .line(let l, _): line([l.start, l.end], closed: false)
            case .polyline(let p, let c, _): line(p, closed: c)
            case .arc(let a, _): line(a.tessellate(chordTolerance: 0.003), closed: false)
            case .face3D(let pts, _):
                for k in 0..<pts.count { segs.append(Segment3(pts[k] + Vec3(0, 0, z), pts[(k + 1) % pts.count] + Vec3(0, 0, z))) }
            default: break
            }
        }
        return segs
    }

    // MARK: Traces on a work plane

    /// Where vertical datums cross a work plane (horizontal or vertical): grids, levels and reference planes, as lines
    /// lying in the plane. Sloped planes and sloped reference planes are left out.
    public static func traces(on f: WorkPlaneFrame, model: BIMModel, visible: (Element) -> Bool = { _ in true }) -> [(segment: Segment3, id: ElementID, category: Category)] {
        var out: [(segment: Segment3, id: ElementID, category: Category)] = []
        let box = extentBox(model)
        if f.isHorizontal {
            let z = f.origin.z
            for e in model.elements(.grids) where visible(e) {
                guard let g = e.grid, gridRange(g, model).contains(z) else { continue }
                let p = gridPath(g)
                out += zip(p, p.dropFirst()).map { (Segment3(Vec3($0, z: z), Vec3($1, z: z)), e.id, .grids) }
            }
            for e in model.elements(.referencePlanes) where e.ownerViewID == nil && visible(e) {
                guard let r = e.referencePlane, r.plane3D == nil, z >= box.min.z, z <= box.max.z else { continue }
                out.append((Segment3(Vec3(r.line.start, z: z), Vec3(r.line.end, z: z)), e.id, .referencePlanes))
            }
            return out
        }
        guard abs(f.normal.z) < 1e-6 else { return out }
        // A vertical plane: its plan trace.
        let o = f.origin.xy, d = f.u.xy.normalized
        func crossing(_ a: Vec2, _ b: Vec2) -> Vec2? {
            let e = b - a
            let den = d.cross(e)
            guard abs(den) > 1e-12 else { return nil }
            let s = (a - o).cross(d) / den
            guard s >= -1e-9, s <= 1 + 1e-9 else { return nil }
            return a + e * s
        }
        for e in model.elements(.grids) where visible(e) {
            guard let g = e.grid else { continue }
            let r = gridRange(g, model), p = gridPath(g)
            for (a, b) in zip(p, p.dropFirst()) {
                if let x = crossing(a, b) { out.append((Segment3(Vec3(x, z: r.lowerBound), Vec3(x, z: r.upperBound)), e.id, .grids)) }
            }
        }
        for e in model.elements(.referencePlanes) where e.ownerViewID == nil && visible(e) {
            guard let r = e.referencePlane, r.plane3D == nil else { continue }
            // Its whole plan line meets the plane's trace in one point (or runs in it: nothing to trace).
            let e2 = r.line.end - r.line.start
            let den = d.cross(e2)
            guard abs(den) > 1e-12 else { continue }
            let s = (r.line.start - o).cross(d) / den
            let x = r.line.start + e2 * s
            out.append((Segment3(Vec3(x, z: box.min.z), Vec3(x, z: box.max.z)), e.id, .referencePlanes))
        }
        // Levels: horizontal lines across the plane over the model's extent.
        var lo = Double.infinity, hi = -Double.infinity
        for c in box.corners { let t = (c.xy - o).dot(d); lo = min(lo, t); hi = max(hi, t) }
        for e in model.levels where visible(e) {
            guard let l = e.level else { continue }
            out.append((Segment3(Vec3(o + d * lo, z: l.elevation), Vec3(o + d * hi, z: l.elevation)), e.id, .levels))
        }
        return out
    }
}
