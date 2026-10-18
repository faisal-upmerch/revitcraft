import Foundation
import ArcusGeometry

/// F2: slanted columns (RevitCraft `FamilyInstance::top_location`, Slanted Column). The column's body leans from its
/// base point to its top point: every horizontal section is the vertical column's, moved along the axis, so the ends
/// stay level with the floors they meet (Revit's "Horizontal" end cut).
public enum SlantedColumns {
    /// Plan offset of the column's section at elevation `z` (zero for vertical columns).
    public static func planShift(_ c: ColumnData, base: Double, top: Double, atZ z: Double) -> Vec2 {
        guard let t = c.topLocation, top - base > Tolerance.length else { return .zero }
        return (t - c.location) * ((z - base) / (top - base))
    }

    /// Leans the vertical column's mesh parts (built from `base` up `height`) toward the top point.
    public static func lean(_ parts: [MeshPart], _ c: ColumnData, base: Double, height h: Double) -> [MeshPart] {
        guard let t = c.topLocation, h > Tolerance.length else { return parts }
        let d = t - c.location
        guard d.length > Tolerance.length else { return parts }
        return parts.map { part in
            var p = part
            for i in p.mesh.positions.indices {
                let q = p.mesh.positions[i]
                let k = (q.z - base) / h
                p.mesh.positions[i] = Vec3(q.x + d.x * k, q.y + d.y * k, q.z)
            }
            WallGeometry.recomputeFlatNormals(&p.mesh)
            return p
        }
    }

    /// The column's axis in 3D, base to top.
    public static func axis(_ e: Element, _ model: BIMModel) -> (Vec3, Vec3)? {
        guard let c = e.column else { return nil }
        let base = model.baseElevation(of: e)
        let top = model.topElevation(base: base, topLevelID: c.topLevelID, topOffset: c.topOffset, unconnectedHeight: c.unconnectedHeight)
        return (Vec3(c.location, z: base), Vec3(c.topLocation ?? c.location, z: top))
    }
}
