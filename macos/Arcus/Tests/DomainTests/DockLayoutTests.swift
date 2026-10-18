import Testing
import Foundation
@testable import ArcusApplication

// W4-SHELL: floating dock geometry and persistence.

@Suite struct DockLayoutTests {
    let metrics = DockMetrics()

    @Test func widthClampsToMetricsAndCanvas() {
        // Plenty of room: the request is honoured within min…max.
        #expect(DockLayout.clampWidth(300, regionWidth: 1500, otherDockWidth: 0) == 300)
        #expect(DockLayout.clampWidth(100, regionWidth: 1500, otherDockWidth: 0) == metrics.minWidth)
        #expect(DockLayout.clampWidth(900, regionWidth: 1500, otherDockWidth: 0) == metrics.maxWidth)
        // The minimum window (980 wide): 980 - 480 canvas - 20 margins = 480 of dock at most.
        #expect(DockLayout.clampWidth(480, regionWidth: 980, otherDockWidth: 0) == 480)
        // With another dock of 300 beside it there is only 160 left, so the panel keeps its minimum (the caller decides whether to hide it).
        #expect(DockLayout.clampWidth(400, regionWidth: 980, otherDockWidth: 300) == metrics.minWidth)
        // Non-finite requests fall back to the minimum instead of poisoning the layout.
        #expect(DockLayout.clampWidth(.nan, regionWidth: 1500, otherDockWidth: 0) == metrics.minWidth)
        #expect(DockLayout.clampWidth(.infinity, regionWidth: 1500, otherDockWidth: 0) == metrics.minWidth)
    }

    @Test func leadingDockFloatsInsideTheRegion() {
        let r = DockLayout.layout(region: DockRegion(width: 1500, height: 800), leading: DockRequest(edge: .leading, width: 300, visible: true), trailing: nil)
        let p = try! #require(r.placement(.leading))
        #expect(p.frame == DockFrame(x: 10, y: 10, width: 300, height: 780))
        #expect(r.leadingInset == 320)
        #expect(r.trailingInset == 0)
        #expect(r.placement(.trailing) == nil)
    }

    @Test func hiddenDocksTakeNoRoom() {
        let r = DockLayout.layout(region: DockRegion(width: 1500, height: 800), leading: DockRequest(edge: .leading, width: 300, visible: false),
                                  trailing: DockRequest(edge: .trailing, width: 320, visible: false))
        #expect(r.placements.isEmpty)
        #expect(r.leadingInset == 0 && r.trailingInset == 0)
    }

    @Test func bothDocksShareANarrowWindow() {
        let r = DockLayout.layout(region: DockRegion(width: 980, height: 600), leading: DockRequest(edge: .leading, width: 300, visible: true),
                                  trailing: DockRequest(edge: .trailing, width: 400, visible: true))
        let l = try! #require(r.placement(.leading)), t = try! #require(r.placement(.trailing))
        #expect(l.frame.width == 300)
        // 980 - 480 - (300 + 20) - 20 = 160 < min → the trailing dock keeps its minimum and overlaps the canvas reserve.
        #expect(t.frame.width == metrics.minWidth)
        #expect(t.frame.maxX == 970)
        #expect(r.trailingInset == metrics.minWidth + 20)
    }

    @Test func degenerateRegionYieldsNothing() {
        let r = DockLayout.layout(region: DockRegion(width: 0, height: 0), leading: DockRequest(edge: .leading, width: 300, visible: true), trailing: nil)
        #expect(r.placements.isEmpty)
    }

    @Test func draggingResizesTowardsTheCanvas() {
        #expect(DockLayout.resized(edge: .leading, startWidth: 300, dragX: 40, regionWidth: 1500, otherDockWidth: 0) == 340)
        #expect(DockLayout.resized(edge: .leading, startWidth: 300, dragX: -400, regionWidth: 1500, otherDockWidth: 0) == metrics.minWidth)
        #expect(DockLayout.resized(edge: .trailing, startWidth: 300, dragX: -40, regionWidth: 1500, otherDockWidth: 0) == 340)
        #expect(DockLayout.resized(edge: .trailing, startWidth: 300, dragX: 40, regionWidth: 1500, otherDockWidth: 0) == metrics.minWidth)
    }

    @Test func preferencesRoundTripAndSanitise() {
        let store = DictionaryDockStore()
        #expect(DockPreferences.load(from: store) == DockPreferences())
        var p = DockPreferences(leadingWidth: 345, trailingWidth: 310, leadingCollapsed: true, trailingCollapsed: false)
        p.save(to: store)
        #expect(DockPreferences.load(from: store) == p)
        p.setWidth(999, .trailing); p.setCollapsed(true, .trailing)
        p.save(to: store)
        // Out-of-range widths come back clamped; flags come back as saved.
        let back = DockPreferences.load(from: store)
        #expect(back.trailingWidth == metrics.maxWidth)
        #expect(back.trailingCollapsed)
        #expect(back.width(.leading) == 345 && back.collapsed(.leading))
        // Garbage in the store is ignored.
        store.values["dock.leading.width"] = -5.0
        #expect(DockPreferences.load(from: store).leadingWidth == DockPreferences.defaultLeadingWidth)
    }
}
