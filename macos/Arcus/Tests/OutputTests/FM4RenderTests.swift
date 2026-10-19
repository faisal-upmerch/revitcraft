import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// FM4: the sample bookcase and table rendered as shop drawings (plan, front, side, section and 3D) to
/// /tmp/arcus-fm4/, for checking the casework drawings by eye; the test checks they draw.
@Suite("FM4 renders")
struct FM4RenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fm4")

    static func render(_ m: BIMModel, _ view: Element, _ name: String) -> Int {
        let g = ViewGraphicsBuilder(model: m, view: view).build()
        guard let img = RasterExporter.render(g, pixelWidth: 1400), let png = RasterExporter.encode(img, as: .png) else { return 0 }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        return g.items.count
    }

    static func withSection(_ m: BIMModel, along x: Bool) -> (BIMModel, Element) {
        let tx = TransactionContext(model: m, name: "Section")
        var v = ViewData(kind: .section, scale: 12)
        // A section through the middle, looking at the side (along +X) or the front (along +Y).
        v.planeOrigin = x ? Vec3(-0.01, 0, 0) : Vec3(0, -0.01, 0)
        v.viewDirection = x ? Vec2(1, 0) : Vec2(0, 1)
        v.farClip = 2
        v.detailLevel = .fine
        let id = tx.create(.views, name: "Section", data: .view(v))
        let r = try! tx.commit().model
        return (r, r[id]!)
    }

    @Test func bookcaseAndTableDrawAsShopDrawings() throws {
        let book = try #require(FurnitureSamples.bookcaseModel())
        let table = try #require(FurnitureSamples.tableModel())
        for (m, label) in [(book, "bookcase"), (table, "table")] {
            for v in m.views {
                guard let d = v.view, d.kind != .threeD || true else { continue }
                let n = Self.render(m, v, "\(label)-\(v.name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))")
                if d.kind == .floorPlan || d.kind == .elevation { #expect(n > 10, "\(label) \(v.name) draws") }
            }
            let (sm, sv) = Self.withSection(m, along: label == "bookcase")
            #expect(Self.render(sm, sv, "\(label)-section") > 5)
        }
        // The bookcase's back fits the carcass, and the plinth sits under the raised bottom.
        let back = try #require(book.elements(.furniturePanels).first { $0.furniturePanel?.role == .back })
        let bb = FurniturePartSolids.partBox(back, book)!.box
        #expect(abs(bb.max.z - (72 - 0.75) * 0.0254) < 1e-6 && abs(bb.min.z - (3.5 + 0.75) * 0.0254) < 1e-6, "\(bb)")
        #expect(book.elements(.furniturePanels).contains { $0.furniturePanel?.role == .plinth })
        #expect(table.elements(.furnitureLegs).count == 4 && table.elements(.furnitureRails).count == 4)
    }
}
