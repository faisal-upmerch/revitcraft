import SwiftUI
import ArcusDomain
import ArcusApplication

extension RibbonContent {
    /// Contextual items for stairs, shape-editable floors and roofs, wall attachment and geometry joins.
    static func wp4SelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        var title: String?
        var items: [RibbonItem] = []
        if sel.count == 1, sel[0].stair != nil { title = "Stair"; items.append(.large(.editStair)) }
        if sel.count == 1, ShapeEditing.canEdit(sel[0]) {
            title = "Shape Editing"
            items += [.large(.modifySubElements), .small(.addShapePoint), .small(.resetShape)]
        }
        if sel.count == 1, sel[0].roof != nil || sel[0].category == .floors { items.append(.small(.attachWallsToHost)) }
        let joinable = sel.filter { SolidJoins.priority($0) != nil }
        if joinable.count >= 2 { items.append(.small(.joinSolids)) }
        if joinable.contains(where: { !SolidJoins.partners(of: $0.id, m).isEmpty }) { items.append(.small(.unjoinSolids)) }
        return (title, items)
    }
}
