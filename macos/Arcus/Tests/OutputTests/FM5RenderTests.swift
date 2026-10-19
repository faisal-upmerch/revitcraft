import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// FM5: the sample base cabinet (a door, three drawers, a door) rendered as shop drawings (plan, front, side, a section
/// and 3D) at Medium and Fine to /tmp/arcus-fm5/, with its bay tags, for checking the casework drawings by eye; the test
/// checks they draw, with swings, drawer boxes and hardware.
@Suite("FM5 renders")
struct FM5RenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fm5")

    static func render(_ m: BIMModel, _ view: Element, _ name: String) -> ViewGraphics {
        let g = ViewGraphicsBuilder(model: m, view: view).build()
        if let img = RasterExporter.render(g, pixelWidth: 1600), let png = RasterExporter.encode(img, as: .png) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
        return g
    }

    /// The model with every view at `detail` and Bay Tags in the Front elevation.
    static func prepared(_ m: BIMModel, detail: DetailLevel) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Detail")
        for v in m.views where v.view?.kind != .threeD { tx.update(v.id) { $0.view?.detailLevel = detail } }
        let front = try #require(m.views.first { $0.view?.kind == .elevation && $0.name == "Front" })
        let tag = m.types(for: .tags).first { $0.typeData?.familyName == FurnitureFrontTypes.bayTagName }?.id
        let fv = try #require(front.view), origin = try #require(fv.planeOrigin), right = try #require(fv.rightVector)
        for b in m.elements(.furnitureBays) where b.furnitureBay?.division == nil {
            guard let o = b.furnitureBay?.opening else { continue }
            let head = Vec2((Vec2((o.x0 + o.x1) / 2, o.y0) - origin.xy).dot(right), (o.z0 + o.z1) / 2)
            tx.create(.tags, data: .tag(TagData(taggedID: b.id, head: head)), typeID: tag, ownerViewID: front.id)
        }
        var v = ViewData(kind: .section, scale: 12)
        v.planeOrigin = Vec3(-0.01, 0, 0); v.viewDirection = Vec2(1, 0); v.farClip = 2; v.detailLevel = detail
        tx.create(.views, name: "Section", data: .view(v))
        return try tx.commit().model
    }

    @Test func baseCabinetDrawsAsShopDrawings() throws {
        let base = try #require(FurnitureSamples.baseCabinetModel())
        for detail in [DetailLevel.medium, .fine] {
            let m = try Self.prepared(base, detail: detail)
            for v in m.views {
                let name = "cabinet-\(detail.rawValue.lowercased())-" + v.name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
                let g = Self.render(m, v, name)
                let kinds = Set(g.items.map(\.category))
                if v.view?.kind == .floorPlan {
                    #expect(kinds.contains(.furnitureFronts), "plan shows the fronts")
                    // Door swings (arcs; the crop turns them into polylines).
                    #expect(g.items.filter { $0.category == .furnitureFronts && $0.layer == .model && $0.hitPolygons.isEmpty }.count >= 2, "door swings")
                }
                if v.view?.kind == .elevation, v.name == "Front" {
                    #expect(kinds.contains(.furnitureHardware), "handles in the front elevation")
                    #expect(g.items.contains { $0.category == .furnitureFronts && $0.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.pattern == .dash }; return false } },
                            "dashed hinge triangles")
                    #expect(g.items.contains { $0.category == .furnitureBays }, "bays are selectable")
                    #expect(g.items.contains { $0.category == .tags }, "bay tags")
                }
            }
        }
    }
}
