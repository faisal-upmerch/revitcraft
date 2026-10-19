import Foundation
import ArcusGeometry

// FM7: CNC programs (Docs/FurnitureMode.md §3 "CNC Export"): each part's outline, cut-outs and machining in the
// part's own 2D coordinates, ready for a DXF/DWG writer. Conventions (as cabinet CAM software reads them):
//   - Units are inches. X runs along the part's cut length, Y along its cut width; the origin is the lower-left corner
//     of face A seen from above. Face A is the part's top face as built (the face toward +Z, +Y or +X for its
//     thickness axis); face B is the opposite face, seen from its own side (the part flipped over its long edge, so
//     B's Y = width − A's Y).
//   - Layers: OUTLINE (closed outline, cut through), INNER (closed cut-outs, through), DRILL_<dia>_<depth> (circles),
//     GROOVE_<depth> and POCKET_<depth> (closed outlines of the cleared area), GRAIN (a line along the grain), LABEL
//     (the Mark). Sizes in layer names are inches to 3 decimals ("DRILL_0.315_0.394").
//   - Edge boring (dowels and cam bolts into an end, slide screws) can't be cut from a face: HDRILL_<dia>_<depth>_Z<z>
//     is a line from the edge inward along the bore, Z its height above face B; HGROOVE_ and HPOCKET_ likewise.
//   - Face B operations go to a second program (<Mark>_B), or, with Flip Layers, into the same file on layers
//     prefixed B_ in face B's coordinates.
// Nested sheets place each part's face A program at its position on the sheet (rotated 90° when it was turned), with
// the stock outline on SHEET.

/// A CNC drawing in part (or sheet) coordinates, meters.
public struct CNCDrawing: Hashable, Sendable {
    public struct Path: Hashable, Sendable { public var layer: String; public var points: [Vec2]; public var closed: Bool }
    public struct Circle: Hashable, Sendable { public var layer: String; public var center: Vec2; public var radius: Double }
    public struct Label: Hashable, Sendable { public var layer: String; public var position: Vec2; public var height: Double; public var text: String }
    public var paths: [Path] = []
    public var circles: [Circle] = []
    public var labels: [Label] = []
    public init() {}

    public var isEmpty: Bool { paths.isEmpty && circles.isEmpty && labels.isEmpty }
    /// Every layer used, sorted.
    public var layers: [String] { Array(Set(paths.map(\.layer) + circles.map(\.layer) + labels.map(\.layer))).sorted() }
    /// Whether the drawing has machining (anything but outline, grain and label).
    public var hasMachining: Bool { layers.contains { !["OUTLINE", "GRAIN", "LABEL", "SHEET"].contains($0) && !$0.hasPrefix("B_LABEL") } }

    /// The drawing moved by `t` (and turned 90° counterclockwise first when `rotated`, about the origin, then shifted
    /// back into positive X by `width`).
    public func placed(at origin: Vec2, rotated: Bool, width: Double) -> CNCDrawing {
        func f(_ p: Vec2) -> Vec2 { rotated ? Vec2(origin.x + width - p.y, origin.y + p.x) : p + origin }
        var d = CNCDrawing()
        d.paths = paths.map { Path(layer: $0.layer, points: $0.points.map(f), closed: $0.closed) }
        d.circles = circles.map { Circle(layer: $0.layer, center: f($0.center), radius: $0.radius) }
        d.labels = labels.map { Label(layer: $0.layer, position: f($0.position), height: $0.height, text: $0.text) }
        return d
    }

    public mutating func append(_ o: CNCDrawing, layerPrefix: String = "") {
        paths += o.paths.map { Path(layer: layerPrefix + $0.layer, points: $0.points, closed: $0.closed) }
        circles += o.circles.map { Circle(layer: layerPrefix + $0.layer, center: $0.center, radius: $0.radius) }
        labels += o.labels.map { Label(layer: layerPrefix + $0.layer, position: $0.position, height: $0.height, text: $0.text) }
    }
}

/// One part's CNC programs.
public struct CNCPartProgram: Sendable {
    public var part: CutPart
    /// File base name (the Mark, made safe for file names).
    public var name: String
    public var faceA: CNCDrawing
    /// Face B operations (nil when there are none).
    public var faceB: CNCDrawing?
    /// Machining operations on both faces and the edges (outlines, grain and labels aside).
    public var operationCount: Int {
        func n(_ d: CNCDrawing?) -> Int { (d?.circles.count ?? 0) + (d?.paths.filter { !["OUTLINE", "GRAIN", "INNER"].contains($0.layer) }.count ?? 0) }
        return n(faceA) + n(faceB)
    }
}

/// One nested sheet's program.
public struct CNCSheetProgram: Sendable {
    public var name: String
    public var group: NestingGroup
    public var index: Int
    public var drawing: CNCDrawing
}

public enum FurnitureCNC {
    static let inch = 0.0254

    // MARK: Layer names

    /// Inches to 3 decimals without trailing zeros ("0.315", "0.75", "1").
    public static func num(_ meters: Double) -> String {
        var s = String(format: "%.3f", meters / inch)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
    public static func drillLayer(diameter: Double, depth: Double) -> String { "DRILL_\(num(diameter))_\(num(depth))" }
    public static func grooveLayer(depth: Double) -> String { "GROOVE_\(num(depth))" }
    public static func pocketLayer(depth: Double) -> String { "POCKET_\(num(depth))" }

    // MARK: Part frames

    /// A part's machining frame: its box, length/width/thickness axes and handedness.
    struct Frame {
        var lo: Vec3, hi: Vec3
        var l: FamilyAxis, w: FamilyAxis, t: FamilyAxis
        /// L × W points along −T: face A's Y runs the other way.
        var mirrored: Bool
        func c(_ p: Vec3, _ a: FamilyAxis) -> Double { a == .x ? p.x : (a == .y ? p.y : p.z) }
        var length: Double { c(hi, l) - c(lo, l) }
        var width: Double { c(hi, w) - c(lo, w) }
        var thickness: Double { c(hi, t) - c(lo, t) }
        /// A model point in face A's coordinates.
        func local(_ p: Vec3) -> Vec2 {
            let x = c(p, l) - c(lo, l), y = c(p, w) - c(lo, w)
            return Vec2(x, mirrored ? width - y : y)
        }
        /// A model direction in face A's coordinates.
        func localDir(_ d: Vec3) -> Vec2 { Vec2(c(d, l), mirrored ? -c(d, w) : c(d, w)) }
        /// Height above face B.
        func z(_ p: Vec3) -> Double { c(p, t) - c(lo, t) }

        init(lo: Vec3, hi: Vec3) {
            self.lo = lo; self.hi = hi
            let ext = FamilyAxis.allCases.map { a -> (FamilyAxis, Double) in (a, a == .x ? hi.x - lo.x : (a == .y ? hi.y - lo.y : hi.z - lo.z)) }
            let s = ext.sorted { $0.1 > $1.1 + 1e-9 || (abs($0.1 - $1.1) <= 1e-9 && $0.0.idx < $1.0.idx) }
            l = s[0].0; w = s[1].0; t = s[2].0
            mirrored = l.unit.cross(w.unit).dot(t.unit) < 0
        }
    }

    /// The frame of an element part: its cut envelope (joints applied) or its box.
    static func frame(_ e: Element, _ m: BIMModel) -> Frame? {
        let sol = JointSolver.solve(m)
        if let env = sol.envelopes[e.id], sol.parts[e.id]?.reshapeable == true {
            return Frame(lo: Vec3(env.l(.x), env.l(.y), env.l(.z)), hi: Vec3(env.h(.x), env.h(.y), env.h(.z)))
        }
        guard let b = FurniturePartSolids.partBox(e, m)?.box else { return nil }
        return Frame(lo: b.min, hi: b.max)
    }

    /// The frame of a slab front's leaf (derived "<front>/front" or "<front>/leafN/front").
    static func frontFrame(_ p: CutPart, _ m: BIMModel) -> Frame? {
        guard p.isDerived, p.key.hasSuffix("/front"), let front = m[p.elementID], let g = FurnitureFronts.geometry(front, m) else { return nil }
        var index = 0
        if let r = p.key.range(of: "/leaf") { index = (Int(p.key[r.upperBound...].prefix { $0.isNumber }) ?? 1) - 1 }
        guard index < g.leaves.count else { return nil }
        let lf = g.leaves[index]
        let (u, v, w) = ((lf.u.0.value, lf.u.1.value), (lf.v.0.value, lf.v.1.value), (lf.w.0.value, lf.w.1.value))
        func mn(_ a: (Double, Double)) -> Double { min(a.0, a.1) }
        func mx(_ a: (Double, Double)) -> Double { max(a.0, a.1) }
        if g.face == .front { return Frame(lo: Vec3(mn(u), mn(w), mn(v)), hi: Vec3(mx(u), mx(w), mx(v))) }
        return Frame(lo: Vec3(mn(u), mn(v), mn(w)), hi: Vec3(mx(u), mx(v), mx(w)))
    }

    // MARK: Programs

    /// Programs for every part (faces A and B).
    public static func programs(_ m: BIMModel) -> [CNCPartProgram] {
        guard m.isFurniture else { return [] }
        let byPart = Dictionary(grouping: FurnitureMachining.entries(m), by: \.partID)
        var used: [String: Int] = [:]
        return FurnitureFabrication.parts(m).map { p in
            var name = safe(p.mark)
            used[name, default: 0] += 1
            if used[name]! > 1 { name += "_\(used[name]!)" }
            let (a, b) = drawings(p, byPart, m)
            return CNCPartProgram(part: p, name: name, faceA: a, faceB: b)
        }
    }

    /// A file-safe name ("DW1-2", "P1").
    public static func safe(_ s: String) -> String {
        let ok = s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let t = String(ok)
        return t.isEmpty ? "Part" : t
    }

    /// Face A and face B drawings of one part.
    static func drawings(_ p: CutPart, _ byPart: [ElementID: [MachiningEntry]], _ m: BIMModel) -> (CNCDrawing, CNCDrawing?) {
        let L = p.length, W = p.width
        var a = CNCDrawing(), b = CNCDrawing()
        let rect = [Vec2(0, 0), Vec2(L, 0), Vec2(L, W), Vec2(0, W)]
        var outline = rect
        var frame: Frame?
        var ops: [MachiningEntry] = []
        if !p.isDerived, let e = m[p.elementID], p.quantity == 1 {
            frame = Self.frame(e, m)
            ops = byPart[e.id] ?? []
            if let f = frame, let shaped = panelOutline(e, f), shaped.count >= 3 { outline = shaped }
            if let f = frame { for hole in panelOpenings(e, f) { a.paths.append(.init(layer: "INNER", points: hole, closed: true)) } }
        } else if let f = frontFrame(p, m) {
            frame = f
            let lo = f.lo - Vec3(0.001, 0.001, 0.001), hi = f.hi + Vec3(0.001, 0.001, 0.001)
            ops = (byPart[p.elementID] ?? []).filter { e in
                let c = center(e.op)
                return c.x >= lo.x && c.x <= hi.x && c.y >= lo.y && c.y <= hi.y && c.z >= lo.z && c.z <= hi.z
            }
        }
        a.paths.insert(.init(layer: "OUTLINE", points: outline, closed: true), at: 0)
        if let f = frame, abs(f.length - L) < 0.002, abs(f.width - W) < 0.002 {
            for e in ops { add(e, f, &a, &b) }
        }
        // Grain and label on face A (and the label on B).
        if p.grain != .none {
            let along = p.grain == .length
            let c = Vec2(L / 2, W / 2), d = along ? Vec2(1, 0) : Vec2(0, 1), half = (along ? L : W) * 0.25
            a.paths.append(.init(layer: "GRAIN", points: [c - d * half, c + d * half], closed: false))
        }
        let h = min(0.5 * inch, W * 0.3)
        a.labels.append(.init(layer: "LABEL", position: Vec2(L / 2, W / 2 + h * 0.6), height: h, text: p.mark))
        if !b.isEmpty {
            b.paths.insert(.init(layer: "OUTLINE", points: rect, closed: true), at: 0)
            b.labels.append(.init(layer: "LABEL", position: Vec2(L / 2, W / 2 + h * 0.6), height: h, text: "\(p.mark) B"))
            return (a, b)
        }
        return (a, nil)
    }

    static func center(_ op: MachiningOp) -> Vec3 {
        switch op {
        case .drill(let c, _, _, _): return c
        case .groove(let s, let e, _, _, _): return (s + e) * 0.5
        case .pocket(let o, _, _): return o.reduce(Vec3(0, 0, 0)) { $0 + $1 } * (1 / Double(max(1, o.count)))
        }
    }

    /// Adds one machining operation to face A, face B or as edge boring.
    static func add(_ e: MachiningEntry, _ f: Frame, _ a: inout CNCDrawing, _ b: inout CNCDrawing) {
        func axisT(_ v: Vec3) -> Double { f.c(v, f.t) }
        func flipB(_ p: Vec2) -> Vec2 { Vec2(p.x, f.width - p.y) }
        switch e.op {
        case .drill(let c, let axis, let dia, let depth):
            let tz = axisT(axis)
            if abs(tz) > 0.9 {
                let p = f.local(c), layer = drillLayer(diameter: dia, depth: depth)
                if tz < 0 { a.circles.append(.init(layer: layer, center: p, radius: dia / 2)) } else { b.circles.append(.init(layer: layer, center: flipB(p), radius: dia / 2)) }
            } else {
                let p = f.local(c), d = f.localDir(axis).normalized
                a.paths.append(.init(layer: "HDRILL_\(num(dia))_\(num(depth))_Z\(num(f.z(c)))", points: [p, p + d * depth], closed: false))
            }
        case .groove(let s, let en, let axis, let width, let depth):
            let tz = axisT(axis)
            let ps = f.local(s), pe = f.local(en)
            if abs(tz) > 0.9 {
                let d = (pe - ps).normalized, n = d.perpendicular * (width / 2)
                let poly = [ps + n, pe + n, pe - n, ps - n]
                if tz < 0 { a.paths.append(.init(layer: grooveLayer(depth: depth), points: poly, closed: true)) }
                else { b.paths.append(.init(layer: grooveLayer(depth: depth), points: poly.map(flipB), closed: true)) }
            } else {
                a.paths.append(.init(layer: "HGROOVE_\(num(depth))_Z\(num(f.z((s + en) * 0.5)))", points: [ps, pe], closed: false))
            }
        case .pocket(let outline, let axis, let depth):
            let tz = axisT(axis)
            let poly = outline.map(f.local)
            if abs(tz) > 0.9 {
                if tz < 0 { a.paths.append(.init(layer: pocketLayer(depth: depth), points: poly, closed: true)) }
                else { b.paths.append(.init(layer: pocketLayer(depth: depth), points: poly.map(flipB), closed: true)) }
            } else {
                let c = center(e.op)
                a.paths.append(.init(layer: "HPOCKET_\(num(depth))_Z\(num(f.z(c)))", points: poly, closed: true))
            }
        }
    }

    /// A shaped panel's outline (Edit Profile) in face A coordinates.
    static func panelOutline(_ e: Element, _ f: Frame) -> [Vec2]? {
        guard let p = e.furniturePanel, let prof = p.profile, prof.count >= 3 else { return nil }
        return prof.map { f.local(panelPoint(p, $0)) }
    }

    /// A panel's openings in face A coordinates.
    static func panelOpenings(_ e: Element, _ f: Frame) -> [[Vec2]] {
        guard let p = e.furniturePanel, let ops = p.openings else { return [] }
        return ops.map { o in [Vec2(o.s0, o.t0), Vec2(o.s1, o.t0), Vec2(o.s1, o.t1), Vec2(o.s0, o.t1)].map { f.local(panelPoint(p, $0)) } }
    }

    /// A panel's face point (s along its line, t from its base) in model coordinates.
    static func panelPoint(_ p: PanelData, _ st: Vec2) -> Vec3 {
        let d = p.length > 1e-9 ? (p.end - p.start) * (1 / p.length) : Vec2(1, 0)
        let q = p.start + d * st.x
        let w = p.base + st.y
        switch p.plane {
        case .xy: return Vec3(q.x, q.y, w)
        case .xz: return Vec3(q.x, w, q.y)
        case .yz: return Vec3(w, q.x, q.y)
        }
    }

    /// Programs for every nested sheet: the stock outline (SHEET) and each part's face A program at its place.
    public static func sheetPrograms(_ m: BIMModel) -> [CNCSheetProgram] {
        let parts = Dictionary(programs(m).map { ($0.part.key, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [CNCSheetProgram] = []
        for g in FurnitureFabrication.nesting(m) {
            for (i, s) in g.result.sheets.enumerated() {
                var d = CNCDrawing()
                d.paths.append(.init(layer: "SHEET", points: [Vec2(0, 0), Vec2(s.stock.length, 0), Vec2(s.stock.length, s.stock.width), Vec2(0, s.stock.width)], closed: true))
                for pl in s.placements {
                    guard let key = g.partKeys[pl.key], let prog = parts[key] else { continue }
                    d.append(prog.faceA.placed(at: pl.rect.min, rotated: pl.rotated, width: prog.part.width))
                }
                let base = safe("\(m[g.materialID]?.name ?? "Material")_\(num(g.thickness))in")
                out.append(CNCSheetProgram(name: "\(base)_Sheet\(i + 1)", group: g, index: i, drawing: d))
            }
        }
        return out
    }

    // MARK: CSV

    /// The part list as CSV for the CNC software: one row per part, with its program files.
    public static func csv(_ m: BIMModel, units: (Double) -> String = { FurnitureCNC.num($0) }) -> String {
        func q(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var lines = ["Mark,Part,Material,Thickness (in),Length (in),Width (in),Qty,Grain,Edge Banding,Face A File,Face B File"]
        for p in programs(m) {
            let mat = m[p.part.materialID]?.name ?? ""
            lines.append([p.part.mark, p.part.name, mat, units(p.part.thickness), units(p.part.length), units(p.part.width), "\(p.part.quantity)",
                          p.part.grain.rawValue, p.part.banding.code, p.name + ".dxf", p.faceB == nil ? "" : p.name + "_B.dxf"].map(q).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
