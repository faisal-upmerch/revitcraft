import SwiftUI
import ArcusDomain
import ArcusApplication

// BL-SITE (ARCUS-043): the Modify | Walls contextual panels, and a compact form of the shared Modify panels so the
// category panels at the right end stay on screen at 1440 pt wide (estimated with the ribbon's own metrics: the full
// panels plus the wall panels need ~1465 pt, more than the ~1190 pt the content column has beside a 250 pt sidebar;
// the compact form needs ~1130 pt).

extension RibbonContent {
    /// Mode (Edit / Reset Profile), Modify Wall (Attach / Detach Top/Base, Flip Wall) and Wall Joins (Allow /
    /// Disallow) for a selection containing walls. Flip Wall stays: the on-canvas flip arrows flip one wall, but Space
    /// does not flip selected walls in this build, so the ribbon keeps the only multi-wall flip.
    static func wallPanels(_ state: DocumentState) -> [RibbonPanel] {
        let sel = state.session.selection.ids.compactMap { state.model[$0] }
        guard sel.contains(where: { $0.wall != nil }) else { return [] }
        return [RibbonPanel(title: "Mode", items: [.small(.editProfile), .small(.resetProfile)], tint: build),
                RibbonPanel(title: "Modify Wall", items: [.small(.attachTop), .small(.detachTop), .small(.flipWall)], tint: build),
                RibbonPanel(title: "Wall Joins", items: [.small(.joinGeometry), .small(.unjoinGeometry)], tint: build)]
    }

    /// The shared Modify panels with small buttons (and the Create panel's large one) shown as icons — titles stay in
    /// the tooltips — and Measure folded into View, used while category panels follow them.
    static var compactModifyPanels: [RibbonPanel] {
        var out: [RibbonPanel] = []
        var measure: [RibbonItem] = []
        func icon(_ i: RibbonItem) -> RibbonItem { var c = i; c.size = .icon; c.breakBefore = false; return c }
        for p in modifyPanels {
            if p.title == "Measure" { measure = p.items.map(icon); continue }
            out.append(RibbonPanel(title: p.title, items: p.items.map { $0.size == .small || p.title == "Create" ? icon($0) : $0 }, tint: p.tint))
        }
        if let i = out.firstIndex(where: { $0.title == "View" }) {
            out[i] = RibbonPanel(title: out[i].title, items: out[i].items + measure, tint: out[i].tint)
        } else if !measure.isEmpty {
            out.append(RibbonPanel(title: "Measure", items: measure, tint: modify))
        }
        return out
    }
}
