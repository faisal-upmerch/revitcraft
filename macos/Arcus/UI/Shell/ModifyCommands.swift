import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Modify commands added with the switcher work package: Create Similar, Measure, Demolish, Scale and Array Number.
extension CommandRouter {
    /// Availability of these commands (nil when they can run).
    func modifyToolsDisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .createSimilar:
            guard selection.count == 1, let e = model[selection[0]] else { return "Select one element." }
            return CreateSimilar.plan(for: e, model) == nil ? "The selected element can't be placed with a tool." : nil
        case .measureBetween, .measureAlong:
            return (state.activeView?.view == nil && !isSheet) || viewKind == .threeD ? "Measure in a plan, section, elevation or drafting view." : nil
        case .demolish:
            if model.phases.isEmpty { return "This project has no phases. Add one in Manage ▸ Phases." }
            return state.activeView?.view == nil || viewKind == .threeD ? "Demolish in a plan, section or elevation view." : nil
        case .scale:
            if selection.isEmpty { return nil } // BL-KEYS: pre-selection flow
            return selection.contains(where: { model[$0].map(ElementOperations.isScalable) ?? false }) ? nil : "Select walls, lines, reference planes, regions or links."
        case .arrayNumber:
            return selectedArrayGroup == nil ? "Select an array group or one of its members." : nil
        default:
            return nil
        }
    }

    var selectedArrayGroup: Element? {
        selection.lazy.compactMap { ArrayOperations.arrayGroup(of: $0, model) }.first
    }

    func runModifyTool(_ id: CommandID) {
        guard let c = ctx() else { return }
        switch id {
        case .measureBetween: state.setTool(MeasureTool(ctx: c, mode: .between))
        case .measureAlong: state.setTool(MeasureTool(ctx: c, mode: .along))
        case .demolish: state.setTool(DemolishTool(ctx: c))
        case .scale: state.setTool(ScaleTool(ctx: c, ids: selection))
        default: break
        }
    }

    /// Starts the placement tool for the selected element's kind with its type (and line style) preselected.
    func createSimilar() {
        guard selection.count == 1, let e = model[selection[0]], let plan = CreateSimilar.plan(for: e, model) else { return }
        if let reason = disabledReason(plan.command) {
            state.show("Create Similar: \(reason)", error: true)
            return
        }
        for (category, type) in plan.types { state.currentTypes[category] = type }
        for c in state.toolContexts.values { c.currentTypes = state.currentTypes }
        session.selection.clear()
        guard let tool = makeTool(plan.command) else { return }
        CreateSimilar.configure(tool, like: e)
        state.setTool(tool)
        if let t = e.typeID.flatMap({ model[$0] }) { state.show("Placing \(t.typeData.map { "\($0.familyName): " } ?? "")\(t.name).") }
    }

    /// Asks for a new number of members and regenerates the array.
    func editArrayNumber() {
        guard let g = selectedArrayGroup, let spec = g.group?.arraySpec else { return }
        let gid = g.id
        let view = state.activeViewID
        state.requestText(prompt: "Number of array members (2–\(ArraySpec.maximumCount))", initial: "\(spec.count)") { text in
            guard let text else { return }
            guard let n = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), n >= 2, n <= ArraySpec.maximumCount else {
                state.show("Enter a whole number from 2 to \(ArraySpec.maximumCount).", error: true); return
            }
            guard n != spec.count else { return }
            session.perform("Array Number") { tx in try ArrayOperations.setCount(n, ofArray: gid, in: tx, viewID: view) }
            if session.lastError == nil, let members = model[gid]?.group?.members {
                session.selection.select(members)
                state.show("The array now has \(n) members.")
            }
        }
    }
}
