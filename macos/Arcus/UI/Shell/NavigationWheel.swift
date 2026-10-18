import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusViewport3D

// F810: RevitCraft's navigation wheels (crates/rc-app/src/wheel.rs): the 2D Wheel (Zoom, Pan, Rewind) of plans,
// sections and sheets, and the Full Navigation Wheel of 3D views (outer: Zoom, Pan, Rewind, Orbit; inner: Center,
// Look, Up/Down, Walk). The wheel floats under the cursor; pressing a wedge and dragging runs it. Esc or the cross
// closes it.

enum NavigationWheel {
    enum Wedge: String { case zoom = "ZOOM", pan = "PAN", rewind = "REWIND", orbit = "ORBIT", center = "CENTER", look = "LOOK", walk = "WALK", upDown = "UP/DOWN" }

    static let outerRadius: CGFloat = 78
    static let middleRadius: CGFloat = 40
    static let holeRadius: CGFloat = 12

    /// (start°, end°, inner radius, outer radius, wedge) in screen angles (0° = right, −90° = up, y down).
    static func sectors(full: Bool) -> [(a0: CGFloat, a1: CGFloat, r0: CGFloat, r1: CGFloat, wedge: Wedge)] {
        if full {
            return [(-135, -45, middleRadius, outerRadius, .zoom), (-45, 45, middleRadius, outerRadius, .pan),
                    (45, 135, middleRadius, outerRadius, .rewind), (135, 225, middleRadius, outerRadius, .orbit),
                    (-135, -45, holeRadius, middleRadius, .center), (-45, 45, holeRadius, middleRadius, .look),
                    (45, 135, holeRadius, middleRadius, .upDown), (135, 225, holeRadius, middleRadius, .walk)]
        }
        let r0 = holeRadius + 10, r1 = outerRadius - 6
        return [(-150, -30, r0, r1, .zoom), (-30, 30, r0, r1, .pan), (30, 150, r0, r1, .rewind), (150, 210, r0, r1, .pan)]
    }

    /// The wedge under `p` for a wheel centred at `c` (screen points, y down).
    static func wedge(full: Bool, center c: CGPoint, at p: CGPoint) -> Wedge? {
        let v = CGPoint(x: p.x - c.x, y: p.y - c.y)
        let d = hypot(v.x, v.y)
        let ang = atan2(v.y, v.x) * 180 / .pi
        return sectors(full: full).first { s in
            var a = ang
            while a < s.a0 { a += 360 }
            return d >= s.r0 && d <= s.r1 && a < s.a1
        }?.wedge
    }

    /// The wheel's close cross, at its top right.
    static func closeCenter(_ c: CGPoint) -> CGPoint { CGPoint(x: c.x + outerRadius * 0.72, y: c.y - outerRadius * 0.72) }

    /// Where the wheel sits when the pointer is at `p`: it moves only when the pointer pushes past its rim.
    static func follow(_ c: CGPoint?, _ p: CGPoint) -> CGPoint {
        guard let c else { return p }
        let v = CGPoint(x: p.x - c.x, y: p.y - c.y)
        let l = hypot(v.x, v.y), limit = outerRadius - 14
        guard l > limit else { return c }
        return CGPoint(x: p.x - v.x / l * limit, y: p.y - v.y / l * limit)
    }

    static func prompt(_ w: Wedge?) -> String {
        switch w {
        case .zoom: "Zoom: drag up to zoom in, down to zoom out."
        case .pan: "Pan: drag to move the view."
        case .rewind: "Rewind: drag left to step back through previous views, right to step forward."
        case .orbit: "Orbit: drag to rotate the view around its pivot."
        case .center: "Center: click a point on the model to make it the pivot."
        case .look: "Look: drag to turn the view direction."
        case .walk: "Walk: drag up to move forward, down to move back."
        case .upDown: "Up/Down: drag to move the view up or down."
        case nil: "Navigation wheel: press a wedge and drag. Esc or the cross closes it."
        }
    }

    /// Shows the wheel of the active view (the Full Navigation Wheel in 3D views), or closes it.
    @MainActor static func toggle(_ state: DocumentState) {
        guard let v = state.activeViewID, let canvas = state.canvases[v], let container = canvas.superview else { return }
        if let open = container.subviews.first(where: { $0 is NavigationWheelView }) as? NavigationWheelView { open.close(); return }
        let wheel = NavigationWheelView(state: state, viewID: v, canvas: canvas, full: canvas is Viewport3DHost)
        wheel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wheel)
        NSLayoutConstraint.activate([
            wheel.leadingAnchor.constraint(equalTo: container.leadingAnchor), wheel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wheel.topAnchor.constraint(equalTo: container.topAnchor), wheel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.window?.makeFirstResponder(wheel)
        state.show(prompt(nil))
    }

    /// Previous cameras of each 3D view (Rewind of the Full Navigation Wheel).
    @MainActor static var cameraHistory: [ElementID: [Camera3D]] = [:]
}

/// The wheel overlay over one canvas: it takes the pointer while it is open and drives the canvas's navigation.
final class NavigationWheelView: NSView {
    unowned let state: DocumentState
    let viewID: ElementID
    weak var canvas: NSView?
    let full: Bool
    private var center: CGPoint?
    private var held: NavigationWheel.Wedge?
    private var hot: NavigationWheel.Wedge?
    private var last = CGPoint.zero
    private var accum: CGFloat = 0
    private var moved = false

    init(state: DocumentState, viewID: ElementID, canvas: NSView, full: Bool) {
        self.state = state; self.viewID = viewID; self.canvas = canvas; self.full = full
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(full ? "Full Navigation Wheel" : "2D Wheel")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate], owner: self))
    }

    func close() {
        let c = canvas
        removeFromSuperview()
        if let c { c.window?.makeFirstResponder((c as? Viewport3DHost)?.viewport ?? c) }
        state.hoverDescription = ""
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        center = NavigationWheel.follow(center, p)
        let h = center.flatMap { NavigationWheel.wedge(full: full, center: $0, at: p) }
        if h != hot || state.hoverDescription.isEmpty { hot = h; state.hoverDescription = NavigationWheel.prompt(h) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        let c = center ?? p
        center = c
        if hypot(p.x - NavigationWheel.closeCenter(c).x, p.y - NavigationWheel.closeCenter(c).y) <= 9 { close(); return }
        held = NavigationWheel.wedge(full: full, center: c, at: p)
        last = p; accum = 0; moved = false
        // Wheel moves are history steps right away (Rewind goes back to them).
        if let h = held, h != .rewind {
            if let c2 = canvas as? Canvas2DView { c2.recordNavigation() }
            if let host = canvas as? Viewport3DHost {
                var hist = NavigationWheel.cameraHistory[viewID] ?? []
                if hist.last.map({ !$0.isAlmostEqual(host.viewport.camera) }) ?? true { hist.append(host.viewport.camera) }
                if hist.count > 50 { hist.removeFirst() }
                NavigationWheel.cameraHistory[viewID] = hist
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let wedge = held, let c = center else { return }
        let p = point(event)
        let dx = p.x - last.x, dy = p.y - last.y // screen points, y down
        last = p
        if abs(dx) + abs(dy) > 0 { moved = true }
        if let c2 = canvas as? Canvas2DView { drag2D(c2, wedge, dx: dx, dy: dy, center: c) }
        if let host = canvas as? Viewport3DHost { drag3D(host.viewport, wedge, dx: dx, dy: dy) }
        if wedge == .pan { center = CGPoint(x: c.x + dx, y: c.y + dy) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if held == .center, let host = canvas as? Viewport3DHost, let c = center {
            // Center: the point under the wheel's centre becomes the pivot.
            let vp = host.viewport
            let q = vp.convert(convert(c, to: nil), from: nil)
            if let hit = vp.pick(at: q).position {
                var cam = vp.camera
                let off = cam.eye - cam.target
                cam.target = hit; cam.eye = hit + off
                vp.camera = cam
            }
        }
        held = nil
        needsDisplay = true
    }

    /// The 2D Wheel: Zoom about the wheel's centre, Pan, Rewind through the view's previous pan and zoom.
    private func drag2D(_ canvas: Canvas2DView, _ w: NavigationWheel.Wedge, dx: CGFloat, dy: CGFloat, center c: CGPoint) {
        switch w {
        case .zoom:
            canvas.zoom(by: exp(-Double(dy) * 0.01), at: canvas.convert(convert(c, to: nil), from: nil))
        case .pan:
            canvas.center = canvas.center - Vec2(Double(dx), -Double(dy)) / canvas.zoom
            canvas.needsDisplay = true
        case .rewind:
            accum += dx
            if abs(accum) > 40 { canvas.stepNavigation(back: accum < 0); accum = 0 }
        default: break
        }
    }

    /// The Full Navigation Wheel of 3D views.
    private func drag3D(_ vp: Viewport3DView, _ w: NavigationWheel.Wedge, dx: CGFloat, dy: CGFloat) {
        var cam = vp.camera
        let dist = max(cam.distance, 1)
        let dx = Double(dx), dy = Double(dy)
        switch w {
        case .zoom:
            cam = CameraMotion.dolly(cam, factor: exp(-dy * 0.01))
        case .pan:
            let h = max(Double(vp.bounds.height), 1)
            let perPoint = cam.isPerspective ? 2 * dist * tan(cam.fieldOfView / 2) / h : cam.orthoHeight / h
            cam = CameraMotion.pan(cam, dx: -dx * perPoint, dy: dy * perPoint)
        case .orbit:
            let k = 0.45 * Double.pi / 180
            cam = CameraMotion.orbit(cam, yaw: -dx * k, pitch: dy * k, pivot: cam.target)
        case .look:
            cam = CameraMotion.fly(cam, yaw: -dx * 0.005, pitch: -dy * 0.005)
        case .walk:
            let f = Vec3(cam.forward.x, cam.forward.y, 0)
            guard f.length > 1e-9 else { return }
            let step = f.normalized * (-dy * dist * 0.004)
            cam.eye = cam.eye + step; cam.target = cam.target + step
        case .upDown:
            let step = Vec3.unitZ * (-dy * dist * 0.004)
            cam.eye = cam.eye + step; cam.target = cam.target + step
        case .rewind:
            accum += CGFloat(dx)
            if accum < -40, var hist = NavigationWheel.cameraHistory[viewID], let prev = hist.popLast() {
                NavigationWheel.cameraHistory[viewID] = hist
                cam = prev
                accum = 0
            }
        case .center:
            return
        }
        vp.camera = cam
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return } // Esc
        canvas?.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { close() }
    override func scrollWheel(with event: NSEvent) { ((canvas as? Viewport3DHost)?.viewport ?? canvas)?.scrollWheel(with: event) }
    override func magnify(with event: NSEvent) { ((canvas as? Viewport3DHost)?.viewport ?? canvas)?.magnify(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = center, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let R = NavigationWheel.outerRadius
        ctx.setFillColor(NSColor.black.withAlphaComponent(40 / 255).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x + 2 - R - 1, y: c.y + 3 - R - 1, width: 2 * R + 2, height: 2 * R + 2))
        let active = held ?? hot
        for s in NavigationWheel.sectors(full: full) {
            let inner = full && s.r1 <= NavigationWheel.middleRadius + 0.1
            let base = inner ? NSColor(srgbRed: 70 / 255, green: 76 / 255, blue: 86 / 255, alpha: 225 / 255) : NSColor(srgbRed: 44 / 255, green: 48 / 255, blue: 56 / 255, alpha: 215 / 255)
            let fill = held == s.wedge ? NSColor(srgbRed: 40 / 255, green: 110 / 255, blue: 200 / 255, alpha: 235 / 255)
                : active == s.wedge ? NSColor(srgbRed: 70 / 255, green: 130 / 255, blue: 210 / 255, alpha: 225 / 255) : base
            let a0 = s.a0 * .pi / 180, a1 = s.a1 * .pi / 180
            let path = CGMutablePath()
            path.addArc(center: c, radius: s.r1, startAngle: a0, endAngle: a1, clockwise: false)
            path.addArc(center: c, radius: s.r0, startAngle: a1, endAngle: a0, clockwise: true)
            path.closeSubpath()
            ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(70 / 255).cgColor); ctx.setLineWidth(1)
            for a in [a0, a1] {
                ctx.move(to: CGPoint(x: c.x + cos(a) * s.r0, y: c.y + sin(a) * s.r0))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * s.r1, y: c.y + sin(a) * s.r1))
            }
            ctx.strokePath()
            let am = (a0 + a1) / 2, rm = (s.r0 + s.r1) / 2
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: inner ? 8.5 : 10), .foregroundColor: NSColor.white]
            let text = NSAttributedString(string: s.wedge.rawValue, attributes: attrs)
            let size = text.size()
            text.draw(at: CGPoint(x: c.x + cos(am) * rm - size.width / 2, y: c.y + sin(am) * rm - size.height / 2))
        }
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(90 / 255).cgColor)
        ctx.strokeEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
        ctx.setFillColor(NSColor.white.withAlphaComponent(200 / 255).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
        // Close cross.
        let x = NavigationWheel.closeCenter(c)
        ctx.setFillColor(NSColor(srgbRed: 44 / 255, green: 48 / 255, blue: 56 / 255, alpha: 230 / 255).cgColor)
        ctx.fillEllipse(in: CGRect(x: x.x - 8, y: x.y - 8, width: 16, height: 16))
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.3)
        ctx.move(to: CGPoint(x: x.x - 3, y: x.y - 3)); ctx.addLine(to: CGPoint(x: x.x + 3, y: x.y + 3))
        ctx.move(to: CGPoint(x: x.x + 3, y: x.y - 3)); ctx.addLine(to: CGPoint(x: x.x - 3, y: x.y + 3))
        ctx.strokePath()
    }
}
