import Foundation
import ArcusGeometry

// FMG1: dimensions to the faces of furniture parts, as Revit's dimensions to wall faces. A dimension references a
// part's face (its min or max along an axis), so it reads the part's current geometry and stays attached when the part
// moves, is resized or flexes. A locked dimension (padlock) between a reference plane and a part face, or between two
// part faces, constrains the part: flexing moves the part to keep the distance (the face's coordinate locks to the
// plane), and moving a locked part by hand is refused with "Constraints are not satisfied", as in Revit.

/// A face of a furniture part: the side of its box along an axis.
public struct PartFaceRef: Hashable, Codable, Sendable {
    public var axis: FamilyAxis
    public var atMax: Bool
    public init(axis: FamilyAxis, atMax: Bool) { self.axis = axis; self.atMax = atMax }
    public static let all: [PartFaceRef] = FamilyAxis.allCases.flatMap { a in [PartFaceRef(axis: a, atMax: false), PartFaceRef(axis: a, atMax: true)] }
}

extension GeometryReference {
    /// FMG1: a reference to a furniture part's face.
    public static func partFace(_ id: ElementID, _ face: PartFaceRef) -> GeometryReference {
        var r = GeometryReference(id, .partFace)
        r.face = face
        return r
    }
}

public enum FurniturePartFaces {
    /// The part's box: its own when it is a box, else its geometry's bounds.
    public static func box(_ e: Element, _ m: BIMModel) -> Box3? {
        guard e.category.isFurniturePart else { return nil }
        if let b = FurniturePartSolids.partBox(e, m)?.box { return b }
        let b = ElementMeshes.bounds(e, m)
        return b.isEmpty ? nil : b
    }

    static func component(_ v: Vec3, _ a: FamilyAxis) -> Double { switch a { case .x: v.x; case .y: v.y; case .z: v.z } }

    /// Where a part's face is along its axis.
    public static func value(_ e: Element, _ face: PartFaceRef, _ m: BIMModel) -> Double? {
        guard let b = box(e, m) else { return nil }
        return component(face.atMax ? b.max : b.min, face.axis)
    }

    /// A face reference in plan: faces across x and y are lines through the part; top and bottom faces aren't seen.
    public static func resolvePlan(_ r: GeometryReference, _ m: BIMModel) -> (point: Vec2, direction: Vec2?)? {
        guard let f = r.face, f.axis != .z, let e = m[r.elementID], let b = box(e, m) else { return nil }
        let c = b.center
        return f.axis == .x ? (Vec2(f.atMax ? b.max.x : b.min.x, c.y), Vec2(0, 1)) : (Vec2(c.x, f.atMax ? b.max.y : b.min.y), Vec2(1, 0))
    }

    /// A top or bottom face seen in an elevation or section: a level line at its height.
    public static func resolveLevel(_ r: GeometryReference, _ m: BIMModel) -> (point: Vec2, direction: Vec2?)? {
        guard let f = r.face, f.axis == .z, let e = m[r.elementID], let v = value(e, f, m) else { return nil }
        return (Vec2(0, v), Vec2(1, 0))
    }

    /// The faces of a part seen as lines in a view, as references.
    public static func references(_ id: ElementID) -> [GeometryReference] { PartFaceRef.all.map { .partFace(id, $0) } }
}

// MARK: - Locked dimensions

public enum FurnitureDimensionLocks {
    /// The signed distance a locked dimension keeps (second reference less the first, along their axis).
    public static let lockedOffset = ParameterID("furniture.dimension.lockedOffset")

    /// One end of a locked dimension: a plane or a part face, along an axis.
    enum End: Equatable {
        case plane(name: String, axis: FamilyAxis)
        case face(ElementID, PartFaceRef)
        var axis: FamilyAxis { switch self { case .plane(_, let a): a; case .face(_, let f): f.axis } }
        var part: ElementID? { if case .face(let id, _) = self { return id }; return nil }
    }

    struct Lock { var dimension: ElementID; var a: End; var b: End }

    static func end(_ r: GeometryReference, _ m: BIMModel, names: [ElementID: String]) -> End? {
        if r.kind == .partFace, let id = r.elementID, let f = r.face, m[id] != nil { return .face(id, f) }
        if let id = r.elementID, let rp = m[id]?.referencePlane, let axis = rp.furniture?.axis, let n = names[id] { return .plane(name: n, axis: axis) }
        return nil
    }

    /// The document's locked dimensions that involve a part face (between a plane and a face, or two faces).
    static func locks(_ m: BIMModel) -> [Lock] {
        guard m.isFurniture else { return [] }
        let names = FurniturePlanes.names(m)
        return m.elements(.dimensions).compactMap { d in
            guard let dd = d.dimension, dd.locked, dd.references.count == 2, dd.references.contains(where: { $0.kind == .partFace }),
                  let a = end(dd.references[0], m, names: names), let b = end(dd.references[1], m, names: names), a.axis == b.axis else { return nil }
            return Lock(dimension: d.id, a: a, b: b)
        }
    }

    static func position(_ e: End, _ m: BIMModel, _ r: FurnitureBoundResolver) -> Double? {
        switch e {
        case .plane(let n, _): r.positions[n]
        case .face(let id, let f): m[id].flatMap { FurniturePartFaces.value($0, f, m) }
        }
    }

    /// True for dimensions this solver keeps (the main constraint solver leaves them alone).
    public static func handles(_ d: DimensionData) -> Bool { d.references.contains { $0.kind == .partFace } }

    /// After the parts follow their planes: each locked dimension keeps its distance, moving the part at its second end
    /// (or the part at its first end when the second is a plane, or was moved by hand). Parts moved by hand stay put;
    /// `check` refuses the edit if that breaks a lock. A dimension just locked records its distance.
    public static func regenerate(_ tx: TransactionContext) {
        let locks = locks(tx.model)
        guard !locks.isEmpty else { return }
        for _ in 0..<3 {
            var moved = false
            for l in locks {
                let r = FurnitureBoundResolver(tx.model)
                guard let dim = tx.model[l.dimension], let pa = position(l.a, tx.model, r), let pb = position(l.b, tx.model, r) else { continue }
                let wasLocked = tx.originalElement(dim.id)?.dimension?.locked == true
                guard wasLocked, let keep = dim.params[lockedOffset]?.doubleValue else {
                    tx.propagate(dim.id) { $0.params[lockedOffset] = .double(pb - pa) }
                    continue
                }
                let error = (pa + keep) - pb
                guard abs(error) > Tolerance.length else { continue }
                // The end that follows: a part not moved by hand, the second end first.
                let candidates: [(End, Double, End)] = [(l.b, error, l.a), (l.a, -error, l.b)]
                guard let (follower, delta, anchor) = candidates.first(where: { c in c.0.part.map { !tx.driven.contains($0) } ?? false }),
                      let id = follower.part, case .face(_, let face) = follower else { continue }
                move(id, face, by: delta, lockTo: anchor, in: tx)
                moved = true
            }
            if !moved { break }
        }
        bindFaceToFace(tx) // FMG4: face-to-face locks hold in loaded families too
    }

    /// Moves a part's face along its axis: the coordinate on the face stretches the part (and locks to the plane the
    /// dimension names), else the whole part moves.
    static func move(_ id: ElementID, _ face: PartFaceRef, by delta: Double, lockTo anchor: End, in tx: TransactionContext) {
        guard var e = tx.model[id], let v = FurniturePartFaces.value(e, face, tx.model) else { return }
        let coords = FurniturePartCoordinates.coordinates(of: e).filter { $0.axis == face.axis }
        let onFace = coords.filter { abs($0.value - v) <= 1e-6 }
        var bounds = FurniturePartBounds.bounds(of: e)
        let r = FurnitureBoundResolver(tx.model)
        for c in onFace.isEmpty ? coords : onFace {
            let nv = c.value + delta
            FurniturePartCoordinates.set(c.key, nv, in: &e)
            if !onFace.isEmpty, case .plane(let n, _) = anchor, let p = r.positions[n] {
                bounds[c.key] = .plane(n, offset: nv - p)
            } else {
                switch bounds[c.key] {
                case .plane(let n, let o)?: bounds[c.key] = .plane(n, offset: o + delta)
                case .value(let x)?: bounds[c.key] = .value(x + delta)
                case nil: break
                }
            }
        }
        FurniturePartBounds.setBounds(bounds, of: &e)
        let data = e.data
        tx.propagate(id) { $0.data = data }
    }

    /// Refuses an edit that breaks a locked dimension (a locked part moved or resized by hand), as Revit's
    /// "Constraints are not satisfied".
    public static func check(_ tx: TransactionContext) throws(TransactionError) {
        let locks = locks(tx.model)
        guard !locks.isEmpty else { return }
        let r = FurnitureBoundResolver(tx.model)
        for l in locks {
            guard let dim = tx.model[l.dimension], tx.originalElement(dim.id)?.dimension?.locked == true, let keep = dim.params[lockedOffset]?.doubleValue,
                  let pa = position(l.a, tx.model, r), let pb = position(l.b, tx.model, r), abs((pa + keep) - pb) > Tolerance.length * 10 else { continue }
            throw TransactionError("Constraints are not satisfied: a locked dimension keeps this part where it is.",
                                   elements: [l.a.part, l.b.part, dim.id].compactMap { $0 },
                                   resolution: "Unlock the dimension (click its padlock), then move the part.")
        }
    }
}
