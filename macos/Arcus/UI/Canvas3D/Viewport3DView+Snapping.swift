import AppKit
import ArcusGeometry
import ArcusDomain

// S3D: the camera of the current frame for screen-space snapping (see ArcusApplication's Snapping3D).
extension Viewport3DView {
    /// The world ↔ view-point mapping the viewport draws with now (view points, origin bottom-left).
    public var screenProjection: ScreenProjection3D {
        let cf = cameraFrame(size: bounds.size)
        return ScreenProjection3D(eye: Vec3(cf.eye), forward: Vec3(cf.forward), right: Vec3(cf.right), up: Vec3(cf.up),
                                  isPerspective: cf.camera.isPerspective, fieldOfView: cf.camera.fieldOfView,
                                  orthoHeight: cf.camera.orthoHeight, size: Vec2(Double(bounds.width), Double(bounds.height)), near: cf.near)
    }
}
