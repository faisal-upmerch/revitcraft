import Foundation

// FMG4: a locked dimension between two part faces carries into the loaded family, as a family keeps a locked
// dimension between the reference planes its faces are on. The face that follows (the second, unless it was moved by
// hand) is put on the plane the other face follows, at the locked distance from it, so when the planes move (Family
// Types, or a loaded piece flexing) both faces move together; the compiled family writes the follower's face on that
// plane (a helper plane at the offset, kept there by a dimension, as for any part face).

extension FurnitureDimensionLocks {
    /// Binds the following face of each face-to-face lock to the plane the other face follows.
    static func bindFaceToFace(_ tx: TransactionContext) {
        let r = FurnitureBoundResolver(tx.model)
        for l in locks(tx.model) {
            guard case .face(let aid, let af) = l.a, case .face(let bid, let bf) = l.b, aid != bid else { continue }
            // The follower: the second face's part unless it was moved by hand (then the first's).
            let (fid, ff, anchorID, anchorFace) = tx.driven.contains(bid) && !tx.driven.contains(aid) ? (aid, af, bid, bf) : (bid, bf, aid, af)
            guard let anchor = tx.model[anchorID], let plane = followedPlane(anchor, anchorFace, tx.model, r), let p = r.positions[plane],
                  var e = tx.model[fid], let v = FurniturePartFaces.value(e, ff, tx.model) else { continue }
            let coords = FurniturePartCoordinates.coordinates(of: e).filter { $0.axis == ff.axis }
            let onFace = coords.filter { abs($0.value - v) <= 1e-6 }
            var bounds = FurniturePartBounds.bounds(of: e)
            var changed = false
            for c in onFace.isEmpty ? coords : onFace {
                let b = FurnitureBound.plane(plane, offset: c.value - p)
                if case .plane(let n, let o)? = bounds[c.key], n == plane, abs(o - (c.value - p)) < 1e-9 { continue }
                bounds[c.key] = b
                changed = true
            }
            guard changed else { continue }
            FurniturePartBounds.setBounds(bounds, of: &e)
            let data = e.data
            tx.propagate(fid) { $0.data = data }
        }
    }

    /// The plane a part's face follows: the plane of its coordinate on that face (or any of its coordinates on that axis).
    static func followedPlane(_ e: Element, _ face: PartFaceRef, _ m: BIMModel, _ r: FurnitureBoundResolver) -> String? {
        guard let v = FurniturePartFaces.value(e, face, m) else { return nil }
        let bounds = FurniturePartBounds.bounds(of: e)
        let coords = FurniturePartCoordinates.coordinates(of: e).filter { $0.axis == face.axis }
        let ordered = coords.filter { abs($0.value - v) <= 1e-6 } + coords.filter { abs($0.value - v) > 1e-6 }
        for c in ordered { if case .plane(let n, _)? = bounds[c.key], r.positions[n] != nil { return n } }
        return nil
    }
}
