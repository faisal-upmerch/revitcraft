import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// POLISH: Fabricate ▸ Shop Drawings on every essential library piece (and the sample base cabinet) gives a clean F101:
/// Part Tags beside the piece, clear of the drawing, the dimensions, the datum labels and each other, inside the sheet's
/// drawing area and off the other views; the sheets render to /tmp/arcus-polish/ for checking by eye.
@Suite("POLISH shop drawing tags")
struct POLISHShopDrawingTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-polish")

    /// Problems with F101 of a piece after Shop Drawings.
    static func problems(_ name: String, _ m: BIMModel) -> [String] {
        var out: [String] = []
        guard let f101 = m.sheets.first(where: { $0.sheet?.number == FurnitureShopDrawings.shopDrawing }) else { return ["\(name): no F101"] }
        let layouts = SheetGraphicsBuilder(model: m, sheet: f101).layouts().map(\.0)
        for viewName in ["Front", FurnitureShopDrawings.sectionName] {
            guard let v = m.views.first(where: { $0.name == viewName && $0.view?.kind != .nesting }), let vd = v.view else { continue }
            let tags = m.owned(byView: v.id).filter { $0.tag != nil }
            var wide = v
            wide.view?.annotationCropOffset = max(vd.annotationCropOffset, 0.06)
            let scene = FurnitureTagLayout.scene(ViewGraphicsBuilder(model: m, view: wide).build(), skipping: Set(tags.map(\.id)))
            let boxes = tags.compactMap { t in t.tag.map { (t, FurnitureTagLayout.box($0.head, scale: vd.scale)) } }
            func mark(_ e: Element) -> String { FurnitureJointParameters.mark(e.tag?.taggedID, m) }
            for (i, (t, b)) in boxes.enumerated() {
                if b.intersects(scene.outline) { out.append("\(name) \(viewName): \(mark(t)) covers the piece") }
                if let o = scene.obstacles.first(where: { $0.intersects(b) }) { out.append("\(name) \(viewName): \(mark(t)) covers an annotation at \(o)") }
                for (u, c) in boxes[(i + 1)...] where c.intersects(b) { out.append("\(name) \(viewName): \(mark(t)) overlaps \(mark(u))") }
                // On the sheet: inside the drawing area, and off every other view.
                guard let layout = layouts.first(where: { $0.viewID == v.id }) else { out.append("\(name): \(viewName) not on F101"); break }
                let paper = Rect2(points: b.corners.map(layout.transform.apply))
                if !FurnitureShopDrawings.drawingArea.contains(paper) { out.append("\(name) \(viewName): \(mark(t)) runs off the drawing area") }
                for other in layouts where other.viewID != v.id && other.box.intersects(paper) {
                    out.append("\(name) \(viewName): \(mark(t)) runs into \(m[other.viewID]?.name ?? "a view")")
                }
            }
            let tagged = Set(tags.compactMap { $0.tag?.taggedID })
            let wanted = Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles && $0 != .furnitureForms }.flatMap { m.elements($0) }.filter { e in
                !e.isType && (viewName == "Front") == (e.furniturePanel?.role != .back) && FurniturePartSolids.partBox(e, m) != nil
            }
            for e in wanted where !tagged.contains(e.id) { out.append("\(name) \(viewName): \(e.name) has no tag") }
        }
        return out
    }

    static func shopDrawings(_ base: BIMModel) throws -> BIMModel {
        let tx = TransactionContext(model: base, name: "Shop Drawings")
        FurnitureShopDrawings.update(in: tx)
        return try tx.commit().model
    }

    static func render(_ m: BIMModel, _ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for number in [FurnitureShopDrawings.shopDrawing, FurnitureShopDrawings.partList] {
            guard let s = m.sheets.first(where: { $0.sheet?.number == number }) else { continue }
            let g = SheetGraphicsBuilder(model: m, sheet: s).build()
            guard let img = RasterExporter.render(g, paper: s.sheet?.paper.landscapeSize, pixelWidth: 2200), let png = RasterExporter.encode(img, as: .png) else { continue }
            try png.write(to: dir.appendingPathComponent("\(number)-\(name.replacingOccurrences(of: " ", with: "-")).png"))
        }
    }

    @Test func theSampleCabinetsF101IsClean() throws {
        let m = try Self.shopDrawings(try #require(FurnitureSamples.baseCabinetModel()))
        let p = Self.problems("Base Cabinet", m)
        #expect(p.isEmpty, "\(p.joined(separator: "\n"))")
        try Self.render(m, "Base Cabinet")
    }

    @Test(arguments: FurnitureLibrary.essentials.map(\.name))
    func everyEssentialsF101IsClean(_ name: String) throws {
        let piece = try #require(FurnitureLibrary.essentials.first { $0.name == name })
        let m = try Self.shopDrawings(piece.build())
        let p = Self.problems(name, m)
        #expect(p.isEmpty, "\(p.prefix(10).joined(separator: "\n"))")
        try Self.render(m, name)
    }
}
