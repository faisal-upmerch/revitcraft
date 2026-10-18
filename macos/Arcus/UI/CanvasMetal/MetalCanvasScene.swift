import Foundation
import Metal
import ArcusGeometry
import ArcusDomain

/// A display list converted to GPU buffers — retained until the display list changes.
///
/// Built off the main thread (`make(_:)` / `build(_:)`), immutable afterwards and therefore safe to share between
/// canvases showing the same view. Pan, zoom, option, highlight and visibility changes never rebuild it: they only
/// change per-frame uniforms and the renderer's small per-item/colour tables.
public final class MetalCanvasScene: @unchecked Sendable {
    public struct Statistics: Sendable {
        public var items: Int
        public var records: Int
        public var segments: Int
        public var arcs: Int
        public var triangles: Int
        public var glyphs: Int
        /// GPU memory of the scene buffers (bytes).
        public var bytes: Int
        /// Wall time of the build (seconds).
        public var buildSeconds: Double
    }

    public nonisolated let viewID: ElementID
    public nonisolated let modelRevision: UInt64
    public nonisolated let statistics: Statistics

    nonisolated let origin: Vec2
    nonisolated let recordCount: Int
    nonisolated let chunks: [SceneChunk]
    nonisolated let itemElementIDs: [ElementID?]
    nonisolated let itemStaticFlags: [UInt32]
    /// Items per element (for highlight / hidden updates).
    nonisolated let elementItems: [ElementID: [Int32]]
    nonisolated let rawColors: [RGBColor]
    nonisolated(unsafe) let records: any MTLBuffer
    nonisolated(unsafe) let strokes: any MTLBuffer
    nonisolated(unsafe) let fills: any MTLBuffer
    nonisolated(unsafe) let texts: any MTLBuffer
    nonisolated(unsafe) let glyphs: any MTLBuffer
    nonisolated let atlasPage: GlyphAtlasPage?
    nonisolated(unsafe) let residency: any MTLResidencySet

    /// Builds a scene synchronously on the calling thread (use from a background task; see `make`).
    /// Returns nil when Metal buffers cannot be allocated or `isCancelled` returns true.
    public nonisolated static func build(_ g: ViewGraphics, context: MetalCanvasContext,
                                         isCancelled: () -> Bool = { false }) -> MetalCanvasScene? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let data = SceneBuilder.build(g, atlas: context.atlas, isCancelled: isCancelled) else { return nil }
        return MetalCanvasScene(data: data, viewID: g.viewID, revision: g.modelRevision, device: context.device, started: t0)
    }

    /// Builds a scene on a detached background task.
    public nonisolated static func make(_ g: ViewGraphics, context: MetalCanvasContext) async -> MetalCanvasScene? {
        await Task.detached(priority: .userInitiated) { build(g, context: context) }.value
    }

    nonisolated init?(data: SceneData, viewID: ElementID, revision: UInt64, device: any MTLDevice, started: CFAbsoluteTime) {
        func buffer<T>(_ a: [T], _ label: String) -> (any MTLBuffer)? {
            let len = max(MemoryLayout<T>.stride * a.count, 64)
            let opts: MTLResourceOptions = [.storageModeShared, .hazardTrackingModeUntracked, .cpuCacheModeWriteCombined]
            let b = a.isEmpty ? device.makeBuffer(length: len, options: opts)
                              : a.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: opts) }
            b?.label = label
            return b
        }
        guard let rec = buffer(data.records, "canvas records"), let st = buffer(data.strokes, "canvas strokes"),
              let fi = buffer(data.fills, "canvas fills"), let tx = buffer(data.texts, "canvas texts"),
              let gl = buffer(data.glyphs, "canvas glyphs") else { return nil }
        let rd = MTLResidencySetDescriptor()
        rd.label = "canvas scene"
        rd.initialCapacity = 6
        guard let rs = try? device.makeResidencySet(descriptor: rd) else { return nil }
        for b in [rec, st, fi, tx, gl] { rs.addAllocation(b) }
        if let page = data.atlasPage { rs.addAllocation(page.texture) }
        rs.commit()
        records = rec; strokes = st; fills = fi; texts = tx; glyphs = gl
        residency = rs
        atlasPage = data.atlasPage
        self.viewID = viewID
        modelRevision = revision
        origin = data.origin
        recordCount = data.records.count
        chunks = data.chunks
        itemElementIDs = data.itemElementIDs
        itemStaticFlags = data.itemFlags
        rawColors = data.colors
        var map: [ElementID: [Int32]] = [:]
        for (i, id) in data.itemElementIDs.enumerated() { if let id { map[id, default: []].append(Int32(i)) } }
        elementItems = map
        let bytes = [rec, st, fi, tx, gl].reduce(0) { $0 + $1.length }
        statistics = Statistics(items: data.itemElementIDs.count, records: data.records.count, segments: data.segmentCount,
                                arcs: data.arcCount, triangles: data.triangleCount, glyphs: data.glyphCount, bytes: bytes,
                                buildSeconds: CFAbsoluteTimeGetCurrent() - started)
    }
}
