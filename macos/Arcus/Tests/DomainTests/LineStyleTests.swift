import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Line styles (W2-ANNOT)")
struct LineStyleTests {
    @Test(arguments: [UnitsSettings.metric, .imperial])
    func newProjectsHaveTheStandardStyles(_ units: UnitsSettings) {
        let (m, _) = ProjectTemplates.make(.architectural, units: units)
        let names = Set(m.elements(.lineStyles).map(\.name))
        for s in LineStyles.standard { #expect(names.contains(s.name), "\(s.name) missing") }
        for expected in ["Thin Lines", "Medium Lines", "Wide Lines", "Lines", "<Hidden>", "<Overhead>", "<Beyond>", "<Centerline>",
                         "<Demolished>", "<Sketch>", "Dashed", "Dash Dot", "Dotted", "Long Dash", "Double Dash", "Property Line"] {
            #expect(names.contains(expected))
        }
        #expect(m.lineStyle(named: "Property Line")?.lineStyle?.pattern == .dashDotDot)
        #expect(m.lineStyle(named: "Wide Lines")?.lineStyle?.weight == 5)
    }

    @Test func patternsHaveAtMostFourDashesAndPaperLengths() {
        for k in LinePatternKind.allCases {
            let p = k.dashPattern
            #expect(p.count % 2 == 0 && p.count <= 8, "\(k)")
            #expect(p.allSatisfy { $0 > 0 && $0 < 20 }, "\(k) lengths are paper millimetres")
        }
        #expect(LinePatternKind.dashDotDot.dashPattern.count == 6)
        #expect(LinePatternKind.solid.dashPattern.isEmpty)
    }

    @Test func userStylesCanBeCreatedRenamedAndDeletedWithUndo() throws {
        let b = AnnotBench(box: false)
        var id: ElementID!
        b.perform("New") { tx in id = try LineStyles.create(name: "  Setting Out ", weight: 20, color: RGBColor(1, 0, 0), pattern: .longDash, in: tx) }
        let style = try #require(b.model[id])
        #expect(style.name == "Setting Out")
        #expect(style.lineStyle?.weight == 16, "weights clamp to 1…16")
        // Duplicate and reserved names are refused.
        #expect(b.perform("Dup") { tx in try LineStyles.create(name: "setting out", weight: 1, in: tx) } == nil)
        #expect(b.session.lastError?.message.contains("already exists") == true)
        #expect(b.perform("Reserved") { tx in try LineStyles.create(name: "<Mine>", weight: 1, in: tx) } == nil)
        // Standard styles can't be renamed or deleted.
        let thin = try #require(b.model.lineStyle(named: "Thin Lines")?.id)
        #expect(b.perform("Rename") { tx in try LineStyles.rename(thin, to: "Hairline", in: tx) } == nil)
        #expect(b.perform("Delete") { tx in try LineStyles.delete(thin, in: tx) } == nil)
        // Rename, draw a line with it, delete: the line moves to Thin Lines; undo brings both back.
        b.perform("Rename") { tx in try LineStyles.rename(id, to: "Setting-Out Line", in: tx) }
        #expect(b.model[id]?.name == "Setting-Out Line")
        let tool = LineTool(ctx: b.ctx(), kind: .detail, commandID: .detailLine)
        tool.setOption("style", .text("Setting-Out Line"))
        b.click(tool, Vec2(0, 0)); b.click(tool, Vec2(3, 0))
        let line = try #require(b.last(.detailLines))
        #expect(line.modelLine?.styleID == id)
        b.perform("Delete Style") { tx in _ = try LineStyles.delete(id, in: tx) }
        #expect(b.model[id] == nil)
        #expect(b.model[line.id]?.modelLine?.styleID == thin)
        b.undo()
        #expect(b.model[id]?.name == "Setting-Out Line")
        #expect(b.model[line.id]?.modelLine?.styleID == id)
        b.redo()
        #expect(b.model[id] == nil)
        // Editing a standard style's weight is allowed (and validated).
        b.perform("Weight") { tx in try LineStyles.edit(thin, weight: 2, in: tx) }
        #expect(b.model[thin]?.lineStyle?.weight == 2)
        #expect(b.perform("Bad weight") { tx in try LineStyles.edit(thin, weight: 0, in: tx) } == nil)
    }

    @Test func detailLineToolOffersStylesWithPreviewsAndDrawsInTheStyle() throws {
        let b = AnnotBench(box: false)
        let tool = LineTool(ctx: b.ctx(), kind: .detail, commandID: .detailLine)
        let opt = try #require(tool.options.first { $0.id == "style" })
        guard case .choice(let names) = opt.kind else { Issue.record("style is a choice"); return }
        #expect(names.first == "Thin Lines", "standard styles first")
        #expect(opt.lineStyles?["Dashed"]?.pattern == .dash, "previews carry the pattern")
        #expect(opt.value.textValue == "Thin Lines")
        tool.setOption("style", .text("<Hidden>"))
        b.click(tool, Vec2(0, 0))
        tool.pointerMoved(b.input(Vec2(2, 1)))
        let rubber = AnnotBench.polylines(tool.preview.primitives)
        #expect(rubber.contains { $0.1.pattern == .hidden }, "the rubber band shows the pattern")
        b.click(tool, Vec2(4, 0))
        let line = try #require(b.last(.detailLines))
        #expect(line.ownerViewID == b.plan)
        let item = try #require(b.item(line.id))
        let st = try #require(AnnotBench.polylines(item.primitives).first?.1)
        #expect(st.pattern == .hidden && st.weight == 1)
        // Model lines (plan, level-hosted) take styles too.
        let model = LineTool(ctx: b.ctx(), kind: .model, commandID: .modelLine)
        model.setOption("style", .text("Wide Lines"))
        b.click(model, Vec2(0, 5)); b.click(model, Vec2(4, 5))
        let ml = try #require(b.model.elements(.detailLines).first { $0.ownerViewID == nil })
        #expect(b.model[ml.modelLine?.styleID]?.name == "Wide Lines")
        #expect(AnnotBench.polylines(try b.prims(ml.id)).first?.1.weight == 5)
    }

    @Test func selectedLinesChangeStyleThroughProperties() throws {
        let b = AnnotBench(box: false)
        let tool = LineTool(ctx: b.ctx(), kind: .detail, commandID: .detailLine)
        b.click(tool, Vec2(0, 0)); b.click(tool, Vec2(4, 0))
        let line = try #require(b.last(.detailLines))
        let entry = try #require(Parameters.instanceEntries(line, b.model).first { $0.name == "Line Style" })
        #expect(entry.type == .elementRef(.lineStyles))
        let dashed = try #require(b.model.lineStyle(named: "Dash Dot")?.id)
        b.perform("Style") { tx in try Parameters.set(entry.id, to: .ref(dashed), on: line.id, in: tx) }
        #expect(AnnotBench.polylines(try b.prims(line.id)).first?.1.pattern == .dashDot)
        b.undo()
        #expect(b.model[line.id]?.modelLine?.styleID == b.model.lineStyle(named: "Thin Lines")?.id)
        // A non-style element is refused.
        #expect(b.perform("Bad") { tx in try Parameters.set(entry.id, to: .ref(b.plan), on: line.id, in: tx) } == nil)
    }

    @Test func viewOverridesApplyOnTopOfTheStyle() throws {
        let b = AnnotBench(box: false)
        let tool = LineTool(ctx: b.ctx(), kind: .detail, commandID: .detailLine)
        tool.setOption("style", .text("Dashed"))
        b.click(tool, Vec2(0, 0)); b.click(tool, Vec2(4, 0))
        let line = try #require(b.last(.detailLines))
        var o = GraphicOverride()
        o.projectionLineWeight = 6
        let item = try #require(AnnotationRenderer.item(line, o, model: b.model, scale: 100, builder: nil))
        let st = try #require(AnnotBench.polylines(item.primitives).first?.1)
        #expect(st.weight == 6 && st.pattern == .dash)
    }

    @Test func olderProjectsGetTheMissingStandardStyles() {
        let b = AnnotBench(box: false)
        let hidden = b.model.lineStyle(named: "<Hidden>")!.id
        b.perform("Remove") { tx in tx.delete(hidden) }
        var added = 0
        b.perform("Add") { tx in added = LineStyles.ensureStandard(in: tx) }
        #expect(added == 1)
        #expect(b.model.lineStyle(named: "<Hidden>") != nil)
    }
}
