import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication
import ArcusOutput

/// FMG4: every library piece opens with its views at a standard furniture scale that follows its size (the library
/// had come out at 1/8" = 1'-0", where the plane names, dimensions and markers were drawn many times the piece's
/// size): the plan's and Front elevation's annotation text is at most a sixth of the piece's smallest plan dimension,
/// and the scale is one of 3" to 1/4" = 1'-0". A few pieces' plan and front render to /tmp/arcus-fmg4/library/.
@Suite("FMG4 library view scales")
struct FMG4LibraryScaleTests {
    static let inch = 0.0254
    static let rendered: Set<String> = ["Entryway Bench", "Side Table", "Sofa", "Wardrobe", "Key Organizer", "Bunk Bed"]

    @Test(arguments: FurnitureLibrary.all.map(\.name))
    func annotationsStaySmallBesideThePiece(_ name: String) throws {
        let piece = try #require(FurnitureLibrary.all.first { $0.name == name })
        let m = piece.build()
        let e = FurniturePlanes.extents(m)
        let mg = FurniturePlanes.margin
        let smallest = min(e.x.upperBound - e.x.lowerBound, e.y.upperBound - e.y.lowerBound) - 2 * mg
        for v in m.views where ["Ref. Level", "Front"].contains(v.name) && v.view?.kind != .nesting {
            let vd = try #require(v.view)
            #expect(FurnitureAutoScale.scales.contains(vd.scale), "\(name) \(v.name): 1:\(vd.scale)")
            let g = ViewGraphicsBuilder(model: m, view: v).build()
            var tallest = 0.0, what = ""
            for item in g.items { for case .text(let t) in item.primitives where t.height * Double(vd.scale) > tallest { tallest = t.height * Double(vd.scale); what = t.string } }
            #expect(tallest <= smallest / 6 + 1e-6, "\(name) \(v.name) at 1:\(vd.scale): “\(what)” is \(tallest / Self.inch)\" tall, the piece \(smallest / Self.inch)\"")
            if Self.rendered.contains(name), let img = RasterExporter.render(g, pixelWidth: 1100), let png = RasterExporter.encode(img, as: .png) {
                let dir = URL(fileURLWithPath: "/tmp/arcus-fmg4/library")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try png.write(to: dir.appendingPathComponent("\(name)-\(v.name).png".replacingOccurrences(of: " ", with: "-")))
            }
        }
    }
}
