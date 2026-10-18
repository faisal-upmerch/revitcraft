import CoreGraphics
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusOutput
@testable import ArcusCanvasMetal

/// W2-ANNOT: the Metal canvas draws the annotation additions — italic, underlined and opaque text, and the four-dash
/// line patterns — like GraphicsRenderer (screen, print and PDF).
@Suite("Metal ↔ CoreGraphics parity: annotations", .serialized)
@MainActor
struct AnnotationParityTests {
    func check(_ name: String, _ g: ViewGraphics, _ setup: CanvasSetup, mismatch: Double = 0.015, ink: ClosedRange<Double> = 0.9...1.1,
               meanAbs: Double = 0.015) throws {
        let cg = Harness.renderCG(g, setup, RenderOptions(), overlay: nil)
        let mt = try Harness.renderMetal(g, setup, RenderOptions(), overlay: nil)
        let c = Harness.compare(cg, mt, background: CanvasColors(options: RenderOptions()).canvas)
        let ok = c.mismatch <= mismatch && ink.contains(c.inkRatio) && c.meanAbs <= meanAbs
        print("[parity] \(name): \(c)")
        if !ok || Harness.alwaysDump { print("[parity] \(name) images: \(Harness.dump(name, cg: cg, metal: mt).path)") }
        #expect(ok, "\(name): \(c)")
    }

    @Test(arguments: [40.0, 160.0])
    func textFaces(zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: 100)
        let h = 2.5 / 1000 * 40 / zoom
        var prims: [GPrimitive] = []
        // A hatch behind, so the opaque text's mask is visible.
        prims.append(.fill([Polygon2([s.view(10, 10), s.view(290, 10), s.view(290, 190), s.view(10, 190)])], GFill(pattern: .solid, color: RGBColor(0.75, 0.8, 0.85))))
        prims.append(.text(GText(position: s.view(20, 40), height: h, string: "Italic note", italic: true)))
        prims.append(.text(GText(position: s.view(20, 80), height: h, string: "Bold italic", bold: true, italic: true)))
        prims.append(.text(GText(position: s.view(20, 120), height: h, string: "Underlined text", underline: true)))
        prims.append(.text(GText(position: s.view(160, 120), height: h, string: "Opaque", verticalAnchor: 1, opaque: true)))
        prims.append(.text(GText(position: s.view(160, 170), height: h, string: "Opaque\nand underlined", rotation: .pi / 12, underline: true, opaque: true)))
        try check("annotation_text_z\(Int(zoom))", Harness.graphics([Harness.item(1, .annotation, prims)]), s)
    }

    @Test(arguments: [40.0, 120.0])
    func newDashPatterns(zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: 100)
        var prims: [GPrimitive] = []
        for (i, k) in [LinePatternKind.longDash, .doubleDash, .dashDotDot, .demolished].enumerated() {
            let y = 20 + Double(i) * 40
            for (j, w) in [1, 3, 6].enumerated() {
                let x = 10 + Double(j) * 96
                prims.append(.polyline([s.view(x, y), s.view(x + 60, y), s.view(x + 80, y + 14)], closed: false, GStroke(weight: w, pattern: k)))
            }
        }
        try check("annotation_dashes_z\(Int(zoom))", Harness.graphics([Harness.item(1, .model, prims)]), s, mismatch: 0.006, ink: 0.92...1.08, meanAbs: 0.01)
    }
}
