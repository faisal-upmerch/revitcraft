import Foundation
import ArcusDomain

/// Options controlling how `GraphicsRenderer` draws a display list.
///
/// Screen and print share one renderer; the differences are expressed here:
/// - `thinLines` is a screen-only convenience (every stroke one device pixel) and is ignored when `printing` is true.
/// - `darkCanvas` inverts near-black ink to a light ink and maps white paper/masking to the canvas color; ignored when printing.
/// - `showOverlays` controls the `.overlay` layer (crop outlines, sheet guide grids). The PDF exporter sets it from
///   `PDFExportJob.hideCropBoundaries`; interactive views normally leave it on.
public struct RenderOptions: Sendable {
    /// Screen only: every stroke is drawn one device pixel wide. Never honored when `printing` is true.
    public var thinLines = false
    /// True for PDF/print output. Disables `thinLines` and `darkCanvas`.
    public var printing = false
    /// Paper/canvas color painted behind the drawing and used for masking regions and halftone blending.
    /// `nil` paints nothing (PDF pages stay transparent; masks and halftone then use white).
    public var background: RGBColor? = .white
    /// Screen dark appearance: near-black ink becomes light, white paper/masking becomes the canvas color.
    public var darkCanvas = false
    /// Canvas colour for masks and dark mapping when `background` is nil (overlay passes never paint a background,
    /// but masks in them — a door preview's wall gap — must still match the canvas).
    public var canvasColor: RGBColor? = nil
    /// Selection / preselection tint per element: strokes and text take this color, fills are blended toward it.
    public var highlight: [ElementID: RGBColor] = [:]
    /// I1: colour laid over the fills of a highlighted element (its alpha is the coverage), as RevitCraft paints its
    /// selection blue over areas. Highlighted elements without an entry blend their fills 65 % toward `highlight`.
    public var highlightFill: [ElementID: RGBColor] = [:]
    /// Fraction (0…1) by which halftoned graphics blend toward the background.
    public var halftoneAmount = 0.55
    /// Draw `.overlay` items (crop outlines, guide grids).
    public var showOverlays = true
    /// Items belonging to these elements are skipped.
    public var hiddenElements: Set<ElementID> = []
    /// Minimum stroke width in device units (points of the target context's user space).
    public var minimumDevicePixel = 0.5
    public init() {}

    /// Options used for vector PDF output.
    public static func pdf(showOverlays: Bool) -> RenderOptions {
        var o = RenderOptions()
        o.printing = true
        o.background = nil
        o.showOverlays = showOverlays
        // 0.1 pt ≈ 0.035 mm: keeps hairlines printable when a view is scaled down to fit a page.
        o.minimumDevicePixel = 0.1
        return o
    }
}
