import Foundation

/// A triangle mesh with optional feature edges, in model meters.
///
/// `featureEdges` are pairs of vertex indices describing edges that should be
/// drawn as lines in hidden-line, wireframe and projection views (silhouette
/// candidates and crease edges). Triangulation diagonals are never feature edges.
public struct Mesh: Hashable, Sendable {
    public var positions: [Vec3]
    public var normals: [Vec3]
    public var indices: [UInt32]
    public var featureEdges: [UInt32]

    public init(positions: [Vec3] = [], normals: [Vec3] = [], indices: [UInt32] = [], featureEdges: [UInt32] = []) {
        self.positions = positions; self.normals = normals; self.indices = indices; self.featureEdges = featureEdges
    }

    public static let empty = Mesh()

    public var isEmpty: Bool { indices.isEmpty && featureEdges.isEmpty }
    public var triangleCount: Int { indices.count / 3 }
    public var bounds: Box3 { Box3(points: positions) }

    /// Appends another mesh (reindexing).
    public mutating func append(_ m: Mesh) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: m.positions)
        if m.normals.count == m.positions.count {
            if normals.count != positions.count - m.positions.count {
                normals = Array(repeating: .unitZ, count: positions.count - m.positions.count)
            }
            normals.append(contentsOf: m.normals)
        }
        indices.append(contentsOf: m.indices.map { $0 + base })
        featureEdges.append(contentsOf: m.featureEdges.map { $0 + base })
    }

    public func transformed(_ t: Transform3) -> Mesh {
        var m = self
        m.positions = positions.map(t.apply)
        let flip = t.determinant < 0
        m.normals = normals.map { t.applyVector($0).normalized }
        if flip {
            for i in stride(from: 0, to: m.indices.count, by: 3) { m.indices.swapAt(i + 1, i + 2) }
        }
        return m
    }

    /// Adds a planar convex or simple polygon face given in CCW order when seen from its normal side.
    /// Triangulated as a fan when convex; callers with concave faces should use `Triangulator`.
    public mutating func addConvexFace(_ pts: [Vec3], normal: Vec3, edges: Bool = true) {
        guard pts.count >= 3 else { return }
        let base = UInt32(positions.count)
        positions.append(contentsOf: pts)
        normals.append(contentsOf: Array(repeating: normal, count: pts.count))
        for i in 1..<(pts.count - 1) {
            indices.append(contentsOf: [base, base + UInt32(i), base + UInt32(i + 1)])
        }
        if edges {
            for i in 0..<pts.count {
                featureEdges.append(contentsOf: [base + UInt32(i), base + UInt32((i + 1) % pts.count)])
            }
        }
    }

    /// Axis-aligned box.
    public static func box(_ b: Box3) -> Mesh {
        var m = Mesh()
        let c = b.corners
        m.addConvexFace([c[0], c[3], c[2], c[1]], normal: -.unitZ)
        m.addConvexFace([c[4], c[5], c[6], c[7]], normal: .unitZ)
        m.addConvexFace([c[0], c[1], c[5], c[4]], normal: -.unitY)
        m.addConvexFace([c[1], c[2], c[6], c[5]], normal: .unitX)
        m.addConvexFace([c[2], c[3], c[7], c[6]], normal: .unitY)
        m.addConvexFace([c[3], c[0], c[4], c[7]], normal: -.unitX)
        return m
    }

    /// Total enclosed volume for closed meshes (divergence theorem).
    public var signedVolume: Double {
        var v = 0.0
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[i])], b = positions[Int(indices[i + 1])], c = positions[Int(indices[i + 2])]
            v += a.dot(b.cross(c)) / 6
        }
        return v
    }
    public var surfaceArea: Double {
        var s = 0.0
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[i])], b = positions[Int(indices[i + 1])], c = positions[Int(indices[i + 2])]
            s += (b - a).cross(c - a).length / 2
        }
        return s
    }
}
