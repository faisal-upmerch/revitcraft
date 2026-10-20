import AppKit
import SwiftUI
import ArcusDomain

// VIS: the View Control Bar's state icons, drawn as template images so they work in menu labels and follow light and
// dark: detail level (Revit-style: a section square, empty at Coarse, hatched at Medium, densely hatched with a round
// part at Fine) and visual style (an isometric cube drawn the way the style draws: wireframe, hidden line, shaded,
// consistent colors, transparent, realistic).

/// Template images for detail levels and visual styles.
@MainActor enum ViewStateIcons {
    static let size = NSSize(width: 16, height: 16)
    private static var cache: [String: NSImage] = [:]

    /// The icon for a detail level.
    static func detail(_ d: DetailLevel) -> NSImage {
        image("detail-\(d.rawValue)") { _ in
            let r = NSRect(x: 2.5, y: 2.5, width: 11, height: 11)
            let box = NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5)
            box.lineWidth = 1.3
            NSColor.black.setStroke()
            box.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r.insetBy(dx: 0.6, dy: 0.6)).addClip()
            let lines: Int = switch d { case .coarse: 0; case .medium: 2; case .fine: 4 }
            let hatch = NSBezierPath()
            hatch.lineWidth = 1
            for k in 0..<lines {
                let o = r.minX - r.height + (r.width + r.height) * (Double(k) + 1) / Double(lines + 1)
                hatch.move(to: NSPoint(x: o, y: r.minY)); hatch.line(to: NSPoint(x: o + r.height, y: r.maxY))
            }
            NSColor.black.withAlphaComponent(0.85).setStroke()
            hatch.stroke()
            NSGraphicsContext.restoreGraphicsState()
            if d == .coarse {
                // Coarse: one bold centre line, the simplest representation.
                let mid = NSBezierPath()
                mid.lineWidth = 1.3
                mid.move(to: NSPoint(x: r.minX + 2.5, y: r.midY)); mid.line(to: NSPoint(x: r.maxX - 2.5, y: r.midY))
                mid.stroke()
            }
            if d == .fine {
                // Fine: a round part in the corner, the curves Fine draws smooth.
                let c = NSBezierPath(ovalIn: NSRect(x: 9.2, y: 0.8, width: 6, height: 6))
                NSColor.black.setFill(); c.fill()
            }
        }
    }

    /// The icon for a visual style.
    static func style(_ s: VisualStyle) -> NSImage {
        image("style-\(s.rawValue)") { _ in
            // Isometric cube: centre c, top face, left and right faces.
            let c = NSPoint(x: 8, y: 7.2), w = 5.6, h = 3.2, v = 6.4
            let left = NSPoint(x: c.x - w, y: c.y + h / 2), right = NSPoint(x: c.x + w, y: c.y + h / 2)
            let back = NSPoint(x: c.x, y: c.y + 2 * h)
            func down(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x, y: p.y - v) }
            func poly(_ pts: [NSPoint]) -> NSBezierPath {
                let p = NSBezierPath(); p.move(to: pts[0]); for q in pts.dropFirst() { p.line(to: q) }; p.close(); return p
            }
            let topFace = poly([c, right, back, left]), leftFace = poly([c, left, down(left), down(c)]), rightFace = poly([c, down(c), down(right), right])
            let faces: (Double, Double, Double)? = switch s {
            case .wireframe, .hiddenLine: nil
            case .shaded: (0.30, 0.55, 0.80)
            case .consistentColors: (0.55, 0.55, 0.55)
            case .transparent: (0.18, 0.18, 0.18)
            case .realistic: (0.25, 0.5, 0.85)
            }
            if let f = faces {
                NSColor.black.withAlphaComponent(f.0).setFill(); topFace.fill()
                NSColor.black.withAlphaComponent(f.1).setFill(); leftFace.fill()
                NSColor.black.withAlphaComponent(f.2).setFill(); rightFace.fill()
            }
            // Edges hidden behind the cube: Wireframe and Transparent show them.
            if s == .wireframe || s == .transparent {
                let hidden = NSBezierPath()
                hidden.lineWidth = s == .wireframe ? 1.1 : 0.9
                let backDown = down(back)
                hidden.move(to: backDown); hidden.line(to: back)
                hidden.move(to: backDown); hidden.line(to: down(left))
                hidden.move(to: backDown); hidden.line(to: down(right))
                if s == .transparent { hidden.setLineDash([1.6, 1.1], count: 2, phase: 0) } // Wireframe: every edge solid
                NSColor.black.withAlphaComponent(s == .wireframe ? 0.95 : 0.7).setStroke()
                hidden.stroke()
            }
            let edges = NSBezierPath()
            edges.lineWidth = s == .consistentColors || s == .realistic ? 0.9 : 1.2
            edges.lineJoinStyle = .round
            edges.append(topFace); edges.append(leftFace); edges.append(rightFace)
            NSColor.black.setStroke()
            edges.stroke()
            if s == .realistic {
                // A sun: Realistic lights with the sun and sky.
                let sun = NSBezierPath(ovalIn: NSRect(x: 11.6, y: 11.6, width: 4, height: 4))
                NSColor.black.setFill(); sun.fill()
            }
        }
    }

    private static func image(_ key: String, _ draw: @escaping (NSRect) -> Void) -> NSImage {
        if let hit = cache[key] { return hit }
        let img = NSImage(size: size, flipped: false) { r in draw(r); return true }
        img.isTemplate = true
        cache[key] = img
        return img
    }
}

extension DetailLevel {
    /// VIS: "Detail Level: Fine", the control's tooltip.
    var controlHelp: String { "Detail Level: \(rawValue)" }
}

/// VIS: a View Control Bar menu label: the state icon in a fixed frame.
struct ViewControlIcon: View {
    let image: NSImage
    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .frame(width: 18, height: 16)
    }
}
