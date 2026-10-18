import AppKit
import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import ArcusCanvasMetal

@Suite("Metal canvas view")
@MainActor
struct ViewTests {
    /// `setGraphics` builds off the main thread and installs only the latest request.
    @Test func setGraphicsInstallsLatestSceneOffMain() async throws {
        let view = MetalCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        try #require(view.renderer != nil)
        var many: [GItem] = []
        for i in 0..<3000 { many.append(Harness.item(UInt64(i + 1), .model, [.polyline([Vec2(Double(i), 0), Vec2(Double(i), 1)], closed: false, .thin)])) }
        let first = Harness.graphics(many)
        let second = Harness.graphics([Harness.item(1, .model, [.polyline([Vec2(0, 0), Vec2(1, 1), Vec2(2, 0)], closed: false, .thin)])])
        view.setGraphics(first)
        view.setGraphics(second)
        let deadline = Date(timeIntervalSinceNow: 10)
        while view.scene == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(300))   // give a stale build the chance to (wrongly) land
        #expect(view.scene?.statistics.records == 2)
    }

    /// The CAMetalLayer drawable path (Metal 4 waitForDrawable / signalDrawable / present with the layer's residency
    /// set) works off-window too; frames complete on the GPU without errors and draw the scene.
    @Test func drawablePathCompletes() throws {
        let ctx = try #require(MetalCanvasContext.shared)
        let layer = CAMetalLayer()
        layer.device = ctx.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 400, height: 200)
        let r = try #require(MetalCanvasRenderer(context: ctx))
        let s = CanvasSetup.model(zoom: 40, viewScale: 100)
        r.setScene(MetalCanvasScene.build(Harness.graphics([Harness.item(1, .model, [.polyline([s.view(10, 50), s.view(190, 50)], closed: false, GStroke(weight: 9))])]), context: ctx))
        MetalCanvasRenderer.attach(layer, to: ctx)
        defer { MetalCanvasRenderer.detach(layer, from: ctx) }
        for i in 0..<6 {
            let d = try #require(layer.nextDrawable())
            let st = try #require(r.encode(to: d.texture, viewToDevice: s.viewToDevice.translatedBy(x: Double(i) * 0.01, y: 0),
                                           pointsPerPaperMeter: s.ppm, pixelsPerPoint: 2, drawable: d))
            let done = r.waitUntilCompleted(st)
            #expect(done.gpuMilliseconds != nil, "frame \(i) completed on the GPU")
        }
    }

    /// End to end in an on-screen window: display link → drawable → Metal 4 present, frames only on change, none
    /// while hidden. The on-screen part needs a window server session in which the test process's windows can be
    /// visible; otherwise it is reported and skipped (the view never draws into invisible windows by design).
    @Test func windowedViewPresentsFramesOnDemand() throws {
        let ctx = try #require(MetalCanvasContext.shared)
        let app = NSApplication.shared
        if app.activationPolicy() == .prohibited { app.setActivationPolicy(.accessory) }
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 400, height: 300), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = MetalCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), context: ctx)
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        var frames = 0
        view.onFrame = { _ in frames += 1 }
        let g = Harness.graphics([Harness.item(1, .model, [.polyline([Vec2(-5, -3), Vec2(5, 3)], closed: false, GStroke(weight: 5))])])
        view.setScene(MetalCanvasScene.build(g, context: ctx))
        view.viewToDevice = CGAffineTransform(a: 30, b: 0, c: 0, d: 30, tx: 200, ty: 150)
        view.pointsPerPaperMeter = 3000
        func pump(_ seconds: Double) {
            let end = Date(timeIntervalSinceNow: seconds)
            while Date() < end { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005)) }
        }
        pump(0.5)
        guard window.occlusionState.contains(.visible) else {
            print("[view] window not visible in this session (no GUI session for the test process); on-screen checks skipped")
            #expect(frames == 0, "never draws into an invisible window")
            return
        }
        #expect(frames > 0, "at least one frame presented")
        let idle = frames
        pump(0.5)
        #expect(frames - idle <= 1, "no frames while nothing changes (got \(frames - idle))")
        let before = frames
        for i in 0..<20 {
            view.viewToDevice = CGAffineTransform(a: 30, b: 0, c: 0, d: 30, tx: 200 + Double(i), ty: 150)
            pump(0.02)
        }
        #expect(frames > before, "pans redraw")
        view.isHidden = true
        let hiddenStart = frames
        view.requestRedraw()
        pump(0.2)
        #expect(frames == hiddenStart, "no drawing while hidden")
    }
}
