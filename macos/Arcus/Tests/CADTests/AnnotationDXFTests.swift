import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// W2-ANNOT: new line patterns and styled text in DXF export.
@Suite("DXF annotation styles")
struct AnnotationDXFTests {
    func graphics() -> ViewGraphics {
        let items = [
            GItem(elementID: ElementID(1), category: .detailLines, layer: .annotation,
                  primitives: [.polyline([Vec2(0, 0), Vec2(10, 0)], closed: false, GStroke(weight: 2, pattern: .dashDotDot))]),
            GItem(elementID: ElementID(2), category: .detailLines, layer: .annotation,
                  primitives: [.polyline([Vec2(0, 1), Vec2(10, 1)], closed: false, GStroke(weight: 1, pattern: .longDash))]),
            GItem(elementID: ElementID(3), category: .textNotes, layer: .annotation,
                  primitives: [.text(GText(position: Vec2(1, 2), height: 0.0025, string: "SEE {DETAIL}", italic: true, underline: true))]),
            GItem(elementID: ElementID(4), category: .textNotes, layer: .annotation,
                  primitives: [.text(GText(position: Vec2(1, 3), height: 0.0025, string: "PLAIN"))]),
        ]
        return ViewGraphics(viewID: ElementID(99), scale: 100, items: items, extents: Rect2(min: .zero, max: Vec2(10, 3)), crop: nil, modelRevision: 0)
    }

    @Test func newPatternsBecomeLineTypesAtTheViewScale() throws {
        let doc = try DXFReader.read(DXFWriter.write(graphics(), units: .millimeters), fileName: "styles.dxf")
        let ddd = try #require(doc.lineTypes.first { $0.name == "ARCUS_DASHDOTDOT" })
        #expect(ddd.pattern.count == 6)
        // 7 mm of paper at 1:100 = 700 mm in the drawing.
        #expect(abs(ddd.pattern[0] - 700) < 1e-6)
        #expect(ddd.pattern[1] < 0, "gaps are negative")
        #expect(doc.lineTypes.contains { $0.name == "ARCUS_LONGDASH" && $0.pattern.count == 2 })
        #expect(doc.modelSpace.contains { $0.props.lineType == "ARCUS_DASHDOTDOT" })
    }

    @Test func styledTextIsFormattedMText() throws {
        let doc = try DXFReader.read(DXFWriter.write(graphics(), units: .millimeters), fileName: "text.dxf")
        let mtexts = doc.modelSpace.compactMap { e -> CADMText? in if case .mtext(let m, _) = e { return m }; return nil }
        let styled = try #require(mtexts.first)
        #expect(styled.rawText.contains("\\L") && styled.rawText.contains("|i1"))
        #expect(styled.plainText == "SEE {DETAIL}")
        #expect(mtexts.count == 1, "plain single-line text stays TEXT")
    }
}
