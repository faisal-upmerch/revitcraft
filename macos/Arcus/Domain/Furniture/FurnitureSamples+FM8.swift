import Foundation
import ArcusGeometry

// FM8: the samples lock what a Revit user would lock before loading a piece: the adjustable shelves' and the aprons'
// ends to the framing planes (Left/Right, Front/Back), so the loaded family flexes as a whole.

extension FurnitureSamples {
    /// Binds every unbound plan coordinate (x, y) of the parts `ids` to the nearer framing plane on its side, at its
    /// current offset, as Align and lock do. Heights are left as they are.
    public static func lockToFramingPlanes(_ ids: [ElementID], in tx: TransactionContext) throws(TransactionError) {
        let positions = FurniturePlanes.positionsByName(tx.model)
        func bound(_ v: Double, _ axis: FamilyAxis) -> FurnitureBound? {
            let (lo, hi) = axis == .x ? ("Left", "Right") : axis == .y ? ("Front", "Back") : ("", "")
            guard let a = positions[lo], let b = positions[hi] else { return nil }
            let name = abs(v - a) <= abs(v - b) ? lo : hi
            return .plane(name, offset: v - (name == lo ? a : b))
        }
        for id in ids {
            guard let original = tx.model[id] else { continue }
            var e = original
            var changed = false
            for c in FurniturePartCoordinates.coordinates(of: e) where c.axis != .z {
                guard let b = bound(c.value, c.axis) else { continue }
                switch e.data {
                case .furnitureShelf(var s) where s.bounds[c.key] == nil:
                    s.bounds[c.key] = b; e.data = .furnitureShelf(s); changed = true
                case .furnitureRail(var r) where r.bounds[c.key] == nil:
                    r.bounds[c.key] = b; e.data = .furnitureRail(r); changed = true
                default: break
                }
            }
            if changed { let data = e.data; _ = tx.update(id) { $0.data = data } }
        }
    }
}
