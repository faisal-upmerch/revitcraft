import Foundation
import Testing
import Metal
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

/// Headless frame-time / memory benchmark (offscreen through the full frame path, 2560×1600, orbiting camera).
/// Prints BENCH lines for reports; assertions are loose sanity bounds only.
@Suite("Viewport benchmark", .serialized)
@MainActor struct ViewportBenchmarkTests {
    static let size = CGSize(width: 2560, height: 1600)

    private func line(_ label: String, _ view: Viewport3DView, _ r: (gpu: [Double], cpu: [Double])) -> String {
        let s = view.statistics
        return String(format: "BENCH %@ [%@] 2560x1600 scale %.2f: gpu median %.3f ms p95 %.3f ms, cpu encode median %.3f ms, draws %d, render targets %.1f MB",
                      label, view.rendererBackend, s.renderScale, Stats.median(r.gpu), Stats.percentile(r.gpu, 0.95), Stats.median(r.cpu), s.drawCalls,
                      Double(view.renderer?.lastBenchmarkTargetBytes ?? 0) / 1_048_576)
    }

    @Test func shadedOrbitBenchmark() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let view = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let firstInit = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let t1 = CFAbsoluteTimeGetCurrent()
        let second = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let secondInit = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        _ = second
        guard let device = view.renderer?.device else { Issue.record("no renderer"); return }
        let before = device.currentAllocatedSize
        let scene = SyntheticScene.make(elements: 3000)
        view.setScene(scene)
        view.zoomExtents(animated: false)
        view.visualStyle = .shaded
        _ = view.measureFrameTimes(frames: 10, size: Self.size) // warm-up (allocates targets)
        let r = view.measureFrameTimes(frames: 120, size: Self.size)
        let after = device.currentAllocatedSize
        let s = view.statistics
        #expect(r.gpu.count == 120)
        print(String(format: "BENCH shaded 2560x1600: tris %d, draws %d, gpu median %.3f ms p95 %.3f ms, cpu encode median %.3f ms, upload %.1f ms, scene buffers %.1f MB, device alloc delta %.1f MB, renderer init first %.1f ms second %.1f ms",
                     s.triangles, s.drawCalls, Stats.median(r.gpu), Stats.percentile(r.gpu, 0.95), Stats.median(r.cpu), s.lastUploadMilliseconds,
                     Double(s.bufferBytes) / 1_048_576, Double(after - before) / 1_048_576, firstInit, secondInit))
        print(line("shaded", view, r))
    }

    /// Every configuration on every backend: plain shaded, all effects at full resolution, all effects upscaled with
    /// MetalFX from 2/3 resolution (the interactive path), and Realistic.
    @Test func effectsAndUpscalingBenchmark() throws {
        let scene = SyntheticScene.make(elements: 3000)
        for backend in Fixture.backends {
            let view = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backend: backend)
            view.setScene(scene)
            view.orient(to: .southWestIso, animated: false)
            view.visualStyle = .shaded
            _ = view.measureFrameTimes(frames: 5, size: Self.size)
            print(line("shaded", view, view.measureFrameTimes(frames: 90, size: Self.size)))
            view.castShadows = true
            view.ambientOcclusion = true
            view.silhouetteEdges = true
            view.sunDirection = nil // sun relative to the view: the shadow map is re-rendered every orbit frame
            _ = view.measureFrameTimes(frames: 5, size: Self.size)
            print(line("shaded+shadows(re-rendered each frame)+AO+silhouettes", view, view.measureFrameTimes(frames: 90, size: Self.size)))
            view.sunDirection = Vec3(0.5, -0.6, 0.6) // world-fixed sun: shadow map cached across frames
            _ = view.measureFrameTimes(frames: 5, size: Self.size)
            print(line("shaded+shadows(cached)+AO+silhouettes", view, view.measureFrameTimes(frames: 90, size: Self.size)))
            if view.renderer?.supportsUpscaling == true {
                _ = view.measureFrameTimes(frames: 5, size: Self.size, renderScale: 2.0 / 3.0)
                let up = view.measureFrameTimes(frames: 90, size: Self.size, renderScale: 2.0 / 3.0)
                #expect(view.statistics.renderScale < 0.7)
                print(line("shaded+effects MetalFX", view, up))
            }
            view.visualStyle = .realistic
            _ = view.measureFrameTimes(frames: 5, size: Self.size)
            print(line("realistic+effects", view, view.measureFrameTimes(frames: 90, size: Self.size)))
        }
    }

    /// Pipeline compile time: cold (new MTL4Archive written) vs. warm (binaries looked up in the archive).
    @Test func pipelineArchiveBenchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else { return }
        let dir = FileManager.default.temporaryDirectory.appending(path: "ArcusViewportArchive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let samples = ViewportPipelines.preferredSampleCount(device)
        let suffix = "\n// benchmark \(UUID().uuidString)\n"
        let cold = try #require(ViewportPipelines.build(device: device, backend: .metal4, sampleCount: samples, archiveDirectory: dir, sourceSuffix: suffix))
        let warm = try #require(ViewportPipelines.build(device: device, backend: .metal4, sampleCount: samples, archiveDirectory: dir, sourceSuffix: suffix))
        #expect(!cold.usedArchive)
        #expect(warm.usedArchive)
        let classic = try #require(ViewportPipelines.build(device: device, backend: .classic, sampleCount: samples, archiveDirectory: nil,
                                                           sourceSuffix: "\n// benchmark \(UUID().uuidString)\n"))
        let first = Viewport3DView(frame: .zero)
        let t0 = CFAbsoluteTimeGetCurrent()
        _ = Viewport3DView(frame: .zero)
        let viewInit = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        _ = first
        print(String(format: "BENCH pipelines: Metal 4 cold %.1f ms, Metal 4 again with archive (+process cache) %.1f ms, classic cold %.1f ms; additional view init with shared pipelines %.2f ms",
                     cold.buildMilliseconds, warm.buildMilliseconds, classic.buildMilliseconds, viewInit))
    }
}
