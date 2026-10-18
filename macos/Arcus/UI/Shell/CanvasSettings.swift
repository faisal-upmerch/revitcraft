import AppKit
import ArcusDomain

extension Notification.Name {
    /// Posted when a canvas display setting changes (colours, temporary dimensions, tooltips); canvases redraw.
    static let arcusCanvasSettingsChanged = Notification.Name("ArcusCanvasSettingsChanged")
}

/// App-wide canvas preferences from Settings (BL-CANVAS: ARCUS-026/027/080/081/085). Stored in user defaults; every
/// reader goes through here so defaults live in one place.
nonisolated enum CanvasSettings {
    // MARK: Colors

    enum ColorRole: String, CaseIterable, Identifiable {
        case selection = "Selection", preselection = "Pre-selection", alert = "Alert"
        var id: String { rawValue }
        var key: String { "canvas.color.\(self)" }
        /// Built-in colour for light and dark canvases.
        func defaultColor(dark: Bool) -> RGBColor {
            switch self {
            case .selection: dark ? RGBColor(hex: 0x4D94FF) : RGBColor(hex: 0x0050D0)
            case .preselection: dark ? RGBColor(hex: 0x8CBDFF) : RGBColor(hex: 0x4F95F2)
            case .alert: dark ? RGBColor(hex: 0xFF9A3C) : RGBColor(hex: 0xF07000)
            }
        }
    }

    /// The user's colour for a role, or nil for the built-in one.
    static func customColor(_ role: ColorRole) -> RGBColor? {
        guard let s = UserDefaults.standard.string(forKey: role.key), s.count == 7, s.hasPrefix("#"), let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return RGBColor(hex: v)
    }
    @MainActor static func setCustomColor(_ role: ColorRole, _ c: RGBColor?) {
        if let c { UserDefaults.standard.set(c.hexString, forKey: role.key) } else { UserDefaults.standard.removeObject(forKey: role.key) }
        changed()
    }
    static func color(_ role: ColorRole, dark: Bool) -> RGBColor { customColor(role) ?? role.defaultColor(dark: dark) }
    static func nsColor(_ role: ColorRole, dark: Bool) -> NSColor {
        let c = color(role, dark: dark)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    // MARK: Temporary dimensions

    enum TextBackground: String, CaseIterable, Identifiable {
        case transparent = "Transparent", opaque = "Opaque"
        var id: String { rawValue }
    }
    static let tempDimSizeKey = "canvas.tempDim.textSize"
    static let tempDimBackgroundKey = "canvas.tempDim.background"
    /// Text size of temporary dimension values, in points (8…16).
    static var tempDimTextSize: Double {
        let v = UserDefaults.standard.double(forKey: tempDimSizeKey)
        return v == 0 ? 11 : min(16, max(8, v))
    }
    static var tempDimBackground: TextBackground { TextBackground(rawValue: UserDefaults.standard.string(forKey: tempDimBackgroundKey) ?? "") ?? .transparent }

    // MARK: Tooltips

    /// How much the canvas explains under the pointer: None hides tooltips; Minimal shows only snaps and drags;
    /// Normal adds the tool's next step and element names ("Category : Family : Type") after a rest; High shows them
    /// sooner, with the element's Mark and level.
    enum TooltipAssistance: String, CaseIterable, Identifiable {
        case none = "None", minimal = "Minimal", normal = "Normal", high = "High"
        var id: String { rawValue }
    }
    static let tooltipKey = "canvas.tooltipAssistance"
    static var tooltipAssistance: TooltipAssistance { TooltipAssistance(rawValue: UserDefaults.standard.string(forKey: tooltipKey) ?? "") ?? .normal }
    /// Rest before the tooltip appears: element names wait longer than drawing aids.
    static func tooltipDelay(element: Bool) -> TimeInterval {
        switch (tooltipAssistance, element) {
        case (.high, true): 0.6
        case (_, true): 1.0
        case (.high, false): 0.3
        default: 0.5
        }
    }

    // MARK: Double-click

    enum FamilyDoubleClick: String, CaseIterable, Identifiable { case editType = "Edit Type", editFamily = "Edit Family", nothing = "Do Nothing"; var id: String { rawValue } }
    enum SketchDoubleClick: String, CaseIterable, Identifiable { case editSketch = "Edit Sketch", nothing = "Do Nothing"; var id: String { rawValue } }
    enum GroupDoubleClick: String, CaseIterable, Identifiable { case editGroup = "Edit Group", nothing = "Do Nothing"; var id: String { rawValue } }
    enum ViewportDoubleClick: String, CaseIterable, Identifiable { case activate = "Activate View", open = "Open View", nothing = "Do Nothing"; var id: String { rawValue } }
    static let familyDoubleClickKey = "doubleClick.family", sketchDoubleClickKey = "doubleClick.sketch"
    static let groupDoubleClickKey = "doubleClick.group", viewportDoubleClickKey = "doubleClick.viewport"
    static var familyDoubleClick: FamilyDoubleClick { FamilyDoubleClick(rawValue: UserDefaults.standard.string(forKey: familyDoubleClickKey) ?? "") ?? .editType }
    static var sketchDoubleClick: SketchDoubleClick { SketchDoubleClick(rawValue: UserDefaults.standard.string(forKey: sketchDoubleClickKey) ?? "") ?? .editSketch }
    static var groupDoubleClick: GroupDoubleClick { GroupDoubleClick(rawValue: UserDefaults.standard.string(forKey: groupDoubleClickKey) ?? "") ?? .editGroup }
    static var viewportDoubleClick: ViewportDoubleClick { ViewportDoubleClick(rawValue: UserDefaults.standard.string(forKey: viewportDoubleClickKey) ?? "") ?? .activate }

    /// Tells open canvases to redraw with the new settings.
    @MainActor static func changed() {
        NotificationCenter.default.post(name: .arcusCanvasSettingsChanged, object: nil)
    }
}
