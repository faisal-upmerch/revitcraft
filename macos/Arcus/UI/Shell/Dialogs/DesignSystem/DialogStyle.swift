import AppKit
import SwiftUI

// DIALOGS: the dialog design system's tokens (Docs/Dialogs.md). Every modal is an `ArcusDialog`: a header (icon tile,
// title, subtitle), grouped content on an 8 pt grid inside 20 pt outer padding, and a footer bar under a full-width
// separator. Sizes come from a size class; heights follow the content up to the class's maximum, then the content
// scrolls. Colours are dynamic (light and dark) and every surface is opaque.

/// Width class of a dialog. The sheet is as wide as its class and as tall as its content (up to `maxContentHeight`).
enum DialogSize: Equatable, Sendable {
    /// Prompts and single-purpose forms (Rename, New Family, Select by ID).
    case small
    /// Most dialogs: forms with sections, short lists (Filter Selection, Import IFC).
    case medium
    /// Master-detail and table dialogs (Design Options, Model Health, Revisions).
    case large
    /// Editors with several panes (Materials, Type Properties, Filters, Schedule Properties).
    case wide
    /// Override tables with many columns (Visibility/Graphics).
    case extraWide

    var width: CGFloat {
        switch self {
        case .small: 420
        case .medium: 560
        case .large: 720
        case .wide: 900
        case .extraWide: 1120
        }
    }
    /// Narrowest the dialog may get when a window-like dialog is resized.
    var minWidth: CGFloat { width }
    /// Widest a resizable dialog may get.
    var maxWidth: CGFloat { self == .wide || self == .extraWide ? 1600 : width * 1.5 }
    /// Tallest the content area gets before it scrolls.
    var maxContentHeight: CGFloat {
        switch self {
        case .small: 420
        case .medium: 520
        case .large: 580
        case .wide, .extraWide: 640
        }
    }
    /// Default width of the label column of `DialogRow`s.
    var labelWidth: CGFloat {
        switch self {
        case .small: 110
        case .medium: 150
        case .large, .wide, .extraWide: 170
        }
    }
}

/// Spacing, radii and type for dialogs (an 8 pt grid; 20 pt outer padding).
enum DialogStyle {
    static let outer: CGFloat = 20
    /// Between sections.
    static let sectionSpacing: CGFloat = 16
    /// Between a section's title and its box, and between stacked controls.
    static let itemSpacing: CGFloat = 8
    /// Inside a section box.
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 8
    static let rowMinHeight: CGFloat = 32
    static let footerPaddingV: CGFloat = 14
    static let iconTile: CGFloat = 36
    static let buttonMinWidth: CGFloat = 80

    static let title = Font.title3.weight(.semibold)
    static let subtitle = Font.callout
    static let sectionTitle = Font.subheadline.weight(.semibold)
    static let footnote = Font.caption
}

extension Tokens {
    /// Corner radius of section boxes, lists and notices. // DIALOGS
    static let radiusSection: CGFloat = 8
    /// Corner radius of the header's icon tile and of small badges. // DIALOGS
    static let radiusTile: CGFloat = 8
    /// Corner radius of summary tiles. // DIALOGS
    static let radiusCard: CGFloat = 10
}

/// Dialog colours: opaque, light and dark.
enum DialogColors {
    /// The sheet's own background: the system window background, always opaque (never the glass material, which
    /// lets the canvas show through).
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    /// A section box: white on the light window background, a lifted grey on the dark one.
    static let sectionFill = Color(nsColor: NSColor(name: "arcus.dialog.section") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(srgbRed: 0.205, green: 0.205, blue: 0.215, alpha: 1)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    })
    /// Hairline around section boxes and lists.
    static let sectionStroke = Color(nsColor: NSColor(name: "arcus.dialog.stroke") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(white: 1, alpha: 0.09)
            : NSColor(white: 0, alpha: 0.09)
    })
    /// Dividers between rows inside a box.
    static let rowDivider = Color(nsColor: NSColor(name: "arcus.dialog.rowDivider") { ap in
        ap.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.07)
    })
    /// Hover and alternating row tint.
    static let rowHover = Color.primary.opacity(0.045)
}

extension EnvironmentValues {
    /// Width of the label column of `DialogRow`s inside this dialog.
    @Entry var dialogLabelWidth: CGFloat = 150
}

extension View {
    /// An opaque sheet background: the window background instead of the default glass, so the canvas never shows
    /// through a dialog. Apply to the root of every `.sheet` content.
    func opaqueDialogBackground() -> some View {
        background(DialogColors.background).presentationBackground(DialogColors.background)
    }
}
