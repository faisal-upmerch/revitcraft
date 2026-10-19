import Foundation
import ArcusGeometry

/// Derived quantities of an element (SI). nil = not applicable.
public struct ElementQuantities: Sendable, Hashable {
    public var length: Double?
    public var area: Double?
    public var volume: Double?
    public var perimeter: Double?
    public var height: Double?
    public var width: Double?
    public var thickness: Double?
    public var elevationTop: Double?
    public var elevationBottom: Double?
    /// Material quantities: material id (nil = <By Category>) → (area, volume).
    public var materials: [MaterialQuantity]
    public init() { materials = [] }

    func value(_ f: (ElementQuantities) -> Double?) -> ParamValue? { f(self).map { .double($0) } }
}

public struct MaterialQuantity: Sendable, Hashable {
    public var materialID: ElementID?
    public var area: Double
    public var volume: Double
}

public enum QuantityEngine {
    public static func quantities(for e: Element, in model: BIMModel) -> ElementQuantities {
        var q = ElementQuantities()
        switch e.data {
        case .wall:
            if let curtain = CurtainWallGeometry.quantities(e, model) { return curtain } // WP3
            guard let f = WallGeometry.frame(e, model) else { return q }
            let ops = WallGeometry.openings(e, model)
            let openingArea = ops.reduce(0) { $0 + ($1.s1 - $1.s0) * ($1.z1 - $1.z0) }
            let fullArea: Double
            if let w = e.wall, w.profile != nil || !w.attachedTopIDs.isEmpty {
                fullArea = WallGeometry.topProfile(e, f, model).area
            } else {
                fullArea = f.length * f.height
            }
            q.length = f.length
            q.height = f.height
            q.width = f.thickness
            q.area = max(0, fullArea - openingArea)
            q.volume = q.area.map { $0 * f.thickness }
            q.elevationBottom = f.baseZ
            q.elevationTop = f.topZ
            q.materials = f.assembly.layers.map { MaterialQuantity(materialID: $0.materialID, area: q.area ?? 0, volume: (q.area ?? 0) * $0.thickness) }
        case .slab:
            guard let p = SlabGeometry.profile(e), let (b, t) = SlabGeometry.planes(e, model) else { return q }
            let th = SlabGeometry.thickness(e, model)
            q.area = p.area
            q.perimeter = p.perimeter
            q.thickness = th
            q.volume = p.area * th
            if let cut = ShaftCuts.remainingArea(e, model) { q.area = cut; q.volume = cut * th } // WP3: shaft openings
            if let pts = e.slab?.shapePoints, !pts.isEmpty { q.volume = abs(SlabGeometry.mesh(e, model).signedVolume) }
            SolidJoins.applyToQuantities(&q, e, model)
            let c = p.outer.centroid
            q.elevationTop = t.z(at: c)
            q.elevationBottom = b.z(at: c)
            if let a = model.typeData(of: e)?.assembly {
                q.materials = a.layers.map { MaterialQuantity(materialID: $0.materialID, area: q.area ?? p.area, volume: (q.area ?? p.area) * $0.thickness) }
            }
        case .roof(let r) where r.extrusion != nil:
            guard let x = RoofExtrusionGeometry.quantities(e, model) else { return q }
            q.area = x.area
            q.volume = x.volume
            q.perimeter = x.perimeter
            q.thickness = RoofGeometry.thickness(e, model)
            q.elevationTop = x.top
            if let a = model.typeData(of: e)?.assembly {
                q.materials = a.layers.map { MaterialQuantity(materialID: $0.materialID, area: x.area, volume: x.area * $0.thickness) }
            }
            SolidJoins.applyToQuantities(&q, e, model)
        case .roof:
            guard let s = RoofGeometry.surface(e, model) else { return q }
            var area = 0.0
            for f in s.faces where f.count >= 3 {
                var n = Vec3.zero
                for i in 1..<(f.count - 1) { n = n + (f[i] - f[0]).cross(f[i + 1] - f[0]) }
                area += n.length / 2
            }
            let holes = RoofGeometry.openings(e).reduce(0) { $0 + $1.area }
            let th = RoofGeometry.thickness(e, model)
            q.area = max(0, area - holes)
            q.thickness = th
            q.volume = max(0, (RoofGeometry.footprint(e)?.polygon.area ?? 0) - holes) * th
            if let shaped = RoofGeometry.shapedMesh(e, model) { q.volume = abs(shaped.signedVolume) }
            SolidJoins.applyToQuantities(&q, e, model)
            q.elevationTop = s.faces.flatMap { $0 }.map(\.z).max()
            q.perimeter = RoofGeometry.footprint(e)?.polygon.perimeter
            if let a = model.typeData(of: e)?.assembly {
                q.materials = a.layers.map { MaterialQuantity(materialID: $0.materialID, area: q.area ?? 0, volume: (q.area ?? 0) * $0.thickness) }
            }
        case .room:
            let b = RoomGeometry.boundary(e, model)
            let h = RoomGeometry.height(e, model)
            q.area = b.area
            q.perimeter = b.perimeter
            q.height = h
            q.volume = b.area * h
        case .column:
            let parts = ComponentGeometry.meshParts(e, model)
            q.volume = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
            if let c = e.column {
                let base = model.baseElevation(of: e)
                q.height = model.topElevation(base: base, topLevelID: c.topLevelID, topOffset: c.topOffset, unconnectedHeight: c.unconnectedHeight) - base
            }
            q.materials = parts.map { MaterialQuantity(materialID: $0.materialID, area: $0.mesh.surfaceArea, volume: abs($0.mesh.signedVolume)) }
        case .beam(let b):
            q.length = b.curve.length
            let (w, d) = BeamGeometry.section(e, model)
            q.width = w; q.height = d
            q.volume = b.curve.length * w * d
        case .stair:
            if let l = StairGeometry.layout(e, model) {
                q.height = l.topZ - l.baseZ
                q.width = l.width
                q.length = l.runs.reduce(0) { $0 + Double($1.risers - 1) * l.treadDepth }
            }
            q.volume = StairGeometry.meshParts(e, model).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        case .railing:
            q.length = RailingGeometry.length(e, model)
        case .ramp:
            if let l = RampGeometry.layout(e, model) {
                q.height = l.rise
                q.width = l.width
                q.length = l.slopedLength
                q.area = l.pieces.reduce(0) { $0 + $1.polygon.area }
                q.elevationBottom = l.baseZ
                q.elevationTop = l.topZ
            }
            q.volume = RampGeometry.meshParts(e, model).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        case .insert:
            if let s = InsertGeometry.openingSize(e, model) {
                q.width = s.width; q.height = s.height; q.area = s.width * s.height
            }
        case .component:
            let parts = ComponentGeometry.meshParts(e, model)
            q.volume = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
            let bb = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            if !bb.isEmpty { q.width = bb.size.x; q.height = bb.size.z }
        case .modelLine(let l):
            q.length = l.drawnLength // F1: splines and ellipses
        case .topography:
            q.area = TopographyGeometry.surfaceArea(e)
            let zs = e.topography?.points.map(\.z) ?? []
            q.elevationTop = zs.max(); q.elevationBottom = zs.min()
            if e.topography?.solid != nil { ToposolidParameters.quantities(e, model, &q) } // BL-SITE
        case .filledRegion(let f):
            if case .success(let p) = f.boundary.profile() { q.area = p.area; q.perimeter = p.perimeter }
        case .mass: // F5: gross surface area and volume
            MassGeometry.quantities(e, model, &q)
        case .furniturePanel, .furnitureShelf, .furnitureLeg, .furnitureRail, .furnitureEdgeProfile, .furnitureForm: // FM4: nominal size, area, volume
            FurniturePartMeshes.quantities(e, model, &q)
        case .furnitureFront: // FM5: front size, area, volume
            FurnitureFrontSolids.quantities(e, model, &q)
        default:
            break
        }
        return q
    }
}

public enum DimensionQueries {
    /// Resolves a geometry reference to a line (for faces/centerlines) or a point, in plan coordinates.
    public static func resolve(_ r: GeometryReference, _ model: BIMModel) -> (point: Vec2, direction: Vec2?)? {
        if r.kind == .point { return r.point.map { ($0, nil) } }
        if r.kind == .partFace { return FurniturePartFaces.resolvePlan(r, model) } // FMG1: furniture part faces
        guard let e = model[r.elementID] else { return r.point.map { ($0, nil) } }
        switch e.data {
        case .wall:
            guard let f = WallGeometry.frame(e, model) else { return nil }
            let c: Curve2
            switch r.kind {
            case .exteriorFace: c = f.exteriorFace
            case .interiorFace: c = f.interiorFace
            case .coreExterior: c = f.location.offset(by: f.offset(fromExterior: f.assembly.exteriorToCore))
            case .coreInterior: c = f.location.offset(by: f.offset(fromExterior: f.assembly.exteriorToCore + f.assembly.coreThickness))
            case .startPoint: return (f.location.start, nil)
            case .endPoint: return (f.location.end, nil)
            default: c = f.location.offset(by: f.centerOffset)
            }
            return (c.midpoint, c.tangent(at: 0.5))
        case .grid(let g):
            switch r.kind {
            case .startPoint: return (g.curve.start, nil)
            case .endPoint: return (g.curve.end, nil)
            default: return (g.curve.midpoint, g.curve.tangent(at: 0.5))
            }
        case .referencePlane(let p):
            if FurniturePlanes.isHorizontal(p) { return FurniturePlanes.position(p).map { (Vec2(0, $0), Vec2(1, 0)) } } // FM3: like a level
            return (p.line.midpoint, p.line.direction)
        case .modelLine(let l):
            switch r.kind {
            case .startPoint: return (l.curve.start, nil)
            case .endPoint: return (l.curve.end, nil)
            default: return (l.curve.midpoint, l.curve.tangent(at: 0.5))
            }
        case .insert:
            guard let pl = InsertGeometry.placement(e, model), let o = FamilyInstanceGeometry.evaluate(e, model)?.opening else { return nil }
            let x: Double
            switch r.kind {
            case .openingLeft: x = o.xMin
            case .openingRight: x = o.xMax
            default: x = (o.xMin + o.xMax) / 2
            }
            return (pl.plan.apply(Vec2(x, 0)), pl.plan.applyVector(Vec2(0, 1)).normalized)
        case .column, .component:
            guard let pl = ComponentGeometry.placement(e, model) else { return nil }
            return (pl.plan.apply(.zero), nil)
        case .level(let l):
            return (Vec2(0, l.elevation), Vec2(1, 0))
        default:
            return r.point.map { ($0, nil) }
        }
    }

    /// Measured distances between consecutive references along the dimension direction.
    public static func measure(_ e: Element, _ model: BIMModel) -> [Double] {
        guard let d = e.dimension else { return [] }
        let pts = d.references.map { resolve($0, model)?.point }
        let resolved: [Vec2] = pts.enumerated().map { i, p in p ?? (i < d.fallbackPoints.count ? d.fallbackPoints[i] : .zero) }
        guard resolved.count >= 2 else { return [] }
        let dir = measurementDirection(d, resolved, model)
        return (0..<(resolved.count - 1)).map { abs((resolved[$0 + 1] - resolved[$0]).dot(dir)) }
    }

    public static func measurementDirection(_ d: DimensionData, _ pts: [Vec2], _ model: BIMModel) -> Vec2 {
        if let a = d.direction { return Vec2.fromAngle(a) }
        // Aligned: perpendicular to the first reference line, else along the first two points.
        if let first = d.references.first, let r = resolve(first, model), let dir = r.direction { return dir.perpendicular.normalized }
        guard pts.count >= 2 else { return .unitX }
        let v = pts[1] - pts[0]
        return v.lengthSquared > 0 ? v.normalized : .unitX
    }
}

public enum RevisionQueries {
    public static func label(_ rev: Element, _ model: BIMModel) -> String {
        guard let r = rev.revisionData else { return "" }
        let same = model.revisions.filter { $0.revisionData?.numbering == r.numbering }
        let index = (same.firstIndex { $0.id == rev.id } ?? 0) + 1
        switch r.numbering {
        case .numeric: return "\(index)"
        case .alphabetic:
            let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ") // I and O are skipped
            var n = index - 1
            var s = ""
            repeat { s = String(letters[n % letters.count]) + s; n = n / letters.count - 1 } while n >= 0
            return s
        }
    }

    /// Revisions shown on a sheet: clouds on the sheet or its placed views, plus explicitly added ones.
    public static func revisions(onSheet sheet: Element, _ model: BIMModel) -> [Element] {
        var ids = Set(sheet.sheet?.additionalRevisionIDs ?? [])
        var views = [sheet.id]
        for vp in model.owned(byView: sheet.id) { if let v = vp.viewport?.viewID { views.append(v) } }
        for v in views {
            for c in model.owned(byView: v) where c.category == .revisionClouds {
                if let r = c.revisionCloud?.revisionID { ids.insert(r) }
            }
        }
        return model.revisions.filter { ids.contains($0.id) }
    }

    public static func current(onSheet sheet: Element, _ model: BIMModel) -> Element? { revisions(onSheet: sheet, model).last }
}
