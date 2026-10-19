import Foundation
import PDFKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// FM7: the shop drawing set (F101–F104) of the sample cabinet as PDF and images, with the Nesting views and the
/// fabrication schedules on their sheets. Renders go to /tmp/arcus-fm7/ for checking by eye.
@Suite("FM7 shop drawings output")
struct FM7OutputTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fm7")

    static func shopModel() throws -> BIMModel {
        let base = try #require(FurnitureSamples.baseCabinetModel())
        let tx = TransactionContext(model: base, name: "Shop Drawings")
        FurnitureShopDrawings.update(in: tx)
        return try tx.commit().model
    }

    @Test func sheetSetExportsToPDF() async throws {
        let m = try Self.shopModel()
        let sheets = m.sheets.filter { $0.sheet?.number.hasPrefix("F1") == true }.sorted { ($0.sheet?.number ?? "") < ($1.sheet?.number ?? "") }
        #expect(sheets.count == 4)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("fm7-pdf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        var job = PDFExportJob(items: sheets.map { .sheet($0.id) }, outputDirectory: out)
        job.combined = true
        job.combinedFileName = "Shop Drawings"
        let r = try await PDFExporter.export(m, job: job)
        #expect(r.files.count == 1 && r.pageCount == 4)
        let url = try #require(r.files.first)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 20_000)
        let pdf = try #require(PDFDocument(url: url))
        // F102 has the Part List; F103 the Nesting views; every page the piece's title block.
        func page(_ i: Int) -> String { pdf.page(at: i)?.string?.lowercased() ?? "" }
        #expect(page(1).contains("part list"))
        #expect(page(1).contains("hardware schedule"))
        #expect(page(2).contains("yield"))
        #expect(page(0).contains("base cabinet"))
        #expect(page(3).contains("piece cost"))
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent("shop-drawings.pdf"))
        try? FileManager.default.copyItem(at: url, to: Self.dir.appendingPathComponent("shop-drawings.pdf"))
    }

    @Test func sheetsAndNestingViewsRenderAsImages() throws {
        let m = try Self.shopModel()
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        for s in m.sheets {
            let g = SheetGraphicsBuilder(model: m, sheet: s).build()
            let img = try #require(RasterExporter.render(g, paper: s.sheet?.paper.landscapeSize, pixelWidth: 2200))
            let png = try #require(RasterExporter.encode(img, as: .png))
            #expect(png.count > 30_000)
            try png.write(to: Self.dir.appendingPathComponent("sheet-\(s.sheet?.number ?? s.name).png"))
        }
        for v in FurnitureNestingViews.views(m) {
            let g = ViewGraphicsBuilder(model: m, view: v).build()
            #expect(!g.items.isEmpty)
            let img = try #require(RasterExporter.render(g, pixelWidth: 1800))
            let png = try #require(RasterExporter.encode(img, as: .png))
            try png.write(to: Self.dir.appendingPathComponent("nesting-\(v.name.replacingOccurrences(of: "\"", with: "in").replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "_")).png"))
        }
    }
}
