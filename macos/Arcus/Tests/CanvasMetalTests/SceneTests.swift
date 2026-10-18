import CoreGraphics
import Foundation
import Metal
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusOutput
@testable import ArcusCanvasMetal

@Suite("Metal canvas scene & renderer")
@MainActor
struct SceneTests {
    /// Swift mirrors must have exactly the MSL sizes (the shader reads them by stride).
    @Test func gpuLayoutsMatchShader() throws {
        let ctx = try #require(MetalCanvasContext.shared)
        let probe = CanvasShaders.source + """

        kernel void layout_sizes(device uint* out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            if (i != 0) return;
            out[0] = sizeof(Rec); out[1] = sizeof(StrokeStyle); out[2] = sizeof(FillInst); out[3] = sizeof(TextInst);
            out[4] = sizeof(Glyph); out[5] = sizeof(Item); out[6] = sizeof(Frame);
        }
        """
        let lib = try ctx.device.makeLibrary(source: probe, options: nil)
        let fn = try #require(lib.makeFunction(name: "layout_sizes"))
        let pso = try ctx.device.makeComputePipelineState(function: fn)
        let out = try #require(ctx.device.makeBuffer(length: 64, options: .storageModeShared))
        let q = try #require(ctx.device.makeCommandQueue())
        let cb = try #require(q.makeCommandBuffer())
        let enc = try #require(cb.makeComputeCommandEncoder())
        enc.setComputePipelineState(pso)
        enc.setBuffer(out, offset: 0, index: 0)
        enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let v = out.contents().bindMemory(to: UInt32.self, capacity: 7)
        #expect(Int(v[0]) == MemoryLayout<GPURecord>.stride)
        #expect(Int(v[1]) == MemoryLayout<GPUStrokeStyle>.stride)
        #expect(Int(v[2]) == MemoryLayout<GPUFill>.stride)
        #expect(Int(v[3]) == MemoryLayout<GPUText>.stride)
        #expect(Int(v[4]) == MemoryLayout<GPUGlyph>.stride)
        #expect(Int(v[5]) == MemoryLayout<GPUItem>.stride)
        #expect(Int(v[6]) == MemoryLayout<GPUFrame>.stride)
        #expect(MemoryLayout<GPUFrame>.stride <= 256, "overlay uniforms live at offset 256")
    }

    /// The dark-canvas colour rules are a port of RenderPass.darkMap — compare them directly.
    @Test func darkMapMatchesGraphicsRenderer() throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: cs,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        for bg in [RGBColor?.none, .white, RGBColor(0.1, 0.1, 0.12), RGBColor(0.3, 0.2, 0.2)] {
            for dark in [false, true] {
                var o = RenderOptions()
                o.background = bg
                o.darkCanvas = dark
                let pass = RenderPass(g: Harness.graphics([]), ctx: bctx, t: .identity, ppm: 1000, options: o, clip: nil)
                let mine = CanvasColors(options: o)
                #expect(mine.canvas == pass.canvas)
                #expect(mine.dark == pass.dark)
                var k = 0
                for r in stride(from: 0.0, through: 1.0, by: 0.125) {
                    for g in stride(from: 0.0, through: 1.0, by: 0.25) {
                        for b in stride(from: 0.0, through: 1.0, by: 0.25) {
                            let c = RGBColor(r, g, b, k % 3 == 0 ? 0.5 : 1)
                            k += 1
                            #expect(mine.resolve(c) == (pass.dark ? pass.darkMap(c) : c))
                        }
                    }
                }
            }
        }
    }

    @Test func fillTessellationHolesAndBoundaries() {
        let outer = Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)])
        let hole = Polygon2([Vec2(2, 2), Vec2(8, 2), Vec2(8, 8), Vec2(2, 8)])
        let island = Polygon2([Vec2(4, 4), Vec2(6, 4), Vec2(6, 6), Vec2(4, 6)])
        let tris = FillTessellator.triangulate([outer, hole, island])
        func area(_ t: FillTessellator.Triangle) -> Double { abs((t.b - t.a).cross(t.c - t.a)) / 2 }
        #expect(abs(tris.reduce(0) { $0 + area($1) } - (100 - 36 + 4)) < 1e-9)
        // Boundary edges: 4 + 4 + 4 loop edges, bridges/diagonals are interior.
        let boundary = tris.reduce(0) { $0 + $1.boundary.nonzeroBitCount }
        #expect(boundary == 12)
        // Two adjacent squares of one fill: the shared edge is not a boundary.
        let l = Polygon2([Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)])
        let r = Polygon2([Vec2(1, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1)])
        let pair = FillTessellator.triangulate([l, r])
        #expect(pair.count == 4)
        #expect(pair.reduce(0) { $0 + $1.boundary.nonzeroBitCount } == 6)
        #expect(FillTessellator.triangulate([Polygon2([Vec2(0, 0), Vec2(1, 1)])]).isEmpty)
    }

    @Test func zeroLengthStrokesDrawNothing() throws {
        let g = Harness.graphics([Harness.item(1, .model, [.polyline([Vec2(1, 1), Vec2(1, 1), Vec2(1, 1)], closed: false, GStroke(weight: 8)),
                                                          .polyline([Vec2(0, 0), Vec2(2, 0), Vec2(2, 0)], closed: false, GStroke(weight: 8))])])
        let data = try #require(SceneBuilder.build(g, atlas: nil))
        #expect(data.records.count == 1)
    }

    /// Highlight, hidden elements and dark mode change without rebuilding or re-uploading geometry.
    @Test func dynamicStateWithoutRebuild() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([
            Harness.item(7, .model, [.polyline([s.view(20, 100), s.view(280, 100)], closed: false, GStroke(weight: 8))]),
            Harness.item(8, .fills, [.fill([Polygon2([s.view(20, 20), s.view(80, 20), s.view(80, 60), s.view(20, 60)])], GFill(pattern: .solid, color: .black))]),
        ])
        let ctx = try #require(MetalCanvasContext.shared)
        let scene = try #require(MetalCanvasScene.build(g, context: ctx))
        let r = try #require(MetalCanvasRenderer(context: ctx))
        r.setScene(scene)
        let tex = try #require(r.makeOffscreenTarget(width: s.pixelWidth, height: s.pixelHeight))
        let recordsBefore = Data(bytes: scene.records.contents(), count: scene.records.length)
        func pixel(_ x: Double, _ y: Double) throws -> [UInt8] {
            _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale)))
            let px = MetalCanvasRenderer.readPixels(tex)
            let i = ((s.pixelHeight - 1 - Int(y * s.scale)) * s.pixelWidth + Int(x * s.scale)) * 4
            return Array(px[i..<i + 4])
        }
        #expect(try pixel(150, 100) == [0, 0, 0, 255])
        var o = r.options
        o.highlight = [ElementID(7): RGBColor(1, 0, 0)]
        r.options = o
        #expect(try pixel(150, 100) == [0, 0, 255, 255])          // BGRA red
        o.hiddenElements = [ElementID(7)]
        r.options = o
        #expect(try pixel(150, 100) == [255, 255, 255, 255])
        r.halftoneElements = [ElementID(8)]
        let ht = try pixel(50, 40)
        #expect(ht[0] > 100 && ht[0] < 160)                     // black mixed 55 % toward white
        o.darkCanvas = true
        o.background = RGBColor(0.1, 0.1, 0.1)
        r.options = o
        #expect(try pixel(150, 150)[0] < 40)
        #expect(r.scene === scene)
        #expect(Data(bytes: scene.records.contents(), count: scene.records.length) == recordsBefore)
    }

    @Test func overlayPrimitivesAPI() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let ctx = try #require(MetalCanvasContext.shared)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        r.setOverlay(primitives: [.polyline([s.view(20, 100), s.view(280, 100)], closed: false, GStroke(weight: 6, color: RGBColor(0, 0, 1)))], scale: 100)
        let tex = try #require(r.makeOffscreenTarget(width: s.pixelWidth, height: s.pixelHeight))
        _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale)))
        let px = MetalCanvasRenderer.readPixels(tex)
        let i = ((s.pixelHeight - 1 - 200) * s.pixelWidth + 300) * 4
        #expect(Array(px[i..<i + 4]) == [255, 0, 0, 255])
        r.setOverlay(primitives: [], scale: 100)
        _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale)))
        #expect(Array(MetalCanvasRenderer.readPixels(tex)[i..<i + 4]) == [255, 255, 255, 255])
    }

    /// `paintsBackground = false`: transparent clear, but masks still paint the canvas colour.
    @Test func transparentBackgroundKeepsCanvasColourForMasks() throws {
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        let g = Harness.graphics([Harness.item(1, .masking, [.fill([Polygon2([s.view(10, 10), s.view(60, 10), s.view(60, 60), s.view(10, 60)])], .mask)])])
        let ctx = try #require(MetalCanvasContext.shared)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        var o = RenderOptions()
        o.background = RGBColor(0.2, 0.4, 0.6)
        r.options = o
        r.paintsBackground = false
        r.setScene(MetalCanvasScene.build(g, context: ctx))
        let tex = try #require(r.makeOffscreenTarget(width: s.pixelWidth, height: s.pixelHeight))
        _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: s.viewToDevice, pointsPerPaperMeter: s.ppm, pixelsPerPoint: s.scale)))
        let px = MetalCanvasRenderer.readPixels(tex)
        func at(_ x: Double, _ y: Double) -> [UInt8] {
            let i = ((s.pixelHeight - 1 - Int(y * s.scale)) * s.pixelWidth + Int(x * s.scale)) * 4
            return Array(px[i..<i + 4])
        }
        #expect(at(200, 150) == [0, 0, 0, 0])
        #expect(at(30, 30) == [153, 102, 51, 255])
    }

    /// Scenes build concurrently off the main actor (shared glyph atlas) with identical results.
    @Test func concurrentBuilds() async throws {
        let ctx = try #require(MetalCanvasContext.shared)
        var items: [GItem] = []
        for i in 0..<200 {
            let p = Vec2(Double(i % 20), Double(i / 20))
            items.append(Harness.item(UInt64(i + 1), .annotation, [.text(GText(position: p, height: 0.003, string: "Tag \(i) ÅØ€ \(i * 7)")),
                                                                  .polyline([p, p + Vec2(0.5, 0.2)], closed: false, GStroke(weight: 2))]))
        }
        let g = Harness.graphics(items)
        let scenes = await withTaskGroup(of: MetalCanvasScene?.self) { group in
            for _ in 0..<6 { group.addTask { await MetalCanvasScene.make(g, context: ctx) } }
            var out: [MetalCanvasScene?] = []
            for await s in group { out.append(s) }
            return out
        }
        let counts = Set(scenes.map { $0?.statistics.records ?? -1 })
        #expect(counts.count == 1 && !counts.contains(-1))
        #expect((scenes.first??.statistics.glyphs ?? 0) > 1000)
    }

    @Test func viewWithoutWindowDoesNotDraw() throws {
        let v = MetalCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        #expect(v.renderer != nil)
        v.viewToDevice = CGAffineTransform(a: 10, b: 0, c: 0, d: 10, tx: 0, ty: 0)
        v.pointsPerPaperMeter = 1000
        v.highlight = [ElementID(1): RGBColor(1, 0, 0)]
        v.setOverlay(primitives: [.polyline([Vec2(0, 0), Vec2(1, 1)], closed: false, .thin)], scale: 100)
        v.requestRedraw()
        #expect(v.lastFrameStats == nil)
        #expect(v.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
