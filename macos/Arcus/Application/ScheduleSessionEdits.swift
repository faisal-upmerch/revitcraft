import Foundation
import ArcusDomain

// BL-SCHED: schedule cell edits and schedule definition edits as single undo steps.

extension DocumentSession {
    /// Writes typed text into a schedule cell: numbers with units, option titles for drop-down cells. Every element of
    /// the row (grouped rows have several) changes in one transaction, so one Undo reverts the edit. Returns false and
    /// sets `lastError` when the cell is read-only or the text doesn't parse.
    @discardableResult
    public func editScheduleCell(_ scheduleID: ElementID, table: ScheduleTable, row: Int, column: Int, text: String) -> Bool {
        guard let s = model[scheduleID] else { return false }
        let target = ScheduleEditing.target(table, row: row, column: column, schedule: s, model: model)
        let m = model
        return perform("Change \(target.heading)") { tx in
            let v = try ScheduleEditing.parse(text, for: target, model: m)
            try ScheduleEditing.apply(v, to: target, in: tx)
        } != nil || lastError == nil
    }

    /// Writes a value (a drop-down choice) into a schedule cell as one undo step.
    @discardableResult
    public func editScheduleCell(_ scheduleID: ElementID, table: ScheduleTable, row: Int, column: Int, value: ParamValue) -> Bool {
        guard let s = model[scheduleID] else { return false }
        let target = ScheduleEditing.target(table, row: row, column: column, schedule: s, model: model)
        return perform("Change \(target.heading)") { tx in try ScheduleEditing.apply(value, to: target, in: tx) } != nil || lastError == nil
    }

    /// Changes a schedule's definition (fields, filters, sorting, formatting, appearance) as one undo step.
    @discardableResult
    public func editSchedule(_ scheduleID: ElementID, _ name: String, _ change: (inout ScheduleDefinition) -> Void) -> Bool {
        guard var def = model[scheduleID]?.schedule else { return false }
        change(&def)
        let d = def
        return perform(name) { tx in tx.update(scheduleID) { $0.schedule = d } } != nil
    }
}
