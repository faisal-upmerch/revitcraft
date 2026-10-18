import Foundation
import ArcusGeometry

/// One panel of a curtain wall: the cell between two vertical and two horizontal grid lines.
public struct CurtainPanel: Sendable, Hashable {
    /// Column (along the wall, from its start) and row (from the base) of the cell.
    public var column: Int
    public var row: Int
    /// Grid stations (meters from the wall start) and absolute elevations bounding the cell.
    public var s0: Double
    public var s1: Double
    public var z0: Double
    public var z1: Double
    public var typeID: ElementID?
    public var kind: CurtainPanelKind
    public var thickness: Double
    public var materialID: ElementID?
    /// Area of the grid cell (meters²).
    public var area: Double { max(0, s1 - s0) * max(0, z1 - z0) }
}

/// One mullion: the part of a grid line between two crossing grid lines.
public struct CurtainMullion: Sendable, Hashable {
    public var isVertical: Bool
    public var isBorder: Bool
    /// Grid position: a station for vertical mullions, an absolute elevation for horizontal ones.
    public var position: Double
    /// Extent along the grid line: absolute elevations (vertical) or stations (horizontal).
    public var from: Double
    public var to: Double
    public var profile: MullionProfile
    public var length: Double { max(0, to - from) }
}

/// The regenerated grid, panels and mullions of one curtain wall.
public struct CurtainLayout: Sendable {
    public var length: Double
    public var baseZ: Double
    public var topZ: Double
    /// All vertical grid stations including both ends (0 … length), ascending.
    public var stations: [Double]
    /// All horizontal grid elevations including base and top, ascending (absolute).
    public var heights: [Double]
    public var panels: [CurtainPanel]
    public var mullions: [CurtainMullion]

    public var interiorStations: [Double] { Array(stations.dropFirst().dropLast()) }
    public var interiorHeights: [Double] { Array(heights.dropFirst().dropLast()) }
    public var interiorMullions: [CurtainMullion] { mullions.filter { !$0.isBorder } }
    public var mullionLength: Double { mullions.reduce(0) { $0 + $1.length } }

    /// The panel containing a point given as (station, absolute elevation).
    public func panel(atStation s: Double, z: Double) -> CurtainPanel? {
        panels.first { s >= $0.s0 - 1e-9 && s <= $0.s1 + 1e-9 && z >= $0.z0 - 1e-9 && z <= $0.z1 + 1e-9 }
    }

    /// Vertical mullion present on grid station index `i` in row `j`.
    func verticalMullion(atStation s: Double, row z0: Double, _ z1: Double) -> CurtainMullion? {
        let mid = (z0 + z1) / 2
        return mullions.first { $0.isVertical && abs($0.position - s) < 1e-6 && mid > $0.from && mid < $0.to }
    }
    func horizontalMullion(atZ z: Double, column s0: Double, _ s1: Double) -> CurtainMullion? {
        let mid = (s0 + s1) / 2
        return mullions.first { !$0.isVertical && abs($0.position - z) < 1e-6 && mid > $0.from && mid < $0.to }
    }
}

/// Regeneration of curtain walls: walls whose type carries a `CurtainSpec`. The wall's location line is the panel
/// plane; panels are flat between grid lines (so curved curtain walls are faceted at their vertical grid lines).
public enum CurtainWallGeometry {
    static let gridTolerance = 0.001
    public static let defaultPanelThickness = 0.025

    public static func spec(_ e: Element, _ model: BIMModel) -> CurtainSpec? {
        guard e.wall != nil else { return nil }
        return model.typeData(of: e)?.curtain
    }

    public static func isCurtain(_ e: Element, _ model: BIMModel) -> Bool { spec(e, model) != nil }

    /// Kind, thickness and material of a curtain panel type (glazed when the type is missing).
    public static func panelInfo(_ typeID: ElementID?, _ model: BIMModel) -> (kind: CurtainPanelKind, thickness: Double, materialID: ElementID?) {
        guard let td = model[typeID]?.typeData, td.instanceCategory == .curtainPanels else {
            return (.glazed, defaultPanelThickness, model.material(named: "Glass")?.id)
        }
        let kind = td.params[.curtainPanelKind]?.textValue.flatMap(CurtainPanelKind.init(rawValue:)) ?? .glazed
        let t = td.params[.curtainPanelThickness]?.doubleValue ?? defaultPanelThickness
        return (kind, max(0.001, t), td.params[.curtainPanelMaterial]?.refValue)
    }

    static func merged(_ values: [Double]) -> [Double] {
        var out: [Double] = []
        for v in values.sorted() where out.last.map({ v - $0 > gridTolerance }) ?? true { out.append(v) }
        return out
    }

    /// Full layout: type grid rules plus manual grid lines, panels with overrides, and mullions with overrides.
    public static func layout(_ e: Element, _ model: BIMModel) -> CurtainLayout? {
        guard let w = e.wall, let spec = spec(e, model), let f = WallGeometry.frame(e, model) else { return nil }
        let L = f.length, H = f.height
        guard L > gridTolerance * 2, H > gridTolerance * 2 else { return nil }
        let inst = w.curtain ?? CurtainInstanceData()
        let tol = gridTolerance
        let vs = merged(spec.vertical.positions(length: L) + inst.verticalGrids.filter { $0 > tol && $0 < L - tol })
        let hs = merged(spec.horizontal.positions(length: H) + inst.horizontalGrids.filter { $0 > tol && $0 < H - tol })
        let stations = [0] + vs + [L]
        let heights = ([0] + hs + [H]).map { f.baseZ + $0 }

        // Mullions: one per grid-line segment between crossing grid lines.
        func overridden(_ vertical: Bool, _ position: Double, _ mid: Double) -> Bool? {
            inst.mullions.last { $0.isVertical == vertical && abs($0.position - position) < tol
                && mid >= min($0.from, $0.to) - tol && mid <= max($0.from, $0.to) + tol }?.present
        }
        var mullions: [CurtainMullion] = []
        for (i, s) in stations.enumerated() {
            let border = i == 0 || i == stations.count - 1
            for j in 0..<(heights.count - 1) {
                let z0 = heights[j], z1 = heights[j + 1]
                let present = overridden(true, s, (z0 + z1) / 2 - f.baseZ) ?? (border ? spec.borderMullions : spec.verticalMullions)
                if present { mullions.append(CurtainMullion(isVertical: true, isBorder: border, position: s, from: z0, to: z1, profile: spec.mullion)) }
            }
        }
        for (j, z) in heights.enumerated() {
            let border = j == 0 || j == heights.count - 1
            for i in 0..<(stations.count - 1) {
                let s0 = stations[i], s1 = stations[i + 1]
                let present = overridden(false, z - f.baseZ, (s0 + s1) / 2) ?? (border ? spec.borderMullions : spec.horizontalMullions)
                if present { mullions.append(CurtainMullion(isVertical: false, isBorder: border, position: z, from: s0, to: s1, profile: spec.mullion)) }
            }
        }

        // Panels.
        var panels: [CurtainPanel] = []
        for i in 0..<(stations.count - 1) {
            for j in 0..<(heights.count - 1) {
                let s0 = stations[i], s1 = stations[i + 1], z0 = heights[j], z1 = heights[j + 1]
                var typeID = spec.panelTypeID
                if let o = inst.panels.last(where: { $0.station >= s0 - tol && $0.station <= s1 + tol
                    && f.baseZ + $0.height >= z0 - tol && f.baseZ + $0.height <= z1 + tol }) {
                    typeID = o.typeID
                }
                let info = panelInfo(typeID, model)
                panels.append(CurtainPanel(column: i, row: j, s0: s0, s1: s1, z0: z0, z1: z1, typeID: typeID,
                                           kind: info.kind, thickness: info.thickness, materialID: info.materialID))
            }
        }
        return CurtainLayout(length: L, baseZ: f.baseZ, topZ: f.topZ, stations: stations, heights: heights, panels: panels, mullions: mullions)
    }

    // MARK: Placement helpers

    /// The panel plane: the wall's centre curve (the location curve offset to the middle of the nominal thickness).
    static func centerCurve(_ f: WallFrame) -> Curve2 { f.location.offset(by: f.centerOffset) }

    static func point(_ c: Curve2, station s: Double, length L: Double) -> Vec2 { c.point(at: L > 0 ? min(1, max(0, s / L)) : 0) }
    static func tangent(_ c: Curve2, station s: Double, length L: Double) -> Vec2 { c.tangent(at: L > 0 ? min(1, max(0, s / L)) : 0) }

    /// Inset of a vertical mullion's near face from its grid station (border mullions sit inside the wall ends).
    static func verticalInset(_ m: CurtainMullion?, side: Double, length L: Double) -> Double {
        guard let m else { return 0 }
        if m.isBorder { return m.position < L / 2 ? (side > 0 ? m.profile.width : 0) : (side < 0 ? m.profile.width : 0) }
        return m.profile.width / 2
    }
    /// Station range [a, b] of a vertical mullion's body.
    static func verticalSpan(_ m: CurtainMullion, length L: Double) -> (Double, Double) {
        let w = m.profile.width
        if m.isBorder { return m.position < L / 2 ? (0, w) : (L - w, L) }
        return (m.position - w / 2, m.position + w / 2)
    }
    /// Elevation range of a horizontal mullion's body.
    static func horizontalSpan(_ m: CurtainMullion, _ layout: CurtainLayout) -> (Double, Double) {
        let w = m.profile.width
        if m.isBorder { return m.position < (layout.baseZ + layout.topZ) / 2 ? (layout.baseZ, layout.baseZ + w) : (layout.topZ - w, layout.topZ) }
        return (m.position - w / 2, m.position + w / 2)
    }

    /// Plan quad of a straight run between two points on the centre curve, `depth` thick across it.
    static func quad(_ a: Vec2, _ b: Vec2, depth: Double) -> Polygon2? {
        let v = b - a
        guard v.length > Tolerance.length, depth > Tolerance.length else { return nil }
        let n = v.normalized.perpendicular * (depth / 2)
        return Polygon2([a - n, b - n, b + n, a + n]).counterClockwise
    }
    /// Plan footprint of a vertical mullion: a width × depth rectangle square to the wall at its station.
    static func verticalFootprint(_ m: CurtainMullion, _ c: Curve2, length L: Double) -> Polygon2? {
        let (a, b) = verticalSpan(m, length: L)
        let mid = (a + b) / 2
        let p = point(c, station: mid, length: L), t = tangent(c, station: mid, length: L)
        return quad(p - t * (m.profile.width / 2), p + t * (m.profile.width / 2), depth: m.profile.depth)
    }

    /// Stations of a horizontal mullion's body after trimming against the vertical mullions it meets.
    static func horizontalRun(_ m: CurtainMullion, _ layout: CurtainLayout) -> (Double, Double) {
        let (z0, z1) = horizontalSpan(m, layout)
        let zmid = (z0 + z1) / 2
        func vertical(at s: Double) -> CurtainMullion? {
            layout.mullions.first { $0.isVertical && abs($0.position - s) < 1e-6 && zmid >= $0.from - 1e-9 && zmid <= $0.to + 1e-9 }
        }
        let a = m.from + verticalInset(vertical(at: m.from), side: 1, length: layout.length)
        let b = m.to - verticalInset(vertical(at: m.to), side: -1, length: layout.length)
        return (a, b)
    }

    /// Station and elevation extents of a panel after trimming to the faces of the mullions around it.
    static func panelExtents(_ p: CurtainPanel, _ layout: CurtainLayout) -> (s0: Double, s1: Double, z0: Double, z1: Double) {
        let L = layout.length
        let left = layout.verticalMullion(atStation: p.s0, row: p.z0, p.z1)
        let right = layout.verticalMullion(atStation: p.s1, row: p.z0, p.z1)
        let bottom = layout.horizontalMullion(atZ: p.z0, column: p.s0, p.s1)
        let top = layout.horizontalMullion(atZ: p.z1, column: p.s0, p.s1)
        let s0 = p.s0 + verticalInset(left, side: 1, length: L)
        let s1 = p.s1 - verticalInset(right, side: -1, length: L)
        let z0 = bottom.map { horizontalSpan($0, layout).1 } ?? p.z0
        let z1 = top.map { horizontalSpan($0, layout).0 } ?? p.z1
        return (s0, s1, z0, z1)
    }

    // MARK: 3D

    /// Solid of each non-empty panel, trimmed to the faces of the mullions around it.
    public static func panelSolids(_ e: Element, _ model: BIMModel) -> [(panel: CurtainPanel, mesh: Mesh)] {
        guard let f = WallGeometry.frame(e, model), let layout = layout(e, model) else { return [] }
        let c = centerCurve(f), L = layout.length
        var out: [(CurtainPanel, Mesh)] = []
        for p in layout.panels where p.kind != .empty {
            let x = panelExtents(p, layout)
            guard x.s1 - x.s0 > Tolerance.shortCurve, x.z1 - x.z0 > Tolerance.shortCurve,
                  let q = quad(point(c, station: x.s0, length: L), point(c, station: x.s1, length: L), depth: p.thickness) else { continue }
            out.append((p, MeshBuilder.extrude(Profile2(outer: q), bottom: x.z0, top: x.z1)))
        }
        return out
    }

    static func mullionSolid(_ m: CurtainMullion, _ layout: CurtainLayout, _ c: Curve2) -> Mesh? {
        let L = layout.length
        if m.isVertical {
            guard let q = verticalFootprint(m, c, length: L) else { return nil }
            return MeshBuilder.extrude(Profile2(outer: q), bottom: m.from, top: m.to)
        }
        let (a, b) = horizontalRun(m, layout)
        let (z0, z1) = horizontalSpan(m, layout)
        guard b - a > Tolerance.shortCurve, let q = quad(point(c, station: a, length: L), point(c, station: b, length: L), depth: m.profile.depth) else { return nil }
        return MeshBuilder.extrude(Profile2(outer: q), bottom: z0, top: z1)
    }

    /// Solid of each mullion segment (horizontal mullions trimmed against the vertical ones they meet).
    public static func mullionSolids(_ e: Element, _ model: BIMModel) -> [(mullion: CurtainMullion, mesh: Mesh)] {
        guard let f = WallGeometry.frame(e, model), let layout = layout(e, model) else { return [] }
        let c = centerCurve(f)
        return layout.mullions.compactMap { m in mullionSolid(m, layout, c).map { (m, $0) } }
    }

    /// Mesh parts: one per panel material and one for the mullions. nil when `e` is not a curtain wall.
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart]? {
        guard let spec = spec(e, model) else { return nil }
        guard let f = WallGeometry.frame(e, model), let layout = layout(e, model) else { return [] }
        var byMaterial: [ElementID?: (Mesh, FamilySubcategory)] = [:]
        var order: [ElementID?] = []
        for (p, m) in panelSolids(e, model) {
            if byMaterial[p.materialID] == nil { order.append(p.materialID); byMaterial[p.materialID] = (Mesh(), p.kind == .glazed ? .glass : .panel) }
            byMaterial[p.materialID]!.0.append(m)
        }
        // Vertical mullions: consecutive segments of one grid line merge into a single continuous bar.
        let c = centerCurve(f)
        var mullionMesh = Mesh()
        let verticals = layout.mullions.filter(\.isVertical).sorted { ($0.position, $0.from) < ($1.position, $1.from) }
        var k = 0
        while k < verticals.count {
            var run = verticals[k]
            var n = k + 1
            while n < verticals.count, abs(verticals[n].position - run.position) < 1e-9, abs(verticals[n].from - run.to) < 1e-9 {
                run.to = verticals[n].to; n += 1
            }
            if let m = mullionSolid(run, layout, c) { mullionMesh.append(m) }
            k = n
        }
        for m in layout.mullions where !m.isVertical {
            if let solid = mullionSolid(m, layout, c) { mullionMesh.append(solid) }
        }
        var parts = order.map { id in MeshPart(mesh: byMaterial[id]!.0, materialID: id, subcategory: byMaterial[id]!.1) }
        if !mullionMesh.isEmpty { parts.append(MeshPart(mesh: mullionMesh, materialID: spec.mullionMaterialID, subcategory: .frame)) }
        return parts
    }

    // MARK: Plan

    /// Plan outlines where a horizontal plane at `z` passes through the wall: panels (thin), and mullions (solid).
    public static func planOutlines(_ e: Element, atZ z: Double, _ model: BIMModel) -> (panels: [Polygon2], mullions: [Polygon2]) {
        guard let f = WallGeometry.frame(e, model), let layout = layout(e, model) else { return ([], []) }
        let c = centerCurve(f)
        let L = layout.length
        var panels: [Polygon2] = [], mullions: [Polygon2] = []
        for p in layout.panels where p.kind != .empty {
            let x = panelExtents(p, layout)
            guard z >= x.z0 - 1e-9, z < x.z1 else { continue }
            if let q = quad(point(c, station: x.s0, length: L), point(c, station: x.s1, length: L), depth: p.thickness) { panels.append(q) }
        }
        for m in layout.mullions {
            if m.isVertical {
                guard z >= m.from - 1e-9, z < m.to, let q = verticalFootprint(m, c, length: L) else { continue }
                mullions.append(q)
            } else {
                let (z0, z1) = horizontalSpan(m, layout)
                guard z >= z0 - 1e-9, z <= z1 + 1e-9 else { continue }
                let (a, b) = horizontalRun(m, layout)
                if let q = quad(point(c, station: a, length: L), point(c, station: b, length: L), depth: m.profile.depth) { mullions.append(q) }
            }
        }
        return (panels, mullions)
    }

    /// Plan outlines seen from above for a curtain wall entirely below a plan's cut plane: the top of the wall.
    public static func planProjection(_ e: Element, _ model: BIMModel) -> (panels: [Polygon2], mullions: [Polygon2]) {
        guard let layout = layout(e, model) else { return ([], []) }
        return planOutlines(e, atZ: layout.topZ - Tolerance.shortCurve, model)
    }

    // MARK: Quantities

    /// Wall quantities for a curtain wall: gross grid area, panel material areas and mullion material volume.
    public static func quantities(_ e: Element, _ model: BIMModel) -> ElementQuantities? {
        guard let spec = spec(e, model) else { return nil }
        var q = ElementQuantities()
        guard let f = WallGeometry.frame(e, model), let layout = layout(e, model) else { return q }
        q.length = f.length
        q.height = f.height
        q.width = f.thickness
        q.area = f.length * f.height
        q.elevationBottom = f.baseZ
        q.elevationTop = f.topZ
        var areas: [ElementID?: (Double, Double)] = [:]
        var order: [ElementID?] = []
        for p in layout.panels where p.kind != .empty {
            let x = panelExtents(p, layout)
            let a = max(0, x.s1 - x.s0) * max(0, x.z1 - x.z0)
            if areas[p.materialID] == nil { order.append(p.materialID); areas[p.materialID] = (0, 0) }
            areas[p.materialID]!.0 += a
            areas[p.materialID]!.1 += a * p.thickness
        }
        q.materials = order.map { MaterialQuantity(materialID: $0, area: areas[$0]!.0, volume: areas[$0]!.1) }
        let mullionVolume = layout.mullions.reduce(0) { $0 + $1.length * $1.profile.width * $1.profile.depth }
        if mullionVolume > 0 {
            let surface = layout.mullions.reduce(0) { $0 + $1.length * 2 * ($1.profile.width + $1.profile.depth) }
            q.materials.append(MaterialQuantity(materialID: spec.mullionMaterialID, area: surface, volume: mullionVolume))
        }
        q.volume = q.materials.reduce(0) { $0 + $1.volume }
        return q
    }

    // MARK: Picking

    /// Station along the wall and absolute elevation of a point in a vertical view, or nil when the view looks along
    /// the wall. `u` is the view's horizontal coordinate (see `VerticalGraphics`).
    public static func station(ofViewU u: Double, view: ViewData, wall f: WallFrame) -> Double? {
        guard let o = view.planeOrigin, let r = view.rightVector, let d = view.viewDirection?.normalized else { return nil }
        let p = o.xy + r * u
        let probe = Segment2(p - d * 10_000, p + d * 10_000)
        switch f.location {
        case .line(let s):
            guard !s.isParallel(to: probe), let hit = s.lineIntersection(probe) else { return nil }
            return hit.t * s.length
        case .arc:
            // Nearest crossing of the view ray with the arc (sampled), measured along the curve.
            let pts = f.location.tessellate(chordTolerance: 0.002)
            var acc = 0.0, best: (Double, Double)?
            for i in 0..<(pts.count - 1) {
                let seg = Segment2(pts[i], pts[i + 1])
                if let hit = seg.lineIntersection(probe), hit.t >= -1e-9, hit.t <= 1 + 1e-9 {
                    let depth = (hit.point - p).dot(d)
                    if best == nil || depth < best!.1 { best = (acc + hit.t * seg.length, depth) }
                }
                acc += seg.length
            }
            guard let b = best else { return nil }
            return b.0 / max(acc, 1e-12) * f.length
        }
    }
}

extension Regenerator {
    /// Curtain walls carry per-instance curtain data (manual grids, overrides); other walls carry none. Keeps that true
    /// whenever a wall is created or re-typed, however the type changed (type selector, Match Type, paste).
    func normalizeCurtainWalls(_ tx: TransactionContext) {
        for id in tx.touchedIDs {
            guard let w = tx.model[id], let wd = w.wall else { continue }
            let isCurtain = tx.model.typeData(of: w)?.curtain != nil
            if isCurtain && wd.curtain == nil {
                tx.propagate(id) { $0.wall?.curtain = CurtainInstanceData() }
            } else if !isCurtain && wd.curtain != nil {
                tx.propagate(id) { $0.wall?.curtain = nil }
            }
        }
    }
}
