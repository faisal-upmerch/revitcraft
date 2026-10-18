import AppKit
import QuartzCore
import simd
import ArcusGeometry
import ArcusDomain

// W2-CAM: camera navigation for every 3D view — middle-button and ⌥-left-button drags (BIM-style by default since
// BL-SITE, Blender-style as the alternative), trackpad gestures, numeric keypad views, fly mode and the camera frame.
// See Docs/KeyboardShortcuts.md ("3D navigation").

// MARK: - Settings

/// Mouse and trackpad scheme of the 3D views.
nonisolated public enum Viewport3DNavigationStyle: String, CaseIterable, Sendable {
    /// Middle-drag orbits (⇧ pans, ⌃ dollies); a two-finger swipe orbits (⇧ pans).
    case blender
    /// Middle-drag pans (⇧ orbits about the selection or the model centre); a two-finger swipe pans (⇧ orbits).
    /// The default (BL-SITE, ARCUS-029).
    case revit

    public var title: String { self == .blender ? "Orbit with Middle Button (Blender-style)" : "Pan with Middle Button (BIM-style)" }

    /// BL-SITE: one-paragraph description for Settings ▸ 3D Navigation.
    public var summary: String {
        switch self {
        case .revit:
            return "Middle-drag pans; ⇧ middle-drag orbits around the selection, or the model's centre when nothing is selected. Trackpad: two-finger drag pans, ⇧ two-finger drag orbits."
        case .blender:
            return "Middle-drag orbits around the point under the pointer (or the selection, with Orbit Around Selection); ⇧ middle-drag pans. Trackpad: two-finger drag orbits, ⇧ two-finger drag pans."
        }
    }
}


/// Requests the viewport forwards to its host because they need the document (the active camera).
nonisolated public enum Viewport3DNavigationAction: Sendable {
    case viewThroughCamera, alignCameraToView
}

/// Navigation preferences shared by all 3D views, stored in the user defaults.
public enum Viewport3DNavigationSettings {
    private static let styleKey = "viewport3D.navigationStyle"
    private static let selectionKey = "viewport3D.orbitAroundSelection"

    public static var style: Viewport3DNavigationStyle {
        get { UserDefaults.standard.string(forKey: styleKey).flatMap(Viewport3DNavigationStyle.init(rawValue:)) ?? .revit } // BL-SITE: BIM-style by default
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }
    /// Orbit about the centre of the selection (when there is one) instead of the point under the pointer.
    public static var orbitAroundSelection: Bool {
        get { UserDefaults.standard.bool(forKey: selectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }
}

// MARK: - Input mapping (pure)

/// What a navigation drag does.
nonisolated enum NavigationDragMode: Equatable { case orbit, pan, dolly }

/// Keys that move the camera in fly mode.
nonisolated enum FlyKey: Hashable { case forward, back, left, right, up, down }

/// Numeric keypad and Home-key view commands.
nonisolated enum KeypadCommand: Equatable {
    case orient(OrientationPreset), toggleProjection, frameSelected, frameAll, zoom(Double)
    case orbitStep(yaw: Double, pitch: Double), opposite, action(Viewport3DNavigationAction)
}

/// Pure mapping from input to navigation (kept free of events so it can be tested).
public nonisolated enum NavigationMapping { // BL-CANVAS: public so 2D canvases share the wheel zoom step
    /// Orbit rate of drags, swipes and arrow keys.
    static let orbitRadiansPerPoint = 0.45 * Double.pi / 180
    /// Keypad orbit step.
    static let orbitStep = 15 * Double.pi / 180

    /// Drag mode for a mouse `button` (0 left, 2 middle) with `modifiers`, or nil when the drag is not navigation.
    /// The left button navigates only with ⌥ (three-button emulation for trackpads and one-button mice).
    static func dragMode(button: Int, modifiers: NSEvent.ModifierFlags, style: Viewport3DNavigationStyle) -> NavigationDragMode? {
        let m = modifiers.intersection([.shift, .control, .option, .command])
        if m.contains(.command) { return nil }
        switch button {
        case 0:
            guard m.contains(.option) else { return nil }
            if m.contains(.control) { return .dolly }
            return m.contains(.shift) ? .pan : .orbit
        case 2:
            if m.contains(.control) { return .dolly }
            switch style {
            case .blender: return m.contains(.shift) ? .pan : .orbit
            case .revit: return m.contains(.shift) ? .orbit : .pan
            }
        default:
            return nil
        }
    }

    /// Yaw and pitch for a drag of (dx, dy) points (view coordinates, y up): dragging right turns the model right,
    /// dragging down raises the camera.
    static func orbitAngles(dx: Double, dy: Double) -> (yaw: Double, pitch: Double) {
        (-dx * orbitRadiansPerPoint, -dy * orbitRadiansPerPoint)
    }

    /// Dolly factor for a vertical drag of `dy` points (dragging up moves closer).
    static func dollyFactor(dy: Double) -> Double { exp(max(-200, min(200, dy)) * 0.01) }

    /// Zoom factor for a scroll of `dy` (forward = positive = closer); the same ratio as 2D views (BL-SITE).
    public static func wheelZoomFactor(dy: Double, precise: Bool) -> Double { NavigationZoom.factor(dy: dy, precise: precise) }

    /// BL-SITE: whether a two-finger trackpad swipe orbits (else it pans): Blender-style orbits unless ⇧ is held,
    /// BIM-style orbits only with ⇧.
    static func trackpadSwipeOrbits(style: Viewport3DNavigationStyle, shift: Bool) -> Bool { (style == .blender) != shift }

    /// BL-SITE: where an orbit turns around.
    enum PivotRule: Equatable {
        /// The selection's centre, else the model's centre (BIM-style).
        case selectionOrModelCentre
        /// The selection's centre, else the surface under the pointer (Blender-style with Orbit Around Selection).
        case selectionOrPointer
        /// The surface under the pointer, else the model's centre (Blender-style).
        case pointer
    }
    static func pivotRule(style: Viewport3DNavigationStyle, orbitAroundSelection: Bool) -> PivotRule {
        style == .revit ? .selectionOrModelCentre : (orbitAroundSelection ? .selectionOrPointer : .pointer)
    }

    /// Keypad view commands (Blender layout): 1/3/7 front/right/top (⌃ for back/left/bottom), 5 perspective toggle,
    /// 2/4/6/8 orbit in 15° steps, 9 the opposite side, 0 view through the camera (⌃⌥0 aligns the camera to the view),
    /// . frame selected, + / − zoom, Home frame all.
    static func keypadCommand(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeypadCommand? {
        let m = modifiers.intersection([.shift, .control, .option, .command])
        guard !m.contains(.command), !m.contains(.shift) else { return nil }
        let ctrl = m.contains(.control)
        switch keyCode {
        case 83: return .orient(ctrl ? .back : .front)
        case 85: return .orient(ctrl ? .left : .right)
        case 89: return .orient(ctrl ? .bottom : .top)
        case 87: return m.isEmpty ? .toggleProjection : nil
        case 84: return m.isEmpty ? .orbitStep(yaw: 0, pitch: -orbitStep) : nil
        case 91: return m.isEmpty ? .orbitStep(yaw: 0, pitch: orbitStep) : nil
        case 86: return m.isEmpty ? .orbitStep(yaw: -orbitStep, pitch: 0) : nil
        case 88: return m.isEmpty ? .orbitStep(yaw: orbitStep, pitch: 0) : nil
        case 92: return m.isEmpty ? .opposite : nil
        case 82: return m == [.control, .option] ? .action(.alignCameraToView) : (m.isEmpty ? .action(.viewThroughCamera) : nil)
        case 65: return m.isEmpty ? .frameSelected : nil
        case 69: return m.isEmpty ? .zoom(1.25) : nil
        case 78: return m.isEmpty ? .zoom(1 / 1.25) : nil
        case 115: return m.isEmpty ? .frameAll : nil
        default: return nil
        }
    }

    /// Fly-mode movement key for a key code (W A S D Q E and the arrow keys).
    static func flyKey(keyCode: UInt16) -> FlyKey? {
        switch keyCode {
        case 13, 126: .forward
        case 1, 125: .back
        case 0, 123: .left
        case 2, 124: .right
        case 14: .up
        case 12: .down
        default: nil
        }
    }

    /// Fly velocity (m/s, camera terms: x right, y forward, z world up) for the held keys.
    static func flyVelocity(_ keys: Set<FlyKey>, speed: Double) -> SIMD3<Double> {
        var v = SIMD3<Double>(0, 0, 0)
        if keys.contains(.forward) { v.y += 1 }
        if keys.contains(.back) { v.y -= 1 }
        if keys.contains(.right) { v.x += 1 }
        if keys.contains(.left) { v.x -= 1 }
        if keys.contains(.up) { v.z += 1 }
        if keys.contains(.down) { v.z -= 1 }
        let l = simd_length(v)
        return l > 0 ? v / l * speed : v
    }

    /// Starting fly speed for a scene of diagonal `d` meters: crossing it takes about 15 s.
    static func initialFlySpeed(sceneDiagonal d: Double) -> Double { max(0.5, min(60, (d.isFinite && d > 0 ? d : 20) / 15)) }
}

/// The camera frame (Blender's camera view border / a camera's crop region) fitted in the viewport.
nonisolated enum CameraFrameFit {
    /// Clearance around the frame as a fraction of the viewport.
    static let margin = 0.06

    /// Frame rectangle of `aspect` (width / height) centred in `size`.
    static func rect(in size: CGSize, aspect: Double) -> CGRect {
        let w = Double(size.width) * (1 - 2 * margin), h = Double(size.height) * (1 - 2 * margin)
        let a = max(aspect, 1e-3)
        let fw: Double, fh: Double
        if w / max(h, 1e-9) > a { fh = h; fw = h * a } else { fw = w; fh = w / a }
        return CGRect(x: (Double(size.width) - fw) / 2, y: (Double(size.height) - fh) / 2, width: fw, height: fh)
    }

    /// The camera to render so that `c`'s field of view (or orthographic height) fills the frame, not the viewport.
    static func framed(_ c: Camera3D, aspect: Double?, size: CGSize) -> Camera3D {
        guard let aspect, size.width > 1, size.height > 1 else { return c }
        let r = rect(in: size, aspect: aspect)
        let k = Double(size.height) / max(Double(r.height), 1e-6)
        var out = c
        if c.isPerspective {
            out.fieldOfView = 2 * atan(min(tan(c.fieldOfView / 2) * k, 1e3))
        } else {
            out.orthoHeight = c.orthoHeight * k
        }
        return out
    }
}

// MARK: - State

/// Per-viewport navigation state. Owned by `Viewport3DView.navigation`.
@MainActor final class ViewportNavigation {
    struct Drag {
        var mode: NavigationDragMode
        var button: Int
        var start: CGPoint
        var last: CGPoint
        var anchor: SIMD3<Double>?
    }

    final class Fly {
        let original: Camera3D
        var keys: Set<FlyKey> = []
        var speed: Double
        var velocity = SIMD3<Double>(0, 0, 0)
        var lastTick = CACurrentMediaTime()
        var timer: Timer?
        var observer: (any NSObjectProtocol)?
        init(original: Camera3D, speed: Double) { self.original = original; self.speed = speed }
    }

    var drag: Drag?
    var fly: Fly?
    /// The click that confirmed fly mode: its mouse-up must not reach selection.
    var swallowMouseUp = false
    /// Camera frame aspect ratio (width / height), or nil for no frame.
    var frameAspect: Double?
    var gesturePivot: (point: SIMD3<Double>, time: CFTimeInterval)?
    var overlay: NavigationOverlayView?
    var onAction: ((Viewport3DNavigationAction) -> Void)?
    var onFlyChanged: ((Bool) -> Void)?

    func framed(_ c: Camera3D, size: CGSize) -> Camera3D { CameraFrameFit.framed(c, aspect: frameAspect, size: size) }
}

/// Draws the camera frame (dimming outside it) and the fly-mode help; never takes mouse events.
final class NavigationOverlayView: NSView {
    var frameAspect: Double? { didSet { if oldValue != frameAspect { needsDisplay = true } } }
    var hudText: String? { didSet { if oldValue != hudText { needsDisplay = true } } }
    var increaseContrast = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if let a = frameAspect {
            let r = CameraFrameFit.rect(in: bounds.size, aspect: a).offsetBy(dx: bounds.minX, dy: bounds.minY)
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: r).reversed)
            NSColor.black.withAlphaComponent(increaseContrast ? 0.55 : 0.32).setFill()
            outside.fill()
            let border = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = increaseContrast ? 2 : 1
            NSColor.white.withAlphaComponent(0.85).setStroke()
            border.stroke()
        }
        if let text = hudText {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: NSColor.white]
            let s = NSAttributedString(string: text, attributes: attrs)
            let size = s.size()
            let box = NSRect(x: bounds.midX - size.width / 2 - 12, y: bounds.minY + 18, width: size.width + 24, height: size.height + 12)
            NSColor.black.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            s.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 6))
        }
    }
}

// MARK: - Viewport API

extension Viewport3DView {
    /// True while the user is moving the camera (a drag, gesture, key repeat, animation or fly mode).
    public var isNavigating: Bool { isInteracting || navigation.drag != nil || navigation.fly != nil }

    /// True while fly mode is on.
    public var isFlying: Bool { navigation.fly != nil }

    /// Keypad 0 / ⌃⌥0 requests the host handles.
    public var onNavigationAction: ((Viewport3DNavigationAction) -> Void)? {
        get { navigation.onAction }
        set { navigation.onAction = newValue }
    }

    /// Called when fly mode starts (true) or ends (false).
    public var onFlyModeChanged: ((Bool) -> Void)? {
        get { navigation.onFlyChanged }
        set { navigation.onFlyChanged = newValue }
    }

    /// Aspect ratio of the camera frame to show (a camera view's crop region), or nil for none. The camera's field of
    /// view then spans the frame height, as in a camera.
    public var cameraFrameAspect: Double? {
        get { navigation.frameAspect }
        set {
            guard newValue != navigation.frameAspect else { return }
            navigation.frameAspect = newValue
            updateNavigationOverlay()
            invalidate()
        }
    }

    /// Switches perspective ↔ orthographic.
    public func toggleProjection() {
        cancelAnimation()
        setPerspective(!camera.isPerspective)
    }

    /// Frames the selection (everything when nothing is selected).
    public func frameSelection() {
        if selection.isEmpty { zoomExtents(animated: true) } else { zoom(toElements: selection, animated: true) }
    }

    /// Orbits about the view centre by the given angles (radians), animated unless Reduce Motion is on.
    public func orbitStep(yaw: Double, pitch: Double) {
        let c = CameraMotion.orbit(camera, yaw: yaw, pitch: pitch, pivot: Vec3(defaultPivot))
        setCamera(c, animated: true)
    }

    /// Runs a keypad command (also used by the View ▸ 3D Navigation menu).
    func performKeypad(_ k: KeypadCommand) {
        switch k {
        case .orient(let p): orient(to: p, animated: true)
        case .toggleProjection: toggleProjection()
        case .frameSelected: frameSelection()
        case .frameAll: zoomExtents(animated: true)
        case .zoom(let f): noteInteraction(); zoom(factor: f, at: CGPoint(x: bounds.midX, y: bounds.midY), hit: nil)
        case .orbitStep(let yaw, let pitch): orbitStep(yaw: yaw, pitch: pitch)
        case .opposite: orbitStep(yaw: .pi, pitch: -2 * CameraMotion.elevation(camera))
        case .action(let a): navigation.onAction?(a)
        }
    }

    /// Pivot for an orbit starting at `p`: the selection centre (when that setting is on), else the surface under the
    /// pointer, else the scene centre.
    func orbitPivot(at p: CGPoint) -> SIMD3<Double> {
        let rule = NavigationMapping.pivotRule(style: Viewport3DNavigationSettings.style, orbitAroundSelection: Viewport3DNavigationSettings.orbitAroundSelection)
        if rule != .pointer, !selection.isEmpty, let s = gpuScene {
            var b = Box3.empty
            for id in selection { if let i = s.indexOf[id] { b.include(s.elementBounds[i]) } }
            if !b.isEmpty { return b.center.simd }
        }
        if rule == .selectionOrModelCentre { return defaultPivot } // BL-SITE: BIM-style orbits about the model's centre
        return pickNow(at: p).position ?? defaultPivot
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    // MARK: Drags

    func beginNavigationDrag(_ mode: NavigationDragMode, button: Int, at p: CGPoint) {
        cancelAnimation()
        let anchor: SIMD3<Double>?
        switch mode {
        case .orbit: anchor = orbitPivot(at: p); pivot = anchor
        case .pan: anchor = pickNow(at: p).position ?? camera.target.simd
        case .dolly: anchor = pickNow(at: p).position
        }
        navigation.drag = ViewportNavigation.Drag(mode: mode, button: button, start: p, last: p, anchor: anchor)
        if preselection != nil { preselection = nil; onHover?(nil) }
    }

    func continueNavigationDrag(to p: CGPoint) {
        guard var d = navigation.drag else { return }
        let dx = Double(p.x - d.last.x), dy = Double(p.y - d.last.y)
        d.last = p
        navigation.drag = d
        noteInteraction()
        switch d.mode {
        case .orbit:
            let a = NavigationMapping.orbitAngles(dx: dx, dy: dy)
            showPivot = true
            camera = CameraMotion.orbit(camera, yaw: a.yaw, pitch: a.pitch, pivot: Vec3(d.anchor ?? defaultPivot))
        case .pan:
            pan(dx: dx, dy: dy, depthPoint: d.anchor)
        case .dolly:
            zoom(factor: NavigationMapping.dollyFactor(dy: dy), at: d.start, hit: d.anchor)
        }
    }

    func endNavigationDrag() {
        navigation.drag = nil
        showPivot = false
        invalidate()
    }

    func navigationMouseDown(_ e: NSEvent) -> Bool {
        if navigation.fly != nil { endFly(restore: false); navigation.swallowMouseUp = true; return true }
        guard let mode = NavigationMapping.dragMode(button: 0, modifiers: e.modifierFlags, style: Viewport3DNavigationSettings.style) else { return false }
        beginNavigationDrag(mode, button: 0, at: point(e))
        return true
    }

    func navigationMouseDragged(_ e: NSEvent) -> Bool {
        if navigation.fly != nil { flyLook(dx: Double(e.deltaX), dy: Double(e.deltaY)); return true }
        guard navigation.drag?.button == 0 else { return false }
        continueNavigationDrag(to: point(e))
        return true
    }

    func navigationMouseUp(_ e: NSEvent) -> Bool {
        if navigation.swallowMouseUp { navigation.swallowMouseUp = false; return true }
        guard navigation.drag?.button == 0 else { return navigation.fly != nil }
        endNavigationDrag()
        return true
    }

    func navigationMouseMoved(_ e: NSEvent) -> Bool {
        guard navigation.fly != nil else { return false }
        flyLook(dx: Double(e.deltaX), dy: Double(e.deltaY))
        return true
    }

    func navigationOtherMouseDown(_ e: NSEvent) -> Bool {
        guard e.buttonNumber == 2 else { return false }
        if navigation.fly != nil { return true }
        window?.makeFirstResponder(self)
        if e.clickCount == 2 { zoomExtents(animated: true); return true }
        guard let mode = NavigationMapping.dragMode(button: 2, modifiers: e.modifierFlags, style: Viewport3DNavigationSettings.style) else { return true }
        beginNavigationDrag(mode, button: 2, at: point(e))
        return true
    }

    func navigationOtherMouseDragged(_ e: NSEvent) -> Bool {
        guard e.buttonNumber == 2 else { return false }
        if navigation.drag?.button == 2 { continueNavigationDrag(to: point(e)) }
        return true
    }

    func navigationOtherMouseUp(_ e: NSEvent) -> Bool {
        guard e.buttonNumber == 2 else { return false }
        if navigation.drag?.button == 2 { endNavigationDrag() }
        return true
    }

    public override func rightMouseDown(with event: NSEvent) {
        if navigation.fly != nil { endFly(restore: true); return }
        super.rightMouseDown(with: event)
    }

    // MARK: Scroll and gestures

    /// Pivot for a trackpad gesture: picked once when the gesture begins.
    private func gesturePivot(at p: CGPoint, began: Bool) -> SIMD3<Double> {
        let now = CACurrentMediaTime()
        if !began, let g = navigation.gesturePivot, now - g.time < 0.6 {
            navigation.gesturePivot = (g.point, now)
            return g.point
        }
        let pv = orbitPivot(at: p)
        navigation.gesturePivot = (pv, now)
        return pv
    }

    func navigationScroll(_ e: NSEvent) {
        let p = point(e)
        if let fly = navigation.fly {
            let dy = Double(e.scrollingDeltaY) * (e.isDirectionInvertedFromDevice ? -1 : 1)
            guard dy != 0, e.momentumPhase == [] else { return }
            fly.speed = max(0.05, min(500, fly.speed * (dy > 0 ? 1.15 : 1 / 1.15)))
            updateNavigationOverlay()
            return
        }
        cancelAnimation()
        let trackpad = e.hasPreciseScrollingDeltas && (e.phase != [] || e.momentumPhase != [])
        // Reduce Motion: no gliding after the fingers lift.
        if trackpad, reduceMotion, e.momentumPhase != [] { return }
        noteInteraction()
        let m = e.modifierFlags
        if trackpad {
            let dx = Double(e.scrollingDeltaX), dy = Double(e.scrollingDeltaY)
            if m.contains(.option) || m.contains(.command) {
                zoom(factor: NavigationMapping.wheelZoomFactor(dy: dy, precise: true), at: p, hit: zoomHit(at: p))
            } else if NavigationMapping.trackpadSwipeOrbits(style: Viewport3DNavigationSettings.style, shift: m.contains(.shift)) { // BL-SITE
                // Two-finger swipe orbits like a middle-button drag in the direction the content moves.
                let a = NavigationMapping.orbitAngles(dx: dx, dy: -dy)
                let pv = gesturePivot(at: p, began: e.phase.contains(.began) || e.phase.contains(.mayBegin))
                camera = CameraMotion.orbit(camera, yaw: a.yaw, pitch: a.pitch, pivot: Vec3(pv))
            } else {
                pan(dx: dx, dy: -dy, depthPoint: zoomHit(at: p) ?? camera.target.simd)
            }
            return
        }
        // Mouse wheel: forward (away from the user) zooms in toward the pointer, independent of natural scrolling.
        let dy = Double(e.scrollingDeltaY) * (e.isDirectionInvertedFromDevice ? -1 : 1)
        guard dy != 0 else { return }
        zoom(factor: NavigationMapping.wheelZoomFactor(dy: dy, precise: e.hasPreciseScrollingDeltas), at: p, hit: zoomHit(at: p))
    }

    func navigationMagnify(_ e: NSEvent) {
        guard navigation.fly == nil else { return }
        let p = point(e)
        cancelAnimation()
        noteInteraction()
        zoom(factor: max(0.2, 1 + Double(e.magnification)), at: p, hit: zoomHit(at: p))
    }

    func navigationRotate(_ e: NSEvent) {
        guard navigation.fly == nil else { return }
        cancelAnimation()
        noteInteraction()
        // Turning two fingers counter-clockwise turns the model counter-clockwise (the camera the other way).
        let pv = gesturePivot(at: point(e), began: e.phase.contains(.began))
        camera = CameraMotion.orbit(camera, yaw: -Double(e.rotation) * .pi / 180, pitch: 0, pivot: Vec3(pv))
    }

    public override func smartMagnify(with event: NSEvent) {
        guard navigation.fly == nil else { return }
        zoomExtents(animated: true)
    }

    // MARK: Keys

    func handleNavigationKey(_ e: NSEvent) -> Bool {
        if navigation.fly != nil { return flyKeyDown(e) }
        let m = e.modifierFlags.intersection([.shift, .control, .option, .command])
        if e.keyCode == 3, m == [.shift] { beginFly(); return true } // ⇧F
        guard let k = NavigationMapping.keypadCommand(keyCode: e.keyCode, modifiers: e.modifierFlags) else { return false }
        performKeypad(k)
        return true
    }

    public override func keyUp(with event: NSEvent) {
        if let fly = navigation.fly {
            if let k = NavigationMapping.flyKey(keyCode: event.keyCode) { fly.keys.remove(k) }
            return
        }
        super.keyUp(with: event)
    }

    public override func resignFirstResponder() -> Bool {
        if navigation.fly != nil { endFly(restore: true) }
        return super.resignFirstResponder()
    }

    // MARK: Fly mode

    /// Starts fly mode (⇧F): the mouse turns the view, W A S D move, Q/E go down/up, scrolling changes the speed,
    /// ⇧ is faster and ⌥ slower. Return or a click keeps the new camera; Esc or a right-click restores the old one.
    public func beginFly() {
        guard navigation.fly == nil, window != nil else { return }
        cancelAnimation()
        let original = camera
        if !camera.isPerspective { setPerspective(true) }
        let fly = ViewportNavigation.Fly(original: original, speed: NavigationMapping.initialFlySpeed(sceneDiagonal: sceneBounds.diagonal))
        navigation.fly = fly
        if preselection != nil { preselection = nil; onHover?(nil) }
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flyTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fly.timer = timer
        if let w = window {
            fly.observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endFly(restore: true) }
            }
        }
        updateNavigationOverlay()
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Fly mode. W A S D to move, Q and E down and up, Return to keep, Escape to cancel.", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        navigation.onFlyChanged?(true)
    }

    /// Ends fly mode, keeping the camera or restoring the one it started from.
    public func endFly(restore: Bool) {
        guard let fly = navigation.fly else { return }
        fly.timer?.invalidate()
        if let o = fly.observer { NotificationCenter.default.removeObserver(o) }
        navigation.fly = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        if restore { camera = fly.original }
        updateNavigationOverlay()
        invalidate()
        navigation.onFlyChanged?(false)
    }

    private func flyKeyDown(_ e: NSEvent) -> Bool {
        guard let fly = navigation.fly else { return false }
        if e.modifierFlags.contains(.command) { return false }
        switch e.keyCode {
        case 53: endFly(restore: true)                 // Esc
        case 36, 76: endFly(restore: false)            // Return / Enter
        default: if let k = NavigationMapping.flyKey(keyCode: e.keyCode) { fly.keys.insert(k) }
        }
        return true
    }

    private func flyLook(dx: Double, dy: Double) {
        guard navigation.fly != nil else { return }
        let k = 0.0022
        noteInteraction()
        camera = CameraMotion.fly(camera, yaw: -dx * k, pitch: -dy * k)
    }

    private func flyTick() {
        guard let fly = navigation.fly else { return }
        let now = CACurrentMediaTime()
        let dt = min(max(now - fly.lastTick, 0), 0.1)
        fly.lastTick = now
        let mods = NSEvent.modifierFlags
        let speed = fly.speed * (mods.contains(.shift) ? 4 : 1) * (mods.contains(.option) ? 0.25 : 1)
        let target = NavigationMapping.flyVelocity(fly.keys, speed: speed)
        // Ease in and out over ~80 ms so starts and stops feel physical; immediate with Reduce Motion.
        let blend = reduceMotion ? 1 : 1 - exp(-dt / 0.08)
        fly.velocity += (target - fly.velocity) * blend
        guard simd_length(fly.velocity) > 1e-4 else { fly.velocity = SIMD3(0, 0, 0); return }
        noteInteraction()
        let m = fly.velocity * dt
        camera = CameraMotion.fly(camera, move: Vec3(m.x, m.y, m.z))
    }

    // MARK: Overlay

    func updateNavigationOverlay() {
        let hud = navigation.fly.map { f in
            String(format: "Fly  ·  W A S D move  ·  Q / E down / up  ·  scroll: speed %.1f m/s  ·  ⇧ faster  ·  ⌥ slower  ·  Return or click keeps  ·  Esc or right-click cancels", f.speed)
        }
        if navigation.frameAspect == nil && hud == nil {
            navigation.overlay?.frameAspect = nil
            navigation.overlay?.hudText = nil
            return
        }
        let o: NavigationOverlayView
        if let existing = navigation.overlay {
            o = existing
        } else {
            o = NavigationOverlayView(frame: bounds)
            o.autoresizingMask = [.width, .height]
            addSubview(o, positioned: .below, relativeTo: orientationWidget)
            navigation.overlay = o
        }
        o.increaseContrast = increaseContrast
        o.frameAspect = navigation.frameAspect
        o.hudText = hud
    }
}
