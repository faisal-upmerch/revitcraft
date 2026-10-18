import Foundation
import Metal
import QuartzCore
import MetalFX

// One encoding path for both command APIs: the renderer describes passes and binds resources through these small
// protocols; `ClassicCommands` maps them onto MTLCommandBuffer/MTLRenderCommandEncoder and `Metal4Commands` onto
// MTL4CommandBuffer/MTL4RenderCommandEncoder + MTL4ArgumentTable (GPU addresses and resource IDs, explicit barriers).

/// One render-pass attachment.
struct PassAttachment {
    var texture: any MTLTexture
    var resolve: (any MTLTexture)?
    var load: MTLLoadAction = .clear
    var store: MTLStoreAction = .store
    var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    var clearDepth: Double = 0
}

struct PassDescription {
    var label: String
    var colors: [PassAttachment] = []
    var depth: PassAttachment?

    func colorDescriptor(_ a: PassAttachment) -> MTLRenderPassColorAttachmentDescriptor {
        let c = MTLRenderPassColorAttachmentDescriptor()
        c.texture = a.texture
        c.resolveTexture = a.resolve
        c.loadAction = a.load
        c.storeAction = a.store
        c.clearColor = a.clearColor
        return c
    }

    func depthDescriptor(_ a: PassAttachment) -> MTLRenderPassDepthAttachmentDescriptor {
        let d = MTLRenderPassDepthAttachmentDescriptor()
        d.texture = a.texture
        d.resolveTexture = a.resolve
        d.loadAction = a.load
        d.storeAction = a.store
        d.clearDepth = a.clearDepth
        if a.resolve != nil { d.depthResolveFilter = .sample0 }
        return d
    }

    var classic: MTLRenderPassDescriptor {
        let r = MTLRenderPassDescriptor()
        for (i, a) in colors.enumerated() { r.colorAttachments[i] = colorDescriptor(a) }
        if let depth { r.depthAttachment = depthDescriptor(depth) }
        return r
    }

    var metal4: MTL4RenderPassDescriptor {
        let r = MTL4RenderPassDescriptor()
        for (i, a) in colors.enumerated() { r.colorAttachments[i] = colorDescriptor(a) }
        if let depth { r.depthAttachment = depthDescriptor(depth) }
        return r
    }
}

/// Render encoder with a shared vertex/fragment binding model.
@MainActor protocol ViewportRenderEncoder: AnyObject {
    func setPipeline(_ p: any MTLRenderPipelineState)
    func setDepthStencil(_ s: (any MTLDepthStencilState)?)
    func setCullMode(_ m: MTLCullMode)
    func setDepthBias(_ bias: Float, slope: Float, clamp: Float)
    func setBuffer(_ b: any MTLBuffer, offset: Int, index: Int)
    func setTexture(_ t: any MTLTexture, index: Int)
    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    func drawIndexed(indexCount: Int, indexBuffer: any MTLBuffer)
    /// Signals `fence` once this pass's fragment work completes (MetalFX consumes it on Metal 4).
    func signal(_ fence: any MTLFence)
    func end()
}

/// One command buffer's worth of GPU work.
@MainActor protocol ViewportCommands: AnyObject {
    /// `dependsOnEarlierWork`: the pass reads or overwrites resources written by earlier passes or frames (Metal 4
    /// inserts a consumer barrier; the classic API tracks hazards itself).
    func renderPass(_ pass: PassDescription, dependsOnEarlierWork: Bool) -> (any ViewportRenderEncoder)?
    func upscale(_ scaler: ViewportUpscaler, from input: any MTLTexture, to output: any MTLTexture, fence: any MTLFence)
    func copy(from texture: any MTLTexture, size: MTLSize, to buffer: any MTLBuffer, offset: Int, bytesPerRow: Int)
    /// Commits; `completion` receives GPU start/end times on an arbitrary thread.
    func commit(present drawable: (any CAMetalDrawable)?, completion: (@Sendable (Double, Double) -> Void)?)
    func waitUntilCompleted()
}

/// MetalFX spatial scaler for either backend.
@MainActor final class ViewportUpscaler {
    let inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int
    let colorUsage: MTLTextureUsage
    let outputUsage: MTLTextureUsage
    let classic: (any MTLFXSpatialScaler)?
    let metal4: (any MTL4FXSpatialScaler)?

    init?(device: any MTLDevice, compiler: (any MTL4Compiler)?, input: (Int, Int), output: (Int, Int), format: MTLPixelFormat) {
        let d = MTLFXSpatialScalerDescriptor()
        d.inputWidth = input.0; d.inputHeight = input.1
        d.outputWidth = output.0; d.outputHeight = output.1
        d.colorTextureFormat = format
        d.outputTextureFormat = format
        d.colorProcessingMode = .perceptual
        inputWidth = input.0; inputHeight = input.1; outputWidth = output.0; outputHeight = output.1
        if let compiler {
            guard MTLFXSpatialScalerDescriptor.supportsMetal4FX(device), let s = d.makeSpatialScaler(device: device, compiler: compiler) else { return nil }
            metal4 = s; classic = nil
            colorUsage = s.colorTextureUsage; outputUsage = s.outputTextureUsage
        } else {
            guard MTLFXSpatialScalerDescriptor.supportsDevice(device), let s = d.makeSpatialScaler(device: device) else { return nil }
            classic = s; metal4 = nil
            colorUsage = s.colorTextureUsage; outputUsage = s.outputTextureUsage
        }
    }

    func matches(input: (Int, Int), output: (Int, Int)) -> Bool {
        inputWidth == input.0 && inputHeight == input.1 && outputWidth == output.0 && outputHeight == output.1
    }
}

// MARK: - Classic

@MainActor final class ClassicRenderEncoder: ViewportRenderEncoder {
    let e: any MTLRenderCommandEncoder
    init(_ e: any MTLRenderCommandEncoder) { self.e = e }
    func setPipeline(_ p: any MTLRenderPipelineState) { e.setRenderPipelineState(p) }
    /// nil (passes without a depth attachment) keeps the encoder's default state.
    func setDepthStencil(_ s: (any MTLDepthStencilState)?) { if let s { e.setDepthStencilState(s) } }
    func setCullMode(_ m: MTLCullMode) { e.setCullMode(m) }
    func setDepthBias(_ bias: Float, slope: Float, clamp: Float) { e.setDepthBias(bias, slopeScale: slope, clamp: clamp) }
    func setBuffer(_ b: any MTLBuffer, offset: Int, index: Int) {
        e.setVertexBuffer(b, offset: offset, index: index)
        e.setFragmentBuffer(b, offset: offset, index: index)
    }
    func setTexture(_ t: any MTLTexture, index: Int) { e.setFragmentTexture(t, index: index) }
    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        e.drawPrimitives(type: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
    }
    func drawIndexed(indexCount: Int, indexBuffer: any MTLBuffer) {
        e.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }
    func signal(_ fence: any MTLFence) {}
    func end() { e.endEncoding() }
}

@MainActor final class ClassicCommands: ViewportCommands {
    let cb: any MTLCommandBuffer
    let event: any MTLSharedEvent
    let serial: UInt64

    init(cb: any MTLCommandBuffer, event: any MTLSharedEvent, serial: UInt64) { self.cb = cb; self.event = event; self.serial = serial }

    func renderPass(_ pass: PassDescription, dependsOnEarlierWork: Bool) -> (any ViewportRenderEncoder)? {
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass.classic) else { return nil }
        e.label = pass.label
        return ClassicRenderEncoder(e)
    }

    func upscale(_ scaler: ViewportUpscaler, from input: any MTLTexture, to output: any MTLTexture, fence: any MTLFence) {
        guard let s = scaler.classic else { return }
        s.colorTexture = input
        s.outputTexture = output
        s.inputContentWidth = scaler.inputWidth
        s.inputContentHeight = scaler.inputHeight
        s.encode(commandBuffer: cb)
    }

    func copy(from texture: any MTLTexture, size: MTLSize, to buffer: any MTLBuffer, offset: Int, bytesPerRow: Int) {
        guard let blit = cb.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: size,
                  to: buffer, destinationOffset: offset, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * size.height)
        blit.endEncoding()
    }

    func commit(present drawable: (any CAMetalDrawable)?, completion: (@Sendable (Double, Double) -> Void)?) {
        cb.encodeSignalEvent(event, value: serial)
        if let drawable { cb.present(drawable) }
        if let completion { cb.addCompletedHandler { b in completion(b.gpuStartTime, b.gpuEndTime) } }
        cb.commit()
    }

    func waitUntilCompleted() { cb.waitUntilCompleted() }
}

// MARK: - Metal 4

@MainActor final class Metal4RenderEncoder: ViewportRenderEncoder {
    let e: any MTL4RenderCommandEncoder
    let table: any MTL4ArgumentTable
    init(_ e: any MTL4RenderCommandEncoder, table: any MTL4ArgumentTable) {
        self.e = e; self.table = table
        e.setArgumentTable(table, stages: [.vertex, .fragment])
    }
    func setPipeline(_ p: any MTLRenderPipelineState) { e.setRenderPipelineState(p) }
    func setDepthStencil(_ s: (any MTLDepthStencilState)?) { if let s { e.setDepthStencilState(s) } }
    func setCullMode(_ m: MTLCullMode) { e.setCullMode(m) }
    func setDepthBias(_ bias: Float, slope: Float, clamp: Float) { e.setDepthBias(bias, slopeScale: slope, clamp: clamp) }
    func setBuffer(_ b: any MTLBuffer, offset: Int, index: Int) { table.setAddress(b.gpuAddress + UInt64(offset), index: index) }
    func setTexture(_ t: any MTLTexture, index: Int) { table.setTexture(t.gpuResourceID, index: index) }
    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        e.drawPrimitives(primitiveType: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
    }
    func drawIndexed(indexCount: Int, indexBuffer: any MTLBuffer) {
        e.drawIndexedPrimitives(primitiveType: .triangle, indexCount: indexCount, indexType: .uint32,
                                indexBuffer: indexBuffer.gpuAddress, indexBufferLength: indexBuffer.length)
    }
    func signal(_ fence: any MTLFence) {
        e.updateFence(fence, afterEncoderStages: .fragment)
        // Producer barrier: later encoders (MetalFX's) start only after this pass's fragment work.
        e.barrier(afterStages: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch, .blit], visibilityOptions: .device)
    }
    func end() { e.endEncoding() }
}

@MainActor final class Metal4Commands: ViewportCommands {
    let queue: any MTL4CommandQueue
    let cb: any MTL4CommandBuffer
    let table: any MTL4ArgumentTable
    let event: any MTLSharedEvent
    let serial: UInt64
    private var committed = false

    init(queue: any MTL4CommandQueue, cb: any MTL4CommandBuffer, allocator: any MTL4CommandAllocator,
         table: any MTL4ArgumentTable, residency: any MTLResidencySet, event: any MTLSharedEvent, serial: UInt64) {
        self.queue = queue; self.cb = cb; self.table = table; self.event = event; self.serial = serial
        cb.beginCommandBuffer(allocator: allocator)
        cb.useResidencySet(residency)
    }

    func renderPass(_ pass: PassDescription, dependsOnEarlierWork: Bool) -> (any ViewportRenderEncoder)? {
        guard let e = cb.makeRenderCommandEncoder(descriptor: pass.metal4, options: MTL4RenderEncoderOptions()) else { return nil }
        e.label = pass.label
        if dependsOnEarlierWork {
            // Wait for every earlier pass (this frame's and in-flight frames') before reading/overwriting their outputs.
            e.barrier(afterQueueStages: [.vertex, .fragment, .dispatch, .blit], beforeStages: [.vertex, .fragment], visibilityOptions: .device)
        }
        return Metal4RenderEncoder(e, table: table)
    }

    func upscale(_ scaler: ViewportUpscaler, from input: any MTLTexture, to output: any MTLTexture, fence: any MTLFence) {
        guard let s = scaler.metal4 else { return }
        s.colorTexture = input
        s.outputTexture = output
        s.inputContentWidth = scaler.inputWidth
        s.inputContentHeight = scaler.inputHeight
        // MetalFX waits on the fence (signaled after the scene pass) and updates it when its output is written.
        s.fence = fence
        s.encode(commandBuffer: cb)
    }

    func copy(from texture: any MTLTexture, size: MTLSize, to buffer: any MTLBuffer, offset: Int, bytesPerRow: Int) {
        guard let e = cb.makeComputeCommandEncoder() else { return }
        e.barrier(afterQueueStages: [.fragment, .dispatch], beforeStages: .blit, visibilityOptions: .device)
        e.copy(sourceTexture: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: size,
               destinationBuffer: buffer, destinationOffset: offset, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * size.height)
        e.endEncoding()
    }

    func commit(present drawable: (any CAMetalDrawable)?, completion: (@Sendable (Double, Double) -> Void)?) {
        cb.endCommandBuffer()
        if let drawable { queue.waitForDrawable(drawable) }
        let options = MTL4CommitOptions()
        if let completion { options.addFeedbackHandler { fb in completion(fb.gpuStartTime, fb.gpuEndTime) } }
        queue.commit([cb], options: options)
        queue.signalEvent(event, value: serial)
        if let drawable {
            queue.signalDrawable(drawable)
            drawable.present()
        }
        committed = true
    }

    func waitUntilCompleted() {
        guard committed else { return }
        _ = event.wait(untilSignaledValue: serial, timeoutMS: 10_000)
    }
}
