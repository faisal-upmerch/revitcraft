import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusOutput

/// F1: Model Text's CoreText glyph outlines (RevitCraft `model_text.rs` `glyph_outlines`).
@Suite("F1 glyph outliner")
struct F1GlyphOutlinerTests {
    @Test func capitalsAreOneCapHeightTallAndCountersAreHoles() {
        let g = GlyphOutliner.outline("HO", fontName: "Arial")
        #expect(!g.contours.isEmpty)
        let ys = g.contours.flatMap { $0 }.map(\.y)
        #expect(abs((ys.max() ?? 0) - 1) < 0.08, "H reaches the capital height (O overshoots it slightly)")
        #expect(abs(ys.min() ?? 1) < 0.08, "glyphs sit on the baseline")
        let shapes = ModelTextGeometry.shapes(g.contours)
        #expect(shapes.count == 2 && shapes.map(\.holes.count).reduce(0, +) == 1)
        #expect(g.advance > 1, "two capitals advance more than one capital height")
    }

    @Test func unknownFontsFallBack() {
        let g = GlyphOutliner.outline("A", fontName: "No Such Font Name 12345")
        #expect(!g.contours.isEmpty)
    }
}
