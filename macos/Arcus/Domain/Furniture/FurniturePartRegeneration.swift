import Foundation
import ArcusGeometry

// FM4: regeneration of furniture parts, after FM3 places the planes. Parts follow the planes they're bound to; a part
// the user moved, stretched or edited keeps following its plane at the new offset, or locks to the plane it was put on
// (the padlock Align gives in Revit); new parts lock to the planes they were drawn on. Attached panels and legs run to
// their shelf or top, EQ dividers stay equally spaced, and new parts are numbered P1, P2… by kind.

/// One coordinate of a part: its key, the world axis it lies along, and its value.
public struct PartCoordinate: Hashable, Sendable {
    public var key: String
    public var axis: FamilyAxis
    public var value: Double
}

public enum FurniturePartCoordinates {
    /// The part's plane-bindable coordinates.
    public static func coordinates(of e: Element) -> [PartCoordinate] {
        switch e.data {
        case .furniturePanel(let p):
            let a = p.plane.axes
            return [.init(key: "start.u", axis: a.u, value: p.start.x), .init(key: "start.v", axis: a.v, value: p.start.y),
                    .init(key: "end.u", axis: a.u, value: p.end.x), .init(key: "end.v", axis: a.v, value: p.end.y),
                    .init(key: "base", axis: a.w, value: p.base), .init(key: "top", axis: a.w, value: p.top)]
        case .furnitureRail(let r):
            let a = r.plane.axes
            return [.init(key: "start.u", axis: a.u, value: r.start.x), .init(key: "start.v", axis: a.v, value: r.start.y),
                    .init(key: "end.u", axis: a.u, value: r.end.x), .init(key: "end.v", axis: a.v, value: r.end.y),
                    .init(key: "w", axis: a.w, value: r.w)]
                + (FurniturePartFlex.slatsFar(r).map { [PartCoordinate(key: "far", axis: $0.axis, value: $0.value)] } ?? []) // FMG1: Slats' far side
        case .furnitureShelf(let s):
            return s.boundary.enumerated().flatMap { i, p in [PartCoordinate(key: "p\(i).x", axis: .x, value: p.x), PartCoordinate(key: "p\(i).y", axis: .y, value: p.y)] }
                + [.init(key: "z", axis: .z, value: s.elevation)]
        case .furnitureLeg(let l):
            return [.init(key: "x", axis: .x, value: l.location.x), .init(key: "y", axis: .y, value: l.location.y),
                    .init(key: "base", axis: .z, value: l.base), .init(key: "top", axis: .z, value: l.top)]
        case .furnitureForm(let f):
            return FurniturePartFlex.revolveCoordinates(f) // FMG1: a revolve's axis and profile points
        default:
            return []
        }
    }

    /// Sets one coordinate.
    public static func set(_ key: String, _ v: Double, in e: inout Element) {
        func pt(_ p: inout Vec2, _ comp: Substring) { if comp == "u" || comp == "x" { p.x = v } else { p.y = v } }
        let parts = key.split(separator: ".")
        switch e.data {
        case .furniturePanel(var p):
            switch key {
            case "base": p.base = v
            case "top": p.top = v
            default: if parts.count == 2 { if parts[0] == "start" { pt(&p.start, parts[1]) } else { pt(&p.end, parts[1]) } }
            }
            e.data = .furniturePanel(p)
        case .furnitureRail(var r):
            if key == "w" { r.w = v } else if key == "far" { FurniturePartFlex.setSlatsFar(v, &r) } // FMG1
            else if parts.count == 2 { if parts[0] == "start" { pt(&r.start, parts[1]) } else { pt(&r.end, parts[1]) } }
            e.data = .furnitureRail(r)
        case .furnitureShelf(var s):
            if key == "z" { s.elevation = v }
            else if parts.count == 2, let i = Int(parts[0].dropFirst()), s.boundary.indices.contains(i) { pt(&s.boundary[i], parts[1]) }
            e.data = .furnitureShelf(s)
        case .furnitureLeg(var l):
            switch key {
            case "x": l.location.x = v
            case "y": l.location.y = v
            case "base": l.base = v
            case "top": l.top = v
            default: break
            }
            e.data = .furnitureLeg(l)
        case .furnitureForm(var f):
            FurniturePartFlex.setRevolve(key, v, &f) // FMG1
            e.data = .furnitureForm(f)
        default: break
        }
    }

    /// The model's furniture planes along `axis`, by name.
    public static func planes(along axis: FamilyAxis, _ m: BIMModel) -> [(name: String, position: Double)] {
        let names = FurniturePlanes.names(m)
        return FurniturePlanes.all(m).compactMap { p in
            guard let rp = p.referencePlane, rp.furniture?.axis == axis, let n = names[p.id], let v = FurniturePlanes.position(rp) else { return nil }
            return (n, v)
        }
    }

    /// The plane along `axis` at `value` (within `tolerance`), nearest first.
    public static func plane(at value: Double, along axis: FamilyAxis, _ m: BIMModel, tolerance: Double = 1e-4) -> String? {
        planes(along: axis, m).filter { abs($0.position - value) <= tolerance }.min { abs($0.position - value) < abs($1.position - value) }?.name
    }
}

/// What a new or moved coordinate locks to: a plane it lies on, else a face of another part that follows a plane (a
/// shelf drawn between two sides keeps to their inside faces as the sides move with Width).
public struct FurniturePartBinder {
    let model: BIMModel
    let excluding: ElementID
    var faces: [FamilyAxis: [PartValue]]

    public init(_ m: BIMModel, excluding id: ElementID, boxes: [ElementID: FurniturePartSolids.PartBox]) {
        model = m; excluding = id
        var f: [FamilyAxis: [PartValue]] = [:]
        for (pid, b) in boxes where pid != id {
            for a in FamilyAxis.allCases {
                let r = b.range(a)
                for v in [r.0, r.1] where v.plane != nil { f[a, default: []].append(v) }
            }
        }
        faces = f
    }

    /// The bound for `value` along `axis`, or nil when nothing lies there.
    public func bound(_ value: Double, along axis: FamilyAxis, tolerance: Double = FurniturePartRegeneration.lockTolerance) -> FurnitureBound? {
        if let n = FurniturePartCoordinates.plane(at: value, along: axis, model, tolerance: tolerance) { return .plane(n, offset: 0) }
        let hit = (faces[axis] ?? []).filter { abs($0.value - value) <= tolerance }.min { abs($0.offset) < abs($1.offset) }
        if let h = hit, let n = h.plane { return .plane(n, offset: h.offset + (value - h.value)) }
        return nil
    }

    /// Every part's box (for binding to faces).
    public static func boxes(_ m: BIMModel) -> [ElementID: FurniturePartSolids.PartBox] {
        var out: [ElementID: FurniturePartSolids.PartBox] = [:]
        for c in [Category.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails] {
            for e in m.elements(c) { if let b = FurniturePartSolids.partBox(e, m) { out[e.id] = b } }
        }
        return out
    }
}

public enum FurniturePartRegeneration {
    /// Tolerance for a coordinate to lock to a plane it lies on (0.1 mm).
    public static let lockTolerance = 1e-4

    /// Regenerates the parts of a Furniture document (called by FM3's regeneration after the planes are placed).
    public static func regenerate(_ tx: TransactionContext, _ touched: [ElementID]) {
        let parts = Category.furnitureParts.flatMap { tx.model.elements($0) }
        guard !parts.isEmpty else { return }
        let resolver = FurnitureBoundResolver(tx.model)
        let touchedSet = Set(touched)
        let needsBinding = parts.contains { touchedSet.contains($0.id) }
        // When the planes moved in this transaction (a Family Types edit), new parts follow the planes they name.
        let planesMoved = FurniturePlanes.positionsByName(tx.originalModel) != resolver.positions
        let boxes = needsBinding ? FurniturePartBinder.boxes(tx.model) : [:]
        for part in parts {
            guard var e = tx.model[part.id] else { continue }
            let before = tx.originalElement(e.id)
            var bounds = FurniturePartBounds.bounds(of: e)
            let coords = FurniturePartCoordinates.coordinates(of: e)
            let old = Dictionary((before.map(FurniturePartCoordinates.coordinates(of:)) ?? []).map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
            let edited = touchedSet.contains(e.id) && tx.driven.contains(e.id)
            let binder = before == nil || edited ? FurniturePartBinder(tx.model, excluding: e.id, boxes: boxes) : nil
            for c in coords {
                let byUser = before == nil || (edited && old[c.key].map { abs($0 - c.value) > 1e-9 } ?? true)
                if byUser {
                    // New, copied or moved by the user: a bound that still holds stays; otherwise the coordinate locks to
                    // the plane (or plane-bound part face) it was put on, or keeps following its plane at the new offset.
                    if let b = bounds[c.key], let v = resolver.resolve(b), abs(v - c.value) <= 1e-9 { continue }
                    if before == nil, planesMoved, let b = bounds[c.key], let v = resolver.resolve(b) {
                        FurniturePartCoordinates.set(c.key, v, in: &e)
                        continue
                    }
                    if let b = binder?.bound(c.value, along: c.axis) {
                        bounds[c.key] = b
                    } else if case .plane(let n, _)? = bounds[c.key], let p = resolver.positions[n] {
                        bounds[c.key] = .plane(n, offset: c.value - p)
                    } else if bounds[c.key] != nil {
                        bounds[c.key] = .value(c.value)
                    }
                } else if let b = bounds[c.key], let v = resolver.resolve(b), abs(v - c.value) > 1e-9 {
                    FurniturePartCoordinates.set(c.key, v, in: &e)
                }
            }
            FurniturePartBounds.setBounds(bounds, of: &e)
            if e != tx.model[part.id] { tx.propagate(e.id) { $0 = e } }
        }
        followAttachments(tx)
        spaceDividers(tx, resolver)
        FurniturePartFlex.regenerate(tx, resolver) // FMG1: EQ rails
        numberMarks(tx)
    }

    /// Attached panels run to their shelf: Attach Top to the underside, Attach Base to the top face. Legs attached to a
    /// top run to its underside.
    static func followAttachments(_ tx: TransactionContext) {
        func underside(_ id: ElementID?) -> (bottom: Double, top: Double)? {
            guard let s = tx.model[id], let sd = s.furnitureShelf else { return nil }
            let t = FurniturePartTypes.values(of: s, tx.model).thickness
            return (sd.elevation - t, sd.elevation)
        }
        for e in tx.model.elements(.furniturePanels) {
            guard var p = e.furniturePanel, p.plane == .xy, p.attachedTopID != nil || p.attachedBaseID != nil else { continue }
            if let a = p.attachedTopID {
                if let u = underside(a) { p.top = u.bottom; p.bounds["top"] = nil } else { p.attachedTopID = nil }
            }
            if let a = p.attachedBaseID {
                if let u = underside(a) { p.base = u.top; p.bounds["base"] = nil } else { p.attachedBaseID = nil }
            }
            if p != e.furniturePanel { tx.propagate(e.id) { $0.furniturePanel = p } }
        }
        for e in tx.model.elements(.furnitureLegs) {
            guard var l = e.furnitureLeg, let a = l.attachedTopID else { continue }
            if let u = underside(a) { l.top = u.bottom; l.bounds["top"] = nil } else { l.attachedTopID = nil }
            if l != e.furnitureLeg { tx.propagate(e.id) { $0.furnitureLeg = l } }
        }
    }

    /// EQ dividers: each centre at its share of the space between its two bounds.
    static func spaceDividers(_ tx: TransactionContext, _ r: FurnitureBoundResolver) {
        for e in tx.model.elements(.furniturePanels) {
            guard var p = e.furniturePanel, let eq = p.eq, eq.count > 0, let lo = r.resolve(eq.low), let hi = r.resolve(eq.high),
                  let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end) else { continue }
            let c = lo + (hi - lo) * Double(eq.index) / Double(eq.count)
            let (fo, fi) = FurniturePartSolids.faceOffsets(p, thickness: FurniturePartTypes.values(of: e, tx.model).thickness)
            let line = c - f.across * (fo + fi) / 2
            if f.lineAlongU { p.start.y = line; p.end.y = line; p.bounds["start.v"] = nil; p.bounds["end.v"] = nil }
            else { p.start.x = line; p.end.x = line; p.bounds["start.u"] = nil; p.bounds["end.u"] = nil }
            if p != e.furniturePanel { tx.propagate(e.id) { $0.furniturePanel = p } }
        }
    }

    /// New parts without a Mark get the next number of their kind: P1, P2…, S1…, L1….
    static func numberMarks(_ tx: TransactionContext) {
        var high: [String: Int] = [:]
        var unnumbered: [(ElementID, String)] = []
        let all = Category.furnitureParts.flatMap { tx.model.elements($0) }
        // Copies arrive with their original's Mark: they're numbered too, as Revit numbers copied instances.
        var markOwners: [String: [ElementID]] = [:]
        for e in all where !e.mark.isEmpty { markOwners[e.mark, default: []].append(e.id) }
        for e in all {
            guard let k = e.furniturePartKind else { continue }
            let prefix = k.markPrefix
            let isNew = tx.originalElement(e.id) == nil
            if e.mark.isEmpty || (isNew && (markOwners[e.mark]?.count ?? 0) > 1 && markOwners[e.mark]?.first != e.id) {
                if isNew { unnumbered.append((e.id, prefix)) }
                continue
            }
            if e.mark.hasPrefix(prefix), let n = Int(e.mark.dropFirst(prefix.count)) { high[prefix] = max(high[prefix] ?? 0, n) }
        }
        for (id, prefix) in unnumbered.sorted(by: { $0.0 < $1.0 }) {
            let n = (high[prefix] ?? 0) + 1
            high[prefix] = n
            tx.propagate(id) { $0.mark = "\(prefix)\(n)" }
        }
    }
}
