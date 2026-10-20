import Foundation
import ArcusGeometry

// F1415: evaluated model lines and controls, and void cutting for every form (RevitCraft `FamilyDef::build`: solids minus
// the union of the voids).

extension EvaluatedFamily {
    /// A model or reference line in family coordinates.
    public struct ModelLine: Sendable {
        public var start: Vec3
        public var end: Vec3
        public var isReference: Bool
        public var subcategory: FamilySubcategory
        public var visibleAt: Set<DetailLevel>
        /// Id of the `FamilyModelLine` this came from (nil for lines of nested families).
        public var sourceID: String?
    }

    /// A flip control at its plan position in family coordinates.
    public struct Control: Sendable {
        public var position: Vec2
        public var kind: FamilyControlKind
        public var sourceID: String?
    }

    /// Total volume of the solids (voids excluded), for quantities and tests.
    public var solidVolume: Double {
        solids.filter { !$0.isVoid }.reduce(0) { $0 + abs($1.familyMesh.signedVolume) }
    }
}

extension FamilyEvaluator {
    /// Cuts every solid by every void it reaches. Voids stay in the list (the editor draws them).
    static func cutVoids(_ solids: [EvaluatedFamily.Solid]) -> [EvaluatedFamily.Solid] {
        let voids = solids.filter(\.isVoid)
        guard !voids.isEmpty else { return solids }
        let voidBounds = voids.map(\.bounds) // VIS: each bounds once (mesh bounds walk every vertex)
        var out: [EvaluatedFamily.Solid] = []
        for s in solids {
            guard !s.isVoid else { out.append(s); continue }
            var parts = [s]
            let sb = s.bounds
            for (v, vb) in zip(voids, voidBounds) where sb.intersects(vb) && (v.cuts.map { c in s.sourceID.map(c.contains) ?? false } ?? true) { // FM6: Cut Geometry
                let whole = parts.count == 1 // still the solid's own extent (cuts only shrink it)
                parts = parts.flatMap { p -> [EvaluatedFamily.Solid] in
                    guard (whole ? sb : p.bounds).intersects(vb) else { return [p] }
                    // FM6: a void cuts at the detail levels it shows at; the solid keeps an uncut copy for the others.
                    let common = p.visibleAt.intersection(v.visibleAt)
                    guard !common.isEmpty else { return [p] }
                    var q = p, uncut: [EvaluatedFamily.Solid] = []
                    if common != p.visibleAt { var u = p; u.visibleAt = p.visibleAt.subtracting(common); uncut = [u]; q.visibleAt = common }
                    if q.form == .extrusion, v.form == .extrusion, q.mesh == nil, v.mesh == nil { return uncut + cut(q, by: v) }
                    return uncut + meshCut(q, by: v)
                }
            }
            out += parts
        }
        return out
    }

    /// A solid minus a void as meshes: the solid keeps its form, name and settings with the cut mesh; its plan footprint
    /// stays the uncut one. A void that removes the whole solid removes it.
    static func meshCut(_ s: EvaluatedFamily.Solid, by v: EvaluatedFamily.Solid) -> [EvaluatedFamily.Solid] {
        guard let mesh = FamilyFormGeometry.subtract(s.familyMesh, v.familyMesh) else { return [s] }
        guard !mesh.isEmpty else { return [] }
        var c = s
        c.mesh = mesh
        c.booleanCut = true // VIS
        let b = mesh.bounds
        c.zMin = b.min.z; c.zMax = b.max.z
        return [c]
    }
}
