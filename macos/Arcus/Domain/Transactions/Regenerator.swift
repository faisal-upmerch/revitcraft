import Foundation
import ArcusGeometry

/// Propagates dependent changes, solves constraints and validates a transaction before commit.
public struct Regenerator: Sendable {
    public init() {}

    public func regenerate(_ tx: TransactionContext) throws(TransactionError) {
        propagateHosts(tx)
        normalizeCurtainWalls(tx) // WP3
        try StructuralFraming.regenerateBeamSystems(tx) // F34
        repairDanglingReferences(tx)
        FurnitureRegeneration.regenerate(tx) // FM3: Furniture documents: planes follow Family Types
        try ConstraintSolver.solve(tx)
        try validate(tx)
    }

    /// Re-projects hosted inserts onto edited walls; removes inserts that no longer fit.
    func propagateHosts(_ tx: TransactionContext) {
        for id in tx.touchedIDs {
            guard let w = tx.model[id], w.wall != nil, let f = WallGeometry.frame(w, tx.model) else { continue }
            for ins in tx.model.hosted(by: id) where ins.insert != nil {
                let width = InsertGeometry.openingSize(ins, tx.model)?.width ?? 0.9
                if let p = InsertGeometry.constrainToHost(ins.insert!.location, width: width, host: f) {
                    tx.propagate(ins.id) { $0.insert?.location = p; $0.levelID = w.levelID }
                } else {
                    tx.warn(ModelWarning(.warning, code: "insert.removed",
                                         "\(ins.category.singularName) \(ins.mark.isEmpty ? ins.id.description : ins.mark) was deleted because its host wall became too short.",
                                         elements: [ins.id, id]))
                    tx.delete(ins.id)
                }
            }
        }
    }

    /// Clears references to elements that no longer exist (top levels, upper limits, underlays, materials).
    func repairDanglingReferences(_ tx: TransactionContext) {
        let m = tx.model
        for w in m.elements(.walls) {
            guard let t = w.wall?.topLevelID, m[t] == nil else { continue }
            let base = tx.originalModel.baseElevation(of: w)
            let top = tx.originalModel.elevation(ofLevel: t) + (w.wall?.topOffset ?? 0)
            tx.propagate(w.id) { $0.wall?.topLevelID = nil; $0.wall?.unconnectedHeight = max(0.1, top - base) }
        }
        for c in m.elements(.columns) + m.elements(.structuralColumns) {
            guard let t = c.column?.topLevelID, m[t] == nil else { continue }
            tx.propagate(c.id) { $0.column?.topLevelID = nil }
        }
        for s in m.elements(.stairs) {
            guard let t = s.stair?.topLevelID, m[t] == nil else { continue }
            tx.propagate(s.id) { $0.stair?.topLevelID = nil }
        }
        for r in m.elements(.ramps) {
            guard let t = r.ramp?.topLevelID, m[t] == nil else { continue }
            let base = tx.originalModel.baseElevation(of: r)
            let top = tx.originalModel.elevation(ofLevel: t) + (r.ramp?.topOffset ?? 0)
            tx.propagate(r.id) { $0.ramp?.topLevelID = nil; $0.ramp?.unconnectedHeight = max(0.1, top - base) }
        }
        for r in m.elements(.rooms) + m.elements(.areas) + m.elements(.spaces) { // F5: spaces
            guard let t = r.room?.upperLimitLevelID, m[t] == nil else { continue }
            tx.propagate(r.id) { $0.room?.upperLimitLevelID = nil }
        }
        for v in m.views {
            guard let vd = v.view else { continue }
            if let u = vd.underlayLevelID, m[u] == nil { tx.propagate(v.id) { $0.view?.underlayLevelID = nil } }
            if let t = vd.templateID, m[t] == nil { tx.propagate(v.id) { $0.view?.templateID = nil } }
            if let p = vd.phaseID, m[p] == nil { tx.propagate(v.id) { $0.view?.phaseID = nil } }
        }
        for s in m.sheets where s.sheet?.titleBlockTypeID.map({ m[$0] == nil }) == true {
            tx.propagate(s.id) { $0.sheet?.titleBlockTypeID = nil }
        }
        ScopeBoxes.repairDanglingReferences(tx) // WP6a
    }

    func validate(_ tx: TransactionContext) throws(TransactionError) {
        let m = tx.model
        for id in tx.touchedIDs {
            guard let e = m[id] else { continue }
            if let l = e.levelID, m[l]?.level == nil, e.category != .views {
                throw TransactionError("\(e.category.singularName) references a level that does not exist.", elements: [id])
            }
            if let t = e.typeID {
                guard let td = m[t]?.typeData else { throw TransactionError("\(e.category.singularName) references a missing type.", elements: [id]) }
                if td.instanceCategory != e.category && !(e.category == .structuralColumns && td.instanceCategory == .columns) {
                    throw TransactionError("A \(td.instanceCategory.singularName) type can't be used for a \(e.category.singularName).", elements: [id])
                }
            }
            if let o = e.ownerViewID, m[o] == nil {
                throw TransactionError("\(e.category.singularName) belongs to a view that no longer exists.", elements: [id])
            }
            switch e.data {
            case .wall(let w):
                if w.location.length < Tolerance.shortCurve {
                    throw TransactionError("The wall is too short. Walls must be longer than 0.8 mm.", elements: [id])
                }
                if let f = WallGeometry.frame(e, m), f.topZ - f.baseZ < Tolerance.shortCurve {
                    throw TransactionError("The top of the wall is below its base.", elements: [id],
                                           resolution: "Raise the Top Constraint/Top Offset or lower the Base Offset.")
                }
                if let t = w.topLevelID, m[t]?.level == nil {
                    throw TransactionError("The wall's top constraint is not a level.", elements: [id])
                }
            case .insert:
                guard let host = m[e.hostID], host.wall != nil else {
                    throw TransactionError("\(e.category.singularName)s must be hosted by a wall.", elements: [id])
                }
                if let f = WallGeometry.frame(host, m), let o = InsertGeometry.openingInHost(e, host: f, m) {
                    if o.0 < -Tolerance.length * 10 || o.1 > f.length + Tolerance.length * 10 {
                        tx.warn(ModelWarning(.warning, code: "insert.outside", "\(e.category.singularName) extends beyond the end of its host wall.", elements: [id, host.id]))
                    }
                    if o.3 > f.topZ + Tolerance.length * 10 {
                        tx.warn(ModelWarning(.warning, code: "insert.aboveTop", "\(e.category.singularName) head is above the top of its host wall.", elements: [id, host.id]))
                    }
                }
            case .slab(let s):
                if case .failure(let err) = s.boundary.profile() {
                    throw TransactionError("\(e.category.singularName) boundary is invalid: \(err)", elements: [id],
                                           resolution: "Edit the boundary so every loop is closed and loops don't cross.")
                }
            case .roof(let r) where r.extrusion != nil:
                if let err = RoofExtrusionGeometry.validate(r.extrusion!) {
                    throw TransactionError("Roof profile is invalid: \(err)", elements: [id])
                }
            case .roof(let r):
                if case .failure(let err) = r.footprint.profile() {
                    throw TransactionError("Roof footprint is invalid: \(err)", elements: [id])
                }
                if r.footprint.loops.first?.count != r.edgeSlopes.count {
                    throw TransactionError("Roof slope settings do not match its footprint lines.", elements: [id])
                }
            case .stair:
                guard let l = StairGeometry.layout(e, m) else {
                    throw TransactionError("The stair needs a top above its base (at least 100 mm).", elements: [id])
                }
                for w in l.warnings { tx.warn(ModelWarning(.warning, code: "stair.rule", w, elements: [id])) }
            case .ramp:
                if let reason = RampGeometry.invalidReason(e, m) { throw TransactionError(reason, elements: [id]) }
                for w in RampGeometry.layout(e, m)?.warnings ?? [] { tx.warn(ModelWarning(.warning, code: "ramp.length", w, elements: [id])) }
            case .level:
                if m.levels.contains(where: { $0.id != id && $0.name == e.name }) {
                    throw TransactionError("The level name “\(e.name)” is already in use.", elements: [id])
                }
            case .grid:
                if m.elements(.grids).contains(where: { $0.id != id && $0.name == e.name }) {
                    throw TransactionError("The grid name “\(e.name)” is already in use.", elements: [id])
                }
            case .view(let v):
                if m.views.contains(where: { $0.id != id && $0.name == e.name && $0.view?.kind.navigatorGroup == v.kind.navigatorGroup }) {
                    throw TransactionError("A view named “\(e.name)” already exists.", elements: [id], resolution: "Choose a unique view name.")
                }
            case .sheet(let s):
                if m.sheets.contains(where: { $0.id != id && $0.sheet?.number == s.number }) {
                    throw TransactionError("Sheet number “\(s.number)” is already in use.", elements: [id])
                }
            case .viewport(let vp):
                guard let v = m[vp.viewID], v.view != nil || v.schedule != nil else {
                    throw TransactionError("The viewport's view no longer exists.", elements: [id])
                }
                if v.view != nil {
                    let placements = m.viewports(showing: vp.viewID)
                    if placements.count > 1 && v.view?.kind != .legend {
                        throw TransactionError("“\(v.name)” is already placed on a sheet. A view can be placed on one sheet only; duplicate it first.", elements: [id])
                    }
                }
            case .room:
                if e.levelID == nil { throw TransactionError("Rooms must be placed on a level.", elements: [id]) }
            case .schedule(let s):
                if s.fields.isEmpty && s.kind != .noteBlock {
                    throw TransactionError("A schedule needs at least one field.", elements: [id])
                }
            case .type(let td):
                if let a = td.assembly, let err = a.validate() {
                    throw TransactionError("Type “\(e.name)”: \(err)", elements: [id])
                }
            default:
                break
            }
        }
    }
}
