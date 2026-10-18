import Foundation
import ArcusGeometry

// F810: Properties of walkthrough views (Total Frames and the frame shown), as the Walkthrough Frames settings of
// mainstream BIM tools. Setters keep the camera on the frame's point of the path.

extension BuiltInCatalog {
    private static func walkthrough(_ key: String, _ name: String, tooltip: String, get: @escaping @Sendable (WalkthroughData) -> Int,
                                    set: @escaping @Sendable (inout WalkthroughData, Int) -> Void) -> P {
        P(key, name, .integer, .camera, tooltip: tooltip, get: { e, _ in e.view?.walkthrough.map { .int(get($0)) } }, set: { e, v, _ in
            guard var d = e.view, var w = d.walkthrough else { throw ParameterError("Only walkthrough views have frames.") }
            guard let n = v.intValue else { throw ParameterError("“\(name)” needs a whole number.") }
            set(&w, n)
            w.frames = max(2, min(10_000, w.frames))
            w.frame = max(1, min(w.frames, w.frame))
            d.camera = w.camera3D(frame: w.frame, base: d.camera)
            d.walkthrough = w
            e.view = d
        })
    }

    static let walkthroughFrames = walkthrough("walkthrough.frames", "Total Frames", tooltip: "Number of frames along the walkthrough path (2 or more).",
                                               get: { $0.frames }, set: { $0.frames = $1 })
    static let walkthroughFrame = walkthrough("walkthrough.frame", "Frame", tooltip: "The frame the view shows.",
                                              get: { $0.frame }, set: { $0.frame = $1 })

    /// Walkthrough parameters of a camera view that is a walkthrough. Hooked from `cameraViewParameters`.
    static func walkthroughParameters(_ e: Element) -> [P] { e.view?.walkthrough == nil ? [] : [walkthroughFrames, walkthroughFrame] }
}
