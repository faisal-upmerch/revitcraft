import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

/// STAIR: stairs in 3D, rendered offscreen to `/tmp/arcus-stair/` for visual review: each kind of stair with its
/// railings, from two sides.
@MainActor
@Suite("STAIR stairs in 3D", .serialized)
struct STAIR3DRenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-stair")

    static func save(_ image: CGImage?, _ name: String) {
        guard let image else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appending(path: name + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// The model in the template's 3D view from `direction` (toward the camera), as a PNG.
    static func render(_ m: BIMModel, _ name: String, direction: Vec3, hideLevels: Bool = false) throws {
        var v3 = try #require(m.elements(.views).first { $0.view?.kind == .threeD })
        if hideLevels { v3.view?.visibility.hiddenCategories.insert(.levels) }
        let v = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 900, height: 640), backend: .classic)
        v.setScene(SceneBuilder.build(model: m, view: v3, detail: .fine))
        v.visualStyle = .shaded
        v.orient(toDirection: direction, animated: false)
        v.zoomExtents(animated: false)
        save(v.snapshot(size: CGSize(width: 900, height: 640)), name)
    }

    /// Stairs of each legacy shape with two hosted railings, and a multistory straight stair.
    static func stairs(_ shapes: [StairShape]) throws -> BIMModel {
        let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m, name: "Stairs")
        let rail = ids.systemTypes["Railing"]
        for (k, shape) in shapes.enumerated() {
            var s = StairData(shape: shape, origin: Vec2(Double(k) * 6, 0), direction: .pi / 2, width: 1.1, topLevelID: ids.levels[1])
            if k == shapes.count - 1 && shape == .straight { s.multistoryTopLevelID = ids.levels[2] }
            let sid = tx.create(.stairs, data: .stair(s), typeID: ids.systemTypes["Stair"], levelID: ids.levels[0])
            for left in [true, false] {
                var r = RailingData(path: [])
                r.followsHost = true; r.hostSideLeft = left
                tx.create(.railings, data: .railing(r), typeID: rail, levelID: ids.levels[0], hostID: sid)
            }
        }
        return try tx.commit().model
    }

    @Test func auditRenders() throws {
        let m = try Self.stairs([.straight, .lShaped, .uShaped, .straight])
        try Self.render(m, "audit-3d-sw", direction: Vec3(-1, -1.2, 0.9))
        try Self.render(m, "audit-3d-ne", direction: Vec3(1, 1.4, 0.7))
    }

    /// Component stairs of every kind (as Create Stair draws them) of one stair type, with railings.
    static func componentStairs(type name: String, only: Int? = nil) throws -> BIMModel {
        let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let type = try #require(m.types(for: .stairs).first { $0.name == name }?.id)
        let tx = TransactionContext(model: m, name: "Stairs")
        let up = Double.pi / 2, down = -Double.pi / 2
        func run(_ x: Double, _ y: Double, _ dir: Double, _ n: Int) -> StairRun { StairRun(start: Vec2(x, y), direction: dir, risers: n, width: 1.1) }
        var spiral = StairRun(shape: .spiral, start: Vec2(25.6, 3), direction: up, risers: 23, width: 1.1)
        spiral.center = Vec2(24, 3); spiral.turnsLeft = true
        var lw = StairRun(shape: .lWinder, start: Vec2(32, 0), direction: up, risers: 23, width: 1.1)
        lw.turnsLeft = true; lw.legTreads = [9]
        var uw = StairRun(shape: .uWinder, start: Vec2(40, 0), direction: up, risers: 23, width: 1.1)
        uw.turnsLeft = true; uw.legTreads = [8, 0]
        let sets: [[StairRun]] = [
            [run(0, 0, up, 23)],
            [run(8, 0, up, 12), run(8 - 0.55, 3.08 + 0.55, .pi, 11)],
            [run(16, 0, up, 12), run(16 - 1.3, 3.08, down, 11)],
            [spiral], [lw], [uw],
        ]
        for (k, runs) in sets.enumerated() where only == nil || only == k {
            var s = StairData(origin: runs[0].start, direction: runs[0].direction, width: 1.1, topLevelID: ids.levels[1])
            s.runs = runs
            let sid = tx.create(.stairs, data: .stair(s), typeID: type, levelID: ids.levels[0])
            for left in [true, false] {
                var r = RailingData(path: [])
                r.followsHost = true; r.hostSideLeft = left
                tx.create(.railings, data: .railing(r), typeID: ids.systemTypes["Railing"], levelID: ids.levels[0], hostID: sid)
            }
        }
        return try tx.commit().model
    }

    @Test func componentRenders() throws {
        for (type, tag) in [("Assembled - 175 max riser", "assembled"), ("Monolithic - 175 max riser", "monolithic"), ("Precast - 175 max riser", "precast")] {
            let m = try Self.componentStairs(type: type)
            #expect(m.elements(.stairs).allSatisfy { !StairGeometry.meshParts($0, m).isEmpty })
            try Self.render(m, "\(tag)-3d-sw", direction: Vec3(-1, -1.2, 0.9))
            try Self.render(m, "\(tag)-3d-ne", direction: Vec3(1, 1.4, 0.7))
        }
    }

    /// Close-ups of each kind.
    @Test func closeUps() throws {
        let kinds = ["straight", "l", "u", "spiral", "lwinder", "uwinder"]
        for (type, tag) in [("Assembled - 175 max riser", "assembled"), ("Monolithic - 175 max riser", "monolithic")] {
            for (k, kind) in kinds.enumerated() {
                let m = try Self.componentStairs(type: type, only: k)
                try Self.render(m, "\(tag)-3d-\(kind)", direction: Vec3(-1, -0.8, 0.7), hideLevels: true)
            }
        }
    }
}
