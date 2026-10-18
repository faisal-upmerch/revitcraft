import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: View/Manage graphics-control commands, Modify ▸ Geometry cut/join order, Structure tab foundations and
// structural walls and floors.

extension CommandRouter {
    func blvgDisabledReason(_ id: CommandID) -> String? {
        let sel = selection.compactMap { model[$0] }
        let view = state.editingViewID.flatMap { model[$0] }
        switch id {
        case .viewTemplateCreate, .viewTemplateApplyProperties, .viewTemplateApply, .temporaryViewProperties:
            return view?.view == nil ? "Open a view (not a sheet or schedule) first." : nil
        case .revealConstraints:
            return view?.view?.kind.isPlan == true || view?.view?.kind == .drafting ? nil : "Reveal Constraints works in plan and drafting views."
        case .idsOfSelection:
            return sel.isEmpty ? "Select elements first." : nil
        case .cutGeometry:
            guard sel.count == 2, SolidJoins.cutPair(sel[0], sel[1]) != nil else {
                return "Select the floor, ceiling or roof to cut, then the wall, floor, roof or ceiling that cuts it."
            }
            return nil
        case .uncutGeometry, .switchJoinOrder:
            return sel.count >= (id == .switchJoinOrder ? 2 : 1) && sel.contains(where: { !SolidJoins.partners(of: $0.id, model).isEmpty })
                ? nil : "Select joined elements."
        case .foundationIsolated:
            return sel.contains { $0.category == .structuralColumns || $0.category == .columns } ? nil : "Select the columns to place footings under."
        case .foundationWall:
            return sel.contains { $0.wall != nil } ? nil : "Select the walls to place footings under."
        case .structuralWall, .structuralFloor, .foundationSlab:
            return isPlan ? nil : "Open a plan view to use this tool."
        default:
            return nil
        }
    }

    func blvgMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .structuralWall:
            let t = WallTool(ctx: c, mode: .line)
            markStructural(t, categories: [.walls])
            return t
        case .structuralFloor, .foundationSlab:
            var footing: ElementID?
            if id == .foundationSlab {
                footing = model.types(for: .floors).first { $0.name == StructuralFoundations.slabTypeName }?.id
                if footing == nil {
                    session.perform("Load Foundation Slab Type") { tx in footing = StructuralFoundations.footingType(StructuralFoundations.slabTypeName, thickness: 0.3, in: tx) }
                }
            }
            let t = SketchTool(ctx: c, target: .floor, commandID: .floor)
            t.drawMode = .line
            markStructural(t, categories: [.floors], typeID: footing)
            return t
        default:
            return nil
        }
    }

    /// Marks the walls or floors `tool` creates as structural (and, for foundation slabs, gives them the footing
    /// type) in the same transaction. The hook removes itself once another tool is active.
    func markStructural(_ tool: any InteractiveTool, categories: Set<Category>, typeID: ElementID? = nil) {
        let state = self.state
        state.session.beforeCommit = { [weak tool, weak state] tx in
            guard let state else { return }
            guard let tool, let active = state.activeTool, active === tool else { state.session.beforeCommit = nil; return }
            for id in tx.touchedIDs where tx.originalElement(id) == nil {
                guard let e = tx.model[id], categories.contains(e.category) else { continue }
                tx.update(id) { e in
                    e.wall?.structural = true
                    e.slab?.structural = true
                    if let typeID { e.typeID = typeID }
                }
            }
        }
    }

    func performBLVG(_ id: CommandID) -> Bool {
        let v = state.editingViewID ?? state.activeViewID
        let sel = selection
        switch id {
        case .filtersDialog: state.presented = .filters(nil)
        case .viewTemplatesManage: state.presented = .viewTemplates(v, .manage)
        case .viewTemplateApply: state.presented = .viewTemplates(v, .assign)
        case .viewTemplateApplyProperties: state.presented = .viewTemplates(v, .applyProperties)
        case .viewTemplateCreate: createTemplateFromView(v)
        case .temporaryViewProperties:
            guard let v else { return true }
            if state.session.temporaryVisibility[v]?.temporaryTemplateID != nil {
                state.session.temporaryVisibility[v]?.temporaryTemplateID = nil
                state.graphics.invalidateView(v)
                state.toolChangedState()
                state.show("View properties restored.")
            } else {
                state.presented = .viewTemplates(v, .temporary)
            }
        case .revealConstraints:
            guard let v else { return true }
            var t = session.temporaryVisibility[v] ?? TemporaryVisibility()
            t.revealConstraints.toggle()
            session.temporaryVisibility[v] = t
            state.graphics.invalidateView(v)
            state.toolChangedState()
            if t.revealConstraints {
                let n = model.elements(.constraints).filter { $0.constraint?.kind != .join }.count + model.elements(.dimensions).filter { $0.dimension?.locked == true || $0.dimension?.equality == true }.count
                state.show(n == 0 ? "Reveal Constraints: the model has no locked dimensions, alignments or EQ constraints." : "Reveal Constraints is on.")
            }
        case .userInterface: state.presented = .userInterface
        case .toggleStatusBar: toggleDefault("statusBar.visible")
        case .toggleNavigationBar: toggleDefault("navigationBar.visible")
        case .objectStyles: state.presented = .objectStyles
        case .warnings: state.scheduleHealthCheck(); state.presented = .warnings
        case .selectByID: state.presented = .selectByID
        case .idsOfSelection: state.presented = .report("IDs of Selection", ElementIDList.format(sel))
        case .additionalSettings, .lineWeights: state.presented = .additionalSettings(.lineWeights)
        case .linePatterns: state.presented = .additionalSettings(.linePatterns)
        case .fillPatterns: state.presented = .additionalSettings(.fillPatterns)
        case .arrowheads: state.presented = .additionalSettings(.arrowheads)
        case .temporaryDimensionSettings: state.presented = .additionalSettings(.temporaryDimensions)
        case .cutGeometry:
            let els = sel.compactMap { model[$0] }
            guard els.count == 2, let pair = SolidJoins.cutPair(els[0], els[1]) else { return true }
            session.perform("Cut Geometry") { tx in try SolidJoins.cutGeometry(cutter: pair.cutter.id, cut: pair.cut.id, in: tx) }
            report { "\(pair.cutter.category.singularName) cuts \(pair.cut.category.singularName.lowercased())." }
        case .uncutGeometry:
            var n = 0
            session.perform("Uncut Geometry") { tx in n = SolidJoins.unjoin(sel, in: tx) }
            if n == 0 { state.show("The selected elements don't cut each other.") }
        case .switchJoinOrder:
            session.perform("Switch Join Order") { tx in try SolidJoins.switchJoinOrder(sel[0], sel[1], in: tx) }
            report { "Join order switched." }
        case .foundationIsolated:
            var made: [ElementID] = []
            session.perform("Isolated Foundation") { tx in made = StructuralFoundations.isolated(under: sel, in: tx) }
            report { "\(made.count) pad footing\(made.count == 1 ? "" : "s") added (structural floors of type “\(StructuralFoundations.padTypeName)”)." }
        case .foundationWall:
            var made: [ElementID] = []
            session.perform("Wall Foundation") { tx in made = StructuralFoundations.wall(under: sel, in: tx) }
            report { made.isEmpty ? "Wall footings need straight walls." : "\(made.count) wall footing\(made.count == 1 ? "" : "s") added (structural floors of type “\(StructuralFoundations.stripTypeName)”)." }
        default:
            return false
        }
        return true
    }

    private func report(_ success: () -> String) {
        if let e = session.lastError { state.show(e.message, error: true); session.clearError() } else { state.show(success()) }
    }

    private func toggleDefault(_ key: String) {
        let on = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        UserDefaults.standard.set(!on, forKey: key)
    }

    func createTemplateFromView(_ v: ElementID?) {
        guard let v, let e = model[v], let vd = e.view else { return }
        var name = "\(e.name) Template", k = 2
        while model.elements(.viewTemplates).contains(where: { $0.name == name }) { name = "\(e.name) Template \(k)"; k += 1 }
        let td = ViewTemplates.make(from: vd)
        var created: ElementID?
        session.perform("Create View Template") { tx in created = tx.create(.viewTemplates, name: name, data: .viewTemplate(td)) }
        if let created { state.presented = .viewTemplates(v, .manage, select: created) }
    }
}
