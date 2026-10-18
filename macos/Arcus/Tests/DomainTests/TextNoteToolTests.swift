import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Text notes (W2-ANNOT)")
struct TextNoteToolTests {
    func note(_ b: AnnotBench) throws -> Element { try #require(b.last(.textNotes)) }

    @Test func textToolPlacesTextWithTheChosenTypeAndAlignment() throws {
        let b = AnnotBench()
        b.typedText = "ROOF OVER"
        let ctx = b.ctx()
        let bigger = try #require(b.model.types(for: .textNotes).first { $0.name == "3.5mm Arial" })
        ctx.currentTypes[.textNotes] = bigger.id
        let tool = TextTool(ctx: ctx)
        tool.setOption("align", .text("Center"))
        tool.pointerMoved(b.input(Vec2(2, 2)))
        #expect(!AnnotBench.texts(tool.preview.primitives).isEmpty, "the text previews at the pointer")
        b.click(tool, Vec2(2, 2))
        let n = try note(b)
        #expect(n.textNote?.text == "ROOF OVER")
        #expect(n.textNote?.alignment == .center)
        #expect(n.typeID == bigger.id)
        #expect(n.ownerViewID == b.plan)
        let t = try #require(AnnotBench.texts(try b.prims(n.id)).first)
        #expect(abs(t.height - 0.0035) < 1e-9, "type size on paper")
        #expect(t.alignment == .center)
        b.undo()
        #expect(b.model.elements(.textNotes).isEmpty)
        b.redo()
        #expect(b.model.elements(.textNotes).count == 1)
        // Cancelled or empty text creates nothing.
        b.typedText = "   "
        b.click(tool, Vec2(5, 5))
        b.typedText = nil
        b.click(tool, Vec2(6, 5))
        #expect(b.model.elements(.textNotes).count == 1)
    }

    @Test func defaultTextTypeIsTheSmallestPlainType() throws {
        let b = AnnotBench(units: .imperial)
        let tool = TextTool(ctx: b.ctx())
        b.click(tool, Vec2(1, 1))
        let n = try note(b)
        #expect(b.model[n.typeID]?.name == "3/32\" Arial")
    }

    @Test func leadersOneSegmentTwoSegmentsAndCurved() throws {
        let b = AnnotBench()
        let tool = TextTool(ctx: b.ctx())
        tool.setOption("leader", .text("One Segment"))
        b.click(tool, Vec2(1, 1))          // arrow
        b.click(tool, Vec2(3, 3))          // text
        var n = try note(b)
        #expect(n.textNote?.leaders == [Vec2(1, 1)])
        var item = try #require(b.item(n.id))
        let lines = AnnotBench.polylines(item.primitives)
        #expect(lines.contains { $0.0.last == Vec2(1, 1) && $0.0.count == 3 }, "leader with a shoulder ends at the arrow point")
        #expect(!AnnotBench.fills(item.primitives).isEmpty, "arrowhead")
        // The leader leaves from beside the text, not from inside it.
        let box = TextNoteGeometry.box(n.textNote!, TextNoteStyle.resolve(n, b.model), scale: 100)
        let start = try #require(lines.first { $0.0.last == Vec2(1, 1) }?.0.first)
        #expect(!box.polygon.contains(start))

        tool.setOption("leader", .text("Two Segments"))
        b.click(tool, Vec2(6, 1)); b.click(tool, Vec2(6, 2)); b.click(tool, Vec2(7, 3))
        n = try note(b)
        #expect(n.textNote?.elbow(0) == Vec2(6, 2))
        item = try #require(b.item(n.id))
        #expect(AnnotBench.polylines(item.primitives).contains { $0.0.contains(Vec2(6, 2)) })

        tool.setOption("leader", .text("Curved"))
        b.click(tool, Vec2(1, 6)); b.click(tool, Vec2(4, 7))
        n = try note(b)
        #expect(n.textNote?.leaderShape == .arc)
        #expect(!AnnotBench.arcs(try b.prims(n.id)).isEmpty)
        #expect(tool.escape() == .exitTool)
    }

    @Test func dragSetsTheWrapWidth() throws {
        let b = AnnotBench()
        let tool = TextTool(ctx: b.ctx())
        b.typedText = "A long note that wraps inside the width dragged for it"
        b.drag(tool, from: Vec2(0, 2), to: Vec2(4, 1))
        let n = try note(b)
        // 4 m at 1:100 = 40 mm of paper.
        #expect(abs((n.textNote?.width ?? 0) - 0.04) < 1e-9)
        #expect(n.textNote?.position == Vec2(0, 2), "top-left of the dragged box")
        let t = try #require(AnnotBench.texts(try b.prims(n.id)).first)
        #expect(abs(t.wrapWidth - 0.04) < 1e-9)
        // The estimated block wraps into several lines, so its box is taller than one line.
        let box = TextNoteGeometry.box(n.textNote!, TextNoteStyle.resolve(n, b.model), scale: 100)
        #expect(box.height > 0.0025 * 100 * 2)
    }

    @Test func gripsMoveTextLeadersElbowsAndWidthWithUndo() throws {
        let b = AnnotBench()
        let tool = TextTool(ctx: b.ctx())
        tool.setOption("leader", .text("One Segment"))
        b.click(tool, Vec2(1, 1)); b.click(tool, Vec2(3, 3))
        let n = try note(b)
        let grips = GripService.grips(for: n, b.model, viewKind: .floorPlan)
        #expect(grips.contains { $0.kind == .textPosition })
        let width = try #require(grips.first { $0.kind == .textWidth })
        let end = try #require(grips.first { $0.kind == .leaderEnd(0) })
        let elbow = try #require(grips.first { $0.kind == .leaderElbow(0) })
        let select = SelectTool(ctx: b.ctx())
        func dragGrip(_ g: Grip, to p: Vec2) {
            b.step {
                _ = select.beginDrag(at: g.position, grip: g)
                select.dragged(to: p)
                select.endDrag(at: p)
            }
        }
        // Dragging previews the note live.
        _ = select.beginDrag(at: end.position, grip: end)
        select.dragged(to: Vec2(0, 0))
        #expect(!AnnotBench.fills(select.preview.primitives).isEmpty, "live preview includes the moved arrow")
        _ = select.escape()
        dragGrip(end, to: Vec2(0, 0))
        #expect(b.model[n.id]?.textNote?.leaders == [Vec2(0, 0)])
        dragGrip(elbow, to: Vec2(1.5, 2.9))
        #expect(b.model[n.id]?.textNote?.elbow(0) == Vec2(1.5, 2.9))
        dragGrip(width, to: Vec2(3 + 3, width.position.y))
        #expect(abs((b.model[n.id]?.textNote?.width ?? 0) - 0.03) < 1e-9, "3 m right of the insertion point at 1:100")
        b.undo()
        #expect(b.model[n.id]?.textNote?.width == 0)
        b.undo()
        #expect(b.model[n.id]?.textNote?.elbow(0) == nil)
        b.redo()
        #expect(b.model[n.id]?.textNote?.elbow(0) == Vec2(1.5, 2.9))
    }

    @Test func leadersAreAddedAndRemoved() throws {
        let b = AnnotBench()
        b.click(TextTool(ctx: b.ctx()), Vec2(3, 3))
        let id = try note(b).id
        b.perform("Add") { tx in TextLeaders.add(to: id, in: tx) }
        b.perform("Add") { tx in TextLeaders.add(to: id, in: tx) }
        let n = try #require(b.model[id]?.textNote)
        #expect(n.leaders.count == 2)
        #expect(n.leaders[0].x < 3 && n.leaders[1].x > 3, "the second leader goes to the other side")
        b.perform("Remove") { tx in TextLeaders.removeLast(from: id, in: tx) }
        #expect(b.model[id]?.textNote?.leaders.count == 1)
        b.undo()
        #expect(b.model[id]?.textNote?.leaders.count == 2)
    }

    @Test func typeAndInstanceFacesBackgroundAndArrowheads() throws {
        let b = AnnotBench()
        b.click(TextTool(ctx: b.ctx()), Vec2(3, 3))
        let n = try note(b)
        var t = try #require(AnnotBench.texts(try b.prims(n.id)).first)
        #expect(t.opaque, "new projects' text types are opaque")
        #expect(!t.bold && !t.italic && !t.underline)
        let type = try #require(n.typeID)
        let typeEntries = Parameters.typeEntries(b.model[type]!, b.model)
        for name in ["Text Size", "Bold", "Italic", "Underline", "Background", "Leader Arrowhead"] {
            #expect(typeEntries.contains { $0.name == name }, "text type parameter \(name)")
        }
        b.perform("Italic") { tx in try Parameters.set(AnnotationParams.textItalic, to: .bool(true), on: type, in: tx) }
        b.perform("Transparent") { tx in try Parameters.set(AnnotationParams.textBackground, to: .text("Transparent"), on: type, in: tx) }
        b.perform("Dot") { tx in try Parameters.set(AnnotationParams.textArrowhead, to: .text("Dot Filled"), on: type, in: tx) }
        let inst = Parameters.instanceEntries(b.model[n.id]!, b.model)
        let underline = try #require(inst.first { $0.name == "Underline" })
        let bold = try #require(inst.first { $0.name == "Bold" })
        b.perform("Underline") { tx in try Parameters.set(underline.id, to: .bool(true), on: n.id, in: tx) }
        b.perform("Bold") { tx in try Parameters.set(bold.id, to: .bool(true), on: n.id, in: tx) }
        t = try #require(AnnotBench.texts(try b.prims(n.id)).first)
        #expect(t.italic && t.underline && t.bold && !t.opaque)
        #expect(Parameters.value(bold.id, of: b.model[n.id]!, b.model)?.boolValue == true)
        let align = try #require(inst.first { $0.name == "Horizontal Align" })
        b.perform("Align") { tx in try Parameters.set(align.id, to: .text("Right"), on: n.id, in: tx) }
        #expect(b.model[n.id]?.textNote?.alignment == .right)
        #expect(b.perform("Bad") { tx in try Parameters.set(AnnotationParams.textBackground, to: .text("Glass"), on: type, in: tx) } == nil)
    }

    @Test func textStaysTheSameSizeOnPaperAtEveryScale() throws {
        let b = AnnotBench()
        b.click(TextTool(ctx: b.ctx()), Vec2(3, 3))
        let n = try note(b)
        let at100 = TextNoteGeometry.box(n.textNote!, TextNoteStyle.resolve(n, b.model), scale: 100)
        let at50 = TextNoteGeometry.box(n.textNote!, TextNoteStyle.resolve(n, b.model), scale: 50)
        #expect(abs(at100.height / at50.height - 2) < 1e-9, "twice the model size at 1:100 than at 1:50")
        b.perform("Scale") { tx in tx.update(b.plan) { $0.view?.scale = 50 } }
        let t = try #require(AnnotBench.texts(try b.prims(n.id)).first)
        #expect(abs(t.height - 0.0025) < 1e-9, "GText heights are paper sizes")
        let hit = try #require(b.item(n.id)?.hitPolygons.first)
        #expect(abs(hit.bounds.height - at50.height) < 1e-6, "picking area follows the scale")
    }

    @Test func textWorksInDraftingViewsSectionsAndOnSheets() throws {
        let b = AnnotBench()
        for view in [b.draftingView(), b.section(), b.sheet()] {
            b.click(TextTool(ctx: b.ctx(view)), Vec2(0.05, 0.05))
            let n = try note(b)
            #expect(n.ownerViewID == view)
            #expect(b.strings(n.id, view) == ["Note"], "\(b.model[view]!.name)")
        }
    }

    @Test func doubleClickEditingAndDeletion() throws {
        let b = AnnotBench()
        b.click(TextTool(ctx: b.ctx()), Vec2(3, 3))
        let n = try note(b)
        b.perform("Edit Text") { tx in tx.update(n.id) { $0.textNote?.text = "Edited" } }
        #expect(b.strings(n.id) == ["Edited"])
        b.step { b.session.delete([n.id]) }
        #expect(b.model[n.id] == nil)
        b.undo()
        #expect(b.strings(n.id) == ["Edited"])
    }

    @Test func textNotesHideWithTheirCategory() throws {
        let b = AnnotBench()
        b.click(TextTool(ctx: b.ctx()), Vec2(3, 3))
        let n = try note(b)
        #expect(b.item(n.id) != nil)
        b.perform("Hide") { tx in tx.update(b.plan) { $0.view?.visibility.hiddenCategories.insert(.textNotes) } }
        #expect(b.item(n.id) == nil)
    }
}
