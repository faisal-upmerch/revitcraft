import Foundation
import ArcusGeometry
import ArcusDomain

// STAIR: the Shaft tool's Pick Stair. Revit never cuts floors for stairs; a shaft through the floors above the stair
// does, and this adds the stair's outline (its runs and landings as one loop, as they show in this plan) to the shaft
// sketch with one click.
extension ShaftOpeningTool {
    func pickStair(_ i: ToolInput) {
        pickingStair = false
        let stair = hit(i, [.stairs]) ?? ctx.model.elements(.stairs).first { s in
            (MultistoryStairs.storeys(of: s, ctx.model) ?? [s]).contains { st in
                StairGeometry.layout(st, ctx.model)?.outline.contains { $0.contains(i.rawPoint) } ?? false
            }
        }
        guard let s = stair else { message("Pick a stair."); return }
        let storeys = MultistoryStairs.storeys(of: s, ctx.model) ?? [s]
        // The storey whose outline the click is in (any storey shares the plan outline).
        let st = storeys.first { StairGeometry.layout($0, ctx.model)?.outline.contains { $0.contains(i.rawPoint) } ?? false } ?? storeys[0]
        guard let outline = StairGeometry.layout(st, ctx.model)?.outline, !outline.isEmpty else { message("The stair has no outline."); return }
        for poly in outline { loops.append(poly.counterClockwise.edges.map { .line($0) }) }
        rebuildPreview()
        message("Added the stair's outline to the shaft sketch.")
    }
}
