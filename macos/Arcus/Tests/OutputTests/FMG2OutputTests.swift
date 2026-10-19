import Foundation
import PDFKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// FMG2: exploded 3D views (Explode Parts) as images and PDF, and shop drawing F104 with its exploded view, rendered
/// to /tmp/arcus-fmg2/ for checking by eye.
@Suite("FMG2 exploded views output")
struct FMG2OutputTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fmg2")
    static let inch = 0.0254

    static func exploded(_ m: BIMModel, _ name: String = "{3D}", distance: Double = 4 * 0.0254) throws -> (BIMModel, Element) {
        let v = try #require(m.views.first { $0.name == name })
        let tx = TransactionContext(model: m, name: "Explode")
        try FurnitureExplode.set(v.id, on: true, distance: distance, in: tx)
        let out = try tx.commit().model
        return (out, try #require(out[v.id]))
    }

    static func write(_ g: ViewGraphics, _ name: String, paper: Vec2? = nil, width: Int = 1800) throws {
        let img = try #require(RasterExporter.render(g, paper: paper, pixelWidth: width))
        let png = try #require(RasterExporter.encode(img, as: .png))
        #expect(png.count > 10_000, "\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent(name + ".png"))
    }

    @Test func explodedViewsRenderAsImages() throws {
        for (name, model) in [("bookcase", FurnitureSamples.bookcaseModel()), ("table", FurnitureSamples.tableModel()), ("cabinet", FurnitureSamples.baseCabinetModel())] {
            let (m, v) = try Self.exploded(try #require(model))
            let g = ViewGraphicsBuilder(model: m, view: v).build()
            let tags = g.items.filter { $0.category == .tags && $0.layer == .annotation }
            #expect(!tags.isEmpty, "\(name) has part tags")
            try Self.write(g, "exploded-\(name)")
        }
    }

    @Test func f104IsExplodedInPDFAndImages() async throws {
        let base = try #require(FurnitureSamples.baseCabinetModel())
        let tx = TransactionContext(model: base, name: "Shop Drawings")
        FurnitureShopDrawings.update(in: tx)
        let m = try tx.commit().model
        let f104 = try #require(m.sheets.first { $0.sheet?.number == FurnitureShopDrawings.details })
        let g = SheetGraphicsBuilder(model: m, sheet: f104).build()
        try Self.write(g, "sheet-F104", paper: f104.sheet?.paper.landscapeSize, width: 2400)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("fmg2-pdf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = try await PDFExporter.export(m, job: PDFExportJob(items: [.sheet(f104.id)], outputDirectory: out))
        let url = try #require(r.files.first)
        let pdf = try #require(PDFDocument(url: url))
        let text = pdf.page(at: 0)?.string ?? ""
        let marks = m.elements(.furniturePanels).map(\.mark).filter { !$0.isEmpty }
        #expect(marks.contains { text.contains($0) }, "the exploded view's tags are in the PDF")
        try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent("sheet-F104.pdf"))
        try? FileManager.default.copyItem(at: url, to: Self.dir.appendingPathComponent("sheet-F104.pdf"))
    }
}
