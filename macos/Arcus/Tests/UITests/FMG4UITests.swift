import Foundation
import Testing
import AppKit
import SwiftUI
@testable import ArcusDomain
@testable import ArcusApplication
@testable import ArcusUI

/// FMG4: Home ▸ Furniture names the new piece after the piece picked last (the owner picked Entryway Bench, then
/// Kitchen Cart, and got a cart called Entryway Bench); a name typed by the user stays; the category follows.
@Suite("FMG4 Home furniture picking") @MainActor
struct FMG4HomeTests {
    static func item(_ name: String, _ category: String) -> FurnitureLibraryCatalog.Item {
        var i = FurnitureLibraryCatalog.Item(url: URL(fileURLWithPath: "/tmp/\(name).arcusfurniture"), name: name, room: "Kitchen", isUser: false)
        i.category = category
        return i
    }

    @Test func theNameFollowsThePickedPieceUntilTheUserTypesOne() {
        let home = HomeModel(tab: .furniture, readsDisk: false)
        home.pickFurnitureTemplate(Self.item("Entryway Bench", "Furniture"))
        #expect(home.furnitureName == "Entryway Bench")
        home.pickFurnitureTemplate(Self.item("Kitchen Cabinet", "Casework"))
        #expect(home.furnitureName == "Kitchen Cabinet")
        #expect(home.furnitureCategory == .casework)
        #expect(home.furnitureTemplate?.lastPathComponent == "Kitchen Cabinet.arcusfurniture")
        home.pickFurnitureTemplate(nil)
        #expect(home.furnitureName == "Untitled Furniture" && home.furnitureTemplate == nil)
        home.furnitureName = "Mudroom Bench"
        home.pickFurnitureTemplate(Self.item("Kitchen Cart", "Furniture"))
        #expect(home.furnitureName == "Mudroom Bench")
        #expect(home.furnitureCategory == .furniture)
    }
}

/// FMG4: the Associate Family Parameter dialog and the = button in Properties, rendered offscreen to /tmp/arcus-fmg4/
/// (light and dark): a Kitchen Cabinet door's Leaf Count (the list, and New Parameter), the Entryway Bench cushion's
/// Visible (associated), and Properties with the = buttons.
@MainActor
@Suite("FMG4 associate UI", .serialized)
struct FMG4AssociateUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fmg4")

    static func render<V: View>(_ view: V, width: CGFloat, _ name: String, height: CGFloat? = nil) async throws -> CGSize {
        _ = NSApplication.shared
        let h = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let fit = h.fittingSize
        let size = CGSize(width: width, height: height ?? max(60, fit.height))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<6 { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
        return fit
    }

    @Test func theDialogAndTheButtonRender() async throws {
        _ = NSApplication.shared
        let cabinet = try #require(FurnitureLibrary.essentials.first { $0.name == "Kitchen Cabinet" }).build()
        let state = DocumentState(session: DocumentSession(model: cabinet))
        let door = try #require(cabinet.elements(.furnitureFronts).first { $0.furnitureFront?.kind == .door })
        let bench = try #require(FurnitureLibrary.essentials.first { $0.name == "Entryway Bench" }).build()
        let benchState = DocumentState(session: DocumentSession(model: bench))
        let cushion = try #require(bench.elements(.furnitureForms).first)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let tag = appearance == .aqua ? "light" : "dark"
            let fit = try await Self.render(AssociateFamilyParameterDialog(state: state, elements: [door.id], property: FurnitureFrontParameters.leafCount.id, propertyName: "Leaf Count"),
                                            width: 480, "fmg4-associate-leafcount-\(tag)")
            #expect(fit.height < 520, "the dialog sizes to its content: \(fit)")
            _ = try await Self.render(AssociateFamilyParameterDialog(state: state, elements: [door.id], property: FurnitureFrontParameters.leafCount.id, propertyName: "Leaf Count",
                                                                     startAdding: true, newName: "Pair Doors"), width: 480, "fmg4-associate-new-\(tag)")
            _ = try await Self.render(AssociateFamilyParameterDialog(state: benchState, elements: [cushion.id], property: FurnitureAssociations.visible, propertyName: "Visible"),
                                      width: 480, "fmg4-associate-visible-\(tag)")
            state.session.selection.select([door.id])
            _ = try await Self.render(PropertiesView(state: state), width: 320, "fmg4-properties-door-\(tag)", height: 620)
            benchState.session.selection.select([cushion.id])
            _ = try await Self.render(PropertiesView(state: benchState), width: 320, "fmg4-properties-cushion-\(tag)", height: 620)
        }
        NSApp.appearance = nil
    }
}

/// FMG4: the ribbon's More popover shows only the panels the row has no room for (a panel the row shows draws
/// nothing there), and a command closes the collapsed-panel and More popovers.
@MainActor
@Suite("FMG4 ribbon overflow")
struct FMG4RibbonTests {
    @Test func morePopoverShowsOnlyHiddenPanels() {
        func width(_ only: Set<String>?) -> CGFloat {
            let v = CollapsibleRibbonPanel(key: "3 Modify", title: "Modify") { _ in Text("Modify tools").padding() }
                .environment(\.ribbonOverflowOnly, only)
            return NSHostingView(rootView: v).fittingSize.width
        }
        #expect(width(nil) > 20)
        #expect(width(["3 Modify"]) > 20)
        #expect(width(["4 Create"]) < 1)
    }

    @Test func aCommandPostsTheNotificationThatClosesPopovers() {
        let state = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        final class Flag: @unchecked Sendable { var heard = false }
        let flag = Flag()
        let token = NotificationCenter.default.addObserver(forName: .arcusCommandRan, object: nil, queue: nil) { _ in flag.heard = true }
        defer { NotificationCenter.default.removeObserver(token) }
        CommandRouter(state: state).run(.modify)
        #expect(flag.heard)
    }
}
