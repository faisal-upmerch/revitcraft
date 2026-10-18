import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

@Suite("DXF writer")
struct DXFWriterTests {
    func sampleGraphics(scale: Int = 100) -> ViewGraphics {
        let wallStroke = GStroke(weight: 5, color: .black)
        let doorStroke = GStroke(weight: 2, color: RGBColor(0.8, 0.1, 0.1), pattern: .dash)
        let items = [
            GItem(elementID: ElementID(1), category: .walls, layer: .cut, primitives: [
                .polyline([Vec2(1, 2), Vec2(11, 2), Vec2(11, 8), Vec2(1, 8)], closed: true, wallStroke),
                .fill([Polygon2([Vec2(1, 2), Vec2(11, 2), Vec2(11, 2.2), Vec2(1, 2.2)])], GFill(pattern: .solid, color: RGBColor(0.3, 0.3, 0.3))),
                .fill([Polygon2([Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)]), Polygon2([Vec2(1, 1), Vec2(2, 1), Vec2(2, 2), Vec2(1, 2)])],
                      GFill(pattern: .diagonalUp)),
            ]),
            GItem(elementID: ElementID(2), category: .doors, layer: .model, primitives: [
                .arc(Arc2(center: Vec2(5, 2), radius: 0.9, startAngle: 0, sweep: .pi / 2), doorStroke),
                .arc(Arc2(center: Vec2(8, 5), radius: 0.3, startAngle: 0, sweep: -.pi / 2), doorStroke),
                .arc(Arc2(center: Vec2(3, 5), radius: 0.25, startAngle: 0, sweep: 2 * .pi), wallStroke),
            ]),
            GItem(elementID: ElementID(3), category: .textNotes, layer: .annotation, primitives: [
                .text(GText(position: Vec2(2, 6), height: 0.0025, string: "Größe ÅΩ 中")),
                .text(GText(position: Vec2(6, 6), height: 0.0035, string: "CENTER", rotation: .pi / 6, alignment: .center, verticalAnchor: 0.5)),
                .text(GText(position: Vec2(2, 4), height: 0.0025, string: "Line one\nLine two", wrapWidth: 0.05)),
            ]),
        ]
        return ViewGraphics(viewID: ElementID(99), scale: scale, items: items, extents: Rect2(min: .zero, max: Vec2(11, 8)), crop: nil, modelRevision: 1)
    }

    @Test func roundTripThroughOwnReader() throws {
        let data = DXFWriter.write(sampleGraphics(), units: .millimeters)
        let doc = try DXFReader.read(data, fileName: "export.dxf")
        #expect(doc.version == "AC1015")
        #expect(doc.units == .millimeters)
        #expect(doc.warnings.isEmpty)
        #expect(Set(doc.layers.map(\.name)).isSuperset(of: ["0", "Walls", "Doors", "Text Notes"]))
        #expect(doc.entityCounts == ["LWPOLYLINE": 1, "HATCH": 2, "ARC": 2, "CIRCLE": 1, "TEXT": 2, "MTEXT": 1])
        guard case .polyline(let p, let props)? = doc.modelSpace.first(where: { $0.typeName == "LWPOLYLINE" }) else { Issue.record("no polyline"); return }
        #expect(p.closed)
        #expect(p.points2D == [Vec2(1000, 2000), Vec2(11000, 2000), Vec2(11000, 8000), Vec2(1000, 8000)])
        #expect(props.layer == "Walls")
        #expect(props.lineWeight != nil)
        #expect(!props.handle.isEmpty)
        let texts = doc.modelSpace.compactMap { e -> CADText? in if case .text(let t, _) = e { return t }; return nil }
        #expect(texts.contains { $0.text == "Größe ÅΩ 中" && approx($0.height, 250) })
        let c = try #require(texts.first { $0.text == "CENTER" })
        #expect(c.horizontal == .center && c.vertical == .middle && approx(c.rotation, .pi / 6, 1e-12))
        guard case .mtext(let m, _)? = doc.modelSpace.first(where: { $0.typeName == "MTEXT" }) else { Issue.record("no mtext"); return }
        #expect(m.plainText == "Line one\nLine two")
        #expect(approx(m.width, 5000))
    }

    @Test func arcsAndHatchesRoundTrip() throws {
        let doc = try DXFReader.read(DXFWriter.write(sampleGraphics(), units: .meters), fileName: "export.dxf")
        let arcs = doc.modelSpace.compactMap { e -> (Vec2, Double, Double, Double)? in if case .arc(let c, let r, let s, let en, _) = e { return (c, r, s, en) }; return nil }
        #expect(arcs.count == 2)
        let cw = try #require(arcs.first { $0.1 == 0.3 })
        // A clockwise sweep is written as the equivalent counter-clockwise arc.
        #expect(approx(Angle.normalize(cw.2), 3 * .pi / 2, 1e-12) && approx(Angle.normalize(cw.3), 0, 1e-12))
        let hatches = doc.modelSpace.compactMap { e -> CADHatch? in if case .hatch(let h, _) = e { return h }; return nil }
        #expect(hatches.contains { $0.isSolid && $0.loops.count == 1 })
        let patterned = try #require(hatches.first { !$0.isSolid })
        #expect(patterned.patternName == "ANSI31" && patterned.loops.count == 2)
        #expect(doc.modelSpace.contains { if case .circle(_, let r, _) = $0 { return r == 0.25 }; return false })
    }

    @Test func r2000StructureAndTables() throws {
        let data = DXFWriter.write(sampleGraphics(), units: .millimeters)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var sections: [String] = []
        for i in stride(from: 0, to: lines.count - 3, by: 2) where lines[i] == "0" && lines[i + 1] == "SECTION" { sections.append(lines[i + 3]) }
        #expect(sections == ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"])
        #expect(Array(lines.suffix(3)) == ["0", "EOF", ""])
        var tables: [String] = []
        for i in stride(from: 0, to: lines.count - 3, by: 2) where lines[i] == "0" && lines[i + 1] == "TABLE" { tables.append(lines[i + 3]) }
        #expect(tables == ["VPORT", "LTYPE", "LAYER", "STYLE", "VIEW", "UCS", "APPID", "DIMSTYLE", "BLOCK_RECORD"])
        #expect(text.contains("$ACADVER\n  1\nAC1015"))
        #expect(text.contains("$INSUNITS\n 70\n4"))
        #expect(text.contains("*Model_Space") && text.contains("*Paper_Space"))
        #expect(text.contains("ARCUS_DASH"))
        // Handles (group 5) are unique.
        var handles: [String] = []
        for i in stride(from: 0, to: lines.count - 1, by: 2) where lines[i] == "5" || lines[i] == "105" { handles.append(lines[i + 1]) }
        #expect(Set(handles).count == handles.count)
        let doc = try DXFReader.read(data, fileName: "export.dxf")
        #expect(doc.layouts.map(\.name) == ["Model", "Layout1"])
        #expect(doc.lineTypes.contains { $0.name == "ARCUS_DASH" && $0.pattern.count == 2 })
        #expect(doc.textStyles.first?.name == "Standard")
        #expect(doc.modelSpace.contains { $0.props.lineType == "ARCUS_DASH" })
    }

    @Test func unitScaleApplied() throws {
        let doc = try DXFReader.read(DXFWriter.write(sampleGraphics(), units: .feet), fileName: "ft.dxf")
        #expect(doc.units == .feet)
        guard case .polyline(let p, _)? = doc.modelSpace.first(where: { $0.typeName == "LWPOLYLINE" }) else { Issue.record("no polyline"); return }
        #expect(approx(p.points[1].x, 11 / 0.3048, 1e-12))
        // Converting back through the importer returns meters.
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        #expect(approx(r.report.extents.max.x, 11, 1e-9))
    }

    @Test func customLayerNamesAreSanitized() throws {
        let doc = try DXFReader.read(DXFWriter.write(sampleGraphics(), layerName: { "A-\($0.rawValue)/<bad>" }), fileName: "x.dxf")
        #expect(doc.layers.contains { $0.name == "A-walls__bad_" })
    }

    @Test func realPlanViewExportsAndReimports() throws {
        let (m0, ids) = templateModel()
        let tx = TransactionContext(model: m0, name: "Walls")
        let l1 = ids.levels[0], l2 = ids.levels[1]
        let wt = ids.wallTypes.values.first!
        let pts = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)]
        for i in 0..<4 {
            tx.create(.walls, data: .wall(WallData(location: .line(Segment2(pts[i], pts[(i + 1) % 4])), topLevelID: l2)), typeID: wt, levelID: l1)
        }
        let m = try tx.commit().model
        let view = m[ids.planViews[l1]!]!
        let g = ViewGraphicsBuilder(model: m, view: view).build()
        let data = DXFWriter.write(g)
        let doc = try DXFReader.read(data, fileName: "plan.dxf")
        #expect(doc.layers.contains { $0.name == "Walls" })
        #expect(doc.modelSpace.count >= 4)
        var o = CADImportOptions()
        o.includedLayers = ["Walls"]
        let r = CADConverter.referenceDrawing(doc, options: o)
        #expect(r.report.extents.width > 9.5 && r.report.extents.width < 11)
    }
}

@Suite("DWG provider")
struct DWGProviderTests {
    @Test func unavailableProviderExplainsTheSDKRequirement() throws {
        let p = UnavailableDWGProvider()
        #expect(!p.isAvailable)
        let reason = try #require(p.unavailableReason)
        #expect(reason.contains("ODA Drawings SDK"))
        #expect(reason.contains("Docs/DWGSDKSetup.md"))
        #expect(reason.contains("DXF"))
        #expect(p.supportedVersions.isEmpty && p.sdkVersion == nil)
        do {
            _ = try p.read(URL(fileURLWithPath: "/nonexistent.dwg"), options: .init(), progress: { _ in }, isCancelled: { false })
            Issue.record("expected an error")
        } catch let e as CADError {
            #expect(e.message == reason)
        }
    }

    @Test func currentProviderWithoutSDKIsUnavailable() {
        let p = DWGProviders.current
        #if ARCUS_HAS_ODA
        #expect(p.sdkName.contains("ODA"))
        #else
        if p is ExternalConverterDWGProvider { return } // W2-DWG: a converter is installed on this Mac (see ExternalDWGConverterTests)
        #expect(!p.isAvailable)
        #expect(p.unavailableReason?.contains("ODA Drawings SDK") == true)
        #endif
    }

    @Test func versionSniffing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sniff-\(UUID().uuidString).dwg")
        try Data("AC1032\0\0\0\0binary".utf8).write(to: url)
        #expect(DWGProviders.sniffVersion(url) == "AC1032")
        try Data("PK\u{3}\u{4}".utf8).write(to: url)
        #expect(DWGProviders.sniffVersion(url) == nil)
        #expect(CADDocument.friendlyVersion("AC1032") == "AutoCAD 2018")
        #expect(DWGProviders.knownVersions.contains("AC1009") && DWGProviders.knownVersions.last == "AC1032")
    }
}
