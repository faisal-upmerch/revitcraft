import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Dimension tools (W2-ANNOT)")
struct DimensionToolTests {
    func dim(_ b: AnnotBench) throws -> Element { try #require(b.last(.dimensions)) }
    func value(_ b: AnnotBench, _ e: Element) -> [Double] { AnnotationGeometry.measure(b.model[e.id]!, b.model).map { ($0 * 1e6).rounded() / 1e6 } }

    func detailLine(_ b: AnnotBench, _ a: Vec2, _ c: Vec2, view: ElementID? = nil) -> ElementID {
        var id: ElementID!
        b.perform("Line") { tx in id = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(a, c)))), ownerViewID: view ?? b.plan) }
        return id
    }

    @Test func alignedDimensionBetweenWallFacesWithPreviewAndUndo() throws {
        let b = AnnotBench()
        let tool = DimensionTool(ctx: b.ctx(), kind: .aligned)
        b.click(tool, Vec2(5, 0.08), hit: b.walls[0])
        tool.pointerMoved(b.input(Vec2(5, 7.92), hit: b.walls[2]))
        #expect(tool.preview.highlight.contains(b.walls[2]), "the reference under the pointer is highlighted")
        b.click(tool, Vec2(5, 7.92), hit: b.walls[2])
        tool.pointerMoved(b.input(Vec2(3, 4)))
        #expect(!AnnotBench.texts(tool.preview.primitives).isEmpty, "the dimension previews before it is placed")
        b.click(tool, Vec2(3, 4))
        let d = try dim(b)
        #expect(d.ownerViewID == b.plan)
        #expect(d.typeID != nil)
        #expect(value(b, d) == [7.8], "interior faces of 200 mm walls 8 m apart")
        let texts = AnnotBench.texts(try b.prims(d.id))
        #expect(texts.count == 1)
        #expect(texts[0].string.contains("7800") || texts[0].string.contains("7.8"))
        // Witness lines start where the faces were picked (x = 5, less the 1.5 mm gap), not at the walls' midpoints.
        let witness = AnnotBench.polylines(try b.prims(d.id)).map(\.0).filter { $0.count == 2 && abs($0[0].y - $0[1].y) < 1e-9 }
        #expect(witness.count == 2)
        #expect(witness.allSatisfy { abs($0[0].x - 4.85) < 1e-6 }, "\(witness)")
        #expect(b.item(d.id)?.hitPolygons.isEmpty == false, "the value text can be clicked")
        b.undo()
        #expect(b.model.elements(.dimensions).isEmpty)
        b.redo()
        #expect(b.model.elements(.dimensions).count == 1)
    }

    @Test func linearDimensionMeasuresHorizontallyOrVertically() throws {
        let b = AnnotBench(box: false)
        let tool = DimensionTool(ctx: b.ctx(), kind: .linear)
        b.click(tool, Vec2(0, 0), snapped: true)
        b.click(tool, Vec2(3, 4), snapped: true)
        b.click(tool, Vec2(0.5, -2))
        #expect(value(b, try dim(b)) == [3])
        b.click(tool, Vec2(0, 0), snapped: true)
        b.click(tool, Vec2(3, 4), snapped: true)
        b.click(tool, Vec2(-2, 1))
        #expect(value(b, try dim(b)) == [4])
    }

    @Test func angularRadialDiameterAndArcLength() throws {
        let b = AnnotBench(box: false)
        let l1 = detailLine(b, Vec2(0, 0), Vec2(4, 0)), l2 = detailLine(b, Vec2(0, 0), Vec2(0, 4))
        let angular = DimensionTool(ctx: b.ctx(), kind: .angular)
        b.click(angular, Vec2(2, 0), hit: l1)
        b.click(angular, Vec2(0, 2), hit: l2)
        b.click(angular, Vec2(1, 1))
        #expect(AnnotBench.strings(try b.prims(try dim(b).id)).first?.hasPrefix("90.00°") == true)
        #expect(!AnnotBench.arcs(try b.prims(try dim(b).id)).isEmpty)

        var arc: ElementID!
        b.perform("Arc") { tx in arc = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .arc(Arc2(center: Vec2(20, 0), radius: 2, startAngle: 0, sweep: .pi / 2)))), ownerViewID: b.plan) }
        for (kind, prefix) in [(DimensionKind.radial, "R "), (.diameter, "⌀ "), (.arcLength, "")] {
            let tool = DimensionTool(ctx: b.ctx(), kind: kind)
            b.click(tool, Vec2(20 + 2 * cos(0.7), 2 * sin(0.7)), hit: arc)
            b.click(tool, Vec2(23, 3))
            let d = try dim(b)
            #expect(d.dimension?.kind == kind)
            let s = try #require(AnnotBench.strings(try b.prims(d.id)).first)
            #expect(s.hasPrefix(prefix), "\(kind): \(s)")
            if kind == .arcLength { #expect(s.contains("3142") || s.contains("3.14"), "quarter circle of radius 2: \(s)") }
        }
    }

    @Test func tickMarksWitnessGapAndTextSizeComeFromTheType() throws {
        let b = AnnotBench()
        let tool = DimensionTool(ctx: b.ctx(), kind: .aligned)
        b.click(tool, Vec2(5, 0.08), hit: b.walls[0])
        b.click(tool, Vec2(5, 7.92), hit: b.walls[2])
        b.click(tool, Vec2(3, 4))
        let d = try dim(b)
        let type = try #require(d.typeID)
        let entries = Parameters.typeEntries(b.model[type]!, b.model).map(\.name)
        for n in ["Tick Mark", "Witness Line Gap to Element", "Witness Line Extension", "Dimension Line Extension", "Text Size", "Text Offset"] {
            #expect(entries.contains(n), "dimension type parameter \(n)")
        }
        #expect(AnnotBench.fills(try b.prims(d.id)).isEmpty, "diagonal ticks are strokes")
        b.perform("Arrow") { tx in try Parameters.set(AnnotationParams.dimensionTick, to: .text("Arrow Filled"), on: type, in: tx) }
        #expect(AnnotBench.fills(try b.prims(d.id)).count == 2, "one arrow at each end")
        b.perform("Dot") { tx in try Parameters.set(AnnotationParams.dimensionTick, to: .text("Dot Filled"), on: type, in: tx) }
        #expect(AnnotBench.fills(try b.prims(d.id)).count == 2)
        // Witness line gap: 3 mm of paper = 0.3 m at 1:100 from the picked face.
        b.perform("Gap") { tx in try Parameters.set(AnnotationParams.dimensionWitnessGap, to: .double(0.003), on: type, in: tx) }
        let starts = AnnotBench.polylines(try b.prims(d.id)).map(\.0).filter { $0.count == 2 && abs($0[0].y - $0[1].y) < 1e-9 }.map { $0[0].x }
        #expect(starts.count == 2 && starts.allSatisfy { abs($0 - 4.7) < 1e-6 }, "witnesses start 0.3 m from the picked point at x = 5: \(starts)")
        b.perform("Size") { tx in try Parameters.set(AnnotationParams.dimensionTextSize, to: .double(0.004), on: type, in: tx) }
        #expect(AnnotBench.texts(try b.prims(d.id)).first?.height == 0.004)
        #expect(b.perform("Too big") { tx in try Parameters.set(AnnotationParams.dimensionWitnessGap, to: .double(1), on: type, in: tx) } == nil)
    }

    @Test func equalityDisplayAndTextDrag() throws {
        let b = AnnotBench(box: false)
        let a = detailLine(b, Vec2(0, 0), Vec2(0, 5)), m = detailLine(b, Vec2(2, 0), Vec2(2, 5)), c = detailLine(b, Vec2(4, 0), Vec2(4, 5))
        let tool = DimensionTool(ctx: b.ctx(), kind: .aligned)
        b.click(tool, Vec2(0, 1), hit: a); b.click(tool, Vec2(2, 1), hit: m); b.click(tool, Vec2(4, 1), hit: c)
        b.click(tool, Vec2(1, -1))
        let d = try dim(b)
        #expect(d.dimension?.references.count == 3)
        #expect(AnnotBench.strings(try b.prims(d.id)).count == 2)
        b.perform("EQ") { tx in tx.update(d.id) { $0.dimension?.equality = true } }
        #expect(AnnotBench.strings(try b.prims(d.id)) == ["EQ", "EQ"])
        let display = try #require(Parameters.instanceEntries(b.model[d.id]!, b.model).first { $0.name == "Equality Display" })
        b.perform("Formula") { tx in try Parameters.set(display.id, to: .text("Equality Formula"), on: d.id, in: tx) }
        let formula = AnnotBench.strings(try b.prims(d.id))
        #expect(formula.count == 1 && formula[0].hasPrefix("2 @ "), "\(formula)")
        b.perform("Value") { tx in try Parameters.set(display.id, to: .text("Value"), on: d.id, in: tx) }
        #expect(AnnotBench.strings(try b.prims(d.id)).allSatisfy { $0 != "EQ" })
        // Drag the second value text up; the others stay.
        let grips = GripService.grips(for: b.model[d.id]!, b.model, viewKind: .floorPlan)
        let text1 = try #require(grips.first { $0.kind == .dimensionText(1) })
        b.perform("Drag") { tx in GripService.apply(text1, to: text1.position + Vec2(0, 1), in: tx) }
        let moved = AnnotBench.texts(try b.prims(d.id)).map(\.position)
        #expect(moved.contains { $0.isAlmostEqual(text1.position + Vec2(0, 1), tolerance: 1e-6) })
        #expect(b.model[d.id]?.dimension?.textOffsets?.count == 2)
        // Deleting the middle line trims the string instead of deleting it.
        b.step { b.session.delete([m]) }
        #expect(b.model[d.id]?.dimension?.references.count == 2)
        #expect(value(b, b.model[d.id]!) == [4])
        b.undo()
        #expect(b.model[d.id]?.dimension?.references.count == 3)
        // A two-reference dimension goes with its reference.
        b.step { b.session.delete([m]) }
        b.step { b.session.delete([a]) }
        #expect(b.model[d.id] == nil)
    }

    @Test func dimensionsInASectionMeasureLevelsAndWalls() throws {
        let b = AnnotBench()
        let section = b.section()
        let ctx = b.ctx(section)
        let levels = b.model.levels
        let tool = DimensionTool(ctx: ctx, kind: .aligned)
        b.click(tool, Vec2(3, levels[0].level!.elevation), hit: levels[0].id)
        b.click(tool, Vec2(3, levels[1].level!.elevation), hit: levels[1].id)
        b.click(tool, Vec2(1, 1))
        let dl = try dim(b)
        #expect(dl.ownerViewID == section)
        #expect(value(b, dl) == [levels[1].level!.elevation - levels[0].level!.elevation])
        // West and east walls are cut by the section: their faces are vertical lines at their stations.
        let frameU: (Double) -> Double = { x in x + 2 }   // the section starts at x = −2 and looks north
        let west = b.walls[3], east = b.walls[1]
        let t2 = DimensionTool(ctx: ctx, kind: .aligned)
        b.click(t2, Vec2(frameU(0.08), 1.5), hit: west)
        b.click(t2, Vec2(frameU(9.92), 1.5), hit: east)
        b.click(t2, Vec2(frameU(5), 2.5))
        let dw = try dim(b)
        #expect(value(b, dw) == [9.8], "interior faces: \(value(b, dw))")
        let texts = AnnotBench.texts(try b.prims(dw.id, section))
        #expect(texts.count == 1)
        #expect(abs(texts[0].position.y - 2.5) < 0.5, "drawn where it was placed in the section")
        // The Value parameter measures in the section too.
        let v = Parameters.value(ParameterID("dimension.value"), of: b.model[dw.id]!, b.model)?.doubleValue
        #expect(abs((v ?? 0) - 9.8) < 1e-6)
    }

    @Test func dimensionsInDraftingViewsAndSheets() throws {
        let b = AnnotBench(box: false)
        let drafting = b.draftingView()
        let a = detailLine(b, Vec2(0, 0), Vec2(0, 1), view: drafting), c = detailLine(b, Vec2(0.6, 0), Vec2(0.6, 1), view: drafting)
        let tool = DimensionTool(ctx: b.ctx(drafting), kind: .aligned)
        b.click(tool, Vec2(0, 0.5), hit: a); b.click(tool, Vec2(0.6, 0.5), hit: c); b.click(tool, Vec2(0.3, -0.2))
        let d = try dim(b)
        #expect(value(b, d) == [0.6])
        #expect(AnnotBench.strings(try b.prims(d.id, drafting)).count == 1)
        let sheet = b.sheet()
        let st = DimensionTool(ctx: b.ctx(sheet), kind: .linear)
        b.click(st, Vec2(0.1, 0.1), snapped: true); b.click(st, Vec2(0.3, 0.1), snapped: true); b.click(st, Vec2(0.15, 0.02))
        let ds = try dim(b)
        #expect(ds.ownerViewID == sheet)
        #expect(value(b, ds) == [0.2])
        #expect(AnnotBench.strings(try b.prims(ds.id, sheet)).count == 1, "sheet dimensions draw at paper size")
    }

    @Test func dimensionSizesAreOnPaper() throws {
        let b = AnnotBench()
        let tool = DimensionTool(ctx: b.ctx(), kind: .aligned)
        b.click(tool, Vec2(5, 0.08), hit: b.walls[0]); b.click(tool, Vec2(5, 7.92), hit: b.walls[2]); b.click(tool, Vec2(3, 4))
        let d = try dim(b)
        func textOffset() throws -> Double {
            let t = try #require(AnnotBench.texts(try b.prims(d.id)).first)
            return abs(t.position.x - 3)
        }
        let at100 = try textOffset()
        b.perform("Scale") { tx in tx.update(b.plan) { $0.view?.scale = 50 } }
        let at50 = try textOffset()
        #expect(abs(at100 / at50 - 2) < 1e-6, "text sits 1.2 mm of paper from the line at any scale")
    }
}
