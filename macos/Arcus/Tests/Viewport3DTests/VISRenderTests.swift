import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusViewport3D

/// VIS: smooth curves, rendered offscreen to `/tmp/arcus-vis/` for visual review: round, tapered, turned and caster
/// legs, a hairpin leg, a round-over top edge, the sample bookcase and a curved wall, at Coarse, Medium and Fine, Shaded
/// (with edges) and Hidden Line.
@MainActor
@Suite("VIS smooth curves in 3D", .serialized)
struct VISRenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-vis")
    static let inch = 0.0254

    static func save(_ image: CGImage?, _ name: String) {
        guard let image else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let url = out.appending(path: name + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// The model's {3D} view at a detail level and style, from `direction` (toward the camera).
    static func render(_ m: BIMModel, _ name: String, detail: DetailLevel, style: VisualStyle, direction: Vec3 = Vec3(-1, -1.3, 0.8),
                       size: CGSize = CGSize(width: 700, height: 700)) throws {
        var v3 = try #require(m.elements(.views).first { $0.view?.kind == .threeD })
        v3.view?.visibility.hiddenCategories.formUnion([.levels, .referencePlanes, .grids])
        let v = Viewport3DView(frame: CGRect(origin: .zero, size: size), backend: .classic)
        v.setScene(SceneBuilder.build(model: m, view: v3, detail: detail))
        v.visualStyle = style
        v.showEdgesInShadedStyles = true
        v.orient(toDirection: direction, animated: false)
        v.zoomExtents(animated: false)
        save(v.snapshot(size: size), name)
    }

    /// A Furniture document with one leg of `type`.
    static func legModel(_ type: String, height: Double = 16) throws -> BIMModel {
        let m = FurnitureTemplates.blank(category: .furniture, name: type)
        let tx = TransactionContext(model: m, name: "Leg")
        FurniturePartTypes.ensureStandard(in: tx)
        let t = try #require(tx.model.types(for: .furnitureLegs).first { $0.name == type }?.id)
        _ = try FurniturePartOperations.createLeg(at: .zero, extent: PartExtent(topPlane: nil, height: height * inch), typeID: t, in: tx)
        return try tx.commit().model
    }

    /// A Furniture document with a small 1 1/2" butcher-block top (round-over edges all round).
    static func topModel() throws -> BIMModel {
        let m = FurnitureTemplates.blank(category: .furniture, name: "Top")
        let tx = TransactionContext(model: m, name: "Top")
        FurniturePartTypes.ensureStandard(in: tx)
        let w = 10 * inch, d = 6 * inch
        _ = try FurniturePartOperations.createShelf(boundary: [Vec2(-w / 2, -d / 2), Vec2(w / 2, -d / 2), Vec2(w / 2, d / 2), Vec2(-w / 2, d / 2)],
                                                    plane: "Top", offset: 0, role: .top,
                                                    typeID: tx.model.types(for: .furnitureShelves).first { $0.name == "1 1/2\" Butcher Block" }?.id, in: tx)
        return try tx.commit().model
    }

    /// A project with a curved wall (6 m radius, a quarter turn) and a tight one (1.5 m radius).
    static func curvedWallModel() throws -> BIMModel {
        let (m, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m, name: "Curved walls")
        let type = ids.wallTypes.values.sorted().first
        tx.create(.walls, data: .wall(WallData(location: .arc(Arc2(center: .zero, radius: 6, startAngle: 0, sweep: .pi / 2)), unconnectedHeight: 3)),
                  typeID: type, levelID: ids.levels[0])
        tx.create(.walls, data: .wall(WallData(location: .arc(Arc2(center: Vec2(8, 0), radius: 1.5, startAngle: 0, sweep: .pi)), unconnectedHeight: 3)),
                  typeID: type, levelID: ids.levels[0])
        return try tx.commit().model
    }

    static let styles: [(VisualStyle, String)] = [(.shaded, "shaded"), (.hiddenLine, "hidden")]

    static func all(_ m: BIMModel, _ tag: String, direction: Vec3 = Vec3(-1, -1.3, 0.8)) throws {
        for d in DetailLevel.allCases {
            for (s, st) in styles { try render(m, "\(tag)-\(d.rawValue.lowercased())-\(st)", detail: d, style: s, direction: direction) }
        }
    }

    @Test func roundLeg() throws { try Self.all(Self.legModel("Round 1 1/2\"", height: 8), "round-leg") }
    @Test func taperedLeg() throws { try Self.all(Self.legModel("Round Tapered 2\"", height: 10), "tapered-leg") }
    @Test func turnedLeg() throws { try Self.all(Self.legModel("Turned 2 1/2\"", height: 18), "turned-leg", direction: Vec3(-1, -1.3, 0.35)) }
    @Test func casterLeg() throws { try Self.all(Self.legModel("Caster 2\"", height: 3), "caster", direction: Vec3(-1.4, -1, 0.5)) }
    @Test func hairpinLeg() throws { try Self.all(Self.legModel("Hairpin 3/8\" Rod", height: 12), "hairpin") }
    @Test func roundOverTop() throws { try Self.all(Self.topModel(), "roundover-top", direction: Vec3(-1, -1.6, 0.5)) }
    @Test func bookcase() throws { try Self.all(try #require(FurnitureSamples.bookcaseModel()), "bookcase") }
    @Test func curvedWall() throws { try Self.all(Self.curvedWallModel(), "curved-wall", direction: Vec3(-0.6, -1, 0.7)) }
}
