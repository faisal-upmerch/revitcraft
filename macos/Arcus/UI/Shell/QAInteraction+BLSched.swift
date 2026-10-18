import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput

// BL-SCHED: interaction QA for editable schedules, the schedule ribbon tab and image export (hooked with one line).
extension QAHarness {
    static func scheduleEditingInteraction(_ s: DocumentState, _ d: CanvasDriver) async {
        await step("Schedule: type drop-down, read-only cue, fields, header groups, Highlight in Model") {
            guard let sched = s.model.schedules.first(where: { $0.name == "Door Schedule" }) else { throw QAError("no door schedule") }
            s.open(sched.id)
            var table: ScheduleTableView?
            for _ in 0..<100 { table = s.canvases[sched.id] as? ScheduleTableView; if table?.tableModel?.rows.isEmpty == false { break }; await pause(30) }
            guard let tv = table else { throw QAError("schedule table did not load") }
            tv.recomputeNow()
            try check(RibbonContent.contextualTitle(s) == "Modify Schedule/Quantities", "contextual tab is \(RibbonContent.contextualTitle(s) ?? "none")")
            guard let tm = tv.tableModel, let row = tm.rows.firstIndex(where: { $0.kind == .data }),
                  let typeCol = tm.columns.firstIndex(where: { $0.heading == "Type" }) else { throw QAError("no data row / Type column") }
            let door = tm.rows[row].elementIDs[0]
            let oldType = s.model[door]?.typeID
            tv.setActive(row: row, column: typeCol)
            guard case .options(let opts)? = tv.activeTarget?.editor, let other = opts.first(where: { $0.value.refValue != oldType }) else { throw QAError("Type cell offers no other type") }
            try check(s.session.editScheduleCell(sched.id, table: tm, row: row, column: typeCol, value: other.value), "type swap refused")
            try check(s.model[door]?.typeID == other.value.refValue, "door type did not change")
            s.session.undoManager.undo()
            try check(s.model[door]?.typeID == oldType, "undo did not restore the type")
            // Read-only: From Room.
            tv.recomputeNow()
            if let c = tv.tableModel?.columns.firstIndex(where: { $0.heading == "From Room" }) {
                tv.setActive(row: row, column: c)
                try check(tv.activeTarget?.editor.isEditable == false, "From Room should be read-only")
                tv.refuseIfReadOnly()
            }
            d.saveCanvas(tv, "schedule-read-only-cue")
            // Fields: add Level, group two headers, hide and unhide.
            s.session.editSchedule(sched.id, "QA Add Level") { $0.fields.append(ScheduleTemplates.field("level", "Level")) }
            tv.recomputeNow()
            try check(tv.tableModel?.columns.contains { $0.heading == "Level" } == true, "Level column missing")
            let ids = s.model[sched.id]!.schedule!.fields.prefix(2).map(\.id)
            s.session.editSchedule(sched.id, "QA Group") { $0.groupHeaders(Array(ids), title: "Identity") }
            tv.recomputeNow()
            try check(tv.tableModel?.headerSpans.first?.title == "Identity", "header group missing")
            d.saveCanvas(tv, "schedule-header-group")
            s.session.undoManager.undo(); s.session.undoManager.undo()
            tv.recomputeNow()
            try check(tv.tableModel?.columns.contains { $0.heading == "Level" } == false, "undo left the Level column")
            // Highlight in Model.
            tv.setActive(row: row, column: 0)
            CommandRouter(state: s).run(.highlightInModel)
            await pause(100)
            try check(s.session.selection.ids == [door], "Highlight in Model selected \(s.session.selection.ids)")
            await d.verify("highlighted door in plan")
            // Image export of the plan renders locally.
            if let v = s.activeView, v.view != nil, let g = s.graphics.graphics(v.id) {
                try check(RasterExporter.render(g, pixelWidth: 400).flatMap { RasterExporter.encode($0, as: .png) } != nil, "plan image export failed")
            }
            d.escape()
            return "type swapped and undone; read-only cue; Level field + header group; Highlight in Model"
        }
    }
}
