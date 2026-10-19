import AppKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusUI

/// FM9B: the simple library pieces as the library shows them (the Load Furniture preview: a shaded three-quarter view
/// of the loaded piece at Medium), rendered offscreen to `/tmp/arcus-fm9b/` one per piece and per type, and as contact
/// sheets of twelve, to check by eye that each piece is recognisable.
@MainActor
@Suite("FM9B library previews", .serialized)
struct FM9BRenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-fm9b")

    @Test func everyPieceRendersAPreview() throws {
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        var images: [(String, CGImage)] = []
        for spec in FurnitureLibrary.simpleASpecs {
            let m = try spec.build()
            for (k, size) in spec.sizes.enumerated() {
                var model = m
                if k > 0 {
                    let tx = TransactionContext(model: m, name: "Type")
                    try FurnitureParameters.setCurrentType(size.name, in: tx)
                    model = try tx.commit().model
                }
                let image = try #require(FurnitureThumbnail.image(model, width: 480, height: 360), "\(spec.name)")
                let file = "\(spec.name)\(k > 0 ? " (\(k + 1))" : "")".replacingOccurrences(of: "/", with: "-")
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: Self.out.appendingPathComponent(file + ".png"))
                if k == 0 { images.append((spec.name, image)) }
            }
        }
        // Contact sheets: 4 x 3 previews with their names.
        let cols = 4, rows = 3, w = 480, h = 380
        for (page, start) in stride(from: 0, to: images.count, by: cols * rows).enumerated() {
            let ctx = try #require(CGContext(data: nil, width: cols * w, height: rows * h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: cols * w, height: rows * h))
            for (i, (name, img)) in images[start..<min(images.count, start + cols * rows)].enumerated() {
                let x = (i % cols) * w, y = (rows - 1 - i / cols) * h
                ctx.draw(img, in: CGRect(x: x, y: y + 20, width: 480, height: 360))
                let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ns
                (name as NSString).draw(at: NSPoint(x: x + 8, y: y + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.black])
                NSGraphicsContext.restoreGraphicsState()
            }
            let sheet = try #require(ctx.makeImage())
            try NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:])?.write(to: Self.out.appendingPathComponent("_sheet \(page + 1).png"))
        }
    }
}
