import Foundation
import ArcusGeometry

/// Maintains locked dimensions, alignments and equality constraints after edits.
///
/// Strategy: references edited by the user in the transaction ("driven") and pinned elements are fixed.
/// Violated constraints are repaired by translating a free element perpendicular to the constrained
/// references. The solver iterates to a fixed point; if constraints remain violated, the transaction
/// is rejected with a conflict that names the elements involved (nothing is committed).
public enum ConstraintSolver {
    public static let maxPasses = 24

    public static func solve(_ tx: TransactionContext) throws(TransactionError) {
        let constraints = activeConstraints(tx.model)
        guard !constraints.isEmpty else { return }
        // Only solve when something relevant changed.
        let touched = Set(tx.touchedIDs)
        let relevant = constraints.filter { c in c.data.references.contains { $0.elementID.map(touched.contains) ?? false } || touched.contains(c.id) }
        guard !relevant.isEmpty else { return }
        var fixed = tx.driven
        for c in constraints { for r in c.data.references { if let id = r.elementID, tx.model[id]?.pinned == true { fixed.insert(id) } } }

        for _ in 0..<maxPasses {
            var violated = false
            for c in constraints {
                guard let err = violation(c.data, tx.model), abs(err.amount) > Tolerance.length * 10 else { continue }
                violated = true
                // Move the last free reference (constraints read left to right: later references follow earlier ones).
                let candidates = err.movable.filter { !fixed.contains($0.id) }
                guard let target = candidates.last else {
                    throw TransactionError("Constraints are not satisfied: a locked or equal dimension would have to change.",
                                           elements: c.data.references.compactMap(\.elementID) + [c.id],
                                           resolution: "Unlock the dimension or remove the constraint, then try again.")
                }
                translate(target.id, by: target.direction * target.sign * err.amount, in: tx)
                fixed.insert(target.id)
            }
            if !violated { return }
        }
        let still = constraints.filter { violation($0.data, tx.model).map { abs($0.amount) > Tolerance.length * 10 } ?? false }
        if !still.isEmpty {
            throw TransactionError("Constraints conflict and cannot all be satisfied.",
                                   elements: still.flatMap { $0.data.references.compactMap(\.elementID) },
                                   resolution: "Remove one of the conflicting locks.")
        }
    }

    struct Movable { var id: ElementID; var direction: Vec2; var sign: Double }
    struct Violation { var amount: Double; var movable: [Movable] }

    static func activeConstraints(_ model: BIMModel) -> [(id: ElementID, data: ConstraintData)] {
        var out: [(ElementID, ConstraintData)] = model.elements(.constraints).compactMap { e in e.constraint.map { (e.id, $0) } }
        // Locked / EQ permanent dimensions act as constraints too.
        for d in model.elements(.dimensions) {
            guard let dd = d.dimension, dd.references.count >= 2 else { continue }
            if dd.locked, dd.references.count == 2 {
                let value = DimensionQueries.measure(d, model).first ?? 0
                let stored = d.params[ParameterID("dimension.lockedValue")]?.doubleValue ?? value
                out.append((d.id, ConstraintData(kind: .lockedDistance, references: dd.references, value: stored, dimensionID: d.id)))
            }
            if dd.equality, dd.references.count >= 3 {
                out.append((d.id, ConstraintData(kind: .equality, references: dd.references, dimensionID: d.id)))
            }
        }
        return out.map { (id: $0.0, data: $0.1) }
    }

    /// Positions of references projected on the constraint normal.
    static func positions(_ refs: [GeometryReference], _ model: BIMModel) -> (normal: Vec2, values: [Double])? {
        let resolved = refs.map { DimensionQueries.resolve($0, model) }
        guard resolved.allSatisfy({ $0 != nil }) else { return nil }
        let r = resolved.map { $0! }
        let normal: Vec2
        if let d = r.first(where: { $0.direction != nil })?.direction { normal = d.perpendicular.normalized }
        else if r.count >= 2 { normal = (r[1].point - r[0].point).normalized }
        else { return nil }
        return (normal, r.map { $0.point.dot(normal) })
    }

    static func violation(_ c: ConstraintData, _ model: BIMModel) -> Violation? {
        // Solid joins are geometry relationships, not dimensional locks: nothing to solve.
        guard c.kind != .join else { return nil }
        guard let (n, vals) = positions(c.references, model), vals.count >= 2 else { return nil }
        func movable(_ i: Int, sign: Double) -> Movable? {
            guard let id = c.references[i].elementID, let e = model[id], ElementTransform.isTransformable(e) || e.level != nil else { return nil }
            return Movable(id: id, direction: n, sign: sign)
        }
        switch c.kind {
        case .alignment:
            let delta = vals[1] - vals[0]
            return Violation(amount: -delta, movable: [movable(0, sign: -1), movable(1, sign: 1)].compactMap { $0 })
        case .lockedDistance:
            let current = vals[1] - vals[0]
            let target = current >= 0 ? abs(c.value) : -abs(c.value)
            let delta = target - current
            return Violation(amount: delta, movable: [movable(0, sign: -1), movable(1, sign: 1)].compactMap { $0 })
        case .equality:
            let first = vals.first!, last = vals.last!
            let step = (last - first) / Double(vals.count - 1)
            var worst = 0.0, worstIndex = -1
            for i in 1..<(vals.count - 1) {
                let d = (first + step * Double(i)) - vals[i]
                if abs(d) > abs(worst) { worst = d; worstIndex = i }
            }
            guard worstIndex > 0 else { return nil }
            return Violation(amount: worst, movable: [movable(worstIndex, sign: 1)].compactMap { $0 })
        case .join:
            return nil
        }
    }

    /// Translates an element (plan) or a level (elevation) by a vector.
    public static func translate(_ id: ElementID, by v: Vec2, in tx: TransactionContext) {
        guard let e = tx.model[id] else { return }
        if e.level != nil {
            tx.propagate(id) { $0.level?.elevation += v.y }
            return
        }
        let t = Transform2.translation(v)
        tx.propagate(id) { ElementTransform.apply(t, to: &$0) }
        // Hosted inserts ride with their host.
        for h in tx.model.hosted(by: id) where h.insert != nil {
            tx.propagate(h.id) { ElementTransform.apply(t, to: &$0) }
        }
    }
}
