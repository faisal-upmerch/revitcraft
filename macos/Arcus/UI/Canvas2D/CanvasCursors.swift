import AppKit
import ArcusApplication

/// I1: the canvas cursors RevitCraft draws (crates/rc-app canvas.rs `paint_crosshair`, `paint_move_glyph`), made as
/// resolution-independent `NSCursor`s so they stay crisp on every display.
@MainActor
enum CanvasCursors {
    /// The drawing cursor: four short grey arms around a small gap and a centre dot, on a light halo.
    static let crosshair: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            let c = NSPoint(x: 12, y: 12)
            let (gap, arm): (CGFloat, CGFloat) = (2.5, 7)
            for (width, color) in [(CGFloat(3.4), NSColor(white: 1, alpha: 0.67)), (1.6, NSColor(white: 78 / 255, alpha: 1))] {
                let path = NSBezierPath()
                for d in [NSPoint(x: 1, y: 0), NSPoint(x: -1, y: 0), NSPoint(x: 0, y: 1), NSPoint(x: 0, y: -1)] {
                    path.move(to: NSPoint(x: c.x + d.x * gap, y: c.y + d.y * gap))
                    path.line(to: NSPoint(x: c.x + d.x * (gap + arm), y: c.y + d.y * (gap + arm)))
                }
                path.lineWidth = width
                color.setStroke()
                path.stroke()
            }
            NSColor(white: 78 / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 0.8, y: c.y - 0.8, width: 1.6, height: 1.6)).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    /// Move and Copy: the arrow with a small four-way glyph below and to the right of its tip.
    static let arrowWithMove: NSCursor = {
        let arrow = NSCursor.arrow
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: true) { _ in
            arrow.image.draw(in: NSRect(origin: .zero, size: arrow.image.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let tip = arrow.hotSpot
            drawFourWay(center: NSPoint(x: tip.x + 13, y: tip.y + 15), radius: 6)
            return true
        }
        return NSCursor(image: image, hotSpot: arrow.hotSpot)
    }()

    /// Over a selected element that can be dragged: the four-way move arrow.
    static let fourWayMove: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            drawFourWay(center: NSPoint(x: 12, y: 12), radius: 8)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    /// A four-way arrow: black on a white halo (symmetric, so it reads the same in flipped and unflipped images).
    private static func drawFourWay(center c: NSPoint, radius r: CGFloat) {
        for (width, color) in [(CGFloat(3), NSColor.white), (1.2, NSColor.black)] {
            let shaft = NSBezierPath()
            shaft.move(to: NSPoint(x: c.x - r, y: c.y)); shaft.line(to: NSPoint(x: c.x + r, y: c.y))
            shaft.move(to: NSPoint(x: c.x, y: c.y - r)); shaft.line(to: NSPoint(x: c.x, y: c.y + r))
            shaft.lineWidth = width
            color.setStroke()
            shaft.stroke()
            for d in [NSPoint(x: 1, y: 0), NSPoint(x: -1, y: 0), NSPoint(x: 0, y: 1), NSPoint(x: 0, y: -1)] {
                let n = NSPoint(x: -d.y, y: d.x)
                let tip = NSPoint(x: c.x + d.x * (r + 2), y: c.y + d.y * (r + 2))
                let head = NSBezierPath()
                head.move(to: tip)
                head.line(to: NSPoint(x: tip.x - d.x * 3.5 + n.x * 2.6, y: tip.y - d.y * 3.5 + n.y * 2.6))
                head.line(to: NSPoint(x: tip.x - d.x * 3.5 - n.x * 2.6, y: tip.y - d.y * 3.5 - n.y * 2.6))
                head.close()
                head.lineWidth = width - 1
                color.setFill(); color.setStroke()
                head.fill(); head.stroke()
            }
        }
    }
}

extension Canvas2DView {
    /// Modify tools that keep the system arrow while they run, as in RevitCraft (Move and Copy add a move glyph).
    static let arrowCursorTools: Set<CommandID> = [.rotate, .align, .offset, .mirrorPickAxis, .mirrorDrawAxis, .array, .scale,
                                                   .trimExtendCorner, .trimExtendSingle, .trimExtendMultiple, .split]
}
