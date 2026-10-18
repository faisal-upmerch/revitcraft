import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

/// F13: DWFx, STL, gbXML, Room/Area Report, Family Types, Print Setup filtering and PDF options.
@Suite("F13 export and print")
struct F13OutputTests {
    let f = Fixture.shared

    @Test func zipRoundTripsWithStandardCRC() throws {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        let big = Data(String(repeating: "Arcus DWFx ", count: 400).utf8)
        let zip = ZipArchive.write([("a.txt", Data("hello".utf8)), ("dir/b.xml", big), ("empty", Data())])
        let back = try #require(ZipArchive.entries(zip))
        #expect(back.map(\.name) == ["a.txt", "dir/b.xml", "empty"])
        #expect(back[1].data == big && back[0].data == Data("hello".utf8) && back[2].data.isEmpty)
        #expect(zip.count < big.count) // deflated
        #expect(ZipArchive.entries(Data("not a zip".utf8)) == nil)
    }

    @Test func dwfxPackagesSheetsAsFixedPages() throws {
        let m = f.model
        let sheet = try #require(m[f.sheetPlan])
        let page = DWFxExporter.sheetPage(sheet, model: m)
        let fakeFont = Data(repeating: 0, count: 16)
        let (data, warnings) = DWFxExporter.write([page, DWFxExporter.schedulePage(m[f.doorSchedule]!, model: m)], fonts: (fakeFont, nil))
        #expect(warnings.isEmpty)
        let entries = try #require(ZipArchive.entries(data))
        let names = Set(entries.map(\.name))
        #expect(names.isSuperset(of: ["[Content_Types].xml", "_rels/.rels", "FixedDocumentSequence.fdseq", "Documents/1/FixedDocument.fdoc", "Resources/arial.ttf"]))
        let pages = entries.filter { $0.name.hasSuffix(".fpage") }
        #expect(pages.count == 2)
        let xml = String(decoding: pages.first { $0.name.contains("A101") }!.data, as: UTF8.self)
        #expect(xml.contains("<FixedPage") && xml.contains("<Path Stroke=") && xml.contains("<Glyphs"))
        // Page size: the A1 sheet in 1/96 inch.
        let w = page.paper.x * 96 / 0.0254
        #expect(xml.contains("Width=\"\(DWFxExporter.n(w))\""))
        let doc = String(decoding: entries.first { $0.name == "Documents/1/FixedDocument.fdoc" }!.data, as: UTF8.self)
        #expect(doc.components(separatedBy: "<PageContent").count == 3)
        // Without fonts the text is left out, with a warning.
        let (_, w2) = DWFxExporter.write([page], fonts: (nil, nil))
        #expect(!w2.isEmpty)
    }

    @Test func stlHasTheModelsTriangles() {
        let (data, n) = STLExporter.write(f.model)
        #expect(n > 50 && data.count == 84 + 50 * n)
        let count = data[80..<84].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        #expect(Int(count) == n)
    }

    @Test func gbXMLAndRoomReportListTheRooms() {
        let (xml, n) = GbXMLExporter.write(f.model)
        #expect(n == 1 && xml.contains("<Space id=") && xml.contains("<ClosedShell>") && xml.contains("101 Reading Room"))
        // Floor, ceiling and four walls.
        #expect(xml.components(separatedBy: "<PolyLoop>").count - 1 == 6)
        let (html, rows) = RoomAreaReport.write(f.model, format: .html)
        #expect(rows == 1 && html.contains("<polygon") && html.contains("Reading Room"))
        let (csv, _) = RoomAreaReport.write(f.model, format: .csv)
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "Kind,Number,Name,Level,Area,Perimeter" && lines.count == 3 && lines[1].hasPrefix("Room,101,Reading Room"))
    }

    @Test func familyTypesExportAsATypeCatalog() throws {
        let fam = try #require(f.model.elements(.families).compactMap(\.family).first { $0.types.count > 1 && $0.parameters.contains { !$0.isInstance && $0.type == .length } })
        let text = FamilyTypesExport.write(fam)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        #expect(lines.first?.contains("##LENGTH##MILLIMETERS") == true)
        #expect(lines.count == fam.types.count + 1)
    }

    @Test func printSetupHidesAndRecolours() throws {
        let m = f.model
        let plan = m[f.plan]!
        var g = ViewGraphicsBuilder(model: m, view: plan).build()
        g.items.append(GItem(elementID: nil, category: .referencePlanes, layer: .model, primitives: [.polyline([.zero, Vec2(1, 0)], closed: false, GStroke(weight: 1, color: RGBColor(0, 0.5, 0)))]))
        g.items.append(GItem(elementID: nil, category: .scopeBoxes, layer: .model, primitives: []))
        var o = PrintOptions()
        o.colors = .grayscale
        let out = PrintFiltering.apply(g, o, model: m)
        #expect(!out.items.contains { $0.category == .referencePlanes || $0.category == .scopeBoxes || $0.layer == .overlay })
        for item in out.items { for p in item.primitives { if case .polyline(_, _, let s) = p { #expect(Fx3.isGray(s.color)) } } }
        let kept = PrintFiltering.apply(g, .none, model: m)
        #expect(kept.items.count == g.items.count)
    }

    @Test func pdfExportHonoursPrintSetupOptions() async throws {
        let dir = Fixture.tempDir()
        var job = PDFExportJob(items: [.view(f.plan)], outputDirectory: dir)
        job.combinedFileName = "plan.pdf"
        job.hideReferencePlanes = true
        job.colors = .blackLines
        let r = try await PDFExporter.export(f.model, job: job)
        #expect(r.pageCount == 1 && r.files.count == 1)
        try? FileManager.default.removeItem(at: dir)
    }
}

enum Fx3 {
    static func isGray(_ c: RGBColor) -> Bool { abs(c.r - c.g) < 1e-9 && abs(c.g - c.b) < 1e-9 }
}
