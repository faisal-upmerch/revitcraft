import Foundation
import ArcusGeometry
import ArcusDomain

// F810: Duplicate View on a sheet (Project Browser ▸ Duplicate Sheet, View ▸ Duplicate View with a sheet open), as
// RevitCraft's `duplicate_view` does it for sheets.

public enum SheetDuplication {
    /// The next free sheet number after `number`: its trailing digits counted up ("A101" → "A102"), 100 when it has none.
    public static func nextNumber(after number: String, in m: BIMModel) -> String {
        let taken = Set(m.sheets.compactMap { $0.sheet?.number })
        let digits = number.reversed().prefix { $0.isASCII && $0.isNumber }
        let base = String(number.dropLast(digits.count))
        let start = Int(String(digits.reversed())) ?? 100
        var n = start + 1
        while taken.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    /// "<name> Copy", then "<name> Copy 2", … unique among sheet names.
    public static func copyName(_ name: String, in m: BIMModel) -> String {
        let names = Set(m.sheets.map(\.name))
        var n = "\(name) Copy", k = 2
        while names.contains(n) { n = "\(name) Copy \(k)"; k += 1 }
        return n
    }

    /// Duplicates a sheet: a new number, the same title block, paper and title block fields, no viewports (a view sits on
    /// one sheet only) and no extra revisions. With detailing, the sheet's own annotation (text, lines, symbols…) is
    /// copied too.
    @discardableResult
    public static func duplicate(_ sheetID: ElementID, withDetailing: Bool, in tx: TransactionContext) throws -> ElementID {
        guard let e = tx.model[sheetID], var sd = e.sheet else { throw TransactionError("Choose a sheet to duplicate.") }
        sd.number = nextNumber(after: sd.number, in: tx.model)
        sd.additionalRevisionIDs = []
        let params = e.params
        let new = tx.create(.sheets, name: copyName(e.name, in: tx.model), data: .sheet(sd)) { ne in ne.params = params }
        if withDetailing {
            let owned = tx.model.owned(byView: sheetID).filter { $0.viewport == nil && $0.category != .viewports }.map(\.id)
            ElementOperations.copy(owned, by: .identity, in: tx, viewID: sheetID, targetView: new)
        }
        return new
    }
}
