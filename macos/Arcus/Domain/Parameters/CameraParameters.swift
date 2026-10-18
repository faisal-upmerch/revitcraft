import Foundation
import ArcusGeometry

// W2-CAM: Properties of camera views (projection, lens, eye and target, roll, clipping and camera frame). Every
// setter edits the view's `Camera3D`, so changes are ordinary undoable parameter transactions.

extension BuiltInCatalog {
    /// Parameters of a camera view, or nil when `e` is not one. Hooked from `viewWP6aParameters`.
    static func cameraViewParameters(_ e: Element) -> [P]? {
        guard e.isCameraView, let c = e.view?.camera else { return nil }
        var list: [P] = [cameraProjection]
        list += c.isPerspective ? [cameraFocalLength, cameraFieldOfView] : [cameraOrthoHeight]
        list += [cameraEyeX, cameraEyeY, cameraEyeElevation, cameraTargetX, cameraTargetY, cameraTargetElevation, cameraRoll,
                 cameraNearClip, cameraFarClipActive, cameraFarClipOffset, cameraCropWidth, cameraCropHeight, cameraAspect]
        return list
    }

    private static func cameraError(_ s: String) -> ParameterError { ParameterError(s) }

    private static func cameraNumber(_ v: ParamValue, _ name: String) throws(ParameterError) -> Double {
        guard let d = v.doubleValue, d.isFinite else { throw cameraError("“\(name)” needs a number.") }
        return d
    }

    /// A camera parameter: `get` reads the camera, `set` edits a copy that is validated and written back.
    private static func cam(_ key: String, _ name: String, _ type: ParamType, _ group: ParameterGroup = .camera, tooltip: String = "",
                            get: @escaping @Sendable (Camera3D, Element, ParameterContext) -> ParamValue?,
                            set: (@Sendable (inout Camera3D, ParamValue, Element, ParameterContext) throws(ParameterError) -> Void)? = nil) -> P {
        let getter: @Sendable (Element, ParameterContext) -> ParamValue? = { e, ctx in
            guard e.isCameraView, let c = e.view?.camera else { return nil }
            return get(c, e, ctx)
        }
        guard let set else { return P(key, name, type, group, tooltip: tooltip, get: getter) }
        let setter: @Sendable (inout Element, ParamValue, ParameterContext) throws -> Void = { e, v, ctx in
            guard e.isCameraView, var d = e.view, var c = d.camera else { throw cameraError("Only camera views have camera settings.") }
            let element = e
            try set(&c, v, element, ctx)
            guard c.distance > Tolerance.shortCurve else { throw cameraError("The eye and target can't coincide.") }
            d.camera = c
            e.view = d
        }
        return P(key, name, type, group, tooltip: tooltip, get: getter, set: setter)
    }

    static let cameraProjection = cam("camera.projection", "Projection", .choice(["Perspective", "Orthographic"]),
                                      tooltip: "Perspective shows depth like a photograph; orthographic keeps parallel lines parallel.",
                                      get: { c, _, _ in .text(c.isPerspective ? "Perspective" : "Orthographic") },
                                      set: { c, v, _, _ throws(ParameterError) in
                                          let s = (v.textValue ?? v.description).lowercased()
                                          guard s.hasPrefix("p") || s.hasPrefix("o") else { throw cameraError("Choose Perspective or Orthographic.") }
                                          c.setPerspective(s.hasPrefix("p"))
                                      })

    static let cameraFocalLength = cam("camera.focalLength", "Focal Length (mm)", .number,
                                       tooltip: "35 mm-equivalent lens focal length. Changing it changes the field of view.",
                                       get: { c, _, _ in .double(c.focalLength) },
                                       set: { c, v, _, _ throws(ParameterError) in
                                           let mm = try cameraNumber(v, "Focal Length")
                                           let r = Camera3D.focalLengthRange
                                           guard r.contains(mm) else { throw cameraError("The focal length must be between \(Int(r.lowerBound)) and \(Int(r.upperBound)) mm.") }
                                           c.focalLength = mm
                                       })

    static let cameraFieldOfView = cam("camera.fieldOfView", "Field of View", .angle,
                                       tooltip: "Vertical angle of view of the camera frame. Changing it changes the focal length.",
                                       get: { c, _, _ in .double(c.fieldOfView) },
                                       set: { c, v, _, _ throws(ParameterError) in
                                           let a = try cameraNumber(v, "Field of View")
                                           let lo = Camera3D.fieldOfView(focalLength: Camera3D.focalLengthRange.upperBound)
                                           let hi = Camera3D.fieldOfView(focalLength: Camera3D.focalLengthRange.lowerBound)
                                           guard a >= lo - 1e-9, a <= hi + 1e-9 else {
                                               throw cameraError(String(format: "The field of view must be between %.1f° and %.1f°.", lo * 180 / .pi, hi * 180 / .pi))
                                           }
                                           c.fieldOfView = a
                                       })

    static let cameraOrthoHeight = cam("camera.orthoHeight", "View Height", .length,
                                       tooltip: "Height of the model shown by an orthographic camera.",
                                       get: { c, _, _ in .double(c.orthoHeight) },
                                       set: { c, v, _, _ throws(ParameterError) in
                                           let h = try cameraNumber(v, "View Height")
                                           guard h > 0.01 else { throw cameraError("The view height must be greater than zero.") }
                                           c.orthoHeight = h
                                       })

    private static func coordinate(_ key: String, _ name: String, target: Bool, x: Bool) -> P {
        cam(key, name, .length, tooltip: target ? "Plan position of the point the camera looks at." : "Plan position of the camera.",
            get: { c, _, _ in
                let p = target ? c.target : c.eye
                return .double(x ? p.x : p.y)
            },
            set: { c, v, _, _ throws(ParameterError) in
                let d = try cameraNumber(v, name)
                let roll = c.roll
                var p = target ? c.target : c.eye
                if x { p.x = d } else { p.y = d }
                if target { c.target = p } else { c.eye = p }
                c.up = Camera3D.levelUp(forward: c.forward)
                c.roll = roll
            })
    }
    static let cameraEyeX = coordinate("camera.eyeX", "Eye Position X", target: false, x: true)
    static let cameraEyeY = coordinate("camera.eyeY", "Eye Position Y", target: false, x: false)
    static let cameraTargetX = coordinate("camera.targetX", "Target Position X", target: true, x: true)
    static let cameraTargetY = coordinate("camera.targetY", "Target Position Y", target: true, x: false)

    /// Eye/target height above the camera's level. Keeps the ids of the earlier Eye Height / Target Height parameters.
    private static func elevation(_ key: String, _ name: String, target: Bool) -> P {
        cam(key, name, .length, tooltip: "Height above the level the camera belongs to.",
            get: { c, e, ctx in .double((target ? c.target.z : c.eye.z) - ctx.model.elevation(ofLevel: e.levelID)) },
            set: { c, v, e, ctx throws(ParameterError) in
                let z = ctx.model.elevation(ofLevel: e.levelID) + (try cameraNumber(v, name))
                let roll = c.roll
                if target { c.target.z = z } else { c.eye.z = z }
                c.up = Camera3D.levelUp(forward: c.forward)
                c.roll = roll
            })
    }
    static let cameraEyeElevation = elevation("view.eyeHeight", "Eye Elevation", target: false)
    static let cameraTargetElevation = elevation("view.targetHeight", "Target Elevation", target: true)

    static let cameraRoll = cam("camera.roll", "Roll", .angle, tooltip: "Rotation about the view direction. 0 keeps the horizon level.",
                                get: { c, _, _ in .double(c.roll) },
                                set: { c, v, _, _ throws(ParameterError) in c.roll = try cameraNumber(v, "Roll") })

    static let cameraNearClip = cam("camera.nearClip", "Near Clip Offset", .length, .extents,
                                    tooltip: "Distance from the eye to the near clip plane. 0 chooses one automatically.",
                                    get: { c, _, _ in .double(c.nearClip ?? 0) },
                                    set: { c, v, _, _ throws(ParameterError) in
                                        let d = try cameraNumber(v, "Near Clip Offset")
                                        guard d >= 0 else { throw cameraError("The near clip offset can't be negative.") }
                                        if let f = c.effectiveFarClip, d >= f { throw cameraError("The near clip must be closer than the far clip.") }
                                        c.nearClip = d > 0 ? max(d, 0.001) : nil
                                    })

    static let cameraFarClipActive = cam("camera.farClipActive", "Far Clip Active", .bool, .extents,
                                         tooltip: "Hides everything farther from the eye than the far clip offset.",
                                         get: { c, _, _ in .bool(c.farClipActive == true) },
                                         set: { c, v, _, _ throws(ParameterError) in
                                             guard let b = v.boolValue else { throw cameraError("Type Yes or No.") }
                                             c.farClipActive = b ? true : nil
                                             if b, c.farClipDistance == nil { c.farClipDistance = max(Camera3D.defaultFarClip, c.distance * 2) }
                                         })

    static let cameraFarClipOffset = cam("camera.farClipOffset", "Far Clip Offset", .length, .extents,
                                         tooltip: "Distance from the eye to the far clip plane.",
                                         get: { c, _, _ in .double(c.farClipDistance ?? max(Camera3D.defaultFarClip, c.distance * 2)) },
                                         set: { c, v, _, _ throws(ParameterError) in
                                             let d = try cameraNumber(v, "Far Clip Offset")
                                             guard d > (c.nearClip ?? 0) + 0.001 else { throw cameraError("The far clip must be farther than the near clip.") }
                                             c.farClipDistance = d
                                         })

    private static func cropSize(_ key: String, _ name: String, width: Bool) -> P {
        cam(key, name, .length, .extents, tooltip: "Size of the camera frame on paper; the width-to-height ratio shapes the frame.",
            get: { c, _, _ in .double(width ? (c.cropWidth ?? CameraViews.defaultCropWidth) : (c.cropHeight ?? CameraViews.defaultCropHeight)) },
            set: { c, v, _, _ throws(ParameterError) in
                let d = try cameraNumber(v, name)
                guard d >= 0.005, d <= 10 else { throw cameraError("The frame size must be between 5 mm and 10 m.") }
                if c.cropWidth == nil || c.cropHeight == nil { c.cropWidth = CameraViews.defaultCropWidth; c.cropHeight = CameraViews.defaultCropHeight }
                if width { c.cropWidth = d } else { c.cropHeight = d }
                guard c.frameAspect >= 0.1, c.frameAspect <= 10 else { throw cameraError("The frame can be at most 10 times wider than tall, or taller than wide.") }
            })
    }
    static let cameraCropWidth = cropSize("camera.cropWidth", "Crop Region Width", width: true)
    static let cameraCropHeight = cropSize("camera.cropHeight", "Crop Region Height", width: false)
    static let cameraAspect = cam("camera.aspect", "Aspect Ratio", .number, .extents, tooltip: "Width divided by height of the camera frame.",
                                  get: { c, _, _ in .double(c.frameAspect) })
}
