import Foundation
import Metal
import simd
import ArcusGeometry
import ArcusDomain

/// Mirrors `Uniforms` in the shader source.
nonisolated struct ViewportUniforms {
    var viewProj = matrix_identity_float4x4
    var pick = matrix_identity_float4x4
    var eye = SIMD4<Float>(0, 0, 0, 0)
    var viewDir = SIMD4<Float>(0, 1, 0, 0)
    var lightDir = SIMD4<Float>(0, 0, 1, 0)
    var clipPlanes: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (.zero, .zero, .zero, .zero, .zero, .zero)
    var selectionColor = SIMD4<Float>(0, 0, 1, 1)
    var preselectColor = SIMD4<Float>(0, 0, 1, 1)
    var edgeColor = SIMD4<Float>(0, 0, 0, 0)
    var capColor = SIMD4<Float>(0.3, 0.3, 0.3, 1)
    var faceColor = SIMD4<Float>(1, 1, 1, 1)
    var viewport = SIMD2<Float>(1, 1)
    var edgeWidth: Float = 1
    var faceAlpha: Float = 0.4
    var style: UInt32 = 2
    var clipEnabled: UInt32 = 0
    var flags: UInt32 = 0
    var edgePull: Float = 0
    var shadowMatrix = matrix_identity_float4x4
    var camRight = SIMD4<Float>(1, 0, 0, 0)
    var camUp = SIMD4<Float>(0, 0, 1, 0)
    var sunColor = SIMD4<Float>(3, 2.9, 2.7, 0)
    var skyZenith = SIMD4<Float>(0.16, 0.32, 0.66, 1)
    var skyHorizon = SIMD4<Float>(0.62, 0.72, 0.86, 1)
    var groundColor = SIMD4<Float>(0.42, 0.4, 0.37, 1)
    var backgroundTop = SIMD4<Float>(1, 1, 1, 1)
    var backgroundBottom = SIMD4<Float>(0.8, 0.8, 0.8, 1)
    var shadowParams = SIMD4<Float>(0, 0, 0, 1.25)
    var lightParams = SIMD4<Float>(1, 0.85, 1, 0)
    /// I1: flat tint laid over selected faces (linear), as RevitCraft's selection overlay.
    var selectionFace = SIMD4<Float>(0.108, 0.183, 0.508, 1)

    static let flagIncreaseContrast: UInt32 = 1
    static let flagShadows: UInt32 = 2
    static let flagSky: UInt32 = 4
}

/// Mirrors `PostUniforms` in the shader source.
nonisolated struct PostUniforms {
    var proj = SIMD4<Float>.zero
    var sizes = SIMD4<Float>.zero
    var ao = SIMD4<Float>.zero
    var silhouette = SIMD4<Float>.zero
    var silhouetteColor = SIMD4<Float>(0, 0, 0, 1)
    var flags: UInt32 = 0
    var pad0: UInt32 = 0
    var pad1: UInt32 = 0
    var pad2: UInt32 = 0

    static let flagAO: UInt32 = 1
    static let flagSilhouettes: UInt32 = 2
    static let flagPerspective: UInt32 = 4
}

/// Mirrors `OverlayVertex` in the shader source.
nonisolated struct OverlayVertex {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var color: SIMD4<Float>
    var offset: SIMD2<Float>
    var width: Float
    var mode: Float
}

/// Mirrors `Vertex` in the shader source (24 bytes).
nonisolated struct PackedVertex {
    var x: Float, y: Float, z: Float
    var normal: UInt32    // snorm8 x, y, z, w = surface finish
    var element: UInt32
    var color: UInt32     // rgba8 sRGB
}

/// GPU-resident batched scene: one vertex buffer, opaque/transparent triangle index buffers and one edge buffer.
/// Positions are Float32 relative to `origin` (the scene center). No CPU copy of vertex data is retained.
///
/// Geometry lives in private storage (GPU-only memory, eligible for lossless compression and never CPU-mapped); it is
/// streamed there through two small write-combined staging buffers and blit copies, so peak extra memory during an
/// upload is 2 × `SceneUploader.chunkBytes` regardless of model size.
@MainActor final class GPUScene {
    let origin: SIMD3<Double>
    let bounds: Box3
    let signature: Int
    let elementIDs: [ElementID]
    let elementBounds: [Box3]
    let elementCategories: [ArcusDomain.Category]
    let indexOf: [ElementID: Int]
    let vertexBuffer: (any MTLBuffer)?
    let opaqueIndexBuffer: (any MTLBuffer)?
    let transparentIndexBuffer: (any MTLBuffer)?
    let edgeBuffer: (any MTLBuffer)?
    /// VIS: silhouette candidates, four words each (vertex a, vertex b, packed normals of the two faces).
    let silhouetteBuffer: (any MTLBuffer)?
    let silhouetteCount: Int
    let opaqueIndexCount: Int
    let transparentIndexCount: Int
    let edgeCount: Int
    let triangleCount: Int
    let uploadMilliseconds: Double

    var elementCount: Int { elementIDs.count }
    var bufferBytes: Int {
        [vertexBuffer, opaqueIndexBuffer, transparentIndexBuffer, edgeBuffer, silhouetteBuffer].reduce(0) { $0 + ($1?.length ?? 0) }
    }
    /// Buffers to keep resident while the scene is displayed.
    var allocations: [any MTLAllocation] {
        [vertexBuffer, opaqueIndexBuffer, transparentIndexBuffer, edgeBuffer, silhouetteBuffer].compactMap { $0 }
    }

    init(scene: Viewport3DScene, device: any MTLDevice, uploader: SceneUploader? = nil) {
        let t0 = CFAbsoluteTimeGetCurrent()
        bounds = scene.bounds
        signature = scene.signature
        let o = scene.bounds.isEmpty ? SIMD3<Double>(0, 0, 0) : scene.bounds.center.simd
        origin = o

        // Pass 1: sizes.
        var vCount = 0, opaqueCount = 0, transCount = 0, eCount = 0, sCount = 0
        for e in scene.elements {
            for p in e.parts {
                vCount += p.mesh.positions.count
                if p.color.a < 0.99 { transCount += p.mesh.indices.count } else { opaqueCount += p.mesh.indices.count }
                eCount += p.mesh.featureEdges.count / 2
                if p.silhouetteNormals.count == p.silhouetteEdges.count { sCount += p.silhouetteEdges.count / 2 } // VIS
            }
        }
        let up = uploader ?? SceneUploader(device: device)
        func make(_ bytes: Int, _ label: String) -> (any MTLBuffer)? {
            guard bytes > 0 else { return nil }
            let b = up.makeDestination(length: bytes)
            b?.label = label
            return b
        }
        let vb = make(vCount * MemoryLayout<PackedVertex>.stride, "Viewport vertices")
        let ob = make(opaqueCount * 4, "Viewport opaque indices")
        let tb = make(transCount * 4, "Viewport transparent indices")
        let eb = make(eCount * 8, "Viewport edges")
        let sb = make(sCount * 16, "Viewport silhouettes") // VIS

        // Pass 2: stream into the private buffers (write-combined staging, sequential writes only).
        var ids: [ElementID] = []; ids.reserveCapacity(scene.elements.count)
        var bnds: [Box3] = []; bnds.reserveCapacity(scene.elements.count)
        var cats: [ArcusDomain.Category] = []; cats.reserveCapacity(scene.elements.count)
        var map: [ElementID: Int] = [:]; map.reserveCapacity(scene.elements.count)
        var vi = 0, oi = 0, ti = 0, ei = 0, si = 0
        var tris = 0
        for (index, e) in scene.elements.enumerated() {
            ids.append(e.id); bnds.append(e.bounds); cats.append(e.category); map[e.id] = index
            let elem = UInt32(index)
            for p in e.parts {
                let m = p.mesh
                let base = UInt32(vi)
                let color = GPUScene.packColor(p.color)
                let finish = p.finish.packed << 24
                let normals = m.normals.count == m.positions.count ? m.normals : GPUScene.computeNormals(m)
                if let vb, !m.positions.isEmpty {
                    let positions = m.positions
                    up.write(PackedVertex.self, count: positions.count, to: vb, at: vi * MemoryLayout<PackedVertex>.stride) { dst, range in
                        var j = 0
                        for k in range {
                            let q = positions[k]
                            dst[j] = PackedVertex(x: Float(q.x - o.x), y: Float(q.y - o.y), z: Float(q.z - o.z),
                                                  normal: GPUScene.packNormal(normals[k]) | finish, element: elem, color: color)
                            j += 1
                        }
                    }
                    vi += positions.count
                }
                let transparent = p.color.a < 0.99
                if !m.indices.isEmpty, let target = transparent ? tb : ob {
                    let at = transparent ? ti : oi
                    let indices = m.indices
                    up.write(UInt32.self, count: indices.count, to: target, at: at * 4) { dst, range in
                        var j = 0
                        for k in range { dst[j] = indices[k] + base; j += 1 }
                    }
                    if transparent { ti += indices.count } else { oi += indices.count }
                }
                let edgeValues = m.featureEdges.count / 2 * 2
                if let eb, edgeValues > 0 {
                    let edges = m.featureEdges
                    up.write(UInt32.self, count: edgeValues, to: eb, at: ei * 4) { dst, range in
                        var j = 0
                        for k in range { dst[j] = edges[k] + base; j += 1 }
                    }
                    ei += edgeValues
                }
                // VIS: silhouette candidates with their two face normals.
                let silCount = p.silhouetteNormals.count == p.silhouetteEdges.count ? p.silhouetteEdges.count / 2 : 0
                if let sb, silCount > 0 {
                    let edges = p.silhouetteEdges, normals = p.silhouetteNormals
                    up.write(UInt32.self, count: silCount * 4, to: sb, at: si * 16) { dst, range in
                        var j = 0
                        for k in range {
                            let e = k / 4
                            switch k % 4 {
                            case 0: dst[j] = edges[2 * e] + base
                            case 1: dst[j] = edges[2 * e + 1] + base
                            case 2: dst[j] = GPUScene.packNormal(normals[2 * e])
                            default: dst[j] = GPUScene.packNormal(normals[2 * e + 1])
                            }
                            j += 1
                        }
                    }
                    si += silCount
                }
                tris += m.triangleCount
            }
        }
        up.finish()
        vertexBuffer = vb; opaqueIndexBuffer = ob; transparentIndexBuffer = tb; edgeBuffer = eb
        silhouetteBuffer = sb; silhouetteCount = sCount
        opaqueIndexCount = opaqueCount; transparentIndexCount = transCount; edgeCount = eCount
        triangleCount = tris
        elementIDs = ids; elementBounds = bnds; elementCategories = cats; indexOf = map
        uploadMilliseconds = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    nonisolated static func packColor(_ c: RGBColor) -> UInt32 {
        func b(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return b(c.r) | (b(c.g) << 8) | (b(c.b) << 16) | (b(c.a) << 24)
    }

    nonisolated static func packNormal(_ n: Vec3) -> UInt32 {
        func s(_ v: Double) -> UInt32 { UInt32(bitPattern: Int32(Int8(max(-127, min(127, (v * 127).rounded()))))) & 0xff }
        return s(n.x) | (s(n.y) << 8) | (s(n.z) << 16)
    }

    /// Area-weighted vertex normals for meshes without normals.
    nonisolated static func computeNormals(_ m: Mesh) -> [Vec3] {
        var n = Array(repeating: Vec3.zero, count: m.positions.count)
        var i = 0
        while i + 2 < m.indices.count {
            let a = Int(m.indices[i]), b = Int(m.indices[i + 1]), c = Int(m.indices[i + 2])
            if a < n.count, b < n.count, c < n.count {
                let fn = (m.positions[b] - m.positions[a]).cross(m.positions[c] - m.positions[a])
                n[a] += fn; n[b] += fn; n[c] += fn
            }
            i += 3
        }
        return n.map { $0.lengthSquared > 0 ? $0.normalized : .unitZ }
    }
}

/// Streams CPU-generated data into private GPU buffers through two ping-ponged staging buffers and blit copies.
///
/// Uses a classic `MTLCommandQueue` for both backends: the copies complete (`finish()` waits) before any frame uses
/// the destination buffers, so no cross-queue synchronization is needed.
@MainActor final class SceneUploader {
    static let chunkBytes = 8 << 20

    let device: any MTLDevice
    private let queue: (any MTLCommandQueue)?
    /// Private storage needs a GPU copy; devices without a queue fall back to shared buffers written in place.
    private let usePrivate: Bool
    private var staging: [any MTLBuffer] = []
    private var inFlight: [(any MTLCommandBuffer)?] = [nil, nil]
    private var current = 0
    private var cursor = 0
    private var copies: [(dst: any MTLBuffer, dstOffset: Int, srcOffset: Int, size: Int)] = []
    private(set) var bytesCopied = 0

    init(device: any MTLDevice) {
        self.device = device
        queue = device.makeCommandQueue()
        queue?.label = "Arcus viewport upload"
        usePrivate = queue != nil
    }

    /// A destination buffer: private (GPU-only), untracked (static after upload; frames never write it).
    func makeDestination(length: Int) -> (any MTLBuffer)? {
        if usePrivate {
            return device.makeBuffer(length: length, options: [.storageModePrivate, .hazardTrackingModeUntracked])
        }
        return device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined])
    }

    /// Writes `count` elements of `T` to `dst` at byte offset `offset`. `body` fills `(pointer, index range)` chunks
    /// sequentially; chunks never exceed the staging buffer.
    func write<T>(_ type: T.Type, count: Int, to dst: any MTLBuffer, at offset: Int,
                  _ body: (UnsafeMutablePointer<T>, Range<Int>) -> Void) {
        let stride = MemoryLayout<T>.stride
        guard usePrivate else {
            let p = (dst.contents() + offset).bindMemory(to: T.self, capacity: count)
            body(p, 0..<count)
            return
        }
        var done = 0
        while done < count {
            if staging.isEmpty { allocateStaging() }
            cursor = (cursor + 15) & ~15
            if SceneUploader.chunkBytes - cursor < stride { flush() }
            let room = (SceneUploader.chunkBytes - cursor) / stride
            let n = min(room, count - done)
            let p = (staging[current].contents() + cursor).bindMemory(to: T.self, capacity: n)
            body(p, done..<(done + n))
            copies.append((dst, offset + done * stride, cursor, n * stride))
            cursor += n * stride
            done += n
        }
    }

    /// Submits pending copies and waits for all of them; releases the staging memory.
    func finish() {
        guard usePrivate else { return }
        flush()
        for cb in inFlight { cb?.waitUntilCompleted() }
        inFlight = [nil, nil]
        staging.removeAll()
        cursor = 0
    }

    private func allocateStaging() {
        for i in 0..<2 {
            if let b = device.makeBuffer(length: SceneUploader.chunkBytes, options: [.storageModeShared, .cpuCacheModeWriteCombined]) {
                b.label = "Viewport upload staging \(i)"
                staging.append(b)
            }
        }
        current = 0; cursor = 0
    }

    private func flush() {
        guard !copies.isEmpty, let queue, let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { cursor = 0; return }
        let src = staging[current]
        for c in copies {
            blit.copy(from: src, sourceOffset: c.srcOffset, to: c.dst, destinationOffset: c.dstOffset, size: c.size)
            bytesCopied += c.size
        }
        blit.endEncoding()
        cb.commit()
        copies.removeAll(keepingCapacity: true)
        inFlight[current] = cb
        current = (current + 1) % staging.count
        inFlight[current]?.waitUntilCompleted()
        inFlight[current] = nil
        cursor = 0
    }
}
