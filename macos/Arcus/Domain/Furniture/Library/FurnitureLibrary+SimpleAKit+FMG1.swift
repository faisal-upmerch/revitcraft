import Foundation
import ArcusGeometry

// FMG1: Slats parts for the part A simple pieces (slatted table tops and bed slats), in place of one rail per slat: a
// Fixed Number layout whose first and last slats are locked to the planes, so the slats spread as the piece flexes.

extension SA.Builder {
    /// `count` slats of `typeName` with their tops at `top`, running along x between `x` (or along y between `y` when
    /// `alongX` is false), the first slat's centre on `first` and the last one's on `last`.
    @discardableResult
    func slats(alongX: Bool, run: (SA.LP, SA.LP), first: SA.LP, last: SA.LP, count: Int, top: SA.LP, _ typeName: String) throws -> ElementID {
        let t = try type(.furnitureRails, typeName)
        let w = FurniturePartTypes.Values(tx.model[t]?.typeData).width
        let a = min(v(first), v(last)) - w / 2, c = max(v(first), v(last)) + w / 2
        let r0 = min(v(run.0), v(run.1)), r1 = max(v(run.0), v(run.1))
        let rect = alongX ? Rect2(min: Vec2(r0, a), max: Vec2(r1, c)) : Rect2(min: Vec2(a, r0), max: Vec2(c, r1))
        let id = try FurniturePartOperations.createSlats(in: rect, alongX: alongX, rule: .fixedNumber, spacing: 0.1, number: max(1, count), z: v(top), typeID: t, in: tx)
        let lo = v(run.0) <= v(run.1) ? run.0 : run.1, hi = v(run.0) <= v(run.1) ? run.1 : run.0
        if alongX {
            setBounds(id, ["start.u": bound(lo), "end.u": bound(hi), "start.v": bound(first), "end.v": bound(first), "far": bound(last), "w": bound(top)])
        } else {
            // Slats along y run from the high end to the low end, so they lie to the line's left (+x).
            setBounds(id, ["start.v": bound(hi), "end.v": bound(lo), "start.u": bound(first), "end.u": bound(first), "far": bound(last), "w": bound(top)])
        }
        return id
    }
}
