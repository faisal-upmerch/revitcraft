import Foundation
import ArcusGeometry

// F12: Split & Place (RevitCraft rc-app dialogs/schedule_tools.rs `SchedTool::Split`).

/// Places a schedule on a sheet in segments (RevitCraft `SchedTool::Split`): side by side from the sheet's top left,
/// replacing the schedule's earlier viewports on that sheet.
public enum ScheduleSplit {
    public static func place(_ scheduleID: ElementID, onSheet sheetID: ElementID, segments: Int, in tx: TransactionContext) throws {
        let m = tx.model
        guard let s = m[scheduleID], s.schedule != nil, let sheet = m[sheetID]?.sheet else { throw TransactionError("Sheet or schedule not found.") }
        let table = ScheduleEngine.compute(s, m)
        let rows = table.rows.count
        guard rows >= 2 else { throw TransactionError("The schedule needs at least two rows to split.") }
        let n = max(1, min(segments, rows))
        let per = Int((Double(rows) / Double(n)).rounded(.up))
        for vp in m.owned(byView: sheetID) where vp.viewport?.viewID == scheduleID { tx.delete(vp.id) }
        let paper = sheet.paper.landscapeSize
        var x = 0.03
        let top = paper.y - 0.03
        for k in 0..<n {
            let first = k * per, last = min(rows, (k + 1) * per) - 1
            guard first < rows else { break }
            let range = ScheduleRowRange(first: first, last: last)
            let w = max(table.totalWidth, 0.04), h = ScheduleLayout.height(table, rows: range)
            let id = try SheetPlacement.place(scheduleID, onSheet: sheetID, at: Vec2(x + w / 2, top - h / 2), in: tx)
            tx.update(id) { $0.viewport?.scheduleRows = range; $0.viewport?.showTitle = false }
            x += w + 0.01
        }
    }
}
