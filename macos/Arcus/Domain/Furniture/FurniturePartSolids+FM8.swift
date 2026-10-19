import Foundation
import ArcusGeometry

// FM8: parts attached to a shelf (Attach Top/Base, legs At Corners) have no plane binding of their own (regeneration
// keeps them on the shelf). Compiled, their attached end follows the shelf's plane, so a loaded table's legs and a
// cabinet's attached panels flex with the top.

extension FurniturePartSolids {
    /// The coordinate `key` ("top" or "base") of `e` at `value`: on the plane of the shelf it is attached to (its
    /// underside for Attach Top, its top face for Attach Base), else as bound.
    static func attachedValue(_ e: Element, _ m: BIMModel, _ key: String, _ value: Double) -> PartValue {
        let target: ElementID? = switch e.data {
        case .furnitureLeg(let l): key == "top" ? l.attachedTopID : nil
        case .furniturePanel(let p) where p.plane == .xy: key == "top" ? p.attachedTopID : key == "base" ? p.attachedBaseID : nil
        default: nil
        }
        guard let id = target, let s = m[id], let sd = s.furnitureShelf, case .plane(let plane, let offset)? = sd.bounds["z"] else { return pv(e, value, key) }
        return PartValue(value, plane: plane, offset: offset + (value - sd.elevation))
    }
}
