import Foundation
import Metal

/// Command API the viewport encodes with.
public enum ViewportBackendKind: String, Sendable {
    /// Metal 4: `MTL4CommandQueue`, command allocators, argument tables, `MTL4Compiler` and an on-disk `MTL4Archive`.
    case metal4 = "Metal 4"
    /// `MTLCommandQueue` / `MTLRenderCommandEncoder` (GPUs without the Metal 4 family).
    case classic = "Metal"

    /// Metal 4 when the device supports it, unless `ARCUS_VIEWPORT_BACKEND=classic` forces the classic path.
    nonisolated static func preferred(for device: any MTLDevice) -> ViewportBackendKind {
        if ProcessInfo.processInfo.environment["ARCUS_VIEWPORT_BACKEND"] == "classic" { return .classic }
        return device.supportsFamily(.metal4) ? .metal4 : .classic
    }
}

/// Every pipeline and depth state the viewport uses, compiled once per (device, backend, sample count) and shared by
/// all 3D views of the process. Immutable after creation, so it can be built on a background thread (`prewarm`).
nonisolated final class ViewportPipelines: @unchecked Sendable {
    static let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    static let depthFormat: MTLPixelFormat = .depth32Float
    static let occlusionFormat: MTLPixelFormat = .r8Unorm

    let device: any MTLDevice
    let backend: ViewportBackendKind
    let sampleCount: Int
    /// Metal 4 compiler (also used to create Metal 4 MetalFX scalers); nil on the classic backend.
    let compiler: (any MTL4Compiler)?

    let background: any MTLRenderPipelineState
    let faceOpaque: any MTLRenderPipelineState
    let faceBlend: any MTLRenderPipelineState
    let edge: any MTLRenderPipelineState
    /// VIS: silhouette candidates (edges drawn only where the surface turns away from the eye).
    let silhouette: any MTLRenderPipelineState
    let overlay: any MTLRenderPipelineState
    /// Overlay for single-sample post passes (composite).
    let overlaySingle: any MTLRenderPipelineState
    let facePick: any MTLRenderPipelineState
    let edgePick: any MTLRenderPipelineState
    let shadow: any MTLRenderPipelineState
    let occlusion: any MTLRenderPipelineState
    let composite: any MTLRenderPipelineState

    let depthWrite: any MTLDepthStencilState
    let depthTest: any MTLDepthStencilState
    let depthAlways: any MTLDepthStencilState
    let shadowDepth: any MTLDepthStencilState

    /// Wall time spent compiling (library + pipelines).
    let buildMilliseconds: Double
    /// True when pipeline binaries came from the on-disk archive written by an earlier launch.
    let usedArchive: Bool

    // MARK: Shared cache

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ViewportPipelines] = [:]
    /// Directory for the Metal 4 pipeline archive (nil disables it): ~/Library/Caches/<bundle id>/ViewportPipelines, or
    /// a temporary directory for processes without a bundle identifier (command-line tools, tests).
    nonisolated(unsafe) static var archiveDirectory: URL? = {
        guard let bundle = Bundle.main.bundleIdentifier, !bundle.contains("xctest") else {
            return FileManager.default.temporaryDirectory.appending(path: "ArcusViewportPipelines")
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return base?.appending(path: bundle).appending(path: "ViewportPipelines")
    }()

    /// The shared pipelines for a device, compiling them on first use (blocks while another thread compiles).
    static func shared(device: any MTLDevice, backend: ViewportBackendKind, sampleCount: Int) -> ViewportPipelines? {
        let key = "\(device.registryID)-\(backend.rawValue)-\(sampleCount)"
        lock.lock(); defer { lock.unlock() }
        if let p = cache[key] { return p }
        guard let p = ViewportPipelines(device: device, backend: backend, sampleCount: sampleCount) else { return nil }
        cache[key] = p
        return p
    }

    /// Compiles the default device's pipelines on a background thread so the first 3D view opens without a stall.
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            _ = shared(device: device, backend: .preferred(for: device), sampleCount: preferredSampleCount(device))
        }
    }

    static func preferredSampleCount(_ device: any MTLDevice) -> Int { device.supportsTextureSampleCount(4) ? 4 : 1 }

    /// Drops the process cache (tests).
    static func resetCache() { lock.lock(); cache.removeAll(); lock.unlock() }

    // MARK: Specs

    struct Spec {
        var label: String
        var vertex: String
        var fragment: String?
        var colors: [(format: MTLPixelFormat, blend: Bool, writeMask: MTLColorWriteMask)]
        var depth: MTLPixelFormat
        var samples: Int
    }

    static func specs(sampleCount s: Int) -> [String: Spec] {
        let c = colorFormat, d = depthFormat
        return [
            "background": Spec(label: "Background", vertex: "background_vertex", fragment: "background_fragment", colors: [(c, false, .all)], depth: d, samples: s),
            "faceOpaque": Spec(label: "Faces opaque", vertex: "face_vertex", fragment: "face_fragment", colors: [(c, false, .all)], depth: d, samples: s),
            "faceBlend": Spec(label: "Faces blended", vertex: "face_vertex", fragment: "face_fragment", colors: [(c, true, .all)], depth: d, samples: s),
            "edge": Spec(label: "Edges", vertex: "edge_vertex", fragment: "edge_fragment", colors: [(c, true, .all)], depth: d, samples: s),
            "silhouette": Spec(label: "Silhouettes", vertex: "silhouette_vertex", fragment: "edge_fragment", colors: [(c, true, .all)], depth: d, samples: s), // VIS
            "overlay": Spec(label: "Overlay", vertex: "overlay_vertex", fragment: "overlay_fragment", colors: [(c, true, .all)], depth: d, samples: s),
            "overlaySingle": Spec(label: "Overlay (post)", vertex: "overlay_vertex", fragment: "overlay_fragment", colors: [(c, true, .all)], depth: .invalid, samples: 1),
            "facePick": Spec(label: "Face pick", vertex: "face_vertex", fragment: "face_pick_fragment", colors: [(.r32Uint, false, .all), (.rgba32Float, false, .all)], depth: d, samples: 1),
            "edgePick": Spec(label: "Edge pick", vertex: "edge_vertex", fragment: "edge_pick_fragment", colors: [(.r32Uint, false, .all), (.rgba32Float, false, [])], depth: d, samples: 1),
            "shadow": Spec(label: "Shadow map", vertex: "shadow_vertex", fragment: nil, colors: [], depth: d, samples: 1),
            "occlusion": Spec(label: "Ambient occlusion", vertex: "fullscreen_vertex", fragment: "ao_fragment", colors: [(occlusionFormat, false, .all)], depth: .invalid, samples: 1),
            "composite": Spec(label: "Composite", vertex: "fullscreen_vertex", fragment: "composite_fragment", colors: [(c, false, .all)], depth: .invalid, samples: 1),
        ]
    }

    // MARK: Build

    /// Compiles an uncached set (benchmarks); `archiveDirectory` overrides the Metal 4 archive location and
    /// `sourceSuffix` (a comment) defeats Metal's in-process compile cache to measure a true cold start.
    static func build(device: any MTLDevice, backend: ViewportBackendKind, sampleCount: Int, archiveDirectory: URL?,
                      sourceSuffix: String = "") -> ViewportPipelines? {
        ViewportPipelines(device: device, backend: backend, sampleCount: sampleCount, archiveDirectory: archiveDirectory,
                          source: ViewportShaders.source + sourceSuffix)
    }

    private convenience init?(device: any MTLDevice, backend: ViewportBackendKind, sampleCount: Int) {
        self.init(device: device, backend: backend, sampleCount: sampleCount, archiveDirectory: ViewportPipelines.archiveDirectory,
                  source: ViewportShaders.source)
    }

    private init?(device: any MTLDevice, backend: ViewportBackendKind, sampleCount: Int, archiveDirectory: URL?, source: String) {
        let t0 = CFAbsoluteTimeGetCurrent()
        self.device = device
        self.backend = backend
        self.sampleCount = sampleCount
        let specs = ViewportPipelines.specs(sampleCount: sampleCount)
        var built: [String: any MTLRenderPipelineState] = [:]
        var archiveUsed = false
        let options = MTLCompileOptions()
        options.mathMode = .fast
        switch backend {
        case .metal4:
            guard let r = ViewportPipelines.buildMetal4(device: device, source: source, specs: specs, options: options,
                                                        archiveDirectory: archiveDirectory) else { return nil }
            compiler = r.compiler; built = r.pipelines; archiveUsed = r.usedArchive
        case .classic:
            compiler = nil
            let library: any MTLLibrary
            do { library = try device.makeLibrary(source: source, options: options) } catch {
                NSLog("Arcus viewport: shader compilation failed: %@", String(describing: error))
                return nil
            }
            for (key, spec) in specs {
                let d = MTLRenderPipelineDescriptor()
                d.label = spec.label
                d.vertexFunction = library.makeFunction(name: spec.vertex)
                d.fragmentFunction = spec.fragment.flatMap { library.makeFunction(name: $0) }
                d.rasterSampleCount = spec.samples
                d.depthAttachmentPixelFormat = spec.depth
                for (i, a) in spec.colors.enumerated() {
                    let c = d.colorAttachments[i]!
                    c.pixelFormat = a.format
                    c.writeMask = a.writeMask
                    if a.blend { ViewportPipelines.premultipliedBlend(c) }
                }
                do { built[key] = try device.makeRenderPipelineState(descriptor: d) } catch {
                    NSLog("Arcus viewport: pipeline %@ failed: %@", spec.label, String(describing: error))
                    return nil
                }
            }
        }
        guard let bg = built["background"], let fo = built["faceOpaque"], let fb = built["faceBlend"], let ed = built["edge"],
              let ov = built["overlay"], let ov1 = built["overlaySingle"], let fp = built["facePick"], let ep = built["edgePick"],
              let sh = built["shadow"], let ao = built["occlusion"], let co = built["composite"], let si = built["silhouette"] else { return nil }
        background = bg; faceOpaque = fo; faceBlend = fb; edge = ed; overlay = ov; overlaySingle = ov1
        silhouette = si
        facePick = fp; edgePick = ep; shadow = sh; occlusion = ao; composite = co
        func depth(_ compare: MTLCompareFunction, write: Bool) -> (any MTLDepthStencilState)? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        // Reversed-Z: larger depth is nearer. The shadow map uses conventional depth (0 = nearest the sun).
        guard let dw = depth(.greater, write: true), let dt = depth(.greaterEqual, write: false), let da = depth(.always, write: false),
              let sd = depth(.less, write: true) else { return nil }
        depthWrite = dw; depthTest = dt; depthAlways = da; shadowDepth = sd
        usedArchive = archiveUsed
        buildMilliseconds = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    static func premultipliedBlend(_ c: MTLRenderPipelineColorAttachmentDescriptor) {
        c.isBlendingEnabled = true
        c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
        c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
        c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    /// Metal 4: compiles with `MTL4Compiler`, looking pipelines up in (and, on a miss, writing) an `MTL4Archive` keyed
    /// by shader source, device and OS so later launches skip backend compilation.
    private static func buildMetal4(device: any MTLDevice, source: String, specs: [String: Spec], options: MTLCompileOptions, archiveDirectory: URL?)
        -> (compiler: any MTL4Compiler, pipelines: [String: any MTLRenderPipelineState], usedArchive: Bool)? {
        let serializerDescriptor = MTL4PipelineDataSetSerializerDescriptor()
        // Binaries only: combining with `.captureDescriptors` makes archive serialization fail.
        serializerDescriptor.configuration = [.captureBinaries]
        let serializer = device.makePipelineDataSetSerializer(descriptor: serializerDescriptor)
        let cd = MTL4CompilerDescriptor()
        cd.label = "Arcus viewport compiler"
        cd.pipelineDataSetSerializer = serializer
        let compiler: any MTL4Compiler
        do { compiler = try device.makeCompiler(descriptor: cd) } catch {
            NSLog("Arcus viewport: Metal 4 compiler unavailable: %@", String(describing: error))
            return nil
        }
        let ld = MTL4LibraryDescriptor()
        ld.source = source
        ld.options = options
        ld.name = "ArcusViewport"
        let library: any MTLLibrary
        do { library = try compiler.makeLibrary(descriptor: ld) } catch {
            NSLog("Arcus viewport: shader compilation failed: %@", String(describing: error))
            return nil
        }
        // Archived binaries are not instrumented: looking them up with GPU shader validation on crashes the compiler.
        let validating = ProcessInfo.processInfo.environment["MTL_SHADER_VALIDATION"].map { $0 != "0" } ?? false
        let archiveURL = validating ? nil : archiveDirectory.map { $0.appending(path: "viewport-\(archiveKey(device: device, source: source)).mtl4archive") }
        var archive: (any MTL4Archive)?
        if let archiveURL, FileManager.default.fileExists(atPath: archiveURL.path) {
            archive = try? device.makeArchive(url: archiveURL)
        }
        let taskOptions = MTL4CompilerTaskOptions()
        if let archive { taskOptions.lookupArchives = [archive] }
        func function(_ name: String) -> MTL4LibraryFunctionDescriptor {
            let f = MTL4LibraryFunctionDescriptor()
            f.name = name
            f.library = library
            return f
        }
        var pipelines: [String: any MTLRenderPipelineState] = [:]
        for (key, spec) in specs {
            let d = MTL4RenderPipelineDescriptor()
            d.label = spec.label
            d.vertexFunctionDescriptor = function(spec.vertex)
            if let f = spec.fragment { d.fragmentFunctionDescriptor = function(f) }
            d.rasterSampleCount = spec.samples
            for (i, a) in spec.colors.enumerated() {
                let c = d.colorAttachments[i]!
                c.pixelFormat = a.format
                c.writeMask = a.writeMask
                if a.blend {
                    c.blendingState = .enabled
                    c.rgbBlendOperation = .add; c.alphaBlendOperation = .add
                    c.sourceRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one
                    c.destinationRGBBlendFactor = .oneMinusSourceAlpha; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
            }
            do { pipelines[key] = try compiler.makeRenderPipelineState(descriptor: d, compilerTaskOptions: taskOptions) } catch {
                NSLog("Arcus viewport: pipeline %@ failed: %@", spec.label, String(describing: error))
                return nil
            }
        }
        if archive == nil, let archiveURL {
            do {
                try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try serializer.serializeAsArchiveAndFlush(url: archiveURL)
            } catch {
                NSLog("Arcus viewport: could not write pipeline archive: %@", String(describing: error))
            }
        }
        return (compiler, pipelines, archive != nil)
    }

    /// Stable key (FNV-1a) of everything that invalidates compiled binaries.
    static func archiveKey(device: any MTLDevice, source: String = ViewportShaders.source) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in (source + device.name + ProcessInfo.processInfo.operatingSystemVersionString).utf8 {
            h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
