import Foundation
import ArcusGeometry

// FM3D: the "3D Design" view of Furniture documents: where the piece is designed in 3D. An orbit-friendly camera on the
// piece (from the front left, above, the piece's middle as the pivot), shaded with edges, Fine, and the work plane
// shown (Ref. Level, with a 6" grid in Furniture documents) so the plane the tools draw on is always visible.

public enum FurnitureDesignView {
    public static let name = "3D Design"

    /// The camera that frames the piece (its planes Left…Right, Front…Back, Bottom…Top) from the front left.
    public static func camera(_ m: BIMModel) -> Camera3D {
        let p = FurniturePlanes.positionsByName(m)
        let lo = Vec3(p["Left"] ?? -0.45, p["Front"] ?? -0.2, p["Bottom"] ?? 0), hi = Vec3(p["Right"] ?? 0.45, p["Back"] ?? 0.2, p["Top"] ?? 0.75)
        let center = (lo + hi) * 0.5
        let size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.3)
        let dir = Vec3(-0.62, -0.85, 0.55).normalized
        return Camera3D(eye: center + dir * size * 4, target: center, orthoHeight: size * 2.1)
    }

    /// The view's data for `m`.
    public static func data(_ m: BIMModel) -> ViewData {
        var v = ViewData(kind: .threeD, scale: 12)
        v.camera = camera(m)
        v.detailLevel = .fine
        v.visualStyle = .shaded
        v.phaseID = m.phases.first?.id
        v.showsWorkPlane = true
        if let l = m.levels.first?.id { v.workPlane = .level(l) }
        return v
    }

    /// The document's 3D Design view, created when missing (Furniture documents only).
    @discardableResult
    public static func ensure(in tx: TransactionContext) -> ElementID? {
        guard tx.model.isFurniture else { return nil }
        if let v = tx.model.views.first(where: { $0.name == name && $0.view?.kind == .threeD }) { return v.id }
        return tx.create(.views, name: name, data: .view(data(tx.model)))
    }
}
