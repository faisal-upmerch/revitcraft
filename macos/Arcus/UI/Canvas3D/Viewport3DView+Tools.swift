import AppKit
import simd
import ArcusGeometry
import ArcusDomain

/// Left-button pointer and editing keys of a 3D viewport, handed to the host first (W2-3D): drawing tools, selection
/// drags and nudges run there on a level work plane. Returning true consumes the event; otherwise the viewport does
/// what it always does (orbit, click-select, camera keys). Middle/right buttons, scroll and gestures never come here.
@MainActor public protocol Viewport3DPointerHandler: AnyObject {
    func viewport3DMouseDown(_ event: NSEvent, at point: CGPoint) -> Bool
    func viewport3DMouseDragged(_ event: NSEvent, at point: CGPoint) -> Bool
    func viewport3DMouseUp(_ event: NSEvent, at point: CGPoint) -> Bool
    func viewport3DMouseMoved(_ event: NSEvent, at point: CGPoint) -> Bool
    func viewport3DKeyDown(_ event: NSEvent) -> Bool
    /// The camera changed (overlays drawn in view space must follow).
    func viewport3DCameraDidChange()
}

/// Ray casting, projection and picking for tools driven from a 3D view (view points: points, origin bottom-left).
extension Viewport3DView {
    /// World ray through a view point.
    public func pointerRay(at point: CGPoint) -> (origin: Vec3, direction: Vec3) {
        let r = cameraFrame(size: bounds.size).ray(at: point, size: bounds.size)
        return (Vec3(r.origin), Vec3(r.direction))
    }

    /// World point → view point; nil behind a perspective camera.
    public func viewPoint(of p: Vec3) -> CGPoint? {
        let cf = cameraFrame(size: bounds.size)
        guard !cf.camera.isPerspective || dot(p.simd - cf.eye, cf.forward) > cf.near else { return nil }
        return cf.project(p.simd, size: bounds.size)
    }

    /// A world segment in view points, clipped to the near plane of a perspective camera; nil when wholly behind it.
    public func viewSegment(_ a: Vec3, _ b: Vec3) -> (CGPoint, CGPoint)? {
        let cf = cameraFrame(size: bounds.size)
        var pa = a.simd, pb = b.simd
        if cf.camera.isPerspective {
            let near = max(cf.near, 1e-3) * 1.01
            let da = dot(pa - cf.eye, cf.forward), db = dot(pb - cf.eye, cf.forward)
            if da < near && db < near { return nil }
            if da < near { pa = pa + (pb - pa) * ((near - da) / (db - da)) }
            if db < near { pb = pb + (pa - pb) * ((near - db) / (da - db)) }
        }
        guard let sa = cf.project(pa, size: bounds.size), let sb = cf.project(pb, size: bounds.size) else { return nil }
        return (sa, sb)
    }

    /// World length of one view point at a world position (screen tolerances on a work plane).
    public func worldPerPoint(at p: Vec3) -> Double {
        cameraFrame(size: bounds.size).worldPerPoint(at: p.simd, viewHeight: Double(bounds.height))
    }

    /// Camera axes in world space (right, up, forward).
    public var cameraAxes: (right: Vec3, up: Vec3, forward: Vec3) {
        let b = CameraFrame.basis(camera)
        return (Vec3(b.right), Vec3(b.up), Vec3(b.forward))
    }

    /// Synchronous GPU pick: the element and world surface point under a view point.
    public func pick(at point: CGPoint) -> (id: ElementID?, position: Vec3?) {
        let r = pickNow(at: point)
        let id: ElementID? = r.elementIndex.flatMap { i in
            guard let s = gpuScene, i >= 0, i < s.elementCount else { return nil }
            return s.elementIDs[i]
        }
        return (id, r.position.map { Vec3($0) })
    }
}
