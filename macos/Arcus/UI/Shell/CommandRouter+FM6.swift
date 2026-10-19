import AppKit
import ArcusDomain
import ArcusApplication

// FM6: routing for Furniture joints (Docs/FurnitureMode.md §3 "Joints"). Joint runs in plans, elevations and sections
// square to the piece, and in 3D; Joint Rules opens its dialog; Allow/Disallow Join act on the selected parts' ends.

extension CommandRouter {
    static let fm6IDs: Set<CommandID> = [.furnitureJoint, .furnitureJointRules, .furnitureAllowJoin, .furnitureDisallowJoin]

    var fm6SelectedParts: [ElementID] {
        selection.compactMap { model[$0] }.filter { $0.category.isFurniturePart && $0.furnitureEdgeProfile == nil && $0.furnitureForm == nil }.map(\.id)
    }

    var fm6In3D: Bool { state.activeViewID.flatMap { model[$0]?.view?.kind } == .threeD }

    /// Why one of this batch's commands can't run now, or nil.
    func fm6DisabledReason(_ id: CommandID) -> String? {
        guard Self.fm6IDs.contains(id) else { return nil }
        guard state.mode == .furniture else { return "Only in Furniture documents." }
        switch id {
        case .furnitureJoint:
            return fm6In3D || FurnitureSketchMap.of(model[state.editingViewID]?.view) != nil ? nil : "Open a plan, an elevation or section square to the piece, or a 3D view."
        case .furnitureAllowJoin:
            return fm6SelectedParts.contains { FurnitureJointOperations.hasDisallowedEnds($0, model) } ? nil : "Select parts whose joins are disallowed."
        case .furnitureDisallowJoin:
            return fm6SelectedParts.isEmpty ? "Select parts." : nil
        default:
            return nil
        }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fm6MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard id == .furnitureJoint else { return nil }
        session.selection.clear()
        return FurnitureJointTool(ctx: c, in3D: fm6In3D)
    }

    /// Runs one of this batch's commands; true when handled.
    func fm6Perform(_ id: CommandID) -> Bool {
        let parts = fm6SelectedParts
        switch id {
        case .furnitureJointRules:
            state.presented = .fm6(.jointRules)
            return true
        case .furnitureAllowJoin:
            session.perform("Allow Join") { tx in FurnitureJointOperations.allowJoins(parts, in: tx) }
        case .furnitureDisallowJoin:
            session.perform("Disallow Join") { tx in FurnitureJointOperations.disallowJoins(parts, in: tx) }
        default:
            return false
        }
        if let e = session.lastError { state.show(e.message, error: true) }
        return true
    }
}
