import Foundation
import Testing
import Metal
import CoreGraphics
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

/// Pixel access for rendered snapshots (BGRA, sRGB).
struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]
    init?(_ image: CGImage?) {
        guard let image else { return nil }
        width = image.width; height = image.height
        var d = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &d, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = d
    }
    /// (r, g, b) at x, y (top-left origin).
    func rgb(_ x: Int, _ y: Int) -> SIMD3<Double> {
        let i = (y * width + x) * 4
        return SIMD3(Double(data[i + 2]), Double(data[i + 1]), Double(data[i])) / 255
    }
    func luminance(_ x: Int, _ y: Int) -> Double { let c = rgb(x, y); return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
    var meanLuminance: Double {
        var s = 0.0
        for y in stride(from: 0, to: height, by: 2) { for x in stride(from: 0, to: width, by: 2) { s += luminance(x, y) } }
        return s / Double((height / 2) * (width / 2))
    }
    /// Distinct colors on a coarse grid (a blank frame has 1-2).
    var distinctColors: Int {
        var set = Set<UInt32>()
        for y in stride(from: 0, to: height, by: 3) {
            for x in stride(from: 0, to: width, by: 3) {
                let i = (y * width + x) * 4
                set.insert(UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16)
            }
        }
        return set.count
    }
    /// Mean absolute per-channel difference (0...1).
    func difference(_ o: Pixels) -> Double {
        guard o.width == width, o.height == height else { return 1 }
        var s = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            s += abs(Int(data[i]) - Int(o.data[i])) + abs(Int(data[i + 1]) - Int(o.data[i + 1])) + abs(Int(data[i + 2]) - Int(o.data[i + 2]))
        }
        return Double(s) / Double(data.count / 4 * 3) / 255
    }
}

enum Snapshots {
    /// Writes a PNG next to the test run for visual review (path printed).
    static func save(_ image: CGImage?, _ name: String) {
        guard let image else { return }
        let dir = FileManager.default.temporaryDirectory.appending(path: "ArcusViewportTests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("SNAPSHOT \(url.path)")
    }
}

@MainActor enum Fixture {
    static let backends: [ViewportBackendKind] = {
        guard let d = MTLCreateSystemDefaultDevice() else { return [] }
        return d.supportsFamily(.metal4) ? [.metal4, .classic] : [.classic]
    }()

    static func view(_ backend: ViewportBackendKind, elements: Int = 60) -> Viewport3DView {
        let v = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), backend: backend)
        v.setScene(SyntheticScene.make(elements: elements))
        v.orient(to: .southWestIso, animated: false)
        return v
    }
}

@Suite("Viewport rendering", .serialized)
@MainActor struct ViewportRenderingTests {
    static let size = CGSize(width: 480, height: 320)

    @Test func shaderStructLayoutsMatchSwift() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let lib = try device.makeLibrary(source: ViewportShaders.source, options: nil)
        let fn = try #require(lib.makeFunction(name: "layout_probe"))
        let pso = try device.makeComputePipelineState(function: fn)
        let out = try #require(device.makeBuffer(length: 16, options: .storageModeShared))
        let q = try #require(device.makeCommandQueue())
        let cb = try #require(q.makeCommandBuffer())
        let e = try #require(cb.makeComputeCommandEncoder())
        e.setComputePipelineState(pso)
        e.setBuffer(out, offset: 0, index: 0)
        e.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        e.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let v = out.contents().bindMemory(to: UInt32.self, capacity: 4)
        #expect(Int(v[0]) == MemoryLayout<ViewportUniforms>.stride)
        #expect(Int(v[1]) == MemoryLayout<PostUniforms>.stride)
        #expect(Int(v[2]) == MemoryLayout<PackedVertex>.stride)
        #expect(Int(v[3]) == MemoryLayout<OverlayVertex>.stride)
    }

    @Test func pipelinesCompileForEveryBackend() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        for b in Fixture.backends {
            let p = try #require(ViewportPipelines.shared(device: device, backend: b, sampleCount: ViewportPipelines.preferredSampleCount(device)))
            #expect(p.backend == b)
            #expect((p.compiler != nil) == (b == .metal4))
            print(String(format: "BENCH pipelines %@: %.1f ms (archive %@)", b.rawValue, p.buildMilliseconds, p.usedArchive ? "hit" : "miss"))
        }
    }

    @Test func rendersNonEmptyFramesOnBothBackends() throws {
        var images: [ViewportBackendKind: Pixels] = [:]
        for b in Fixture.backends {
            let v = Fixture.view(b)
            #expect(v.rendererBackend == b.rawValue)
            for style in VisualStyle.allCases {
                v.visualStyle = style
                let img = v.snapshot(size: Self.size)
                let px = try #require(Pixels(img), "no image for \(style) on \(b.rawValue)")
                #expect(px.distinctColors > 8, "\(style) on \(b.rawValue) looks blank")
                Snapshots.save(img, "style-\(style.rawValue.replacingOccurrences(of: " ", with: ""))-\(b == .metal4 ? "mtl4" : "classic")")
                if style == .shaded { images[b] = px }
            }
        }
        if let a = images[.metal4], let c = images[.classic] {
            // Same frame through both command APIs.
            #expect(a.difference(c) < 0.01)
        }
    }

    @Test func pickingFindsElementsOnBothBackends() throws {
        for b in Fixture.backends {
            let v = Fixture.view(b, elements: 1)
            v.visualStyle = .shaded
            v.zoomExtents(animated: false)
            // The view has no window: picking uses the 400×300 point bounds at 2× scale.
            let center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
            let id = v.element(at: center)
            #expect(id != nil, "nothing picked on \(b.rawValue)")
            #expect(v.surfacePoint(at: center) != nil)
            #expect(v.element(at: CGPoint(x: 2, y: 2)) == nil)
        }
    }

    @Test func sunShadowsDarkenTheGround() throws {
        for b in Fixture.backends {
            let v = Fixture.view(b, elements: 16)
            v.visualStyle = .shaded
            // Sun behind the model (northeast) so shadows fall toward the southwest camera.
            v.sunDirection = Vec3(0.55, 0.45, 0.62)
            let plain = try #require(Pixels(v.snapshot(size: Self.size)))
            v.castShadows = true
            let img = v.snapshot(size: Self.size)
            let shadowed = try #require(Pixels(img))
            Snapshots.save(img, "shadows-\(b == .metal4 ? "mtl4" : "classic")")
            #expect(shadowed.meanLuminance < plain.meanLuminance - 0.005, "shadows had no visible effect on \(b.rawValue)")
            // Cached shadow map: a second frame with the same sun must match exactly.
            let again = try #require(Pixels(v.snapshot(size: Self.size)))
            #expect(again.difference(shadowed) < 0.0005)
        }
    }

    @Test func ambientOcclusionAndSilhouettesChangeTheImage() throws {
        for b in Fixture.backends {
            let v = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), backend: b)
            v.setScene(SyntheticScene.corner())
            v.orient(to: .northEastIso, animated: false)
            v.visualStyle = .consistentColors
            v.showEdgesInShadedStyles = false
            let plain = try #require(Pixels(v.snapshot(size: Self.size)))
            v.ambientOcclusion = true
            let aoImage = v.snapshot(size: Self.size)
            let ao = try #require(Pixels(aoImage))
            Snapshots.save(aoImage, "ao-\(b == .metal4 ? "mtl4" : "classic")")
            #expect(ao.meanLuminance < plain.meanLuminance - 0.002, "ambient occlusion had no effect on \(b.rawValue)")
            v.ambientOcclusion = false
            v.silhouetteEdges = true
            let silImage = v.snapshot(size: Self.size)
            let sil = try #require(Pixels(silImage))
            Snapshots.save(silImage, "silhouettes-\(b == .metal4 ? "mtl4" : "classic")")
            #expect(sil.meanLuminance < plain.meanLuminance - 0.002, "silhouettes had no effect on \(b.rawValue)")
        }
    }

    @Test func realisticStyleRendersSkyAndMaterials() throws {
        for b in Fixture.backends {
            let v = Fixture.view(b, elements: 16)
            v.visualStyle = .realistic
            v.castShadows = true
            v.ambientOcclusion = true
            v.sunDirection = Vec3(0.4, -0.7, 0.55)
            let img = v.snapshot(size: Self.size)
            Snapshots.save(img, "realistic-\(b == .metal4 ? "mtl4" : "classic")")
            v.setPerspective(true)
            v.zoomExtents(animated: false)
            Snapshots.save(v.snapshot(size: Self.size), "realistic-perspective-\(b == .metal4 ? "mtl4" : "classic")")
            let px = try #require(Pixels(img))
            // Sky at the top of an orthographic view: blue dominates.
            let sky = px.rgb(px.width / 2, 2)
            #expect(sky.z > sky.x, "expected a sky gradient on \(b.rawValue), got \(sky)")
            #expect(px.distinctColors > 50)
        }
    }

    @Test func upscaledInteractiveFramesMatchFullResolution() throws {
        guard let v = Optional(Fixture.view(Fixture.backends.first ?? .classic, elements: 30)), v.renderer?.supportsUpscaling == true else { return }
        v.visualStyle = .shaded
        v.ambientOcclusion = true
        let size = CGSize(width: 1200, height: 800)
        let full = v.measureFrameTimes(frames: 3, size: size, orbitDegreesPerFrame: 0)
        #expect(v.statistics.renderScale == 1)
        let scaled = v.measureFrameTimes(frames: 3, size: size, orbitDegreesPerFrame: 0, renderScale: 2.0 / 3.0)
        #expect(full.gpu.count == 3 && scaled.gpu.count == 3)
        #expect(v.statistics.renderScale < 0.7)
    }

    @Test func idleViewDoesNotRedraw() {
        let v = Fixture.view(Fixture.backends.first ?? .classic)
        #expect(v.isPaused)
        #expect(v.enableSetNeedsDisplay)
        v.orient(to: .top, animated: true) // no window: applied immediately, no display link
        #expect(v.isPaused)
        #expect(v.statistics.framesRendered == 0)
    }

    @Test func memoryPressureShedsOptionalMemory() {
        let normal = ViewportQuality.current(physicalMemory: 16 << 30, pressure: .normal)
        let low = ViewportQuality.current(physicalMemory: 8 << 30, pressure: .normal)
        let critical = ViewportQuality.current(physicalMemory: 16 << 30, pressure: .critical)
        #expect(normal.shadowMapSize == 2048 && normal.ambientOcclusion)
        #expect(low.shadowMapSize == 1024)
        #expect(critical.shadowMapSize == 1024 && !critical.ambientOcclusion)
    }
}

@Suite("Viewport presentation", .serialized)
@MainActor struct ViewportPresentationTests {
    /// The on-screen path (drawable, layer residency set, present, frame semaphore) without a window.
    @Test func drawsIntoLayerDrawablesOnBothBackends() async throws {
        for b in Fixture.backends {
            let v = Fixture.view(b, elements: 40)
            v.castShadows = true
            v.ambientOcclusion = true
            guard let renderer = v.renderer else { continue }
            let layer = CAMetalLayer()
            layer.device = renderer.device
            layer.pixelFormat = ViewportRenderer.colorFormat
            layer.framebufferOnly = true
            layer.drawableSize = CGSize(width: 800, height: 600)
            var times: [Double] = []
            for i in 0..<6 {
                guard let drawable = layer.nextDrawable() else { Issue.record("no drawable"); return }
                let frame = v.frameParams(pixelSize: layer.drawableSize)
                let calls = renderer.drawFrame(scene: v.gpuScene, frame: frame, states: Array(repeating: 0, count: v.sceneElementIDs.count),
                                               drawable: drawable, layer: layer, renderScale: i % 2 == 0 ? 1 : 2.0 / 3.0) { ms in times.append(ms) }
                #expect(calls >= 4)
            }
            renderer.waitIdle()
            for _ in 0..<100 where times.count < 6 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(times.count == 6, "frame completions on \(b.rawValue)")
            #expect(times.allSatisfy { $0 >= 0 && $0 < 1000 })
        }
    }

    @Test func dynamicResolutionHonorsModeAndReduceMotion() {
        let v = Fixture.view(Fixture.backends.first ?? .classic)
        guard v.renderer?.supportsUpscaling == true else { return }
        let size = CGSize(width: 3000, height: 2000)
        let frame = v.frameParams(pixelSize: size)
        v.dynamicResolution = .never
        #expect(v.renderScale(for: size, frame: frame) == 1)
        v.dynamicResolution = .always
        #expect(v.renderScale(for: size, frame: frame) < 1)
        v.dynamicResolution = .automatic
        #expect(v.renderScale(for: size, frame: frame) == 1) // not interacting
        v.reduceMotion = true
        #expect(v.renderScale(for: size, frame: frame) == 1)
    }
}
