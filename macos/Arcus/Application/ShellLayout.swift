import Foundation

// W4-WIRE: geometry of the floating shell over the edge-to-edge canvas: the ribbon tab pill and the controls pill in
// the top row, the ribbon strip under them, the Options pill and the view-tab row when they apply, the bottom pill,
// the collapsed-sidebar strip, and the insets the canvas keeps from all of it. Pure values (no AppKit) so the window
// and its tests share one definition; `DockLayout` places the side docks, this places everything else around them.

/// Fixed metrics of the floating shell. Heights are the pills' outer heights; `margin` is the gap between any two
/// floating pieces and between a piece and the window edge.
public struct ShellMetrics: Sendable, Equatable {
    public var margin: Double = 10
    /// The top-row pills (ribbon tabs, controls) and the collapsed-sidebar strip.
    public var pillHeight: Double = 36
    /// The ribbon's panel strip.
    public var ribbonHeight: Double = 98
    /// The tool Options pill.
    public var optionsHeight: Double = 36
    /// The open-view tab pills.
    public var viewTabsHeight: Double = 30
    /// The bottom pill (view controls, status, selection).
    public var bottomHeight: Double = 36
    /// The strip that holds the traffic lights and the show-sidebar button while the sidebar is collapsed.
    public var collapsedStripWidth: Double = 118
    /// Widths used before the controls pill has been measured, and to decide when it compacts.
    public var controlsFullWidth: Double = 268
    public var controlsCompactWidth: Double = 154
    /// Width of the tab pill once its tabs have collapsed into one menu (the narrowest it gets).
    public var tabsCompactWidth: Double = 170
    public init() {}
}

/// What the shell has to place, and the room it has.
public struct ShellRequest: Sendable, Equatable {
    public var region: DockRegion
    /// The side docks' insets from `DockLayoutResult` (0 when a dock is hidden).
    public var leadingInset: Double = 0
    public var trailingInset: Double = 0
    /// No leading dock is showing: the traffic lights move to the collapsed strip.
    public var sidebarCollapsed = false
    /// The ribbon is minimized to its tabs.
    public var ribbonMinimized = false
    /// A tool is running (its Options pill shows).
    public var optionsShown = false
    /// More than one view is open (the view-tab row shows).
    public var viewTabsShown = false
    public var bottomShown = true
    /// The controls pill's measured width, or nil before the first layout.
    public var controlsWidth: Double? = nil
    public init(region: DockRegion) { self.region = region }
}

/// Where everything goes (origin top-left, y down) and the insets the canvas keeps from it.
public struct ShellLayoutResult: Sendable, Equatable {
    /// The collapsed-sidebar strip (traffic lights + show button), when the sidebar is collapsed.
    public var strip: DockFrame? = nil
    /// The ribbon tab pill's slot: `x`/`y` are its origin, `width` the most it may take.
    public var tabs = DockFrame(x: 0, y: 0, width: 0, height: 0)
    /// The controls pill (right-aligned in the top row).
    public var controls = DockFrame(x: 0, y: 0, width: 0, height: 0)
    public var controlsCompact = false
    public var ribbon: DockFrame? = nil
    public var options: DockFrame? = nil
    public var viewTabs: DockFrame? = nil
    public var bottom: DockFrame? = nil
    /// The horizontal span the top rows, the strip rows and the bottom pill share (between the docks).
    public var contentLeft: Double = 0
    public var contentRight: Double = 0
    public var contentWidth: Double { max(0, contentRight - contentLeft) }
    /// Insets of the part of the canvas that is not under any floating piece (zoom to fit, HUD placement).
    public var topInset: Double = 0
    public var bottomInset: Double = 0
    public var leadingInset: Double = 0
    public var trailingInset: Double = 0
}

public enum ShellLayout {
    /// The width the ribbon tabs may take in the top row beside the controls pill.
    public static func tabsWidth(contentWidth: Double, controlsWidth: Double, metrics: ShellMetrics = ShellMetrics()) -> Double {
        max(0, contentWidth - controlsWidth - metrics.margin)
    }

    /// Whether the controls pill has to drop to its compact form for the compact tab pill to fit beside it.
    public static func controlsCompact(contentWidth: Double, metrics: ShellMetrics = ShellMetrics()) -> Bool {
        contentWidth < metrics.tabsCompactWidth + metrics.margin + metrics.controlsFullWidth
    }

    public static func layout(_ r: ShellRequest, metrics m: ShellMetrics = ShellMetrics()) -> ShellLayoutResult {
        var out = ShellLayoutResult()
        guard r.region.width > 0, r.region.height > 0 else { return out }
        let stripShown = r.sidebarCollapsed || r.leadingInset <= 0
        if stripShown { out.strip = DockFrame(x: m.margin, y: m.margin, width: m.collapsedStripWidth, height: m.pillHeight) }
        out.contentLeft = stripShown ? m.margin * 2 + m.collapsedStripWidth : r.leadingInset
        out.contentRight = r.region.width - (r.trailingInset > 0 ? r.trailingInset : m.margin)
        let width = out.contentWidth
        out.controlsCompact = controlsCompact(contentWidth: width, metrics: m)
        let controlsW = r.controlsWidth ?? (out.controlsCompact ? m.controlsCompactWidth : m.controlsFullWidth)
        out.controls = DockFrame(x: out.contentRight - controlsW, y: m.margin, width: controlsW, height: m.pillHeight)
        out.tabs = DockFrame(x: out.contentLeft, y: m.margin, width: tabsWidth(contentWidth: width, controlsWidth: controlsW, metrics: m), height: m.pillHeight)
        var y = m.margin + m.pillHeight + m.margin
        if !r.ribbonMinimized {
            out.ribbon = DockFrame(x: out.contentLeft, y: y, width: width, height: m.ribbonHeight)
            y += m.ribbonHeight + m.margin
        }
        if r.optionsShown {
            out.options = DockFrame(x: out.contentLeft, y: y, width: width, height: m.optionsHeight)
            y += m.optionsHeight + m.margin
        }
        if r.viewTabsShown {
            out.viewTabs = DockFrame(x: out.contentLeft, y: y, width: width, height: m.viewTabsHeight)
            y += m.viewTabsHeight + m.margin
        }
        out.topInset = y
        if r.bottomShown {
            out.bottom = DockFrame(x: out.contentLeft, y: r.region.height - m.margin - m.bottomHeight, width: width, height: m.bottomHeight)
            out.bottomInset = m.bottomHeight + m.margin * 2
        }
        // The collapsed strip only covers a corner: the canvas is fully usable under the rest of the left edge.
        out.leadingInset = r.leadingInset
        out.trailingInset = r.trailingInset
        return out
    }
}
