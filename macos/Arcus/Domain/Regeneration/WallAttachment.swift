import Foundation
import ArcusGeometry

/// Attaching wall tops to roofs and floors after the fact (the walls below a new roof or floor, or on request).
public enum WallAttachment {
    /// Walls below `host` (a roof or floor) whose tops reach its underside and that are not attached to it yet.
    public static func candidates(for host: Element, _ model: BIMModel) -> [ElementID] {
        guard host.roof != nil || (host.slab != nil && host.category == .floors) else { return [] }
        var out: [ElementID] = []
        for w in model.elements(.walls) {
            guard let wd = w.wall, !wd.attachedTopIDs.contains(host.id), w.designOptionID == host.designOptionID,
                  let f = WallGeometry.frame(w, model) else { continue }
            let center = f.location.offset(by: f.centerOffset)
            let samples = max(2, min(40, Int(f.length / 0.25)))
            var hits = 0
            var reaches = false
            for i in 0...samples {
                let p = center.point(at: Double(i) / Double(samples))
                guard let under = AttachmentQueries.undersideZ(host, at: p, model) else { continue }
                // The wall must start below the host and rise to (or through) its underside.
                guard f.baseZ < under - 0.05 else { continue }
                hits += 1
                if f.topZ >= under - 0.05 { reaches = true }
            }
            if hits > 0 && reaches { out.append(w.id) }
        }
        return out
    }

    /// Attaches the walls' tops to `host`. For roofs the walls are first raised to the ridge so the roof underside
    /// shapes their tops (gable ends fill up to the roof); floors simply stop the walls at their underside.
    public static func attach(_ walls: [ElementID], to host: ElementID, in tx: TransactionContext) {
        guard let h = tx.model[host] else { return }
        let ridge = h.roof != nil ? RoofGeometry.ridgeHeight(h, tx.model) : nil
        for id in walls {
            tx.update(id) { e in
                guard var wd = e.wall, !wd.attachedTopIDs.contains(host) else { return }
                wd.attachedTopIDs.append(host)
                if let ridge {
                    let base = tx.model.elevation(ofLevel: e.levelID) + wd.baseOffset
                    if wd.topLevelID == nil { wd.unconnectedHeight = max(wd.unconnectedHeight, ridge - base) }
                    else { wd.topOffset = max(wd.topOffset, ridge - tx.model.elevation(ofLevel: wd.topLevelID)) }
                }
                e.wall = wd
            }
        }
    }
}
