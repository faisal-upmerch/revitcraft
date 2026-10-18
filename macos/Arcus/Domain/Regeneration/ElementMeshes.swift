import Foundation
import ArcusGeometry

/// Dispatches 3D representation generation per element kind.
public enum ElementMeshes {
    public static func parts(_ e: Element, _ model: BIMModel, detail: DetailLevel = .fine) -> [MeshPart] {
        let base = rawParts(e, model, detail: detail) + HostedProfiles.parts(e, model) // W2-DWG: sweeps, slab edges, soffits
        // Painted material override applies to every surface of the element.
        guard let paint = e.params[.paintMaterial]?.refValue, model[paint]?.material != nil else { return base }
        return base.map { var p = $0; p.materialID = paint; return p }
    }

    static func rawParts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart] {
        switch e.data {
        case .wall:
            return wallParts(e, model, detail: detail)
        case .insert:
            return InsertGeometry.meshParts(e, model, detail: detail)
        case .component, .column:
            return ComponentGeometry.meshParts(e, model, detail: detail)
        case .beam:
            return BeamGeometry.meshParts(e, model)
        case .slab:
            return SlabGeometry.meshParts(e, model, detail: detail)
        case .roof:
            return RoofGeometry.meshParts(e, model)
        case .stair:
            return StairGeometry.meshParts(e, model)
        case .railing:
            return RailingGeometry.meshParts(e, model)
        case .ramp:
            return RampGeometry.meshParts(e, model)
        case .topography where e.topography?.solid != nil:
            return ToposolidGeometry.meshParts(e, model) // BL-SITE: layered toposolids and sub-divisions
        case .topography:
            return [MeshPart(mesh: TopographyGeometry.mesh(e), materialID: e.topography?.materialID)] // W2-DWG: sub-region material
        case .referenceGeometry(let r):
            return [MeshPart(mesh: r.mesh, materialID: nil)]
        case .linkedModel, .pointCloud, .decal: // F67
            return LinkedGeometry.meshParts(e, model)
        default:
            return []
        }
    }

    static func wallParts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart] {
        if let curtain = CurtainWallGeometry.meshParts(e, model) { return curtain } // WP3
        let mesh = WallGeometry.solid(e, model)
        guard let f = WallGeometry.frame(e, model) else { return [] }
        // Material: the core layer (layer-by-layer solids would multiply geometry; plan/section views show layers).
        let core = f.assembly.layers.indices.contains(f.assembly.coreStart) ? f.assembly.layers[f.assembly.coreStart] : f.assembly.layers.first
        let exterior = f.assembly.layers.first
        return [MeshPart(mesh: mesh, materialID: exterior?.materialID ?? core?.materialID)]
    }

    /// True if the element has a 3D representation.
    public static func hasModelGeometry(_ e: Element) -> Bool {
        switch e.data {
        case .wall, .insert, .component, .column, .beam, .slab, .roof, .stair, .railing, .topography, .referenceGeometry, .ramp: true
        case .linkedModel, .pointCloud, .decal: true // F67
        default: false
        }
    }

    /// Default color for categories when an element has no material.
    public static func defaultColor(_ c: Category) -> RGBColor {
        switch c {
        case .walls: RGBColor(0.86, 0.84, 0.80)
        case .floors, .buildingPads: RGBColor(0.78, 0.77, 0.74)
        case .ceilings: RGBColor(0.93, 0.93, 0.92)
        case .roofs: RGBColor(0.55, 0.50, 0.47)
        case .doors: RGBColor(0.70, 0.56, 0.42)
        case .windows: RGBColor(0.60, 0.74, 0.82, 0.55)
        case .stairs, .ramps: RGBColor(0.74, 0.73, 0.70)
        case .railings: RGBColor(0.35, 0.36, 0.38)
        case .columns, .structuralColumns, .structuralFraming: RGBColor(0.72, 0.72, 0.70)
        case .furniture, .casework: RGBColor(0.80, 0.70, 0.58)
        case .topography: RGBColor(0.62, 0.70, 0.55)
        case .ifcReference: RGBColor(0.68, 0.72, 0.80, 0.8)
        case .planting: RGBColor(0.45, 0.62, 0.36) // W2-LIB
        case .entourage: RGBColor(0.62, 0.66, 0.74)
        case .lightingFixtures: RGBColor(0.93, 0.92, 0.86)
        case .site: RGBColor(0.70, 0.70, 0.68)
        case .pointClouds: RGBColor(0.36, 0.46, 0.62) // F67
        case .coordinationModels: RGBColor(0.72, 0.74, 0.80, 0.9)
        default: RGBColor(0.80, 0.80, 0.80)
        }
    }

    /// World bounding box of an element's model geometry or plan graphics.
    public static func bounds(_ e: Element, _ model: BIMModel) -> Box3 {
        switch e.data {
        case .wall(let w):
            guard let f = WallGeometry.frame(e, model) else { return .empty }
            let r = w.location.bounds.expanded(by: f.thickness)
            return Box3(min: Vec3(r.min, z: f.baseZ), max: Vec3(r.max, z: f.topZ))
        case .level(let l):
            return Box3(min: Vec3(0, 0, l.elevation), max: Vec3(0, 0, l.elevation))
        case .grid(let g):
            let r = g.curve.bounds
            return Box3(min: Vec3(r.min, z: 0), max: Vec3(r.max, z: 0))
        case .room(let r):
            let z = model.baseElevation(of: e)
            if let p = RoomGeometry.boundary(e, model).profile {
                return Box3(min: Vec3(p.bounds.min, z: z), max: Vec3(p.bounds.max, z: z + RoomGeometry.height(e, model)))
            }
            return Box3(min: Vec3(r.point, z: z), max: Vec3(r.point, z: z))
        case .modelLine(let l):
            let r = l.curve.bounds
            let z = model.elevation(ofLevel: e.levelID)
            return Box3(min: Vec3(r.min, z: z), max: Vec3(r.max, z: z))
        case .link(let l):
            guard let d = model.referenceDrawings[l.contentKey] else { return .empty }
            let r = Rect2(points: d.extents.corners.map(l.placement.apply))
            let z = model.elevation(ofLevel: e.levelID) + l.elevationOffset
            return Box3(min: Vec3(r.min, z: z), max: Vec3(r.max, z: z))
        default:
            return parts(e, model, detail: .coarse).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        }
    }
}

/// Thread-safe cache of element meshes keyed by the revisions of every input the geometry depends on.
/// A stale entry can never be returned because its key no longer matches.
/// Drops every process-wide derived-geometry cache (meshes, room boundaries, evaluated families). Called when the
/// last document closes so a closed project's derived data does not stay resident.
public enum DerivedCaches {
    public static func purgeAll() {
        GeometryCache.shared.purge()
        RoomBoundaryCache.shared.purge()
        FamilyEvalCache.shared.purge()
    }
}

public final class GeometryCache: @unchecked Sendable {
    public static let shared = GeometryCache()
    private let lock = NSLock()
    private var entries: [ElementID: (key: Int, parts: [MeshPart])] = [:]
    public private(set) var hits = 0
    public private(set) var misses = 0

    public func parts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart] {
        let key = GeometryCache.key(e, model, detail: detail)
        lock.lock()
        if let hit = entries[e.id], hit.key == key { hits += 1; lock.unlock(); return hit.parts }
        misses += 1
        lock.unlock()
        let p = ElementMeshes.parts(e, model, detail: detail)
        lock.lock()
        entries[e.id] = (key, p)
        lock.unlock()
        return p
    }

    public func purge() { lock.lock(); entries.removeAll(); lock.unlock() }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    public var approximateBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.values.reduce(0) { acc, v in acc + v.parts.reduce(0) { $0 + $1.mesh.positions.count * 48 + $1.mesh.indices.count * 4 + $1.mesh.featureEdges.count * 4 } }
    }

    public static func key(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> Int {
        var h = Hasher()
        h.combine(detail)
        for id in DependencyGraph.inputs(of: e, model) {
            h.combine(id)
            h.combine(model[id]?.revision ?? 0)
        }
        return h.finalize()
    }
}

/// Dependency relationships used for cache keys and localized invalidation.
public enum DependencyGraph {
    /// Elements whose state the geometry of `e` depends on (including `e`). Sorted, deterministic.
    public static func inputs(of e: Element, _ model: BIMModel) -> [ElementID] {
        var s: Set<ElementID> = [e.id]
        func addType(_ x: Element) {
            if let t = x.typeID {
                s.insert(t)
                if let f = model[t]?.typeData?.familyID { s.insert(f) }
                if let a = model[t]?.typeData?.assembly { for l in a.layers { if let m = l.materialID { s.insert(m) } } }
            }
        }
        addType(e)
        if let l = e.levelID { s.insert(l) }
        s.formUnion(SolidJoins.inputs(of: e, model))
        switch e.data {
        case .wall(let w):
            if let t = w.topLevelID { s.insert(t) }
            for i in model.hosted(by: e.id) { s.insert(i.id); addType(i) }
            for o in WallGeometry.joinCandidates(e, model) { s.insert(o.id); addType(o); if let l = o.levelID { s.insert(l) }; if let t = o.wall?.topLevelID { s.insert(t) } }
            for a in w.attachedTopIDs + w.attachedBaseIDs { s.insert(a); if let x = model[a] { addType(x); if let l = x.levelID { s.insert(l) } } }
        case .insert:
            if let h = model[e.hostID] {
                s.insert(h.id); addType(h)
                if let l = h.levelID { s.insert(l) }
                if let t = h.wall?.topLevelID { s.insert(t) }
            }
        case .column(let c):
            if let t = c.topLevelID { s.insert(t) }
        case .stair(let st):
            if let t = st.topLevelID { s.insert(t) }
        case .ramp(let r):
            if let t = r.topLevelID { s.insert(t) }
        case .railing:
            if let h = model[e.hostID] { s.insert(h.id); addType(h); if let l = h.levelID { s.insert(l) }; if let t = h.stair?.topLevelID ?? h.ramp?.topLevelID { s.insert(t) } }
        case .topography: // BL-SITE: a sub-division follows its host toposolid
            if let h = model[e.hostID], h.topography != nil { s.insert(h.id) }
        case .decal(let d): // F67: the decal type's image
            s.insert(d.decalTypeID)
        case .slab, .roof: // WP3: shafts cutting this element
            for sh in ShaftCuts.shafts(cutting: e, model) { s.insert(sh.id); if let l = sh.levelID { s.insert(l) }; if let t = sh.opening?.shaft?.topLevelID { s.insert(t) } }
        default:
            break
        }
        if case .wall = e.data, let c = model.typeData(of: e)?.curtain { // WP3: curtain panel types
            if let p = c.panelTypeID { s.insert(p) }
            for o in e.wall?.curtain?.panels ?? [] { if let p = o.typeID { s.insert(p) } }
        }
        return s.sorted()
    }

    /// Elements whose derived graphics are affected by a set of changed elements.
    public static func affected(by changed: Set<ElementID>, before: BIMModel, after: BIMModel) -> Set<ElementID> {
        var out = changed
        for id in changed {
            for m in [before, after] {
                guard let e = m[id] else { continue }
                switch e.data {
                case .wall:
                    for o in WallGeometry.joinCandidates(e, m) { out.insert(o.id) }
                    for i in m.hosted(by: id) { out.insert(i.id) }
                    for r in m.elements(.rooms) where r.levelID == e.levelID { out.insert(r.id) }
                case .level:
                    for x in m.onLevel(id) { out.insert(x.id) }
                    for w in m.elements(.walls) where w.wall?.topLevelID == id { out.insert(w.id) }
                case .type:
                    for x in m.instances(ofType: id) { out.insert(x.id) }
                case .family:
                    for t in m.elements(.elementTypes) where t.typeData?.familyID == id { for x in m.instances(ofType: t.id) { out.insert(x.id) } }
                case .modelLine, .column:
                    for r in m.elements(.rooms) where r.levelID == e.levelID { out.insert(r.id) }
                case .insert:
                    if let h = e.hostID { out.insert(h) }
                case .stair, .ramp:
                    for r in m.hosted(by: id) { out.insert(r.id) }
                case .topography: // BL-SITE: sub-divisions follow their host
                    for r in m.hosted(by: id) { out.insert(r.id) }
                case .opening: // WP3
                    if let h = e.hostID { out.insert(h) }
                    for x in ShaftCuts.cutElements(by: e, m) { out.insert(x.id) }
                default: break
                }
                for t in m.tags(of: id) { out.insert(t.id) }
                out.formUnion(SolidJoins.partners(of: id, m))
                if e.typeData?.instanceCategory == .curtainPanels { for w in CurtainWallGeometry.walls(usingPanelType: id, m) { out.insert(w.id) } } // WP3
            }
        }
        return out
    }
}
