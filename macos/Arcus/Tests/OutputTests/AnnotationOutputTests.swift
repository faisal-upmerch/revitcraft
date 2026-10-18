import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

// W2-ANNOT: line patterns, text faces, underline and opaque text in the CoreGraphics renderer (screen and PDF), and
// annotations in exported PDFs.

/// 20 px per paper millimetre.
private let ppm = 20_000.0
private func viewT(_ scale: Int) -> CGAffineTransform { CGAffineTransform(scaleX: CGFloat(ppm / Double(scale)), y: CGFloat(ppm / Double(scale))) }

/// Lengths (px) of the inked runs along row y between x0 and x1.
private func runs(_ b: Bitmap, y: Int, _ x0: Int, _ x1: Int) -> [Int] {
    var out: [Int] = []
    var n = 0
    for x in x0..<x1 {
        if b.ink(x, y) > 0.5 { n += 1 } else if n > 0 { out.append(n); n = 0 }
    }
    if n > 0 { out.append(n) }
    return out
}

final class DashCounter { var dashes = 0 }

@Suite("Annotation output (W2-ANNOT)")
struct AnnotationOutputTests {
    /// A 58 mm (paper) line 1 mm above the bottom of the bitmap, in a view at `scale`.
    func line(_ pattern: LinePatternKind, scale: Int) -> ViewGraphics {
        let s = Double(scale)
        return graphics([GItem(elementID: nil, category: .detailLines, layer: .annotation,
                               primitives: [.polyline([Vec2(0.001 * s, 0.001 * s), Vec2(0.059 * s, 0.001 * s)], closed: false, GStroke(weight: 1, pattern: pattern))])],
                        scale: scale)
    }

    @Test(arguments: [LinePatternKind.longDash, .doubleDash, .dashDotDot, .demolished])
    func newPatternsDrawTheirDashesAtPaperSize(_ pattern: LinePatternKind) {
        // The same paper length at 1:100 and 1:50: the dashes are identical on paper.
        var measured: [[Int]] = []
        for scale in [100, 50] {
            let b = Bitmap(1200, 40)
            GraphicsRenderer.draw(line(pattern, scale: scale), in: b.ctx, viewToDevice: viewT(scale), pointsPerPaperMeter: ppm, options: RenderOptions())
            measured.append(runs(b, y: 20, 0, 1200))
        }
        #expect(measured[0].count >= 3, "\(pattern): \(measured[0])")
        #expect(measured[0].prefix(3) == measured[1].prefix(3), "dash lengths are paper sizes: \(measured)")
        let first = Double(measured[0][0]) / 20   // mm
        #expect(abs(first - pattern.dashPattern[0]) < 0.6, "\(pattern): first dash \(first) mm")
        if pattern == .dashDotDot {
            // Dash, dot, dot, dash…
            #expect(measured[0][1] < 10 && measured[0][2] < 10 && measured[0][3] > 100, "\(measured[0])")
        }
    }

    @Test func italicAndBoldItalicFaces() {
        var fonts = FontCache()
        let italic = CTFontCopyPostScriptName(fonts.font(bold: false, italic: true, capHeight: 10)) as String
        let boldItalic = CTFontCopyPostScriptName(fonts.font(bold: true, italic: true, capHeight: 10)) as String
        let regular = CTFontCopyPostScriptName(fonts.font(bold: false, capHeight: 10)) as String
        #expect(italic.contains("Italic") && boldItalic.contains("Italic") && !regular.contains("Italic"))
        #expect(italic != boldItalic)
    }

    func text(_ t: GText, over line: Bool = false) -> Bitmap {
        let b = Bitmap(400, 200)
        var items: [GItem] = []
        if line { items.append(GItem(elementID: nil, category: .detailLines, layer: .annotation, primitives: [.polyline([Vec2(0, 0.0245), Vec2(0.1, 0.0245)], closed: false, GStroke(weight: 8))])) }
        items.append(GItem(elementID: nil, category: .textNotes, layer: .annotation, primitives: [.text(t)]))
        GraphicsRenderer.draw(graphics(items, scale: 1), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: 4000, y: 4000), pointsPerPaperMeter: 4000,
                              options: RenderOptions())
        return b
    }

    @Test func underlineDrawsBelowTheBaseline() {
        let t = GText(position: Vec2(0.01, 0.025), height: 0.005, string: "NOTE")
        var u = t
        u.underline = true
        let plain = text(t), underlined = text(u)
        // Cap height 20 px, baseline at y = 100: the underline sits about 4 px below it, under the whole word.
        let below = (40..<100).filter { underlined.ink($0, 95) > 0.3 }.count
        #expect(below > 30, "a continuous underline: \(below) px")
        #expect((40..<100).filter { plain.ink($0, 95) > 0.3 }.isEmpty)
    }

    @Test func opaqueTextMasksWhatIsBehindIt() {
        var t = GText(position: Vec2(0.01, 0.03), height: 0.005, string: "MMMM", verticalAnchor: 1)
        let transparent = text(t, over: true)
        t.opaque = true
        let opaque = text(t, over: true)
        // The line runs through the text block at y = 98 px; between letters it shows only when the text is transparent.
        let seenT = (44..<110).filter { transparent.ink($0, 98) > 0.5 }.count
        let seenO = (44..<110).filter { opaque.ink($0, 98) > 0.5 }.count
        #expect(seenT > seenO + 10, "transparent \(seenT) px of line, opaque \(seenO) px")
        // Beyond the block the line is untouched.
        #expect(opaque.ink(300, 98) > 0.5)
    }

    @Test func exportedPDFsCarryAnnotationTextAndDashes() async throws {
        let f = Fixture.shared
        let tx = TransactionContext(model: f.model, name: "Annotations")
        let wallType = f.model[f.walls[0]]!.typeID!
        tx.update(wallType) { $0.typeData?.params[ParameterID("type.keynote")] = .text("A2.01") }
        var key = TagData(taggedID: f.walls[0], head: Vec2(5, 2), hasLeader: true)
        key.kind = .keynoteElement
        key.keynoteDisplay = .keyAndText
        tx.create(.tags, data: .tag(key), ownerViewID: f.plan)
        var note = TextNoteData(position: Vec2(2, 6), text: "UNDERLINED NOTE")
        note.underline = true
        note.leaders = [Vec2(1, 5)]
        tx.create(.textNotes, data: .textNote(note), typeID: f.ids.systemTypes["Text 2.5mm Arial"], ownerViewID: f.plan)
        let property = f.model.lineStyle(named: "Property Line")!.id
        tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(-2, -2), Vec2(12, -2))), styleID: property)), ownerViewID: f.plan)
        let m = try tx.commit().model
        let r = try await PDFExporter.export(m, job: PDFExportJob(items: [.view(f.plan)], outputDirectory: Fixture.tempDir()))
        let s = PDFDocument(url: r.files[0])?.page(at: 0)?.string ?? ""
        #expect(s.contains("UNDERLINED NOTE"))
        #expect(s.contains("A2.01 Brick outer leaf"))
        // The property line is dashed in the PDF (a `d` operator with a non-empty array).
        let doc = CGPDFDocument(r.files[0] as CFURL)!
        let counter = DashCounter()
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "d") { scanner, info in
            var array: CGPDFArrayRef?
            var phase: CGPDFReal = 0
            _ = CGPDFScannerPopNumber(scanner, &phase)
            if CGPDFScannerPopArray(scanner, &array), let array, CGPDFArrayGetCount(array) == 6 {
                Unmanaged<DashCounter>.fromOpaque(info!).takeUnretainedValue().dashes += 1
            }
        }
        let stream = CGPDFContentStreamCreateWithPage(doc.page(at: 1)!)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(counter).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        #expect(counter.dashes >= 1, "a six-entry dash-dot-dot pattern")
    }
}
