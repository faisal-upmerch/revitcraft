import CoreGraphics
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusOutput
@testable import ArcusCanvasMetal

/// Pixel parity between the Metal renderer and GraphicsRenderer (CoreGraphics) on representative display lists.
///
/// Metrics (see `Comparison`): `mismatch` = share of pixels whose 3×3-blurred colours differ by more than 15 %
/// (structural differences, tolerant of anti-aliasing), `inkRatio` = total ink Metal ÷ CoreGraphics (line widths,
/// pattern density, text weight), `meanAbs` = mean absolute channel difference. On failure (or with
/// ARCUS_PARITY_DUMP=1) cg.png / metal.png / diff.png are written to $TMPDIR/ArcusCanvasMetalParity/<case>/.
@Suite("Metal ↔ CoreGraphics parity", .serialized)
@MainActor
struct ParityTests {
    struct Tolerance {
        var mismatch = 0.004
        var ink: ClosedRange<Double> = 0.93...1.07
        var meanAbs = 0.01
    }

    @discardableResult
    func check(_ name: String, _ g: ViewGraphics, _ setup: CanvasSetup, _ options: RenderOptions = RenderOptions(),
               _ tol: Tolerance = Tolerance(), overlay: (ViewGraphics, RenderOptions)? = nil) throws -> Comparison {
        let cg = Harness.renderCG(g, setup, options, overlay: overlay)
        let mt = try Harness.renderMetal(g, setup, options, overlay: overlay)
        let bg: RGBColor? = options.background == nil ? nil : CanvasColors(options: options).canvas
        let c = Harness.compare(cg, mt, background: bg)
        let ok = c.mismatch <= tol.mismatch && tol.ink.contains(c.inkRatio) && c.meanAbs <= tol.meanAbs
        print("[parity] \(name): \(c)")
        if !ok || Harness.alwaysDump {
            let dir = Harness.dump(name, cg: cg, metal: mt)
            print("[parity] \(name) images: \(dir.path)")
        }
        #expect(ok, "\(name): \(c)")
        return c
    }

    // MARK: Lines

    @Test(arguments: [(50, 60.0), (100, 40.0), (200, 15.0), (100, 400.0)])
    func lineWeights(viewScale: Int, zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: viewScale)
        var prims: [GPrimitive] = []
        for w in 1...16 {
            let y = 10 + Double(w - 1) * 11.5
            prims.append(.polyline([s.view(12, y), s.view(150, y + 3)], closed: false, GStroke(weight: w)))
        }
        // Corners (round joins) and a closed polyline.
        prims.append(.polyline([s.view(170, 20), s.view(200, 170), s.view(230, 30), s.view(260, 160)], closed: false, GStroke(weight: 5)))
        prims.append(.polyline([s.view(175, 185), s.view(285, 185), s.view(285, 120)], closed: true, GStroke(weight: 3, color: RGBColor(0.8, 0.1, 0.1))))
        try check("lines_1to\(viewScale)_z\(Int(zoom))", Harness.graphics(scale: viewScale, [Harness.item(1, .model, prims)]), s)
    }

    @Test func thinLinesAndMinimumWidth() throws {
        let s = CanvasSetup.model(zoom: 30, viewScale: 100)
        var prims: [GPrimitive] = []
        for w in [1, 4, 9, 14] {
            let y = 20 + Double(w) * 10
            prims.append(.polyline([s.view(20, y), s.view(280, y + 12)], closed: false, GStroke(weight: w)))
        }
        let g = Harness.graphics([Harness.item(1, .model, prims)])
        var thin = RenderOptions()
        thin.thinLines = true
        try check("thin_lines", g, s, thin)
        var minW = RenderOptions()
        minW.minimumDevicePixel = 1
        let far = CanvasSetup.model(zoom: 2, viewScale: 100, center: s.view(150, 100))
        try check("minimum_device_pixel", g, far, minW, Tolerance(mismatch: 0.004, ink: 0.9...1.1))
    }

    @Test(arguments: [40.0, 120.0])
    func dashPatterns(zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: 100)
        var prims: [GPrimitive] = []
        for (i, k) in LinePatternKind.allCases.enumerated() {
            let y = 14 + Double(i) * 26
            for (j, w) in [1, 3, 6].enumerated() {
                let x = 10 + Double(j) * 96
                prims.append(.polyline([s.view(x, y), s.view(x + 60, y), s.view(x + 80, y + 14)], closed: false, GStroke(weight: w, pattern: k)))
            }
        }
        try check("dashes_z\(Int(zoom))", Harness.graphics([Harness.item(1, .model, prims)]), s, RenderOptions(),
                  Tolerance(mismatch: 0.006, ink: 0.92...1.08))
    }

    @Test func densePatternDrawsSolid() throws {
        let s = CanvasSetup.model(zoom: 0.8, viewScale: 100)
        let prims: [GPrimitive] = LinePatternKind.allCases.enumerated().map { i, k in
            .polyline([s.view(20, 20 + Double(i) * 25), s.view(280, 30 + Double(i) * 25)], closed: false, GStroke(weight: 4, pattern: k))
        }
        try check("dashes_dense", Harness.graphics([Harness.item(1, .model, prims)]), s)
    }

    @Test(arguments: [25.0, 300.0])
    func arcs(zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: 100)
        let u = 1 / zoom   // one point in view units
        let prims: [GPrimitive] = [
            .arc(Arc2(center: s.view(60, 60), radius: 40 * u, startAngle: 0, sweep: .pi / 2), GStroke(weight: 5)),
            .arc(Arc2(center: s.view(150, 60), radius: 35 * u, startAngle: 0.3, sweep: -2.4), GStroke(weight: 3, color: RGBColor(0.1, 0.3, 0.8))),
            .arc(Arc2(center: s.view(240, 60), radius: 30 * u, startAngle: 0, sweep: 2 * .pi), GStroke(weight: 2)),
            .arc(Arc2(center: s.view(60, 150), radius: 45 * u, startAngle: 0.2, sweep: 0.17), GStroke(weight: 8)),
            .arc(Arc2(center: s.view(150, 150), radius: 38 * u, startAngle: -1, sweep: 4.5), GStroke(weight: 3, pattern: .dash)),
            .arc(Arc2(center: s.view(240, 150), radius: 3 * u, startAngle: 0, sweep: 2 * .pi), GStroke(weight: 1)),
            .arc(Arc2(center: s.view(240, 150), radius: 25 * u, startAngle: 1, sweep: 3), GStroke(weight: 12)),
        ]
        try check("arcs_z\(Int(zoom))", Harness.graphics([Harness.item(1, .model, prims)]), s)
    }

    // MARK: Fills

    nonisolated static let fillCases: [(FillPatternKind, Bool)] = FillPatternKind.allCases.flatMap { [($0, false), ($0, true)] }

    @Test(arguments: fillCases)
    func fillPattern(kind: FillPatternKind, model: Bool) throws {
        let s = CanvasSetup.model(zoom: 60, viewScale: 50)
        let rect = Polygon2([s.view(10, 10), s.view(290, 10), s.view(290, 190), s.view(10, 190)])
        let tri = Polygon2([s.view(160, 30), s.view(280, 100), s.view(170, 180)])
        let fill = GFill(pattern: kind, color: RGBColor(0.2, 0.2, 0.25), background: nil, isModelPattern: model)
        let bgFill = GFill(pattern: kind, color: RGBColor(0.1, 0.3, 0.1), background: RGBColor(0.95, 0.92, 0.8), isModelPattern: model)
        let g = Harness.graphics(scale: 50, [Harness.item(1, .fills, [.fill([rect], fill)]), Harness.item(2, .fills, [.fill([tri], bgFill)])])
        let dense = kind == .sand || kind == .concrete || kind == .earth || kind == .insulation || kind == .wood
        try check("fill_\(kind.rawValue.replacingOccurrences(of: " ", with: ""))_\(model ? "model" : "drafting")", g, s, RenderOptions(),
                  Tolerance(mismatch: dense ? 0.03 : 0.01, ink: dense ? 0.85...1.15 : 0.9...1.1, meanAbs: 0.02))
    }

    @Test func patternDensityFallsBackToTint() throws {
        let s = CanvasSetup.model(zoom: 1.5, viewScale: 100)
        let rect = Polygon2([s.view(10, 10), s.view(290, 10), s.view(290, 190), s.view(10, 190)])
        let g = Harness.graphics([Harness.item(1, .fills, [.fill([rect], GFill(pattern: .crosshatch, color: .black))])])
        try check("fill_tint", g, s)
    }

    @Test func fillsWithHoles() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let outer = Polygon2([s.view(10, 10), s.view(200, 10), s.view(200, 190), s.view(10, 190)])
        let hole1 = Polygon2([s.view(30, 30), s.view(100, 30), s.view(100, 100), s.view(30, 100)])
        let island = Polygon2([s.view(50, 50), s.view(80, 50), s.view(65, 80)])
        let hole2 = Polygon2([s.view(120, 120), s.view(180, 130), s.view(150, 175)])
        // Two adjacent pieces of one fill (shared edge must not show a seam).
        let left = Polygon2([s.view(215, 20), s.view(250, 20), s.view(250, 180), s.view(215, 180)])
        let right = Polygon2([s.view(250, 20), s.view(290, 20), s.view(290, 180), s.view(250, 180)])
        let concave = Polygon2([s.view(215, 190), s.view(290, 190), s.view(290, 185), s.view(250, 186), s.view(215, 186)])
        let g = Harness.graphics([
            Harness.item(1, .fills, [.fill([outer, hole1, island, hole2], GFill(pattern: .solid, color: RGBColor(0.3, 0.4, 0.6)))]),
            Harness.item(2, .fills, [.fill([left, right], GFill(pattern: .solid, color: RGBColor(0.6, 0.3, 0.2)))]),
            Harness.item(3, .fills, [.fill([concave], GFill(pattern: .diagonalUp, color: .black, background: RGBColor(0.9, 0.9, 0.7)))]),
        ])
        try check("fill_holes", g, s)
    }

    @Test func transparencyAndHalftone() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        var lines: [GPrimitive] = []
        for i in 0..<12 { lines.append(.polyline([s.view(10, 10 + Double(i) * 16), s.view(290, 20 + Double(i) * 14)], closed: false, GStroke(weight: 4))) }
        let rect = Polygon2([s.view(40, 30), s.view(260, 30), s.view(260, 170), s.view(40, 170)])
        let g = Harness.graphics([
            Harness.item(1, .model, lines),
            Harness.item(2, .fills, [.fill([rect], GFill(pattern: .solid, color: RGBColor(0.1, 0.5, 0.9), transparency: 0.5))]),
            Harness.item(3, .fills, [.fill([Polygon2([s.view(60, 60), s.view(140, 60), s.view(140, 140), s.view(60, 140)])],
                                           GFill(pattern: .diagonalCrosshatch, color: RGBColor(0.8, 0.1, 0.1), background: .white, transparency: 0.3, halftone: true))]),
            Harness.item(4, .model, [.polyline([s.view(150, 50), s.view(280, 150)], closed: false, GStroke(weight: 8, color: RGBColor(0.9, 0.2, 0.1), halftone: true)),
                                     .polyline([s.view(150, 150), s.view(280, 50)], closed: false, GStroke(weight: 6, halftone: true))]),
        ])
        try check("transparency_halftone", g, s)
        var o = RenderOptions()
        o.halftoneAmount = 0.3
        try check("transparency_halftone_03", g, s, o)
    }

    @Test func masking() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        var lines: [GPrimitive] = []
        for i in 0..<10 { lines.append(.polyline([s.view(10 + Double(i) * 28, 10), s.view(20 + Double(i) * 28, 190)], closed: false, GStroke(weight: 5))) }
        let g = Harness.graphics([
            Harness.item(1, .model, lines),
            Harness.item(2, .masking, [.fill([Polygon2([s.view(40, 40), s.view(160, 40), s.view(160, 120), s.view(40, 120)])], GFill(pattern: .solid, color: .white))]),
            Harness.item(3, .annotation, [.fill([Polygon2([s.view(180, 100), s.view(270, 100), s.view(225, 180)])], .mask),
                                          .text(GText(position: s.view(190, 120), height: 0.0025, string: "MASK"))]),
        ])
        try check("masking", g, s, RenderOptions(), Tolerance(mismatch: 0.006))
        var dark = RenderOptions()
        dark.darkCanvas = true
        dark.background = RGBColor(0.16, 0.16, 0.17)
        try check("masking_dark", g, s, dark, Tolerance(mismatch: 0.006))
    }

    // MARK: Text

    @Test(arguments: [40.0, 160.0])
    func text(zoom: Double) throws {
        let s = CanvasSetup.model(zoom: zoom, viewScale: 100)
        let h = 2.5 / 1000 * 40 / zoom   // same on-screen size for both zooms
        var prims: [GPrimitive] = []
        let aligns: [TextAlignment] = [.left, .center, .right]
        for (i, a) in aligns.enumerated() {
            for (j, anchor) in [0.0, 0.5, 1.0].enumerated() {
                let p = s.view(50 + Double(i) * 100, 30 + Double(j) * 28)
                prims.append(.polyline([p - Vec2(3 / zoom, 0), p + Vec2(3 / zoom, 0)], closed: false, GStroke(weight: 1, color: RGBColor(1, 0, 0))))
                prims.append(.text(GText(position: p, height: h, string: "Room 101", alignment: a, verticalAnchor: anchor, bold: j == 1)))
            }
        }
        prims.append(.text(GText(position: s.view(40, 185), height: h, string: "Rotated 30°", rotation: .pi / 6)))
        prims.append(.text(GText(position: s.view(20, 110), height: h * 0.8, string: "VERTICAL", rotation: .pi / 2)))
        prims.append(.text(GText(position: s.view(150, 170), height: h * 0.9, string: "Line one\nLine two\nThree", alignment: .center, verticalAnchor: 0.5,
                                 color: RGBColor(0.1, 0.3, 0.7))))
        prims.append(.text(GText(position: s.view(210, 180), height: h * 0.7, string: "Wrapped notes wrap inside their width box",
                                 verticalAnchor: 1, wrapWidth: 70 / s.ppm)))
        try check("text_z\(Int(zoom))", Harness.graphics([Harness.item(1, .annotation, prims)]), s, RenderOptions(),
                  Tolerance(mismatch: 0.015, ink: 0.9...1.1, meanAbs: 0.015))
    }

    // MARK: Options

    @Test func darkCanvas() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let colors: [RGBColor] = [.black, RGBColor(0.4, 0.4, 0.4), RGBColor(0.8, 0.1, 0.1), RGBColor(0.1, 0.2, 0.6), RGBColor(0.2, 0.7, 0.3), .white]
        var prims: [GPrimitive] = []
        for (i, c) in colors.enumerated() {
            prims.append(.polyline([s.view(10, 15 + Double(i) * 12), s.view(140, 15 + Double(i) * 12)], closed: false, GStroke(weight: 6, color: c)))
        }
        prims.append(.fill([Polygon2([s.view(160, 10), s.view(290, 10), s.view(290, 90), s.view(160, 90)])],
                           GFill(pattern: .diagonalUp, color: RGBColor(0.3, 0.3, 0.3), background: .white)))
        prims.append(.fill([Polygon2([s.view(160, 100), s.view(220, 100), s.view(220, 190), s.view(160, 190)])], GFill(pattern: .solid, color: RGBColor(0.28, 0.28, 0.28))))
        prims.append(.text(GText(position: s.view(20, 150), height: 0.004, string: "Dark canvas", color: .black)))
        let g = Harness.graphics([Harness.item(1, .model, prims),
                                  Harness.item(2, .masking, [.fill([Polygon2([s.view(240, 120), s.view(285, 120), s.view(285, 180), s.view(240, 180)])], .mask)])])
        var o = RenderOptions()
        o.darkCanvas = true
        o.background = RGBColor(0.12, 0.12, 0.13)
        try check("dark_canvas", g, s, o, Tolerance(mismatch: 0.008))
        o.background = .white   // light background requested → default dark canvas colour
        try check("dark_canvas_default", g, s, o, Tolerance(mismatch: 0.008))
    }

    @Test func highlight() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([
            Harness.item(10, .fills, [.fill([Polygon2([s.view(20, 20), s.view(140, 20), s.view(140, 90), s.view(20, 90)])], GFill(pattern: .solid, color: RGBColor(0.3, 0.3, 0.3)))]),
            Harness.item(11, .cut, [.polyline([s.view(20, 20), s.view(140, 20), s.view(140, 90), s.view(20, 90)], closed: true, GStroke(weight: 5))]),
            Harness.item(12, .model, [.polyline([s.view(160, 20), s.view(280, 90)], closed: false, GStroke(weight: 4)),
                                      .arc(Arc2(center: s.view(220, 140), radius: 1, startAngle: 0, sweep: 3), GStroke(weight: 3))]),
            Harness.item(13, .annotation, [.text(GText(position: s.view(30, 140), height: 0.004, string: "Tagged"))]),
            Harness.item(14, .model, [.polyline([s.view(20, 180), s.view(280, 180)], closed: false, GStroke(weight: 3))]),
        ])
        var o = RenderOptions()
        o.highlight = [ElementID(10): RGBColor(0.1, 0.45, 0.95), ElementID(11): RGBColor(0.1, 0.45, 0.95),
                       ElementID(12): RGBColor(0.95, 0.55, 0.1, 0.8), ElementID(13): RGBColor(0.1, 0.45, 0.95)]
        o.hiddenElements = [ElementID(14)]
        try check("highlight_hidden", g, s, o, Tolerance(mismatch: 0.008))
    }

    /// I1: RevitCraft's selection fill (a translucent blue laid over fills) and heavier outlines match on both paths.
    @Test func highlightFillTint() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([
            Harness.item(20, .fills, [.fill([Polygon2([s.view(20, 20), s.view(140, 20), s.view(140, 90), s.view(20, 90)])], GFill(pattern: .solid, color: RGBColor(0.3, 0.3, 0.3)))]),
            Harness.item(21, .fills, [.fill([Polygon2([s.view(160, 20), s.view(280, 20), s.view(280, 90), s.view(160, 90)])], GFill(pattern: .solid, color: .white))]),
            Harness.item(22, .cut, [.polyline([s.view(20, 120), s.view(280, 120)], closed: false, GStroke(weight: 5))]),
            Harness.item(23, .model, [.polyline([s.view(20, 160), s.view(280, 160)], closed: false, GStroke(weight: 1))]),
        ])
        var o = RenderOptions()
        let blue = RGBColor(24 / 255, 84 / 255, 216 / 255)
        let tint = RGBColor(19 / 255, 57 / 255, 159 / 255, 140 / 255)
        o.highlight = [ElementID(20): blue, ElementID(21): blue, ElementID(22): blue, ElementID(23): blue]
        o.highlightFill = [ElementID(20): tint, ElementID(21): tint]
        try check("highlight_fill_tint", g, s, o, Tolerance(mismatch: 0.008))
    }

    @Test func overlayLayerVisibility() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([
            Harness.item(1, .model, [.polyline([s.view(20, 20), s.view(280, 180)], closed: false, GStroke(weight: 4))]),
            Harness.item(nil, .overlay, [.polyline([s.view(10, 10), s.view(290, 10), s.view(290, 190), s.view(10, 190)], closed: true, GStroke(weight: 2))]),
        ])
        try check("overlay_layer_shown", g, s)
        var o = RenderOptions()
        o.showOverlays = false
        try check("overlay_layer_hidden", g, s, o)
    }

    /// The overlay pass (tool previews) draws on top without painting a background — also in dark mode.
    @Test func overlayDoesNotClear() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([
            Harness.item(1, .fills, [.fill([Polygon2([s.view(20, 20), s.view(200, 20), s.view(200, 150), s.view(20, 150)])], GFill(pattern: .solid, color: RGBColor(0.5, 0.5, 0.5)))]),
            Harness.item(2, .model, [.polyline([s.view(10, 170), s.view(290, 170)], closed: false, GStroke(weight: 6))]),
        ])
        let preview = Harness.graphics([Harness.item(nil, .overlay, [
            .polyline([s.view(100, 40), s.view(280, 120)], closed: false, GStroke(weight: 3, color: RGBColor(0.1, 0.45, 0.95))),
            .arc(Arc2(center: s.view(150, 100), radius: 1, startAngle: 0, sweep: 2), GStroke(weight: 2, pattern: .dash)),
        ])])
        var main = RenderOptions()
        main.darkCanvas = true
        main.background = RGBColor(0.12, 0.12, 0.13)
        var po = RenderOptions()
        po.background = nil
        po.darkCanvas = true
        try check("overlay_pass_dark", g, s, main, Tolerance(mismatch: 0.006), overlay: (preview, po))

        // Separate overlay-only pass loading the previous frame: everything outside the preview strokes is untouched.
        let ctx = try #require(MetalCanvasContext.shared)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        r.options = main
        r.setScene(try #require(MetalCanvasScene.build(g, context: ctx)))
        let tex = try #require(r.makeOffscreenTarget(width: s.pixelWidth, height: s.pixelHeight))
        _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale, passes: .scene)))
        let before = MetalCanvasRenderer.readPixels(tex)
        r.overlayOptions = po
        r.setOverlay(preview)
        _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale,
                                                       passes: .overlay, load: .load)))
        let after = MetalCanvasRenderer.readPixels(tex)
        let w = s.pixelWidth
        // Probe points away from the preview strokes: canvas, fill and the black line must be unchanged.
        for (x, y) in [(20.0, 100.0), (60.0, 60.0), (150.0, 30.0), (40.0, 170.0), (250.0, 180.0)] {
            let px = Int(x * s.scale), py = s.pixelHeight - 1 - Int(y * s.scale)
            let i = (py * w + px) * 4
            #expect(Array(before[i..<i + 4]) == Array(after[i..<i + 4]), "pixel (\(x), \(y)) changed by the overlay pass")
        }
        // …and the overlay did draw.
        let changed = zip(before, after).filter { $0 != $1 }.count
        #expect(changed > 1000)
    }

    /// CoreGraphics' default bitmap context snaps glyph origins to whole device pixels; Metal keeps exact fractional
    /// positions (like CG with sub-pixel positioning). Reported for the record with a looser tolerance.
    @Test func textAgainstPixelSnappedCoreGraphics() throws {
        Harness.subpixelTextDefault = false
        defer { Harness.subpixelTextDefault = true }
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        var prims: [GPrimitive] = []
        for i in 0..<6 {
            prims.append(.text(GText(position: s.view(15, 20 + Double(i) * 30), height: 0.0025 + Double(i) * 0.0006, string: "Room 1A0\(i) Office Library")))
        }
        try check("text_cg_pixel_snapped", Harness.graphics([Harness.item(1, .annotation, prims)]), s, RenderOptions(),
                  Tolerance(mismatch: 0.05, ink: 0.93...1.07, meanAbs: 0.02))
    }

    // MARK: Transforms & precision

    /// Geometry 100 km from the view origin at ~1 µm per point: hi/lo positions keep sub-pixel accuracy.
    @Test func deepZoomFarFromOrigin() throws {
        let far = Vec2(100_000.25, -80_000.75)
        let s = CanvasSetup.model(zoom: 200_000, viewScale: 1, center: far)
        let u = 1 / 200_000.0
        let prims: [GPrimitive] = [
            .polyline([far + Vec2(-100 * u, -60 * u), far + Vec2(100 * u, -60 * u), far + Vec2(100 * u, 60 * u), far + Vec2(-100 * u, 60 * u)], closed: true, GStroke(weight: 1)),
            .polyline([far + Vec2(-130 * u, 0), far + Vec2(130 * u, 3 * u)], closed: false, GStroke(weight: 1, pattern: .dash)),
            .arc(Arc2(center: far, radius: 40 * u, startAngle: 0, sweep: 5), GStroke(weight: 1)),
            .fill([Polygon2([far + Vec2(-90 * u, -50 * u), far + Vec2(-20 * u, -50 * u), far + Vec2(-55 * u, -10 * u)])], GFill(pattern: .solid, color: RGBColor(0.2, 0.4, 0.8))),
        ]
        let g = Harness.graphics(scale: 1, [Harness.item(1, .model, prims), Harness.item(2, .model, [.polyline([Vec2(0, 0), Vec2(1, 1)], closed: false, .thin)])])
        var o = RenderOptions()
        o.minimumDevicePixel = 1
        try check("deep_zoom_far", g, s, o)
    }

    @Test(arguments: [(30.0, false), (90.0, false), (0.0, true), (-20.0, true)])
    func rotatedAndMirroredTransforms(degrees: Double, mirrored: Bool) throws {
        let zoom = 40.0
        let a = degrees * .pi / 180
        var m = CGAffineTransform(a: zoom * cos(a), b: zoom * sin(a), c: -zoom * sin(a), d: zoom * cos(a), tx: 0, ty: 0)
        if mirrored { m = CGAffineTransform(scaleX: 1, y: -1).concatenating(m) }
        m.tx = 150; m.ty = 100
        let s = CanvasSetup(viewToDevice: m, ppm: zoom * 100)
        let prims: [GPrimitive] = [
            .polyline([Vec2(-3, -2), Vec2(3, -2), Vec2(3, 2), Vec2(-3, 2)], closed: true, GStroke(weight: 4)),
            .polyline([Vec2(-3.4, 0), Vec2(3.4, 0.4)], closed: false, GStroke(weight: 2, pattern: .center)),
            .arc(Arc2(center: Vec2(1.5, 0.8), radius: 0.8, startAngle: 0.3, sweep: 2.2), GStroke(weight: 3)),
            .fill([Polygon2([Vec2(-2.8, -1.8), Vec2(-0.5, -1.8), Vec2(-0.5, 1.8), Vec2(-2.8, 1.8)])], GFill(pattern: .brick, color: RGBColor(0.3, 0.2, 0.2))),
            .text(GText(position: Vec2(0.2, -1.2), height: 0.003, string: "Rotated view", rotation: 0.2)),
        ]
        try check("transform_\(Int(degrees))\(mirrored ? "_mirrored" : "")", Harness.graphics([Harness.item(1, .model, prims)]), s, RenderOptions(),
                  Tolerance(mismatch: 0.01, ink: 0.93...1.07, meanAbs: 0.015))
    }

    // MARK: Real display list

    @Test func courtyardGroundFloor() throws {
        let m = CourtyardHouse.make()
        let plan = try #require(m.views.first { $0.name == "Ground Floor" && $0.view?.kind == .floorPlan })
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        var r = Rect2.empty
        for i in g.items where i.layer != .overlay { r.include(i.bounds) }
        let w = 900.0, h = 600.0
        let zoom = min(w / r.width, h / r.height) * 0.92
        let s = CanvasSetup.model(zoom: zoom, viewScale: g.scale, center: r.center, widthPt: w, heightPt: h)
        try check("courtyard_plan_fit", g, s, RenderOptions(), Tolerance(mismatch: 0.02, ink: 0.9...1.1, meanAbs: 0.02))
        // Zoomed into the corridor of the lower wing (doors, dimensions, tags, dashed grid lines).
        let detail = CanvasSetup.model(zoom: zoom * 6, viewScale: g.scale, center: s.view(450, 160), widthPt: w, heightPt: h)
        try check("courtyard_plan_detail", g, detail, RenderOptions(), Tolerance(mismatch: 0.02, ink: 0.9...1.1, meanAbs: 0.02))
        var dark = RenderOptions()
        dark.darkCanvas = true
        dark.background = RGBColor(0.12, 0.12, 0.13)
        try check("courtyard_plan_dark", g, detail, dark, Tolerance(mismatch: 0.02, ink: 0.9...1.1, meanAbs: 0.02))

        // A sheet (paper meters, viewports carrying their own line scale, title block text).
        let sheet = try #require(m.sheets.first)
        let sg = SheetGraphicsBuilder(model: m, sheet: sheet).build()
        let e = sg.extents
        let sz = min(w / e.width, h / e.height) * 0.95
        let ss = CanvasSetup.model(zoom: sz, viewScale: sg.scale, center: e.center, widthPt: w, heightPt: h)
        try check("courtyard_sheet", sg, ss, RenderOptions(), Tolerance(mismatch: 0.02, ink: 0.9...1.1, meanAbs: 0.02))
    }
}

extension CanvasSetup {
    /// View-space point drawn at device point (x, y).
    func view(_ x: Double, _ y: Double) -> Vec2 {
        let p = CGPoint(x: x, y: y).applying(viewToDevice.inverted())
        return Vec2(Double(p.x), Double(p.y))
    }
}
