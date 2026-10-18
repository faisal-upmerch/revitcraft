import CoreGraphics
import Foundation
import ImageIO
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

/// BL-SCHED: File ▸ Export ▸ Images renders views and sheets to PNG/JPEG locally.
@Suite("Image export (BL-SCHED)")
struct RasterExportTests {
    func darkPixels(_ image: CGImage) -> Int {
        let b = Bitmap(image.width, image.height)
        b.ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var n = 0
        for y in stride(from: 0, to: image.height, by: 2) { for x in stride(from: 0, to: image.width, by: 2) where b.ink(x, y) > 0.5 { n += 1 } }
        return n
    }

    func decoded(_ data: Data) throws -> (image: CGImage, props: [CFString: Any]) {
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        return (img, props)
    }

    @Test func planViewExportsAsPNG() throws {
        let f = Fixture.shared
        let g = ViewGraphicsBuilder(model: f.model, view: f.model[f.plan]!).build()
        let image = try #require(RasterExporter.render(g, pixelWidth: 1600))
        #expect(image.width == 1600)
        let region = RasterExporter.region(g, paper: nil)
        #expect(abs(Double(image.height) - 1600 * region.height / region.width) <= 1)
        #expect(darkPixels(image) > 500, "the walls should be drawn")
        let png = try #require(RasterExporter.encode(image, as: .png))
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        let back = try decoded(png)
        #expect(back.image.width == image.width && back.image.height == image.height)
    }

    @Test func sheetExportsAsJPEGAtPaperAspectWithDPI() throws {
        let f = Fixture.shared
        let sheet = f.model[f.sheetPlan]!
        let paper = sheet.sheet!.paper.landscapeSize
        let g = SheetGraphicsBuilder(model: f.model, sheet: sheet).build()
        let image = try #require(RasterExporter.render(g, paper: paper, pixelWidth: 2000))
        #expect(image.width == 2000 && abs(Double(image.height) - 2000 * paper.y / paper.x) <= 1)
        #expect(darkPixels(image) > 500, "title block and viewport content should be drawn")
        let dpi = RasterExporter.dpi(pixelWidth: image.width, paperWidth: paper.x)
        let jpeg = try #require(RasterExporter.encode(image, as: .jpeg, quality: 0.8, dpi: dpi))
        #expect(Array(jpeg.prefix(3)) == [0xFF, 0xD8, 0xFF])
        let back = try decoded(jpeg)
        #expect(back.image.width == 2000)
        let written = (back.props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
        #expect(abs(written - dpi) < 1)
    }

    @Test func pixelSizeIsClamped() {
        let tall = Rect2(min: .zero, max: Vec2(1, 100))
        let s = RasterExporter.pixelSize(tall, pixelWidth: 4000)
        #expect(s.height == RasterExporter.maximumPixels && s.width < 4000 && s.width >= 16)
        #expect(RasterExporter.pixelSize(Rect2(min: .zero, max: Vec2(2, 1)), pixelWidth: 1000) == (1000, 500))
    }

    @Test func emptyViewStillProducesAnImage() throws {
        let g = graphics([])
        let image = try #require(RasterExporter.render(g, pixelWidth: 200))
        #expect(image.width == 200 && darkPixels(image) == 0)
    }
}
