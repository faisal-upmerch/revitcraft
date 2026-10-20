import Foundation
import ArcusGeometry
import ArcusDomain

// FMG4: where a piece dragged onto a 3D view lands: on the view's work plane (Work Plane ▸ Set: a reference plane or
// a picked face), as components drawn in 3D are; a level otherwise. On a horizontal work plane above the level (a
// table top, a reference plane at counter height) the piece sits on it, its Elevation from Level the plane's height;
// a vertical one (a wall face) places it on the level where the pointer meets the plane.

extension WorkPlane3D {
    /// The plan point and the elevation from the level of a piece dropped at a pointer sample, or nil when the pointer
    /// meets neither the work plane nor the level.
    public static func dropPlacement(_ s: PointerSample, workPlane: WorkPlaneFrame?, levelZ: Double) -> (point: Vec2, offset: Double)? {
        if let w = workPlane {
            let n = w.normal
            let den = s.direction.dot(n)
            if abs(den) > 1e-9 {
                let t = (w.origin - s.origin).dot(n) / den
                if t > 0, t.isFinite {
                    let p = s.origin + s.direction * t
                    return (p.xy, w.isHorizontal ? w.origin.z - levelZ : 0)
                }
            }
            if w.isHorizontal, let q = s.pickedPoint { return (q.xy, w.origin.z - levelZ) }
        }
        return planPoint(s, planeZ: levelZ).map { ($0.xy, 0) }
    }
}
