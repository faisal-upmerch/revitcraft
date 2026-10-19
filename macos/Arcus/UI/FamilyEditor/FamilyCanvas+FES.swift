import AppKit
import ArcusGeometry
import ArcusDomain

// FES: the family canvas under the floating shell. It fills the window edge to edge, so zoom to fit and its captions
// keep to the part of the drawing that isn't under the docks, the ribbon or the bottom pill (as the project canvas
// does with its safe-area insets), and it reports its zoom and grid step to the bottom pill.

enum FamilyCanvasFit {
    /// What a zoom to fit was made for.
    struct Record {
        var size: CGSize
        var insets: NSEdgeInsets
        var camera: FamilyEditing.Camera
        /// The view's size or the shell's insets changed since the fit.
        func isStale(size s: CGSize, insets i: NSEdgeInsets) -> Bool {
            s != size || i.top != insets.top || i.left != insets.left || i.bottom != insets.bottom || i.right != insets.right
        }
    }

    /// A camera that shows `bounds` in the part of a `size` view inside `insets` (top-left origin), with a margin.
    static func camera(_ bounds: Rect2, size: Vec2, insets: NSEdgeInsets, margin: Double = 48) -> FamilyEditing.Camera {
        let visible = Vec2(max(80, size.x - insets.left - insets.right), max(80, size.y - insets.top - insets.bottom))
        var c = FamilyEditing.Camera.fitting(bounds, size: visible, inset: margin)
        // Move the fitted centre so it lands at the centre of the visible part rather than of the whole view.
        let dx = (Double(insets.left) - Double(insets.right)) / 2, dy = (Double(insets.top) - Double(insets.bottom)) / 2
        c.center = Vec2(c.center.x - dx / c.scale, c.center.y + dy / c.scale)
        return c
    }
}

extension FamilyCanvasView {
    /// The middle of the part of the view not under the shell.
    var visibleCenter: Vec2 {
        Vec2(Double(chromeInsets.left) + (Double(bounds.width) - Double(chromeInsets.left) - Double(chromeInsets.right)) / 2,
             Double(chromeInsets.top) + (Double(bounds.height) - Double(chromeInsets.top) - Double(chromeInsets.bottom)) / 2)
    }

    /// Fits again when the window or the shell changed since the last fit and the user hasn't zoomed or panned since.
    func refitIfUntouched() {
        guard let f = lastFit, f.camera == camera, f.isStale(size: bounds.size, insets: chromeInsets) else { return }
        zoomToFit()
    }

    /// Zooms to `scale` points per metre about the middle of the visible part (the bottom pill's zoom menu).
    func zoom(toScale scale: Double) {
        guard scale > 0, camera.scale > 0 else { return }
        camera = camera.zoomed(by: scale / camera.scale, at: visibleCenter, size: Vec2(bounds.width, bounds.height))
        needsDisplay = true
    }

    /// Tells the bottom pill the zoom (after the current update, never during one).
    func reportZoom() {
        let s = camera.scale
        DispatchQueue.main.async { [weak self] in
            guard let chrome = self?.model?.chrome, abs(chrome.zoomScale - s) > 1e-6 else { return }
            chrome.zoomScale = s
        }
    }

    /// Tells the bottom pill the grid step drawn (metres).
    func reportGrid(_ step: Double) {
        guard let chrome = model?.chrome, chrome.gridStep != step else { return }
        DispatchQueue.main.async { chrome.gridStep = step }
    }
}
