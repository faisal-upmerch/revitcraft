import Foundation
import ArcusGeometry

// F810: model data of the View tab's RevitCraft features: cut profiles, matchlines, saved renderings, Show Hidden
// Lines pairs and walkthroughs. Docs/RevitCraftPort.md §5 (F8–F10).

/// View ▸ Cut Profile: a sketched region that reshapes a wall's cut in one view only (`Element.ownerViewID`); the wall
/// is `Element.hostID`. A region lying mostly inside the wall cuts it away, otherwise it joins the wall, as in
/// RevitCraft's `add_cut_profile`.
public struct CutProfileData: Hashable, Codable, Sendable {
    /// Closed region in plan coordinates (counter-clockwise).
    public var region: [Vec2]
    /// True when the region joins the wall's cut shape; false when it is cut away.
    public var adds: Bool
    public init(region: [Vec2], adds: Bool) { self.region = region; self.adds = adds }
}

/// View ▸ Sheet Composition ▸ Matchline: a line where a plan continues on another sheet. Drawn in every plan view, as
/// in RevitCraft (`add_matchline`).
public struct MatchlineData: Hashable, Codable, Sendable {
    public var start: Vec2
    public var end: Vec2
    public init(start: Vec2, end: Vec2) { self.start = start; self.end = end }
    public var segment: Segment2 { Segment2(start, end) }
}

/// View ▸ Presentation ▸ Render ▸ Save to Project: a rendered still image kept in the project (the Render Gallery).
public struct RenderingData: Hashable, Codable, Sendable {
    /// PNG bytes of the image.
    public var png: Data
    public var width: Int
    public var height: Int
    /// The 3D view it was rendered from (nil once that view is deleted).
    public var viewID: ElementID?
    public var date: Date
    /// "Draft", "Low", "Medium", "High" or "Best".
    public var quality: String
    public var sunLighting: Bool
    public var skyBackground: Bool
    public init(png: Data, width: Int, height: Int, viewID: ElementID?, date: Date = Date(), quality: String, sunLighting: Bool, skyBackground: Bool) {
        self.png = png; self.width = width; self.height = height; self.viewID = viewID; self.date = date; self.quality = quality
        self.sunLighting = sunLighting; self.skyBackground = skyBackground
    }
}

/// View ▸ Graphics ▸ Show Hidden Lines: in a view, the lines of `hidden` behind `obscuring` are drawn dashed.
public struct HiddenLinePair: Hashable, Codable, Sendable {
    public var obscuring: ElementID
    public var hidden: ElementID
    public init(obscuring: ElementID, hidden: ElementID) { self.obscuring = obscuring; self.hidden = hidden }
}

/// View ▸ 3D View ▸ Walkthrough: the camera moves along `path` (eye points) over `frames` frames. The view's camera is
/// the current frame's (RevitCraft's `Walkthrough`).
public struct WalkthroughData: Hashable, Codable, Sendable {
    public var path: [Vec3]
    public var frames: Int
    /// The frame shown (1-based).
    public var frame: Int
    public init(path: [Vec3], frames: Int = 300, frame: Int = 1) { self.path = path; self.frames = frames; self.frame = frame }

    public static let defaultFrames = 300
    /// How far ahead along the path the camera looks (meters).
    public static let lookAhead = 1.0

    /// Total path length (meters).
    public var length: Double { zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

    /// The point at distance `s` along the path.
    public func point(at s: Double) -> Vec3 {
        guard path.count >= 2 else { return path.first ?? .zero }
        var s = max(0, min(length, s))
        for k in 0..<(path.count - 1) {
            let l = path[k].distance(to: path[k + 1])
            if s <= l || k == path.count - 2 { return path[k].lerp(to: path[k + 1], t: l > 0 ? min(1, s / l) : 0) }
            s -= l
        }
        return path[path.count - 1]
    }

    /// Eye and target at a frame: evenly along the path, looking a little ahead along it (along the last segment at
    /// the end).
    public func camera(frame f: Int) -> (eye: Vec3, target: Vec3) {
        guard path.count >= 2 else {
            let e = path.first ?? .zero
            return (e, e + Vec3.unitY)
        }
        let total = length
        let t = Double(max(1, min(max(frames, 1), f)) - 1) / Double(max(frames, 2) - 1)
        let s = t * total
        let eye = point(at: s)
        if total - s > Self.lookAhead { return (eye, point(at: s + Self.lookAhead)) }
        let last = path[path.count - 1] - path[path.count - 2]
        let dir = last.length > 1e-9 ? last.normalized : Vec3.unitY
        return (eye, eye + dir * Self.lookAhead)
    }

    /// The camera of a walkthrough view at frame `f`, keeping the view's lens and clip settings.
    public func camera3D(frame f: Int, base: Camera3D?) -> Camera3D {
        let (eye, target) = camera(frame: f)
        var c = base ?? Camera3D(eye: eye, target: target, isPerspective: true, fieldOfView: CameraViews.defaultFieldOfView)
        c.eye = eye; c.target = target; c.up = .unitZ; c.isPerspective = true
        return c
    }
}

// MARK: - Typed accessors

extension Element {
    public var cutProfile: CutProfileData? {
        get { if case .cutProfile(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .cutProfile(v) } }
    }
    public var matchline: MatchlineData? {
        get { if case .matchline(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .matchline(v) } }
    }
    public var rendering: RenderingData? {
        get { if case .rendering(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .rendering(v) } }
    }
}
