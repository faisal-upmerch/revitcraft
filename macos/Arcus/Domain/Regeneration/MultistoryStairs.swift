import Foundation
import ArcusGeometry

/// F2: multistory stairs (RevitCraft `stair_storeys`, Connect Levels). A stair with a multistory top level repeats, one
/// copy per storey from its top level up to that level, each from one level to the next. The copies are derived (never
/// stored): the same element on the storey's level, so plans, sections and 3D show and pick them as the stair.
public enum MultistoryStairs {
    /// The stair and its repeats, bottom up; nil when `e` isn't a multistory stair (no repeat level above its top).
    public static func storeys(of e: Element, _ model: BIMModel) -> [Element]? {
        guard let s = e.stair, let mt = s.multistoryTopLevelID, let topZ = model[mt]?.level?.elevation, var cur = s.topLevelID,
              model[cur]?.level != nil else { return nil }
        var first = e
        first.stair?.multistoryTopLevelID = nil
        var out = [first]
        let levels = model.levels.compactMap { l in l.level.map { (l.id, $0.elevation) } }.sorted { $0.1 < $1.1 }
        while let z = model[cur]?.level?.elevation, z < topZ - Tolerance.length {
            guard let next = levels.first(where: { $0.1 > z + Tolerance.length }) else { break }
            var copy = first
            copy.levelID = cur
            copy.stair?.baseOffset = 0
            copy.stair?.topLevelID = next.0
            copy.stair?.topOffset = 0
            out.append(copy)
            cur = next.0
        }
        return out.count > 1 ? out : nil
    }

    /// The paths of a railing hosted on a multistory stair, one per storey; nil otherwise.
    public static func railingPaths(_ e: Element, _ model: BIMModel) -> [[Vec3]]? {
        guard let r = e.railing, r.followsHost, let host = model[e.hostID], let storeys = storeys(of: host, model) else { return nil }
        return storeys.map { StairGeometry.railingPath($0, model, leftSide: r.hostSideLeft) }
    }

    /// Levels a stair can repeat up to: those above its top level.
    public static func connectableLevels(_ e: Element, _ model: BIMModel) -> [Element] {
        guard let t = e.stair?.topLevelID, let z = model[t]?.level?.elevation else { return [] }
        return model.levels.filter { ($0.level?.elevation ?? -.infinity) > z + Tolerance.length }
            .sorted { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) }
    }
}
