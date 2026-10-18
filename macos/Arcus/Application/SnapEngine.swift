import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// The snapping behaviour BIM users expect while drawing and dragging, in priority order:
///
/// 1. Point snaps on visible geometry (endpoint, midpoint, intersection, centre, perpendicular, tangent…), within the
///    snap distance of the pointer.
/// 2. Where two guides cross: extensions of lines, horizontal/vertical through the start point, parallel/perpendicular
///    to nearby or recently hovered lines, and the line under the pointer ("INTERSECTION of EXTENSION of … AND VERTICAL").
/// 3. Nearest point on the line under the pointer.
/// 4. A single guide, with the length from the start point rounded to an increment that suits the zoom.
/// 5. Otherwise the pointer, with the length rounded the same way.
///
/// Guides and point snaps carry a status-bar label naming the elements involved and the dashed guide lines to draw.
extension ToolContext {
    /// A line the pointer can be held on.
    struct Guide {
        var origin: Vec2
        var direction: Vec2
        var label: String
        var kind: SnapKind
        var ids: [ElementID]
        /// Where the dashed guide starts (a line's end for extensions, the start point for directions).
        var anchor: Vec2?
        /// Passes through the start point: the length along it can be rounded.
        var throughStart: Bool
        /// Tooltip name when the kind's own name doesn't fit ("Alignment").
        var shortName: String? = nil
        func distance(to p: Vec2) -> Double { abs((p - origin).cross(direction)) }
        /// Tooltip form: "Horizontal", "Extension", "Angle 45°".
        var short: String {
            if let s = shortName { return s }
            switch kind {
            case .angle: return label.hasPrefix("ANGLE") ? "Angle" + label.dropFirst(5) : label.capitalized
            case .parallel: return "Parallel"
            case .perpendicular: return "Perpendicular"
            case .extension: return "Extension"
            case .nearest: return "Nearest"
            default: return kind.rawValue
            }
        }
        func project(_ p: Vec2) -> Vec2 { origin + direction * (p - origin).dot(direction) }
    }

    /// Status label for an element: "Walls : Basic Wall : Generic 200mm", "Lines : Model Lines".
    public func elementLabel(_ id: ElementID) -> String {
        guard let e = model[id] else { return "?" }
        if e.modelLine != nil { return "Lines : Model Lines" }
        if e.category == .detailLines { return "Lines : Detail Lines" }
        if let t = model.type(of: e), let td = t.typeData { return "\(e.category.displayName) : \(td.familyName) : \(t.name)" }
        return e.category.displayName + (e.name.isEmpty ? "" : " : \(e.name)")
    }

    /// Length increment for the rubber band at the current zoom: the smallest round step at least 8 points on screen.
    public var lengthIncrement: Double {
        let inches: [Double] = [0.0625, 0.125, 0.25, 0.5, 1, 3, 6, 12, 24, 60, 120, 240, 600]
        let metres: [Double] = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10, 50]
        let steps: [Double] = units.system == .imperial ? inches.map { $0 * 0.0254 } : metres
        let minimum = pixel * 8
        return steps.first { $0 >= minimum } ?? steps.last!
    }

    func pointLabel(_ s: SnapResult) -> String {
        let names = s.elementIDs.map { "[\(elementLabel($0))]" }
        let of = names.first ?? ""
        switch s.kind {
        case .endpoint: return "ENDPOINT of \(of)"
        case .midpoint: return "MIDPOINT of \(of)"
        case .center: return "CENTER of \(of)"
        case .quadrant: return "QUADRANT of \(of)"
        case .perpendicular: return "PERPENDICULAR to \(of)"
        case .tangent: return "TANGENT to \(of)"
        case .nearest: return "NEAREST to \(of)"
        case .intersection, .gridIntersection: return "INTERSECTION of " + names.joined(separator: " AND ")
        case .midBetweenPoints: return "MIDDLE of TWO POINTS"
        case .angle, .parallel, .extension: return s.kind.rawValue.uppercased()
        }
    }

    /// Guides available at `raw`: through the start point (angle increments, parallel/perpendicular) and extensions
    /// of visible lines passing near the pointer.
    func guides(near raw: Vec2, from: Vec2?, settings: SnapSettings, orthoOnly: Bool, tolerance: Double) -> [Guide] {
        var out: [Guide] = []
        if let f = from, (raw - f).length > pixel * 4 {
            if orthoOnly || settings.enabled.contains(.angle) {
                out.append(Guide(origin: f, direction: .unitX, label: "HORIZONTAL", kind: .angle, ids: [], anchor: f, throughStart: true))
                out.append(Guide(origin: f, direction: .unitY, label: "VERTICAL", kind: .angle, ids: [], anchor: f, throughStart: true))
                let inc = orthoOnly ? 90 : settings.angleIncrement > 0 ? max(settings.angleIncrement, 1)
                    : SnapSettings.adaptiveIncrement(pixels: (raw - f).length / max(pixel, 1e-12)) // I2
                let deg = (Angle.degrees((raw - f).angle) / inc).rounded() * inc
                let normalized = (deg.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
                if normalized > 1e-6, abs(normalized - 90) > 1e-6 {
                    out.append(Guide(origin: f, direction: Vec2.fromAngle(Angle.radians(deg), length: 1), label: String(format: "ANGLE %.0f°", normalized),
                                     kind: .angle, ids: [], anchor: f, throughStart: true))
                }
            }
            if !orthoOnly {
                for (d, id) in snapIndex.lineDirections(near: [raw, f], radius: pixel * 60, exclude: snapExclusions) + acquiredLines {
                    let name = id.map { " to [\(elementLabel($0))]" } ?? ""
                    if settings.enabled.contains(.parallel) {
                        out.append(Guide(origin: f, direction: d, label: "PARALLEL" + name, kind: .parallel, ids: id.map { [$0] } ?? [], anchor: f, throughStart: true))
                    }
                    if settings.enabled.contains(.perpendicular) {
                        out.append(Guide(origin: f, direction: Vec2(-d.y, d.x), label: "PERPENDICULAR" + name, kind: .perpendicular,
                                         ids: id.map { [$0] } ?? [], anchor: f, throughStart: true))
                    }
                }
            }
        }
        // Ends of lines parallel to the rubber band: a guide square to it through each end, so a wall drawn beside
        // another stops level with it.
        if let f = from, settings.enabled.contains(.extension), (raw - f).length > pixel * 12 {
            let v = raw - f
            var seen: [Double] = []
            let box = Rect2(center: raw, halfSize: Vec2(pixel * 600, pixel * 600))
            // Parallel: the pointer is within reach of the line through the start point in the line's direction.
            let lines = snapIndex.visibleLines(in: box, minimumLength: pixel * 12, exclude: snapExclusions)
                .filter { abs($0.seg.direction.cross(v)) <= tolerance * 2.5 && abs(($0.seg.start - f).cross($0.seg.direction)) > tolerance }
                .sorted { $0.seg.distance(to: raw) < $1.seg.distance(to: raw) }
            for l in lines.prefix(12) {
                let dd = l.seg.direction * (l.seg.direction.dot(v) < 0 ? -1 : 1), across = Vec2(-dd.y, dd.x)
                for e in [l.seg.start, l.seg.end] {
                    let along = (e - f).dot(dd)
                    guard along > tolerance, !seen.contains(where: { abs($0 - along) < pixel * 0.5 }) else { continue }
                    seen.append(along)
                    out.append(Guide(origin: e, direction: across, label: "ALIGNMENT with END of [\(l.id.map(elementLabel) ?? "line")]",
                                     kind: .extension, ids: l.id.map { [$0] } ?? [], anchor: e, throughStart: false, shortName: "Alignment"))
                }
            }
        }
        if settings.enabled.contains(.extension) {
            let ext = snapIndex.extensionLines(near: raw, radius: pixel * 900, tolerance: tolerance * 1.5, minimumLength: pixel * 12, exclude: snapExclusions)
            for e in ext.prefix(8) {
                out.append(Guide(origin: e.seg.start, direction: e.seg.direction, label: "EXTENSION of [\(e.id.map(elementLabel) ?? "line")]",
                                 kind: .extension, ids: e.id.map { [$0] } ?? [], anchor: e.end, throughStart: false))
            }
        }
        // Level with a neighbour: a horizontal or vertical guide through the nearest element centre or line end the
        // pointer lines up with, so a column placed beside another lands on its axis (dashed line, "Alignment").
        if settings.enabled.contains(.extension) {
            for a in snapIndex.alignedPoints(with: raw, tolerance: tolerance, reach: pixel * 600, exclude: snapExclusions) {
                if let f = from, a.p.distance(to: f) < tolerance { continue }
                let dir: Vec2 = a.vertical ? .unitY : .unitX
                // An extension of a horizontal or vertical line already runs through its end: one guide is enough.
                if out.contains(where: { abs($0.direction.cross(dir)) < 1e-9 && abs(($0.origin - a.p).cross(dir)) < tolerance * 0.1 }) { continue }
                let what = a.kind == .center ? "CENTER" : a.kind == .midpoint ? "MIDPOINT" : "END"
                out.append(Guide(origin: a.p, direction: dir, label: "ALIGNMENT with \(what) of [\(a.id.map(elementLabel) ?? "line")]",
                                 kind: .extension, ids: a.id.map { [$0] } ?? [], anchor: a.p, throughStart: false, shortName: "Alignment"))
            }
        }
        return out
    }

    /// Dashed guide for a snapped point on `g`: from its anchor through the point, a little beyond.
    func guideSegment(_ g: Guide, to p: Vec2) -> Segment2? {
        guard let a = g.anchor, a.distance(to: p) > pixel * 2 else { return nil }
        let d = (p - a).normalized
        return Segment2(a - d * pixel * 12, p + d * pixel * 24)
    }

    /// The snap engine (see the type comment). `from` is the start point of the element being drawn or dragged.
    func resolveSnap(_ raw: Vec2, from: Vec2?, settings: SnapSettings, orthoOnly: Bool) -> (Vec2, SnapResult?) {
        guard settings.snapsOn else { return (raw, nil) }
        let radius = settings.pixelRadius * pixel
        let tolerance = pixel * 6
        let object = snapIndex.snap(raw, radius: radius, from: from, settings: settings, exclude: snapExclusions)
        var all = guides(near: raw, from: from, settings: settings, orthoOnly: orthoOnly, tolerance: tolerance)

        // 1. Point snaps. Name the start point's horizontal/vertical when the point also lies on it.
        if var o = object, o.kind != .nearest {
            var label = pointLabel(o)
            var guidesToDraw: [Segment2] = []
            var short = o.kind.rawValue
            for g in all where g.throughStart && g.kind == .angle && g.distance(to: o.point) < pixel * 0.5 && !g.label.hasPrefix("ANGLE") {
                label += " AND \(g.label)"
                short += " and \(g.short)"
                if let s = guideSegment(g, to: o.point) { guidesToDraw.append(s) }
            }
            o.label = label
            o.shortLabel = short
            o.guides = guidesToDraw
            return (o.point, o)
        }

        // The line under the pointer takes part in guide intersections.
        if let o = object, let (seg, id) = snapIndex.nearestSegment(raw, radius: radius, visibleOnly: true) {
            all.append(Guide(origin: seg.start, direction: seg.direction, label: "[\(id.map(elementLabel) ?? "line")]", kind: .nearest,
                             ids: id.map { [$0] } ?? o.elementIDs, anchor: nil, throughStart: false))
        }

        // 2. Crossings of two guides near the pointer.
        let near = all.filter { $0.distance(to: raw) <= tolerance * 2.5 }
        var best: (p: Vec2, d: Double, a: Int, b: Int)?
        if near.count >= 2 {
            for i in 0..<near.count {
                for j in (i + 1)..<near.count {
                    let a = near[i], b = near[j]
                    let den = a.direction.cross(b.direction)
                    // Guides meeting at less than ~2° cross somewhere arbitrary along their length: not a useful point.
                    guard abs(den) > 0.035 else { continue }
                    let t = (b.origin - a.origin).cross(b.direction) / den
                    let q = a.origin + a.direction * t
                    let d = q.distance(to: raw)
                    if let f = from, a.throughStart && b.throughStart && q.distance(to: f) < pixel { continue }
                    guard d <= tolerance * 1.5, d < (best?.d ?? .infinity) else { continue }
                    best = (q, d, i, j)
                }
            }
        }
        if let b = best {
            let on = near.enumerated().filter { $0.offset == b.a || $0.offset == b.b || $0.element.distance(to: b.p) < pixel * 0.5 }.map(\.element)
            let parts = on.map { $0.kind == .nearest ? $0.label : $0.label }
            var r = SnapResult(point: b.p, kind: .intersection, elementIDs: on.flatMap(\.ids))
            r.label = "INTERSECTION of " + parts.joined(separator: " AND ")
            var shorts: [String] = []
            for g in on where !shorts.contains(g.short) { shorts.append(g.short) }
            r.shortLabel = shorts.count == 1 ? "Intersection of \(shorts[0])s" : shorts.joined(separator: " and ")
            r.guides = on.compactMap { guideSegment($0, to: b.p) }
            return (b.p, r)
        }

        // 3. Nearest point on a visible line.
        if var o = object {
            o.label = pointLabel(o)
            o.shortLabel = o.kind.rawValue
            return (o.point, o)
        }

        // 4. A single guide (the closest), rounding the length from the start point along it.
        if let g = all.filter({ $0.kind != .nearest && $0.distance(to: raw) <= tolerance }).min(by: { $0.distance(to: raw) < $1.distance(to: raw) }) {
            var p = g.project(raw)
            if let f = from, g.throughStart {
                let step = lengthIncrement
                let along = (p - f).dot(g.direction)
                p = f + g.direction * ((along / step).rounded() * step)
            }
            var r = SnapResult(point: p, kind: g.kind, elementIDs: g.ids)
            r.label = g.label
            r.shortLabel = g.short
            r.guides = [guideSegment(g, to: p)].compactMap { $0 }
            return (p, r)
        }

        // 5. Free: round the rubber band's length.
        if let f = from {
            let v = raw - f
            let len = v.length
            guard len > pixel * 4 else { return (raw, nil) }
            let step = lengthIncrement
            let rounded = max(step, (len / step).rounded() * step)
            return (f + v / len * rounded, nil)
        }
        return (raw, nil)
    }
}
