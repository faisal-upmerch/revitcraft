import CoreGraphics
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput

/// 20 px per paper millimeter → a 1:100 view maps 1 model meter to 200 px.
private let ppm = 20_000.0
private func viewT(_ scale: Int) -> CGAffineTransform { CGAffineTransform(scaleX: CGFloat(ppm / Double(scale)), y: CGFloat(ppm / Double(scale))) }

private func hLine(_ y: Double, _ st: GStroke, id: UInt64? = nil, layer: GItem.Layer = .model) -> GItem {
    GItem(elementID: id.map(ElementID.init), category: .walls, layer: layer, primitives: [.polyline([Vec2(0.05, y), Vec2(0.95, y)], closed: false, st)])
}

/// Number of pixels with ink ≥ threshold in a vertical run through column x.
private func thickness(_ b: Bitmap, x: Int, threshold: Double = 0.3) -> Int {
    (0..<b.height).filter { b.ink(x, $0) >= threshold }.count
}

@Suite("Renderer")
struct RendererTests {
    @Test func heavyCutLineIsThickerThanThinProjectionLineAt1to100() {
        let cut = Bitmap(200, 100), proj = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 5))]), in: cut.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 1))]), in: proj.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        let heavy = thickness(cut, x: 100), thin = thickness(proj, x: 100)
        // Pen 5 = 0.35 mm × 20 px/mm = 7 px; pen 1 = 0.09 mm → ~2 px.
        #expect(heavy >= 6 && heavy <= 9)
        #expect(thin >= 1 && thin <= 3)
        #expect(heavy > thin * 2)
    }

    @Test func itemLineScaleOverridesGraphicsScale() {
        // A viewport from a 1:20 detail placed on a sheet (scale 1) uses the detail's pen table.
        var item = GItem(elementID: nil, category: .viewports, layer: .model, primitives: [.polyline([Vec2(0.0005, 0.0025), Vec2(0.0095, 0.0025)], closed: false, GStroke(weight: 5))])
        let plain = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([item], scale: 1), in: plain.ctx, viewToDevice: viewT(1), pointsPerPaperMeter: ppm, options: RenderOptions())
        item.lineScale = 200
        let coarse = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([item], scale: 1), in: coarse.ctx, viewToDevice: viewT(1), pointsPerPaperMeter: ppm, options: RenderOptions())
        // Scale 1 clamps the factor to 1.5×; 1:200 thins lines to ~0.88×.
        #expect(thickness(plain, x: 100) > thickness(coarse, x: 100))
    }

    @Test func halftoneIsLighter() {
        let a = Bitmap(200, 100), b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6))]), in: a.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6, halftone: true))]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        #expect(a.ink(100, 50) > 0.95)
        #expect(abs(b.ink(100, 50) - 0.45) < 0.05)
    }

    @Test func thinLinesDrawsOnePixelStrokesOnScreenOnly() {
        var o = RenderOptions()
        o.thinLines = true
        let screen = Bitmap(200, 100)
        let t = viewT(100).concatenating(CGAffineTransform(translationX: 0, y: 0.5))
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 8))]), in: screen.ctx, viewToDevice: t, pointsPerPaperMeter: ppm, options: o)
        #expect(thickness(screen, x: 100, threshold: 0.5) == 1)
        o.printing = true
        let print = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 8))]), in: print.ctx, viewToDevice: t, pointsPerPaperMeter: ppm, options: o)
        #expect(thickness(print, x: 100, threshold: 0.5) >= 18)
    }

    /// Regression: tool/drag preview passes draw with no background over the finished view. In dark mode they used to
    /// paint the dark canvas colour over the whole clip, making the view vanish while a tool or drag was active.
    @Test(arguments: [false, true])
    func overlayPassWithoutBackgroundKeepsExistingPixels(_ dark: Bool) {
        let b = Bitmap(200, 100)
        b.ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        b.ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        var o = RenderOptions()
        o.background = nil
        o.darkCanvas = dark
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 5), layer: .overlay)]), in: b.ctx, viewToDevice: viewT(100),
                              pointsPerPaperMeter: ppm, options: o, clip: CGRect(x: 0, y: 0, width: 200, height: 100))
        let corner = b.pixel(5, 90)
        #expect(corner.r == 255 && corner.g == 0 && corner.b == 0, "pixels outside the preview are untouched")
        #expect(b.pixel(100, 50) != corner, "the preview line itself is drawn")
    }

    @Test func darkCanvasInvertsBlackInkAndPaper() {
        var o = RenderOptions()
        o.darkCanvas = true
        o.background = RGBColor(0.1, 0.1, 0.1)
        let b = Bitmap(200, 100)
        let mask = GItem(elementID: nil, category: .maskingRegions, layer: .masking,
                         primitives: [.fill([.rectangle(Rect2(min: Vec2(0.6, 0.05), max: Vec2(0.9, 0.2)))], .mask)])
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6)), mask]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        let line = b.pixel(100, 50), canvas = b.pixel(10, 10), masked = b.pixel(150, 25)
        #expect(line.r > 200)                     // black ink became light
        #expect(canvas.r < 40)                    // canvas painted dark
        #expect(abs(masked.r - canvas.r) <= 2)    // white mask shows the canvas, not white
        // Colored ink stays colored and legible.
        let red = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6, color: RGBColor(0.85, 0.1, 0.1)))]), in: red.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        let p = red.pixel(100, 50)
        #expect(p.r > 180 && p.r > p.g + 100)
    }

    @Test func darkCanvasIsIgnoredWhenPrinting() {
        var o = RenderOptions()
        o.darkCanvas = true
        o.printing = true
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6))]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        #expect(b.ink(100, 50) > 0.95)
        #expect(b.ink(10, 10) < 0.01)
    }

    @Test func highlightTintsStrokesAndFills() {
        var o = RenderOptions()
        o.highlight = [ElementID(7): RGBColor(0.1, 0.4, 1.0)]
        let fill = GItem(elementID: ElementID(7), category: .floors, layer: .fills,
                         primitives: [.fill([.rectangle(Rect2(min: Vec2(0.6, 0.05), max: Vec2(0.9, 0.2)))], GFill(pattern: .solid, color: .black))])
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6), id: 7), fill]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        let p = b.pixel(100, 50)
        #expect(p.b > 230 && p.r < 60)
        let f = b.pixel(150, 25)
        #expect(f.b > f.r + 60)
    }

    @Test func hiddenElementsAndOverlaysAreSkipped() {
        var o = RenderOptions()
        o.hiddenElements = [ElementID(3)]
        o.showOverlays = false
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6), id: 3), hLine(0.1, GStroke(weight: 6), layer: .overlay)]),
                              in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        #expect(b.ink(100, 50) < 0.01)
        #expect(b.ink(100, 20) < 0.01)
        o.showOverlays = true
        GraphicsRenderer.draw(graphics([hLine(0.1, GStroke(weight: 6), layer: .overlay)]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: o)
        #expect(b.ink(100, 20) > 0.9)
    }

    @Test func maskingRegionHidesLinesBeneathIt() {
        let mask = GItem(elementID: nil, category: .maskingRegions, layer: .masking,
                         primitives: [.fill([.rectangle(Rect2(min: Vec2(0.4, 0.1), max: Vec2(0.6, 0.4)))], .mask)])
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6)), mask]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        #expect(b.ink(100, 50) < 0.01)
        #expect(b.ink(40, 50) > 0.9)
    }

    @Test func fillTransparencyIsRespected() {
        let fill = GItem(elementID: nil, category: .floors, layer: .fills,
                         primitives: [.fill([.rectangle(Rect2(min: Vec2(0.1, 0.1), max: Vec2(0.9, 0.4)))], GFill(pattern: .solid, color: .black, transparency: 0.5))])
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([fill]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        #expect(abs(b.ink(100, 50) - 0.5) < 0.03)
    }

    @Test func dashedLinesHaveGaps() {
        let b = Bitmap(400, 60)
        let item = GItem(elementID: nil, category: .detailLines, layer: .annotation, primitives: [.polyline([Vec2(0.1, 0.15), Vec2(1.9, 0.15)], closed: false, GStroke(weight: 3, pattern: .dash))])
        GraphicsRenderer.draw(graphics([item]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        let row = (20..<380).map { b.ink($0, 30) }
        let on = row.filter { $0 > 0.5 }.count, off = row.filter { $0 < 0.05 }.count
        // 3 mm dash / 1.5 mm gap → roughly 2:1 minus round caps.
        #expect(on > 150 && off > 60)
    }

    @Test func arcsAreTrueArcs() {
        let b = Bitmap(200, 200)
        let arc = Arc2(center: Vec2(0.5, 0.5), radius: 0.4, startAngle: 0, sweep: .pi)
        GraphicsRenderer.draw(graphics([GItem(elementID: nil, category: .doors, layer: .model, primitives: [.arc(arc, GStroke(weight: 4))])]),
                              in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm, options: RenderOptions())
        // Point on the arc at 45°: (0.5 + 0.4·cos45°, …) → device (156.6, 156.6).
        #expect(b.ink(156, 156) > 0.5)
        #expect(b.ink(100, 180) > 0.5)       // apex
        #expect(b.ink(100, 20) < 0.01)       // lower half not drawn (sweep is +π, counter-clockwise)
        #expect(b.ink(100, 100) < 0.01)      // center empty
    }

    @Test(arguments: FillPatternKind.allCases)
    func patternStaysInsideItsRegionAndDrawsInk(_ kind: FillPatternKind) {
        // Sheet-like drafting pattern: 8 px per paper millimeter.
        let p = 8_000.0
        let t = CGAffineTransform(scaleX: CGFloat(p), y: CGFloat(p))
        let region = Rect2(min: Vec2(0.00625, 0.00625), max: Vec2(0.03125, 0.03125)) // 50…250 px
        let item = GItem(elementID: nil, category: .filledRegions, layer: .fills,
                         primitives: [.fill([.rectangle(region)], GFill(pattern: kind, color: .black))])
        let b = Bitmap(300, 300)
        GraphicsRenderer.draw(graphics([item], scale: 1), in: b.ctx, viewToDevice: t, pointsPerPaperMeter: p, options: RenderOptions())
        var outside = 0.0, inside = 0.0
        for y in stride(from: 0, to: 300, by: 1) {
            for x in stride(from: 0, to: 300, by: 1) {
                let v = b.ink(x, y)
                if x < 48 || x > 252 || y < 48 || y > 252 { outside = max(outside, v) } else { inside += v }
            }
        }
        #expect(outside < 0.01, "pattern \(kind.rawValue) leaked outside its region")
        #expect(inside > 50, "pattern \(kind.rawValue) drew nothing")
    }

    @Test func holesStayEmptyWithEvenOddClipping() {
        let p = 8_000.0
        let outer = Polygon2.rectangle(Rect2(min: Vec2(0.00625, 0.00625), max: Vec2(0.03125, 0.03125)))
        let hole = Polygon2.rectangle(Rect2(min: Vec2(0.015, 0.015), max: Vec2(0.0225, 0.0225)))
        for kind in [FillPatternKind.solid, .crosshatch, .concrete] {
            let b = Bitmap(300, 300)
            let item = GItem(elementID: nil, category: .filledRegions, layer: .fills, primitives: [.fill([outer, hole], GFill(pattern: kind, color: .black))])
            GraphicsRenderer.draw(graphics([item], scale: 1), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: CGFloat(p), y: CGFloat(p)), pointsPerPaperMeter: p, options: RenderOptions())
            var holeInk = 0.0
            for y in 124...176 { for x in 124...176 { holeInk = max(holeInk, b.ink(x, y)) } }
            #expect(holeInk < 0.01, "\(kind.rawValue) painted inside the hole")
        }
    }

    @Test func patternsAreDeterministic() {
        func render() -> [UInt8] {
            let b = Bitmap(200, 200)
            let item = GItem(elementID: nil, category: .filledRegions, layer: .fills,
                             primitives: [.fill([.rectangle(Rect2(min: Vec2(0.001, 0.001), max: Vec2(0.024, 0.024)))], GFill(pattern: .concrete, color: .black))])
            GraphicsRenderer.draw(graphics([item], scale: 1), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: 8000, y: 8000), pointsPerPaperMeter: 8000, options: RenderOptions())
            return b.bytes
        }
        #expect(render() == render())
    }

    @Test func modelPatternsScaleWithTheModel() {
        // Brick as a model pattern: 75 mm courses. At 1:20 that is 3.75 paper mm → 30 px at 8 px/mm.
        func bedJoints(scale: Int) -> Int {
            let p = 8_000.0
            let t = CGAffineTransform(scaleX: CGFloat(p / Double(scale)), y: CGFloat(p / Double(scale)))
            let size = 0.03 * Double(scale) // 240 px square in view units
            let item = GItem(elementID: nil, category: .walls, layer: .fills,
                             primitives: [.fill([.rectangle(Rect2(min: Vec2(0, 0), max: Vec2(size, size)))], GFill(pattern: .brick, color: .black, isModelPattern: true))])
            let b = Bitmap(240, 240)
            GraphicsRenderer.draw(graphics([item], scale: scale), in: b.ctx, viewToDevice: t, pointsPerPaperMeter: p, options: RenderOptions())
            // Count dark runs down a column that avoids head joints as much as possible.
            var runs = 0, inRun = false
            for y in 0..<240 {
                let dark = (0..<240).filter { b.ink($0, y) > 0.2 }.count > 200
                if dark && !inRun { runs += 1 }
                inRun = dark
            }
            return runs
        }
        let at20 = bedJoints(scale: 20), at50 = bedJoints(scale: 50)
        #expect(at20 >= 7 && at20 <= 9)   // 240 px / 30 px
        #expect(at50 > at20 * 2)          // courses get closer at a coarser scale
    }

    @Test func densePatternsFallBackToATintQuickly() {
        // A 2 km region at a tiny zoom: sand would need billions of dots.
        let item = GItem(elementID: nil, category: .topography, layer: .fills,
                         primitives: [.fill([.rectangle(Rect2(min: Vec2(-1000, -1000), max: Vec2(1000, 1000)))], GFill(pattern: .sand, color: .black, isModelPattern: true))])
        let b = Bitmap(200, 200)
        let clock = ContinuousClock()
        let d = clock.measure {
            GraphicsRenderer.draw(graphics([item], scale: 100), in: b.ctx, viewToDevice: CGAffineTransform(scaleX: 0.1, y: 0.1).translatedBy(x: 1000, y: 1000),
                                  pointsPerPaperMeter: 10, options: RenderOptions())
        }
        #expect(d < .seconds(1))
        let v = b.ink(100, 100)
        #expect(v > 0.05 && v < 0.4)
    }

    @Test func clipLimitsDrawingToTheGivenRect() {
        let b = Bitmap(200, 100)
        GraphicsRenderer.draw(graphics([hLine(0.25, GStroke(weight: 6))]), in: b.ctx, viewToDevice: viewT(100), pointsPerPaperMeter: ppm,
                              options: RenderOptions(), clip: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(b.ink(50, 50) > 0.9)
        #expect(b.ink(150, 50) < 0.01)
    }

    @Test func textBoundsFollowCapHeightLinesAndWrapping() {
        let k = 2835.0 // 72 pt per inch
        let one = GraphicsRenderer.textBounds(GText(position: .zero, height: 0.0025, string: "DOOR SCHEDULE"), pointsPerPaperMeter: k)
        #expect(abs(one.height - 0.0025 * k) < 0.01)          // single line: height == cap height
        let two = GraphicsRenderer.textBounds(GText(position: .zero, height: 0.005, string: "DOOR SCHEDULE"), pointsPerPaperMeter: k)
        #expect(abs(two.width - one.width * 2) < one.width * 0.05)
        let lines = GraphicsRenderer.textBounds(GText(position: .zero, height: 0.0025, string: "A\nB\nC"), pointsPerPaperMeter: k)
        #expect(abs(lines.height - 0.0025 * k * (1 + 2 * 1.7)) < 0.1)
        let wrapped = GraphicsRenderer.textBounds(GText(position: .zero, height: 0.0025, string: "the quick brown fox jumps over the lazy dog", wrapWidth: 0.02), pointsPerPaperMeter: k)
        #expect(wrapped.width <= 0.02 * k + 0.5)
        #expect(wrapped.height > one.height * 3)
    }

    @Test func textIsDrawnWithAlignmentAnchorAndRotation() {
        func inkBox(_ t: GText) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
            let b = Bitmap(400, 400)
            GraphicsRenderer.draw(graphics([GItem(elementID: nil, category: .textNotes, layer: .annotation, primitives: [.text(t)])], scale: 1),
                                  in: b.ctx, viewToDevice: CGAffineTransform(scaleX: 4000, y: 4000), pointsPerPaperMeter: 4000, options: RenderOptions())
            var r = (minX: 400, maxX: -1, minY: 400, maxY: -1)
            for y in 0..<400 { for x in 0..<400 where b.ink(x, y) > 0.4 { r.minX = min(r.minX, x); r.maxX = max(r.maxX, x); r.minY = min(r.minY, y); r.maxY = max(r.maxY, y) } }
            return r
        }
        let c = Vec2(0.05, 0.05) // device (200, 200)
        let left = inkBox(GText(position: c, height: 0.005, string: "PLAN"))
        #expect(left.minX >= 199 && left.minX <= 204)
        #expect(left.minY >= 198 && left.maxY <= 222)            // baseline at 200, cap height 20 px
        let right = inkBox(GText(position: c, height: 0.005, string: "PLAN", alignment: .right))
        #expect(right.maxX <= 201 && right.maxX >= 195)
        let top = inkBox(GText(position: c, height: 0.005, string: "PLAN", verticalAnchor: 1))
        #expect(top.maxY <= 201 && top.maxY >= 196)
        let rotated = inkBox(GText(position: c, height: 0.005, string: "SECTION", rotation: .pi / 2))
        #expect(rotated.maxY - rotated.minY > rotated.maxX - rotated.minX)
        #expect(rotated.maxX <= 201)
    }

    @Test func realPlanRendersWallsDoorsAndText() {
        let f = Fixture.shared
        let g = ViewGraphicsBuilder(model: f.model, view: f.model[f.plan]!).build()
        let b = Bitmap(600, 500)
        // Fit 0…10 × 0…8 model meters with a margin; 1:100.
        let zoom = 45.0
        let t = CGAffineTransform(translationX: 60, y: 60).scaledBy(x: CGFloat(zoom), y: CGFloat(zoom))
        GraphicsRenderer.drawScreen(g, in: b.ctx, modelToScreen: t, visibleRect: CGRect(x: 0, y: 0, width: 600, height: 500), options: RenderOptions())
        // Wall along y = 0 around x = 5 → device (285, 60).
        #expect((50...70).contains { b.ink(285, $0) > 0.5 })
        let total = (0..<500).reduce(0) { acc, y in acc + (0..<600).filter { b.ink($0, y) > 0.5 }.count }
        #expect(total > 2_000)
    }

    @Test func renders20kPrimitivesAtInteractiveRates() {
        // Synthetic plan: 2,000 elements × 10 primitives (walls with cut fills, door swings, text).
        var items: [GItem] = []
        for i in 0..<2_000 {
            let x = Double(i % 50) * 2, y = Double(i / 50) * 2
            var prims: [GPrimitive] = []
            let r = Rect2(min: Vec2(x, y), max: Vec2(x + 1.6, y + 0.2))
            prims.append(.fill([.rectangle(r)], GFill(pattern: i % 3 == 0 ? .diagonalUp : .solid, color: RGBColor(0.3, 0.3, 0.3), background: .white)))
            prims.append(.polyline(r.corners, closed: true, GStroke(weight: 5)))
            for k in 0..<4 { prims.append(.polyline([Vec2(x + 0.2 * Double(k), y + 0.3), Vec2(x + 0.2 * Double(k) + 0.15, y + 0.9)], closed: false, GStroke(weight: 1, pattern: k == 3 ? .hidden : .solid))) }
            prims.append(.arc(Arc2(center: Vec2(x + 1, y + 0.2), radius: 0.8, startAngle: 0, sweep: .pi / 2), GStroke(weight: 1)))
            prims.append(.polyline([Vec2(x + 1, y + 0.2), Vec2(x + 1, y + 1)], closed: false, GStroke(weight: 2)))
            prims.append(.polyline([Vec2(x, y + 1.2), Vec2(x + 1.5, y + 1.2), Vec2(x + 1.5, y + 1.6)], closed: false, GStroke(weight: 3, color: RGBColor(0.2, 0.3, 0.8))))
            prims.append(.text(GText(position: Vec2(x + 0.1, y + 1.3), height: 0.0025, string: "D\(i)")))
            items.append(GItem(elementID: ElementID(UInt64(i + 1)), category: .walls, layer: i % 2 == 0 ? .cut : .model, primitives: prims))
        }
        items.sort { $0.layer < $1.layer }
        let g = graphics(items, scale: 100)
        let primitiveCount = items.reduce(0) { $0 + $1.primitives.count }
        #expect(primitiveCount == 20_000)
        let b = Bitmap(2000, 1500)
        let clock = ContinuousClock()
        // Whole plan on screen: 100 m × 80 m into 2000 px.
        let fitT = CGAffineTransform(scaleX: 19, y: 19)
        _ = clock.measure { GraphicsRenderer.drawScreen(g, in: b.ctx, modelToScreen: fitT, visibleRect: CGRect(x: 0, y: 0, width: 2000, height: 1500), options: RenderOptions()) }
        var full: Duration = .zero, zoomed: Duration = .zero
        for _ in 0..<3 {
            full += clock.measure { GraphicsRenderer.drawScreen(g, in: b.ctx, modelToScreen: fitT, visibleRect: CGRect(x: 0, y: 0, width: 2000, height: 1500), options: RenderOptions()) }
        }
        // Zoomed in to ~10 m wide: most items culled.
        let zoomT = CGAffineTransform(scaleX: 200, y: 200).translatedBy(x: -40, y: -30)
        for _ in 0..<3 {
            zoomed += clock.measure { GraphicsRenderer.drawScreen(g, in: b.ctx, modelToScreen: zoomT, visibleRect: CGRect(x: 0, y: 0, width: 2000, height: 1500), options: RenderOptions()) }
        }
        var thin = RenderOptions()
        thin.thinLines = true
        let thinFull = clock.measure { GraphicsRenderer.drawScreen(g, in: b.ctx, modelToScreen: fitT, visibleRect: CGRect(x: 0, y: 0, width: 2000, height: 1500), options: thin) }
        print("RENDER-TIMING full=\(full / 3) zoomed=\(zoomed / 3) thinLinesFull=\(thinFull) primitives=\(primitiveCount)")
        // Debug builds are several times slower than release; generous bounds still catch regressions.
        #expect(full / 3 < .milliseconds(1_500))
        #expect(zoomed / 3 < full / 3)
    }
}
