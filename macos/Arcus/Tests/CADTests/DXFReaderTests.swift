import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

@Suite("DXF reader: R12")
struct DXFReaderR12Tests {
    @Test func headerTablesAndLayerStates() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        #expect(doc.version == "AC1009")
        #expect(doc.versionName == "AutoCAD R11/R12")
        #expect(doc.units == .unitless)
        #expect(doc.codepage == "ANSI_1252")
        let names = Set(doc.layers.map(\.name))
        #expect(names.isSuperset(of: ["0", "WALLS", "HIDDEN-OFF", "FROZEN", "LOCKED"]))
        let off = try #require(doc.layers.first { $0.name == "HIDDEN-OFF" })
        #expect(!off.isOn)
        #expect(off.colorIndex == 3)
        #expect(off.lineType == "DASHED")
        #expect(doc.layers.first { $0.name == "FROZEN" }?.isFrozen == true)
        #expect(doc.layers.first { $0.name == "LOCKED" }?.isLocked == true)
        #expect(doc.layers.first { $0.name == "WALLS" }?.color == RGBColor(1, 0, 0))
        let dashed = try #require(doc.lineTypes.first { $0.name == "DASHED" })
        #expect(dashed.pattern == [10, -5])
        #expect(doc.fonts == ["romans.shx"])
        #expect(doc.textStyles.first?.isSHX == true)
    }

    @Test func entityCountsIncludeAllSpacesAndBlocks() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        #expect(doc.entityCounts["LINE"] == 5)      // 3 model + 1 paper + 1 in block TREE
        #expect(doc.entityCounts["POLYLINE"] == 3)
        #expect(doc.entityCounts["3DFACE"] == 1)
        #expect(doc.entityCounts["SOLID"] == 1)
        #expect(doc.entityCounts["TRACE"] == 1)
        #expect(doc.entityCounts["INSERT"] == 1)
        #expect(doc.entityCounts["VERTEX"] == nil)
        #expect(doc.warnings.isEmpty)
    }

    @Test func polylineVerticesWithBulge() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        let bulged = doc.modelSpace.compactMap { e -> CADPolyline? in
            if case .polyline(let p, _) = e, p.hasBulges { return p }; return nil
        }
        let p = try #require(bulged.first)
        #expect(p.points.count == 3)
        #expect(p.bulge(at: 1) == 1.0)
        let arc = try #require(CADGeometry.bulgeArc(p.points[1].xy, p.points[2].xy, 1.0))
        #expect(approx(arc.center, Vec2(6000, 9000)))
        #expect(approx(arc.radius, 2000))
        #expect(approx(arc.sweep, .pi))
    }

    @Test func threeDPolylineAndPolyfaceMesh() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        let polys = doc.modelSpace.compactMap { e -> CADPolyline? in if case .polyline(let p, _) = e { return p }; return nil }
        let p3 = try #require(polys.first { $0.is3D && !$0.isMesh })
        #expect(p3.points.map(\.z) == [0, 500, 1000])
        let mesh = try #require(polys.first { $0.isMesh })
        #expect(mesh.points.count == 4)
        #expect(mesh.meshFaces == [[0, 1, 2], [0, 2, 3]])
    }

    @Test func mirroredExtrusionArcIsMappedToWorld() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        let arcs = doc.modelSpace.compactMap { e -> (Vec2, Double, Double, Double)? in
            if case .arc(let c, let r, let s, let en, _) = e { return (c, r, s, en) }; return nil
        }
        let m = try #require(arcs.first { $0.1 == 500 })
        #expect(approx(m.0, Vec2(-1000, 1000)))
        #expect(approx(Angle.normalize(m.2), .pi / 2))
        #expect(approx(Angle.normalize(m.3), .pi))
    }

    @Test func textControlCodesAndAlignment() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        let texts = doc.modelSpace.compactMap { e -> CADText? in if case .text(let t, _) = e { return t }; return nil }
        #expect(texts.contains { $0.text == "R12 PLAN 90°" })
        let c = try #require(texts.first { $0.text == "CENTERED" })
        #expect(c.horizontal == .center)
        #expect(c.alignmentPoint == Vec2(5000, 12000))
    }

    @Test func paperSpaceEntitiesFormALayout() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        #expect(doc.layouts.map(\.name) == ["Model", "Layout1"])
        #expect(doc.layouts[0].isModelSpace)
        #expect(doc.layouts[1].entities.count == 2)
        #expect(!doc.modelSpace.contains { $0.props.paperSpace })
    }

    @Test func insertScaleAndRotation() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        guard case .insert(let ins, let p)? = doc.modelSpace.first(where: { $0.typeName == "INSERT" }) else { Issue.record("no insert"); return }
        #expect(ins.blockName == "TREE")
        #expect(ins.scale == Vec2(2, 2))
        #expect(approx(ins.rotation, .pi / 4))
        #expect(p.layer == "WALLS")
        #expect(doc.blocks["TREE"]?.entities.count == 2)
    }

    @Test func extentsComputedFromGeometry() throws {
        let doc = try Fx.doc("r12_plan.dxf")
        #expect(approx(doc.extents.min.x, -1500, 1e-6))
        #expect(approx(doc.extents.min.y, -500, 1e-6))
        #expect(doc.extents.max.y >= 15000)
    }
}

@Suite("DXF reader: AutoCAD 2000 imperial")
struct DXFReaderAC1015Tests {
    @Test func unitsAndLayerProperties() throws {
        let doc = try Fx.doc("ac1015_imperial_layouts.dxf")
        #expect(doc.units == .inches)
        #expect(doc.versionName == "AutoCAD 2000")
        let wall = try #require(doc.layers.first { $0.name == "A-WALL" })
        #expect(wall.trueColor == RGBColor(hex: 0x336699))
        #expect(wall.color == RGBColor(hex: 0x336699))
        #expect(wall.lineWeight == 0.5)
        let anno = try #require(doc.layers.first { $0.name == "A-ANNO" })
        #expect(!anno.plots)
        #expect(anno.lineWeight == 0.18)
        #expect(doc.layers.first { $0.name == "0" }?.lineWeight == nil)
    }

    @Test func entityCommonPropertiesPreserved() throws {
        let doc = try Fx.doc("ac1015_imperial_layouts.dxf")
        let line = try #require(doc.entity(handle: "101"))
        let p = line.props
        #expect(p.layer == "A-WALL")
        #expect(p.lineType == "HIDDEN")
        #expect(p.lineWeight == 0.35)
        #expect(p.color == .rgb(RGBColor(hex: 0xFF8000)))
        #expect(p.owner == "1F")
        #expect(!p.paperSpace)
    }

    @Test func layoutsFromLayoutObjectsAndPaperSpaceBlocks() throws {
        let doc = try Fx.doc("ac1015_imperial_layouts.dxf")
        #expect(doc.layouts.map(\.name) == ["Model", "Layout1", "Sheet A"])
        let sheet = try #require(doc.layout(named: "sheet a"))
        #expect(sheet.paperSize == Vec2(431.8, 279.4))
        #expect(sheet.entities.count == 2)
        #expect(sheet.entities.contains { if case .text(let t, _) = $0 { return t.text == "SHEET A TITLE" }; return false })
        #expect(doc.layout(named: "Layout1")?.entities.count == 1)
        #expect(doc.blocks["*Paper_Space0"] == nil) // layout blocks are not listed as reusable blocks
    }

    @Test func imageDefinitionResolvedOnImageEntity() throws {
        let doc = try Fx.doc("ac1015_imperial_layouts.dxf")
        #expect(doc.images == ["photos\\site.jpg"])
        guard case .image(let path, let corners, _)? = doc.entity(handle: "104") else { Issue.record("no image"); return }
        #expect(path == "photos\\site.jpg")
        #expect(approx(corners[0], Vec2(300, 0)))
        #expect(approx(corners[2], Vec2(364, 48)))
    }

    @Test func lightweightPolylineBulgeAndClosure() throws {
        let doc = try Fx.doc("ac1015_imperial_layouts.dxf")
        guard case .polyline(let p, _)? = doc.entity(handle: "100") else { Issue.record("no lwpolyline"); return }
        #expect(p.closed)
        #expect(p.points.count == 4)
        let arc = try #require(CADGeometry.bulgeArc(p.points[1].xy, p.points[2].xy, p.bulge(at: 1)))
        #expect(approx(arc.sweep, .pi / 2, 1e-9))
        #expect(approx(arc.radius, 48, 1e-9))
    }
}

@Suite("DXF reader: blocks and annotation")
struct DXFReaderAC1027Tests {
    @Test func nestedBlocksWithBasePointAndAttributeDefinitions() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        let set = try #require(doc.blocks["TABLE_SET"])
        #expect(set.basePoint == Vec2(1000, 0))
        #expect(set.entities.filter { $0.typeName == "INSERT" }.count == 2)
        let chair = try #require(doc.blocks["CHAIR"])
        #expect(chair.entities.contains { if case .attributeDefinition(let a, _) = $0 { return a.tag == "MARK" && a.text.text == "C1" }; return false })
        #expect(doc.blocks["*D1"]?.isAnonymous == true)
    }

    @Test func insertAttributesAndArrays() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .insert(let a, _)? = doc.entity(handle: "100") else { Issue.record("no insert"); return }
        #expect(a.attributes.count == 1)
        #expect(a.attributes[0].tag == "MARK")
        #expect(a.attributes[0].text.text == "C-101")
        guard case .insert(let m, _)? = doc.entity(handle: "104") else { Issue.record("no minsert"); return }
        #expect(m.columns == 3 && m.rows == 2)
        #expect(m.columnSpacing == 1000 && m.rowSpacing == 1500)
        guard case .insert(let t, _)? = doc.entity(handle: "103") else { Issue.record("no table insert"); return }
        #expect(t.scale == Vec2(2, 2))
        #expect(approx(t.rotation, .pi / 2))
    }

    @Test func ellipsesAndSplines() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .ellipse(let full, _)? = doc.entity(handle: "105"), case .ellipse(let half, _)? = doc.entity(handle: "106") else {
            Issue.record("ellipses missing"); return
        }
        #expect(full.isFull && full.ratio == 0.5 && full.majorAxis == Vec2(2000, 0))
        #expect(!half.isFull && approx(half.paramSpan, .pi))
        guard case .spline(let s?, _, _, _)? = doc.entity(handle: "107") else { Issue.record("spline missing"); return }
        #expect(s.degree == 3 && s.controlPoints.count == 4 && s.isValid)
        #expect(approx(s.point(at: 0), Vec2(0, 20000)) && approx(s.point(at: 1), Vec2(4000, 20000)))
        guard case .spline(nil, let fit, _, _)? = doc.entity(handle: "108") else { Issue.record("fit spline missing"); return }
        #expect(fit.count == 3)
    }

    @Test func hatchEdgeLoopWithArc() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .hatch(let h, _)? = doc.entity(handle: "109") else { Issue.record("hatch missing"); return }
        #expect(h.isSolid)
        #expect(h.loops.count == 1 && h.loops[0].count == 4)
        #expect(h.loops[0].contains { if case .arc = $0 { return true }; return false })
        let pts = CADGeometry.loopPoints(h.loops[0])
        let b = Rect2(points: pts)
        #expect(approx(b.max.x, 33000, 1e-3))
        #expect(approx(b.min.x, 30000) && approx(b.max.y, 2000, 1e-6))
    }

    @Test func patternHatchWithBulgedPolylineBoundary() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .hatch(let h, _)? = doc.entity(handle: "10A") else { Issue.record("hatch missing"); return }
        #expect(!h.isSolid)
        #expect(h.patternName == "ANSI31")
        guard case .polyline(let pts, let bul, let closed)? = h.loops.first?.first else { Issue.record("no polyline edge"); return }
        #expect(pts.count == 3 && closed && bul[1] == 1.0)
    }

    @Test func dimensionsUseBlockAndMeasurementText() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .dimension(let d, _)? = doc.entity(handle: "10B") else { Issue.record("dimension missing"); return }
        #expect(d.blockName == "*D1")
        #expect(d.measurement == 3000)
        #expect(d.text == "3000")
        guard case .dimension(let d2, _)? = doc.entity(handle: "10C") else { Issue.record("dimension missing"); return }
        #expect(d2.text == "1234.5 mm")
    }

    @Test func leadersAndMultileaders() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .leader(let pts, let arrow, _)? = doc.entity(handle: "10D") else { Issue.record("leader missing"); return }
        #expect(pts.count == 3 && arrow)
        guard case .multileader(let m, _)? = doc.entity(handle: "10E") else { Issue.record("mleader missing"); return }
        #expect(m.leaderLines.count == 1)
        #expect(m.leaderLines[0] == [Vec2(8000, -1500), Vec2(9000, -500)])
        #expect(m.text == "Door note\nsecond line")
        #expect(m.textPosition == Vec2(9100, -450))
        #expect(m.textHeight == 125)
    }

    @Test func proxiesAndUnsupportedTypesAreRetainedOrCounted() throws {
        let doc = try Fx.doc("ac1027_blocks_annotation.dxf")
        guard case .proxy(let n, let b, _)? = doc.entity(handle: "10F") else { Issue.record("proxy missing"); return }
        #expect(n == "ACAD_PROXY_ENTITY" && b == nil)
        guard case .proxy(let n2, let b2?, _)? = doc.entity(handle: "110") else { Issue.record("custom entity missing"); return }
        #expect(n2 == "AECC_COGO_POINT")
        #expect(b2 == Rect2(min: Vec2(7000, 7000), max: Vec2(7100, 7050)))
        guard case .unsupported(let n3, _)? = doc.entity(handle: "111") else { Issue.record("3dsolid missing"); return }
        #expect(n3 == "3DSOLID")
        #expect(doc.unsupportedCounts == ["ACAD_PROXY_ENTITY": 1, "AECC_COGO_POINT": 1, "3DSOLID": 1])
    }
}

@Suite("DXF reader: encodings and formats")
struct DXFReaderEncodingTests {
    @Test func utf8NamesAndText2018() throws {
        let doc = try Fx.doc("ac1032_unicode_survey.dxf")
        #expect(doc.codepage == "UTF-8")
        #expect(doc.units == .meters)
        #expect(Set(doc.layers.map(\.name)).isSuperset(of: ["Ébauche", "Straße", "図面-文字"]))
        let texts = doc.modelSpace.compactMap { e -> String? in if case .text(let t, _) = e { return t.text }; return nil }
        #expect(texts.contains("Café Größe ±5 平面図"))
        #expect(texts.contains("Angle 45° ⌀100 ±2"))
    }

    @Test func mtextFormattingStripped() throws {
        let doc = try Fx.doc("ac1032_unicode_survey.dxf")
        guard case .mtext(let m, _)? = doc.entity(handle: "A5") else { Issue.record("mtext missing"); return }
        #expect(m.plainText == "Grundriss\nZimmer ÅΩ 1/2 klein\nLine\u{00A0}three red \\ back")
        #expect(m.width == 40)
        #expect(m.rawText.hasPrefix("{\\fArial"))
    }

    @Test func largeCoordinatesKeepFullPrecision() throws {
        let doc = try Fx.doc("ac1032_unicode_survey.dxf")
        guard case .line(let a, let b, _)? = doc.entity(handle: "A1") else { Issue.record("line missing"); return }
        #expect(a.x == 512345.678 && a.y == 4234567.891)
        #expect(b.x == 512355.678)
    }

    @Test func legacyCodepageDecoding() throws {
        var bytes = Data()
        var d = DXFText()
        d.seq([(0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, "AC1015"), (9, "$DWGCODEPAGE"), (3, "ANSI_1252"), (0, "ENDSEC"),
               (0, "SECTION"), (2, "ENTITIES"), (0, "TEXT"), (8, "0"), (10, 0), (20, 0), (40, 1)])
        bytes.append(d.data)
        bytes.append(Data("  1\n".utf8))
        bytes.append(contentsOf: [0x43, 0x61, 0x66, 0xE9, 0x20]) // "Café " in Windows-1252
        bytes.append(Data("\\U+00C5\n  0\nENDSEC\n  0\nEOF\n".utf8))
        let doc = try DXFReader.read(bytes, fileName: "cp1252.dxf")
        guard case .text(let t, _)? = doc.modelSpace.first else { Issue.record("text missing"); return }
        #expect(t.text == "Café Å")
    }

    @Test func carriageReturnOnlyLineEnds() throws {
        let d = DXFText.minimal { $0.seq([(0, "LINE"), (8, "0"), (10, 1), (20, 2), (11, 3), (21, 4)]) }
        let cr = Data(String(decoding: d.data, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r").utf8)
        let doc = try DXFReader.read(cr, fileName: "cr.dxf")
        guard case .line(let a, let b, _)? = doc.modelSpace.first else { Issue.record("line missing"); return }
        #expect(a.xy == Vec2(1, 2) && b.xy == Vec2(3, 4))
    }

    static func binary(shortCodes: Bool) -> Data {
        var out = Data("AutoCAD Binary DXF\r\n\u{1A}\0".utf8)
        func code(_ c: Int) {
            if shortCodes {
                if c < 255 { out.append(UInt8(c)) } else { out.append(255); out.append(contentsOf: withUnsafeBytes(of: Int16(c).littleEndian, Array.init)) }
            } else {
                out.append(contentsOf: withUnsafeBytes(of: Int16(c).littleEndian, Array.init))
            }
        }
        func s(_ c: Int, _ v: String) { code(c); out.append(Data(v.utf8)); out.append(0) }
        func dbl(_ c: Int, _ v: Double) { code(c); out.append(contentsOf: withUnsafeBytes(of: v.bitPattern.littleEndian, Array.init)) }
        func i16(_ c: Int, _ v: Int16) { code(c); out.append(contentsOf: withUnsafeBytes(of: v.littleEndian, Array.init)) }
        s(0, "SECTION"); s(2, "HEADER"); s(9, "$ACADVER"); s(1, shortCodes ? "AC1009" : "AC1015"); s(9, "$INSUNITS"); i16(70, 6); s(0, "ENDSEC")
        s(0, "SECTION"); s(2, "ENTITIES")
        s(0, "LINE"); s(5, "2A"); s(8, "BIN"); i16(62, 3); dbl(10, 1.25); dbl(20, -2.5); dbl(30, 0); dbl(11, 1e6 + 0.125); dbl(21, 7); dbl(31, 0)
        s(0, "CIRCLE"); s(8, "BIN"); dbl(10, 0); dbl(20, 0); dbl(30, 0); dbl(40, 3)
        s(0, "ENDSEC"); s(0, "EOF")
        return out
    }

    @Test(arguments: [false, true])
    func binaryDXF(shortCodes: Bool) throws {
        let doc = try DXFReader.read(Self.binary(shortCodes: shortCodes), fileName: "bin.dxf")
        #expect(doc.format == "DXF (binary)")
        #expect(doc.units == .meters)
        guard case .line(let a, let b, let p)? = doc.modelSpace.first else { Issue.record("line missing"); return }
        #expect(a.xy == Vec2(1.25, -2.5) && b.xy == Vec2(1e6 + 0.125, 7))
        #expect(p.layer == "BIN" && p.handle == "2A" && p.color == .index(3))
        #expect(doc.modelSpace.count == 2)
    }

    @Test func looksLikeDXFSniffing() throws {
        #expect(DXFReader.looksLikeDXF(try Fx.data("r12_plan.dxf")))
        #expect(DXFReader.looksLikeDXF(DXFReaderEncodingTests.binary(shortCodes: false)))
        #expect(!DXFReader.looksLikeDXF(Data("hello world".utf8)))
    }
}

@Suite("DXF reader: geometry details")
struct DXFReaderGeometryTests {
    @Test func hatchEllipseAndSplineEdges() throws {
        let d = DXFText.minimal { t in
            t.seq([(0, "HATCH"), (5, "H1"), (8, "0"), (10, 0), (20, 0), (30, 0), (210, 0), (220, 0), (230, 1), (2, "SOLID"), (70, 1), (71, 0), (91, 1),
                   (92, 1), (93, 3),
                   // Lower half of an ellipse (ccw from π to 2π), center (0,0), a = 10, b = 5.
                   (72, 3), (10, 0), (20, 0), (11, 10), (21, 0), (40, 0.5), (50, 180), (51, 360), (73, 1),
                   // Cubic spline edge from (10,0) up and back to (0,8).
                   (72, 4), (94, 3), (73, 0), (74, 0), (95, 8), (96, 4),
                   (40, 0), (40, 0), (40, 0), (40, 0), (40, 1), (40, 1), (40, 1), (40, 1),
                   (10, 10), (20, 0), (10, 10), (20, 8), (10, 4), (20, 10), (10, 0), (20, 8),
                   (72, 1), (10, 0), (20, 8), (11, -10), (21, 0),
                   (97, 0), (75, 0), (76, 1), (98, 0)])
        }
        let doc = try DXFReader.read(d.data, fileName: "edges.dxf")
        guard case .hatch(let h, _)? = doc.modelSpace.first else { Issue.record("hatch missing"); return }
        #expect(h.loops.count == 1 && h.loops[0].count == 3)
        guard case .ellipse(let el, true) = h.loops[0][0], case .spline(let sp) = h.loops[0][1] else { Issue.record("edge kinds"); return }
        #expect(approx(el.paramSpan, .pi))
        #expect(sp.isValid && sp.degree == 3)
        let b = Rect2(points: CADGeometry.loopPoints(h.loops[0]))
        #expect(approx(b.min.y, -5, 1e-3) && approx(b.min.x, -10, 1e-6) && b.max.y > 7)
    }

    @Test func polygonMeshBecomesQuadFaces() throws {
        let d = DXFText.minimal { t in
            t.seq([(0, "POLYLINE"), (8, "0"), (66, 1), (10, 0), (20, 0), (30, 0), (70, 16), (71, 2), (72, 3)])
            for i in 0..<2 { for j in 0..<3 { t.seq([(0, "VERTEX"), (8, "0"), (10, j), (20, i), (30, i + j), (70, 64)]) } }
            t.seq([(0, "SEQEND"), (8, "0")])
        }
        let doc = try DXFReader.read(d.data, fileName: "mesh.dxf")
        guard case .polyline(let p, _)? = doc.modelSpace.first else { Issue.record("mesh missing"); return }
        #expect(p.isMesh && p.points.count == 6)
        #expect(p.meshFaces == [[0, 1, 4, 3], [1, 2, 5, 4]])
        let r = CADConverter.referenceDrawing(doc, options: CADImportOptions())
        #expect(r.drawing.entities.filter { if case .face3D = $0 { return true }; return false }.count == 2)
    }

    @Test func mirroredExtrusionPolylineAndInsert() throws {
        var d = DXFText()
        d.seq([(0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, "AC1015"), (0, "ENDSEC"),
               (0, "SECTION"), (2, "BLOCKS"), (0, "BLOCK"), (2, "B"), (70, 0), (10, 0), (20, 0),
               (0, "LINE"), (8, "0"), (10, 0), (20, 0), (11, 10), (21, 5), (0, "ENDBLK"), (0, "ENDSEC"),
               (0, "SECTION"), (2, "ENTITIES"),
               (0, "LWPOLYLINE"), (5, "P"), (8, "0"), (90, 2), (70, 0), (10, 0), (20, 0), (42, 1), (10, 10), (20, 0), (210, 0), (220, 0), (230, -1),
               (0, "INSERT"), (5, "I"), (8, "0"), (2, "B"), (10, 100), (20, 0), (210, 0), (220, 0), (230, -1),
               (0, "ENDSEC"), (0, "EOF")])
        let doc = try DXFReader.read(d.data, fileName: "ocs.dxf")
        guard case .polyline(let p, _)? = doc.entity(handle: "P") else { Issue.record("polyline missing"); return }
        #expect(p.points2D == [Vec2(0, 0), Vec2(-10, 0)])
        #expect(p.bulges[0] == -1)
        let arc = try #require(CADGeometry.bulgeArc(p.points2D[0], p.points2D[1], p.bulges[0]))
        #expect(arc.mid.y < 0) // the mirrored arc still bulges toward -Y
        guard case .insert(let ins, _)? = doc.entity(handle: "I") else { Issue.record("insert missing"); return }
        let t = ins.transform(basePoint: .zero)
        #expect(approx(t.apply(Vec2(10, 5)), Vec2(-110, 5), 1e-12))
    }

    @Test func wcsEllipseWithNegativeExtrusionReversesParameters() throws {
        let d = DXFText.minimal { t in
            t.seq([(0, "ELLIPSE"), (8, "0"), (10, 0), (20, 0), (11, 4), (21, 0), (40, 0.5), (41, 0), (42, 1.5707963267948966), (210, 0), (220, 0), (230, -1)])
        }
        let doc = try DXFReader.read(d.data, fileName: "e.dxf")
        guard case .ellipse(let el, _)? = doc.modelSpace.first else { Issue.record("ellipse missing"); return }
        // Viewed from +Z the quarter runs from (4,0) clockwise to (0,-2).
        let pts = [el.start, el.end]
        #expect(pts.contains { approx($0, Vec2(4, 0), 1e-9) } && pts.contains { approx($0, Vec2(0, -2), 1e-9) })
    }
}

@Suite("Text decoding and units")
struct CADTextAndUnitsTests {
    @Test func mtextStackedFractionsAndEscapes() {
        #expect(CADTextDecoder.plainMText("\\S3#4;\" door") == "3/4\" door")
        #expect(CADTextDecoder.plainMText("+0.1\\S^-0.1;") == "+0.1-0.1")
        #expect(CADTextDecoder.plainMText("\\{literal\\} {\\LUnder\\l}") == "{literal} Under")
        #expect(CADTextDecoder.plainMText("A^IB") == "A\tB")
        #expect(CADTextDecoder.plainMText("%%c50") == "⌀50")
        #expect(CADTextDecoder.plainMText("unterminated \\fArial") == "unterminated ")
    }

    @Test func textControlCodes() {
        #expect(CADTextDecoder.decodeText("%%uUnder%%u 100%%%") == "Under 100%")
        #expect(CADTextDecoder.decodeText("%%065BC") == "ABC")
        #expect(CADTextDecoder.decodeText("\\U+4E2D\\U+6587") == "中文")
        #expect(CADTextDecoder.decodeText("broken \\U+ZZ") == "broken \\U+ZZ")
    }

    @Test func unitScales() {
        #expect(CADUnits.inches.metersPerUnit == 0.0254)
        #expect(CADUnits.feet.metersPerUnit == 0.3048)
        #expect(CADUnits.millimeters.metersPerUnit == 0.001)
        #expect(CADUnits.decimeters.rawValue == 14)
        #expect(approx(CADUnits.usSurveyFeet.metersPerUnit, 0.3048006096012192))
        #expect(CADUnits.unitless.metersPerUnit == 0.001)
        for u in CADUnits.allCases { #expect(u.metersPerUnit > 0 && u.metersPerUnit.isFinite) }
    }

    @Test func aciPalette() {
        #expect(ACIColor.rgb(1) == RGBColor(1, 0, 0))
        #expect(ACIColor.rgb(11) == RGBColor(1, 0.5, 0.5))
        #expect(ACIColor.nearest(RGBColor(0, 0, 1)) == 5)
        #expect(ACIColor.nearest(.black) == 7)
        #expect(ACIColor.trueColor(0x336699) == RGBColor(hex: 0x336699))
        #expect(ACIColor.trueColorValue(RGBColor(hex: 0x336699)) == 0x336699)
    }
}
