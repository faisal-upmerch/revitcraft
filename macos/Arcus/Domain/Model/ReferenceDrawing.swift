import Foundation
import ArcusGeometry

/// Converted 2D reference content from CAD (DWG/DXF) or PDF, in drawing units already scaled to meters
/// and positioned relative to the drawing's insertion base. Immutable once created; stored content-addressed.
public struct ReferenceDrawing: Hashable, Codable, Sendable {
    public struct Layer: Hashable, Codable, Sendable {
        public var name: String
        public var color: RGBColor
        public var lineWeight: Double?     // paper mm, nil = default
        public var lineType: String
        public var isOn: Bool
        public var isFrozen: Bool
        public var isLocked: Bool
        public var plots: Bool
        public init(name: String, color: RGBColor = .black, lineWeight: Double? = nil, lineType: String = "Continuous",
                    isOn: Bool = true, isFrozen: Bool = false, isLocked: Bool = false, plots: Bool = true) {
            self.name = name; self.color = color; self.lineWeight = lineWeight; self.lineType = lineType
            self.isOn = isOn; self.isFrozen = isFrozen; self.isLocked = isLocked; self.plots = plots
        }
    }

    public struct Style: Hashable, Codable, Sendable {
        public var layer: Int
        public var color: RGBColor?
        public var lineWeight: Double?
        public var lineType: String?
        /// Source entity handle for diagnostics and reload matching.
        public var handle: String
        public init(layer: Int, color: RGBColor? = nil, lineWeight: Double? = nil, lineType: String? = nil, handle: String = "") {
            self.layer = layer; self.color = color; self.lineWeight = lineWeight; self.lineType = lineType; self.handle = handle
        }
    }

    public enum Entity: Hashable, Codable, Sendable {
        case line(Segment2, Style)
        case polyline([Vec2], closed: Bool, Style)
        case arc(Arc2, Style)
        case text(position: Vec2, height: Double, rotation: Double, text: String, alignment: TextAlignment, Style)
        case hatch(loops: [[Vec2]], solid: Bool, Style)
        /// Block reference: block name, transform, attribute values.
        case insert(block: String, transform: Transform2, attributes: [String: String], Style)
        case point(Vec2, Style)
        /// 3D face or solid kept as reference geometry (projected to plan for display).
        case face3D([Vec3], Style)
        /// Unsupported object retained by its bounds with an explanation.
        case proxy(bounds: Rect2, typeName: String, Style)
        /// External image reference (by file name) with placement.
        case imageRef(name: String, corners: [Vec2], Style)

        public var style: Style {
            switch self {
            case .line(_, let s), .polyline(_, _, let s), .arc(_, let s), .text(_, _, _, _, _, let s), .hatch(_, _, let s),
                 .insert(_, _, _, let s), .point(_, let s), .face3D(_, let s), .proxy(_, _, let s), .imageRef(_, _, let s):
                s
            }
        }
    }

    public var layers: [Layer]
    public var blocks: [String: [Entity]]
    public var entities: [Entity]
    /// Extents of model content in meters (after unit scaling).
    public var extents: Rect2
    public var metadata: [String: String]

    public init(layers: [Layer], blocks: [String: [Entity]] = [:], entities: [Entity], extents: Rect2, metadata: [String: String] = [:]) {
        self.layers = layers; self.blocks = blocks; self.entities = entities; self.extents = extents; self.metadata = metadata
    }

    /// Content-addressed key (stable hash of the encoded content).
    public var contentKey: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        // Never let unrelated drawings share a key: fall back to a unique key if encoding fails.
        guard let data = try? enc.encode(self), !data.isEmpty else { return "ref-" + UUID().uuidString.lowercased() }
        return "ref-" + StableHash.hex(data)
    }

    /// Flattens block inserts into world entities (bounded recursion depth for hostile input).
    public func flattened(maxDepth: Int = 32, maxEntities: Int = 500_000) -> [Entity] {
        var out: [Entity] = []
        func walk(_ ents: [Entity], _ t: Transform2, depth: Int) {
            for e in ents {
                if out.count >= maxEntities { return }
                switch e {
                case .insert(let name, let bt, _, _):
                    if depth < maxDepth, let b = blocks[name] { walk(b, t * bt, depth: depth + 1) }
                default:
                    out.append(e.transformed(t))
                }
            }
        }
        walk(entities, .identity, depth: 0)
        return out
    }
}

extension ReferenceDrawing.Entity {
    public func transformed(_ t: Transform2) -> ReferenceDrawing.Entity {
        if t == .identity { return self }
        switch self {
        case .line(let s, let st): return .line(s.transformed(t), st)
        case .polyline(let p, let c, let st): return .polyline(p.map(t.apply), closed: c, st)
        case .arc(let a, let st): return .arc(a.transformed(t), st)
        case .text(let p, let h, let r, let s, let al, let st):
            return .text(position: t.apply(p), height: h * t.uniformScale, rotation: r + t.rotationAngle, text: s, alignment: al, st)
        case .hatch(let loops, let solid, let st): return .hatch(loops: loops.map { $0.map(t.apply) }, solid: solid, st)
        case .insert(let b, let bt, let a, let st): return .insert(block: b, transform: t * bt, attributes: a, st)
        case .point(let p, let st): return .point(t.apply(p), st)
        case .face3D(let pts, let st): let t3 = Transform3(t); return .face3D(pts.map(t3.apply), st)
        case .proxy(let r, let n, let st): return .proxy(bounds: Rect2(points: r.corners.map(t.apply)), typeName: n, st)
        case .imageRef(let n, let c, let st): return .imageRef(name: n, corners: c.map(t.apply), st)
        }
    }
    public var bounds: Rect2 {
        switch self {
        case .line(let s, _): s.bounds
        case .polyline(let p, _, _): Rect2(points: p)
        case .arc(let a, _): a.bounds
        case .text(let p, let h, _, let s, _, _): Rect2(min: p, max: p + Vec2(h * 0.6 * Double(max(1, s.count)), h))
        case .hatch(let loops, _, _): Rect2(points: loops.flatMap { $0 })
        case .insert(_, let t, _, _): Rect2(points: [t.apply(.zero)])
        case .point(let p, _): Rect2(points: [p])
        case .face3D(let pts, _): Rect2(points: pts.map(\.xy))
        case .proxy(let r, _, _): r
        case .imageRef(_, let c, _): Rect2(points: c)
        }
    }
}

/// Small deterministic 128-bit FNV-style hash for content addressing (not cryptographic).
public enum StableHash {
    public static func hex(_ data: Data) -> String {
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x6c62272e07bb0142
        for b in data {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(b)) &* 0x100000001b3 &+ 0x9e3779b97f4a7c15
        }
        return String(format: "%016llx%016llx", h1, h2)
    }
    public static func hex(_ string: String) -> String { hex(Data(string.utf8)) }
}
