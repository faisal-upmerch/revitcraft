import Foundation
import ArcusGeometry
import ArcusDomain

extension ToolContext {
    /// Every distinct object snap within reach of `raw`, best first (the snap `snap(_:from:)` would pick comes first).
    /// Tab steps through these while a drawing tool is active, so a hidden endpoint or intersection can be picked
    /// where a stronger snap wins by default.
    public func snapCandidates(_ raw: Vec2, from: Vec2?) -> [SnapResult] {
        let base = effectiveSnapSettings
        guard base.snapsOn else { return [] }
        let radius = base.pixelRadius * pixel
        var found: [SnapResult] = []
        for kind in SnapKind.allCases where ![.angle, .parallel, .extension].contains(kind) && base.enabled.contains(kind) {
            var s = base
            s.enabled = [kind]
            guard let r = snapIndex.snap(raw, radius: radius, from: from, settings: s, exclude: snapExclusions) else { continue }
            if !found.contains(where: { $0.point.isAlmostEqual(r.point, tolerance: pixel * 0.5) }) { found.append(r) }
        }
        return found.sorted { ($0.kind.priority, $0.point.distance(to: raw)) < ($1.kind.priority, $1.point.distance(to: raw)) }
    }
}
