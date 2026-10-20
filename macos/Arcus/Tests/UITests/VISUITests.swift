import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// VIS: the View Control Bar shows the view's state: the detail level and visual style buttons carry the current
/// choice's icon and tooltip, their menus tick the current choice, toggles show on and off, and the active view tab
/// stands out. Captures go to /tmp/arcus-vis/ (light and dark).
@MainActor
@Suite("VIS view control bar", .serialized)
struct VISUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-vis")

    static func host<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name) async -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: appearance)
        let h = NSHostingView(rootView: AnyView(view.padding(8).frame(width: size.width, height: size.height, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<6 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
        return h
    }

    static func shoot(_ v: NSView, _ name: String) throws {
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    static func setView(_ state: DocumentState, _ id: ElementID, _ change: @escaping (inout ViewData) -> Void) {
        state.session.perform("View") { tx in tx.update(id) { e in if var v = e.view { change(&v); e.view = v } } }
    }

    static func furniture() throws -> (DocumentState, threeD: ElementID, plan: ElementID) {
        let m = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: m))
        let v3 = try #require(m.views.first { $0.view?.kind == .threeD }?.id)
        let plan = try #require(m.views.first { $0.view?.kind.isPlan == true }?.id)
        state.openViews = [plan, v3]
        state.activeViewID = v3
        return (state, v3, plan)
    }

    @Test("Menus tick the view's current detail level and visual style")
    func menusReflectTheView() throws {
        var vd = ViewData(kind: .threeD)
        vd.detailLevel = .fine
        vd.visualStyle = .realistic
        #expect(ViewControlChoices.detailLevels(vd).filter(\.checked).map(\.level) == [.fine])
        #expect(ViewControlChoices.visualStyles(vd).map(\.style) == VisualStyle.allCases)
        #expect(ViewControlChoices.visualStyles(vd).filter(\.checked).map(\.style) == [.realistic])
        vd.detailLevel = .coarse
        #expect(ViewControlChoices.detailLevels(vd).filter(\.checked).map(\.level) == [.coarse])
        // Plans offer Wireframe and Hidden Line; any other style reads as Hidden Line.
        var plan = ViewData(kind: .floorPlan)
        plan.visualStyle = .shaded
        #expect(ViewControlChoices.visualStyles(plan).map(\.style) == [.wireframe, .hiddenLine])
        #expect(ViewControlChoices.visualStyles(plan).filter(\.checked).map(\.style) == [.hiddenLine])
        plan.visualStyle = .wireframe
        #expect(ViewControlChoices.visualStyles(plan).filter(\.checked).map(\.style) == [.wireframe])
        #expect(DetailLevel.fine.controlHelp == "Detail Level: Fine")
    }

    @Test("Every detail level and visual style has its own icon")
    func iconsAreDistinct() {
        let details = DetailLevel.allCases.map { ViewStateIcons.detail($0).tiffRepresentation }
        #expect(Set(details).count == DetailLevel.allCases.count)
        let styles = VisualStyle.allCases.map { ViewStateIcons.style($0).tiffRepresentation }
        #expect(Set(styles).count == VisualStyle.allCases.count)
        #expect(ViewStateIcons.detail(.fine).isTemplate && ViewStateIcons.style(.shaded).isTemplate)
    }

    @Test("The bar in each state, light and dark")
    func captures() async throws {
        let (state, v3, plan) = try Self.furniture()
        let size = CGSize(width: 460, height: 40)
        for (app, tag) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            for d in DetailLevel.allCases {
                for s in [VisualStyle.wireframe, .hiddenLine, .shaded, .consistentColors, .realistic] {
                    Self.setView(state, v3) { $0.detailLevel = d; $0.visualStyle = s; $0.displayOptions.castShadows = false; $0.sectionBoxActive = false }
                    let h = await Self.host(ViewControlStrip(state: state), size: size, appearance: app)
                    try Self.shoot(h, "bar-3d-\(d.rawValue.lowercased())-\(s.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(tag)")
                }
            }
            // Toggles on: shadows, section box, temporary hide/isolate, reveal hidden.
            Self.setView(state, v3) { $0.displayOptions.castShadows = true; $0.sectionBoxActive = true }
            var temp = TemporaryVisibility()
            temp.hiddenCategories = [.furnitureShelves]
            temp.revealHidden = true
            state.session.temporaryVisibility[v3] = temp
            try Self.shoot(await Self.host(ViewControlStrip(state: state), size: CGSize(width: 640, height: 40), appearance: app), "bar-3d-toggles-on-\(tag)")
            state.session.temporaryVisibility[v3] = nil
            // A plan: Hidden Line, crop on.
            state.activeViewID = plan
            Self.setView(state, plan) { $0.cropActive = true; $0.detailLevel = .medium }
            try Self.shoot(await Self.host(ViewControlStrip(state: state), size: CGSize(width: 560, height: 40), appearance: app), "bar-plan-crop-on-\(tag)")
            try Self.shoot(await Self.host(ViewTabPills(state: state), size: CGSize(width: 560, height: 44), appearance: app), "view-tabs-\(tag)")
            // The tabs on a plain pill (offscreen captures can't draw the glass): the active tab's contrast.
            let bar = ViewTabBar(state: state)
            let tabs = HStack(spacing: 6) {
                ForEach(state.openViews, id: \.self) { id in
                    if let e = state.model[id] { bar.tab(id, e).frame(height: 28).background(Capsule().fill(Color.primary.opacity(0.06))) }
                }
            }
            try Self.shoot(await Self.host(tabs, size: CGSize(width: 560, height: 44), appearance: app), "view-tabs-plain-\(tag)")
            state.activeViewID = v3
        }
    }

    @Test("The Family Editor's bottom pill shows the detail level")
    func familyPill() async throws {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        let m = FamilyEditorModel(family: f, state: DocumentState(session: DocumentSession(model: BIMModel())), familyID: nil)
        m.applyVisibility = true
        for d in DetailLevel.allCases {
            m.detail = d
            for (app, tag) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                try Self.shoot(await Self.host(FamilyViewControls(model: m), size: CGSize(width: 300, height: 40), appearance: app), "family-pill-\(d.rawValue.lowercased())-\(tag)")
            }
        }
    }
}
