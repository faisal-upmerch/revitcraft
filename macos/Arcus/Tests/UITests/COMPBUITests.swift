import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// COMPB: Joint Rules with connector components (the Fastener column), rendered offscreen to `/tmp/arcus-compb/` in
/// light and dark: Side – Top uses metal dowels, Shelf – Side system cams, Side – Back butt with corner brackets.
@MainActor
@Suite("COMPB joint rules UI", .serialized)
struct COMPBUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-compb")

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

    @Test func jointRulesShowTheFastenerColumn() async throws {
        _ = NSApplication.shared
        let model = try #require(FurnitureSamples.bookcaseModel())
        let session = DocumentSession(model: model)
        let cam = try #require(FurnitureJointFasteners.options(.camLock).first { $0.family == "Cam and Bolt Connector" })
        let dowel = try #require(FurnitureJointFasteners.options(.dowel).first { $0.family == "Metal Dowel" })
        let bracket = try #require(FurnitureJointFasteners.options(.butt).first { $0.family == "Corner Bracket" })
        _ = session.perform("Rules") { tx in
            var r = tx.model.furnitureJointRules
            func set(_ pair: JointPairKind, _ t: JointType, _ f: JointFastener) {
                var rule = r.rule(pair, category: .casework)
                rule.type = t
                rule.parameters = JointParameters(fastener: f.key)
                if let i = r.rules.firstIndex(where: { $0.pair == pair }) { r.rules[i] = rule } else { r.rules.append(rule) }
            }
            set(.sideTop, .dowel, dowel)
            set(.shelfSide, .camLock, cam)
            set(.shelfBack, .butt, bracket)
            try FurnitureJointOperations.setRules(r, in: tx)
        }
        #expect(session.lastError == nil, "\(session.lastError?.message ?? "")")
        let state = DocumentState(session: session)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            try await Self.render(FurnitureJointRulesDialog(state: state), size: CGSize(width: 1230, height: 640), "ui-joint-rules-fasteners-\(appearance == .aqua ? "light" : "dark")")
        }
        NSApp.appearance = nil
    }

    /// The sample table on Component Library legs (hairpin, tapered, pedestal-free types), as the library previews it.
    @Test func tableOnComponentLegsRenders() throws {
        let m0 = try #require(FurnitureSamples.tableModel())
        for name in ["Hairpin Leg", "Turned Leg", "Angled Leg", "Tube Leg"] {
            let d = try #require(ComponentLibrary.component(named: name))
            let tx = TransactionContext(model: m0, name: "Legs")
            let t = try #require(ComponentLegTypes.ensureType(d, typeName: d.defaultType!.name, in: tx))
            for l in tx.model.elements(.furnitureLegs) { tx.update(l.id) { $0.typeID = t } }
            let m = try tx.commit().model
            let image = try #require(FurnitureThumbnail.image(m, width: 640, height: 480, detail: .fine))
            try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: Self.out.appendingPathComponent("table-\(name).png"))
        }
    }
}
