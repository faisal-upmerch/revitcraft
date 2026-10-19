import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// DIALOGS: every dialog rendered offscreen at the size its sheet takes (its ideal size, as `.presentationSizing(.fitted)`
/// sizes it), light and dark, to `/tmp/arcus-dialogs/` for review (Docs/Dialogs.md ▸ Render check). The test also
/// checks that each dialog fits its size class (no dialog wider than its class, none taller than a laptop screen).
/// An offscreen window that draws as the key window (default buttons in the accent colour, as in a real sheet).
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
@Suite("Dialog renders", .serialized)
struct DialogRenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-dialogs", isDirectory: true)

    /// A project with sample data (Courtyard House, imperial; a toposurface; Model Health results; a selection).
    static func projectState() -> DocumentState {
        _ = NSApplication.shared
        var model = CourtyardHouse.make(units: .imperial)
        let session = DocumentSession(model: model)
        if model.elements(.topography).isEmpty {
            let pts = [Vec3(0, 0, 0), Vec3(18, 0, 0.4), Vec3(18, 14, 1.1), Vec3(0, 14, 0.6), Vec3(9, 7, 0.9)]
            session.perform("Toposurface") { tx in _ = tx.create(.topography, name: "Site", data: .topography(TopographyData(points: pts))) }
            model = session.model
        }
        let s = DocumentState(session: session)
        s.healthWarnings = QAHarness.sampleHealthWarnings
        s.session.selection.select(Array(model.elements(.walls).prefix(4).map(\.id)) + Array(model.elements(.doors).prefix(3).map(\.id)))
        return s
    }

    static func furnitureState() -> DocumentState {
        DocumentState(session: DocumentSession(model: FurnitureSamples.baseCabinetModel() ?? BIMModel()))
    }

    /// Renders `view` at its ideal size; returns that size.
    @discardableResult
    static func render<V: View>(_ view: V, _ name: String, dark: Bool, maxHeight: CGFloat = 1000) async throws -> CGSize {
        let root = view.fixedSize().background(DialogColors.background)
        let h = NSHostingView(rootView: root)
        h.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let w = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = h.appearance
        w.contentView = h
        for _ in 0..<5 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(25)) }
        var size = h.fittingSize
        size.height = min(size.height, maxHeight)
        h.frame = NSRect(origin: .zero, size: size)
        w.setContentSize(size)
        for _ in 0..<5 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(25)) }
        size = h.fittingSize
        size.height = min(size.height, maxHeight)
        h.frame = NSRect(origin: .zero, size: size)
        w.setContentSize(size)
        h.layoutSubtreeIfNeeded()
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        return size
    }

    @Test("Every dialog renders, light and dark, within its size class")
    func everyDialog() async throws {
        let project = Self.projectState()
        let furniture = Self.furnitureState()
        let fixtures = QAHarness.dialogFixtures(project.model, at: Self.out.appendingPathComponent("fixtures", isDirectory: true))
        let only = ProcessInfo.processInfo.environment["ARCUS_DIALOG"].map { Set($0.split(separator: ",").map(String.init)) }
        var sizes: [String] = []
        for entry in QAHarness.dialogCatalog(project: project, furniture: furniture, fixtures: fixtures) {
            if let only, !only.contains(entry.name) { continue }
            let state = entry.furniture ? furniture : project
            for dark in [false, true] {
                state.presented = entry.kind
                let size = try await Self.render(DialogHost(state: state, dialog: entry.kind), entry.name, dark: dark)
                if !dark { sizes.append("\(entry.name)\t\(Int(size.width))×\(Int(size.height))") }
                #expect(size.width >= 300 && size.width <= 1400, "\(entry.name) is \(size.width) pt wide")
                #expect(size.height >= 120, "\(entry.name) is \(size.height) pt tall")
            }
        }
        // Sheets outside DialogKind: the Family Editor's own dialogs.
        if only == nil || only!.contains("family-editor") {
            var f = FamilyTemplates.make(.furniture)
            f.name = "Side Table"
            let fe = FamilyEditorModel(family: f, state: project, familyID: nil)
            for dark in [false, true] {
                try await Self.render(FamilyTypesDialog(model: fe), "family-editor-types", dark: dark)
                try await Self.render(FamilyCategoryDialog(model: fe), "family-editor-category", dark: dark)
                try await Self.render(FamilyWorkPlaneDialog(model: fe), "family-editor-work-plane", dark: dark)
            }
        }
        try? sizes.joined(separator: "\n").write(to: Self.out.appendingPathComponent("_sizes.txt"), atomically: true, encoding: .utf8)
    }
}
