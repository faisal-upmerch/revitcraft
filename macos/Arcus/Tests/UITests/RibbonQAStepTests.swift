import AppKit
import SwiftUI
import Testing
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// PILLS: the QA harness's "Ribbon …" steps (QAHarness+POLISH.swift) run here without the app: every tab of the
/// project and Furniture ribbons and of the Family Editor, switched in place as the QA run does (the first tab
/// included), at 1280 pt and at the minimum width.
@MainActor
@Suite("Ribbon QA steps", .serialized)
struct RibbonQAStepTests {
    /// Each tab's step on the tab freshly laid out (offscreen, a hosted ribbon reports its panels' frames on its first
    /// layout only, so each tab gets its own host; in the app `showRibbonTab` gets the same fresh layout in place).
    func checkTabs(_ s: DocumentState, _ label: String) async {
        let frames = RibbonFrames.of(s)
        for window in [1280.0, POLISHRibbonTests.mainMinimum] {
            for tab in RibbonTab.tabs(for: s.mode) {
                frames.reset()
                s.ribbonTab = tab; s.ribbonShowsContextual = false
                _ = await POLISHRibbonTests.host(RibbonStrip(state: s), size: CGSize(width: POLISHRibbonTests.stripWidth(window), height: CGFloat(ShellMetrics.arcus.ribbonHeight)))
                do { _ = try QAHarness.ribbonTabReport(s, tab) } catch { Issue.record("\(label) \(Int(window)) \(tab.rawValue): \(error)") }
            }
        }
    }

    @Test("Switching tabs in place lays every panel out again: each tab is its own page of panels, and the step leaves the tab already showing first")
    func tabsArePages() async {
        let s = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        let pages = RibbonTab.tabs(for: s.mode).map { t -> String in s.ribbonTab = t; s.ribbonShowsContextual = false; return RibbonContentKey(s, contextual: false).page }
        #expect(Set(pages).count == pages.count, "\(pages)")
        // Panels shared by tabs (Select, Properties…) are rebuilt too: the row's identity is the page.
        s.ribbonTab = .architecture
        var seen: [RibbonTab] = []
        let observer = Task { @MainActor in
            for _ in 0..<40 { if seen.last != s.ribbonTab { seen.append(s.ribbonTab) }; try? await Task.sleep(for: .milliseconds(5)) }
        }
        await QAHarness.showRibbonTab(s, .architecture, settle: 120)
        await observer.value
        #expect(seen.contains { $0 != .architecture } && seen.last == .architecture, "tabs shown: \(seen)")
    }

    @Test("Project ribbon: every tab's step passes")
    func project() async {
        await checkTabs(DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)), "project")
    }

    @Test("Furniture ribbon: every tab's step passes")
    func furniture() async throws {
        await checkTabs(DocumentState(session: DocumentSession(model: try #require(FurnitureSamples.baseCabinetModel()))), "furniture")
    }

    @Test("Family Editor ribbon: every tab's step passes, the first one included")
    func familyEditor() async {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Ribbon Check"
        let m = FamilyEditorModel(family: f, state: DocumentState(session: DocumentSession(model: BIMModel())), familyID: nil)
        let wc = FamilyEditorWindowController(model: m)
        defer { wc.close() }
        guard let w = wc.window, let v = w.contentView else { Issue.record("no window"); return }
        for size in [NSSize(width: 1280, height: 800), FamilyEditorChrome.minimumSize] {
            w.setContentSize(size)
            await QAHarness.settleRibbon(v, 150)
            for tab in FamilyRibbonTab.allCases {
                await QAHarness.showFamilyRibbonTab(m, tab, settle: 150, view: v)
                do { _ = try QAHarness.familyRibbonTabReport(m, tab) } catch { Issue.record("\(Int(size.width)) \(tab.rawValue): \(error)") }
            }
        }
    }
}
