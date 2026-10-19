import AppKit
import SwiftUI
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
@testable import ArcusUI

/// FM9: offscreen renders of the Furniture Library to `/tmp/arcus-fm9/` (every essential piece in 3D and in a front
/// elevation, each type; the kit's recipes), and of the galleries that show it (Home ▸ Furniture, Load Furniture).
/// `FM9_PIECES=Sofa,Bed` limits the piece renders to those names.
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
        for (k, t) in types.enumerated() {
            let suffix = types.count > 1 ? "-\(k + 1)" : ""
            write(onWhite(FurnitureThumbnail.image(m, width: 900, height: 680, type: t)), "\(file)\(suffix)-3d")
            if k == 0 {
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
}
