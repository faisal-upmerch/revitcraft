import AppKit
import simd
import ArcusGeometry
import ArcusDomain

// BL-SITE (ARCUS-031): orientation cube edges and bottom corners orient the camera to arbitrary directions.

/// Camera up vector for a view-from direction: north (+Y) when looking straight up or down, else world up.
nonisolated enum OrientationCubeMath {
    static func up(forViewFrom d: SIMD3<Double>) -> SIMD3<Double> {
        let n = simd_normalize(d)
        return abs(n.z) > 0.999 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
    }
}

extension Viewport3DView {
    /// Looks at the model (or the section box) from direction `dir` (from the model toward the camera), framing it.
    public func orient(toDirection dir: Vec3, animated: Bool = true) {
        guard dir.lengthSquared > 1e-12 else { return }
        let d = dir.normalized.simd
        var box = gpuScene?.bounds ?? .empty
        if let sb = sectionBox, !box.isEmpty {
            let i = Box3(min: Vec3(max(box.min.x, sb.min.x), max(box.min.y, sb.min.y), max(box.min.z, sb.min.z)),
                         max: Vec3(min(box.max.x, sb.max.x), min(box.max.y, sb.max.y), min(box.max.z, sb.max.z)))
            if !i.isEmpty { box = i }
        }
        if box.isEmpty { box = Box3(min: Vec3(-5, -5, 0), max: Vec3(5, 5, 5)) }
        let c = CameraFit.fit(box, forward: -d, up: OrientationCubeMath.up(forViewFrom: d), base: camera, aspect: viewAspect)
        setCamera(c, animated: animated)
    }
}
