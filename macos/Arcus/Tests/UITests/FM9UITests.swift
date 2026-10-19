import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusPersistence
@testable import ArcusUI

/// FM9: offscreen renders of the Furniture Library to `/tmp/arcus-fm9/` (every essential piece in 3D and in a front
/// elevation, each type; the kit's recipes), and of the galleries that show it (Home ▸ Furniture, Load Furniture).
/// `FM9_PIECES=Sofa,Bed` limits the piece renders to those names; `FM9_FAST=1` renders only the first type in 3D.
@MainActor
@Suite("FM9 Furniture Library UI", .serialized)
struct FM9UITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm9")

    static var only: Set<String>? {
        ProcessInfo.processInfo.environment["FM9_PIECES"].map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
    }

    static func write(_ image: CGImage?, _ name: String) {
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? png.write(to: out.appendingPathComponent(name + ".png"))
    }

    /// The piece in 3D (front left, above) and seen from the front, on white, for each of its types.
    static func renderPiece(_ name: String, _ m: BIMModel) {
        let file = name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: "")
        let types = m.furnitureSetup?.family.types.map(\.name) ?? []
        let fast = ProcessInfo.processInfo.environment["FM9_FAST"] != nil
        for (k, t) in types.enumerated() where !fast || k == 0 {
            let suffix = types.count > 1 ? "-\(k + 1)" : ""
            write(onWhite(FurnitureThumbnail.image(m, width: 900, height: 680, type: t)), "\(file)\(suffix)-3d")
            if k == 0, !fast {
                write(onWhite(FurnitureThumbnail.image(m, width: 900, height: 680, type: t, yaw: 0, pitch: 0)), "\(file)-front")
                write(onWhite(FurnitureThumbnail.image(m, width: 900, height: 680, type: t, yaw: -Double.pi / 2, pitch: 0)), "\(file)-side")
            }
        }
    }

    static func onWhite(_ image: CGImage?) -> CGImage? {
        guard let image, let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    @Test func rendersTheEssentials() throws {
        for p in FurnitureLibrary.all where p.detail == .high && (Self.only?.contains(p.name) ?? true) {
            Self.renderPiece(p.name, p.build())
        }
    }

    @Test func rendersTheKitRecipes() throws {
        guard Self.only?.contains("Kit") ?? true else { return }
        let pieces: [(String, BIMModel)] = [
            ("Kit Cabinet", LibraryKit.piece("Kit Cabinet", category: .casework, sizes: [.init("36\"", w: 36, d: 20, h: 30)]) { b in
                try b.carcass(CarcassSpec(columns: [CarcassColumn(CarcassRow(.door, shelves: 1), CarcassRow(.drawers(1), height: 5)),
                                                    CarcassColumn(CarcassRow(.drawers(3)))]))
            }),
            ("Kit Table", LibraryKit.piece("Kit Table", sizes: [.init("60\"", w: 60, d: 36, h: 30)]) { b in
                try b.table(TableSpec(drawer: (width: 18, height: 3.5, type: nil)))
            }),
            ("Kit Chair", LibraryKit.piece("Kit Chair", sizes: [.init("Standard", w: 18, d: 20, h: 34)]) { b in
                try b.chair(ChairSpec(seat: .upholstered(material: "Fabric - Oatmeal Linen", thickness: 2), stretchers: (type: "3/4\" x 1 1/2\" Stretcher", height: 6)))
            }),
            ("Kit Bed", LibraryKit.piece("Kit Bed", sizes: [.init("Queen", w: 64, d: 86, h: 44)]) { b in
                try b.bed(BedSpec(headboard: .upholstered(material: "Fabric - Sage Boucle", thickness: 3, channels: 6)))
            }),
            ("Kit Shelving", LibraryKit.piece("Kit Shelving", sizes: [.init("36\"", w: 36, d: 14, h: 72)]) { b in
                try b.shelving(ShelvingSpec(brace: "3/4\" x 3/4\" Cleat"))
            }),
            ("Kit Sofa", LibraryKit.piece("Kit Sofa", sizes: [.init("84\"", w: 84, d: 36, h: 34)]) { b in
                try b.upholstered(UpholsteredSpec(seats: 3, pillows: 2))
            }),
        ]
        for (n, m) in pieces { Self.renderPiece(n, m) }
    }

    // MARK: Generator and galleries

    /// The library written to a fresh folder with the generator (the essentials, or everything registered).
    static func writeLibrary(_ pieces: [FurnitureLibraryPiece]) throws -> (URL, [FurnitureLibraryWriter.Result], FurnitureLibraryIndex) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fm9-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        let (results, index) = try FurnitureLibraryWriter.write(pieces, to: dir, appVersion: "1.0", build: "1") { FurniturePreview.png($0) }
        return (dir, results, index)
    }

    static func render<V: View>(_ view: V, size: CGSize, _ name: String, dark: Bool, settle: Int = 16) async throws {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let h = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        h.frame = NSRect(origin: .zero, size: size)
        w.contentView = h
        for _ in 0..<settle { h.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(60)) }
        h.displayIfNeeded()
        let rep = try #require(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    @Test func generatorWritesFurnitureDocumentsTheCatalogListsUnderEveryRoom() async throws {
        let pieces = FurnitureLibrary.all.filter { $0.detail == .high }
        let (dir, results, index) = try Self.writeLibrary(pieces)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(results.allSatisfy { $0.error == nil }, "\(results.compactMap(\.error).prefix(3))")
        #expect(index.pieces.count == pieces.count)
        // Every file opens as a Furniture document with its types and a preview.
        for p in index.pieces {
            let url = dir.appending(path: p.file, directoryHint: .notDirectory)
            let (m, manifest) = try ArcusPackage.read(from: url)
            #expect(m.isFurniture && m.furnitureSetup?.name == p.name && manifest.kind == DocumentKind.furniture.rawValue, "\(p.file)")
            #expect(m.furnitureSetup?.family.types.map(\.name) == p.types.map(\.name))
            #expect(ArcusPackage.readThumbnail(url) != nil, "\(p.file): no preview")
            #expect(p.types.allSatisfy { $0.width > 0 && $0.depth > 0 && $0.height > 0 })
        }
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "Living Room/Sofa.arcusfurniture").path))
        #expect(index.pieces.first { $0.name == "Bed" }?.types.map(\.width) == [40, 56, 62, 78], "the mattress sizes drive the bed's Width")
        // The catalog lists each piece under every room it names; the file lives once, in the first room.
        let items = FurnitureLibraryCatalog.scan(bundled: dir, user: nil)
        let storage = items.filter { $0.name == "Storage Cabinet" }
        #expect(Set(storage.map(\.room)) == ["Living Room", "Storage & Utility"] && Set(storage.map(\.url)).count == 1)
        #expect(storage.first?.url.path.contains("/Living Room/") == true)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "Storage & Utility/Storage Cabinet.arcusfurniture").path))
        #expect(FurnitureLibraryCatalog.rooms(items, matching: "nightstand").flatMap(\.items).map(\.name) == ["Bedside Table"], "keywords are searched")
        #expect(items.first { $0.name == "Sofa" }?.typeCountText == "3 types")
        // The galleries, light and dark.
        let project = DocumentState(session: DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0))
        for dark in [false, true] {
            try await Self.render(FurnitureLibraryBrowser(state: project, items: items), size: CGSize(width: 1120, height: 680), "fm9-load-furniture", dark: dark)
            let home = HomeModel(tab: .furniture, readsDisk: false)
            home.library = items
            Self.renderHome(home, "fm9-home-furniture", dark: dark)
            ComponentLibraryView.startInFurniture = true
            try await Self.render(ComponentLibraryView(state: project, categories: [], furnitureItems: items), size: CGSize(width: 1120, height: 720), "fm9-component-library-furniture", dark: dark)
            ComponentLibraryView.startInFurniture = false
        }
        try await Self.render(FurnitureLibraryBrowser(state: project, items: items.filter { $0.matches("walnut") }), size: CGSize(width: 1120, height: 680),
                              "fm9-load-furniture-search", dark: false)
    }

    /// Home in its real window chrome (as HomeRenderTests draws it).
    static func renderHome(_ model: HomeModel, _ name: String, dark: Bool) {
        _ = NSApplication.shared
        let w = AppDelegate.makeHubWindow(model: model)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.setContentSize(CGSize(width: 1040, height: 660))
        w.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        w.contentView?.layoutSubtreeIfNeeded()
        w.displayIfNeeded()
        guard let view = w.contentView?.superview ?? w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: "\(name)-\(dark ? "dark" : "light").png"))
        w.close()
    }
}
