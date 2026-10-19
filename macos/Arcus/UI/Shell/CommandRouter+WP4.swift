import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Floors, roofs, stairs and ramps: availability and actions of the WP4 commands.
extension CommandRouter {
    func wp4DisabledReason(_ id: CommandID) -> String? {
        let sel = selection.compactMap { model[$0] }
        let vertical = viewKind?.isVerticalCut ?? false
        switch id {
        case .ramp:
            return isPlan ? nil : "Open a plan view to draw ramps."
        case .roofExtrusion:
            return vertical ? nil : "Open an elevation or section to sketch the roof profile."
        case .editStair:
            return sel.count == 1 && sel[0].stair != nil && isPlan ? nil : "Select one stair in a plan view."
        case .modifySubElements, .addShapePoint:
            return sel.count == 1 && ShapeEditing.canEdit(sel[0]) && isPlan ? nil : "Select one floor or flat roof in a plan view."
        case .resetShape:
            return sel.contains { !ShapeEditing.points(of: $0).isEmpty } ? nil : "Select a shape-edited floor or roof."
        case .attachWallsToHost:
            return sel.count == 1 && (sel[0].roof != nil || sel[0].category == .floors) ? nil : "Select one roof or floor."
        case .joinSolids:
            return sel.filter { SolidJoins.priority($0) != nil }.count >= 2 ? nil : "Select two or more overlapping walls, floors, roofs or ceilings."
        case .unjoinSolids:
            return sel.contains { !SolidJoins.partners(of: $0.id, model).isEmpty } ? nil : "Select joined elements."
        case .editBoundary:
            // An extruded roof's profile is edited in a view that looks straight at its work plane.
            guard sel.count == 1, let x = sel[0].roof?.extrusion else { return nil }
            guard vertical, let r = state.activeView?.view?.rightVector, abs(r.cross(x.direction)) < 1e-3 else {
                return "Open an elevation or section that looks straight at the roof's work plane to edit its profile."
            }
            return nil
        default:
            return nil
        }
    }

    func performWP4(_ id: CommandID) {
        let sel = selection
        switch id {
        case .ramp:
            if let c = ctx() { state.setTool(RampTool(ctx: c)) }
        case .roofExtrusion:
            guard let c = ctx() else { return }
            let t = SketchTool(ctx: c, target: .roofExtrusion, commandID: .roofExtrusion)
            t.drawMode = .line
            state.setTool(t)
        case .editStair:
            if let c = ctx(), let s = sel.first, let t = StairTool(ctx: c, editing: s) { state.setTool(t) } // STAIR: Edit Stairs
        case .modifySubElements, .addShapePoint:
            guard let c = ctx(), let e = sel.first,
                  let t = ShapeEditTool(ctx: c, elementID: e, mode: id == .addShapePoint ? .addPoint : .modify) else { return }
            state.setTool(t)
        case .resetShape:
            session.perform("Reset Shape") { tx in for e in sel { tx.update(e) { ShapeEditing.setPoints([], on: &$0) } } }
        case .attachWallsToHost:
            guard let h = sel.first, let host = model[h] else { return }
            let walls = WallAttachment.candidates(for: host, model)
            guard !walls.isEmpty else { state.show("No unattached walls below reach this \(host.category.singularName.lowercased()).") ; return }
            session.perform("Attach Walls") { tx in WallAttachment.attach(walls, to: h, in: tx) }
            if session.lastError == nil { state.show("\(walls.count) wall\(walls.count == 1 ? "" : "s") attached to the \(host.category.singularName.lowercased()).") }
        case .joinSolids:
            let pairs = SolidJoins.joinablePairs(sel, model)
            guard !pairs.isEmpty else { state.show("The selected elements don't overlap, or are already joined."); return }
            session.perform("Join Geometry") { tx in SolidJoins.join(sel, in: tx) }
            if session.lastError == nil { state.show("\(pairs.count) join\(pairs.count == 1 ? "" : "s") created. The overlap is cut from the lower-priority element.") }
        case .unjoinSolids:
            var n = 0
            session.perform("Unjoin Geometry") { tx in n = SolidJoins.unjoin(sel, in: tx) }
            if n == 0 { state.show("The selected elements aren't joined to each other.") }
        default:
            break
        }
    }
}
