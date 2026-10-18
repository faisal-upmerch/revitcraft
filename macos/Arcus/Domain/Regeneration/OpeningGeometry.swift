import Foundation
import ArcusGeometry

/// Shaft openings: vertical voids that cut floors, ceilings, building pads and roofs between their base and top.
public enum ShaftCuts {
    /// Absolute bottom and top of a shaft.
    public static func range(_ shaft: Element, _ model: BIMModel) -> (bottom: Double, top: Double)? {
        guard let s = shaft.opening?.shaft else { return nil }
        if s.hosted != nil { return HostedOpenings.range(shaft, model) } // F1: a hosted opening spans its host
        let base = model.elevation(ofLevel: shaft.levelID) + s.baseOffset
        let top = model.topElevation(base: base, topLevelID: s.topLevelID, topOffset: s.topOffset, unconnectedHeight: s.unconnectedHeight)
        return (min(base, top), max(base, top))
    }

    /// The shaft's plan profile (outer boundary; inner loops leave islands uncut).
    public static func profile(_ shaft: Element) -> Profile2? {
        guard let s = shaft.opening?.shaft, case .success(let p) = s.boundary.profile() else { return nil }
        return p
    }

    /// Conservative elevation range and plan bounds of a host that shafts can cut. Roofs use their slopes'
    /// steepest rise over the footprint instead of solving the roof, so this stays cheap for cache keys.
    static func hostExtent(_ e: Element, _ model: BIMModel) -> (z0: Double, z1: Double, bounds: Rect2)? {
        switch e.data {
        case .slab:
            guard let p = SlabGeometry.profile(e), let (b, t) = SlabGeometry.planes(e, model) else { return nil }
            let pts = p.outer.points
            let lo = pts.map { b.z(at: $0) }.min() ?? 0, hi = pts.map { t.z(at: $0) }.max() ?? 0
            return (lo, hi, p.bounds)
        case .roof(let r):
            guard let fp = RoofGeometry.footprint(e) else { return nil }
            let z = RoofGeometry.baseZ(e, model)
            let slope = r.edgeSlopes.compactMap { $0 }.map { tan(min(abs($0), Angle.radians(85))) }.max() ?? 0
            let bb = fp.polygon.bounds
            let t = RoofGeometry.thickness(e, model)
            return (z - t, z + slope * max(bb.width, bb.height) / 2 + t, bb)
        default:
            return nil
        }
    }

    /// Shafts whose volume overlaps `e` (a floor, ceiling, pad or roof) by more than 1 mm vertically and whose plan
    /// bounds meet it. Sorted by id.
    public static func shafts(cutting e: Element, _ model: BIMModel) -> [Element] {
        let all = model.elements(.shaftOpenings)
        guard !all.isEmpty, e.slab != nil || e.roof != nil, let host = hostExtent(e, model) else { return [] }
        return all.filter { sh in
            if sh.opening?.shaft?.hosted != nil { return sh.hostID == e.id && profile(sh) != nil } // F1: cuts its host only
            guard sh.designOptionID == nil || sh.designOptionID == e.designOptionID else { return false }
            guard let (z0, z1) = range(sh, model), min(host.z1, z1) - max(host.z0, z0) > 0.001 else { return false }
            guard let p = profile(sh) else { return false }
            return p.bounds.intersects(host.bounds)
        }
    }

    /// Floors, ceilings, pads and roofs that a shaft cuts.
    public static func cutElements(by shaft: Element, _ model: BIMModel) -> [Element] {
        model.elements([.floors, .ceilings, .buildingPads, .roofs]).filter { shafts(cutting: $0, model).contains { $0.id == shaft.id } }
    }

    /// Plan polygons that shafts remove from `e` (used as extra holes by roofs).
    public static func externalCuts(for e: Element, _ model: BIMModel) -> [Polygon2] {
        // F1: By Face openings in roofs are cut square to the roof face by the roof mesh (HostedOpenings), not vertically.
        shafts(cutting: e, model).filter { e.roof == nil || $0.opening?.shaft?.hosted != .byFace }.compactMap { profile($0)?.outer }
    }

    /// The pieces of a slab's profile left after shafts cut it; nil when no shaft cuts it.
    public static func cutProfiles(_ e: Element, _ model: BIMModel) -> [Profile2]? {
        let cuts = externalCuts(for: e, model)
        guard !cuts.isEmpty, e.slab != nil, let p = SlabGeometry.profile(e) else { return nil }
        return PolygonBoolean.difference([p], cuts.map { Profile2(outer: $0) })
    }

    /// Slab mesh parts with shafts cut out (same layering as `SlabGeometry.meshParts`); nil when no shaft cuts it.
    public static func slabParts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart]? {
        guard let pieces = cutProfiles(e, model), let (b, t) = SlabGeometry.planes(e, model) else { return nil }
        guard detail == .fine, let a = model.typeData(of: e)?.assembly, a.layers.count > 1 else {
            var mesh = Mesh()
            for p in pieces { mesh.append(MeshBuilder.slab(p, bottom: b, top: t)) }
            return [MeshPart(mesh: mesh, materialID: SlabGeometry.surfaceMaterial(e, model))]
        }
        var parts: [MeshPart] = []
        var acc = 0.0
        for layer in a.layers where layer.thickness > Tolerance.length {
            let top = PlaneZ(a: t.a, b: t.b, c: t.c - acc)
            acc += layer.thickness
            let bot = PlaneZ(a: t.a, b: t.b, c: t.c - acc)
            var mesh = Mesh()
            for p in pieces { mesh.append(MeshBuilder.slab(p, bottom: bot, top: top)) }
            parts.append(MeshPart(mesh: mesh, materialID: layer.materialID))
        }
        return parts
    }

    /// Plan area of a slab after shaft cuts; nil when no shaft cuts it.
    public static func remainingArea(_ e: Element, _ model: BIMModel) -> Double? {
        cutProfiles(e, model).map { $0.reduce(0) { $0 + $1.area } }
    }

    /// A single plan profile for drawing a cut slab. When the shafts split the slab into several pieces, the result
    /// keeps the original outline with the cut regions as holes (drawn even-odd).
    public static func planProfile(_ e: Element, _ model: BIMModel) -> Profile2? {
        guard let p = SlabGeometry.profile(e) else { return nil }
        guard let pieces = cutProfiles(e, model) else { return p }
        if pieces.count == 1 { return pieces[0] }
        if pieces.isEmpty { return nil }
        let removed = PolygonBoolean.difference([p], pieces).map(\.outer)
        return Profile2(outer: p.outer, holes: p.holes + removed)
    }
}

public enum WallOpeningGeometry {
    /// Station range and absolute elevations of a wall opening, clamped to its host.
    public static func extents(_ e: Element, _ model: BIMModel) -> (s0: Double, s1: Double, z0: Double, z1: Double, host: WallFrame)? {
        guard let host = model[e.hostID], let f = WallGeometry.frame(host, model),
              let op = WallGeometry.openings(host, model).first(where: { $0.insertID == e.id }) else { return nil }
        return (op.s0, op.s1, op.z0, op.z1, f)
    }

    /// Plan rectangle of a wall opening across its host's thickness (straight hosts), or its outline along a curved host.
    public static func planOutline(_ e: Element, _ model: BIMModel) -> Polygon2? {
        guard let x = extents(e, model) else { return nil }
        let f = x.host
        let L = f.length
        let steps = f.isStraight ? 1 : max(2, Int((x.s1 - x.s0) / 0.1))
        var left: [Vec2] = [], right: [Vec2] = []
        for i in 0...steps {
            let s = x.s0 + (x.s1 - x.s0) * Double(i) / Double(steps)
            let t = L > 0 ? s / L : 0
            let p = f.location.point(at: t), n = f.location.normal(at: t)
            left.append(p + n * f.leftOffset); right.append(p + n * f.rightOffset)
        }
        let poly = Polygon2(right + left.reversed())
        return poly.isDegenerate ? nil : poly.counterClockwise
    }
}

extension CurtainWallGeometry {
    /// Curtain walls whose type or overrides use a panel type.
    public static func walls(usingPanelType id: ElementID, _ model: BIMModel) -> [Element] {
        model.elements(.walls).filter { w in
            guard let c = model.typeData(of: w)?.curtain else { return false }
            return c.panelTypeID == id || (w.wall?.curtain?.panels.contains { $0.typeID == id } ?? false)
        }
    }
}
