import Foundation
import ArcusGeometry

// FMG3: bays, doors, drawers and flaps on any face of a piece, as Revit-style casework is hosted on whichever face it
// is drawn on. A bay keeps the direction it is seen from (`BayData.facing`, the angle of its frame); its opening, its
// fronts' leaves and their hardware are found in the bay's own frame, where the face looks like the front (u to the
// viewer's right, v into the piece, z up), and are turned into the model at the end. A face square to the piece (Back,
// Left, Right) keeps every coordinate on its plane, so its fronts flex in a loaded family as front ones do; a canted
// face (a corner cabinet's 45° door) writes its coordinates as formulas of the planes they follow.

/// A sum of planes in a part coordinate: `value = Σ coefficient · position(plane) + offset`. A single plane keeps its
/// name; other sums are written as one plane name, "⟨-1.0×Left⟩" or "⟨0.7071×Front‖0.7071×Left⟩", so the coordinates
/// of a turned face pass through everything that carries a plane name (bounds, shifts, midpoints).
public enum PlaneTerms {
    static let open = "⟨", close = "⟩", separator = "‖", times = "×"

    /// True for a sum of planes (not a single plane name).
    public static func isSum(_ name: String?) -> Bool { name?.hasPrefix(open) == true && name?.hasSuffix(close) == true }

    /// The planes of a name and their coefficients (a single plane: its name and 1).
    public static func terms(_ name: String?) -> [String: Double] {
        guard let name else { return [:] }
        guard isSum(name) else { return [name: 1] }
        var out: [String: Double] = [:]
        for part in name.dropFirst().dropLast().components(separatedBy: separator) {
            guard let r = part.range(of: times), let c = Double(part[..<r.lowerBound]) else { continue }
            out[String(part[r.upperBound...]), default: 0] += c
        }
        return out
    }

    /// The name of a sum (nil when every coefficient is zero).
    public static func name(_ terms: [String: Double]) -> String? {
        let kept = terms.filter { abs($0.value) > 1e-12 }
        guard !kept.isEmpty else { return nil }
        if kept.count == 1, let (n, c) = kept.first, abs(c - 1) < 1e-12 { return n }
        return open + kept.keys.sorted().map { "\(kept[$0] ?? 0)\(times)\($0)" }.joined(separator: separator) + close
    }

    /// The sum as a length formula of the family's planes (`formula` gives a plane's offset formula, a number when the
    /// plane doesn't move), with `offset` (meters) added; nil when a plane is unknown.
    public static func expression(_ name: String, offset: Double, _ formula: (String) -> String?) -> String? {
        var parts: [String] = []
        for (plane, c) in terms(name).sorted(by: { $0.key < $1.key }) where abs(c) > 1e-12 {
            guard let f = formula(plane)?.trimmingCharacters(in: .whitespaces) else { return nil }
            let term = Double(f).map { "\(FurnitureFormLocks.num($0)) m" } ?? "(\(f))"
            parts.append(abs(c - 1) < 1e-12 ? term : "\(FurnitureFormLocks.num(c)) * \(term)")
        }
        guard !parts.isEmpty else { return nil }
        return "(" + parts.joined(separator: " + ") + ") \(offset < 0 ? "-" : "+") \(FurnitureFormLocks.num(abs(offset))) m"
    }
}

extension PartValue {
    /// The part that doesn't follow a plane (the whole value when it follows none).
    var constant: Double { plane == nil ? value : offset }

    /// `k` times the coordinate (its planes scaled too).
    public func scaled(_ k: Double) -> PartValue {
        guard let n = PlaneTerms.name(PlaneTerms.terms(plane).mapValues { $0 * k }) else { return PartValue(value * k) }
        return PartValue(value * k, plane: n, offset: constant * k)
    }

    /// The sum of two coordinates (planes added term by term).
    public static func sum(_ a: PartValue, _ b: PartValue) -> PartValue {
        var t = PlaneTerms.terms(a.plane)
        for (n, c) in PlaneTerms.terms(b.plane) { t[n, default: 0] += c }
        guard let n = PlaneTerms.name(t) else { return PartValue(a.value + b.value) }
        return PartValue(a.value + b.value, plane: n, offset: a.constant + b.constant)
    }
}

/// The frame of a bay's face: `world = R(angle) · local`, about the piece's origin. The front frame is the identity
/// (local = model); the back is turned 180°, the left -90° and the right 90°; a canted face any angle.
public struct BayFrame: Hashable, Sendable {
    /// Radians, counterclockwise, in [0, 2π).
    public let angle: Double
    public let c: Double
    public let s: Double

    public init(angle a: Double) {
        let twoPi = 2 * Double.pi
        var n = a.truncatingRemainder(dividingBy: twoPi)
        if n < 0 { n += twoPi }
        let q = (n / (.pi / 2)).rounded()
        if abs(n - q * .pi / 2) < 1e-6 {
            let k = Int(q) % 4
            angle = Double(k) * .pi / 2
            (c, s) = [(1.0, 0.0), (0, 1), (-1, 0), (0, -1)][k]
        } else {
            angle = n; c = cos(n); s = sin(n)
        }
    }

    public static let front = BayFrame(angle: 0)

    /// The frame of a bay (front-facing bays and top-access bays: the identity).
    public init(_ bay: BayData) { self.init(angle: bay.face == .front ? (bay.facing ?? 0) : 0) }

    /// The frame of a view looking at a face: its right vector is the face's u.
    public init?(view v: ViewData?) {
        guard let v, v.kind.isVerticalCut, let r = v.rightVector, r.length > 1e-9 else { return nil }
        self.init(angle: atan2(r.y, r.x))
    }

    /// 0…3 for faces square to the piece (front, right, back, left), nil for canted ones.
    public var quarter: Int? {
        if abs(s) < 1e-12 { return c > 0 ? 0 : 2 }
        if abs(c) < 1e-12 { return s > 0 ? 1 : 3 }
        return nil
    }
    public var isIdentity: Bool { quarter == 0 }
    public var isSquare: Bool { quarter != nil }

    /// What Properties call the face.
    public var name: String {
        switch quarter {
        case 0?: "Front"
        case 1?: "Right"
        case 2?: "Back"
        case 3?: "Left"
        default: "Angled \(FurnitureFormLocks.num((angle * 180 / .pi * 10).rounded() / 10))°"
        }
    }

    /// The stored angle for a bay (nil for the front, so older files stay as they were).
    public var stored: Double? { isIdentity ? nil : angle }

    // MARK: Points

    public func world(_ p: Vec2) -> Vec2 { Vec2(c * p.x - s * p.y, s * p.x + c * p.y) }
    public func local(_ p: Vec2) -> Vec2 { Vec2(c * p.x + s * p.y, -s * p.x + c * p.y) }
    public func world(_ p: Vec3) -> Vec3 { Vec3(world(p.xy), z: p.z) }
    public func local(_ p: Vec3) -> Vec3 { Vec3(local(p.xy), z: p.z) }
    public func worldCurve(_ cv: Curve2) -> Curve2 { isIdentity ? cv : cv.transformed(Transform2.rotation(angle)) }
    /// The face's outward normal in plan (toward the viewer).
    public var outward: Vec2 { world(Vec2(0, -1)) }
    /// The view direction that looks at the face.
    public var viewDirection: Vec2 { world(Vec2(0, 1)) }

    /// True when a vertical view looks straight at this face.
    public func faces(_ forward: Vec2) -> Bool { forward.normalized.dot(viewDirection) > 0.999 }

    // MARK: Coordinates with their planes

    public func worldX(_ u: PartValue, _ v: PartValue) -> PartValue { .sum(u.scaled(c), v.scaled(-s)) }
    public func worldY(_ u: PartValue, _ v: PartValue) -> PartValue { .sum(u.scaled(s), v.scaled(c)) }
    public func localU(_ x: PartValue, _ y: PartValue) -> PartValue { .sum(x.scaled(c), y.scaled(s)) }
    public func localV(_ x: PartValue, _ y: PartValue) -> PartValue { .sum(x.scaled(-s), y.scaled(c)) }

    /// A local point with its planes in the model.
    public func world(_ p: (x: PartValue, y: PartValue, z: PartValue)) -> (x: PartValue, y: PartValue, z: PartValue) {
        isIdentity ? p : (worldX(p.x, p.y), worldY(p.x, p.y), p.z)
    }

    /// A box's extent seen in this frame: the low and high u and v over its corners (with their planes).
    public func localBox(_ b: FurniturePartSolids.PartBox) -> FurniturePartSolids.PartBox {
        if isIdentity { return b }
        func pick(_ r: (PartValue, PartValue), _ k: Double) -> (PartValue, PartValue) { k >= 0 ? r : (r.1, r.0) }
        let xu = pick(b.x, c), yu = pick(b.y, s), xv = pick(b.x, -s), yv = pick(b.y, c)
        return .init(x: (localU(xu.0, yu.0), localU(xu.1, yu.1)), y: (localV(xv.0, yv.0), localV(xv.1, yv.1)), z: b.z)
    }

    /// A local box's extent in the model (faces square to the piece; a canted frame gives its bounding box).
    public func worldBox(_ b: FurniturePartSolids.PartBox) -> FurniturePartSolids.PartBox {
        if isIdentity { return b }
        func pick(_ r: (PartValue, PartValue), _ k: Double) -> (PartValue, PartValue) { k >= 0 ? r : (r.1, r.0) }
        let ux = pick(b.x, c), vx = pick(b.y, -s), uy = pick(b.x, s), vy = pick(b.y, c)
        return .init(x: (worldX(ux.0, vx.0), worldX(ux.1, vx.1)), y: (worldY(uy.0, vy.0), worldY(uy.1, vy.1)), z: b.z)
    }

    /// Faces square to the piece: the model axis local u runs along and its sign.
    public var uAxis: (axis: FamilyAxis, sign: Double)? {
        guard let q = quarter else { return nil }
        return q % 2 == 0 ? (.x, c) : (.y, s)
    }
    /// Faces square to the piece: the model axis local v (depth) runs along and its sign.
    public var vAxis: (axis: FamilyAxis, sign: Double)? {
        guard let q = quarter else { return nil }
        return q % 2 == 0 ? (.y, c) : (.x, -s)
    }

    /// The model coordinate along `uAxis` of a local u (faces square to the piece).
    public func worldAlongU(_ u: PartValue) -> PartValue { u.scaled(uAxis?.sign ?? 1) }

    // MARK: Solids

    /// A local box as a model solid: a box on the planes for faces square to the piece, a plan polygon (corners as
    /// formulas when compiling) for canted ones.
    func solid(_ name: String, x: (PartValue, PartValue), y: (PartValue, PartValue), z: (PartValue, PartValue), _ ctx: PartSolidContext, void isVoid: Bool) -> FamilySolid {
        func sorted(_ r: (PartValue, PartValue)) -> (PartValue, PartValue) { r.0.value <= r.1.value ? r : (r.1, r.0) }
        let lb = FurniturePartSolids.PartBox(x: sorted(x), y: sorted(y), z: sorted(z))
        if isSquare {
            let wb = worldBox(lb)
            return FamilySolid(name: name, profile: .rectangle(xMin: ctx.bound(wb.x.0), xMax: ctx.bound(wb.x.1), yMin: ctx.bound(wb.y.0), yMax: ctx.bound(wb.y.1)),
                               zMin: ctx.bound(wb.z.0), zMax: ctx.bound(wb.z.1), isVoid: isVoid)
        }
        let corners = [(lb.x.0, lb.y.0), (lb.x.1, lb.y.0), (lb.x.1, lb.y.1), (lb.x.0, lb.y.1)]
        if ctx.symbolic, let a = ctx.cantAnchors {
            let pts = corners.compactMap { a.point($0.0.value, $0.1.value, ctx) }.map { FamilyPoint($0.0, $0.1) }
            if pts.count == 4 { return FamilySolid(name: name, profile: .polygon(pts), zMin: ctx.bound(lb.z.0), zMax: ctx.bound(lb.z.1), isVoid: isVoid) }
        }
        let pts = corners.map { FamilyPoint(ctx.bound(worldX($0.0, $0.1)), ctx.bound(worldY($0.0, $0.1))) }
        return FamilySolid(name: name, profile: .polygon(pts), zMin: ctx.bound(lb.z.0), zMax: ctx.bound(lb.z.1), isVoid: isVoid)
    }

    /// A local prism (numbers) as a model solid: turned in plan when it lies on XY, onto the turned plane for faces
    /// square to the piece, else its box.
    func prism(_ name: String, plane: FamilySketchPlane, _ pts: [Vec2], w: (PartValue, PartValue), _ ctx: PartSolidContext, void isVoid: Bool) -> FamilySolid {
        let (w0, w1) = w.0.value <= w.1.value ? (w.0, w.1) : (w.1, w.0)
        if plane == .xy {
            let poly = Polygon2(pts.map(world)).counterClockwise
            return FamilySolid(name: name, profile: .polygon(poly.points.map(ctx.point)), zMin: ctx.bound(w0), zMax: ctx.bound(w1), isVoid: isVoid)
        }
        // In-plane horizontal axis a (u) and the normal n (w) of the local plane, as model axes.
        if isSquare {
            let (aLocal, nLocal): (Vec2, Vec2) = plane == .xz ? (Vec2(1, 0), Vec2(0, 1)) : (Vec2(0, 1), Vec2(1, 0))
            let a = world(aLocal), n = world(nLocal)
            let toYZ = abs(a.y) > 0.5
            let su = toYZ ? a.y : a.x, sw = toYZ ? n.x : n.y
            let poly = Polygon2(pts.map { Vec2($0.x * su, $0.y) }).counterClockwise
            let ws = [w0.scaled(sw), w1.scaled(sw)].sorted { $0.value < $1.value }
            var s = FamilySolid(name: name, profile: .polygon(poly.points.map(ctx.point)), zMin: ctx.bound(ws[0]), zMax: ctx.bound(ws[1]), isVoid: isVoid)
            s.workPlane = toYZ ? .yz : .xz
            return s
        }
        let corners = pts.flatMap { p in [plane.point(p.x, p.y, w0.value), plane.point(p.x, p.y, w1.value)] }
        let local = corners.reduce(Box3.empty) { $0.union(Box3(min: $1, max: $1)) }
        return solid(name, x: (PartValue(local.min.x), PartValue(local.max.x)), y: (PartValue(local.min.y), PartValue(local.max.y)),
                     z: (PartValue(local.min.z), PartValue(local.max.z)), ctx, void: isVoid)
    }

    /// A local family placed in the bay's frame, placed in the model.
    func placed(_ p: PlacedLocalFamily) -> PlacedLocalFamily {
        guard !isIdentity else { return p }
        var q = p
        let w = world((p.x, p.y, p.z))
        q.x = w.x; q.y = w.y; q.z = w.z
        q.rotation = p.rotation + angle * 180 / .pi
        return q
    }
}

/// Compiling a front on a canted face: the face's two front corners in the model (with their planes), so the front's
/// solids and hardware stay between them when a loaded piece flexes out of square (the face then turns a little, as a
/// door on a reference line between two planes does).
public struct CantAnchors: Sendable {
    public var p0: (x: PartValue, y: PartValue)
    public var p1: (x: PartValue, y: PartValue)
    public var u0: Double, v0: Double, u1: Double, v1: Double

    public init?(_ o: BayOpening, _ f: BayFrame) {
        guard let c = o.cant, c.count == 4, !f.isSquare else { return nil }
        let a = (o.value("cant.u0"), o.value("cant.v0")), b = (o.value("cant.u1"), o.value("cant.v1"))
        p0 = (f.worldX(a.0, a.1), f.worldY(a.0, a.1))
        p1 = (f.worldX(b.0, b.1), f.worldY(b.0, b.1))
        u0 = c[0]; v0 = c[1]; u1 = c[2]; v1 = c[3]
    }

    /// A local point (u along the face, v into it) as formulas of the planes: from the nearer corner, along the line
    /// between the corners and square to it.
    public func point(_ u: Double, _ v: Double, _ ctx: PartSolidContext) -> (FamilyBound, FamilyBound)? {
        guard let formula = ctx.planeFormula else { return nil }
        func e(_ p: PartValue) -> String? {
            guard let n = p.plane else { return "\(FurnitureFormLocks.num(p.value)) m" }
            return PlaneTerms.expression(n, offset: p.offset, formula)
        }
        guard let x0 = e(p0.x), let y0 = e(p0.y), let x1 = e(p1.x), let y1 = e(p1.y) else { return nil }
        let dx = "((\(x1)) - (\(x0)))", dy = "((\(y1)) - (\(y0)))"
        let len = "sqrt(\(dx) * \(dx) + \(dy) * \(dy))"
        let near0 = abs(u - u0) <= abs(u - u1)
        let (ax, ay, du, dv) = near0 ? (x0, y0, u - u0, v - v0) : (x1, y1, u - u1, v - v1)
        let n = FurnitureFormLocks.num
        let x = "(\(ax)) + \(dx) / \(len) * (\(n(du)) m) - \(dy) / \(len) * (\(n(dv)) m)"
        let y = "(\(ay)) + \(dy) / \(len) * (\(n(du)) m) + \(dx) / \(len) * (\(n(dv)) m)"
        return (.expr(x), .expr(y))
    }
}
