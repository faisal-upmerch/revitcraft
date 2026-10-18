import Foundation
import ArcusGeometry

// BL-VG: Modify ▸ Geometry — Cut/Uncut Geometry and Switch Join Order on top of Join Geometry.

extension SolidJoins {
    /// Elements whose solids are rebuilt as prisms after a cut: floors, building pads, ceilings and roofs. Walls can
    /// cut but are not cut (their layered geometry isn't rebuilt from prisms).
    public static func isCuttable(_ e: Element) -> Bool { priority(e).map { $0 < 3 } ?? false }

    /// For two selected elements, which one is cut and which cuts: the only cuttable one is cut; when both are
    /// cuttable, the first picked is cut (as in "pick the geometry to cut, then the cutting geometry").
    public static func cutPair(_ first: Element, _ second: Element) -> (cutter: Element, cut: Element)? {
        guard first.id != second.id, priority(first) != nil, priority(second) != nil else { return nil }
        switch (isCuttable(first), isCuttable(second)) {
        case (true, _): return (second, first)
        case (false, true): return (first, second)
        default: return nil
        }
    }

    /// Cut Geometry: `cutter` removes its overlap from `cut`, whatever the usual join order.
    public static func cutGeometry(cutter: ElementID, cut: ElementID, in tx: TransactionContext) throws(TransactionError) {
        guard let a = tx.model[cutter], let b = tx.model[cut], priority(a) != nil, isCuttable(b) else {
            throw TransactionError("Cut Geometry cuts floors, ceilings, roofs and building pads with walls, floors, roofs or ceilings.")
        }
        guard joinID(cutter, cut, tx.model) == nil else {
            throw TransactionError("These elements are already joined.", elements: [cutter, cut], resolution: "Use Switch Join Order to change which one cuts.")
        }
        guard overlapVolume(b, a, tx.model) > 1e-9 else {
            throw TransactionError("The elements don't overlap, so there is nothing to cut.", elements: [cutter, cut])
        }
        tx.create(.constraints, data: .constraint(ConstraintData(kind: .join, references: [GeometryReference(cutter, .location), GeometryReference(cut, .location)])))
    }

    /// Switch Join Order: the element that was cut now cuts. Only possible when the former cutter can be cut.
    public static func switchJoinOrder(_ a: ElementID, _ b: ElementID, in tx: TransactionContext) throws(TransactionError) {
        guard let j = joins(tx.model).first(where: { ($0.cutter == a && $0.cut == b) || ($0.cutter == b && $0.cut == a) }) else {
            throw TransactionError("The selected elements aren't joined.", elements: [a, b])
        }
        guard let newCut = tx.model[j.cutter], isCuttable(newCut) else {
            throw TransactionError("Walls always cut floors, ceilings and roofs; the join order can't be switched.", elements: [a, b])
        }
        tx.update(j.id) { e in e.constraint?.references = [GeometryReference(j.cut, .location), GeometryReference(j.cutter, .location)] }
    }
}
