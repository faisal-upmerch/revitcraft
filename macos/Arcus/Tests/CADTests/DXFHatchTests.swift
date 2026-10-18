import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

// W4-HATCH: project fill patterns go out as HATCH entities with their own pattern definition lines.

@Suite("DXF hatch patterns")
struct DXFHatchTests {
    func graphics(_ fill: GFill, scale: Int = 100) -> ViewGraphics {
        let item = GItem(elementID: ElementID(1), category: .walls, layer: .cut, primitives: [
            .fill([Polygon2([Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)]), Polygon2([Vec2(1, 1), Vec2(2, 1), Vec2(2, 2), Vec2(1, 2)])], fill),
        ])
        return ViewGraphics(viewID: ElementID(9), scale: scale, items: [item], extents: Rect2(min: .zero, max: Vec2(4, 4)), crop: nil, modelRevision: 1)
    }

    /// Group code / value pairs of the first HATCH entity.
    func hatchPairs(_ text: String) -> [(Int, String)] {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let start = lines.firstIndex(of: "HATCH") else { return [] }
        var out: [(Int, String)] = []
        var i = start + 1
        while i + 1 < lines.count, !(lines[i] == "0") {
            if let code = Int(lines[i]) { out.append((code, lines[i + 1])) }
            i += 2
        }
        return out
    }

    @Test func projectPatternWritesDefinitionLinesInDrawingUnits() throws {
        // Concrete block: 45°/135° crosshatch 4 mm on paper → at 1:100 in a millimetre DXF that is 400 drawing units.
        let d = try #require(FillPatternLibrary.named("Masonry - Concrete Block")).data
        let fill = GFill(fillPattern: d, color: .black, background: .white)
        let data = DXFWriter.write(graphics(fill), units: .millimeters)
        let text = String(decoding: data, as: UTF8.self)
        let pairs = hatchPairs(text)
        let name = try #require(pairs.first { $0.0 == 2 }?.1)
        #expect(name.hasPrefix("ARCUS_DIAGONAL_CROSSHATCH_"))
        #expect(pairs.first { $0.0 == 70 }?.1 == "0")         // not solid
        #expect(pairs.first { $0.0 == 78 }?.1 == "2")         // two definition lines
        let angles = pairs.filter { $0.0 == 53 }.map { Double($0.1)! }
        #expect(angles == [45, 135])
        let offsets = pairs.filter { $0.0 == 45 || $0.0 == 46 }.map { abs(Double($0.1)!) }
        // Offset vector = spacing × normal: 400 × (sin 45°, cos 45°) ≈ 282.84 for both components.
        #expect(offsets.allSatisfy { abs($0 - 282.84) < 0.05 }, "\(offsets)")
        #expect(pairs.filter { $0.0 == 79 }.allSatisfy { $0.1 == "0" })   // continuous lines: no dashes
        // The two loops (outer and hole) are still written.
        #expect(pairs.first { $0.0 == 91 }?.1 == "2")
        // Our own reader still reads it as a hatch.
        let doc = try DXFReader.read(data, fileName: "hatch.dxf")
        #expect(doc.entityCounts["HATCH"] == 1 && doc.warnings.isEmpty)
    }

    @Test func dashedAndModelPatternsKeepDashesAndModelSize() throws {
        let d = try #require(FillPatternLibrary.named("Brick")).data   // model running bond 225 × 75 mm
        let data = DXFWriter.write(graphics(GFill(fillPattern: d, color: .black), scale: 50), units: .meters)
        let pairs = hatchPairs(String(decoding: data, as: UTF8.self))
        #expect(pairs.first { $0.0 == 78 }?.1 == "3")
        // Bed joints: horizontal lines 75 mm apart → 0.075 m offset in y, independent of the 1:50 scale.
        let firstOffsetY = try #require(pairs.first { $0.0 == 46 }.flatMap { Double($0.1) })
        #expect(abs(firstOffsetY - 0.075) < 1e-6)
        let dashes = pairs.filter { $0.0 == 49 }.compactMap { Double($0.1) }
        #expect(dashes.count == 4 && dashes.contains { abs($0 - 0.075) < 1e-9 } && dashes.contains { abs($0 + 0.075) < 1e-9 })
    }

    @Test func fillsWithoutProjectPatternsStillWriteANSI31AndSolid() throws {
        let hatch = String(decoding: DXFWriter.write(graphics(GFill(pattern: .diagonalUp)), units: .millimeters), as: UTF8.self)
        #expect(hatchPairs(hatch).first { $0.0 == 2 }?.1 == "ANSI31")
        let solid = String(decoding: DXFWriter.write(graphics(GFill(pattern: .solid, color: .black)), units: .millimeters), as: UTF8.self)
        #expect(hatchPairs(solid).first { $0.0 == 2 }?.1 == "SOLID")
    }
}
