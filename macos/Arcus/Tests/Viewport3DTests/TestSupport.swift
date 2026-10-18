import Foundation
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

/// Synthetic BIM-like scenes for headless viewport tests and benchmarks.
enum SyntheticScene {
    /// A subdivided box (each face split into `n`×`n` quads) with per-face normals and its 12 outline edges.
    static func box(min lo: Vec3, max hi: Vec3, subdivisions n: Int = 4) -> Mesh {
        var m = Mesh()
        let faces: [(origin: Vec3, u: Vec3, v: Vec3, normal: Vec3)] = {
            let d = hi - lo
            return [
                (lo, Vec3(d.x, 0, 0), Vec3(0, 0, d.z), Vec3(0, -1, 0)),
                (Vec3(hi.x, hi.y, lo.z), Vec3(-d.x, 0, 0), Vec3(0, 0, d.z), Vec3(0, 1, 0)),
                (Vec3(lo.x, hi.y, lo.z), Vec3(0, -d.y, 0), Vec3(0, 0, d.z), Vec3(-1, 0, 0)),
                (Vec3(hi.x, lo.y, lo.z), Vec3(0, d.y, 0), Vec3(0, 0, d.z), Vec3(1, 0, 0)),
                (Vec3(lo.x, hi.y, lo.z), Vec3(d.x, 0, 0), Vec3(0, -d.y, 0), Vec3(0, 0, -1)),
                (Vec3(lo.x, lo.y, hi.z), Vec3(d.x, 0, 0), Vec3(0, d.y, 0), Vec3(0, 0, 1)),
            ]
        }()
        for f in faces {
            let base = UInt32(m.positions.count)
            for j in 0...n {
                for i in 0...n {
                    m.positions.append(f.origin + f.u * (Double(i) / Double(n)) + f.v * (Double(j) / Double(n)))
                    m.normals.append(f.normal)
                }
            }
            let row = UInt32(n + 1)
            for j in 0..<UInt32(n) {
                for i in 0..<UInt32(n) {
                    let a = base + j * row + i, b = a + 1, c = a + row, d = c + 1
                    m.indices += [a, b, d, a, d, c]
                }
            }
            // Outline of the face (duplicates across faces are fine for a benchmark).
            let c0 = base, c1 = base + UInt32(n), c2 = base + row * UInt32(n), c3 = c2 + UInt32(n)
            m.featureEdges += [c0, c1, c1, c3, c3, c2, c2, c0]
        }
        return m
    }

    /// `count` elements on a grid (≈192 triangles each with the default subdivision); every 10th is translucent glass.
    static func make(elements count: Int = 3000, subdivisions: Int = 4, revision: UInt64 = 1) -> Viewport3DScene {
        let side = Int(Double(count).squareRoot().rounded(.up))
        var elements: [SceneElement] = []
        elements.reserveCapacity(count)
        for k in 0..<count {
            let x = Double(k % side) * 3.0, y = Double(k / side) * 3.0
            let h = 2.0 + Double((k * 7919) % 13) * 0.5
            let mesh = box(min: Vec3(x, y, 0), max: Vec3(x + 2.2, y + 2.2, h), subdivisions: subdivisions)
            let glass = k % 10 == 0
            let color = glass ? RGBColor(0.55, 0.75, 0.85, 0.3) : RGBColor(0.55 + Double(k % 5) * 0.08, 0.5, 0.45 + Double(k % 3) * 0.1, 1)
            elements.append(SceneElement(id: ElementID(UInt64(k + 1)), category: glass ? .windows : .walls, parts: [ScenePart(mesh: mesh, color: color)]))
        }
        // Ground slab so shadows and ambient occlusion have something to land on.
        let extent = Double(side) * 3.0
        let ground = box(min: Vec3(-2, -2, -0.3), max: Vec3(extent + 2, extent + 2, 0), subdivisions: 1)
        elements.append(SceneElement(id: ElementID(UInt64(count + 1)), category: .floors, parts: [ScenePart(mesh: ground, color: RGBColor(0.7, 0.7, 0.68, 1))]))
        return Viewport3DScene(elements: elements, modelRevision: revision)
    }
}

extension SyntheticScene {
    /// A room corner: floor and two walls meeting at the origin, plus a column (ambient occlusion collects in the
    /// wall/floor junctions).
    static func corner() -> Viewport3DScene {
        let floor = box(min: Vec3(0, 0, -0.2), max: Vec3(10, 10, 0), subdivisions: 2)
        let wallA = box(min: Vec3(0, 0, 0), max: Vec3(10, 0.2, 3), subdivisions: 2)
        let wallB = box(min: Vec3(0, 0, 0), max: Vec3(0.2, 10, 3), subdivisions: 2)
        let column = box(min: Vec3(4, 4, 0), max: Vec3(4.5, 4.5, 3), subdivisions: 2)
        let parts: [(Mesh, ArcusDomain.Category)] = [(floor, .floors), (wallA, .walls), (wallB, .walls), (column, .columns)]
        return Viewport3DScene(elements: parts.enumerated().map { i, p in
            SceneElement(id: ElementID(UInt64(i + 1)), category: p.1, parts: [ScenePart(mesh: p.0, color: RGBColor(0.85, 0.85, 0.82, 1))])
        }, modelRevision: 7)
    }
}

enum Stats {
    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    static func percentile(_ v: [Double], _ p: Double) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
    }
}
