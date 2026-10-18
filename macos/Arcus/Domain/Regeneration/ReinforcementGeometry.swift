import Foundation
import ArcusGeometry
import ArcusCalc

// F34: geometry of reinforcement, ported from RevitCraft's rc-core rebar.rs: bar types and cover, host frames, the
// bars of rebar sets, area and path reinforcement, fabric sheets and couplers, and their 3D rods.

/// One straight bar (or fabric wire) in world coordinates.
public struct ReinforcingBar: Hashable, Sendable {
    public var start: Vec3
    public var end: Vec3
    public var diameter: Double
    public init(_ start: Vec3, _ end: Vec3, _ diameter: Double) { self.start = start; self.end = end; self.diameter = diameter }
    public var length: Double { start.distance(to: end) }
}

public enum Reinforcement {
    public static let barDiameterParameter = ParameterID("rebar.barDiameter")
    public static let fabricLengthParameter = ParameterID("fabric.overallLength")
    public static let fabricWidthParameter = ParameterID("fabric.overallWidth")
    public static let fabricMajorSpacingParameter = ParameterID("fabric.majorSpacing")
    public static let fabricMinorSpacingParameter = ParameterID("fabric.minorSpacing")
    public static let fabricWireParameter = ParameterID("fabric.wireDiameter")
    public static let fabricMajorLapParameter = ParameterID("fabric.majorLap")
    public static let fabricMinorLapParameter = ParameterID("fabric.minorLap")
    public static let barFamily = "Rebar Bar"
    public static let fabricFamily = "Fabric Sheet"

    // MARK: Settings and types

    /// The concrete cover: the project's Rebar Cover Settings, else 40 mm (1 1/2" in imperial projects).
    public static func cover(_ m: BIMModel) -> Double {
        let c = m.structuralSettings.rebarCover
        if c > 0 { return c }
        return m.units.system == .imperial ? 0.0381 : 0.040
    }

    /// The project's rebar bar types, created on first use: 10M–25M, or #3–#6 in imperial projects.
    @discardableResult
    public static func ensureBarTypes(in tx: TransactionContext) -> [ElementID] {
        let have = barTypes(tx.model)
        if !have.isEmpty { return have.map(\.id) }
        let sizes: [(String, Double)] = tx.model.units.system == .imperial
            ? [("#3", 0.009525), ("#4", 0.0127), ("#5", 0.015875), ("#6", 0.01905)]
            : [("10M", 0.0113), ("15M", 0.016), ("20M", 0.0195), ("25M", 0.0252)]
        let steel = steelMaterial(tx.model)
        return sizes.map { name, d in
            var td = TypeData(instanceCategory: .structuralRebar, familyName: barFamily, params: [barDiameterParameter: .double(d)])
            if let steel { td.params[ParameterID("type.material")] = .ref(steel) }
            return tx.create(.elementTypes, name: name, data: .type(td))
        }
    }

    /// Bar types sorted by diameter.
    public static func barTypes(_ m: BIMModel) -> [Element] {
        m.types(for: .structuralRebar).sorted { barDiameter(m, $0.id) < barDiameter(m, $1.id) }
    }

    /// The bar type new reinforcement uses: the second size (15M / #4), as in RevitCraft.
    public static func defaultBarType(_ m: BIMModel) -> ElementID? {
        let t = barTypes(m)
        return (t.count > 1 ? t[1] : t.first)?.id
    }

    public static func barDiameter(_ m: BIMModel, _ type: ElementID?) -> Double {
        m[type]?.typeData?.params[barDiameterParameter]?.doubleValue ?? 0.012
    }

    public static func barName(_ m: BIMModel, _ type: ElementID?) -> String { m[type]?.name ?? "" }

    /// The project's fabric sheet type, made on first use: 4800 × 2400 at 200 (12'-6" × 8'-0" at 1'-0").
    @discardableResult
    public static func ensureFabricType(in tx: TransactionContext) -> ElementID {
        if let t = tx.model.types(for: .fabricReinforcement).first { return t.id }
        let imperial = tx.model.units.system == .imperial
        let (l, w, s, d, lap) = imperial ? (3.81, 2.4384, 0.3048, 0.0049, 0.2032) : (4.8, 2.4, 0.2, 0.006, 0.2)
        var td = TypeData(instanceCategory: .fabricReinforcement, familyName: fabricFamily, params: [
            fabricLengthParameter: .double(l), fabricWidthParameter: .double(w), fabricMajorSpacingParameter: .double(s),
            fabricMinorSpacingParameter: .double(s), fabricWireParameter: .double(d), fabricMajorLapParameter: .double(lap),
            fabricMinorLapParameter: .double(lap),
        ])
        if let steel = steelMaterial(tx.model) { td.params[ParameterID("type.material")] = .ref(steel) }
        return tx.create(.elementTypes, name: "Fabric Sheet 1", data: .type(td))
    }

    /// (length, width, major spacing, minor spacing, wire diameter) of a fabric sheet type.
    public static func sheetSize(_ m: BIMModel, _ type: ElementID?) -> (length: Double, width: Double, major: Double, minor: Double, wire: Double) {
        let p = m[type]?.typeData?.params ?? [:]
        func g(_ id: ParameterID, _ d: Double) -> Double { p[id]?.doubleValue ?? d }
        return (g(fabricLengthParameter, 4.8), g(fabricWidthParameter, 2.4), g(fabricMajorSpacingParameter, 0.2),
                g(fabricMinorSpacingParameter, 0.2), g(fabricWireParameter, 0.006))
    }

    static func steelMaterial(_ m: BIMModel) -> ElementID? {
        m.materials.first { $0.material?.materialClass == .metal && $0.name.localizedCaseInsensitiveContains("steel") }?.id
            ?? m.materials.first { $0.material?.materialClass == .metal }?.id
    }

    // MARK: Hosts

    /// Floors (including foundation slabs) and walls host reinforcement.
    public static func canHost(_ e: Element) -> Bool {
        (e.category == .floors && e.slab != nil) || (e.wall != nil && e.wall?.curtain == nil)
    }

    public static func isWallHosted(_ m: BIMModel, _ host: ElementID?) -> Bool { m[host]?.wall != nil }

    /// A straight wall's face frame: the start of its centre line, its direction, the exterior normal, base and thickness.
    public static func wallFrame(_ m: BIMModel, _ host: ElementID?) -> (origin: Vec2, direction: Vec2, normal: Vec2, base: Double, thickness: Double, height: Double, length: Double)? {
        guard let w = m[host], w.wall != nil, let f = WallGeometry.frame(w, m), let seg = f.location.asSegment else { return nil }
        let center = seg.offset(by: f.centerOffset)
        let side: Double = f.exteriorOffset >= f.centerOffset ? 1 : -1
        return (center.start, center.direction, center.normal * side, f.baseZ, f.thickness, f.height, center.length)
    }

    /// The host's outline in reinforcement coordinates: a floor's boundary, or a wall's face (0…length × 0…height).
    public static func hostRegion(_ m: BIMModel, _ host: ElementID?) -> Polygon2? {
        guard let h = m[host] else { return nil }
        if h.slab != nil { return SlabGeometry.profile(h)?.outer }
        guard let f = wallFrame(m, host) else { return nil }
        return Polygon2([.zero, Vec2(f.length, 0), Vec2(f.length, f.height), Vec2(0, f.height)])
    }

    /// A face point of wall-hosted reinforcement in the world, on the wall's centre plane.
    public static func facePoint(_ m: BIMModel, _ host: ElementID?, _ q: Vec2) -> Vec3? {
        guard let f = wallFrame(m, host) else { return nil }
        return Vec3(f.origin + f.direction * q.x, z: f.base + q.y)
    }

    /// Maps reinforcement points to the world for a layer of bars of diameter `d` (`below` = diameters laid outside
    /// it): floors take plan points at the layer's height; walls take face points at its depth from the exterior
    /// (`top`) or interior face.
    static func layerMap(_ m: BIMModel, host: ElementID?, top: Bool, diameter d: Double, below: Double) -> ((Vec2) -> Vec3)? {
        let c = cover(m) + below
        if let h = m[host], h.slab != nil, let planes = SlabGeometry.planes(h, m) {
            return { q in Vec3(q, z: top ? planes.top.z(at: q) - c - d / 2 : planes.bottom.z(at: q) + c + d / 2) }
        }
        guard let f = wallFrame(m, host) else { return nil }
        let off = (f.thickness / 2 - c - d / 2) * (top ? 1 : -1)
        return { q in Vec3(f.origin + f.direction * q.x + f.normal * off, z: f.base + q.y) }
    }

    /// Lines across a polygon parallel to `dir` at `spacing`, centred across it.
    public static func hatch(_ poly: [Vec2], direction dir: Vec2, spacing: Double) -> [Segment2] {
        guard poly.count >= 3 else { return [] }
        let n = dir.perpendicular, o = poly[0]
        let across = poly.map { ($0 - o).dot(n) }
        guard let lo = across.min(), let hi = across.max(), spacing > 0.001, hi - lo >= 0.001 else { return [] }
        let count = Int(((hi - lo) / spacing + 1e-9).rounded(.down)) + 1
        let first = lo + (hi - lo - Double(count - 1) * spacing) / 2
        var out: [Segment2] = []
        for k in 0..<count {
            let base = o + n * (first + Double(k) * spacing)
            var ts: [Double] = []
            for i in poly.indices {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                let da = (a - base).dot(n), db = (b - base).dot(n)
                if (da > 0) != (db > 0) {
                    let t = da / (da - db)
                    ts.append((a + (b - a) * t - base).dot(dir))
                }
            }
            ts.sort()
            var i = 0
            while i + 1 < ts.count {
                if ts[i + 1] - ts[i] > 0.001 { out.append(Segment2(base + dir * ts[i], base + dir * ts[i + 1])) }
                i += 2
            }
        }
        return out
    }

    /// The boundary shrunk by the cover (the largest piece).
    static func insideCover(_ m: BIMModel, _ boundary: [Vec2]) -> Polygon2? {
        let inner = Polygon2(boundary).counterClockwise.offset(by: -cover(m)).filter(\.isCounterClockwise).max { $0.area < $1.area }
        guard let inner, inner.count >= 3, inner.area > 1e-6 else { return nil }
        return inner
    }

    // MARK: Bars

    /// The bars of an area reinforcement: each layer inside the cover, top (exterior) layers then bottom (interior).
    public static func areaBars(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        guard let a = e.areaReinforcement, a.layers.count == 4, let inner = insideCover(m, a.boundary) else { return [] }
        let major = a.major.lengthSquared > 1e-12 ? a.major.normalized : .unitX
        let minor = major.perpendicular
        let d = a.layers.map { barDiameter(m, $0.barTypeID) }
        // Major layers are outermost on each face; minor layers lie inside them.
        let below = [0, d[0], 0, d[2]]
        var out: [ReinforcingBar] = []
        for k in 0..<4 where a.layers[k].on {
            guard let at = layerMap(m, host: e.hostID, top: k < 2, diameter: d[k], below: below[k]) else { return [] }
            for s in hatch(inner.points, direction: k % 2 == 0 ? major : minor, spacing: a.layers[k].spacing) {
                out.append(ReinforcingBar(at(s.start), at(s.end), d[k]))
            }
        }
        return out
    }

    /// A straight rebar set: `count` bars `spacing` apart, to the left of start → end, at the host's bottom cover.
    public static func rebarBars(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        guard let r = e.rebar, r.start.distance(to: r.end) > Tolerance.shortCurve else { return [] }
        let d = barDiameter(m, e.typeID)
        guard let at = layerMap(m, host: e.hostID, top: false, diameter: d, below: 0) else { return [] }
        let n = (r.end - r.start).normalized.perpendicular
        return (0..<max(1, r.count)).map { k in
            let off = n * (r.spacing * Double(k))
            return ReinforcingBar(at(r.start + off), at(r.end + off), d)
        }
    }

    /// Which side of the path (+1 left, −1 right) the bars run to: into the host (or the other way when flipped).
    public static func pathSide(_ e: Element, _ m: BIMModel) -> Double {
        guard let r = e.pathReinforcement else { return 1 }
        var side = 1.0
        if let region = hostRegion(m, e.hostID), r.path.count >= 2 {
            let a = r.path[0], b = r.path[1]
            let n = (b - a).normalized.perpendicular
            side = region.contains((a + b) / 2 + n * min(r.length, 0.6) / 2) ? 1 : -1
        }
        return r.flip ? -side : side
    }

    /// The bars of a path reinforcement, centred along each segment of the path.
    public static func pathBars(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        guard let r = e.pathReinforcement, r.spacing >= 0.001 else { return [] }
        let d = barDiameter(m, r.barTypeID)
        guard let at = layerMap(m, host: e.hostID, top: r.top, diameter: d, below: 0) else { return [] }
        let side = pathSide(e, m)
        var out: [ReinforcingBar] = []
        for i in 0..<max(0, r.path.count - 1) {
            let a = r.path[i], b = r.path[i + 1], len = a.distance(to: b)
            guard len >= 0.001 else { continue }
            let dir = (b - a) / len, n = dir.perpendicular * side
            let count = Int((len / r.spacing + 1e-9).rounded(.down)) + 1
            let first = (len - Double(count - 1) * r.spacing) / 2
            for k in 0..<count {
                let q = a + dir * (first + Double(k) * r.spacing)
                out.append(ReinforcingBar(at(q), at(q + n * r.length), d))
            }
        }
        return out
    }

    /// The strips a path reinforcement covers, one per path segment (host coordinates).
    public static func pathRegions(_ e: Element, _ m: BIMModel) -> [Polygon2] {
        guard let r = e.pathReinforcement, r.path.count >= 2 else { return [] }
        let side = pathSide(e, m)
        return (0..<(r.path.count - 1)).map { i in
            let a = r.path[i], b = r.path[i + 1]
            let n = (b - a).normalized.perpendicular * side * r.length
            return Polygon2([a, b, b + n, a + n])
        }
    }

    /// The outline of a sheet of `length` × `width` centred at `c`, its length along `dir`.
    public static func sheetRect(_ c: Vec2, direction dir: Vec2, length: Double, width: Double) -> [Vec2] {
        let u = dir * (length / 2), v = dir.perpendicular * (width / 2)
        return [c - u - v, c + u - v, c + u + v, c - u + v]
    }

    /// The outline of a fabric sheet element (host coordinates).
    public static func sheetOutline(_ e: Element, _ m: BIMModel) -> [Vec2] {
        guard let s = e.fabricSheet else { return [] }
        let size = sheetSize(m, e.typeID)
        return sheetRect(s.center, direction: .fromAngle(s.angle), length: size.length, width: size.width)
    }

    /// The wires of a fabric piece: major wires along `dir`, minor wires across them.
    static func sheetWires(_ m: BIMModel, host: ElementID?, top: Bool, type: ElementID?, piece: [Vec2], direction dir: Vec2) -> [ReinforcingBar] {
        let s = sheetSize(m, type)
        guard let m0 = layerMap(m, host: host, top: top, diameter: s.wire, below: 0),
              let m1 = layerMap(m, host: host, top: top, diameter: s.wire, below: s.wire) else { return [] }
        return hatch(piece, direction: dir, spacing: s.major).map { ReinforcingBar(m0($0.start), m0($0.end), s.wire) }
            + hatch(piece, direction: dir.perpendicular, spacing: s.minor).map { ReinforcingBar(m1($0.start), m1($0.end), s.wire) }
    }

    public static func fabricSheetWires(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        guard let s = e.fabricSheet else { return [] }
        return sheetWires(m, host: e.hostID, top: s.top, type: e.typeID, piece: sheetOutline(e, m), direction: .fromAngle(s.angle))
    }

    /// The sheets of a fabric area: lapped tiles along the major direction, cut to the boundary inside the cover.
    public static func fabricAreaSheets(_ e: Element, _ m: BIMModel) -> [Polygon2] {
        guard let a = e.fabricArea, let inner = insideCover(m, a.boundary) else { return [] }
        let size = sheetSize(m, a.fabricTypeID)
        let dir = a.major.lengthSquared > 1e-12 ? a.major.normalized : .unitX, n = dir.perpendicular
        let su = max(size.length - a.majorLap, 0.1), sv = max(size.width - a.minorLap, 0.1)
        let o = inner.points[0]
        let us = inner.points.map { ($0 - o).dot(dir) }, vs = inner.points.map { ($0 - o).dot(n) }
        guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max() else { return [] }
        let area = [Profile2(outer: inner)]
        var out: [Polygon2] = []
        var u = u0
        while u < u1 - 0.001 && out.count < 2000 {
            var v = v0
            while v < v1 - 0.001 {
                let c = o + dir * (u + size.length / 2) + n * (v + size.width / 2)
                let tile = Polygon2(sheetRect(c, direction: dir, length: size.length, width: size.width)).counterClockwise
                for p in PolygonBoolean.intersection([Profile2(outer: tile)], area) where p.outer.count >= 3 && p.outer.area > 0.001 {
                    out.append(p.outer)
                }
                v += sv
            }
            u += su
        }
        return out
    }

    public static func fabricAreaWires(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        guard let a = e.fabricArea else { return [] }
        let dir = a.major.lengthSquared > 1e-12 ? a.major.normalized : .unitX
        return fabricAreaSheets(e, m).flatMap { sheetWires(m, host: e.hostID, top: a.top, type: a.fabricTypeID, piece: $0.points, direction: dir) }
    }

    /// Couplers: (centre, bar axis, bar diameter), one per bar of the host set.
    public static func couplerPoints(_ e: Element, _ m: BIMModel) -> [(center: Vec3, axis: Vec3, diameter: Double)] {
        guard let c = e.rebarCoupler, let r = m[e.hostID], r.rebar != nil else { return [] }
        return rebarBars(r, m).map { b in (c.atEnd ? b.end : b.start, (b.end - b.start).normalized, b.diameter) }
    }

    /// Every bar of a reinforcement element (fabric: its wires).
    public static func bars(_ e: Element, _ m: BIMModel) -> [ReinforcingBar] {
        switch e.data {
        case .rebar: rebarBars(e, m)
        case .areaReinforcement: areaBars(e, m)
        case .pathReinforcement: pathBars(e, m)
        case .fabricArea: fabricAreaWires(e, m)
        case .fabricSheet: fabricSheetWires(e, m)
        default: []
        }
    }

    // MARK: Tags

    /// A length in project units without the unit symbol, as reinforcement tags read ("15M @ 300").
    static func length(_ v: Double, _ m: BIMModel) -> String { QuantityFormatter.format(v, kind: .length, units: m.units, includeSymbol: false) }

    /// The tag of a rebar set, as "3 15M @ 200".
    public static func rebarTag(_ e: Element, _ m: BIMModel) -> String {
        guard let r = e.rebar else { return "" }
        return "\(r.count) \(barName(m, e.typeID)) @ \(length(r.spacing, m))"
    }

    /// The tag of a path reinforcement, as "15M @ 300".
    public static func pathTag(_ e: Element, _ m: BIMModel) -> String {
        guard let r = e.pathReinforcement else { return "" }
        return "\(barName(m, r.barTypeID)) @ \(length(r.spacing, m))"
    }

    /// The tag of an area reinforcement, as "(T) 15M@300 EW (B) 15M@300 EW".
    public static func areaTag(_ e: Element, _ m: BIMModel) -> String {
        guard let a = e.areaReinforcement, a.layers.count == 4 else { return "" }
        func s(_ l: RebarLayer) -> String { "\(barName(m, l.barTypeID))@\(length(l.spacing, m))" }
        func face(_ i: Int, _ tag: String) -> String? {
            let maj = a.layers[i], min = a.layers[i + 1]
            switch (maj.on, min.on) {
            case (true, true) where maj.barTypeID == min.barTypeID && abs(maj.spacing - min.spacing) < 1e-9: return "(\(tag)) \(s(maj)) EW"
            case (true, true): return "(\(tag)) \(s(maj)) / \(s(min))"
            case (true, false): return "(\(tag)) \(s(maj))"
            case (false, true): return "(\(tag)) \(s(min))"
            default: return nil
            }
        }
        return [face(0, "T"), face(2, "B")].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: 3D

    /// Bars as octagonal rods (steel), couplers as sleeves.
    public static func meshParts(_ e: Element, _ m: BIMModel) -> [MeshPart] {
        let mesh: Mesh
        switch e.data {
        case .rebarCoupler:
            var parts: [ReinforcingBar] = []
            for (c, ax, d) in couplerPoints(e, m) {
                parts.append(ReinforcingBar(c - ax * (2 * d), c - ax * (0.4 * d), 1.5 * d))
                parts.append(ReinforcingBar(c - ax * (0.4 * d), c + ax * (0.4 * d), 1.8 * d))
                parts.append(ReinforcingBar(c + ax * (0.4 * d), c + ax * (2 * d), 1.5 * d))
            }
            mesh = barsMesh(parts)
        default:
            mesh = barsMesh(bars(e, m))
        }
        guard !mesh.isEmpty else { return [] }
        let type: ElementID? = e.rebar != nil || e.fabricSheet != nil ? e.typeID
            : e.areaReinforcement?.layers.first?.barTypeID ?? e.pathReinforcement?.barTypeID ?? e.fabricArea?.fabricTypeID
        return [MeshPart(mesh: mesh, materialID: m[type]?.typeData?.params[ParameterID("type.material")]?.refValue ?? steelMaterial(m))]
    }

    public static func barsMesh(_ bars: [ReinforcingBar]) -> Mesh {
        var mesh = Mesh()
        for b in bars {
            let axis = (b.end - b.start).normalized
            guard axis.lengthSquared > 0.5 else { continue }
            let u = (abs(axis.z) < 0.9 ? axis.cross(.unitZ) : axis.cross(.unitX)).normalized
            let v = axis.cross(u), r = b.diameter / 2
            func ring(_ c: Vec3) -> [Vec3] { (0..<8).map { k in let t = Double(k) * .pi / 4; return c + (u * cos(t) + v * sin(t)) * r } }
            let ra = ring(b.start), rb = ring(b.end)
            let base = UInt32(mesh.positions.count)
            for k in 0..<8 {
                let j = (k + 1) % 8
                let mid = ((ra[k] + ra[j]) * 0.5 - b.start).normalized
                mesh.addConvexFace([ra[k], ra[j], rb[j], rb[k]], normal: mid, edges: false)
            }
            // Silhouette lines along two opposite sides of the rod.
            mesh.featureEdges += [base + 2 * 4 + 0, base + 2 * 4 + 3, base + 6 * 4 + 0, base + 6 * 4 + 3]
            mesh.addConvexFace(ra.reversed(), normal: -axis)
            mesh.addConvexFace(rb, normal: axis)
        }
        return mesh
    }
}

// MARK: - Dependencies

extension Reinforcement {
    /// Elements a reinforcement element's geometry depends on: its host (and the host's type and levels), its bar or
    /// fabric types, the rebar set of a coupler and the project's Structural Settings (cover).
    static func inputs(of e: Element, _ m: BIMModel) -> Set<ElementID> {
        var s: Set<ElementID> = []
        func addHost(_ id: ElementID?) {
            guard let h = m[id] else { return }
            s.insert(h.id)
            for x in [h.typeID, h.levelID, h.wall?.topLevelID] { if let x { s.insert(x) } }
            if let a = m.typeData(of: h)?.assembly { for l in a.layers { if let mat = l.materialID { s.insert(mat) } } }
        }
        addHost(e.hostID)
        if let r = m[e.hostID], r.rebar != nil { addHost(r.hostID); if let t = r.typeID { s.insert(t) } }
        for t in [e.pathReinforcement?.barTypeID, e.fabricArea?.fabricTypeID] + (e.areaReinforcement?.layers.map(\.barTypeID) ?? []) { if let t { s.insert(t) } }
        if let settings = m.elements(.structuralSettings).first { s.insert(settings.id) }
        if let info = m.projectInfoElement { s.insert(info.id) } // units: the default cover
        return s
    }

    /// Elements whose graphics change with `e`: reinforcement in a changed host, couplers and symbols of a changed set,
    /// reinforcement using a changed bar type, everything after a Structural Settings change.
    static func affected(by e: Element, _ m: BIMModel) -> Set<ElementID> {
        var out: Set<ElementID> = []
        func addWithDependents(_ x: Element) { out.insert(x.id); for d in m.hosted(by: x.id) { out.insert(d.id); for dd in m.hosted(by: d.id) { out.insert(dd.id) } } }
        switch e.data {
        case .slab, .wall, .beamSystem, .rebar, .areaReinforcement, .pathReinforcement, .fabricArea, .fabricSheet:
            for h in m.hosted(by: e.id) { addWithDependents(h) }
        case .structuralSettings:
            for c in Category.f34Structural + [.structuralFraming] { for x in m.elements(c) { addWithDependents(x) } }
        case .type(let td) where td.instanceCategory == .structuralRebar || td.instanceCategory == .fabricReinforcement:
            for c in [Category.areaReinforcement, .pathReinforcement, .fabricAreas] {
                for x in m.elements(c) where inputs(of: x, m).contains(e.id) { addWithDependents(x) }
            }
            for x in m.instances(ofType: e.id) { addWithDependents(x) }
        default: break
        }
        return out
    }
}
