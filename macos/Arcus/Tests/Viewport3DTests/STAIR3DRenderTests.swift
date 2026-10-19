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
    static func render(_ m: BIMModel, _ name: String, direction: Vec3) throws {
        let v3 = try #require(m.elements(.views).first { $0.view?.kind == .threeD })
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
}
