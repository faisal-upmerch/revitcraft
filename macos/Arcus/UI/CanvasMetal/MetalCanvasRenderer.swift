import CoreGraphics
import Foundation
import Metal
import QuartzCore
import ArcusGeometry
import ArcusDomain
import ArcusOutput

/// Timing and workload of one encoded frame.
public struct CanvasFrameStats: Sendable {
    public var frameIndex: UInt64 = 0
    /// CPU time spent building uniforms, uploading dirty tables, culling and encoding (excludes `slotWait`).
    public var cpuEncodeMilliseconds: Double = 0
    /// Time blocked waiting for a free frame slot (GPU back-pressure).
    public var slotWaitMilliseconds: Double = 0
    /// GPU execution time, when known (see `MetalCanvasRenderer.waitUntilCompleted`).
    public var gpuMilliseconds: Double?
    public var drawCalls = 0
    public var recordsSubmitted = 0
}

/// Encodes canvas frames with Metal 4. One renderer per canvas (it owns the per-canvas dynamic state: colour table,
/// per-item highlight/visibility table, overlay primitives and a ring of three frame slots).
///
/// Per frame only a 112-byte uniform block changes; the colour table and item table are re-uploaded to a slot only
/// when options/highlights changed since that slot was last used.
public final class MetalCanvasRenderer {
    /// Which content a pass draws.
    public struct Passes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let scene = Passes(rawValue: 1)
        public static let overlay = Passes(rawValue: 2)
        public static let all: Passes = [.scene, .overlay]
    }

    /// What happens to the target's existing pixels.
    public enum Load: Sendable {
        /// Clear to the canvas colour (options.background != nil) or to transparent (background nil) — GraphicsRenderer's
        /// "only a pass that asks for a background paints one".
        case clear
        /// Keep the existing pixels (e.g. an overlay-only pass on top of a previously rendered frame).
        case load
    }

    public let context: MetalCanvasContext
    public private(set) var scene: MetalCanvasScene?
    /// Options of the main pass (thin lines, dark canvas, highlight, hidden elements, …).
    public var options = RenderOptions() { didSet { optionsChanged(from: oldValue) } }
    /// Options of the overlay pass (defaults: no background, matching Canvas2DView's preview pass).
    public var overlayOptions: RenderOptions { didSet { overlayOptionsChanged(from: oldValue) } }
    /// Elements drawn halftoned regardless of their styles (e.g. "halftone" temporary overrides) — no rebuild.
    public var halftoneElements: Set<ElementID> = [] { didSet { if halftoneElements != oldValue { updateItems(forcedHalftone: oldValue) } } }
    /// When false, `.clear` passes clear to transparent even if `options.background` is set; the background colour is
    /// still the canvas colour for masks, halftone and dark mapping. Use it to show CoreGraphics content (underlays,
    /// sheet paper and shadow) in a layer beneath the Metal layer.
    public var paintsBackground = true
    /// Reproduce CoreGraphics' pattern budget (tint when a visible fill would need more than 40 000 marks).
    public var matchCoreGraphicsPatternBudget = true
    public private(set) var lastFrame = CanvasFrameStats()

    static let slotCount = 3
    private let slots: [FrameSlot]
    private let event: any MTLSharedEvent
    private var frameIndex: UInt64 = 0
    private let residency: any MTLResidencySet
    private var residentTargets: [(id: ObjectIdentifier, texture: any MTLTexture)] = []
    private var residentPages: Set<ObjectIdentifier> = []
    private let dummyTexture: any MTLTexture
    private let timings = GPUTimings()

    // Scene dynamic state
    private var sceneColors = CanvasColors(options: RenderOptions())
    private var sceneColorTable: [SIMD4<Float>] = [.zero]
    private var sceneItems: [GPUItem] = []
    private var sceneVersion: UInt64 = 1
    private var colorsVersion: UInt64 = 1
    private var itemsVersion: UInt64 = 1
    private var appliedHighlight: [ElementID: RGBColor] = [:]
    private var appliedHidden: Set<ElementID> = []

    // Overlay
    private var overlay: SceneData?
    private var overlayVersion: UInt64 = 1
    private var overlayColorTable: [SIMD4<Float>] = [.zero]
    private var overlayItems: [GPUItem] = []

    public init?(context: MetalCanvasContext) {
        self.context = context
        let device = context.device
        var o = RenderOptions()
        o.background = nil
        overlayOptions = o
        guard let ev = device.makeSharedEvent() else { return nil }
        event = ev
        let rd = MTLResidencySetDescriptor()
        rd.label = "canvas renderer"
        rd.initialCapacity = 64
        guard let rs = try? device.makeResidencySet(descriptor: rd) else { return nil }
        residency = rs
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: 1, height: 1, mipmapped: false)
        td.usage = .shaderRead
        td.storageMode = .shared
        guard let dummy = device.makeTexture(descriptor: td) else { return nil }
        dummyTexture = dummy
        rs.addAllocation(dummy)
        var made: [FrameSlot] = []
        for i in 0..<Self.slotCount {
            guard let s = FrameSlot(device: device, index: i) else { return nil }
            rs.addAllocation(s.uniforms)
            made.append(s)
        }
        slots = made
        rs.commit()
    }

    // MARK: Content

    /// Replaces the retained scene (nil draws only the background and overlay). Cheap: no geometry is copied.
    public func setScene(_ s: MetalCanvasScene?) {
        if s === scene { return }
        scene = s
        sceneVersion &+= 1
        rebuildSceneTables()
    }

    /// Per-frame dynamic primitives drawn on top of the scene without painting any background (tool previews, drag
    /// previews, temporary graphics). Built synchronously — keep overlays small. `scale` is the view scale used for pen
    /// widths.
    public func setOverlay(primitives: [GPrimitive], scale: Int) {
        guard !primitives.isEmpty else { setOverlay(nil); return }
        let g = ViewGraphics(viewID: ElementID(0), scale: scale,
                             items: [GItem(elementID: nil, category: .views, layer: .overlay, primitives: primitives, selectable: false)],
                             extents: .empty, crop: nil, modelRevision: 0)
        setOverlay(g)
    }

    /// Overlay from a complete display list (several items / layers).
    public func setOverlay(_ g: ViewGraphics?) {
        overlay = g.flatMap { SceneBuilder.build($0, atlas: context.atlas) }
        overlayVersion &+= 1
        overlayItems = overlay.map { $0.itemFlags.map { GPUItem(flags: $0) } } ?? []
        overlayColorTable = CanvasColors(options: overlayOptions).table(overlay?.colors ?? [.white])
    }

    // MARK: Encoding

    /// Encodes and commits one frame into `target`.
    /// - Parameters:
    ///   - viewToDevice: view units → device points (the same transform GraphicsRenderer receives).
    ///   - pointsPerPaperMeter: device points per paper meter.
    ///   - pixelsPerPoint: target pixels per device point (the layer's contentsScale).
    ///   - drawable: when rendering into a `CAMetalDrawable`, it is synchronised and presented.
    @discardableResult
    public func encode(to target: any MTLTexture, viewToDevice: CGAffineTransform, pointsPerPaperMeter: Double,
                       pixelsPerPoint: Double, passes: Passes = .all, load: Load = .clear,
                       drawable: (any CAMetalDrawable)? = nil) -> CanvasFrameStats? {
        guard pointsPerPaperMeter.isFinite, pointsPerPaperMeter > 0, pixelsPerPoint > 0,
              let pipeline = context.pipeline(for: target.pixelFormat) else { return nil }
        let slot = slots[Int(frameIndex % UInt64(Self.slotCount))]
        let tw = CFAbsoluteTimeGetCurrent()
        if frameIndex >= UInt64(Self.slotCount) {
            _ = event.wait(untilSignaledValue: frameIndex - UInt64(Self.slotCount) + 1, timeoutMS: 1000)
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        var stats = CanvasFrameStats()
        stats.frameIndex = frameIndex
        stats.slotWaitMilliseconds = (t0 - tw) * 1000

        let width = Double(target.width), height = Double(target.height)
        let drawScene = passes.contains(.scene) ? scene : nil
        let drawOverlay = passes.contains(.overlay) ? overlay : nil
        var residencyDirty = false
        if drawable == nil { residencyDirty = makeResident(target) || residencyDirty }

        // Uniforms.
        let viewport = CGRect(x: 0, y: 0, width: width / pixelsPerPoint, height: height / pixelsPerPoint)
        guard let sceneFrame = frameUniforms(origin: drawScene?.origin ?? .zero, t: viewToDevice, ppm: pointsPerPaperMeter,
                                             s: pixelsPerPoint, size: (width, height), options: options, colors: sceneColors)
        else { return nil }
        let ovColors = CanvasColors(options: overlayOptions)
        let ovFrame = frameUniforms(origin: drawOverlay?.origin ?? .zero, t: viewToDevice, ppm: pointsPerPaperMeter,
                                    s: pixelsPerPoint, size: (width, height), options: overlayOptions, colors: ovColors)
        withUnsafeBytes(of: sceneFrame) { slot.uniforms.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        if let ovFrame {
            withUnsafeBytes(of: ovFrame) { slot.uniforms.contents().advanced(by: FrameSlot.overlayOffset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }

        // Dirty tables.
        if drawScene != nil {
            if slot.sceneColorsVersion != colorsVersion &+ sceneVersion {
                residencyDirty = slot.sceneColors.upload(sceneColorTable, device: context.device, residency: residency) || residencyDirty
                slot.sceneColorsVersion = colorsVersion &+ sceneVersion
            }
            if slot.sceneItemsVersion != itemsVersion &+ sceneVersion {
                residencyDirty = slot.sceneItems.upload(sceneItems, device: context.device, residency: residency) || residencyDirty
                slot.sceneItemsVersion = itemsVersion &+ sceneVersion
            }
        }
        if let ov = drawOverlay, slot.overlayVersion != overlayVersion {
            let d = context.device
            var r = slot.ovRecords.upload(ov.records, device: d, residency: residency)
            r = slot.ovStrokes.upload(ov.strokes, device: d, residency: residency) || r
            r = slot.ovFills.upload(ov.fills, device: d, residency: residency) || r
            r = slot.ovTexts.upload(ov.texts, device: d, residency: residency) || r
            r = slot.ovGlyphs.upload(ov.glyphs, device: d, residency: residency) || r
            r = slot.ovColors.upload(overlayColorTable, device: d, residency: residency) || r
            r = slot.ovItems.upload(overlayItems, device: d, residency: residency) || r
            residencyDirty = r || residencyDirty
            slot.overlayVersion = overlayVersion
        }
        if let page = drawOverlay?.atlasPage, residentPages.insert(ObjectIdentifier(page)).inserted {
            residency.addAllocation(page.texture)
            residencyDirty = true
        }
        if residencyDirty { residency.commit() }

        // Visible chunks (painter's order preserved: runs are ascending and merged).
        var runs: [(Int, Int)] = []
        if let sc = drawScene {
            let margin = 3.0 + max(options.minimumDevicePixel, 1 / pixelsPerPoint)
            runs = visibleRuns(sc, t: viewToDevice, ppm: pointsPerPaperMeter, viewport: viewport, margin: margin)
        }

        // Encode.
        slot.allocator.reset()
        guard let cb = context.device.makeCommandBuffer() else { return nil }
        cb.beginCommandBuffer(allocator: slot.allocator)
        cb.label = "canvas frame"
        cb.useResidencySet(residency)
        if let sc = drawScene { cb.useResidencySet(sc.residency) }
        let rp = MTL4RenderPassDescriptor()
        let ca = rp.colorAttachments[0]!
        ca.texture = target
        ca.storeAction = .store
        switch load {
        case .load:
            ca.loadAction = .load
        case .clear:
            ca.loadAction = .clear
            if options.background != nil && paintsBackground {
                let c = sceneColors.canvas
                let a = max(0, min(1, c.a))
                ca.clearColor = MTLClearColor(red: max(0, min(1, c.r)) * a, green: max(0, min(1, c.g)) * a,
                                              blue: max(0, min(1, c.b)) * a, alpha: a)
            } else {
                ca.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            }
        }
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else {
            cb.endCommandBuffer()
            return nil
        }
        enc.label = "canvas"
        enc.setRenderPipelineState(pipeline)
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1))
        if let sc = drawScene, !runs.isEmpty {
            let at = slot.sceneTable
            at.setAddress(slot.uniforms.gpuAddress, index: 0)
            at.setAddress(sc.records.gpuAddress, index: 1)
            at.setAddress(sc.strokes.gpuAddress, index: 2)
            at.setAddress(sc.fills.gpuAddress, index: 3)
            at.setAddress(sc.texts.gpuAddress, index: 4)
            at.setAddress(sc.glyphs.gpuAddress, index: 5)
            at.setAddress(slot.sceneColors.address, index: 6)
            at.setAddress(slot.sceneItems.address, index: 7)
            at.setTexture((sc.atlasPage?.texture ?? dummyTexture).gpuResourceID, index: 0)
            enc.setArgumentTable(at, stages: [.vertex, .fragment])
            for (start, count) in runs {
                enc.drawPrimitives(primitiveType: .triangle, vertexStart: start * 6, vertexCount: count * 6)
                stats.drawCalls += 1
                stats.recordsSubmitted += count
            }
        }
        if let ov = drawOverlay, !ov.records.isEmpty, ovFrame != nil {
            let at = slot.overlayTable
            at.setAddress(slot.uniforms.gpuAddress + UInt64(FrameSlot.overlayOffset), index: 0)
            at.setAddress(slot.ovRecords.address, index: 1)
            at.setAddress(slot.ovStrokes.address, index: 2)
            at.setAddress(slot.ovFills.address, index: 3)
            at.setAddress(slot.ovTexts.address, index: 4)
            at.setAddress(slot.ovGlyphs.address, index: 5)
            at.setAddress(slot.ovColors.address, index: 6)
            at.setAddress(slot.ovItems.address, index: 7)
            at.setTexture((ov.atlasPage?.texture ?? dummyTexture).gpuResourceID, index: 0)
            enc.setArgumentTable(at, stages: [.vertex, .fragment])
            enc.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: ov.records.count * 6)
            stats.drawCalls += 1
            stats.recordsSubmitted += ov.records.count
        }
        enc.endEncoding()
        cb.endCommandBuffer()

        let frame = frameIndex
        let timings = timings
        let commit = MTL4CommitOptions()
        commit.addFeedbackHandler { fb in
            timings.record(frame: frame, milliseconds: (fb.gpuEndTime - fb.gpuStartTime) * 1000, failed: fb.error != nil)
        }
        if let drawable { context.queue.waitForDrawable(drawable) }
        context.queue.commit([cb], options: commit)
        if let drawable {
            context.queue.signalDrawable(drawable)
            drawable.present()
        }
        context.queue.signalEvent(event, value: frame + 1)
        frameIndex += 1
        stats.cpuEncodeMilliseconds = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        lastFrame = stats
        return stats
    }

    /// Blocks until the GPU finished `stats.frameIndex`; returns the stats with `gpuMilliseconds` filled in.
    public func waitUntilCompleted(_ stats: CanvasFrameStats, timeout: TimeInterval = 5) -> CanvasFrameStats {
        var s = stats
        _ = event.wait(untilSignaledValue: stats.frameIndex + 1, timeoutMS: UInt64(timeout * 1000))
        s.gpuMilliseconds = timings.wait(frame: stats.frameIndex, timeout: timeout)
        return s
    }

    // MARK: Layers

    /// Makes a CAMetalLayer's drawables resident on the context's Metal 4 queue (call once per layer before
    /// rendering into its drawables; `MetalCanvasView` does this itself).
    public static func attach(_ layer: CAMetalLayer, to context: MetalCanvasContext) {
        context.queue.addResidencySet(layer.residencySet)
    }

    /// Reverses `attach`.
    public static func detach(_ layer: CAMetalLayer, from context: MetalCanvasContext) {
        context.queue.removeResidencySet(layer.residencySet)
    }

    // MARK: Offscreen

    /// A shared-storage BGRA8 render target (tests, thumbnails, snapshots).
    public func makeOffscreenTarget(width: Int, height: Int) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: max(width, 1), height: max(height, 1), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return context.device.makeTexture(descriptor: d)
    }

    /// BGRA premultiplied bytes of a shared texture, rows top-down (same layout as a CoreGraphics
    /// `premultipliedFirst | byteOrder32Little` bitmap).
    public static func readPixels(_ t: any MTLTexture) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: t.width * t.height * 4)
        out.withUnsafeMutableBytes { raw in
            t.getBytes(raw.baseAddress!, bytesPerRow: t.width * 4, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    // MARK: Uniforms & culling

    private func frameUniforms(origin: Vec2, t: CGAffineTransform, ppm: Double, s: Double, size: (Double, Double),
                               options o: RenderOptions, colors: CanvasColors) -> GPUFrame? {
        let det = Double(t.a * t.d - t.b * t.c)
        guard det.isFinite, abs(det) > 1e-300 else { return nil }
        let inv = t.inverted()
        let cPt = CGPoint(x: size.0 / s / 2, y: size.1 / s / 2)
        let camX = Double(inv.a * cPt.x + inv.c * cPt.y + inv.tx), camY = Double(inv.b * cPt.x + inv.d * cPt.y + inv.ty)
        let rx = camX - origin.x, ry = camY - origin.y
        let hx = Float(rx), hy = Float(ry)
        var f = GPUFrame()
        f.linear = SIMD4(Float(Double(t.a) * s), Float(Double(t.b) * s), Float(Double(t.c) * s), Float(Double(t.d) * s))
        f.camHi = SIMD2(hx, hy)
        f.camLo = SIMD2(Float(rx - Double(hx)), Float(ry - Double(hy)))
        f.centerPx = SIMD2(Float(size.0 / 2), Float(size.1 / 2))
        f.viewport = SIMD2(Float(size.0), Float(size.1))
        f.camView = SIMD2(Float(camX), Float(camY))
        f.ppmPx = Float(ppm * s)
        f.viewUnitPx = Float(abs(det).squareRoot() * s)
        f.minWidthPx = Float(o.minimumDevicePixel * s)
        f.halftoneAmount = Float(o.halftoneAmount)
        var flags: UInt32 = 0
        if o.thinLines && !o.printing { flags |= GPUFrame.thinLines }
        if o.printing { flags |= GPUFrame.printing }
        if o.showOverlays { flags |= GPUFrame.showOverlays }
        if matchCoreGraphicsPatternBudget { flags |= GPUFrame.patternBudget }
        f.flags = flags
        f.pixelsPerPoint = Float(s)
        f.canvas = colors.canvas.simd
        f.clipPx = SIMD4(0, 0, Float(size.0), Float(size.1))
        return f
    }

    private func visibleRuns(_ sc: MetalCanvasScene, t: CGAffineTransform, ppm: Double, viewport: CGRect, margin: Double) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        runs.reserveCapacity(8)
        for c in sc.chunks {
            var visible = true
            if !c.bounds.isEmpty {
                let r = CGRect(x: c.bounds.min.x, y: c.bounds.min.y, width: c.bounds.width, height: c.bounds.height).applying(t)
                let m = CGFloat(c.paperMargin * ppm + margin)
                visible = r.insetBy(dx: -m, dy: -m).intersects(viewport)
            }
            guard visible else { continue }
            if let last = runs.last, last.0 + last.1 == c.start { runs[runs.count - 1].1 += c.count } else { runs.append((c.start, c.count)) }
        }
        return runs
    }

    private func makeResident(_ t: any MTLTexture) -> Bool {
        let id = ObjectIdentifier(t)
        if residentTargets.contains(where: { $0.id == id }) { return false }
        residency.addAllocation(t)
        residentTargets.append((id, t))
        if residentTargets.count > 4 {
            residency.removeAllocation(residentTargets.removeFirst().texture)
        }
        return true
    }

    // MARK: Dynamic tables

    private func rebuildSceneTables() {
        sceneColors = CanvasColors(options: options)
        sceneColorTable = sceneColors.table(scene?.rawColors ?? [.white])
        colorsVersion &+= 1
        appliedHighlight = [:]
        appliedHidden = []
        sceneItems = (scene?.itemStaticFlags ?? []).map { GPUItem(flags: $0) }
        guard let sc = scene else { itemsVersion &+= 1; return }
        for id in Set(options.highlight.keys).union(options.hiddenElements).union(halftoneElements) {
            for i in sc.elementItems[id] ?? [] { sceneItems[Int(i)] = itemState(Int(i), id: id) }
        }
        appliedHighlight = options.highlight
        appliedHidden = options.hiddenElements
        itemsVersion &+= 1
    }

    /// RGBA8, red in the low byte (Metal's `unpack_unorm4x8_to_float`).
    static func packRGBA8(_ c: ArcusDomain.RGBColor) -> UInt32 {
        func b(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return b(c.r) | b(c.g) << 8 | b(c.b) << 16 | b(c.a) << 24
    }

    private func itemState(_ i: Int, id: ElementID) -> GPUItem {
        var it = GPUItem(flags: scene?.itemStaticFlags[i] ?? 0)
        if options.hiddenElements.contains(id) { it.flags |= GPUItem.hidden }
        if let h = options.highlight[id] {
            it.flags |= GPUItem.highlighted; it.highlight = h.simd
            if let t = options.highlightFill[id] { it.fillTint = Self.packRGBA8(t) }
        }
        if halftoneElements.contains(id) { it.flags |= GPUItem.forceHalftone }
        return it
    }

    private func optionsChanged(from old: RenderOptions) {
        let c = CanvasColors(options: options)
        if c != sceneColors {
            sceneColors = c
            sceneColorTable = c.table(scene?.rawColors ?? [.white])
            colorsVersion &+= 1
        }
        if options.highlight != appliedHighlight || options.highlightFill != old.highlightFill || options.hiddenElements != appliedHidden {
            updateItems(forcedHalftone: halftoneElements, fillChanged: Set(options.highlightFill.keys).union(old.highlightFill.keys).filter { options.highlightFill[$0] != old.highlightFill[$0] })
        }
    }

    private func overlayOptionsChanged(from old: RenderOptions) {
        if CanvasColors(options: overlayOptions) != CanvasColors(options: old) {
            overlayColorTable = CanvasColors(options: overlayOptions).table(overlay?.colors ?? [.white])
            overlayVersion &+= 1
        }
    }

    /// Re-evaluates only the items whose element changed highlight, visibility or forced halftone.
    private func updateItems(forcedHalftone oldHalftone: Set<ElementID>, fillChanged: Set<ElementID> = []) {
        guard let sc = scene else {
            appliedHighlight = options.highlight
            appliedHidden = options.hiddenElements
            return
        }
        var changed = Set<ElementID>()
        for (id, c) in options.highlight where appliedHighlight[id] != c { changed.insert(id) }
        for id in appliedHighlight.keys where options.highlight[id] == nil { changed.insert(id) }
        changed.formUnion(options.hiddenElements.symmetricDifference(appliedHidden))
        changed.formUnion(halftoneElements.symmetricDifference(oldHalftone))
        changed.formUnion(fillChanged)
        appliedHighlight = options.highlight
        appliedHidden = options.hiddenElements
        var touched = false
        for id in changed {
            for i in sc.elementItems[id] ?? [] { sceneItems[Int(i)] = itemState(Int(i), id: id); touched = true }
        }
        if touched { itemsVersion &+= 1 }
    }
}

// MARK: - Frame slot

/// Resources of one in-flight frame. A slot is reused only after the GPU finished the frame that last used it.
private final class FrameSlot {
    static let overlayOffset = 256
    let allocator: any MTL4CommandAllocator
    let uniforms: any MTLBuffer
    let sceneTable: any MTL4ArgumentTable
    let overlayTable: any MTL4ArgumentTable
    let sceneColors = DynamicBuffer("scene colours")
    let sceneItems = DynamicBuffer("scene items")
    let ovRecords = DynamicBuffer("overlay records")
    let ovStrokes = DynamicBuffer("overlay strokes")
    let ovFills = DynamicBuffer("overlay fills")
    let ovTexts = DynamicBuffer("overlay texts")
    let ovGlyphs = DynamicBuffer("overlay glyphs")
    let ovColors = DynamicBuffer("overlay colours")
    let ovItems = DynamicBuffer("overlay items")
    var sceneColorsVersion: UInt64 = 0
    var sceneItemsVersion: UInt64 = 0
    var overlayVersion: UInt64 = 0

    init?(device: any MTLDevice, index: Int) {
        guard let a = device.makeCommandAllocator(),
              let u = device.makeBuffer(length: 512, options: [.storageModeShared, .hazardTrackingModeUntracked]) else { return nil }
        let td = MTL4ArgumentTableDescriptor()
        td.maxBufferBindCount = 8
        td.maxTextureBindCount = 1
        td.label = "canvas slot \(index)"
        guard let st = try? device.makeArgumentTable(descriptor: td), let ot = try? device.makeArgumentTable(descriptor: td) else { return nil }
        allocator = a
        uniforms = u
        u.label = "canvas uniforms \(index)"
        sceneTable = st
        overlayTable = ot
    }
}

/// A grow-only shared buffer registered in the renderer's residency set.
private final class DynamicBuffer {
    private(set) var buffer: (any MTLBuffer)?
    let label: String
    init(_ label: String) { self.label = label }

    var address: UInt64 { buffer?.gpuAddress ?? 0 }

    /// Copies `values`; returns true when the residency set changed (caller commits it).
    func upload<T>(_ values: [T], device: any MTLDevice, residency: any MTLResidencySet) -> Bool {
        let bytes = max(MemoryLayout<T>.stride * values.count, 64)
        var changed = false
        if buffer == nil || buffer!.length < bytes {
            let cap = max(bytes, (buffer?.length ?? 0) * 3 / 2, 4096)
            guard let b = device.makeBuffer(length: cap, options: [.storageModeShared, .hazardTrackingModeUntracked, .cpuCacheModeWriteCombined]) else { return false }
            b.label = label
            if let old = buffer { residency.removeAllocation(old) }
            residency.addAllocation(b)
            buffer = b
            changed = true
        }
        if let b = buffer, !values.isEmpty {
            values.withUnsafeBytes { b.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        }
        return changed
    }
}

/// GPU completion times delivered by commit feedback (any thread).
private nonisolated final class GPUTimings: @unchecked Sendable {
    private let cond = NSCondition()
    private var times: [UInt64: Double] = [:]

    func record(frame: UInt64, milliseconds: Double, failed: Bool) {
        cond.lock()
        times[frame] = failed ? -1 : milliseconds
        if times.count > 64, let oldest = times.keys.min() { times.removeValue(forKey: oldest) }
        cond.broadcast()
        cond.unlock()
    }

    func wait(frame: UInt64, timeout: TimeInterval) -> Double? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        cond.lock()
        defer { cond.unlock() }
        while times[frame] == nil {
            if !cond.wait(until: deadline) { return nil }
        }
        let t = times[frame] ?? -1
        return t >= 0 ? t : nil
    }
}
