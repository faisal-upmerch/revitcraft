import Foundation
import ArcusGeometry
import ArcusDomain

// W2-CAM: eye and target grips of a camera view's glyph in plan.

/// Plan grips for camera views: `.start` is the eye, `.end` the target. Dragging keeps heights and roll.
enum CameraGrips {
    static func grips(for e: Element, viewKind: ViewKind?) -> [Grip] {
        guard viewKind?.isPlan == true, e.isCameraView, let c = e.view?.camera else { return [] }
        return [Grip(elementID: e.id, kind: .start, position: c.eye.xy), Grip(elementID: e.id, kind: .end, position: c.target.xy)]
    }

    /// Moves the eye or target of a camera view in plan. Returns false when the grip is not a camera grip.
    static func apply(_ g: Grip, to p: Vec2, in tx: TransactionContext) -> Bool {
        guard g.kind == .start || g.kind == .end, let e = tx.model[g.elementID], e.isCameraView, var c = e.view?.camera else { return false }
        let roll = c.roll
        if g.kind == .start { c.eye = Vec3(p, z: c.eye.z) } else { c.target = Vec3(p, z: c.target.z) }
        guard c.distance > Tolerance.shortCurve else { return true }
        c.up = Camera3D.levelUp(forward: c.forward)
        c.roll = roll
        tx.update(g.elementID) { $0.view?.camera = c }
        return true
    }
}
