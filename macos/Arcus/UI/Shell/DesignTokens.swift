import AppKit
import SwiftUI
import ArcusDomain
import ArcusCalc

// Disambiguate Domain names that collide with Foundation/ObjectiveC types.
typealias Category = ArcusDomain.Category
typealias QuantityDimension = ArcusCalc.Dimension
typealias RGBColor = ArcusDomain.RGBColor

/// One design-token layer for Arcus: colors, spacing, metrics, typography.
enum Tokens {
    // MARK: Color
    /// Selection tint: a strong blue by default, or the colour chosen in Settings ▸ Colors. // BL-CANVAS: ARCUS-027
    static let selection = NSColor(name: "arcus.selection") { ap in
        CanvasSettings.nsColor(.selection, dark: ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil)
    }
    /// Pre-selection (hover) tint: lighter than the selection. // BL-CANVAS
    static let preselection = NSColor(name: "arcus.preselection") { ap in
        CanvasSettings.nsColor(.preselection, dark: ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil)
    }
    /// Elements named by errors and warnings (sketch lines that don't close, for example). // BL-CANVAS
    static let alert = NSColor(name: "arcus.alert") { ap in
        CanvasSettings.nsColor(.alert, dark: ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil)
    }
    /// Warm white model canvas (light) / graphite drafting field (dark).
    static let canvas = NSColor(name: "arcus.canvas") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
            ? (CanvasTheme.current == .black ? CanvasTheme.blackCanvas : NSColor(srgbRed: 0.145, green: 0.150, blue: 0.160, alpha: 1)) // F810: Black canvas theme
            : NSColor(srgbRed: 0.985, green: 0.980, blue: 0.965, alpha: 1)
    }
    static let paper = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let sheetBackdrop = NSColor(name: "arcus.sheetBackdrop") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil ? NSColor(srgbRed: 0.10, green: 0.105, blue: 0.11, alpha: 1) : NSColor(srgbRed: 0.86, green: 0.86, blue: 0.85, alpha: 1)
    }
    static let construction = NSColor(name: "arcus.construction") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil ? NSColor(srgbRed: 0.42, green: 0.62, blue: 0.80, alpha: 0.9) : NSColor(srgbRed: 0.24, green: 0.47, blue: 0.68, alpha: 0.9)
    }
    static let warning = NSColor.systemOrange
    static let error = NSColor.systemRed

    static var selectionColor: Color { Color(nsColor: selection) }

    // MARK: Spacing & metrics
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 6
    static let spacingM: CGFloat = 10
    static let spacingL: CGFloat = 16
    static let inspectorRowHeight: CGFloat = 22
    static let inspectorLabelWidth: CGFloat = 112 // W4-AUDIT: value column keeps "Wall Centerline" untruncated at 300 pt
    static let sidebarMinWidth: CGFloat = 280 // BL-PROPS: room for "Wall Centerline", "Ground Floor"
    /// Width of the left dock on first launch (users resize it; the split view remembers). BL-PROPS
    static let sidebarDefaultWidth: CGFloat = 300
    static let sidebarMaxWidth: CGFloat = 480
    static let inspectorMinWidth: CGFloat = 260
    static let canvasMinWidth: CGFloat = 480
    /// The ribbon's panel strip (a floating glass bar under the tab pill; ShellLayout places it). // W4-WIRE
    static let ribbonPanelHeight: CGFloat = 92
    /// Contextual ("Modify | …") tabs use a green accent, as users of mainstream BIM tools expect.
    static let contextualTint = Color(red: 0.16, green: 0.58, blue: 0.30)
    /// The bottom pill's content: view controls, prompt, coordinates, warnings and selection. // W4-WIRE
    static let bottomBarHeight: CGFloat = 36

    // MARK: Typography
    static let monoDigits = Font.system(size: 11).monospacedDigit()
    static let small = Font.system(size: 11)
    static let label = Font.system(size: 11, weight: .regular)
    static let groupHeader = Font.system(size: 11, weight: .semibold)
}

/// PILLS: the one geometry for a selected or hovered capsule inside a pill, a segmented track or any container: tabs,
/// segmented controls, chips, toggles and selected rows. A selected capsule never hugs its container or its content.
/// See Docs/Dialogs.md, "Pills and selection".
enum PillSpec {
    /// Gap between a selected capsule and the glass pill around it, all round (36 pt pill → 28 pt capsule).
    static let inset: CGFloat = 4
    /// Gap between a segment and its segmented track, all round (smaller tracks, same look).
    static let trackInset: CGFloat = 3
    /// Side padding between a capsule's edge and its text or icon, each side.
    static let padding: CGFloat = 12
    /// Trailing padding before a close button: its 16 pt circle carries ~4 pt of air, so the ✕ sits 12 pt in, as the
    /// leading icon does.
    static let closePadding: CGFloat = 8
    /// Space between neighbouring capsules in one container.
    static let gap: CGFloat = 2
    /// Side padding of a selected list row inside its list (the row itself sits `inset` or more from the list edge).
    static let rowPadding: CGFloat = 12

    /// A capsule's height inside a container `outer` tall.
    static func height(in outer: CGFloat, inset: CGFloat = inset) -> CGFloat { max(0, outer - 2 * inset) }
    /// A rounded selection's corner radius inside a container of radius `outer` (concentric corners).
    static func radius(inside outer: CGFloat, inset: CGFloat = inset) -> CGFloat { max(0, outer - inset) }

    /// Capsule heights: shell pills (ribbon tabs, controls, bottom bar), view tabs, and segmented controls.
    static let shellItemHeight: CGFloat = 28 // 36 pt pill
    static let viewTabItemHeight: CGFloat = 22 // 30 pt view-tab pill
    /// The close button's circle in a view tab.
    static let closeButtonSize: CGFloat = 16

    // Fills (light and dark come from `primary` and the tint).
    /// Hover wash.
    static let hoverOpacity: Double = 0.07
    /// Selected, neutral (ribbon tabs, a chosen toggle without a tint).
    static let selectedOpacity: Double = 0.11
    /// Selected, tinted (the active view tab, a contextual tab, an "on" toggle): fill and edge.
    static let tintOpacity: Double = 0.2
    static let tintEdgeOpacity: Double = 0.5
}

extension RGBColor {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(nsColor: nsColor) }
    static func from(_ ns: NSColor) -> RGBColor {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        return RGBColor(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }
}

/// Accessibility environment helpers.
enum AccessibilityPrefs {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
}

extension View {
    /// Applies an animation unless Reduce Motion is on (then changes are instant).
    func arcusAnimation<V: Equatable>(_ value: V) -> some View {
        animation(AccessibilityPrefs.reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
    }
}
