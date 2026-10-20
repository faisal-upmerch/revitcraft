import AppKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusApplication
import ArcusOutput
@testable import ArcusUI

/// LEGFIX: the Decorative Bench at Fine, rendered offscreen to `/tmp/arcus-legfix/`: its turned legs keep their beads
/// and vase, with a square block where the low stretchers join and the aprons in the pommel.
@MainActor
@Suite("LEGFIX bench render", .serialized)
struct LEGFIXUITests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-legfix")

    @Test func theBenchRendersAtFine() throws {
        let m = try #require(SimpleB.pieces.first { $0.name == "Decorative Bench" }).make()
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        let views: [(String, Double?, Double?)] = [("3d", nil, nil), ("front", 0, 0), ("low", -0.35, 0.12)]
        for (name, yaw, pitch) in views {
            let img = FM9UITests.onWhite(FurnitureThumbnail.image(m, width: 1200, height: 900, yaw: yaw ?? ShadedFamilyRenderer.yaw,
                                                                  pitch: pitch ?? ShadedFamilyRenderer.pitch, detail: .fine))
            let shot = try #require(img, "\(name) renders")
            let png = try #require(NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:]))
            try png.write(to: Self.out.appendingPathComponent("decorative-bench-fine-\(name).png"))
        }
    }
}
