import CoreGraphics
import Foundation
import PDFKit
import ImageIO
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

// W4-HATCH: line-family hatches through the CoreGraphics renderer and the PDF exporter.

@Suite("Hatch output")
struct HatchOutputTests {
    /// Sheet-like drafting space: 8 px per paper millimetre; region 50…250 px.
    static let p = 8_000.0
    static let region = Rect2(min: Vec2(0.00625, 0.00625), max: Vec2(0.03125, 0.03125))

    static func render(_ fill: GFill, hole: Bool = false) -> Bitmap {
        var polys = [Polygon2.rectangle(region)]
        if hole { polys.append(.rectangle(Rect2(min: Vec2(0.015, 0.015), max: Vec2(0.0225, 0.0225)))) }
        let item = GItem(elementID: nil, category: .filledRegions, layer: .fills, primitives: [.fill(polys, fill)])
        let b = Bitmap(300, 300)
        GraphicsRenderer.draw(graphics([item], scale: 1), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: CGFloat(p), y: CGFloat(p)), pointsPerPaperMeter: p, options: RenderOptions())
        return b
    }

    @Test(arguments: FillPatternLibrary.drafting.filter { $0.kind != .solid }.map(\.name))
    func everyStandardDraftingPatternDrawsInkInsideItsRegionOnly(_ name: String) throws {
        let d = try #require(FillPatternLibrary.named(name)).data
        let b = Self.render(GFill(fillPattern: d, color: .black))
        var outside = 0.0, inside = 0.0
        for y in 0..<300 { for x in 0..<300 { let v = b.ink(x, y); if x < 47 || x > 253 || y < 47 || y > 253 { outside = max(outside, v) } else { inside += v } } }
        #expect(outside < 0.01, "\(name) leaked outside its region")
        #expect(inside > 30, "\(name) drew nothing")
    }

    @Test func hatchLinesAreRealLinesNotProceduralAndHolesStayEmpty() throws {
        // Horizontal 3 mm lines: at 8 px/mm rows of ink every 24 px, nothing between them.
        var d = FillPatternData(kind: .horizontal, isModelPattern: false, spacing: 3)
        d.families = [HatchFamily(angle: 0, spacing: 3)]
        let b = Self.render(GFill(fillPattern: d, color: .black), hole: true)
        var inkedRows = 0, holeInk = 0.0
        for y in 50..<250 {
            let row = (55..<115).reduce(0.0) { $0 + b.ink($1, y) }
            if row > 20 { inkedRows += 1 }
        }
        for y in 124...176 { for x in 124...176 { holeInk = max(holeInk, b.ink(x, y)) } }
        // ~8 lines (200 px / 24 px), each a pen 1 stroke about 1–2 px high.
        #expect((7...20).contains(inkedRows), "inked rows \(inkedRows)")
        #expect(holeInk < 0.01)
        // Denser than two device pixels → the renderer tints instead of drawing lines (no moiré).
        var dense = d; dense.families = [HatchFamily(angle: 0, spacing: 0.1)]
        let t = Self.render(GFill(fillPattern: dense, color: .black))
        let centre = t.ink(150, 150), neighbour = t.ink(150, 151)
        #expect(centre > 0.05 && centre < 0.6 && abs(centre - neighbour) < 0.05, "expected a flat tint, got \(centre)/\(neighbour)")
    }

    @Test func modelPatternsScaleWithTheViewAndDraftingPatternsDoNot() throws {
        func rows(_ d: FillPatternData, scale: Int) -> Int {
            // 1 model metre region drawn at `scale` with 20 px per paper mm.
            let ppm = 20_000.0
            let item = GItem(elementID: nil, category: .floors, layer: .fills, primitives: [.fill([.rectangle(Rect2(min: Vec2(0, 0), max: Vec2(1, 1)))], GFill(fillPattern: d, color: .black))])
            let px = Int(ppm / Double(scale))
            let b = Bitmap(px, px)
            GraphicsRenderer.draw(graphics([item], scale: scale), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: CGFloat(ppm / Double(scale)), y: CGFloat(ppm / Double(scale))), pointsPerPaperMeter: ppm, options: RenderOptions())
            var n = 0
            for y in 0..<px where (px / 4..<px * 3 / 4).reduce(0.0, { $0 + b.ink($1, y) }) > Double(px) * 0.2 { n += 1 }
            return n
        }
        var model = FillPatternData(kind: .horizontal, isModelPattern: true, spacing: 100)
        model.families = [HatchFamily(angle: 0, spacing: 100)]       // 100 mm boards → 9 interior lines per metre at any scale
        var drafting = FillPatternData(kind: .horizontal, isModelPattern: false, spacing: 3)
        drafting.families = [HatchFamily(angle: 0, spacing: 3)]      // 3 mm on paper → 1 m at 1:100 holds 3 lines, at 1:20 holds 16
        let m100 = rows(model, scale: 100), m20 = rows(model, scale: 20)
        let d100 = rows(drafting, scale: 100), d20 = rows(drafting, scale: 20)
        #expect(m100 >= 8 && m100 <= 20 && m20 >= 8 && m20 <= 40, "model rows \(m100) / \(m20)")
        #expect(d20 > d100 * 3, "drafting rows \(d100) at 1:100, \(d20) at 1:20")
    }

    @Test func pdfPlanContainsVectorHatchLines() async throws {
        let f = Fixture.shared
        // The brick-on-CMU walls at fine detail produce many short hatch strokes; coarse produces solid fills only.
        func lineOps(detail: DetailLevel) async throws -> Int {
            var m = f.model
            let tx = TransactionContext(model: m, name: "detail")
            tx.update(f.plan) { $0.view?.detailLevel = detail }
            m = try tx.commit().model
            let job = PDFExportJob(items: [PDFExportItem(elementID: f.plan, kind: .view)], outputDirectory: Fixture.tempDir())
            let r = try await PDFExporter.export(m, job: job)
            let doc = try #require(PDFDocument(url: r.files[0]))
            let page = try #require(doc.page(at: 0)?.pageRef)
            let ops = operatorCounts(page)
            #expect(ops.xobjects == 0)
            return ops.lines
        }
        let fine = try await lineOps(detail: .fine)
        let coarse = try await lineOps(detail: .coarse)
        #expect(fine > coarse + 200, "fine \(fine) vs coarse \(coarse) line operators")
    }

    /// Writes a contact sheet of every standard pattern when ARCUS_HATCH_PREVIEW_DIR is set (visual QA aid).
    @Test func previewSheetOfTheStandardLibrary() throws {
        guard let dir = ProcessInfo.processInfo.environment["ARCUS_HATCH_PREVIEW_DIR"] else { return }
        let all = FillPatternLibrary.all
        let cols = 6, cell = 190, w = cols * cell, h = ((all.count + cols - 1) / cols) * cell
        let b = Bitmap(w, h)
        b.ctx.setFillColor(CGColor(gray: 1, alpha: 1)); b.ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var items: [GItem] = []
        for (i, p) in all.enumerated() {
            let x = (i % cols) * cell, y = (i / cols) * cell
            // One drafting scale for the whole sheet (2.4 pt per mm); model patterns are pre-scaled to fit ~3 repeats.
            let k = p.isModel ? Double(cell - 20) / (3.2 * (p.families.map { max($0.spacing, $0.period) }.max() ?? 100)) / 2.4 : 1
            let region = Rect2(min: Vec2(Double(x + 10), Double(y + 30)), max: Vec2(Double(x + cell - 10), Double(y + cell - 10)))
            var d = p.data; d.isModelPattern = false
            d.families = p.families.map { HatchFamily(angle: $0.angle, origin: $0.origin * k, shift: $0.shift * k, spacing: $0.spacing * k, dashes: $0.dashes.map { $0 * k }) }
            let fill = GFill(fillPattern: d, color: .black)
            items.append(GItem(elementID: nil, category: .filledRegions, layer: .fills, primitives: [.fill([.rectangle(region)], fill), .polyline(region.corners, closed: true, GStroke(weight: 1, color: RGBColor(0.6, 0.6, 0.6)))]))
        }
        let g = ViewGraphics(viewID: ElementID(1), scale: 2400, items: items, extents: Rect2(min: .zero, max: Vec2(Double(w), Double(h))), crop: nil, modelRevision: 1)
        GraphicsRenderer.draw(g, in: b.ctx, viewToDevice: .identity, pointsPerPaperMeter: 2400, options: RenderOptions())
        for (i, p) in all.enumerated() {
            let x = (i % cols) * cell, y = (i / cols) * cell
            _ = NSAttributedStringLabel.draw(p.name + (p.isModel ? "  (model)" : ""), at: CGPoint(x: Double(x + 10), y: Double(y + 10)), in: b.ctx)
        }
        let img = try #require(b.ctx.makeImage())
        let url = URL(fileURLWithPath: dir).appendingPathComponent("fill-patterns.png") as CFURL
        let dest = try #require(CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}

/// Minimal CoreText label for the preview sheet.
enum NSAttributedStringLabel {
    static func draw(_ s: String, at p: CGPoint, in ctx: CGContext) -> Bool {
        let attrs: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, 11, nil), .foregroundColor: CGColor(gray: 0.1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.saveGState()
        ctx.textPosition = p
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return true
    }
}
