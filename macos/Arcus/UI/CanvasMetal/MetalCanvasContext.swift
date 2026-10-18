import Foundation
import Metal
import os

/// Process-wide Metal state shared by every canvas: device, Metal 4 command queue, runtime-compiled pipelines (cached
/// per pixel format) and the glyph atlas. Creation never traps: when the device, Metal 4 or shader compilation is
/// unavailable, `shared` is nil and `isSupported` is false (callers keep the CoreGraphics path).
public final class MetalCanvasContext: @unchecked Sendable {
    /// The default context (system default device), created on first use from any thread.
    public nonisolated static let shared: MetalCanvasContext? = MetalCanvasContext()
    /// True when the GPU canvas can be used on this machine.
    public nonisolated static var isSupported: Bool { shared != nil }

    public nonisolated let device: any MTLDevice
    nonisolated let queue: any MTL4CommandQueue
    nonisolated let atlas: GlyphAtlas
    private nonisolated let compiler: any MTL4Compiler
    private nonisolated let library: any MTLLibrary
    private nonisolated let lock = NSLock()
    private nonisolated(unsafe) var pipelines: [UInt: any MTLRenderPipelineState] = [:]
    /// Why initialisation failed (diagnostics for the shared context).
    public nonisolated static let log = Logger(subsystem: "Arcus", category: "CanvasMetal")

    public nonisolated init?(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        guard let device else {
            Self.log.error("No Metal device")
            return nil
        }
        guard device.supportsFamily(.metal4) else {
            Self.log.error("Device \(device.name, privacy: .public) does not support Metal 4")
            return nil
        }
        let qd = MTL4CommandQueueDescriptor()
        qd.label = "Arcus canvas"
        guard let queue = try? device.makeMTL4CommandQueue(descriptor: qd) else {
            Self.log.error("Could not create a Metal 4 command queue")
            return nil
        }
        do {
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            let ld = MTL4LibraryDescriptor()
            ld.source = CanvasShaders.source
            ld.name = "ArcusCanvas"
            let opts = MTLCompileOptions()
            opts.mathMode = .safe
            ld.options = opts
            library = try compiler.makeLibrary(descriptor: ld)
            self.compiler = compiler
        } catch {
            Self.log.error("Canvas shader compilation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        self.device = device
        self.queue = queue
        atlas = GlyphAtlas(device: device)
        guard pipeline(for: .bgra8Unorm) != nil else { return nil }
    }

    /// Render pipeline for a colour attachment format (premultiplied source-over blending).
    nonisolated func pipeline(for format: MTLPixelFormat) -> (any MTLRenderPipelineState)? {
        lock.lock()
        defer { lock.unlock() }
        if let p = pipelines[format.rawValue] { return p }
        let vf = MTL4LibraryFunctionDescriptor()
        vf.name = "canvas_vertex"
        vf.library = library
        let ff = MTL4LibraryFunctionDescriptor()
        ff.name = "canvas_fragment"
        ff.library = library
        let d = MTL4RenderPipelineDescriptor()
        d.label = "Arcus canvas"
        d.vertexFunctionDescriptor = vf
        d.fragmentFunctionDescriptor = ff
        let ca = d.colorAttachments[0]!
        ca.pixelFormat = format
        ca.blendingState = .enabled
        ca.rgbBlendOperation = .add
        ca.alphaBlendOperation = .add
        ca.sourceRGBBlendFactor = .one
        ca.sourceAlphaBlendFactor = .one
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            let p = try compiler.makeRenderPipelineState(descriptor: d)
            pipelines[format.rawValue] = p
            return p
        } catch {
            Self.log.error("Canvas pipeline creation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
