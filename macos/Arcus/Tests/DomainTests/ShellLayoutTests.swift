import Testing
import Foundation
@testable import ArcusApplication

// W4-WIRE: the floating shell's rows, pills and canvas insets.

@Suite struct ShellLayoutTests {
    let m = ShellMetrics()

    func request(_ w: Double, _ h: Double, leading: Double = 320, trailing: Double = 0) -> ShellRequest {
        var r = ShellRequest(region: DockRegion(width: w, height: h))
        r.leadingInset = leading; r.trailingInset = trailing
        return r
    }

    @Test func rowsStackUnderTheTopPillsAndInsetTheCanvas() {
        let r = ShellLayout.layout(request(1500, 900))
        #expect(r.strip == nil)
        #expect(r.contentLeft == 320 && r.contentRight == 1490)
        #expect(r.tabs.x == 320 && r.tabs.y == 10 && r.tabs.height == m.pillHeight)
        #expect(r.controls.maxX == 1490)
        // The tab pill stops one margin short of the controls pill.
        #expect(r.tabs.width == 1490 - 320 - m.controlsFullWidth - 10)
        let ribbon = try! #require(r.ribbon)
        #expect(ribbon.y == 10 + m.pillHeight + 10 && ribbon.x == 320 && ribbon.width == 1170)
        #expect(r.options == nil && r.viewTabs == nil)
        #expect(r.topInset == ribbon.maxY + 10)
        let bottom = try! #require(r.bottom)
        #expect(bottom.maxY == 890 && bottom.x == 320 && bottom.width == 1170)
        #expect(r.bottomInset == m.bottomHeight + 20)
        #expect(r.leadingInset == 320 && r.trailingInset == 0)
    }

    @Test func optionsAndViewTabsAddRowsBelowTheRibbon() {
        var q = request(1500, 900)
        q.optionsShown = true; q.viewTabsShown = true
        let r = ShellLayout.layout(q)
        let ribbon = try! #require(r.ribbon), options = try! #require(r.options), tabs = try! #require(r.viewTabs)
        #expect(options.y == ribbon.maxY + 10 && tabs.y == options.maxY + 10)
        #expect(r.topInset == tabs.maxY + 10)
    }

    @Test func minimizedRibbonKeepsTheTabPillAndShrinksTheInset() {
        var q = request(1500, 900)
        q.ribbonMinimized = true; q.optionsShown = true
        let r = ShellLayout.layout(q)
        #expect(r.ribbon == nil)
        #expect(r.tabs.y == 10)
        #expect(r.options?.y == 10 + m.pillHeight + 10)
        #expect(r.topInset == 10 + m.pillHeight + 10 + m.optionsHeight + 10)
    }

    @Test func collapsedSidebarShowsTheStripAndTheTabPillFollows() {
        var q = request(1500, 900, leading: 0)
        q.sidebarCollapsed = true
        let r = ShellLayout.layout(q)
        let strip = try! #require(r.strip)
        #expect(strip == DockFrame(x: 10, y: 10, width: m.collapsedStripWidth, height: m.pillHeight))
        #expect(r.contentLeft == strip.maxX + 10 && r.tabs.x == r.contentLeft)
        #expect(r.leadingInset == 0)
        // A leading dock with nothing to show behaves like a collapsed one.
        #expect(ShellLayout.layout(request(1500, 900, leading: 0)).strip != nil)
    }

    @Test func inspectorKeepsThePillsClearOnTheRight() {
        let r = ShellLayout.layout(request(1500, 900, trailing: 320))
        #expect(r.contentRight == 1180)
        #expect(r.controls.maxX == 1180 && r.ribbon?.maxX == 1180 && r.bottom?.maxX == 1180)
        #expect(r.trailingInset == 320)
    }

    @Test func narrowWindowsCompactTheControls() {
        // 980 wide with a 300 sidebar: 650 of content — enough for the compact tab pill and the full controls.
        let wide = ShellLayout.layout(request(980, 640))
        #expect(!wide.controlsCompact)
        #expect(wide.tabs.width >= m.tabsCompactWidth)
        // Both docks at 980 (Mac Spacious): 360 of content — the controls compact so both pills fit.
        let both = ShellLayout.layout(request(980, 640, trailing: 300))
        #expect(both.controlsCompact)
        #expect(both.tabs.width == 360 - m.controlsCompactWidth - 10)
        #expect(both.tabs.width >= m.tabsCompactWidth)
        #expect(both.bottom?.width == 360)
    }

    @Test func measuredControlsWidthDrivesTheTabPill() {
        var q = request(1500, 900)
        q.controlsWidth = 300
        let r = ShellLayout.layout(q)
        #expect(r.controls.width == 300 && r.controls.x == 1190)
        #expect(r.tabs.width == ShellLayout.tabsWidth(contentWidth: 1170, controlsWidth: 300))
        #expect(ShellLayout.tabsWidth(contentWidth: 100, controlsWidth: 300) == 0)
    }

    @Test func degenerateRegionYieldsNothing() {
        let r = ShellLayout.layout(request(0, 0))
        #expect(r.ribbon == nil && r.bottom == nil && r.topInset == 0)
    }
}
