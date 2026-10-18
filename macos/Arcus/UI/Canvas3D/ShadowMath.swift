import Foundation
import simd
import ArcusGeometry

/// Directional (sun) shadow-map projection.
nonisolated enum ShadowMath {
    /// Orthographic light projection that tightly encloses `bounds` (world) seen from the sun.
    ///
    /// - Parameters:
    ///   - towardLight: unit vector from the scene toward the sun (world).
    ///   - bounds: world box of the shadow casters and receivers (scene ∩ section box).
    ///   - origin: the scene origin; the matrix maps origin-relative positions like the vertex buffers.
    /// - Returns: the matrix (xy → [-1, 1], z → [0, 1] with 0 nearest the sun) and the world size of the covered
    ///   square side, or nil for an empty box.
    static func lightMatrix(towardLight: SIMD3<Double>, bounds: Box3, origin: SIMD3<Double>) -> (matrix: simd_float4x4, extent: SIMD3<Double>)? {
        guard !bounds.isEmpty, simd_length(towardLight) > 1e-9 else { return nil }
        let f = -simd_normalize(towardLight)
        let worldUp: SIMD3<Double> = abs(f.z) > 0.99 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
        let r = simd_normalize(cross(f, worldUp))
        let u = cross(r, f)
        var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
        for c in bounds.corners {
            let p = c.simd - origin
            let q = SIMD3(dot(p, r), dot(p, u), dot(p, f))
            lo = simd_min(lo, q); hi = simd_max(hi, q)
        }
        // Pad so PCF taps and the depth range never clip at the border.
        let size = hi - lo
        let pad = SIMD3(Swift.max(size.x, size.y) * 0.02 + 0.05, Swift.max(size.x, size.y) * 0.02 + 0.05, size.z * 0.02 + 0.05)
        lo -= pad; hi += pad
        let e = hi - lo
        let sx = 2 / e.x, sy = 2 / e.y, sz = 1 / e.z
        // Rows: x' = sx (p·r) - sx (lo.x + hi.x)/2, y' likewise, z' = sz (p·f - lo.z).
        let m = simd_double4x4(rows: [
            SIMD4(r.x * sx, r.y * sx, r.z * sx, -(lo.x + hi.x) / 2 * sx),
            SIMD4(u.x * sy, u.y * sy, u.z * sy, -(lo.y + hi.y) / 2 * sy),
            SIMD4(f.x * sz, f.y * sz, f.z * sz, -lo.z * sz),
            SIMD4(0, 0, 0, 1),
        ])
        func c(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
        return (simd_float4x4(columns: (c(m.columns.0), c(m.columns.1), c(m.columns.2), c(m.columns.3))), e)
    }

    /// Camera-relative key light used when no sun is set: above and to the viewer's left, tied to the camera azimuth
    /// so both visible sides of a box read differently.
    static func cameraKeyLight(forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>,
                               azimuthDegrees: Double = 40, altitudeDegrees: Double = 52) -> SIMD3<Double> {
        var back = SIMD3<Double>(-forward.x, -forward.y, 0)
        if simd_length(back) < 1e-3 { back = SIMD3(-up.x, -up.y, 0) }
        if simd_length(back) < 1e-3 { back = SIMD3(0, -1, 0) }
        back = simd_normalize(back)
        let leftH = simd_normalize(SIMD3<Double>(-right.x, -right.y, 0) + SIMD3(1e-9, 0, 0))
        let az = azimuthDegrees * .pi / 180, el = altitudeDegrees * .pi / 180
        let horiz = simd_normalize(back * cos(az) + leftH * sin(az))
        return simd_normalize(horiz * cos(el) + SIMD3(0, 0, sin(el)))
    }
}
