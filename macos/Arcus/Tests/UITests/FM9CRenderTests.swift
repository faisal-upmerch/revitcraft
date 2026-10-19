import AppKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusUI

/// FM9C: every simple piece of part B rendered as its Furniture preview (shaded three-quarter view at Medium, as Home ▸
/// Furniture and Load Furniture show it) to /tmp/arcus-fm9c/<Name>.png and on contact sheets of twelve
/// (sheet-1.png…), for checking the pieces by eye; the test checks each one draws.
@MainActor
@Suite("FM9C library renders")
struct FM9CRenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fm9c")

    @Test func everyPieceRendersItsPreview() throws {
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let (w, h, label) = (420, 315, 26)
        var images: [(String, CGImage)] = []
        for p in SimpleB.pieces {
            let m = try p.make()
            let img = try #require(FurnitureThumbnail.image(m, width: w, height: h), "\(p.name) draws")
            images.append((p.name, img))
            if let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                try png.write(to: Self.dir.appendingPathComponent("\(p.name.replacingOccurrences(of: "/", with: "-")).png"))
            }
        }
        let cols = 4, rows = 3
        for (k, start) in stride(from: 0, to: images.count, by: cols * rows).enumerated() {
            let page = Array(images[start..<min(images.count, start + cols * rows)])
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cols * w, pixelsHigh: rows * (h + label), bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(white: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: cols * w, height: rows * (h + label)).fill()
            for (i, (name, img)) in page.enumerated() {
                let c = i % cols, r = i / cols
                let y = (rows - 1 - r) * (h + label)
                NSGraphicsContext.current?.cgContext.draw(img, in: CGRect(x: c * w, y: y, width: w, height: h))
                NSColor(white: 0.85, alpha: 1).setStroke()
                NSRect(x: c * w, y: y, width: w, height: h + label).frame()
                (name as NSString).draw(at: NSPoint(x: c * w + 8, y: y + h + 5), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.black])
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.dir.appendingPathComponent("sheet-\(k + 1).png"))
        }
    }
}
