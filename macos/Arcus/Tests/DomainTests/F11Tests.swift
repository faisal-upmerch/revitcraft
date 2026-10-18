import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F11–F12: Manage (global parameters, coordinates and position, design options, saved selections, starting view),
/// schedules (header rows, styles, combined parameters, Split & Place) and keynotes.
@Suite("F11 Manage, schedules and keynotes")
struct F11Tests {
    func unconnectedWall(_ tx: TransactionContext, _ ids: ProjectTemplates.Ids, _ a: Vec2, _ b: Vec2) -> ElementID {
        Fx.wall(tx, ids, a, b, top: nil) { $0.unconnectedHeight = 3 }
    }

    // MARK: Global parameters

    @Test func globalParametersDriveAssociatedParametersThroughFormulas() throws {
        var (m, ids) = Fx.template()
        var w = ElementID(0)
        try Fx.commit(&m) { tx in w = unconnectedWall(tx, ids, Vec2(0, 0), Vec2(5, 0)) }
        let width = GlobalParameter(name: "Width", type: .length, value: .double(5))
        var height = GlobalParameter(name: "Height", type: .length, formula: "Width / 2")
        height.associations = [GlobalParameterAssociation(elementID: w, parameterID: ParameterID("wall.unconnectedHeight"))]
        try Fx.commit(&m) { tx in try GlobalParameters.set([width, height], in: tx) }
        #expect(Fx.approx(GlobalParameters.named("Height", m)!.value.doubleValue!, 2.5))
        #expect(Fx.approx(m[w]!.wall!.unconnectedHeight, 2.5))
        // The associated parameter is read-only in Properties and schedules.
        let entry = Parameters.instanceEntries(m[w]!, m).first { $0.id == ParameterID("wall.unconnectedHeight") }!
        #expect(entry.isReadOnly && entry.readOnlyReason?.contains("Height") == true)
        #expect(!Parameters.isEditable(ParameterID("wall.unconnectedHeight"), on: m[w]!, m))
        // Changing the driving global updates the computed one and the wall.
        var list = GlobalParameters.all(m)
        list[0].value = .double(6)
        try Fx.commit(&m) { tx in try GlobalParameters.set(list, in: tx) }
        #expect(Fx.approx(m[w]!.wall!.unconnectedHeight, 3))
        // Freeing the parameter leaves its value and makes it editable again.
        try Fx.commit(&m) { tx in try GlobalParameters.associate(w, ParameterID("wall.unconnectedHeight"), with: nil, in: tx) }
        #expect(Parameters.isEditable(ParameterID("wall.unconnectedHeight"), on: m[w]!, m))
    }

    @Test func globalParameterFormulaErrorsAreRefused() throws {
        let units = UnitsSettings.metric
        let a = GlobalParameter(name: "A", type: .length, formula: "B + 1")
        let b = GlobalParameter(name: "B", type: .length, formula: "A + 1")
        #expect(throws: ParameterError.self) { _ = try GlobalParameters.evaluate([a, b], units: units) }
        let selfRef = GlobalParameter(name: "C", type: .length, formula: "C * 2")
        #expect(throws: ParameterError.self) { _ = try GlobalParameters.evaluate([selfRef], units: units) }
        let unknown = GlobalParameter(name: "D", type: .length, formula: "Nope + 1")
        #expect(throws: ParameterError.self) { _ = try GlobalParameters.evaluate([unknown], units: units) }
        var (m, _) = Fx.template()
        let dup = [GlobalParameter(name: "X", type: .number), GlobalParameter(name: "X", type: .number)]
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try GlobalParameters.set(dup, in: tx) } }
    }

    @Test func aLabelledDimensionHoldsTheGlobalDistance() throws {
        var (m, ids) = Fx.template()
        var a = ElementID(0), b = ElementID(0), d = ElementID(0)
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, Vec2(0, 0), Vec2(0, 6))
            b = Fx.wall(tx, ids, Vec2(4, 0), Vec2(4, 6))
            d = tx.create(.dimensions, data: .dimension(DimensionData(kind: .linear, references: [GeometryReference(a, .location), GeometryReference(b, .location)],
                                                                      linePoint: Vec2(2, -1), direction: 0)), ownerViewID: plan)
        }
        let g = GlobalParameter(name: "Bay", type: .length, value: .double(5))
        try Fx.commit(&m) { tx in try GlobalParameters.set([g], in: tx) }
        let gid = GlobalParameters.named("Bay", m)!.id
        try Fx.commit(&m) { tx in try GlobalParameters.associate(d, GlobalParameters.dimensionLabel, with: gid, in: tx) }
        let xa = m[a]!.wall!.location.asSegment!.start.x, xb = m[b]!.wall!.location.asSegment!.start.x
        #expect(Fx.approx(abs(xb - xa), 5, 1e-4))
        // Editing the global moves the dimensioned wall again.
        var list = GlobalParameters.all(m)
        list[0].value = .double(3)
        try Fx.commit(&m) { tx in try GlobalParameters.set(list, in: tx) }
        #expect(Fx.approx(abs(m[b]!.wall!.location.asSegment!.start.x - m[a]!.wall!.location.asSegment!.start.x), 3, 1e-4))
    }

    @Test func schedulesCalculateWithGlobalParameters() throws {
        var (m, _) = Fx.template()
        try Fx.commit(&m) { tx in try GlobalParameters.set([GlobalParameter(name: "Allowance", type: .length, value: .double(0.05))], in: tx) }
        let s = m.schedules.first { $0.name == "Door Schedule" }!
        var def = s.schedule!
        def.fields.append(ScheduleField(source: .formula("Allowance * 2", .length), heading: "Twice"))
        try Fx.commit(&m) { tx in tx.update(s.id) { $0.schedule = def } }
        #expect(ScheduleEngine.formulaValue(def.fields.last!, def, [:], m)?.doubleValue.map { Fx.approx($0, 0.1) } == true)
    }

    // MARK: Coordinates and position

    @Test func sharedCoordinatesSpecifyAndRelocate() throws {
        var info = ProjectInfoData()
        let p = Vec3(10, 5, 0)
        SharedCoordinates.specify(at: p, reads: SharedPoint(northSouth: 1000, eastWest: 2000, elevation: 50), trueNorth: Angle.radians(30), &info)
        let s = SharedCoordinates.shared(p, info)
        #expect(Fx.approx(s.northSouth, 1000) && Fx.approx(s.eastWest, 2000) && Fx.approx(s.elevation, 50))
        #expect(Fx.approx(info.trueNorthAngle, Angle.radians(30)))
        // A point 1 m along true north reads 1 m more north/south.
        let north = Vec2(-sin(info.trueNorthAngle), cos(info.trueNorthAngle))
        #expect(Fx.approx(SharedCoordinates.shared(Vec3(p.xy + north, z: 0), info).northSouth, 1001))
        // Relocate: the point now reads what the point 3 m east of it read.
        let east = Vec2(cos(info.trueNorthAngle), sin(info.trueNorthAngle))
        let before = SharedCoordinates.shared(Vec3(p.xy + east * 3, z: 0), info)
        SharedCoordinates.relocate(by: east * 3, &info)
        #expect(Fx.approx(SharedCoordinates.shared(p, info).eastWest, before.eastWest))
    }

    @Test func rotateAndMirrorProjectMoveModelViewsAndNorth() throws {
        var (m, ids) = Fx.template()
        var w = ElementID(0)
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, Vec2(2, 0), Vec2(6, 0))
            tx.update(plan) { $0.view?.cropRegion = Rect2(min: Vec2(0, -1), max: Vec2(8, 1)) }
        }
        try Fx.commit(&m) { tx in ProjectPosition.rotate(degrees: 90, in: tx) }
        let seg = m[w]!.wall!.location.asSegment!
        #expect(Fx.approx(seg.start, Vec2(0, 2), 1e-9) && Fx.approx(seg.end, Vec2(0, 6), 1e-9))
        #expect(Fx.approx(m.projectInfo.trueNorthAngle, Angle.normalize(-Double.pi / 2), 1e-9))
        let crop = m[plan]!.view!.cropRegion!
        #expect(Fx.approx(crop.min, Vec2(-1, 0), 1e-9) && Fx.approx(crop.max, Vec2(1, 8), 1e-9))
        try Fx.commit(&m) { tx in ProjectPosition.mirror(northSouth: false, in: tx) }
        let s2 = m[w]!.wall!.location.asSegment!
        #expect(Fx.approx(s2.start, Vec2(0, -2), 1e-9) && Fx.approx(s2.end, Vec2(0, -6), 1e-9))
    }

    // MARK: Design options

    @MainActor @Test func addToSetMovesAndCopiesAndNewElementsJoinTheEditedOption() throws {
        var (m, ids) = Fx.template()
        var w = ElementID(0), primary = ElementID(0), second = ElementID(0)
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, Vec2(0, 0), Vec2(5, 0))
            primary = tx.create(.designOptions, name: "A", data: .designOption(DesignOptionData(setName: "Entry", isPrimary: true)))
            second = tx.create(.designOptions, name: "B", data: .designOption(DesignOptionData(setName: "Entry", isPrimary: false)))
        }
        var moved: [ElementID] = []
        try Fx.commit(&m) { tx in moved = try DesignOptionEditing.addToSet([w], options: [primary, second], in: tx) }
        #expect(m[w]?.designOptionID == primary)
        #expect(moved.count == 2 && m.elements(.walls).filter { $0.designOptionID == second }.count == 1)
        #expect(DesignOptionEditing.pickTarget(w, m) == primary)
        // Main model only.
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try DesignOptionEditing.addToSet([w], options: [second], in: tx) } }

        let session = DocumentSession(model: m)
        session.activeDesignOptionID = second
        session.perform("Wall") { tx in _ = Fx.wall(tx, ids, Vec2(0, 3), Vec2(5, 3)) }
        let fresh = session.model.elements(.walls).max { $0.id < $1.id }!
        #expect(fresh.designOptionID == second)
        session.activeDesignOptionID = nil
        session.perform("Wall") { tx in _ = Fx.wall(tx, ids, Vec2(0, 6), Vec2(5, 6)) }
        #expect(session.model.elements(.walls).max { $0.id < $1.id }!.designOptionID == nil)
        // While an option is edited, elements of the set's other options can't be picked.
        session.selection.editingOption = second
        #expect(!session.selection.allows(session.model[w]!) && session.selection.allows(fresh))
    }

    // MARK: Saved selections and starting view

    @Test func savedSelectionsRoundTripAndForgetDeletedElements() throws {
        var (m, ids) = Fx.template()
        var a = ElementID(0), b = ElementID(0)
        try Fx.commit(&m) { tx in a = Fx.wall(tx, ids, Vec2(0, 0), Vec2(5, 0)); b = Fx.wall(tx, ids, Vec2(0, 2), Vec2(5, 2)) }
        try Fx.commit(&m) { tx in try SavedSelections.save([a, b], name: "Façade", in: tx) }
        let set = m.manageData.selectionSets.first!
        #expect(set.name == "Façade" && SavedSelections.elements(of: set.id, m) == [a, b])
        try Fx.commit(&m) { tx in tx.delete(b) }
        #expect(SavedSelections.elements(of: set.id, m) == [a])
        try Fx.commit(&m) { tx in try SavedSelections.rename(set.id, to: "North", in: tx) }
        #expect(m.manageData.selectionSets.first?.name == "North")
        #expect(SavedSelections.nextName(m) == "Selection 2")
        try Fx.commit(&m) { tx in SavedSelections.delete(set.id, in: tx) }
        #expect(m.manageData.selectionSets.isEmpty && m.projectInfo.f11 == nil)
    }

    @Test func startingViewIsStoredAndOlderFilesDecode() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[1]]!
        try Fx.commit(&m) { tx in StartingView.set(plan, in: tx) }
        #expect(StartingView.view(m)?.id == plan)
        try Fx.commit(&m) { tx in tx.delete(plan) }
        #expect(StartingView.view(m) == nil)
        // Project information without F11 data decodes.
        let json = try JSONEncoder().encode(ProjectInfoData())
        #expect(!String(decoding: json, as: UTF8.self).contains("f11"))
        #expect(try JSONDecoder().decode(ProjectInfoData.self, from: json).f11 == nil)
    }

    // MARK: Keynotes

    @Test func keynoteTablesLegendAndDisplay() throws {
        #expect(throws: TransactionError.self) { _ = try Keynoting.parse("no tabs here") }
        let table = try Keynoting.parse("# test\nA\tGeneral\t\nA.1\tPaint finish\tA\n")
        #expect(table.count == 2 && table[1].parent == "A")
        var (m, ids) = Fx.template()
        var w = ElementID(0)
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, Vec2(0, 0), Vec2(5, 0))
            var t = TagData(taggedID: w, head: Vec2(2, 1))
            t.kind = .keynoteUser; t.keynote = "A.1"
            tx.create(.tags, data: .tag(t), ownerViewID: plan)
            tx.updateManageData { $0.keynoteTable = table; $0.keynoteFile = "test.txt"; $0.keynoteDisplay = .keyAndText }
        }
        #expect(Keynoting.text(for: "A.1", m) == "Paint finish")
        #expect(Keynoting.pickable(m).map(\.key) == ["A.1"])
        let tag = m.elements(.tags).first!
        #expect(AnnotationRenderer.keynoteLabel(tag.tag!, .keynoteUser, target: m[w], model: m) == "A.1 Paint finish")
        var legend = ElementID(0)
        try Fx.commit(&m) { tx in legend = tx.create(.schedules, name: "Keynote Legend", data: .schedule(KeynoteLegend.definition())) }
        let t = ScheduleEngine.compute(m[legend]!, m)
        #expect(t.rows.count == 1 && t.rows[0].cells.map(\.text) == ["A.1", "Paint finish"] && t.rows[0].elementIDs == [tag.id])
    }

    // MARK: Schedule tools

    func doorSchedule(_ m: BIMModel) -> Element { m.schedules.first { $0.name == "Door Schedule" }! }

    @Test func headerRowsMergeStyleAndLayOutOnSheets() throws {
        var (m, _) = Fx.template()
        let s = doorSchedule(m)
        let plain = ScheduleLayout.height(ScheduleEngine.compute(s, m))
        var def = s.schedule!
        ScheduleFormattingEdits.insertHeaderRow(at: 0, &def)
        ScheduleFormattingEdits.insertHeaderRow(at: 0, &def)
        ScheduleFormattingEdits.setText("Project Harbour", row: 0, column: 0, &def)
        ScheduleFormattingEdits.setText("Second", row: 0, column: 1, &def)
        ScheduleFormattingEdits.mergeOrUnmerge(row: 0, columns: [0, 1, 2], &def)
        #expect(def.formatting.headerRows[0].merges == [ScheduleMerge(first: 0, last: 2)])
        #expect(def.formatting.headerRows[0].cells[0] == "Project Harbour" && def.formatting.headerRows[0].cells[1].isEmpty)
        ScheduleFormattingEdits.style([.headerRow(0, 0)], &def) { $0.shading = RGBColor(0.9, 0.9, 0.5); $0.font = ScheduleFont(size: 0.004, bold: true) }
        ScheduleFormattingEdits.style([.body(def.fields[0].id)], &def) { $0.horizontal = .right; $0.border = .wide }
        #expect(def.fields[0].alignment == .right && def.formatting.style(.body(def.fields[0].id)).horizontal == nil)
        try Fx.commit(&m) { tx in tx.update(s.id) { $0.schedule = def } }
        let t = ScheduleEngine.compute(m[s.id]!, m)
        #expect(Fx.approx(ScheduleLayout.height(t), plain + 2 * ScheduleLayout.rowHeight, 1e-12))
        let g = ScheduleLayout.grid(t)
        let first = g.rows.first { $0.kind == .headerRow(0) }!
        #expect(first.cells.first?.span == 3 && first.cells.first?.shading != nil && first.cells.first?.bold == true)
        let prims = ScheduleLayout.primitives(t, topLeft: Vec2(0, 0.5))
        let texts = prims.compactMap { if case .text(let x) = $0 { return x } else { return nil } }
        #expect(texts.contains { $0.string == "Project Harbour" && Fx.approx($0.height, 0.004) })
        #expect(texts.contains { $0.string == "DOOR SCHEDULE" })
        #expect(prims.contains { if case .polyline(_, _, let st) = $0 { return st.weight == ScheduleBorder.wide.lineWeight } else { return false } })
        // Deleting a header row drops its styles and moves the next row's up.
        ScheduleFormattingEdits.deleteHeaderRows([0], &def)
        #expect(def.formatting.headerRows.count == 1 && def.formatting.styles["x0:0"] == nil)
        ScheduleFormattingEdits.reset([.body(def.fields[0].id)], &def)
        #expect(def.formatting.styles.isEmpty)
    }

    @Test func combinedParametersJoinValues() throws {
        var (m, ids) = Fx.template()
        try Fx.commit(&m) { tx in
            let w = Fx.wall(tx, ids, Vec2(0, 0), Vec2(5, 0))
            Fx.door(tx, ids, host: w, at: Vec2(2, 0), mark: "D7")
        }
        let s = doorSchedule(m)
        var def = s.schedule!
        let parts = [ScheduleCombinedPart(parameterID: ParameterID("mark"), name: "Mark", prefix: "[", suffix: "]", separator: " – "),
                     ScheduleCombinedPart(parameterID: ParameterID("level"), name: "Level")]
        let fid = ScheduleFormattingEdits.combine(parts, heading: "Mark and Level", &def)
        try Fx.commit(&m) { tx in tx.update(s.id) { $0.schedule = def } }
        let t = ScheduleEngine.compute(m[s.id]!, m)
        let col = t.columns.firstIndex { $0.id == fid }!
        let text = t.rows.first { $0.kind == .data && $0.cells.contains { $0.text == "D7" } }!.cells[col].text
        #expect(text.hasPrefix("[D7] – "))
        #expect(!ScheduleEditing.target(t, row: t.rows.firstIndex { $0.kind == .data }!, column: col, schedule: m[s.id]!, model: m).editor.isEditable)
    }

    @Test func splitAndPlacePutsSegmentsSideBySide() throws {
        var (m, ids) = Fx.template()
        try Fx.commit(&m) { tx in
            let w = Fx.wall(tx, ids, Vec2(0, 0), Vec2(20, 0))
            for i in 0..<6 { Fx.door(tx, ids, host: w, at: Vec2(1.5 + Double(i) * 3, 0), mark: "D\(i)") }
        }
        let s = doorSchedule(m), sheet = m.sheets.first!.id
        let rows = ScheduleEngine.compute(s, m).rows.count
        try Fx.commit(&m) { tx in try ScheduleSplit.place(s.id, onSheet: sheet, segments: 3, in: tx) }
        let vps = m.owned(byView: sheet).filter { $0.viewport?.viewID == s.id }.sorted { $0.viewport!.center.x < $1.viewport!.center.x }
        #expect(vps.count == 3)
        let ranges = vps.compactMap { $0.viewport?.scheduleRows }
        #expect(ranges.first?.first == 0 && ranges.last?.last == rows - 1)
        // Later segments repeat the headings but not the title.
        let t = ScheduleEngine.compute(s, m)
        let g1 = ScheduleLayout.grid(t, rows: ranges[0]), g2 = ScheduleLayout.grid(t, rows: ranges[1])
        #expect(g1.rows.contains { $0.kind == .title } && !g2.rows.contains { $0.kind == .title } && g2.rows.contains { $0.kind == .headings })
        let sheetG = SheetGraphicsBuilder(model: m, sheet: m[sheet]!).build()
        #expect(sheetG.items.filter { $0.category == .viewports && $0.targetViewID == s.id }.count >= 3)
    }
}
