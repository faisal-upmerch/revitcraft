import AppKit
import simd

/// Compact orientation control (an orientation cube): a labeled cube (TOP/FRONT/RIGHT…) above a compass ring
/// (N/E/S/W), plus a home button. Click a face to look at it, an edge for the view between its two faces, a corner for
/// the matching isometric view (top corners) or view from below (bottom corners), a compass letter for the elevation
/// from that side; drag to orbit. BL-SITE (ARCUS-031): edges, bottom corners and compass letters are clickable.
@MainActor final class OrientationWidget: NSView {
    var basisProvider: (() -> (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>))?
    var onOrient: ((OrientationPreset) -> Void)?
    /// BL-SITE: orient to look from a direction (toward the model), for edges and bottom corners.
    var onOrientDirection: ((SIMD3<Double>) -> Void)?
    var onOrbitDrag: ((Double, Double) -> Void)?
    var isDark = false { didSet { needsDisplay = true } }

    /// What a point of the widget does when clicked.
    enum Target: Equatable { case face(OrientationPreset), corner(OrientationPreset), direction(SIMD3<Double>), compass(OrientationPreset), home }
    private var hovered: Target? { didSet { if oldValue != hovered { needsDisplay = true } } }
    private var dragStart: CGPoint?
    private var lastDrag: CGPoint = .zero
    private var dragged = false

    private let cubeHalf = 20.0
    private var cubeCenter: CGPoint { CGPoint(x: bounds.midX + 4, y: bounds.maxY - 56) }
    private var homeRect: CGRect { CGRect(x: 4, y: 4, width: 24, height: 24) }

    private struct Face {
        let preset: OrientationPreset
        let label: String
        let normal: SIMD3<Double>
        /// Label axes on the face (reading direction, up) as seen from outside.
        let u: SIMD3<Double>
        let v: SIMD3<Double>
    }
    private let faces: [Face] = [
        Face(preset: .top, label: "TOP", normal: SIMD3(0, 0, 1), u: SIMD3(1, 0, 0), v: SIMD3(0, 1, 0)),
        Face(preset: .bottom, label: "BOTTOM", normal: SIMD3(0, 0, -1), u: SIMD3(1, 0, 0), v: SIMD3(0, -1, 0)),
        Face(preset: .front, label: "FRONT", normal: SIMD3(0, -1, 0), u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1)),
        Face(preset: .back, label: "BACK", normal: SIMD3(0, 1, 0), u: SIMD3(-1, 0, 0), v: SIMD3(0, 0, 1)),
        Face(preset: .right, label: "RIGHT", normal: SIMD3(1, 0, 0), u: SIMD3(0, 1, 0), v: SIMD3(0, 0, 1)),
        Face(preset: .left, label: "LEFT", normal: SIMD3(-1, 0, 0), u: SIMD3(0, -1, 0), v: SIMD3(0, 0, 1)),
    ]
    private let corners: [(OrientationPreset, SIMD3<Double>)] = [
        (.northEastIso, SIMD3(1, 1, 1)), (.northWestIso, SIMD3(-1, 1, 1)), (.southEastIso, SIMD3(1, -1, 1)), (.southWestIso, SIMD3(-1, -1, 1)),
    ]
    /// BL-SITE: the bottom corners and the twelve edges (cube coordinates; also the view-from direction).
    private let lowerCorners: [SIMD3<Double>] = [SIMD3(1, 1, -1), SIMD3(-1, 1, -1), SIMD3(1, -1, -1), SIMD3(-1, -1, -1)]
    private let edges: [SIMD3<Double>] = [
        SIMD3(1, 0, 1), SIMD3(-1, 0, 1), SIMD3(0, 1, 1), SIMD3(0, -1, 1),
        SIMD3(1, 1, 0), SIMD3(-1, 1, 0), SIMD3(1, -1, 0), SIMD3(-1, -1, 0),
        SIMD3(1, 0, -1), SIMD3(-1, 0, -1), SIMD3(0, 1, -1), SIMD3(0, -1, -1),
    ]
    private static let compassLetters: [(String, Double, OrientationPreset)] = [
        ("N", Double.pi / 2, .back), ("E", 0.0, .right), ("S", -Double.pi / 2, .front), ("W", Double.pi, .left),
    ]

    /// A cube feature (corner or edge) faces the viewer when one of the faces it touches does.
    private func isVisible(_ c: SIMD3<Double>, _ b: (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>)) -> Bool {
        faces.contains { f in dot(f.normal, c) > 0 && -dot(f.normal, b.forward) > 0.02 }
    }

    /// Where a compass letter sits on the ring.
    private func compassPoint(_ angle: Double, _ b: (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>)) -> CGPoint {
        let r = 2.05
        return project(SIMD3(cos(angle) * r, sin(angle) * r, -1), b, scale: cubeHalf)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("View orientation")
        setAccessibilityHelp("Choose a standard view of the model")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        OrientationPreset.allCases.map { preset in
            NSAccessibilityCustomAction(name: preset == .home ? "Home view" : "\(preset.title) view") { [weak self] in
                self?.onOrient?(preset); return true
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: Projection

    private func basis() -> (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>) {
        basisProvider?() ?? (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1))
    }

    private func project(_ p: SIMD3<Double>, _ b: (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>), scale: Double) -> CGPoint {
        CGPoint(x: cubeCenter.x + dot(p, b.right) * scale, y: cubeCenter.y + dot(p, b.up) * scale)
    }

    private func facePolygon(_ f: Face, _ b: (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>)) -> [CGPoint] {
        let c = f.normal, u = f.u, v = f.v
        return [c - u - v, c + u - v, c + u + v, c - u + v].map { project($0, b, scale: cubeHalf) }
    }

    private func visibleFaces(_ b: (forward: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>)) -> [(Face, Double)] {
        faces.compactMap { f in
            let facing = -dot(f.normal, b.forward)
            return facing > 0.02 ? (f, facing) : nil
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = basis()
        let accent = NSColor(srgbRed: 0x2F / 255, green: 0x6F / 255, blue: 0xA8 / 255, alpha: 1)
        let ink = isDark ? NSColor(white: 0.88, alpha: 1) : NSColor(white: 0.22, alpha: 1)
        let faceFill = isDark ? NSColor(white: 0.28, alpha: 0.92) : NSColor(white: 0.985, alpha: 0.92)
        let stroke = isDark ? NSColor(white: 0.62, alpha: 0.9) : NSColor(white: 0.45, alpha: 0.9)

        // Compass ring in the XY plane at the cube's base: far half behind the cube, near half and labels in front.
        let ringR = cubeHalf * 2.05
        let z = -cubeHalf
        func ringPoint(_ a: Double) -> (CGPoint, Double) {
            let v = SIMD3(cos(a) * ringR / cubeHalf, sin(a) * ringR / cubeHalf, z / cubeHalf)
            return (project(v, b, scale: cubeHalf), dot(v, b.forward))
        }
        func strokeRing(front: Bool) {
            let path = CGMutablePath()
            var open = false
            for i in 0...96 {
                let (p, depth) = ringPoint(Double(i) / 96 * 2 * .pi)
                if (depth < 0) == front {
                    if open { path.addLine(to: p) } else { path.move(to: p); open = true }
                } else { open = false }
            }
            ctx.addPath(path)
            ctx.setStrokeColor(stroke.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
        strokeRing(front: false)
        // Cube faces (visible ones; convex, so no overlap).
        let lightDir = simd_normalize(SIMD3<Double>(-0.35, -0.45, 0.82))
        for (f, facing) in visibleFaces(b) {
            let poly = facePolygon(f, b)
            let shade = 0.84 + 0.16 * max(0, dot(f.normal, lightDir))
            var fill = faceFill.blended(withFraction: 1 - shade, of: isDark ? .black : NSColor(white: 0.6, alpha: 1)) ?? faceFill
            if hovered == .face(f.preset) { fill = fill.blended(withFraction: 0.45, of: accent) ?? fill }
            let p = CGMutablePath()
            p.addLines(between: poly); p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
            ctx.addPath(p)
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            // Label mapped onto the face plane.
            guard facing > 0.25 else { continue }
            let o = project(f.normal, b, scale: cubeHalf)
            let ux = project(f.normal + f.u, b, scale: cubeHalf), vy = project(f.normal + f.v, b, scale: cubeHalf)
            let e1 = CGPoint(x: ux.x - o.x, y: ux.y - o.y), e2 = CGPoint(x: vy.x - o.x, y: vy.y - o.y)
            let t = CGAffineTransform(a: e1.x / cubeHalf, b: e1.y / cubeHalf, c: e2.x / cubeHalf, d: e2.y / cubeHalf, tx: o.x, ty: o.y)
            let labelFont = NSFont.systemFont(ofSize: f.label.count > 5 ? 7 : 8.5, weight: .bold)
            let color = hovered == .face(f.preset) ? (isDark ? NSColor.white : NSColor.black) : ink
            let s = NSAttributedString(string: f.label, attributes: [.font: labelFont, .foregroundColor: color.withAlphaComponent(0.4 + 0.6 * min(1, facing * 1.4))])
            let sz = s.size()
            ctx.saveGState()
            ctx.concatenate(t)
            s.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2 + 0.5))
            ctx.restoreGState()
        }

        strokeRing(front: true)
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        for (label, angle, preset) in Self.compassLetters {
            let (p, _) = ringPoint(angle)
            let color = label == "N" || hovered == .compass(preset) ? accent : ink.withAlphaComponent(0.85) // BL-SITE: hover
            let s = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            let sz = s.size()
            let r = CGRect(x: p.x - sz.width / 2 - 2.5, y: p.y - sz.height / 2 - 0.5, width: sz.width + 5, height: sz.height + 1)
            (isDark ? NSColor(white: 0.2, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)).setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
            s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
        }

        // Clickable top corners.
        for (preset, c) in corners {
            let facingAny = faces.contains { f in dot(f.normal, c) > 0 && -dot(f.normal, b.forward) > 0.02 }
            guard facingAny else { continue }
            let p = project(c, b, scale: cubeHalf)
            let hot = hovered == .corner(preset)
            let r = hot ? 4.5 : 2.5
            ctx.setFillColor((hot ? accent : stroke).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }

        // BL-SITE: the hovered edge or lower corner.
        if case .direction(let d)? = hovered {
            let p = project(d, b, scale: cubeHalf)
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }

        // Home button.
        let hr = homeRect
        let hot = hovered == .home
        let bg = NSBezierPath(roundedRect: hr, xRadius: 6, yRadius: 6)
        (hot ? accent.withAlphaComponent(0.2) : faceFill).setFill()
        bg.fill()
        stroke.withAlphaComponent(0.6).setStroke()
        bg.lineWidth = 0.75
        bg.stroke()
        if let img = NSImage(systemSymbolName: "house", accessibilityDescription: "Home view") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let sized = img.withSymbolConfiguration(cfg) ?? img
            let tinted = NSImage(size: sized.size, flipped: false) { rect in
                sized.draw(in: rect)
                (hot ? accent : ink).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let s = tinted.size
            tinted.draw(in: CGRect(x: hr.midX - s.width / 2, y: hr.midY - s.height / 2, width: s.width, height: s.height))
        }
    }

    // MARK: Hit testing

    func target(at p: CGPoint) -> Target? {
        if homeRect.insetBy(dx: -2, dy: -2).contains(p) { return .home }
        let b = basis()
        for (preset, c) in corners {
            guard isVisible(c, b) else { continue }
            let q = project(c, b, scale: cubeHalf)
            if hypot(q.x - p.x, q.y - p.y) < 6 { return .corner(preset) }
        }
        // BL-SITE: bottom corners, then edges (their midpoints), then compass letters.
        for c in lowerCorners where isVisible(c, b) {
            let q = project(c, b, scale: cubeHalf)
            if hypot(q.x - p.x, q.y - p.y) < 6 { return .direction(c) }
        }
        for e in edges where isVisible(e, b) {
            let q = project(e, b, scale: cubeHalf)
            if hypot(q.x - p.x, q.y - p.y) < 5 { return .direction(e) }
        }
        for (_, angle, preset) in Self.compassLetters {
            let q = compassPoint(angle, b)
            if hypot(q.x - p.x, q.y - p.y) < 7 { return .compass(preset) }
        }
        for (f, _) in visibleFaces(b) {
            let poly = facePolygon(f, b)
            let path = CGMutablePath()
            path.addLines(between: poly); path.closeSubpath()
            if path.contains(p) { return .face(f.preset) }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        if target(at: p) != nil { return self }
        // The ring area is also draggable; elsewhere let events reach the viewport.
        let d = hypot(p.x - cubeCenter.x, p.y - cubeCenter.y)
        return d < cubeHalf * 2.1 ? self : nil
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = target(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p; lastDrag = p; dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let s = dragStart else { return }
        if !dragged && hypot(p.x - s.x, p.y - s.y) < 3 { return }
        dragged = true
        onOrbitDrag?(Double(p.x - lastDrag.x) * 1.5, Double(p.y - lastDrag.y) * 1.5)
        lastDrag = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard !dragged else { return }
        switch target(at: convert(event.locationInWindow, from: nil)) {
        case .face(let preset)?, .corner(let preset)?, .compass(let preset)?: onOrient?(preset)
        case .direction(let d)?: onOrientDirection?(d) // BL-SITE
        case .home?: onOrient?(.home)
        case nil: break
        }
    }
}
