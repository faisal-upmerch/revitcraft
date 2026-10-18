import CoreGraphics
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import ArcusCanvasMetal

/// Scene build, per-frame CPU encode and GPU times for pans/zooms at 2560×1600 px, versus GraphicsRenderer (CPU) for
/// the same frames. Numbers are printed as a table ("[perf]" lines); assertions only guard gross regressions so the
/// test stays deterministic on any Apple-silicon Mac. Build with `-c release` for representative CPU numbers.
@Suite("Canvas performance", .serialized)
@MainActor
struct PerformanceTests {
    struct Row {
        var name: String
        var items: Int
        var records: Int
        var buildMs: Double
        var encodeMs: Double
        var encodeP95: Double
        var gpuMs: Double
        var gpuP95: Double
        var cgMs: Double
    }

    static func median(_ a: [Double]) -> Double { let s = a.sorted(); return s.isEmpty ? .nan : s[s.count / 2] }
    static func p95(_ a: [Double]) -> Double { let s = a.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * 0.95))] }

    /// Pan/zoom path: starts at "zoom to fit", zooms in 8× while panning across the drawing and back out.
    static func frames(fit: Rect2, widthPt: Double, heightPt: Double, count: Int) -> [(CGAffineTransform, Double)] {
        let fitZoom = min(widthPt / fit.width, heightPt / fit.height) * 0.92
        return (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1))
            let zoom = fitZoom * pow(8, sin(t * .pi))
            let c = fit.center + Vec2(fit.width * 0.3 * sin(t * 2 * .pi), fit.height * 0.25 * sin(t * 3 * .pi))
            let m = CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: widthPt / 2 - c.x * zoom, ty: heightPt / 2 - c.y * zoom)
            return (m, zoom)
        }
    }

    func measure(_ name: String, _ g: ViewGraphics, frameCount: Int = 90, cgFrames: Int = 12) throws -> Row {
        let ctx = try #require(MetalCanvasContext.shared)
        var builds: [Double] = []
        var scene: MetalCanvasScene?
        for _ in 0..<3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            scene = MetalCanvasScene.build(g, context: ctx)
            builds.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        let sc = try #require(scene)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        r.setScene(sc)
        let widthPt = 1280.0, heightPt = 800.0, scale = 2.0
        let tex = try #require(r.makeOffscreenTarget(width: Int(widthPt * scale), height: Int(heightPt * scale)))
        var fit = Rect2.empty
        for i in g.items where i.layer != .overlay { fit.include(i.bounds) }
        let path = Self.frames(fit: fit, widthPt: widthPt, heightPt: heightPt, count: frameCount)
        // Warm-up (pipeline, residency, first-touch of buffers).
        for (m, zoom) in path.prefix(3) {
            _ = r.waitUntilCompleted(try #require(r.encode(to: tex, viewToDevice: m, pointsPerPaperMeter: zoom * Double(g.scale), pixelsPerPoint: scale)))
        }
        var encode: [Double] = [], gpu: [Double] = []
        for (m, zoom) in path {
            let st = try #require(r.encode(to: tex, viewToDevice: m, pointsPerPaperMeter: zoom * Double(g.scale), pixelsPerPoint: scale))
            let done = r.waitUntilCompleted(st)
            encode.append(st.cpuEncodeMilliseconds)
            if let t = done.gpuMilliseconds { gpu.append(t) }
        }
        #expect(r.scene === sc, "pan/zoom must not rebuild the scene")

        // CoreGraphics for a subset of the same frames.
        let w = Int(widthPt * scale), h = Int(heightPt * scale)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var cg: [Double] = []
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let step = max(1, path.count / cgFrames)
        bytes.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
            c.scaleBy(x: scale, y: scale)
            for (m, zoom) in stride(from: 0, to: path.count, by: step).map({ path[$0] }) {
                let t0 = CFAbsoluteTimeGetCurrent()
                GraphicsRenderer.draw(g, in: c, viewToDevice: m, pointsPerPaperMeter: zoom * Double(g.scale), options: RenderOptions(),
                                      clip: CGRect(x: 0, y: 0, width: widthPt, height: heightPt))
                cg.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            }
        }
        return Row(name: name, items: g.items.count, records: sc.statistics.records, buildMs: Self.median(builds),
                   encodeMs: Self.median(encode), encodeP95: Self.p95(encode), gpuMs: Self.median(gpu), gpuP95: Self.p95(gpu),
                   cgMs: Self.median(cg))
    }

    @Test func panZoomCourtyardAndStress() throws {
        var rows: [Row] = []
        let t0 = CFAbsoluteTimeGetCurrent()
        let house = CourtyardHouse.make()
        let plan = try #require(house.views.first { $0.name == "Ground Floor" && $0.view?.kind == .floorPlan })
        let hg = ViewGraphicsBuilder(model: house, view: plan).build()
        print(String(format: "[perf] Courtyard House model + plan display list: %.0f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000))
        rows.append(try measure("Courtyard House ground plan", hg))

        let t1 = CFAbsoluteTimeGetCurrent()
        let stress = CourtyardHouse.stress(count: 20_000)
        let sPlan = try #require(stress.views.first { $0.view?.kind == .floorPlan })
        let sg = ViewGraphicsBuilder(model: stress, view: sPlan).build()
        print(String(format: "[perf] Stress 20k model + plan display list: %.0f ms", (CFAbsoluteTimeGetCurrent() - t1) * 1000))
        rows.append(try measure("Stress 20 000 elements", sg))

        print("[perf] | display list | items | GPU records | scene build ms | CPU encode ms/frame (p50/p95) | GPU ms/frame (p50/p95) | CoreGraphics ms/frame |")
        for r in rows {
            print(String(format: "[perf] | %@ | %d | %d | %.1f | %.3f / %.3f | %.3f / %.3f | %.1f |", r.name, r.items, r.records,
                         r.buildMs, r.encodeMs, r.encodeP95, r.gpuMs, r.gpuP95, r.cgMs))
            // Gross-regression guards only (120 Hz budget is 8.3 ms; debug CPU builds are slower).
            #expect(r.gpuMs < 8.3, "\(r.name): GPU \(r.gpuMs) ms/frame")
            #expect(r.encodeMs < 8.3, "\(r.name): CPU encode \(r.encodeMs) ms/frame")
        }
    }
}
