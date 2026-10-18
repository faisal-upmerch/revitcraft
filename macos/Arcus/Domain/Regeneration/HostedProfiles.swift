import Foundation
import ArcusGeometry

// W2-DWG: profiles that belong to a host element — wall sweeps, floor slab edges and roof soffits. They are stored on the
// host (optional fields, so older documents decode unchanged) and regenerate with it, like the roof's fascia and gutter.

/// A horizontal sweep along one face of a wall (base board, string course, cornice).
public struct WallSweep: Hashable, Codable, Sendable {
    public enum Side: String, Codable, Sendable, CaseIterable { case exterior = "Exterior", interior = "Interior" }
    /// Height of the sweep's bottom above the wall base.
    public var height: Double
    /// How far it projects from the face.
    public var projection: Double
    /// Vertical size of the profile.
    public var depth: Double
    public var side: Side
    public var materialID: ElementID?
    public init(height: Double = 0, projection: Double = 0.02, depth: Double = 0.15, side: Side = .exterior, materialID: ElementID? = nil) {
        self.height = height; self.projection = projection; self.depth = depth; self.side = side; self.materialID = materialID
    }
}

/// A thickened edge (downstand) swept under a floor along its outer boundary.
public struct SlabEdgeProfile: Hashable, Codable, Sendable {
    /// Width measured inward from the slab edge.
    public var width: Double
    /// Depth below the underside of the slab.
    public var depth: Double
    public var materialID: ElementID?
    public init(width: Double = 0.3, depth: Double = 0.3, materialID: ElementID? = nil) { self.width = width; self.depth = depth; self.materialID = materialID }
}

/// A flat soffit board under the eaves of a footprint roof.
public struct RoofSoffit: Hashable, Codable, Sendable {
    /// Width measured inward from the eave line (defaults to the roof's overhang when it has one).
    public var depth: Double
    public var thickness: Double
    public var materialID: ElementID?
    public init(depth: Double = 0.45, thickness: Double = 0.02, materialID: ElementID? = nil) { self.depth = depth; self.thickness = thickness; self.materialID = materialID }
}

public enum HostedProfiles {
    /// Extra mesh parts for an element's sweeps, slab edge or soffit (empty when it has none).
    public static func parts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        switch e.data {
        case .wall(let w) where w.curtain == nil && !(w.sweeps ?? []).isEmpty:
            return wallSweepParts(e, model)
        case .slab(let s) where s.edgeProfile != nil && e.category == .floors:
            return slabEdgeParts(e, model)
        case .roof(let r) where r.soffit != nil && r.extrusion == nil:
            return soffitParts(e, model)
        default:
            return []
        }
    }

    static func wallSweepParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let w = e.wall, let f = WallGeometry.frame(e, model) else { return [] }
        var out: [MeshPart] = []
        for s in w.sweeps ?? [] where s.projection > Tolerance.length && s.depth > Tolerance.length {
            let z = f.baseZ + s.height
            guard z >= f.baseZ - Tolerance.length, z < f.topZ else { continue }
            let offset = s.side == .exterior ? f.exteriorOffset : f.interiorOffset
            let other = s.side == .exterior ? f.interiorOffset : f.exteriorOffset
            // Profile u points left of the path; the face's outward direction is away from the other face.
            let outward: Double = offset >= other ? 1 : -1
            let path = f.location.offset(by: offset).tessellate(chordTolerance: 0.01).map { Vec3($0, z: z) }
            let depth = min(s.depth, f.topZ - z)
            let prof = Polygon2([Vec2(0, 0), Vec2(outward * s.projection, 0), Vec2(outward * s.projection, depth), Vec2(0, depth)])
            let mesh = MeshBuilder.sweep(profile: prof, along: path)
            if !mesh.isEmpty { out.append(MeshPart(mesh: mesh, materialID: s.materialID, subcategory: .frame)) }
        }
        return out
    }

    static func slabEdgeParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let edge = e.slab?.edgeProfile, edge.width > Tolerance.length, edge.depth > Tolerance.length,
              let prof = SlabGeometry.profile(e), let (_, top) = SlabGeometry.planes(e, model) else { return [] }
        let t = SlabGeometry.thickness(e, model)
        let outer = prof.outer.simplified().counterClockwise
        guard outer.count >= 3 else { return [] }
        // Closed path around the counter-clockwise outline: the interior is on the left (+u).
        var path = outer.points.map { Vec3($0, z: top.z(at: $0)) }
        path.append(path[0])
        let section = Polygon2([Vec2(0, -t - edge.depth), Vec2(edge.width, -t - edge.depth), Vec2(edge.width, -t), Vec2(0, -t)])
        let mesh = MeshBuilder.sweep(profile: section, along: path)
        return mesh.isEmpty ? [] : [MeshPart(mesh: mesh, materialID: edge.materialID ?? SlabGeometry.surfaceMaterial(e, model), subcategory: .general)]
    }

    static func soffitParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let r = e.roof, let so = r.soffit, let (poly, _) = RoofGeometry.footprint(e) else { return [] }
        let depth = so.depth > Tolerance.length ? so.depth : (r.overhang > Tolerance.length ? r.overhang : 0.45)
        let inner = poly.offset(by: -depth)
        let holes = inner.filter(\.isCounterClockwise).map(\.clockwise)
        guard !holes.isEmpty else { return [] }
        let top = RoofGeometry.baseZ(e, model) - RoofGeometry.thickness(e, model)
        let mesh = MeshBuilder.extrude(Profile2(outer: poly.counterClockwise, holes: holes), bottom: top - max(0.005, so.thickness), top: top)
        return mesh.isEmpty ? [] : [MeshPart(mesh: mesh, materialID: so.materialID, subcategory: .frame)]
    }
}
