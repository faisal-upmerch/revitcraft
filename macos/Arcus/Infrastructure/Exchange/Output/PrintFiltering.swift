import Foundation
import ArcusGeometry
import ArcusDomain

// F13: Print Setup and PDF/DWFx options (RevitCraft rc-core sheet.rs `PrintSettings`, `apply_print_settings`): hide
// reference planes, scope boxes, crop boundaries and unreferenced view tags; print in color, black lines or grayscale.

/// What to leave out of printed and exported pages, and how to print colours.
public struct PrintOptions: Sendable, Hashable {
    public var hideReferencePlanes = true
    public var hideScopeBoxes = true
    public var hideCropBoundaries = true
    /// Section, elevation and callout tags of views that aren't placed on any sheet.
    public var hideUnreferencedViewTags = false
    public var colors: PrintSetup.Colors = .color
    public init() {}
    public init(_ s: PrintSetup) {
        hideReferencePlanes = s.hideReferencePlanes; hideScopeBoxes = s.hideScopeBoxes; hideCropBoundaries = s.hideCropBoundaries
        hideUnreferencedViewTags = s.hideUnreferencedViewTags; colors = s.colors
    }
    /// Options that change nothing (the display list prints as drawn).
    public static let none: PrintOptions = { var o = PrintOptions(); o.hideReferencePlanes = false; o.hideScopeBoxes = false; o.hideCropBoundaries = false; return o }()
}

public enum PrintFiltering {
    /// The display list with hidden items removed and colours converted.
    public static func apply(_ g: ViewGraphics, _ o: PrintOptions, model: BIMModel) -> ViewGraphics {
        var out = g
        out.items = g.items.filter { item in
            if o.hideReferencePlanes && item.category == .referencePlanes { return false }
            if o.hideScopeBoxes && item.category == .scopeBoxes { return false }
            if o.hideCropBoundaries && item.layer == .overlay { return false }
            if o.hideUnreferencedViewTags, let target = item.targetViewID, [.sectionMarks, .elevationMarks, .callouts].contains(item.category),
               model.sheet(containing: target) == nil { return false }
            return true
        }
        if o.colors != .color {
            for i in out.items.indices { out.items[i].primitives = out.items[i].primitives.map { recolor($0, o.colors) } }
        }
        return out
    }

    static func gray(_ c: RGBColor) -> RGBColor {
        let y = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return RGBColor(y, y, y, c.a)
    }

    /// Lines and text: black (white stays white) or grey; fills: grey.
    static func recolor(_ p: GPrimitive, _ mode: PrintSetup.Colors) -> GPrimitive {
        func ink(_ c: RGBColor) -> RGBColor {
            switch mode {
            case .color: return c
            case .grayscale: return gray(c)
            case .blackLines: return c.r > 0.98 && c.g > 0.98 && c.b > 0.98 ? c : RGBColor(0, 0, 0, c.a)
            }
        }
        switch p {
        case .polyline(let pts, let closed, var s): s.color = ink(s.color); return .polyline(pts, closed: closed, s)
        case .arc(let a, var s): s.color = ink(s.color); return .arc(a, s)
        case .text(var t): t.color = ink(t.color); return .text(t)
        case .fill(let polys, var f):
            f.color = mode == .blackLines && f.pattern != .solid ? .black : gray(f.color)
            f.background = f.background.map(gray)
            return .fill(polys, f)
        }
    }
}
