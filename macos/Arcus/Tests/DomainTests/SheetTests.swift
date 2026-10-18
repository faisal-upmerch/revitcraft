import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Sheets, viewports and revisions")
struct SheetTests {
    /// A class so closures passed to `Fx.commit(&s.model)` can read the immutable ids without an exclusivity conflict.
    final class Setup {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        let l1: ElementID
        let sheet: ElementID
        let viewport: ElementID
        init(box: Fx.Box, sheet: ElementID, viewport: ElementID) {
            model = box.model; ids = box.ids; l1 = box.l1; self.sheet = sheet; self.viewport = viewport
        }
    }

    func setup(crop: Rect2? = nil) throws -> Setup {
        var box = try Fx.box { tx, ids, walls in Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0)) }
        let sheet = box.model.sheets[0].id
        let plan = box.ids.planViews[box.l1]!
        var vp: ElementID!
        try Fx.commit(&box.model) { tx in
            if let crop { tx.update(plan) { $0.view?.cropActive = true; $0.view?.cropRegion = crop } }
            vp = tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.4, 0.3), detailNumber: "1")), ownerViewID: sheet)
        }
        return Setup(box: box, sheet: sheet, viewport: vp)
    }

    func texts(_ g: ViewGraphics) -> [String] {
        g.items.flatMap(\.primitives).compactMap { if case .text(let t) = $0 { return t.string } else { return nil } }
    }

    @Test func viewportLayoutIsCentredAndScaled() throws {
        let s = try setup()
        let b = SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!)
        let (layout, graphics) = try #require(b.layouts().first)
        #expect(layout.viewportID == s.viewport)
        #expect(layout.scale == 100)
        #expect(Fx.approx(layout.box.center, Vec2(0.4, 0.3), 1e-12))
        let region = SheetGraphicsBuilder.viewRegion(graphics!)
        #expect(Fx.approx(layout.box.width, region.width / 100, 1e-12))
        #expect(Fx.approx(layout.box.height, region.height / 100, 1e-12))
        #expect(Fx.approx(layout.transform.apply(region.center), Vec2(0.4, 0.3), 1e-12))
    }

    @Test func croppedViewportClipsToTheCrop() throws {
        let crop = Rect2(min: Vec2(-1, -1), max: Vec2(6, 9))
        let s = try setup(crop: crop)
        let b = SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!)
        let layout = try #require(b.layouts().first).0
        #expect(Fx.approx(layout.box.width, 0.07, 1e-12) && Fx.approx(layout.box.height, 0.10, 1e-12))
        let g = b.build()
        let margin = 0.012 + 1e-9
        for item in g.items where item.elementID == s.viewport && item.layer != .annotation {
            #expect(layout.box.expanded(by: margin).contains(item.bounds) || item.bounds.isEmpty)
        }
        #expect(g.items.contains { $0.elementID == s.viewport && $0.targetViewID == s.ids.planViews[s.l1] })
        #expect(g.extents == Rect2(min: .zero, max: PaperSize.a1.landscapeSize))
    }

    @Test func titleBlockFieldsAndViewportTitle() throws {
        let s = try setup()
        let info = s.model.projectInfoElement!.id
        try Fx.commit(&s.model) { tx in
            tx.update(s.sheet) { $0.name = "Ground Floor Plan"; $0.sheet?.drawnBy = "FI" }
            tx.update(info) { $0.projectInfo?.projectNumber = "P-042" }
        }
        let b = SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!)
        #expect(b.titleBlockValue("Sheet Number") == "A101")
        #expect(b.titleBlockValue("Sheet Name") == "Ground Floor Plan")
        #expect(b.titleBlockValue("Project Name") == "Untitled Project")
        #expect(b.titleBlockValue("Project Number") == "P-042")
        #expect(b.titleBlockValue("Organization") == "Arcus Studio")
        #expect(b.titleBlockValue("Drawn By") == "FI")
        #expect(b.titleBlockValue("Scale") == "1 : 100")
        #expect(b.titleBlockValue("Appears In Sheet List") == "Yes")
        #expect(b.titleBlockValue("No Such Field") == "")
        let t = texts(b.build())
        #expect(t.contains("A101") && t.contains("Ground Floor Plan") && t.contains("P-042"))
        #expect(t.contains("LEVEL 1"), "viewport title uses the upper-cased view name")
        #expect(t.contains("1"), "detail number")
        #expect(b.build().items.contains { $0.category == .titleBlocks })
    }

    @Test func scaleFieldSaysAsIndicatedForMixedScales() throws {
        let s = try setup()
        #expect(SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!).titleBlockValue("Scale") == "1 : 100")
        try Fx.commit(&s.model) { tx in
            let l2 = s.ids.planViews[s.ids.levels[1]]!
            tx.update(l2) { $0.view?.scale = 50 }
            tx.create(.viewports, data: .viewport(ViewportData(viewID: l2, center: Vec2(0.2, 0.3), detailNumber: "2")), ownerViewID: s.sheet)
        }
        #expect(SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!).titleBlockValue("Scale") == "As indicated")
        var empty = s.model
        var newSheet: ElementID!
        try Fx.commit(&empty) { tx in newSheet = tx.create(.sheets, name: "Blank", data: .sheet(SheetData(number: "A999"))) }
        #expect(SheetGraphicsBuilder(model: empty, sheet: empty[newSheet]!).titleBlockValue("Scale") == "")
    }

    @Test func sheetWithoutTitleBlockDrawsBorder() throws {
        let s = try setup()
        var blank: ElementID!
        try Fx.commit(&s.model) { tx in blank = tx.create(.sheets, name: "Sketch", data: .sheet(SheetData(number: "SK1", paper: .a3))) }
        let g = SheetGraphicsBuilder(model: s.model, sheet: s.model[blank]!).build()
        #expect(g.items.contains { $0.category == .titleBlocks })
        #expect(texts(g).contains("SK1 – Sketch"))
        #expect(g.extents.max == PaperSize.a3.landscapeSize)
    }

    @Test func aViewCanBePlacedOnOneSheetOnly() throws {
        let s = try setup()
        let plan = s.ids.planViews[s.l1]!
        let tx = TransactionContext(model: s.model, name: "Twice")
        let other = tx.create(.sheets, name: "Other", data: .sheet(SheetData(number: "A102")))
        tx.create(.viewports, data: .viewport(ViewportData(viewID: plan, center: Vec2(0.3, 0.3), detailNumber: "1")), ownerViewID: other)
        #expect(throws: TransactionError.self) { try tx.commit() }
        // Legends may appear on many sheets.
        try Fx.commit(&s.model) { tx in
            let legend = tx.create(.views, name: "Legend 1", data: .view(ViewData(kind: .legend)))
            let a = tx.create(.sheets, name: "A", data: .sheet(SheetData(number: "A201")))
            let b = tx.create(.sheets, name: "B", data: .sheet(SheetData(number: "A202")))
            tx.create(.viewports, data: .viewport(ViewportData(viewID: legend, center: Vec2(0.3, 0.3), detailNumber: "1")), ownerViewID: a)
            tx.create(.viewports, data: .viewport(ViewportData(viewID: legend, center: Vec2(0.3, 0.3), detailNumber: "1")), ownerViewID: b)
        }
        #expect(s.model.sheet(containing: plan)?.id == s.sheet)
        #expect(Parameters.value(ParameterID("view.sheetNumber"), of: s.model[plan]!, s.model) == .text("A101"))
    }

    @Test func duplicateDetailNumberOnSheetIsRejected() throws {
        let s = try setup()
        var second: ElementID!
        try Fx.commit(&s.model) { tx in
            let l2 = s.ids.planViews[s.ids.levels[1]]!
            second = tx.create(.viewports, data: .viewport(ViewportData(viewID: l2, center: Vec2(0.2, 0.3), detailNumber: "2")), ownerViewID: s.sheet)
        }
        let tx = TransactionContext(model: s.model, name: "Renumber")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("viewport.detailNumber"), to: .text("1"), on: second, in: tx) }
        try Parameters.set(ParameterID("viewport.detailNumber"), to: .text("3"), on: second, in: tx)
    }

    @Test func scheduleViewportDrawsTheTable() throws {
        let s = try setup()
        let doors = s.model.schedules.first { $0.name == "Door Schedule" }!.id
        var vp: ElementID!
        try Fx.commit(&s.model) { tx in
            vp = tx.create(.viewports, data: .viewport(ViewportData(viewID: doors, center: Vec2(0.6, 0.5), detailNumber: "")), ownerViewID: s.sheet)
        }
        let b = SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!)
        let layout = try #require(b.layouts().first { $0.0.viewportID == vp }).0
        #expect(Fx.approx(layout.box.center, Vec2(0.6, 0.5), 1e-12))
        let table = ScheduleEngine.compute(s.model[doors]!, s.model)
        #expect(Fx.approx(layout.box.width, table.totalWidth, 1e-12))
        // ScheduleLayout draws a title band, one header row and the rows.
        let drawn = ScheduleLayout.titleHeight + Double(table.rows.count + 1) * ScheduleLayout.rowHeight
        #expect(Fx.approx(layout.box.height, drawn, 1e-12))
        let item = try #require(b.build().items.first { $0.elementID == vp })
        #expect(item.targetViewID == doors)
        #expect(item.primitives.contains { if case .text(let t) = $0 { return t.string == "DOOR SCHEDULE" } else { return false } })
    }

    @Test func sheetParametersValidateNumbers() throws {
        let s = try setup()
        let tx = TransactionContext(model: s.model, name: "Renumber")
        let other = tx.create(.sheets, name: "Other", data: .sheet(SheetData(number: "A102")))
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("sheet.number"), to: .text("A101"), on: other, in: tx) }
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("sheet.number"), to: .text("  "), on: other, in: tx) }
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("sheet.paper"), to: .text("B5"), on: other, in: tx) }
        try Parameters.set(ParameterID("sheet.paper"), to: .text("A3"), on: other, in: tx)
        #expect(tx.model[other]!.sheet!.paper == .a3)
    }

    // MARK: Revisions

    @Test func revisionsComeFromCloudsOnPlacedViewsAndExplicitAdds() throws {
        let s = try setup()
        let rev1 = s.model.revisions[0].id
        var rev2: ElementID!
        #expect(RevisionQueries.revisions(onSheet: s.model[s.sheet]!, s.model).isEmpty)
        #expect(SheetGraphicsBuilder(model: s.model, sheet: s.model[s.sheet]!).titleBlockValue("Current Revision") == "")
        try Fx.commit(&s.model) { tx in
            tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: .rectangle(Rect2(min: .zero, max: Vec2(2, 2))), revisionID: rev1)),
                      ownerViewID: s.ids.planViews[s.l1])
            rev2 = tx.create(.revisions, name: "Revision 2", data: .revision(RevisionData(sequence: 2, date: "2026-09-01", description: "Tender")))
        }
        let sheet = { s.model[s.sheet]! }
        #expect(RevisionQueries.revisions(onSheet: sheet(), s.model).map(\.id) == [rev1])
        #expect(Parameters.value(ParameterID("sheet.currentRevision"), of: sheet(), s.model) == .text("1"))
        try Fx.commit(&s.model) { tx in tx.update(s.sheet) { $0.sheet?.additionalRevisionIDs = [rev2] } }
        #expect(RevisionQueries.revisions(onSheet: sheet(), s.model).map(\.id) == [rev1, rev2])
        #expect(RevisionQueries.current(onSheet: sheet(), s.model)?.id == rev2)
        let b = SheetGraphicsBuilder(model: s.model, sheet: sheet())
        #expect(b.titleBlockValue("Current Revision") == "2")
        #expect(b.titleBlockValue("Current Revision Date") == "2026-09-01")
        let t = texts(b.build())
        #expect(t.contains("Issued for review") && t.contains("Tender"), "revision schedule in the title block")
        // A cloud on an unplaced view does not count.
        try Fx.commit(&s.model) { tx in
            tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: .rectangle(Rect2(min: .zero, max: Vec2(1, 1))), revisionID: rev2)),
                      ownerViewID: s.ids.planViews[s.ids.levels[2]])
            tx.update(s.sheet) { $0.sheet?.additionalRevisionIDs = [] }
        }
        #expect(RevisionQueries.revisions(onSheet: sheet(), s.model).map(\.id) == [rev1])
    }

    @Test func revisionLabelsByNumberingScheme() throws {
        var (m, _) = Fx.template()
        var alpha: [ElementID] = []
        try Fx.commit(&m) { tx in
            for i in 0..<26 {
                alpha.append(tx.create(.revisions, name: "R\(i)", data: .revision(RevisionData(sequence: 10 + i, date: "", description: "", numbering: .alphabetic))))
            }
            tx.create(.revisions, name: "N2", data: .revision(RevisionData(sequence: 50, date: "", description: "")))
        }
        let labels = alpha.map { RevisionQueries.label(m[$0]!, m) }
        #expect(Array(labels.prefix(9)) == ["A", "B", "C", "D", "E", "F", "G", "H", "J"], "I is skipped")
        #expect(labels[13] == "P", "O is skipped")
        #expect(labels[24] == "AA" && labels[25] == "AB")
        #expect(RevisionQueries.label(m.revisions.last!, m) == "2", "numeric revisions count separately")
    }

    @Test func issuedRevisionsAreLocked() throws {
        var (m, _) = Fx.template()
        let rev = m.revisions[0].id
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("revision.issued"), to: .bool(true), on: rev, in: tx) }
        let tx = TransactionContext(model: m, name: "Edit issued")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("revision.description"), to: .text("changed"), on: rev, in: tx) }
    }

    @Test(arguments: PaperSize.allCases)
    func paperSizesAreLandscape(_ p: PaperSize) {
        #expect(p.landscapeSize.x > p.landscapeSize.y)
    }
}
