import Foundation
import ArcusGeometry
import ArcusDomain

/// Surface response used by the Realistic visual style (roughness 0 = mirror, 1 = fully diffuse).
nonisolated public struct SurfaceFinish: Hashable, Sendable {
    public var roughness: Double
    public var metallic: Bool
    public init(roughness: Double = 0.85, metallic: Bool = false) { self.roughness = roughness; self.metallic = metallic }

    public static let matte = SurfaceFinish()

    /// Typical finish for a material class.
    public static func typical(for c: MaterialClass) -> SurfaceFinish {
        switch c {
        case .metal: SurfaceFinish(roughness: 0.35, metallic: true)
        case .glass, .liquid: SurfaceFinish(roughness: 0.06)
        case .ceramic: SurfaceFinish(roughness: 0.3)
        case .plastic, .paint: SurfaceFinish(roughness: 0.5)
        case .wood: SurfaceFinish(roughness: 0.65)
        case .stone: SurfaceFinish(roughness: 0.6)
        case .concrete, .masonry, .plaster, .insulation, .earth, .gas, .generic: .matte
        }
    }

    /// GPU encoding (the `w` byte of the packed normal): bits 0-3 roughness, bit 4 metallic.
    var packed: UInt32 {
        let r = UInt32(max(0, min(15, (roughness * 15).rounded())))
        return r | (metallic ? 16 : 0)
    }
}

/// One piece of an element's 3D geometry with its display color.
/// `color.a` is opacity (`1 - material transparency`).
nonisolated public struct ScenePart: Sendable {
    public var mesh: Mesh
    public var color: RGBColor
    public var finish: SurfaceFinish
    public init(mesh: Mesh, color: RGBColor, finish: SurfaceFinish = .matte) { self.mesh = mesh; self.color = color; self.finish = finish }
}

/// A visible model element prepared for the 3D viewport.
nonisolated public struct SceneElement: Sendable {
    public var id: ElementID
    public var category: ArcusDomain.Category
    public var parts: [ScenePart]
    public var bounds: Box3
    public init(id: ElementID, category: ArcusDomain.Category, parts: [ScenePart], bounds: Box3? = nil) {
        self.id = id; self.category = category; self.parts = parts
        self.bounds = bounds ?? parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }
    public var triangleCount: Int { parts.reduce(0) { $0 + $1.mesh.triangleCount } }
}

/// Everything the viewport draws. Built off the main actor by `SceneBuilder`, handed to `Viewport3DView.setScene`.
nonisolated public struct Viewport3DScene: Sendable {
    public var elements: [SceneElement]
    public var bounds: Box3
    public var modelRevision: UInt64
    public init(elements: [SceneElement], bounds: Box3? = nil, modelRevision: UInt64) {
        self.elements = elements
        self.bounds = bounds ?? elements.reduce(Box3.empty) { $0.union($1.bounds) }
        self.modelRevision = modelRevision
    }
    public static let empty = Viewport3DScene(elements: [], bounds: .empty, modelRevision: 0)

    public var triangleCount: Int { elements.reduce(0) { $0 + $1.triangleCount } }

    /// Cheap content signature used to skip redundant GPU uploads (revision + element set + geometry size).
    public var signature: Int {
        var h = Hasher()
        h.combine(modelRevision)
        h.combine(elements.count)
        for e in elements {
            h.combine(e.id)
            h.combine(e.parts.count)
            for p in e.parts { h.combine(p.mesh.positions.count); h.combine(p.mesh.indices.count); h.combine(p.color); h.combine(p.finish) }
        }
        return h.finalize()
    }
}

/// Standard camera orientations. Front looks north (camera south of the model); right looks west (camera east).
nonisolated public enum OrientationPreset: String, CaseIterable, Sendable {
    case top, bottom, front, back, left, right, northEastIso, northWestIso, southEastIso, southWestIso, home

    /// Human-readable name for menus and accessibility.
    public var title: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .front: "Front (South)"
        case .back: "Back (North)"
        case .left: "Left (West)"
        case .right: "Right (East)"
        case .northEastIso: "Northeast Isometric"
        case .northWestIso: "Northwest Isometric"
        case .southEastIso: "Southeast Isometric"
        case .southWestIso: "Southwest Isometric"
        case .home: "Home"
        }
    }

    /// Unit vector from the model toward the camera (nil for `.home`).
    public var viewFromDirection: Vec3? {
        let d = 1 / 3.0.squareRoot()
        switch self {
        case .top: return .unitZ
        case .bottom: return -.unitZ
        case .front: return -.unitY
        case .back: return .unitY
        case .left: return -.unitX
        case .right: return .unitX
        case .northEastIso: return Vec3(d, d, d)
        case .northWestIso: return Vec3(-d, d, d)
        case .southEastIso: return Vec3(d, -d, d)
        case .southWestIso: return Vec3(-d, -d, d)
        case .home: return nil
        }
    }

    /// Camera up vector for this orientation.
    public var up: Vec3 {
        switch self {
        case .top: .unitY
        case .bottom: .unitY
        default: .unitZ
        }
    }
}

/// Rendering statistics for diagnostics and QA.
nonisolated public struct ViewportStatistics: Sendable {
    /// Triangles submitted per frame (scene faces).
    public var triangles: Int
    /// Draw calls encoded in the last frame.
    public var drawCalls: Int
    /// GPU time of the last completed frame (ms). Falls back to CPU encode time when GPU timing is unavailable.
    public var lastFrameMilliseconds: Double
    /// Bytes held in GPU buffers for the scene.
    public var bufferBytes: Int
    /// Elements in the scene.
    public var elements: Int
    /// Feature edges drawn (line segments).
    public var edges: Int
    /// CPU time spent encoding the last frame (ms).
    public var cpuEncodeMilliseconds: Double
    /// Time spent in the last scene upload (ms).
    public var lastUploadMilliseconds: Double
    /// Command API in use ("Metal 4" or "Metal").
    public var backend: String = ""
    /// Bytes held by render targets that occupy memory (memoryless MSAA/depth attachments count as zero).
    public var renderTargetBytes: Int = 0
    /// Render resolution scale of the last frame (below 1 while MetalFX upscales during interaction).
    public var renderScale: Double = 1
    /// Frames rendered since the view was created (idle views do not render).
    public var framesRendered: Int = 0

    public init(triangles: Int = 0, drawCalls: Int = 0, lastFrameMilliseconds: Double = 0, bufferBytes: Int = 0,
                elements: Int = 0, edges: Int = 0, cpuEncodeMilliseconds: Double = 0, lastUploadMilliseconds: Double = 0) {
        self.triangles = triangles; self.drawCalls = drawCalls; self.lastFrameMilliseconds = lastFrameMilliseconds
        self.bufferBytes = bufferBytes; self.elements = elements; self.edges = edges
        self.cpuEncodeMilliseconds = cpuEncodeMilliseconds; self.lastUploadMilliseconds = lastUploadMilliseconds
    }
}
