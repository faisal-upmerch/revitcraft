import AppKit
import SwiftUI
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusApplication
import ArcusOutput
@testable import ArcusUI

/// FMG2: joints in Properties and Explode Parts on screen, rendered offscreen to `/tmp/arcus-fmg2/` (light and dark):
/// Properties of a joint the Joint tool picked (made by the rules), of a part with its joints, of an exploded 3D view,
/// and the Explode Parts dialog. The test checks the palette subject, the edit that makes the joint, and the command.
@MainActor
@Suite("FMG2 joints and explode UI", .serialized)
struct FMG2UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fmg2")

    static func render<V: View>(_ view: V, size: CGSize, _ name: String) async throws {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<6 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    @Test func pickedJointsShowInPropertiesAndEditingOneMakesIt() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: model))
        let front = try #require(model.views.first { $0.name == "Front" })
        state.open(front.id)
        CommandRouter(state: state).run(.furnitureJoint)
        let tool = try #require(state.activeTool as? FurnitureJointTool)
        let sides = model.elements(.furniturePanels).filter { $0.furniturePanel?.role == .panel }.map(\.id)
        let top = try #require(model.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
        let j = try #require(FurnitureJoints.joint(sides[0], top.id, state.model))
        let p = try #require(FurnitureSketchMap.of(front.view)).project(j.marker)
        tool.ctx.pixel = 0.002
        tool.pointerDown(ToolInput(point: p, rawPoint: p))
        state.toolChangedState()
        #expect(tool.picked == j.key && state.session.selection.isEmpty)
        #expect(state.paletteSubject == .joint(j.key), "a joint the rules make shows in Properties")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            try await Self.render(PropertiesView(state: state), size: CGSize(width: 320, height: 560), "ui-joint-properties-\(appearance == .aqua ? "light" : "dark")")
        }
        // Editing it there makes the user's joint, selects it, and the marker turns square.
        let view = PropertiesView(state: state)
        let apply = try #require(view.applyOverride)
        try apply(FurnitureJointParameters.jointType.id, .text("Cam Lock"))
        let set = try #require(FurnitureJoints.joint(sides[0], top.id, state.model))
        #expect(set.type == .camLock && set.isUserSet && state.session.selection.ids == [set.elementID!])
        #expect(tool.worldMarkers.contains { $0.square && $0.emphasis == 2 })
        #expect(throws: ParameterError.self) { try apply(FurnitureJointParameters.byRule.id, .bool(false)) }
        try apply(FurnitureJointParameters.byRule.id, .bool(true))
        #expect(state.model.elements(.furnitureJoints).isEmpty)
        state.cancelTool()
        // A part lists its joints.
        state.session.selection.select([sides[0]])
        #expect(state.paletteSubject == .elements([sides[0]], common: false))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            try await Self.render(PropertiesView(state: state), size: CGSize(width: 320, height: 900), "ui-part-joints-\(appearance == .aqua ? "light" : "dark")")
        }
        NSApp.appearance = nil
    }

    @Test func explodePartsCommandDialogAndProperties() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.bookcaseModel())
        let state = DocumentState(session: DocumentSession(model: model))
        let router = CommandRouter(state: state)
        #expect(CommandCatalog.info(.furnitureExplodeParts).title == "Explode Parts")
        let plan = try #require(model.views.first { $0.name == "Ref. Level" })
        state.open(plan.id)
        #expect(router.fmg2DisabledReason(.furnitureExplodeParts) == "Open a 3D view.")
        let v3 = try #require(model.views.first { $0.name == "{3D}" })
        state.open(v3.id)
        #expect(router.fmg2DisabledReason(.furnitureExplodeParts) == nil)
        router.run(.furnitureExplodeParts)
        #expect(state.presented == .fmg2(.explodeParts(v3.id)))
        let project = DocumentState(session: DocumentSession(model: BIMModel()))
        #expect(CommandRouter(state: project).fmg2DisabledReason(.furnitureExplodeParts) == "Only in Furniture documents.")
        // The dialog applies in one step.
        let dialog = ExplodePartsDialog(state: state, viewID: v3.id)
        dialog.apply()
        #expect(FurnitureExplode.isExploded(state.model[v3.id]!) && state.presented == nil)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            try await Self.render(ExplodePartsDialog(state: state, viewID: v3.id), size: CGSize(width: 440, height: 260), "ui-explode-dialog-\(suffix)")
            state.session.selection.clear()
            try await Self.render(PropertiesView(state: state), size: CGSize(width: 320, height: 700), "ui-3d-view-properties-\(suffix)")
        }
        NSApp.appearance = nil
    }
}
