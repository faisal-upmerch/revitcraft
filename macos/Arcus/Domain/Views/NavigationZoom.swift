import Foundation

/// BL-SITE (ARCUS-030): wheel and pinch zoom shared by plan, elevation, section and 3D views, so one wheel notch or
/// one scroll distance changes the scale by the same ratio everywhere.
public enum NavigationZoom {
    /// Scale change per mouse-wheel notch (one line of scrolling).
    public static let notchFactor = 1.18
    /// Scale change per point of continuous (trackpad or smooth-wheel) scrolling.
    public static let pointFactor = 1.006

    /// Zoom factor for a scroll of `dy` (positive = zoom in): lines for notched wheels, points for precise scrolling.
    public static func factor(dy: Double, precise: Bool) -> Double {
        precise ? pow(pointFactor, max(-300, min(300, dy))) : pow(notchFactor, max(-4, min(4, dy)))
    }
}
