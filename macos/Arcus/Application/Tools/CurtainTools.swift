import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Picking curtain walls

/// A point on a curtain wall under the cursor: the wall, its layout, the station along it and the absolute elevation.
struct CurtainPick {
    var wall: Element
    var frame: WallFrame
    var layout: CurtainLayout
    var station: Double
    var z: Double
    var instance: CurtainInstanceData { wall.wall?.curtain ?? CurtainInstanceData() }
}

/// Maps between view coordinates and curtain wall (station, elevation) in plans and in elevations/sections.
@MainActor
enum CurtainPicking {
    /// Elevation used for picks in plan views: the view's cut plane.
    static func planZ(_ ctx: ToolContext) -> Double {
        ctx.levelElevation + (ctx.viewData?.viewRange.cutOffset ?? 1.2)
    }

    /// The curtain wall under the cursor, nearest the viewer. Plans pick along the wall's thickness; elevations and
    /// sections pick inside the wall's elevation outline.
    static func pick(_ i: ToolInput, _ ctx: ToolContext) -> CurtainPick? {
        let m = ctx.model
        if ctx.isPlan {
            let tol = ctx.pixel * 8
            let p = i.rawPoint
            let cands = m.elements(.walls, intersecting: Rect2(center: p, halfSize: Vec2(tol + 1, tol + 1)))
            var best: (CurtainPick, Double)?
            for w in cands where CurtainWallGeometry.isCurtain(w, m) {
                guard let f = WallGeometry.frame(w, m), let l = CurtainWallGeometry.layout(w, m) else { continue }
                let d = f.location.distance(to: p)
                guard d <= f.thickness / 2 + tol + abs(f.centerOffset) else { continue }
                let s = WallGeometry.station(of: f.location.closestPoint(to: p), on: f.location)
                let z = min(max(planZ(ctx), f.baseZ + 1e-6), f.topZ - 1e-6)
                if best == nil || d < best!.1 { best = (CurtainPick(wall: w, frame: f, layout: l, station: min(max(s, 0), f.length), z: z), d) }
            }
            return best?.0
        }
        guard ctx.isVertical, let vd = ctx.viewData, let o = vd.planeOrigin, let fwd = vd.viewDirection?.normalized else { return nil }
        let p = i.rawPoint
        var best: (CurtainPick, Double)?
        let ordered = ([i.hit].compactMap { $0 } + i.hitCandidates).compactMap { m[$0] }.filter { $0.wall != nil }
        let others = m.elements(.walls).filter { w in !ordered.contains { $0.id == w.id } }
        for w in ordered + others where CurtainWallGeometry.isCurtain(w, m) {
            guard let f = WallGeometry.frame(w, m), p.y >= f.baseZ - 1e-9, p.y <= f.topZ + 1e-9,
                  let s = CurtainWallGeometry.station(ofViewU: p.x, view: vd, wall: f), s >= -1e-6, s <= f.length + 1e-6,
                  let l = CurtainWallGeometry.layout(w, m) else { continue }
            let pt = WallGeometry.point(atStation: s, on: f.location)
            let depth = (pt - o.xy).dot(fwd)
            guard depth >= -0.01, depth <= vd.farClip else { continue }
            if best == nil || depth < best!.1 { best = (CurtainPick(wall: w, frame: f, layout: l, station: min(max(s, 0), f.length), z: p.y), depth) }
        }
        return best?.0
    }

    /// View coordinate of a wall station: plan XY on the wall's centre curve, or (u, ·) in vertical views.
    static func viewPoint(station s: Double, z: Double, _ f: WallFrame, _ ctx: ToolContext) -> Vec2? {
        let c = f.location.offset(by: f.centerOffset)
        let p = c.point(at: f.length > 0 ? min(1, max(0, s / f.length)) : 0)
        if ctx.isPlan { return p }
        guard let vd = ctx.viewData, let o = vd.planeOrigin, let r = vd.rightVector else { return nil }
        return Vec2((p - o.xy).dot(r), z)
    }

    /// Preview of a vertical grid line (station) or horizontal grid line (elevation) across a curtain wall.
    static func gridLine(vertical: Bool, position: Double, from a: Double, to b: Double, _ f: WallFrame, _ ctx: ToolContext) -> [Vec2] {
        if vertical {
            if ctx.isPlan {
                let t = f.length > 0 ? min(1, max(0, position / f.length)) : 0
                let p = f.location.offset(by: f.centerOffset).point(at: t), n = f.location.normal(at: t) * (f.thickness / 2 + ctx.pixel * 6)
                return [p - n, p + n]
            }
            return [viewPoint(station: position, z: a, f, ctx), viewPoint(station: position, z: b, f, ctx)].compactMap { $0 }
        }
        guard !ctx.isPlan else { return [] }
        let steps = f.isStraight ? 1 : 24
        return (0...steps).compactMap { k in viewPoint(station: a + (b - a) * Double(k) / Double(steps), z: position, f, ctx) }
    }
}

// MARK: - Curtain Grid

/// Adds grid lines to curtain walls (and removes grid lines that were added by hand).
@MainActor
public final class CurtainGridTool: BaseTool, InteractiveTool {
    public enum Orientation: String, CaseIterable { case automatic = "Automatic", vertical = "Vertical", horizontal = "Horizontal" }
    public let commandID = CommandID.curtainGrid
    public let title = "Curtain Grid"
    public var orientation: Orientation = .automatic
    struct Hover { var pick: CurtainPick; var vertical: Bool; var position: Double; var manual: Double? }
    var hover: Hover?

    public var prompt: String {
        guard ctx.isPlan || ctx.isVertical else { return "Add curtain grids in a plan, elevation or section." }
        if let h = hover, h.manual != nil { return "Click to remove this grid line." }
        return ctx.isPlan ? "Click a curtain wall to add a vertical grid line, or type the distance from the previous grid line."
            : "Click a curtain wall to add a grid line: near its top or bottom edge for a vertical line, near its ends for a horizontal one. Click a grid line you added to remove it."
    }
    public var numericLabel: String? { hover == nil ? nil : "Distance" }
    public var options: [ToolOption] {
        [ToolOption(id: "orientation", label: "Grid", kind: .choice(Orientation.allCases.map(\.rawValue)), value: .text(orientation.rawValue))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "orientation", let o = Orientation(rawValue: value.textValue ?? "") { orientation = o }
    }

    func resolve(_ i: ToolInput) -> Hover? {
        guard let pick = CurtainPicking.pick(i, ctx) else { return nil }
        let l = pick.layout
        var vertical: Bool
        switch orientation {
        case .vertical: vertical = true
        case .horizontal: vertical = false
        case .automatic:
            let dz = min(pick.z - l.baseZ, l.topZ - pick.z), ds = min(pick.station, l.length - pick.station)
            vertical = ctx.isPlan || dz <= ds
        }
        if ctx.isPlan { vertical = true }
        let tol = ctx.pixel * 6
        var pos = vertical ? pick.station : pick.z - l.baseZ
        let extent = vertical ? l.length : l.topZ - l.baseZ
        // A grid line added by hand under the cursor is removed instead.
        let manual = (vertical ? pick.instance.verticalGrids : pick.instance.horizontalGrids).min { abs($0 - pos) < abs($1 - pos) }
        if let m = manual, abs(m - pos) <= tol { return Hover(pick: pick, vertical: vertical, position: m, manual: m) }
        // Snap to the middle of the panel.
        let lines = vertical ? l.stations : l.heights.map { $0 - l.baseZ }
        if let k = lines.indices.dropLast().first(where: { lines[$0] <= pos && pos <= lines[$0 + 1] }) {
            let mid = (lines[k] + lines[k + 1]) / 2
            if abs(mid - pos) <= tol { pos = mid }
        }
        guard pos > 0.001, pos < extent - 0.001 else { return nil }
        if lines.contains(where: { abs($0 - pos) < 0.001 }) { return nil }
        return Hover(pick: pick, vertical: vertical, position: pos, manual: nil)
    }

    public func pointerMoved(_ i: ToolInput) {
        hover = resolve(i)
        rebuildPreview()
    }

    func rebuildPreview() {
        preview = ToolPreview()
        guard let h = hover else { return }
        let f = h.pick.frame, l = h.pick.layout
        let st = h.manual != nil ? GStroke(weight: 3, color: RGBColor(0.8, 0.25, 0.2), pattern: .dash) : GStroke(weight: 3, color: RGBColor(0.18, 0.43, 0.66), pattern: .dash)
        let pts = h.vertical ? CurtainPicking.gridLine(vertical: true, position: h.position, from: l.baseZ, to: l.topZ, f, ctx)
                             : CurtainPicking.gridLine(vertical: false, position: l.baseZ + h.position, from: 0, to: l.length, f, ctx)
        if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: false, st)) }
        preview.highlight = [h.pick.wall.id]
        // Distances to the neighbouring grid lines.
        if h.manual == nil {
            let lines = h.vertical ? l.stations : l.heights.map { $0 - l.baseZ }
            let prev = lines.last { $0 < h.position } ?? 0, next = lines.first { $0 > h.position } ?? h.position
            let z = h.pick.z
            func vp(_ v: Double) -> Vec2? {
                h.vertical ? CurtainPicking.viewPoint(station: v, z: z, f, ctx) : CurtainPicking.viewPoint(station: h.pick.station, z: l.baseZ + v, f, ctx)
            }
            if let a = vp(prev), let b = vp(h.position), let c = vp(next) {
                preview.tempDims = [TemporaryDimension(from: a, to: b, text: ctx.format(h.position - prev), isAngle: false, isActive: true),
                                    TemporaryDimension(from: b, to: c, text: ctx.format(next - h.position), isAngle: false, isActive: false)]
            }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan || ctx.isVertical else { message("Open a plan, elevation or section to add curtain grids."); return }
        guard let h = resolve(i) else { message("Click inside a curtain wall, away from its existing grid lines."); return }
        apply(h, position: h.position, remove: h.manual != nil)
        hover = nil
        pointerMoved(i)
    }

    func apply(_ h: Hover, position: Double, remove: Bool) {
        let id = h.pick.wall.id
        ctx.session.perform(remove ? "Remove Curtain Grid" : "Add Curtain Grid") { tx in
            tx.update(id) { e in
                var c = e.wall?.curtain ?? CurtainInstanceData()
                if h.vertical {
                    if remove { c.verticalGrids.removeAll { abs($0 - position) < 1e-9 } } else { c.verticalGrids = (c.verticalGrids + [position]).sorted() }
                } else {
                    if remove { c.horizontalGrids.removeAll { abs($0 - position) < 1e-9 } } else { c.horizontalGrids = (c.horizontalGrids + [position]).sorted() }
                }
                e.wall?.curtain = c
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    /// Places a grid line at a typed distance from the previous grid line (toward the cursor).
    public func numericInput(_ text: String) -> Bool {
        guard let h = hover, h.manual == nil, let d = ctx.parse(text), d > 0.001 else { return false }
        let l = h.pick.layout
        let lines = h.vertical ? l.stations : l.heights.map { $0 - l.baseZ }
        let prev = lines.last { $0 < h.position } ?? 0
        let pos = prev + d
        let extent = h.vertical ? l.length : l.topZ - l.baseZ
        guard pos < extent - 0.001, !lines.contains(where: { abs($0 - pos) < 0.001 }) else { message("That distance falls outside the panel."); return false }
        apply(h, position: pos, remove: false)
        hover = nil
        preview = ToolPreview()
        return true
    }

    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Mullion

/// Adds mullions to curtain grid lines, or removes them where they already exist.
@MainActor
public final class MullionTool: BaseTool, InteractiveTool {
    public enum Placement: String, CaseIterable { case segment = "Grid Line Segment", line = "Grid Line", all = "All Grid Lines" }
    public let commandID = CommandID.mullion
    public let title = "Mullion"
    public var placement: Placement = .segment
    struct Target { var pick: CurtainPick; var vertical: Bool; var position: Double; var from: Double; var to: Double; var present: Bool }
    var target: Target?

    public var prompt: String {
        guard ctx.isPlan || ctx.isVertical else { return "Add mullions in a plan, elevation or section." }
        switch placement {
        case .all: return "Click a curtain wall to put mullions on all of its grid lines."
        default:
            if let t = target, t.present { return "Click to remove the mullion from this grid line\(placement == .segment ? " segment" : "")." }
            return "Click a curtain grid line to add a mullion\(placement == .segment ? " to that segment" : "")."
        }
    }
    public var options: [ToolOption] {
        [ToolOption(id: "placement", label: "Placement", kind: .choice(Placement.allCases.map(\.rawValue)), value: .text(placement.rawValue))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "placement", let p = Placement(rawValue: value.textValue ?? "") { placement = p }
    }

    func resolve(_ i: ToolInput) -> Target? {
        guard let pick = CurtainPicking.pick(i, ctx) else { return nil }
        let l = pick.layout
        let tol = max(ctx.pixel * 8, l.mullions.first?.profile.width ?? 0)
        let H = l.topZ - l.baseZ
        // Nearest grid line: vertical (by station) or horizontal (by elevation; not in plans).
        let vs = l.stations.min { abs($0 - pick.station) < abs($1 - pick.station) } ?? 0
        let hs = l.heights.min { abs($0 - pick.z) < abs($1 - pick.z) } ?? l.baseZ
        let dv = abs(vs - pick.station), dh = abs(hs - pick.z)
        let vertical = ctx.isPlan || dv <= dh
        guard placement == .all || (vertical ? dv : dh) <= tol else { return nil }
        if vertical {
            let rows = l.heights
            let j = rows.indices.dropLast().first { rows[$0] <= pick.z && pick.z <= rows[$0 + 1] } ?? 0
            let (a, b) = placement == .segment ? (rows[j] - l.baseZ, rows[j + 1] - l.baseZ) : (0, H)
            let present = l.mullions.filter { $0.isVertical && abs($0.position - vs) < 1e-9 && ($0.from + $0.to) / 2 - l.baseZ > a && ($0.from + $0.to) / 2 - l.baseZ < b }
            let segments = rows.indices.dropLast().filter { (rows[$0] + rows[$0 + 1]) / 2 - l.baseZ > a && (rows[$0] + rows[$0 + 1]) / 2 - l.baseZ < b }.count
            return Target(pick: pick, vertical: true, position: vs, from: a, to: b, present: present.count == segments && segments > 0)
        }
        let cols = l.stations
        let k = cols.indices.dropLast().first { cols[$0] <= pick.station && pick.station <= cols[$0 + 1] } ?? 0
        let (a, b) = placement == .segment ? (cols[k], cols[k + 1]) : (0, l.length)
        let present = l.mullions.filter { !$0.isVertical && abs($0.position - hs) < 1e-9 && ($0.from + $0.to) / 2 > a && ($0.from + $0.to) / 2 < b }
        let segments = cols.indices.dropLast().filter { (cols[$0] + cols[$0 + 1]) / 2 > a && (cols[$0] + cols[$0 + 1]) / 2 < b }.count
        return Target(pick: pick, vertical: false, position: hs - l.baseZ, from: a, to: b, present: present.count == segments && segments > 0)
    }

    public func pointerMoved(_ i: ToolInput) {
        target = resolve(i)
        preview = ToolPreview()
        guard let t = target else { return }
        let f = t.pick.frame, l = t.pick.layout
        preview.highlight = [t.pick.wall.id]
        guard placement != .all else { return }
        let st = GStroke(weight: 4, color: t.present ? RGBColor(0.8, 0.25, 0.2) : RGBColor(0.18, 0.43, 0.66))
        let pts = t.vertical ? CurtainPicking.gridLine(vertical: true, position: t.position, from: l.baseZ + t.from, to: l.baseZ + t.to, f, ctx)
                             : CurtainPicking.gridLine(vertical: false, position: l.baseZ + t.position, from: t.from, to: t.to, f, ctx)
        if pts.count >= 2 { preview.primitives.append(.polyline(pts, closed: false, st)) }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan || ctx.isVertical else { message("Open a plan, elevation or section to add mullions."); return }
        guard let t = resolve(i) else { message("Click on a curtain grid line."); return }
        let id = t.pick.wall.id
        let l = t.pick.layout
        var overrides: [CurtainMullionOverride] = []
        if placement == .all {
            let H = l.topZ - l.baseZ
            overrides = l.stations.map { CurtainMullionOverride(isVertical: true, position: $0, from: 0, to: H, present: true) }
                + l.heights.map { CurtainMullionOverride(isVertical: false, position: $0 - l.baseZ, from: 0, to: l.length, present: true) }
        } else {
            overrides = [CurtainMullionOverride(isVertical: t.vertical, position: t.position, from: t.from, to: t.to, present: !t.present)]
        }
        ctx.session.perform(placement != .all && t.present ? "Remove Mullion" : "Add Mullion") { tx in
            tx.update(id) { e in
                var c = e.wall?.curtain ?? CurtainInstanceData()
                for o in overrides {
                    // Earlier overrides that the new one covers completely no longer matter.
                    c.mullions.removeAll { $0.isVertical == o.isVertical && abs($0.position - o.position) < 1e-6
                        && min($0.from, $0.to) >= o.from - 1e-6 && max($0.from, $0.to) <= o.to + 1e-6 }
                    c.mullions.append(o)
                }
                e.wall?.curtain = c
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
        pointerMoved(i)
    }

    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Curtain Panel

/// Swaps curtain panels to the panel type chosen in the type selector (glazed, solid, empty or any duplicated type).
@MainActor
public final class CurtainPanelTool: BaseTool, InteractiveTool {
    public enum Scope: String, CaseIterable { case panel = "Panel", row = "Row", column = "Column", all = "All Panels" }
    public let commandID = CommandID.curtainPanel
    public let title = "Curtain Panel"
    public var scope: Scope = .panel
    var hover: (pick: CurtainPick, panel: CurtainPanel)?

    public var prompt: String {
        guard ctx.isPlan || ctx.isVertical else { return "Swap curtain panels in a plan, elevation or section." }
        let name = ctx.type(for: .curtainPanels).flatMap { ctx.model[$0]?.name } ?? "the chosen panel type"
        return "Choose a panel type in the type selector, then click panels to change them to \(name)."
    }
    public var options: [ToolOption] {
        [ToolOption(id: "scope", label: "Apply to", kind: .choice(Scope.allCases.map(\.rawValue)), value: .text(scope.rawValue))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "scope", let s = Scope(rawValue: value.textValue ?? "") { scope = s }
    }

    func panels(_ h: (pick: CurtainPick, panel: CurtainPanel)) -> [CurtainPanel] {
        let all = h.pick.layout.panels
        switch scope {
        case .panel: return [h.panel]
        case .row: return all.filter { $0.row == h.panel.row }
        case .column: return all.filter { $0.column == h.panel.column }
        case .all: return all
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        hover = CurtainPicking.pick(i, ctx).flatMap { p in p.layout.panel(atStation: p.station, z: p.z).map { (p, $0) } }
        guard let h = hover else { return }
        preview.highlight = [h.pick.wall.id]
        let st = GStroke(weight: 3, color: RGBColor(0.18, 0.43, 0.66))
        for p in panels(h) {
            if ctx.isPlan {
                if let a = CurtainPicking.viewPoint(station: p.s0, z: 0, h.pick.frame, ctx), let b = CurtainPicking.viewPoint(station: p.s1, z: 0, h.pick.frame, ctx) {
                    preview.primitives.append(.polyline([a, b], closed: false, st))
                }
            } else if let a = CurtainPicking.viewPoint(station: p.s0, z: p.z0, h.pick.frame, ctx), let b = CurtainPicking.viewPoint(station: p.s1, z: p.z1, h.pick.frame, ctx) {
                preview.primitives.append(.polyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, st))
            }
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan || ctx.isVertical else { message("Open a plan, elevation or section to swap curtain panels."); return }
        pointerMoved(i)
        guard let h = hover else { message("Click a curtain wall panel."); return }
        guard let typeID = ctx.type(for: .curtainPanels) else { message("The project has no curtain panel types."); return }
        let targets = panels(h)
        let base = h.pick.layout.baseZ
        let id = h.pick.wall.id
        ctx.session.perform("Change Curtain Panel") { tx in
            tx.update(id) { e in
                var c = e.wall?.curtain ?? CurtainInstanceData()
                for p in targets {
                    // One override per panel: drop older seeds inside this cell.
                    c.panels.removeAll { $0.station >= p.s0 - 1e-6 && $0.station <= p.s1 + 1e-6 && base + $0.height >= p.z0 - 1e-6 && base + $0.height <= p.z1 + 1e-6 }
                    c.panels.append(CurtainPanelOverride(station: (p.s0 + p.s1) / 2, height: (p.z0 + p.z1) / 2 - base, typeID: typeID))
                }
                e.wall?.curtain = c
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
        pointerMoved(i)
    }

    public func escape() -> EscapeResult { .exitTool }
}
