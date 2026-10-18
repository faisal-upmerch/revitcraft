import Foundation
import ArcusGeometry

// W2-CAM: camera views. A camera is a 3D view with a saved eye, target, projection and lens; it shows in plans as a
// glyph and is navigated with the Blender-style controls in the 3D viewport. The pure math lives here (Domain) so the
// viewport, the parameters and the tests share it.

// MARK: - Lens, basis and roll

extension Camera3D {
    /// Frame height of a 35 mm full-frame sensor (36 × 24 mm). Focal lengths are 35 mm-equivalent: the field of view is
    /// the vertical angle of the camera frame through a lens of that focal length on this sensor.
    public static let sensorHeightMM = 24.0
    /// Focal lengths offered (mm): ultra-wide 4 mm (≈143°) to a 2000 mm telephoto (≈0.7°).
    public static let focalLengthRange: ClosedRange<Double> = 4...2000
    public static let defaultNearClip = 0.1
    public static let defaultFarClip = 100.0

    /// Vertical field of view (radians) of a 35 mm-equivalent focal length in millimetres.
    public static func fieldOfView(focalLength mm: Double) -> Double {
        let f = min(max(mm, focalLengthRange.lowerBound), focalLengthRange.upperBound)
        return 2 * atan(sensorHeightMM / 2 / f)
    }

    /// 35 mm-equivalent focal length (mm) of a vertical field of view (radians).
    public static func focalLength(fieldOfView fov: Double) -> Double {
        sensorHeightMM / 2 / tan(min(max(fov, 1e-4), .pi - 1e-4) / 2)
    }

    /// Lens focal length (mm, 35 mm-equivalent), linked to `fieldOfView`.
    public var focalLength: Double {
        get { Camera3D.focalLength(fieldOfView: fieldOfView) }
        set { fieldOfView = Camera3D.fieldOfView(focalLength: newValue) }
    }

    /// Unit view direction (north when eye and target coincide).
    public var forward: Vec3 {
        let d = target - eye
        return d.length > 1e-12 ? d.normalized : .unitY
    }

    /// Eye-to-target distance.
    public var distance: Double { (target - eye).length }

    /// The camera's right and up axes, robust to `up` being parallel to the view direction (same rules as the viewport:
    /// looking straight down or up, north is at the top of the frame).
    public var basis: (forward: Vec3, right: Vec3, up: Vec3) {
        let f = forward
        var u = up
        if u.length < 1e-12 { u = .unitZ }
        var r = f.cross(u.normalized)
        if r.length < 1e-9 { r = f.cross(abs(f.z) > 0.9 ? .unitY : .unitZ) }
        r = r.normalized
        return (f, r, r.cross(f))
    }

    /// Up vector with no roll: world Z made perpendicular to the view (north when looking straight down or up).
    public static func levelUp(forward f: Vec3) -> Vec3 {
        let z = Vec3.unitZ - f * f.z
        if z.length > 1e-6 { return z.normalized }
        return (Vec3.unitY - f * f.y).normalized
    }

    /// Rotation of the camera about its view direction (radians); positive turns the camera clockwise as seen by the
    /// viewer, so the horizon tilts counter-clockwise in the frame. 0 keeps the horizon level.
    public var roll: Double {
        get {
            let b = basis
            let lu = Camera3D.levelUp(forward: b.forward)
            return atan2(b.forward.dot(lu.cross(b.up)), lu.dot(b.up))
        }
        set {
            let f = forward
            up = CameraMotion.rotate(Camera3D.levelUp(forward: f), axis: f, angle: newValue)
        }
    }

    /// A camera at `eye` looking at `target`, with the given roll.
    public static func lookAt(eye: Vec3, target: Vec3, roll: Double = 0, isPerspective: Bool = true,
                              fieldOfView: Double = 50 * .pi / 180, orthoHeight: Double = 40) -> Camera3D {
        var c = Camera3D(eye: eye, target: target, up: .unitZ, isPerspective: isPerspective, fieldOfView: fieldOfView, orthoHeight: orthoHeight)
        c.roll = roll
        return c
    }

    /// Far clip distance when the far clip plane is on.
    public var effectiveFarClip: Double? { farClipActive == true ? max(farClipDistance ?? Camera3D.defaultFarClip, 0.01) : nil }

    /// Width / height of the camera frame (3:2 when unset).
    public var frameAspect: Double {
        guard let w = cropWidth, let h = cropHeight, w > 0, h > 0 else { return 1.5 }
        return w / h
    }

    /// Switches projection keeping the eye and target (a camera stays where it was placed). Orthographic takes the
    /// height the perspective frame had at the target; perspective keeps the lens.
    public mutating func setPerspective(_ perspective: Bool) {
        guard perspective != isPerspective else { return }
        if !perspective { orthoHeight = max(2 * max(distance, 0.05) * tan(fieldOfView / 2), 0.05) }
        isPerspective = perspective
    }

    /// Same pose, projection and lens within `tolerance` (clip and frame settings are compared exactly).
    public func isAlmostEqual(_ o: Camera3D, tolerance: Double = 1e-6) -> Bool {
        eye.isAlmostEqual(o.eye, tolerance: tolerance) && target.isAlmostEqual(o.target, tolerance: tolerance)
            && (up.normalized - o.up.normalized).length <= tolerance && isPerspective == o.isPerspective
            && abs(fieldOfView - o.fieldOfView) <= tolerance && abs(orthoHeight - o.orthoHeight) <= tolerance
            && nearClip == o.nearClip && farClipActive == o.farClipActive && farClipDistance == o.farClipDistance
            && cropWidth == o.cropWidth && cropHeight == o.cropHeight
    }
}

// MARK: - Navigation math

/// Pure camera motions used by the 3D viewport's navigation (orbit, pan, dolly, zoom, fly) and by camera editing.
/// Angles are radians, distances meters. Every motion returns a new camera and keeps clip and frame settings.
public enum CameraMotion {
    /// Rotates `v` about the unit `axis` by `angle` (Rodrigues).
    public static func rotate(_ v: Vec3, axis: Vec3, angle: Double) -> Vec3 {
        let c = cos(angle), s = sin(angle)
        return v * c + axis.cross(v) * s + axis * (axis.dot(v) * (1 - c))
    }

    /// Elevation of the view direction above the horizon, looking down positive (radians, −π/2…π/2).
    public static func elevation(_ c: Camera3D) -> Double { asin(max(-1, min(1, -c.forward.z))) }

    /// Turntable orbit about `pivot`: `yaw` about world Z (positive turns the camera counter-clockwise seen from above),
    /// then `pitch` about the camera's right axis (positive raises the camera to look further down). The elevation stays
    /// within ±90° and the roll is kept.
    public static func orbit(_ c: Camera3D, yaw: Double, pitch: Double, pivot: Vec3) -> Camera3D {
        var r = c
        let roll = c.roll
        var eye = pivot + rotate(c.eye - pivot, axis: .unitZ, angle: yaw)
        var target = pivot + rotate(c.target - pivot, axis: .unitZ, angle: yaw)
        var up = rotate(c.basis.up, axis: .unitZ, angle: yaw)
        r.eye = eye; r.target = target; r.up = up
        let b = r.basis
        // Tilt about the level right axis (horizontal), so a rolled camera still orbits like a turntable.
        let h = b.forward.cross(.unitZ)
        let axis = h.length > 1e-6 ? h.normalized : b.right
        let el = elevation(r)
        let p = max(-Double.pi / 2, min(Double.pi / 2, el + pitch)) - el
        eye = pivot + rotate(eye - pivot, axis: axis, angle: -p)
        target = pivot + rotate(target - pivot, axis: axis, angle: -p)
        up = rotate(b.up, axis: axis, angle: -p)
        r.eye = eye; r.target = target; r.up = up
        let f = r.forward
        if abs(f.z) < 0.9995 { r.up = Camera3D.levelUp(forward: f); r.roll = roll }
        return r
    }

    /// Moves eye and target together by `dx` along the camera's right axis and `dy` along its up axis (meters).
    public static func pan(_ c: Camera3D, dx: Double, dy: Double) -> Camera3D {
        let b = c.basis
        let d = b.right * dx + b.up * dy
        var r = c
        r.eye = c.eye + d; r.target = c.target + d
        return r
    }

    /// Dolly by `factor` (> 1 moves closer): perspective cameras move the eye toward the target, pushing the target
    /// ahead once it is closer than `minDistance`; orthographic cameras shrink the view height.
    public static func dolly(_ c: Camera3D, factor: Double, minDistance: Double = 0.05) -> Camera3D {
        guard factor.isFinite, factor > 0 else { return c }
        var r = c
        if !c.isPerspective {
            r.orthoHeight = min(max(c.orthoHeight / factor, 0.05), 1e6)
            return r
        }
        let f = c.forward
        let d = max(c.distance, minDistance)
        let nd = d / factor
        if nd < minDistance {
            // Dolly through: the eye keeps moving forward by what the zoom asked for, the target stays ahead.
            let travel = d - nd
            r.eye = c.eye + f * travel
            r.target = r.eye + f * minDistance
        } else {
            r.eye = c.target - f * min(nd, 1e6)
        }
        return r
    }

    /// Perspective zoom toward a world point (the point under the pointer): the eye moves `1 − 1/factor` of the way
    /// there (at most 90 %), the view direction is unchanged and the target stays at the same relative depth.
    public static func zoom(_ c: Camera3D, factor: Double, toward p: Vec3) -> Camera3D {
        guard factor.isFinite, factor > 0 else { return c }
        guard c.isPerspective else { return dolly(c, factor: factor) }
        let f = c.forward
        let focal = max(c.distance, 0.05)
        let t = min(1 - 1 / factor, 0.9)
        var r = c
        r.eye = c.eye + (p - c.eye) * t
        r.target = r.eye + f * max(focal * (1 - t), 0.05)
        return r
    }

    /// First-person look and move (fly mode): turns the view about the eye by `yaw` (about world Z, positive turns left)
    /// and `pitch` (positive looks up, clamped to ±89°), then moves by `move` in camera terms: x right, y forward
    /// (along the view direction), z world up. The eye-to-target distance and roll are kept.
    public static func fly(_ c: Camera3D, yaw: Double = 0, pitch: Double = 0, move: Vec3 = .zero) -> Camera3D {
        var r = c
        let d = max(c.distance, 0.05)
        let roll = c.roll
        var f = rotate(c.forward, axis: .unitZ, angle: yaw)
        let limit = 89 * Double.pi / 180
        let el = asin(max(-1, min(1, f.z)))
        let p = max(-limit, min(limit, el + pitch)) - el
        if abs(p) > 0 {
            let right = f.cross(.unitZ).length > 1e-9 ? f.cross(.unitZ).normalized : c.basis.right
            f = rotate(f, axis: right, angle: p).normalized
        }
        r.target = c.eye + f * d
        r.up = Camera3D.levelUp(forward: f)
        r.roll = roll
        let b = r.basis
        let delta = b.right * move.x + f * move.y + Vec3.unitZ * move.z
        r.eye = r.eye + delta
        r.target = r.target + delta
        return r
    }

    /// Points the camera at `p` from where it stands (keeps roll).
    public static func look(_ c: Camera3D, at p: Vec3) -> Camera3D {
        guard (p - c.eye).length > 1e-9 else { return c }
        var r = c
        let roll = c.roll
        r.target = p
        r.up = Camera3D.levelUp(forward: r.forward)
        r.roll = roll
        return r
    }

    /// "Align Camera to View": the saved camera takes the view's pose, projection and lens; its clip and frame settings
    /// stay. A perspective view keeps the camera's target distance when the view's is degenerate.
    public static func align(_ saved: Camera3D, to view: Camera3D) -> Camera3D {
        var r = saved
        r.eye = view.eye; r.target = view.target; r.up = view.up
        r.isPerspective = view.isPerspective; r.fieldOfView = view.fieldOfView; r.orthoHeight = view.orthoHeight
        if r.distance < 1e-6 { r.target = r.eye + view.forward * max(saved.distance, 1) }
        return r
    }
}

// MARK: - Camera views in the model

extension Element {
    /// A camera view: a 3D view placed as a camera (from a plan or from a 3D view) or any perspective 3D view.
    public var isCameraView: Bool {
        guard let v = view, v.kind == .threeD, let c = v.camera else { return false }
        return c.isPerspective || levelID != nil
    }
}

extension BIMModel {
    /// Camera views sorted by name.
    public var cameraViews: [Element] {
        views.filter(\.isCameraView).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension CameraViews {
    /// Default camera frame on paper (3:2, like a 35 mm frame).
    public static let defaultCropWidth = 0.24
    public static let defaultCropHeight = 0.16

    /// `base`, or `base 2`, `base 3`, … — unique among 3D view names.
    public static func uniqueName(_ base: String, _ model: BIMModel) -> String {
        let names = Set(model.views.filter { $0.view?.kind == .threeD }.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// The level a camera at height `z` belongs to: the highest level at or below it (the lowest level otherwise).
    public static func level(forEyeZ z: Double, _ model: BIMModel) -> ElementID? {
        let levels = model.levels
        return levels.last(where: { ($0.level?.elevation ?? 0) <= z + 1e-6 })?.id ?? levels.first?.id
    }

    /// Creates a camera view with `camera` ("Create Camera from View"); its level is the one the eye stands on.
    @discardableResult
    public static func create(camera: Camera3D, name: String? = nil, from template: ViewData? = nil, in tx: TransactionContext) -> ElementID {
        var v = template ?? ViewData(kind: .threeD)
        v.kind = .threeD
        v.camera = camera
        v.cropActive = true
        if v.phaseID == nil { v.phaseID = tx.model.latestPhase?.id }
        let level = level(forEyeZ: camera.eye.z, tx.model)
        return tx.create(.views, name: uniqueName(name ?? nextName(tx.model), tx.model), data: .view(v), levelID: level)
    }

    /// Duplicates a camera view (same camera, graphics and level) as "<name> Copy".
    @discardableResult
    public static func duplicate(_ id: ElementID, in tx: TransactionContext) throws -> ElementID {
        guard let e = tx.model[id], e.isCameraView, let v = e.view else { throw TransactionError("Choose a camera to duplicate.") }
        return tx.create(.views, name: uniqueName(e.name + " Copy", tx.model), data: .view(v), levelID: e.levelID)
    }

    /// Replaces the pose, projection and lens of a camera view (clip and frame settings are kept).
    public static func setCamera(_ camera: Camera3D, of id: ElementID, in tx: TransactionContext) throws {
        guard let e = tx.model[id], let old = e.view?.camera else { throw TransactionError("The camera no longer exists.") }
        guard camera.distance > Tolerance.shortCurve || !camera.isPerspective else { throw TransactionError("The eye and target can't coincide.") }
        let c = CameraMotion.align(old, to: camera)
        tx.update(id) { $0.view?.camera = c }
    }
}
