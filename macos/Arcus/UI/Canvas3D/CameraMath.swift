import Foundation
import simd
import ArcusGeometry
import ArcusDomain

nonisolated extension Vec3 {
    var simd: SIMD3<Double> { SIMD3(x, y, z) }
    init(_ s: SIMD3<Double>) { self.init(s.x, s.y, s.z) }
    var float3: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}

nonisolated extension RGBColor {
    /// sRGB components → linear-light float4 (alpha unchanged).
    var linear: SIMD4<Float> {
        func l(_ c: Double) -> Float {
            let c = max(0, min(1, c))
            return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return SIMD4(l(r), l(g), l(b), Float(a))
    }
}

/// Rotates `v` around the unit `axis` by `angle` radians (Rodrigues).
nonisolated func rotateVector(_ v: SIMD3<Double>, axis: SIMD3<Double>, angle: Double) -> SIMD3<Double> {
    let c = cos(angle), s = sin(angle)
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1 - c)
}

/// Camera basis and matrices for one frame. All world quantities are Double; GPU matrices are relative to `origin`
/// (the scene center) so Float32 vertex positions keep precision far from the project origin.
nonisolated struct CameraFrame {
    let camera: Camera3D
    let origin: SIMD3<Double>
    let eye: SIMD3<Double>
    let target: SIMD3<Double>
    let forward: SIMD3<Double>
    let right: SIMD3<Double>
    let up: SIMD3<Double>
    let aspect: Double
    let near: Double
    let far: Double
    /// Reversed-Z perspective depth terms: ndc.z = depthB / distance − depthA (depthA = 0 for an infinite far plane).
    let depthA: Double
    let depthB: Double
    let view: simd_double4x4
    let projection: simd_double4x4
    let viewProjection: simd_double4x4
    let inverseViewProjection: simd_double4x4

    /// Basis vectors for a camera, robust to `up` being parallel to the view direction.
    static func basis(_ c: Camera3D) -> (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>) {
        var f = c.target.simd - c.eye.simd
        if simd_length(f) < 1e-12 { f = SIMD3(0, 1, 0) }
        f = simd_normalize(f)
        var u = c.up.simd
        if simd_length(u) < 1e-12 { u = SIMD3(0, 0, 1) }
        var r = cross(f, simd_normalize(u))
        if simd_length(r) < 1e-9 {
            // Up parallel to forward: pick a stable fallback (north for top/bottom views).
            r = cross(f, abs(f.z) > 0.9 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1))
        }
        r = simd_normalize(r)
        let uu = cross(r, f)
        return (f, r, uu)
    }

    /// - Parameters:
    ///   - depthBounds: world box used to choose the near/far planes (scene ∪ overlays).
    init(camera: Camera3D, aspect: Double, origin: SIMD3<Double>, depthBounds: Box3) {
        self.camera = camera
        self.origin = origin
        self.aspect = max(aspect, 1e-6)
        eye = camera.eye.simd
        target = camera.target.simd
        let b = CameraFrame.basis(camera)
        forward = b.forward; right = b.right; up = b.up

        // Near/far from the depth bounds along the view direction.
        var dMin = Double.infinity, dMax = -Double.infinity
        if !depthBounds.isEmpty {
            for c in depthBounds.corners {
                let d = dot(c.simd - eye, forward)
                dMin = Swift.min(dMin, d); dMax = Swift.max(dMax, d)
            }
        } else {
            dMin = 0.1; dMax = 100
        }
        let span = Swift.max(dMax - dMin, 1)
        // W2-CAM: a camera's near clip and far clip plane replace the automatic planes.
        let farClip = camera.effectiveFarClip
        var n: Double, fz: Double
        if camera.isPerspective {
            n = camera.nearClip.map { Swift.max($0, 0.001) } ?? Swift.max(0.01, Swift.min(Swift.max(dMin * 0.5, 0.02), 1.0))
            fz = .infinity
            if let fc = farClip { fz = Swift.max(fc, n * 1.001) }
        } else {
            n = camera.nearClip ?? (dMin - span * 0.05 - 1)
            fz = dMax + span * 0.05 + 1
            if let fc = farClip { fz = Swift.max(fc, n + 0.001) }
        }
        near = n; far = fz
        if fz.isFinite && camera.isPerspective {
            depthA = n / (fz - n); depthB = n * fz / (fz - n)
        } else {
            depthA = 0; depthB = n
        }

        // View matrix relative to origin.
        let e = eye - origin
        let r = right, u = up, f = forward
        view = simd_double4x4(rows: [
            SIMD4(r.x, r.y, r.z, -dot(r, e)),
            SIMD4(u.x, u.y, u.z, -dot(u, e)),
            SIMD4(-f.x, -f.y, -f.z, dot(f, e)),
            SIMD4(0, 0, 0, 1),
        ])
        if camera.isPerspective {
            // Reversed-Z, infinite far plane: ndc.z = near / distance.
            let fy = 1 / tan(Swift.max(0.01, Swift.min(camera.fieldOfView, 3.0)) / 2)
            projection = simd_double4x4(columns: (
                SIMD4(fy / self.aspect, 0, 0, 0),
                SIMD4(0, fy, 0, 0),
                SIMD4(0, 0, depthA, -1),
                SIMD4(0, 0, depthB, 0)))
        } else {
            let h = Swift.max(camera.orthoHeight, 1e-4)
            let w = h * self.aspect
            // Reversed-Z orthographic: ndc.z = (z + far) / (far - near) for view z ∈ [-far, -near].
            let dz = far - near
            projection = simd_double4x4(columns: (
                SIMD4(2 / w, 0, 0, 0),
                SIMD4(0, 2 / h, 0, 0),
                SIMD4(0, 0, 1 / dz, 0),
                SIMD4(0, 0, far / dz, 1)))
        }
        viewProjection = projection * view
        inverseViewProjection = viewProjection.inverse
    }

    var viewProjectionFloat: simd_float4x4 {
        let m = viewProjection
        func c(_ v: SIMD4<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
        return simd_float4x4(columns: (c(m.columns.0), c(m.columns.1), c(m.columns.2), c(m.columns.3)))
    }

    /// World point → normalized device coordinates (x, y in [-1, 1], z depth) and clip w.
    func ndc(_ p: SIMD3<Double>) -> (SIMD3<Double>, Double) {
        let c = viewProjection * SIMD4(p - origin, 1)
        let w = c.w
        return (SIMD3(c.x / w, c.y / w, c.z / w), w)
    }

    /// World point → view coordinates (points, origin bottom-left) for a view of `size`.
    func project(_ p: SIMD3<Double>, size: CGSize) -> CGPoint? {
        let (n, w) = ndc(p)
        guard w > 1e-9 || !camera.isPerspective else { return nil }
        return CGPoint(x: (n.x * 0.5 + 0.5) * size.width, y: (n.y * 0.5 + 0.5) * size.height)
    }

    /// Ray through a view point (points, origin bottom-left).
    func ray(at point: CGPoint, size: CGSize) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        let nx = Double(point.x / Swift.max(size.width, 1)) * 2 - 1
        let ny = Double(point.y / Swift.max(size.height, 1)) * 2 - 1
        if camera.isPerspective {
            let fy = tan(camera.fieldOfView / 2)
            let d = simd_normalize(forward + right * (nx * fy * aspect) + up * (ny * fy))
            return (eye, d)
        } else {
            let h = camera.orthoHeight, w = h * aspect
            let o = eye + right * (nx * w / 2) + up * (ny * h / 2)
            return (o, forward)
        }
    }

    /// World size of one view point at a world position (for screen-constant sizing).
    func worldPerPoint(at p: SIMD3<Double>, viewHeight: Double) -> Double {
        if camera.isPerspective {
            let d = Swift.max(dot(p - eye, forward), near)
            return 2 * d * tan(camera.fieldOfView / 2) / Swift.max(viewHeight, 1)
        }
        return camera.orthoHeight / Swift.max(viewHeight, 1)
    }
}

nonisolated enum CameraFit {
    /// Returns a camera looking along `forward` (with `up`) that frames `box` in a view of `aspect`.
    static func fit(_ box: Box3, forward: SIMD3<Double>, up: SIMD3<Double>, base: Camera3D, aspect: Double, margin: Double = 1.08) -> Camera3D {
        guard !box.isEmpty else { return base }
        let f = simd_normalize(forward)
        var r = cross(f, simd_normalize(up))
        if simd_length(r) < 1e-9 { r = cross(f, SIMD3(0, 1, 0)) }
        r = simd_normalize(r)
        let u = cross(r, f)
        let center = box.center.simd
        let aspect = Swift.max(aspect, 1e-3)
        var cam = base
        cam.up = Vec3(u)
        // Extents of the box in camera axes.
        var xMin = Double.infinity, xMax = -Double.infinity, yMin = Double.infinity, yMax = -Double.infinity, zMax = -Double.infinity
        for c in box.corners {
            let d = c.simd - center
            let x = dot(d, r), y = dot(d, u), z = dot(d, f)
            xMin = Swift.min(xMin, x); xMax = Swift.max(xMax, x); yMin = Swift.min(yMin, y); yMax = Swift.max(yMax, y)
            zMax = Swift.max(zMax, -z)
        }
        let cx = (xMin + xMax) / 2, cy = (yMin + yMax) / 2
        let focus = center + r * cx + u * cy
        let halfW = Swift.max((xMax - xMin) / 2, 0.05), halfH = Swift.max((yMax - yMin) / 2, 0.05)
        if base.isPerspective {
            let tanY = tan(base.fieldOfView / 2), tanX = tanY * aspect
            var dist = 0.0
            for c in box.corners {
                let d = c.simd - focus
                let x = abs(dot(d, r)), y = abs(dot(d, u)), z = dot(d, f)
                // Point at depth (dist + z) must satisfy |x| <= (dist + z) tanX, |y| <= (dist + z) tanY.
                dist = Swift.max(dist, x * margin / tanX - z, y * margin / tanY - z)
            }
            dist = Swift.max(dist, 0.5)
            cam.eye = Vec3(focus - f * dist)
            cam.target = Vec3(focus)
            // Keep a sensible ortho height too so switching projection keeps framing.
            cam.orthoHeight = Swift.max(halfH, halfW / aspect) * 2 * margin
        } else {
            cam.orthoHeight = Swift.max(halfH, halfW / aspect) * 2 * margin
            let dist = Swift.max(zMax, 1) + Swift.max(halfW, halfH) + 5
            cam.eye = Vec3(focus - f * dist)
            cam.target = Vec3(focus)
        }
        return cam
    }
}

/// Ease-out cubic.
nonisolated func easeOut(_ t: Double) -> Double { let u = 1 - Swift.max(0, Swift.min(1, t)); return 1 - u * u * u }

/// Interpolates cameras by orbiting the view direction (slerp) and lerping distance/target.
nonisolated func interpolate(_ a: Camera3D, _ b: Camera3D, t: Double) -> Camera3D {
    if t <= 0 { return a }
    if t >= 1 { return b }
    let fa = a.target.simd - a.eye.simd, fb = b.target.simd - b.eye.simd
    let la = simd_length(fa), lb = simd_length(fb)
    let da = la > 0 ? fa / la : SIMD3(0, 1, 0), db = lb > 0 ? fb / lb : SIMD3(0, 1, 0)
    let target = a.target.simd + (b.target.simd - a.target.simd) * t
    let dist = la + (lb - la) * t
    let dir = slerp(da, db, t)
    var c = b
    c.target = Vec3(target)
    c.eye = Vec3(target - dir * dist)
    let ua = a.up.simd, ub = b.up.simd
    var u = slerp(simd_length(ua) > 0 ? simd_normalize(ua) : SIMD3(0, 0, 1), simd_length(ub) > 0 ? simd_normalize(ub) : SIMD3(0, 0, 1), t)
    if simd_length(u) < 1e-6 { u = ub }
    c.up = Vec3(u)
    c.orthoHeight = a.orthoHeight + (b.orthoHeight - a.orthoHeight) * t
    c.fieldOfView = a.fieldOfView + (b.fieldOfView - a.fieldOfView) * t
    return c
}

nonisolated func slerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
    let d = Swift.max(-1, Swift.min(1, dot(a, b)))
    if d > 0.9995 { return simd_normalize(a + (b - a) * t) }
    if d < -0.9995 {
        // Opposite: rotate through any perpendicular axis.
        var axis = cross(a, SIMD3(0, 0, 1))
        if simd_length(axis) < 1e-6 { axis = cross(a, SIMD3(1, 0, 0)) }
        return rotateVector(a, axis: simd_normalize(axis), angle: .pi * t)
    }
    let theta = acos(d) * t
    let rel = simd_normalize(b - a * d)
    return a * cos(theta) + rel * sin(theta)
}
