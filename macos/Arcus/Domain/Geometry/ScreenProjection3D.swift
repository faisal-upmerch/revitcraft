import Foundation

/// S3D: a 3D view's camera as a pure mapping between world points and view points (points, origin bottom-left), the
/// same mapping the Metal viewport draws with. Screen-space snapping and CPU ray casts use it without the renderer.
public struct ScreenProjection3D: Sendable, Hashable {
    public var eye: Vec3
    /// Unit view direction.
    public var forward: Vec3
    /// Unit screen right and up in world space.
    public var right: Vec3
    public var up: Vec3
    public var isPerspective: Bool
    /// Vertical field of view (radians) of a perspective camera.
    public var fieldOfView: Double
    /// Height of the view volume (meters) of a parallel camera.
    public var orthoHeight: Double
    /// View size in points.
    public var size: Vec2
    /// Near clip distance of a perspective camera.
    public var near: Double

    public init(eye: Vec3, forward: Vec3, right: Vec3, up: Vec3, isPerspective: Bool, fieldOfView: Double, orthoHeight: Double,
                size: Vec2, near: Double) {
        self.eye = eye; self.forward = forward; self.right = right; self.up = up
        self.isPerspective = isPerspective; self.fieldOfView = fieldOfView; self.orthoHeight = orthoHeight
        self.size = size; self.near = near
    }

    /// A camera at `eye` looking at `target` (the viewport's basis: right = forward × up).
    public static func looking(from eye: Vec3, at target: Vec3, up: Vec3 = .unitZ, perspective: Bool, fieldOfView: Double = 50 * .pi / 180,
                               orthoHeight: Double = 10, size: Vec2 = Vec2(800, 600), near: Double = 0.05) -> ScreenProjection3D {
        let f = (target - eye).normalized
        var r = f.cross(up.normalized)
        if r.length < 1e-9 { r = f.cross(abs(f.z) > 0.9 ? .unitY : .unitZ) }
        r = r.normalized
        return ScreenProjection3D(eye: eye, forward: f, right: r, up: r.cross(f), isPerspective: perspective, fieldOfView: fieldOfView,
                                  orthoHeight: orthoHeight, size: size, near: near)
    }

    public var aspect: Double { size.x / max(size.y, 1) }

    /// Distance of `p` in front of the eye along the view direction.
    @inlinable public func depth(of p: Vec3) -> Double { (p - eye).dot(forward) }

    /// World point → view point; nil behind the near plane of a perspective camera.
    public func project(_ p: Vec3) -> Vec2? {
        let v = p - eye
        let d = v.dot(forward)
        let nx: Double, ny: Double
        if isPerspective {
            guard d > max(near, 1e-9) else { return nil }
            let t = tan(fieldOfView / 2)
            nx = v.dot(right) / (d * t * aspect)
            ny = v.dot(up) / (d * t)
        } else {
            let h = max(orthoHeight, 1e-9)
            nx = v.dot(right) / (h * aspect / 2)
            ny = v.dot(up) / (h / 2)
        }
        return Vec2((nx * 0.5 + 0.5) * size.x, (ny * 0.5 + 0.5) * size.y)
    }

    /// World ray through a view point.
    public func ray(at s: Vec2) -> (origin: Vec3, direction: Vec3) {
        let nx = s.x / max(size.x, 1) * 2 - 1
        let ny = s.y / max(size.y, 1) * 2 - 1
        if isPerspective {
            let t = tan(fieldOfView / 2)
            return (eye, (forward + right * (nx * t * aspect) + up * (ny * t)).normalized)
        }
        let h = orthoHeight, w = h * aspect
        return (eye + right * (nx * w / 2) + up * (ny * h / 2), forward)
    }

    /// World length of one view point at `p`'s depth.
    public func worldPerPoint(at p: Vec3) -> Double { worldPerPoint(atDepth: depth(of: p)) }

    public func worldPerPoint(atDepth d: Double) -> Double {
        if isPerspective { return 2 * max(d, near) * tan(fieldOfView / 2) / max(size.y, 1) }
        return orthoHeight / max(size.y, 1)
    }

    /// A segment clipped to the near plane of a perspective camera (parallel cameras keep it); nil when wholly behind.
    public func clippedToNear(_ a: Vec3, _ b: Vec3) -> (Vec3, Vec3)? {
        guard isPerspective else { return (a, b) }
        let n = max(near, 1e-3) * 1.01
        let da = depth(of: a), db = depth(of: b)
        if da < n && db < n { return nil }
        var pa = a, pb = b
        if da < n { pa = a + (b - a) * ((n - da) / (db - da)) }
        if db < n { pb = b + (a - b) * ((n - db) / (da - db)) }
        return (pa, pb)
    }

    /// True when a sphere may cover view points within `radius` points of `pointer` (conservative: spheres reaching the
    /// near plane always pass).
    public func sphereMayCover(center c: Vec3, radius rr: Double, pointer: Vec2, within radius: Double) -> Bool {
        let d = depth(of: c)
        if isPerspective {
            if d + rr <= near { return false }
            if d - rr <= max(near, 1e-6) * 2 { return true }
        }
        guard let s = project(c) else { return true }
        let onScreen = rr / max(worldPerPoint(atDepth: d - rr), 1e-12)
        return s.distance(to: pointer) <= onScreen + radius
    }

    /// The direction from `p` toward the viewer and how far the viewer is along it (parallel cameras: unbounded).
    public func towardViewer(from p: Vec3) -> (direction: Vec3, distance: Double) {
        guard isPerspective else { return (-forward, .infinity) }
        let v = eye - p
        let l = v.length
        return (l > 1e-12 ? v / l : -forward, max(0, l - near))
    }
}

/// S3D: closest points and ray hits used by 3D snapping.
public enum Intersect3D {
    /// The point of segment `a`–`b` closest to the line through `o` along unit `d`, as the segment parameter in [0, 1].
    public static func segmentParameter(closestToLine o: Vec3, _ d: Vec3, _ a: Vec3, _ b: Vec3) -> Double {
        let u = b - a
        let w = a - o
        let uu = u.dot(u), ud = u.dot(d), dd = d.dot(d)
        let uw = u.dot(w), dw = d.dot(w)
        let den = uu * dd - ud * ud
        guard uu > 1e-18 else { return 0 }
        let t = den > 1e-14 * uu * dd ? (ud * dw - dd * uw) / den : -uw / uu
        return min(max(t, 0), 1)
    }

    /// Closest points between segments `a0`–`a1` and `b0`–`b1`: their parameters and the gap between them.
    public static func closestPoints(_ a0: Vec3, _ a1: Vec3, _ b0: Vec3, _ b1: Vec3) -> (s: Double, t: Double, gap: Double) {
        let d1 = a1 - a0, d2 = b1 - b0, r = a0 - b0
        let a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r)
        var s = 0.0, t = 0.0
        if a <= 1e-18 && e <= 1e-18 { return (0, 0, a0.distance(to: b0)) }
        if a <= 1e-18 {
            t = min(max(f / e, 0), 1)
        } else {
            let c = d1.dot(r)
            if e <= 1e-18 {
                s = min(max(-c / a, 0), 1)
            } else {
                let b = d1.dot(d2)
                let den = a * e - b * b
                s = den > 1e-14 * a * e ? min(max((b * f - c * e) / den, 0), 1) : 0
                t = (b * s + f) / e
                if t < 0 { t = 0; s = min(max(-c / a, 0), 1) } else if t > 1 { t = 1; s = min(max((b - c) / a, 0), 1) }
            }
        }
        return (s, t, (a0 + d1 * s).distance(to: b0 + d2 * t))
    }

    /// Two-sided ray/triangle hit (Möller–Trumbore): the ray parameter, or nil.
    @inlinable public static func ray(_ o: Vec3, _ d: Vec3, triangle a: Vec3, _ b: Vec3, _ c: Vec3) -> Double? {
        let e1 = b - a, e2 = c - a
        let p = d.cross(e2)
        let det = e1.dot(p)
        guard abs(det) > 1e-14 else { return nil }
        let inv = 1 / det
        let s = o - a
        let u = s.dot(p) * inv
        guard u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        let q = s.cross(e1)
        let v = d.dot(q) * inv
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { return nil }
        let t = e2.dot(q) * inv
        return t.isFinite ? t : nil
    }

    /// True when the ray `o + t d`, 0 ≤ t ≤ tMax, passes through `box`.
    public static func ray(_ o: Vec3, _ d: Vec3, hits box: Box3, tMax: Double) -> Bool {
        guard !box.isEmpty else { return false }
        var lo = 0.0, hi = tMax
        for (oc, dc, mn, mx) in [(o.x, d.x, box.min.x, box.max.x), (o.y, d.y, box.min.y, box.max.y), (o.z, d.z, box.min.z, box.max.z)] {
            if abs(dc) < 1e-15 {
                if oc < mn || oc > mx { return false }
                continue
            }
            var t0 = (mn - oc) / dc, t1 = (mx - oc) / dc
            if t0 > t1 { swap(&t0, &t1) }
            lo = max(lo, t0); hi = min(hi, t1)
            if lo > hi { return false }
        }
        return true
    }
}
