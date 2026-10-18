import Foundation
import ArcusGeometry

/// Whole-model checks for the Model Health panel. Each warning names the elements involved so the UI
/// can navigate to and select them.
public enum ModelHealth {
    public static func check(_ model: BIMModel, isCancelled: () -> Bool = { false }) -> [ModelWarning] {
        var out: [ModelWarning] = []
        // Duplicate marks per category.
        for c in Category.allCases where c.isModel {
            var byMark: [String: [ElementID]] = [:]
            for e in model.elements(c) where !e.mark.isEmpty { byMark[e.mark, default: []].append(e.id) }
            for (m, ids) in byMark.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
                out.append(ModelWarning(.warning, code: "mark.duplicate", "\(ids.count) \(c.displayName.lowercased()) share the mark “\(m)”.", elements: ids))
            }
        }
        if isCancelled() { return out }
        // Rooms.
        for l in model.levels {
            let bounds = RoomBoundaryCache.shared.boundaries(level: l.id, model)
            for (id, b) in bounds.sorted(by: { $0.key < $1.key }) {
                let name = model[id].map { "\($0.room?.number ?? "") \($0.name)".trimmingCharacters(in: .whitespaces) } ?? id.description
                switch b.state {
                case .notEnclosed: out.append(ModelWarning(.warning, code: "room.unbounded", "Room “\(name)” is not in a properly enclosed region.", elements: [id]))
                case .redundant(let other): out.append(ModelWarning(.warning, code: "room.redundant", "Room “\(name)” shares an enclosed region with another room.", elements: [id, other]))
                case .notPlaced: out.append(ModelWarning(.info, code: "room.unplaced", "Room “\(name)” is not placed.", elements: [id]))
                case .bounded: break
                }
            }
        }
        if isCancelled() { return out }
        // Hosts and references.
        for e in model.elements(.doors) + model.elements(.windows) {
            if model[e.hostID]?.wall == nil { out.append(ModelWarning(.error, code: "host.orphan", "\(e.category.singularName) has no host wall.", elements: [e.id])) }
        }
        for e in model.allElements {
            if let t = e.typeID, model[t]?.typeData == nil { out.append(ModelWarning(.error, code: "type.missing", "\(e.category.singularName) references a missing type.", elements: [e.id])) }
            if let l = e.levelID, model[l]?.level == nil, e.category != .views { out.append(ModelWarning(.error, code: "level.missing", "\(e.category.singularName) references a missing level.", elements: [e.id])) }
        }
        for t in model.elements(.elementTypes) {
            if let a = t.typeData?.assembly {
                for l in a.layers where l.materialID != nil && model[l.materialID]?.material == nil {
                    out.append(ModelWarning(.warning, code: "material.missing", "Type “\(t.name)” uses a material that no longer exists.", elements: [t.id]))
                }
            }
        }
        // Invalid sketches.
        for e in model.elements(.floors) + model.elements(.ceilings) + model.elements(.buildingPads) {
            if case .failure(let err) = e.slab?.boundary.profile() ?? .failure(.empty) {
                out.append(ModelWarning(.error, code: "sketch.invalid", "\(e.category.singularName) boundary: \(err)", elements: [e.id]))
            }
        }
        // Overlapping walls (collinear overlap on the same level).
        let walls = model.elements(.walls)
        var grid = SpatialGrid<ElementID>(cellSize: 4)
        for w in walls { if let c = w.wall?.location { grid.insert(w.id, bounds: c.bounds.expanded(by: 0.01)) } }
        var reported = Set<String>()
        for w in walls {
            guard let s = w.wall?.location.asSegment else { continue }
            for oid in grid.query(s.bounds.expanded(by: 0.01)) where oid > w.id {
                guard let o = model[oid], o.levelID == w.levelID, o.designOptionID == w.designOptionID, let t = o.wall?.location.asSegment else { continue }
                guard s.isCollinear(with: t) else { continue }
                let a0 = s.parameter(of: t.start) * s.length, a1 = s.parameter(of: t.end) * s.length
                let overlap = min(s.length, max(a0, a1)) - max(0, min(a0, a1))
                if overlap > 0.01 {
                    let k = "\(w.id)-\(oid)"
                    if reported.insert(k).inserted {
                        out.append(ModelWarning(.warning, code: "wall.overlap", "Walls overlap. One of them may be ignored when rooms are calculated.", elements: [w.id, oid]))
                    }
                }
            }
        }
        // Elements far from the origin.
        let limit = model.projectInfo.extentsWarningDistance
        for e in model.allElements where e.category.isModel {
            let b = ElementMeshes.bounds(e, model)
            guard !b.isEmpty else { continue }
            if max(abs(b.min.x), abs(b.max.x), abs(b.min.y), abs(b.max.y)) > limit {
                out.append(ModelWarning(.warning, code: "extents.far", "\(e.category.singularName) is more than \(Int(limit / 1000)) km from the internal origin. Graphics precision may suffer.", elements: [e.id]))
            }
        }
        // Constraints.
        for c in ConstraintSolver.activeConstraints(model) {
            if let v = ConstraintSolver.violation(c.data, model), abs(v.amount) > Tolerance.length * 10 {
                out.append(ModelWarning(.error, code: "constraint.violated", "A locked constraint is not satisfied.", elements: c.data.references.compactMap(\.elementID) + [c.id]))
            }
        }
        // Stairs.
        for s in model.elements(.stairs) {
            for w in StairGeometry.layout(s, model)?.warnings ?? [] { out.append(ModelWarning(.warning, code: "stair.rule", w, elements: [s.id])) }
        }
        for r in model.elements(.ramps) {
            for w in RampGeometry.layout(r, model)?.warnings ?? [] { out.append(ModelWarning(.warning, code: "ramp.length", w, elements: [r.id])) }
        }
        // Views not on sheets (info) and missing links.
        for l in model.elements(.importedCAD) where l.link?.isLinked == true && l.link?.isLoaded == false {
            out.append(ModelWarning(.warning, code: "link.unloaded", "Link “\(l.link?.sourceName ?? l.name)” is not loaded.", elements: [l.id]))
        }
        // Export: rooms without numbers and elements without IFC-compatible classification are fine; unnamed levels flagged.
        for l in model.levels where l.name.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(ModelWarning(.warning, code: "export.levelName", "A level has no name; IFC storeys need names.", elements: [l.id]))
        }
        return out.sorted { ($0.severity, $0.code, $0.id) > ($1.severity, $1.code, $1.id) }
    }
}
