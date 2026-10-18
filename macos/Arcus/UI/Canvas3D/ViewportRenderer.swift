import Foundation
import Metal
import QuartzCore
import simd
import CoreGraphics
import ArcusGeometry
import ArcusDomain

/// Sun shadow request for one frame.
struct ShadowRequest {
    /// Relative-world → shadow clip.
    var matrix: simd_float4x4
    /// Changes whenever the shadow map content would change (scene, light, section box, size).
    var key: ShadowKey
}

struct ShadowKey: Equatable {
    var sceneSignature: Int
    var light: SIMD3<Int32>
    var sectionBox: Box3?
    var size: Int
}

/// Everything one frame needs besides the scene buffers.
@MainActor struct FrameParams {
    var uniforms: ViewportUniforms
    var style: VisualStyle
    var showEdges: Bool
    var overlay: [OverlayVertex]
    var shadow: ShadowRequest?
    /// Post-processing (ambient occlusion / silhouettes); `flags == 0` renders straight to the output.
    var post = PostUniforms()
}

/// Result of a GPU pick.
nonisolated struct PickResult: Sendable {
    /// Element index in the GPU scene, nil for background.
    var elementIndex: Int?
    /// World position of the surface under the cursor (faces only).
    var position: SIMD3<Double>?
}

/// Quality knobs derived from the machine and current memory pressure.
nonisolated struct ViewportQuality: Equatable {
    var shadowMapSize: Int
    var ambientOcclusion: Bool
    /// Render scale MetalFX upscales from while the camera moves.
    var interactiveScale: Double

    static func current(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
                        pressure: MemoryPressureLevel = .normal) -> ViewportQuality {
        let lowMemory = physicalMemory <= 8 << 30
        var q = ViewportQuality(shadowMapSize: lowMemory ? 1024 : 2048, ambientOcclusion: true, interactiveScale: 2.0 / 3.0)
        switch pressure {
        case .normal: break
        case .warning: q.shadowMapSize = 1024
        case .critical: q.shadowMapSize = 1024; q.ambientOcclusion = false
        }
        return q
    }
}

/// Owns the GPU context of one viewport and encodes its passes (on-screen, offscreen snapshot, benchmark and ID
/// picking) through a single code path for both command APIs:
///
///     [shadow map, cached] → scene pass (4× MSAA, memoryless) → [ambient occlusion] → [MetalFX upscale] → composite + overlay
///
/// Without post effects the scene pass resolves straight into the drawable and draws the overlay itself.
@MainActor final class ViewportRenderer {
    let device: any MTLDevice
    let backend: ViewportBackendKind
    let pipelines: ViewportPipelines
    var sampleCount: Int { pipelines.sampleCount }
    static let colorFormat: MTLPixelFormat = ViewportPipelines.colorFormat
    static let depthFormat: MTLPixelFormat = ViewportPipelines.depthFormat
    static let maxFramesInFlight = 3
    /// Full-resolution GPU frame time above which interactive frames render at reduced resolution (≈ 2/3 of a
    /// 120 Hz frame, leaving headroom for the compositor).
    static let upscaleThresholdMilliseconds = 5.5
    /// Limits CPU run-ahead to `maxFramesInFlight` frames (per-frame arenas are reused round-robin).
    let inFlight = DispatchSemaphore(value: ViewportRenderer.maxFramesInFlight)

    /// Scene buffers, render targets and arenas; attached to the command queue, so nothing is tracked per encoder.
    let residency: (any MTLResidencySet)?
    let uploader: SceneUploader
    /// Memoryless MSAA/depth attachments (Apple GPUs: they live only in tile memory).
    let memoryless: Bool
    /// Depth resolve is needed for ambient occlusion and silhouettes.
    let supportsDepthResolve: Bool
    var quality = ViewportQuality.current()

    private let event: any MTLSharedEvent
    private var serial: UInt64 = 0
    private let queue: (any MTLCommandQueue)?
    private let queue4: (any MTL4CommandQueue)?
    private let table: (any MTL4ArgumentTable)?
    private var allocators: [(allocator: any MTL4CommandAllocator, serial: UInt64)] = []
    private var attachedLayerSets = Set<ObjectIdentifier>()

    private var frameArenas: [FrameArena] = []
    private var frameIndex = 0
    private var syncArena: FrameArena!
    private var hoverArena: FrameArena!
    private var screenTargets: RenderTargets?
    private var offscreenTargets: RenderTargets?
    private var shadowMap: (any MTLTexture)?
    private var shadowKey: ShadowKey?
    private let dummyDepth: (any MTLTexture)?
    private var upscaler: ViewportUpscaler?
    private var upscalerUnavailable = false
    private let fence: (any MTLFence)?
    private var syncPick: PickTargets?
    private var hoverPick: PickTargets?
    private var retired: [(serial: UInt64, objects: [AnyObject], allocations: [any MTLAllocation])] = []

    private(set) var lastDrawCalls = 0
    private(set) var lastRenderScale = 1.0
    /// Render-target bytes (excluding the output texture) held during the last benchmark.
    private(set) var lastBenchmarkTargetBytes = 0

    /// Bytes of render targets that take memory (memoryless attachments are free).
    var renderTargetBytes: Int {
        (screenTargets?.bytes ?? 0) + (offscreenTargets?.bytes ?? 0) + (shadowMap?.allocatedSize ?? 0)
    }
    var supportsUpscaling: Bool { !upscalerUnavailable && supportsDepthResolve }

    init?(device: any MTLDevice, sampleCount: Int? = nil, backend requested: ViewportBackendKind? = nil) {
        let backend = requested ?? .preferred(for: device)
        let samples = sampleCount ?? ViewportPipelines.preferredSampleCount(device)
        guard let pipelines = ViewportPipelines.shared(device: device, backend: backend, sampleCount: samples),
              let event = device.makeSharedEvent() else { return nil }
        self.device = device
        self.backend = backend
        self.pipelines = pipelines
        self.event = event
        uploader = SceneUploader(device: device)
        memoryless = device.hasUnifiedMemory && device.supportsFamily(.apple2)
        supportsDepthResolve = device.supportsFamily(.apple3) || device.supportsFamily(.mac2)
        let rd = MTLResidencySetDescriptor()
        rd.label = "Arcus viewport"
        rd.initialCapacity = 32
        residency = try? device.makeResidencySet(descriptor: rd)
        switch backend {
        case .classic:
            guard let q = device.makeCommandQueue() else { return nil }
            q.label = "Arcus Viewport"
            if let residency { q.addResidencySet(residency) }
            queue = q; queue4 = nil; table = nil
        case .metal4:
            let qd = MTL4CommandQueueDescriptor()
            qd.label = "Arcus Viewport (Metal 4)"
            let td = MTL4ArgumentTableDescriptor()
            td.maxBufferBindCount = 4
            td.maxTextureBindCount = 3
            td.label = "Arcus viewport bindings"
            guard let residency, let q = try? device.makeMTL4CommandQueue(descriptor: qd),
                  let t = try? device.makeArgumentTable(descriptor: td) else { return nil }
            q.addResidencySet(residency)
            queue = nil; queue4 = q; table = t
        }
        fence = device.makeFence()
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ViewportRenderer.depthFormat, width: 1, height: 1, mipmapped: false)
        dd.usage = [.shaderRead, .renderTarget]
        dd.storageMode = .private
        dummyDepth = device.makeTexture(descriptor: dd)
        frameArenas = (0..<ViewportRenderer.maxFramesInFlight).map { FrameArena(renderer: self, label: "Viewport frame arena \($0)") }
        syncArena = FrameArena(renderer: self, label: "Viewport sync arena")
        hoverArena = FrameArena(renderer: self, label: "Viewport hover arena")
        if let dummyDepth { makeResident([dummyDepth]) }
        residency?.requestResidency()
    }

    // MARK: Residency and deferred release

    func makeResident(_ allocations: [any MTLAllocation]) {
        guard let residency, !allocations.isEmpty else { return }
        residency.addAllocations(allocations)
        residency.commit()
    }

    /// Keeps `objects` alive (and resident) until every command buffer committed so far has completed.
    func retire(_ objects: [AnyObject], allocations: [any MTLAllocation]) {
        guard !objects.isEmpty || !allocations.isEmpty else { return }
        retired.append((serial, objects, allocations))
    }

    private func collectRetired() {
        guard !retired.isEmpty else { return }
        let done = event.signaledValue
        var removed = false
        retired.removeAll { r in
            guard r.serial <= done else { return false }
            if let residency, !r.allocations.isEmpty { residency.removeAllocations(r.allocations); removed = true }
            return true
        }
        if removed { residency?.commit() }
    }

    /// Blocks until the GPU finished all submitted work (scene replacement, teardown).
    func waitIdle() {
        if serial > 0 { _ = event.wait(untilSignaledValue: serial, timeoutMS: 10_000) }
        collectRetired()
    }

    private var isResident = true

    /// Lets the OS page out viewport memory while the view is off screen (any later GPU work restores residency).
    func setResident(_ resident: Bool) {
        guard resident != isResident else { return }
        if resident { waitIdle() }
        isResident = resident
        if resident { residency?.requestResidency() } else { waitIdle(); residency?.endResidency() }
    }

    /// Frees size-dependent targets, the shadow map and the upscaler (memory pressure, hidden view).
    func releaseTransientResources() {
        for t in [screenTargets, offscreenTargets].compactMap({ $0 }) { retire([t], allocations: t.allocations) }
        screenTargets = nil; offscreenTargets = nil
        if let s = shadowMap { retire([s], allocations: [s]) }
        shadowMap = nil; shadowKey = nil
        if let u = upscaler { retire([u], allocations: []) }
        upscaler = nil
    }

    // MARK: Scene

    func upload(_ scene: Viewport3DScene) -> GPUScene {
        // The pool drains the upload command buffers now, so the staging buffers they retain are freed immediately.
        let s = autoreleasepool { GPUScene(scene: scene, device: device, uploader: uploader) }
        makeResident(s.allocations)
        return s
    }

    func release(_ scene: GPUScene) {
        retire([scene], allocations: scene.allocations)
        if shadowKey?.sceneSignature == scene.signature { shadowKey = nil }
    }

    // MARK: Commands

    private func makeCommands() -> (any ViewportCommands)? {
        if !isResident { setResident(true) }
        serial += 1
        switch backend {
        case .classic:
            guard let cb = queue?.makeCommandBuffer() else { serial -= 1; return nil }
            return ClassicCommands(cb: cb, event: event, serial: serial)
        case .metal4:
            guard let queue4, let table, let residency, let cb = device.makeCommandBuffer() else { serial -= 1; return nil }
            let done = event.signaledValue
            let allocator: any MTL4CommandAllocator
            if let i = allocators.firstIndex(where: { $0.serial <= done }) {
                allocator = allocators[i].allocator
                allocator.reset()
                allocators[i].serial = serial
            } else {
                guard let a = device.makeCommandAllocator() else { serial -= 1; return nil }
                allocator = a
                allocators.append((a, serial))
            }
            return Metal4Commands(queue: queue4, cb: cb, allocator: allocator, table: table, residency: residency, event: event, serial: serial)
        }
    }

    // MARK: Frames

    /// Encodes and presents one on-screen frame. `completion` gets the GPU time (ms) on the main actor.
    @discardableResult
    func drawFrame(scene: GPUScene?, frame: FrameParams, states: [UInt8], drawable: any CAMetalDrawable, layer: CAMetalLayer?,
                   renderScale: Double, completion: @escaping @MainActor (Double) -> Void) -> Int {
        inFlight.wait()
        collectRetired()
        if backend == .metal4, let layer, let queue4 {
            let set = layer.residencySet
            if attachedLayerSets.insert(ObjectIdentifier(set)).inserted { queue4.addResidencySet(set) }
        }
        frameIndex = (frameIndex + 1) % frameArenas.count
        let sem = SemaphoreBox(inFlight)
        guard let cmd = makeCommands() else { inFlight.signal(); return 0 }
        let calls = encodeFrame(cmd, arena: frameArenas[frameIndex], scene: scene, frame: frame, states: states,
                                output: drawable.texture, offscreen: false, renderScale: renderScale)
        cmd.commit(present: drawable) { start, end in
            sem.semaphore.signal()
            let ms = (end - start) * 1000
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(ms) } }
        }
        lastDrawCalls = calls
        return calls
    }

    private func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, usage: MTLTextureUsage, storage: MTLStorageMode, samples: Int = 1, label: String) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(1, w), height: max(1, h), mipmapped: false)
        d.usage = usage
        d.storageMode = storage
        if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples }
        let t = device.makeTexture(descriptor: d)
        t?.label = label
        return t
    }

    /// Size-dependent attachments, reallocated only when the configuration changes.
    private func targets(offscreen: Bool, output: (Int, Int), render: (Int, Int), post: Bool, occlusion: Bool, upscaled: Bool) -> RenderTargets? {
        let config = RenderTargets.Config(output: SIMD2(output.0, output.1), render: SIMD2(render.0, render.1), post: post, occlusion: occlusion, upscaled: upscaled)
        if let t = offscreen ? offscreenTargets : screenTargets, t.config == config { return t }
        if let old = offscreen ? offscreenTargets : screenTargets { retire([old], allocations: old.allocations) }
        let s = sampleCount
        let t = RenderTargets(config: config)
        let transient: MTLStorageMode = memoryless ? .memoryless : .private
        let (rw, rh) = render
        if s > 1 {
            t.msaaColor = texture(ViewportRenderer.colorFormat, rw, rh, usage: .renderTarget, storage: transient, samples: s, label: "Viewport MSAA color")
        }
        if post {
            t.depth = texture(ViewportRenderer.depthFormat, rw, rh, usage: .renderTarget, storage: transient, samples: s, label: "Viewport MSAA depth")
            if s == 1 { t.depth = nil }
            var colorUsage: MTLTextureUsage = [.renderTarget, .shaderRead]
            if upscaled, let u = upscaler { colorUsage.formUnion(u.colorUsage) }
            t.sceneColor = texture(ViewportRenderer.colorFormat, rw, rh, usage: colorUsage, storage: .private, label: "Viewport scene color")
            t.sceneDepth = texture(ViewportRenderer.depthFormat, rw, rh, usage: [.renderTarget, .shaderRead], storage: .private, label: "Viewport scene depth")
            if occlusion {
                t.occlusion = texture(ViewportPipelines.occlusionFormat, (rw + 1) / 2, (rh + 1) / 2, usage: [.renderTarget, .shaderRead], storage: .private, label: "Viewport ambient occlusion")
            }
            if upscaled, let u = upscaler {
                t.upscaled = texture(ViewportRenderer.colorFormat, output.0, output.1, usage: u.outputUsage.union(.shaderRead), storage: .private, label: "Viewport upscaled color")
            }
            guard t.sceneColor != nil, t.sceneDepth != nil, !occlusion || t.occlusion != nil, !upscaled || t.upscaled != nil else { return nil }
        } else {
            t.depth = texture(ViewportRenderer.depthFormat, rw, rh, usage: .renderTarget, storage: transient, samples: s, label: "Viewport depth")
            guard t.depth != nil else { return nil }
        }
        if s > 1 && t.msaaColor == nil { return nil }
        makeResident(t.allocations)
        if offscreen { offscreenTargets = t } else { screenTargets = t }
        return t
    }

    private func ensureShadowMap(size: Int) -> (any MTLTexture)? {
        if let s = shadowMap, s.width == size { return s }
        if let s = shadowMap { retire([s], allocations: [s]) }
        shadowKey = nil
        shadowMap = texture(ViewportRenderer.depthFormat, size, size, usage: [.renderTarget, .shaderRead], storage: .private, label: "Viewport sun shadow map")
        if let s = shadowMap { makeResident([s]) }
        return shadowMap
    }

    private func ensureUpscaler(input: (Int, Int), output: (Int, Int)) -> ViewportUpscaler? {
        if upscalerUnavailable { return nil }
        if let u = upscaler, u.matches(input: input, output: output) { return u }
        if let u = upscaler { retire([u], allocations: []) }
        upscaler = ViewportUpscaler(device: device, compiler: pipelines.compiler, input: input, output: output, format: ViewportRenderer.colorFormat)
        if upscaler == nil { upscalerUnavailable = true }
        return upscaler
    }

    /// Encodes one complete frame into `output`. Returns the number of draw calls.
    func encodeFrame(_ cmd: any ViewportCommands, arena: FrameArena, scene: GPUScene?, frame: FrameParams, states: [UInt8],
                     output: any MTLTexture, offscreen: Bool, renderScale requestedScale: Double) -> Int {
        var calls = 0
        let ow = output.width, oh = output.height
        let wantsAO = frame.post.flags & PostUniforms.flagAO != 0 && quality.ambientOcclusion && supportsDepthResolve
        let wantsSilhouettes = frame.post.flags & PostUniforms.flagSilhouettes != 0 && supportsDepthResolve
        var scale = 1.0
        var up: ViewportUpscaler?
        if requestedScale < 0.999, supportsDepthResolve {
            let rw = max(1, Int((Double(ow) * requestedScale).rounded())), rh = max(1, Int((Double(oh) * requestedScale).rounded()))
            if let u = ensureUpscaler(input: (rw, rh), output: (ow, oh)) { up = u; scale = Double(rw) / Double(ow) }
        }
        let rw = up?.inputWidth ?? ow, rh = up?.inputHeight ?? oh
        let post = wantsAO || wantsSilhouettes || up != nil
        guard let t = targets(offscreen: offscreen, output: (ow, oh), render: (rw, rh), post: post, occlusion: wantsAO, upscaled: up != nil) else { return 0 }
        lastRenderScale = scale

        let overlayBytes = frame.overlay.count * MemoryLayout<OverlayVertex>.stride
        arena.begin(capacity: 4 * FrameArena.aligned(MemoryLayout<ViewportUniforms>.stride) + FrameArena.aligned(MemoryLayout<PostUniforms>.stride)
                    + FrameArena.aligned(max(states.count, 16)) + FrameArena.aligned(overlayBytes) + 1024)
        guard let ab = arena.buffer else { return 0 }
        let fullU = frame.uniforms
        var renderU = fullU
        if up != nil {
            renderU.viewport = SIMD2(Float(rw), Float(rh))
            renderU.edgeWidth *= Float(scale)
        }
        let fullOff = arena.push(fullU)
        let renderOff = up != nil ? arena.push(renderU) : fullOff
        let statesOff = arena.push(bytes: states, minimum: 16)
        let overlayOff = frame.overlay.isEmpty ? 0 : arena.push(bytes: frame.overlay)

        // Sun shadow map: rendered only when its key changes (scene, sun, section box, size).
        var shadowTexture = dummyDepth
        if let req = frame.shadow, let scene, let vb = scene.vertexBuffer, let map = ensureShadowMap(size: req.key.size) {
            if shadowKey != req.key {
                let pass = PassDescription(label: "Sun shadow map", depth: PassAttachment(texture: map, load: .clear, store: .store, clearDepth: 1))
                if let enc = cmd.renderPass(pass, dependsOnEarlierWork: true) {
                    enc.setPipeline(pipelines.shadow)
                    enc.setDepthStencil(pipelines.shadowDepth)
                    enc.setCullMode(.none)
                    enc.setDepthBias(2, slope: 2.5, clamp: 0)
                    enc.setBuffer(vb, offset: 0, index: 0)
                    enc.setBuffer(ab, offset: renderOff, index: 1)
                    if let ib = scene.opaqueIndexBuffer {
                        enc.drawIndexed(indexCount: scene.opaqueIndexCount, indexBuffer: ib)
                        calls += 1
                    }
                    enc.end()
                    shadowKey = req.key
                }
            }
            shadowTexture = map
        }

        // Scene pass.
        let s = sampleCount
        var main = PassDescription(label: "Viewport scene")
        if post, let sceneColor = t.sceneColor, let sceneDepth = t.sceneDepth {
            main.colors = [s > 1 ? PassAttachment(texture: t.msaaColor!, resolve: sceneColor, load: .clear, store: .multisampleResolve)
                                 : PassAttachment(texture: sceneColor, load: .clear, store: .store)]
            main.depth = s > 1 ? PassAttachment(texture: t.depth!, resolve: sceneDepth, load: .clear, store: .multisampleResolve, clearDepth: 0)
                               : PassAttachment(texture: sceneDepth, load: .clear, store: .store, clearDepth: 0)
        } else {
            main.colors = [s > 1 ? PassAttachment(texture: t.msaaColor!, resolve: output, load: .clear, store: .multisampleResolve)
                                 : PassAttachment(texture: output, load: .clear, store: .store)]
            main.depth = PassAttachment(texture: t.depth!, load: .clear, store: .dontCare, clearDepth: 0)
        }
        guard let enc = cmd.renderPass(main, dependsOnEarlierWork: true) else { return calls }
        calls += encodeScene(enc, scene: scene, frame: frame, arena: ab, uniforms: renderOff, states: statesOff, shadow: shadowTexture)
        if !post {
            calls += encodeOverlay(enc, pipeline: pipelines.overlay, frame: frame, arena: ab, uniforms: fullOff, vertices: overlayOff)
        } else if up != nil, let fence {
            enc.signal(fence)
        }
        enc.end()

        if post, let sceneColor = t.sceneColor, let sceneDepth = t.sceneDepth {
            var pu = frame.post
            if !wantsAO { pu.flags &= ~PostUniforms.flagAO }
            if !wantsSilhouettes { pu.flags &= ~PostUniforms.flagSilhouettes }
            let aoW = t.occlusion?.width ?? 1, aoH = t.occlusion?.height ?? 1
            pu.sizes = SIMD4(Float(rw), Float(rh), Float(aoW), Float(aoH))
            pu.silhouette.x *= Float(scale)
            pu.ao.w *= Float(scale)
            let postOff = arena.push(pu)
            if wantsAO, let occ = t.occlusion,
               let e = cmd.renderPass(PassDescription(label: "Ambient occlusion", colors: [PassAttachment(texture: occ, load: .dontCare, store: .store)]), dependsOnEarlierWork: true) {
                e.setPipeline(pipelines.occlusion)
                e.setDepthStencil(nil)
                e.setCullMode(.none)
                e.setBuffer(ab, offset: postOff, index: 0)
                e.setTexture(sceneDepth, index: 1)
                e.draw(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
                e.end()
                calls += 1
            }
            var color = sceneColor
            if let up, let upscaled = t.upscaled, let fence {
                cmd.upscale(up, from: sceneColor, to: upscaled, fence: fence)
                color = upscaled
            }
            let composite = PassDescription(label: "Viewport composite", colors: [PassAttachment(texture: output, load: .dontCare, store: .store)])
            if let e = cmd.renderPass(composite, dependsOnEarlierWork: true) {
                e.setPipeline(pipelines.composite)
                e.setDepthStencil(nil)
                e.setCullMode(.none)
                e.setBuffer(ab, offset: postOff, index: 0)
                e.setTexture(color, index: 0)
                e.setTexture(sceneDepth, index: 1)
                e.setTexture(t.occlusion ?? color, index: 2)
                e.draw(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
                calls += 1
                calls += encodeOverlay(e, pipeline: pipelines.overlaySingle, frame: frame, arena: ab, uniforms: fullOff, vertices: overlayOff)
                e.end()
            }
        }
        return calls
    }

    /// Background, faces and edges.
    private func encodeScene(_ enc: any ViewportRenderEncoder, scene: GPUScene?, frame: FrameParams, arena: any MTLBuffer,
                             uniforms: Int, states: Int, shadow: (any MTLTexture)?) -> Int {
        var calls = 0
        enc.setCullMode(.none)
        enc.setPipeline(pipelines.background)
        enc.setDepthStencil(pipelines.depthAlways)
        enc.setBuffer(arena, offset: uniforms, index: 1)
        enc.draw(.triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        calls += 1

        guard let scene, let vb = scene.vertexBuffer else { return calls }
        enc.setBuffer(vb, offset: 0, index: 0)
        enc.setBuffer(arena, offset: states, index: 2)
        if let eb = scene.edgeBuffer { enc.setBuffer(eb, offset: 0, index: 3) }
        if let shadow { enc.setTexture(shadow, index: 0) }
        let style = frame.style
        let transparentStyle = style == .transparent
        let drawFaces = style != .wireframe
        let drawEdges = scene.edgeCount > 0 && (style == .hiddenLine || style == .wireframe || style == .transparent || frame.showEdges)

        if drawFaces && !transparentStyle, let ib = scene.opaqueIndexBuffer {
            enc.setPipeline(pipelines.faceOpaque)
            enc.setDepthStencil(pipelines.depthWrite)
            // Push faces slightly away (reversed-Z: negative) so coplanar edges win without z-fighting.
            enc.setDepthBias(-2, slope: -2.5, clamp: 0)
            enc.drawIndexed(indexCount: scene.opaqueIndexCount, indexBuffer: ib)
            enc.setDepthBias(0, slope: 0, clamp: 0)
            calls += 1
        }
        func edges() {
            enc.setPipeline(pipelines.edge)
            enc.setDepthStencil(style == .wireframe ? pipelines.depthAlways : pipelines.depthTest)
            enc.draw(.triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.edgeCount)
            calls += 1
        }
        if drawEdges && !transparentStyle { edges() }
        if drawFaces {
            enc.setPipeline(pipelines.faceBlend)
            enc.setDepthStencil(pipelines.depthTest)
            if transparentStyle, let ib = scene.opaqueIndexBuffer {
                enc.drawIndexed(indexCount: scene.opaqueIndexCount, indexBuffer: ib)
                calls += 1
            }
            if let tb = scene.transparentIndexBuffer {
                enc.drawIndexed(indexCount: scene.transparentIndexCount, indexBuffer: tb)
                calls += 1
            }
        }
        if drawEdges && transparentStyle { edges() }
        return calls
    }

    private func encodeOverlay(_ enc: any ViewportRenderEncoder, pipeline: any MTLRenderPipelineState, frame: FrameParams,
                               arena: any MTLBuffer, uniforms: Int, vertices: Int) -> Int {
        guard !frame.overlay.isEmpty else { return 0 }
        enc.setPipeline(pipeline)
        enc.setDepthStencil(pipeline === pipelines.overlaySingle ? nil : pipelines.depthAlways)
        enc.setBuffer(arena, offset: vertices, index: 0)
        enc.setBuffer(arena, offset: uniforms, index: 1)
        enc.draw(.triangle, vertexStart: 0, vertexCount: frame.overlay.count, instanceCount: 1)
        return 1
    }

    // MARK: Offscreen rendering

    /// Renders one frame offscreen and returns the image (sRGB).
    func renderImage(width: Int, height: Int, scene: GPUScene?, frame: FrameParams, states: [UInt8]) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        collectRetired()
        guard let out = texture(ViewportRenderer.colorFormat, width, height, usage: [.renderTarget], storage: .shared, label: "Viewport snapshot"),
              let cmd = makeCommands() else { return nil }
        makeResident([out])
        lastDrawCalls = encodeFrame(cmd, arena: syncArena, scene: scene, frame: frame, states: states, output: out, offscreen: true, renderScale: 1)
        cmd.commit(present: nil, completion: nil)
        cmd.waitUntilCompleted()
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        data.withUnsafeMutableBytes { raw in
            out.getBytes(raw.baseAddress!, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        retire([out], allocations: [out])
        if let t = offscreenTargets { retire([t], allocations: t.allocations); offscreenTargets = nil }
        collectRetired()
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Renders `frames` offscreen frames through the full frame path (no readback) and returns GPU and CPU-encode
    /// milliseconds per frame.
    func benchmark(width: Int, height: Int, scene: GPUScene?, frames: Int, states: [UInt8], renderScale: Double = 1,
                   frameAt: (Int) -> FrameParams) -> (gpu: [Double], cpu: [Double]) {
        collectRetired()
        guard let out = texture(ViewportRenderer.colorFormat, width, height, usage: [.renderTarget], storage: .private, label: "Viewport benchmark output") else { return ([], []) }
        makeResident([out])
        var gpu: [Double] = [], cpu: [Double] = []
        let timing = TimingBox()
        for i in 0..<frames {
            let ok: Bool = autoreleasepool {
                let t0 = CFAbsoluteTimeGetCurrent()
                guard let cmd = makeCommands() else { return false }
                lastDrawCalls = encodeFrame(cmd, arena: syncArena, scene: scene, frame: frameAt(i), states: states, output: out, offscreen: true, renderScale: renderScale)
                cmd.commit(present: nil) { start, end in timing.finish((end - start) * 1000) }
                cpu.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                gpu.append(timing.wait())
                return true
            }
            if !ok { break }
        }
        lastBenchmarkTargetBytes = (offscreenTargets?.bytes ?? 0) + (shadowMap?.allocatedSize ?? 0)
        retire([out], allocations: [out])
        if let t = offscreenTargets { retire([t], allocations: t.allocations); offscreenTargets = nil }
        waitIdle()
        return (gpu, cpu)
    }

    // MARK: Picking

    /// Pick matrix zooming the pick region (centered at `pixel`, top-left origin) to the full clip space.
    static func pickMatrix(pixel: CGPoint, viewport: CGSize, regionSize: Int) -> simd_float4x4 {
        let w = Float(viewport.width), h = Float(viewport.height), s = Float(regionSize)
        let cx = Float(pixel.x) / w * 2 - 1
        let cy = 1 - Float(pixel.y) / h * 2
        let sx = w / s, sy = h / s
        return simd_float4x4(columns: (
            SIMD4(sx, 0, 0, 0),
            SIMD4(0, sy, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(-cx * sx, -cy * sy, 0, 1)))
    }

    static let pickRadius = 4

    private func pickTargets(hover: Bool) -> PickTargets? {
        if let t = hover ? hoverPick : syncPick { return t }
        guard let t = PickTargets(renderer: self, memoryless: memoryless) else { return nil }
        makeResident(t.allocations)
        if hover { hoverPick = t } else { syncPick = t }
        return t
    }

    /// Encodes an ID pick at `pixel` (drawable pixels, top-left origin). `completion` runs on the main actor.
    func pick(at pixel: CGPoint, viewport: CGSize, scene: GPUScene, uniforms: ViewportUniforms, style: VisualStyle,
              states: [UInt8], wait: Bool, completion: @escaping @MainActor (PickResult) -> Void) {
        collectRetired()
        guard let targets = pickTargets(hover: !wait), let vb = scene.vertexBuffer else { completion(PickResult()); return }
        let arena = wait ? syncArena! : hoverArena!
        let n = ViewportRenderer.pickRadius * 2 + 1
        arena.begin(capacity: 2 * FrameArena.aligned(MemoryLayout<ViewportUniforms>.stride) + FrameArena.aligned(max(states.count, 16)) + 512)
        guard let ab = arena.buffer, let cmd = makeCommands() else { completion(PickResult()); return }
        var u = uniforms
        u.pick = ViewportRenderer.pickMatrix(pixel: pixel, viewport: viewport, regionSize: n)
        u.flags &= ~ViewportUniforms.flagShadows
        let uOff = arena.push(u)
        let sOff = arena.push(bytes: states, minimum: 16)
        let pass = PassDescription(label: "Viewport pick", colors: [
            PassAttachment(texture: targets.id, load: .clear, store: .store, clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)),
            PassAttachment(texture: targets.position, load: .clear, store: .store, clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)),
        ], depth: PassAttachment(texture: targets.depth, load: .clear, store: .dontCare, clearDepth: 0))
        guard let enc = cmd.renderPass(pass, dependsOnEarlierWork: true) else { cmd.commit(present: nil, completion: nil); completion(PickResult()); return }
        enc.setCullMode(.none)
        enc.setBuffer(vb, offset: 0, index: 0)
        enc.setBuffer(ab, offset: uOff, index: 1)
        enc.setBuffer(ab, offset: sOff, index: 2)
        if let d = dummyDepth { enc.setTexture(d, index: 0) }
        enc.setPipeline(pipelines.facePick)
        enc.setDepthStencil(pipelines.depthWrite)
        if let ib = scene.opaqueIndexBuffer { enc.drawIndexed(indexCount: scene.opaqueIndexCount, indexBuffer: ib) }
        if let tb = scene.transparentIndexBuffer { enc.drawIndexed(indexCount: scene.transparentIndexCount, indexBuffer: tb) }
        if style == .wireframe, let eb = scene.edgeBuffer, scene.edgeCount > 0 {
            // Wireframe: visible edges take precedence (see-through), widened for an easier target.
            var ue = u
            ue.edgeWidth = max(ue.edgeWidth, 5)
            enc.setBuffer(ab, offset: arena.push(ue), index: 1)
            enc.setBuffer(eb, offset: 0, index: 3)
            enc.setPipeline(pipelines.edgePick)
            enc.setDepthStencil(pipelines.depthAlways)
            enc.draw(.triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.edgeCount)
        }
        enc.end()
        let size = MTLSize(width: n, height: n, depth: 1)
        cmd.copy(from: targets.id, size: size, to: targets.readback, offset: 0, bytesPerRow: n * 4)
        cmd.copy(from: targets.position, size: size, to: targets.readback, offset: PickTargets.positionOffset, bytesPerRow: n * 16)
        let origin = scene.origin
        let box = ReadbackBox(targets.readback)
        if wait {
            cmd.commit(present: nil, completion: nil)
            cmd.waitUntilCompleted()
            completion(ViewportRenderer.decodePick(box.buffer, n: n, origin: origin))
        } else {
            cmd.commit(present: nil) { _, _ in
                let r = ViewportRenderer.decodePick(box.buffer, n: n, origin: origin)
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(r) } }
            }
        }
    }

    nonisolated static func decodePick(_ b: any MTLBuffer, n: Int, origin: SIMD3<Double>) -> PickResult {
        let ids = b.contents().bindMemory(to: UInt32.self, capacity: n * n)
        let pos = (b.contents() + PickTargets.positionOffset).bindMemory(to: SIMD4<Float>.self, capacity: n * n)
        let c = n / 2
        var best: Int?
        var bestD = Int.max
        for y in 0..<n {
            for x in 0..<n where ids[y * n + x] != 0 {
                let d = (x - c) * (x - c) + (y - c) * (y - c)
                if d < bestD { bestD = d; best = y * n + x }
            }
        }
        guard let i = best else { return PickResult() }
        var r = PickResult(elementIndex: Int(ids[i]) - 1, position: nil)
        // Prefer the exact center position; otherwise the chosen pixel's.
        for k in [c * n + c, i] where pos[k].w > 0.5 {
            let p = pos[k]
            r.position = origin + SIMD3(Double(p.x), Double(p.y), Double(p.z))
            break
        }
        return r
    }
}

// MARK: - Supporting types

/// Attachments for one output configuration.
@MainActor final class RenderTargets {
    struct Config: Equatable {
        var output: SIMD2<Int>
        var render: SIMD2<Int>
        var post: Bool
        var occlusion: Bool
        var upscaled: Bool
    }
    let config: Config
    var msaaColor: (any MTLTexture)?
    /// Scene-pass depth (MSAA, memoryless on Apple GPUs); nil when single-sampled post uses `sceneDepth` directly.
    var depth: (any MTLTexture)?
    var sceneColor: (any MTLTexture)?
    var sceneDepth: (any MTLTexture)?
    var occlusion: (any MTLTexture)?
    var upscaled: (any MTLTexture)?

    init(config: Config) { self.config = config }

    var textures: [any MTLTexture] { [msaaColor, depth, sceneColor, sceneDepth, occlusion, upscaled].compactMap { $0 } }
    /// Residency sets reject memoryless textures (they have no memory to make resident).
    var allocations: [any MTLAllocation] { textures.filter { $0.storageMode != .memoryless } }
    var bytes: Int { textures.reduce(0) { $0 + ($1.storageMode == .memoryless ? 0 : $1.allocatedSize) } }
}

/// Per-frame upload arena: uniforms, element states and overlay vertices in one shared, untracked buffer.
@MainActor final class FrameArena {
    nonisolated static let alignment = 256
    static func aligned(_ n: Int) -> Int { (n + alignment - 1) & ~(alignment - 1) }

    private unowned let renderer: ViewportRenderer
    private let label: String
    private(set) var buffer: (any MTLBuffer)?
    private var offset = 0

    init(renderer: ViewportRenderer, label: String) { self.renderer = renderer; self.label = label }

    /// Starts a new frame, growing the buffer (the old one is retired) when `capacity` does not fit.
    func begin(capacity: Int) {
        offset = 0
        if let b = buffer, b.length >= capacity { return }
        if let b = buffer { renderer.retire([b], allocations: [b]) }
        var length = 16 << 10
        while length < capacity { length *= 2 }
        buffer = renderer.device.makeBuffer(length: length, options: [.storageModeShared, .hazardTrackingModeUntracked])
        buffer?.label = label
        if let b = buffer { renderer.makeResident([b]) }
    }

    func push<T>(_ value: T) -> Int {
        let at = offset
        guard let b = buffer, at + MemoryLayout<T>.stride <= b.length else { return 0 }
        (b.contents() + at).storeBytes(of: value, as: T.self)
        offset = FrameArena.aligned(at + MemoryLayout<T>.stride)
        return at
    }

    func push<T>(bytes values: [T], minimum: Int = 0) -> Int {
        let at = offset
        let n = values.count * MemoryLayout<T>.stride
        guard let b = buffer, at + max(n, minimum) <= b.length else { return 0 }
        values.withUnsafeBytes { raw in
            if let base = raw.baseAddress, n > 0 { (b.contents() + at).copyMemory(from: base, byteCount: n) }
        }
        offset = FrameArena.aligned(at + max(n, minimum))
        return at
    }
}

/// ID-pick attachments and readback for one pick stream.
@MainActor final class PickTargets {
    /// Byte offset of the positions in `readback` (copy destinations must be aligned to the texel size).
    nonisolated static let positionOffset = FrameArena.alignment * 2
    let id: any MTLTexture
    let position: any MTLTexture
    let depth: any MTLTexture
    let readback: any MTLBuffer

    init?(renderer: ViewportRenderer, memoryless: Bool) {
        let n = ViewportRenderer.pickRadius * 2 + 1
        let device = renderer.device
        let a = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: n, height: n, mipmapped: false)
        a.usage = [.renderTarget]; a.storageMode = .private
        let b = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: n, height: n, mipmapped: false)
        b.usage = [.renderTarget]; b.storageMode = .private
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ViewportRenderer.depthFormat, width: n, height: n, mipmapped: false)
        d.usage = [.renderTarget]; d.storageMode = memoryless ? .memoryless : .private
        guard let idTex = device.makeTexture(descriptor: a), let posTex = device.makeTexture(descriptor: b),
              let depthTex = device.makeTexture(descriptor: d),
              let rb = device.makeBuffer(length: PickTargets.positionOffset + n * n * 16, options: .storageModeShared) else { return nil }
        id = idTex; position = posTex; depth = depthTex; readback = rb
    }

    var allocations: [any MTLAllocation] {
        var a: [any MTLAllocation] = [id, position, readback]
        if depth.storageMode != .memoryless { a.append(depth) }
        return a
    }
}

/// Carries a Metal buffer across the completion-handler boundary (read only after GPU completion).
nonisolated private final class ReadbackBox: @unchecked Sendable {
    let buffer: any MTLBuffer
    init(_ b: any MTLBuffer) { buffer = b }
}

/// Carries the frame semaphore into the completion handler.
nonisolated final class SemaphoreBox: @unchecked Sendable {
    let semaphore: DispatchSemaphore
    init(_ s: DispatchSemaphore) { semaphore = s }
}

/// GPU time handed from a completion handler to a waiting benchmark loop.
nonisolated private final class TimingBox: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value = 0.0
    func finish(_ ms: Double) { lock.lock(); value = ms; lock.unlock(); done.signal() }
    func wait() -> Double {
        _ = done.wait(timeout: .now() + 10)
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
