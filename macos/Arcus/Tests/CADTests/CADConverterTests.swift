import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

@Suite("CAD converter")
struct CADConverterTests {
    func convert(_ name: String, _ configure: (inout CADImportOptions) -> Void = { _ in }, survey: Vec2 = .zero) throws -> (ReferenceDrawing, CADImportReport, Transform2) {
        var o = CADImportOptions()
        configure(&o)
        let doc = try Fx.doc(name)
        let r = CADConverter.referenceDrawing(doc, options: o, surveyOrigin: survey)
        return (r.drawing, r.report, CADConverter.placement(for: r.drawing, options: o, surveyOrigin: survey))
    }

    func first(_ d: ReferenceDrawing, handle: String) -> ReferenceDrawing.Entity? { d.entities.first { $0.style.handle == handle } }

    @Test func unitlessDefaultsToMillimetersWithWarning() throws {
        let (d, report, _) = try convert("r12_plan.dxf")
        #expect(report.units == .unitless)
        #expect(report.unitScale == 0.001)
        #expect(report.warnings.contains { $0.contains("millimeters were assumed") })
        #expect(approx(report.extents.min.x, -1.5, 1e-9))
        #expect(d.metadata["source.version"] == "AC1009")
    }

    @Test func unitsOverride() throws {
        let (_, report, _) = try convert("r12_plan.dxf") { $0.unitsOverride = .centimeters }
        #expect(report.units == .centimeters)
        #expect(report.unitScale == 0.01)
        #expect(!report.warnings.contains { $0.contains("millimeters were assumed") })
    }

    @Test func imperialScaling() throws {
        let (d, report, placement) = try convert("ac1015_imperial_layouts.dxf")
        #expect(report.unitScale == 0.0254)
        guard case .line(let s, _)? = first(d, handle: "101") else { Issue.record("line missing"); return }
        #expect(approx(placement.apply(s.end), Vec2(120 * 0.0254, 60 * 0.0254), 1e-12))
    }

    @Test func originToOriginPlacesDrawingOriginAtModelOrigin() throws {
        let (d, _, placement) = try convert("r12_plan.dxf")
        let walls = d.entities.compactMap { e -> Segment2? in if case .line(let s, let st) = e, d.layers[st.layer].name == "WALLS" { return s }; return nil }
        let w = try #require(walls.first)
        #expect(approx(placement.apply(w.start), .zero, 1e-12))
        #expect(approx(placement.apply(w.end), Vec2(10, 0), 1e-12))
    }

    @Test func centerToCenterCentersExtentsOnOrigin() throws {
        let (d, _, placement) = try convert("r12_plan.dxf") { $0.positioning = .centerToCenter }
        let placed = Rect2(points: d.extents.corners.map(placement.apply))
        #expect(approx(placed.center, .zero, 1e-9))
    }

    @Test func sharedCoordinatesSubtractSurveyPointAndRotate() throws {
        let e = 512300.0, n = 4234500.0
        let (d, _, p0) = try convert("ac1032_unicode_survey.dxf", { $0.positioning = .sharedCoordinates(easting: e, northing: n, rotation: 0) },
                                     survey: Vec2(10, 20))
        guard case .line(let s, _)? = first(d, handle: "A1") else { Issue.record("line missing"); return }
        #expect(approx(p0.apply(s.start), Vec2(45.678 + 10, 67.891 + 20), 1e-9))
        let (d2, _, p1) = try convert("ac1032_unicode_survey.dxf", { $0.positioning = .sharedCoordinates(easting: e, northing: n, rotation: .pi / 2) })
        guard case .line(let s2, _)? = first(d2, handle: "A1") else { Issue.record("line missing"); return }
        #expect(approx(p1.apply(s2.start), Vec2(-67.891, 45.678), 1e-9))
    }

    @Test func largeCoordinatesStayPreciseRelativeToLocalOrigin() throws {
        let (d, report, placement) = try convert("ac1032_unicode_survey.dxf")
        guard case .line(let s, _)? = first(d, handle: "A1") else { Issue.record("line missing"); return }
        // Content is stored near its own origin; placement carries the survey offset.
        #expect(abs(s.start.x) < 1000 && abs(s.start.y) < 1000)
        let world = placement.apply(s.start)
        #expect(abs(world.x - 512345.678) < 1e-7)
        #expect(abs(world.y - 4234567.891) < 1e-7)
        #expect(approx(report.extents.min.x, 512300, 1e-12))
        guard case .point(let p, _)? = first(d, handle: "A6") else { Issue.record("point missing"); return }
        #expect(abs(placement.apply(p).x - 512350) < 1e-7)
    }

    @Test func userScaleAndRotationApplyAboutInsertionPoint() throws {
        let (d, _, placement) = try convert("r12_plan.dxf") { $0.scale = 2; $0.rotation = .pi / 2 }
        let walls = d.entities.compactMap { e -> Segment2? in if case .line(let s, let st) = e, d.layers[st.layer].name == "WALLS" { return s }; return nil }
        let w = try #require(walls.first)
        #expect(approx(placement.apply(w.end), Vec2(0, 20), 1e-12))
    }

    @Test func blocksPreservedAsReusableDefinitions() throws {
        let (d, _, _) = try convert("ac1027_blocks_annotation.dxf")
        #expect(Set(d.blocks.keys).isSuperset(of: ["CHAIR", "TABLE_SET", "*D1"]))
        let chairInserts = d.entities.filter { if case .insert(let b, _, _, _) = $0 { return b == "CHAIR" }; return false }
        #expect(chairInserts.count == 7) // one single insert + a 3 × 2 array
        guard case .insert(_, _, let attrs, _)? = d.entities.first(where: { if case .insert = $0 { return $0.style.handle == "100" }; return false }) else {
            Issue.record("insert missing"); return
        }
        #expect(attrs == ["MARK": "C-101"])
        // Attribute text is shown; the template (ATTDEF) inside the block is not.
        #expect(d.entities.contains { if case .text(_, _, _, let s, _, _) = $0 { return s == "C-101" }; return false })
        #expect(!(d.blocks["CHAIR"] ?? []).contains { if case .text = $0 { return true }; return false })
        // Nested block content is resolvable by flattening (TABLE_SET → CHAIR).
        let flat = d.flattened()
        #expect(flat.filter { if case .polyline(let p, true, _) = $0 { return p.count == 4 }; return false }.count >= 7 + 2 + 1)
    }

    @Test func nestedInsertTransformsMatchSourceGeometry() throws {
        let (d, _, placement) = try convert("ac1027_blocks_annotation.dxf") { $0.explodeBlocks = true }
        // TABLE_SET base (1000,0) inserted at (10000,5000), scale 2, rotated 90°: its corner (2800,1000) → (8000, 8600).
        let pts = d.entities.flatMap { e -> [Vec2] in if case .polyline(let p, _, let st) = e, st.handle == "55" { return p.map(placement.apply) }; return [] }
        #expect(pts.contains { approx($0, Vec2(8.0, 8.6), 1e-9) })
    }

    @Test func explodeBlocksFlattensWithLayerInheritance() throws {
        let (d, _, _) = try convert("ac1027_blocks_annotation.dxf") { $0.explodeBlocks = true }
        #expect(d.blocks.isEmpty)
        #expect(!d.entities.contains { if case .insert = $0 { return true }; return false })
        // Chair outlines live on layer 0 in the block and take the insert's layer when exploded.
        let chairs = d.entities.filter { if case .polyline(_, true, let st) = $0 { return st.handle == "51" }; return false }
        #expect(chairs.count == 1 + 6 + 2)
        #expect(chairs.allSatisfy { d.layers[$0.style.layer].name == "A-FURN" })
    }

    @Test func handlesAndStylesPreservedOnConvertedEntities() throws {
        let (d, _, _) = try convert("ac1015_imperial_layouts.dxf")
        guard case .line(_, let st)? = first(d, handle: "101") else { Issue.record("line missing"); return }
        #expect(d.layers[st.layer].name == "A-WALL")
        #expect(st.color == RGBColor(hex: 0xFF8000))
        #expect(st.lineWeight == 0.35)
        #expect(st.lineType == "HIDDEN")
        let wall = try #require(d.layers.first { $0.name == "A-WALL" })
        #expect(wall.color == RGBColor(hex: 0x336699) && wall.lineWeight == 0.5)
        #expect(d.layers.first { $0.name == "A-ANNO" }?.plots == false)
    }

    @Test func bulgedPolylineKeepsTrueArcsWithSharedHandle() throws {
        let (d, _, _) = try convert("ac1015_imperial_layouts.dxf")
        let parts = d.entities.filter { $0.style.handle == "100" }
        #expect(parts.count == 4)
        let arcs = parts.compactMap { e -> Arc2? in if case .arc(let a, _) = e { return a }; return nil }
        #expect(arcs.count == 1)
        #expect(approx(arcs[0].radius, 48 * 0.0254, 1e-12))
    }

    @Test func curvesTessellatedAndHatchesConverted() throws {
        let (d, _, _) = try convert("ac1027_blocks_annotation.dxf")
        guard case .polyline(let el, true, _)? = first(d, handle: "105") else { Issue.record("ellipse missing"); return }
        #expect(el.count > 16)
        guard case .polyline(let sp, false, _)? = first(d, handle: "107") else { Issue.record("spline missing"); return }
        #expect(sp.count > 4)
        guard case .hatch(let loops, true, _)? = first(d, handle: "109") else { Issue.record("hatch missing"); return }
        #expect(loops.count == 1 && loops[0].count > 8)
        guard case .hatch(_, false, _)? = first(d, handle: "10A") else { Issue.record("pattern hatch missing"); return }
    }

    @Test func dimensionsLeadersAndMultileaders() throws {
        let (d, _, _) = try convert("ac1027_blocks_annotation.dxf")
        guard case .insert(let b, _, _, _)? = first(d, handle: "10B") else { Issue.record("dimension missing"); return }
        #expect(b == "*D1")
        #expect(d.entities.contains { if case .text(_, _, _, let s, _, let st) = $0 { return s == "1234.5 mm" && st.handle == "10C" }; return false })
        let leader = d.entities.filter { $0.style.handle == "10D" }
        #expect(leader.contains { if case .polyline(let p, false, _) = $0 { return p.count == 3 }; return false })
        #expect(leader.contains { if case .hatch(_, true, _) = $0 { return true }; return false }) // arrowhead
        let ml = d.entities.filter { $0.style.handle == "10E" }
        #expect(ml.filter { if case .text = $0 { return true }; return false }.count == 2)
    }

    @Test func proxiesRetainedAsBoundsAndUnsupportedCounted() throws {
        let (d, report, _) = try convert("ac1027_blocks_annotation.dxf")
        guard case .proxy(let r, let n, _)? = first(d, handle: "110") else { Issue.record("proxy missing"); return }
        #expect(n == "AECC_COGO_POINT")
        #expect(approx(r.width, 0.1, 1e-12))
        #expect(report.unsupported == ["ACAD_PROXY_ENTITY": 1, "AECC_COGO_POINT": 1, "3DSOLID": 1])
        #expect(report.retainedAsReference >= 1)
        #expect(report.warnings.contains { $0.contains("unsupported types") })
    }

    @Test func threeDFacesAndMeshesKeptAsReference() throws {
        let (d, report, _) = try convert("r12_plan.dxf")
        let faces = d.entities.filter { if case .face3D = $0 { return true }; return false }
        #expect(faces.count == 3) // one 3DFACE + two polyface triangles
        #expect(report.retainedAsReference == 2)
        guard case .face3D(let pts, _)? = faces.first(where: { if case .face3D(let p, _) = $0 { return p.count == 4 }; return false }) else { return }
        #expect(pts.map(\.z).max() == 0.5)
    }

    @Test func layerFilterAndLayoutSelection() throws {
        let (d, _, _) = try convert("ac1027_blocks_annotation.dxf") { $0.includedLayers = ["a-hatch"] }
        #expect(d.entities.count == 2)
        #expect(Set(d.layers.map(\.name)) == ["0", "A-HATCH"])
        let (s, _, _) = try convert("ac1015_imperial_layouts.dxf") { $0.layout = "Sheet A" }
        #expect(s.entities.contains { if case .text(_, _, _, let t, _, _) = $0 { return t == "SHEET A TITLE" }; return false })
        #expect(s.entities.count == 2)
        let (m, rep, _) = try convert("ac1015_imperial_layouts.dxf") { $0.layout = "Nope" }
        #expect(rep.warnings.contains { $0.contains("“Nope” was not found") })
        #expect(m.entities.count > 2)
    }

    @Test func reportHasEveryFieldFilled() throws {
        let (_, r, _) = try convert("ac1027_blocks_annotation.dxf")
        #expect(r.format == "DXF")
        #expect(r.version == "AutoCAD 2013 (AC1027)")
        #expect(r.units == .millimeters && r.unitScale == 0.001)
        #expect(r.layouts == ["Model"])
        #expect(r.layerCount >= 6)
        #expect(r.entityCountsByType["INSERT"] == 5)
        #expect(r.converted >= 14)
        #expect(CADGeometry.isFinite(r.extents))
        #expect(r.elapsed >= 0)
        #expect(r.summary.contains("Converted"))
    }

    @Test func contentKeyIsDeterministic() throws {
        let (a, _, _) = try convert("ac1027_blocks_annotation.dxf")
        let (b, _, _) = try convert("ac1027_blocks_annotation.dxf")
        #expect(a.contentKey == b.contentKey)
        #expect(a.contentKey != "ref-" + StableHash.hex(Data()))
        let (c, _, _) = try convert("ac1027_blocks_annotation.dxf") { $0.explodeBlocks = true }
        #expect(a.contentKey != c.contentKey)
    }

    @Test func textAlignmentAndMText() throws {
        let (d, _, placement) = try convert("r12_plan.dxf")
        guard case .text(let p, let h, _, _, let al, _)? = d.entities.first(where: { if case .text(_, _, _, let s, _, _) = $0 { return s == "CENTERED" }; return false }) else {
            Issue.record("text missing"); return
        }
        #expect(al == .center)
        #expect(approx(placement.apply(p), Vec2(5, 12), 1e-12))
        #expect(approx(h, 0.25, 1e-12))
        let (u, _, _) = try convert("ac1032_unicode_survey.dxf")
        let lines = u.entities.compactMap { e -> String? in if case .text(_, _, _, let s, _, let st) = e, st.handle == "A5" { return s }; return nil }
        #expect(lines.first == "Grundriss")
        #expect(lines.count >= 3)
    }
}
