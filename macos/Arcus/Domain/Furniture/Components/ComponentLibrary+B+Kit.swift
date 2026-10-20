import Foundation
import ArcusGeometry

// COMPB: geometry and symbol helpers Group B's definitions are written with, on top of the kit's ComponentBuilder.
//
// Round parts are drawn as 24-sided prisms and revolves: the kit's circle profile tessellates to 2 mm chords, which
// makes a 5 mm shelf pin a triangle. Detail levels follow Revit's habit for hardware: Coarse shows the symbol (and,
// for structural pieces in the plan frame such as legs, bases and casters, a plain envelope solid), Medium the real
// shape, Fine adds threads, screws, flutes and other small pieces.

/// Detail level sets.
enum CBL {
    static let coarse: Set<DetailLevel> = [.coarse]
    static let mediumFine: Set<DetailLevel> = [.medium, .fine]
    static let fine: Set<DetailLevel> = [.fine]
    static let all: Set<DetailLevel> = [.coarse, .medium, .fine]
}

/// Expression helpers.
enum CBE {
    /// "-(e)".
    static func neg(_ e: String) -> String { "-(\(e))" }
    /// "(e) / 2".
    static func half(_ e: String) -> String { "(\(e)) / 2" }
    /// "-(e) / 2".
    static func nhalf(_ e: String) -> String { "-(\(e)) / 2" }
}

extension ComponentBuilder {
    // MARK: Scoped settings

    /// Adds what `body` adds at `levels`, then restores the current levels.
    mutating func at(_ levels: Set<DetailLevel>, _ body: (inout ComponentBuilder) -> Void) {
        let saved = visibleAt
        visibleAt = levels
        body(&self)
        visibleAt = saved
    }

    /// Adds what `body` adds with the material slot `slot`.
    mutating func slot(_ slot: String, _ body: (inout ComponentBuilder) -> Void) {
        let saved = currentMaterial
        currentMaterial = slot
        body(&self)
        currentMaterial = saved
    }

    /// Adds what `body` adds shown by the Yes/No parameter `flag`.
    mutating func shown(by flag: String?, _ body: (inout ComponentBuilder) -> Void) {
        let saved = visibility
        visibility = flag
        body(&self)
        visibility = saved
    }

    // MARK: Smooth round forms

    /// A smooth round bar along `axis` (24-sided), centred at `c` on the plane across it ((X, Y) for Z, (X, Z) for Y,
    /// (Y, Z) for X).
    @discardableResult
    mutating func rod(_ name: String, axis: FamilyAxis = .z, c: (String, String) = (CX.zero, CX.zero), r: String, from: String, to: String,
                      void: Bool = false, sides: Int = 24) -> String {
        extrusion(name, profile: ComponentKit.circle(center: c, radius: r, segments: sides), plane: Self.plane(normal: axis), from: from, to: to, void: void)
    }

    /// An oval bar along `axis`: half widths `ru` and `rv` on the plane across it (oval wardrobe rails, tubes).
    @discardableResult
    mutating func ovalRod(_ name: String, axis: FamilyAxis, c: (String, String) = (CX.zero, CX.zero), ru: String, rv: String, from: String, to: String) -> String {
        let pts = (0..<28).map { k -> FamilyPoint in
            let a = Double(k) / 28 * 2 * .pi
            return FamilyPoint("\(c.0) + (\(ru)) * \(LX.num(cos(a)))", "\(c.1) + (\(rv)) * \(LX.num(sin(a)))")
        }
        return extrusion(name, profile: pts, plane: Self.plane(normal: axis), from: from, to: to)
    }

    /// A round tube: a smooth bar with a bore cut by a void that cuts only it.
    mutating func pipe(_ name: String, axis: FamilyAxis = .z, c: (String, String) = (CX.zero, CX.zero), outer: String, inner: String, from: String, to: String) {
        let id = rod(name, axis: axis, c: c, r: outer, from: from, to: to)
        let v = rod("\(name) Bore", axis: axis, c: c, r: inner, from: from, to: to, void: true)
        if let k = definition.family.solids.firstIndex(where: { $0.id == v }) { definition.family.solids[k].cuts = [id] }
    }

    /// A turned form: an (r, h) profile turned about an axis parallel to `axis` through `c`, h measured from `base`.
    @discardableResult
    mutating func turn(_ name: String, axis: FamilyAxis = .z, c: (String, String) = (CX.zero, CX.zero), base: String = CX.zero, _ profile: [(String, String)]) -> String {
        revolve(name, profile: ComponentKit.points(profile), plane: Self.plane(normal: axis), axis: c, base: base)
    }

    /// A round (or n-sided) bar from a bottom centre to a top centre on Z, tapering from r0 to r1: splayed legs, rods.
    @discardableResult
    mutating func strut(_ name: String, bottom: (String, String), top: (String, String), r0: String, r1: String, z: (String, String), sides: Int = 20) -> String {
        blend(name, bottom: ComponentKit.circle(center: bottom, radius: r0, segments: sides), top: ComponentKit.circle(center: top, radius: r1, segments: sides),
              from: z.0, to: z.1)
    }

    /// A tapering square bar on Z (tapered legs): w0 × w0 at z0 to w1 × w1 at z1.
    @discardableResult
    mutating func taperedBox(_ name: String, w0: String, w1: String, d0: String? = nil, d1: String? = nil, z: (String, String)) -> String {
        blend(name, bottom: ComponentKit.rect(width: w0, height: d0 ?? w0), top: ComponentKit.rect(width: w1, height: d1 ?? w1), from: z.0, to: z.1)
    }

    /// A flat plate with rounded corners in the XY plane from z0 to z1.
    @discardableResult
    mutating func plate(_ name: String, c: (String, String) = (CX.zero, CX.zero), w: String, h: String, r: String, z: (String, String)) -> String {
        roundedBar(name, center: c, width: w, height: h, radius: r, from: z.0, to: z.1)
    }

    /// Screw heads on a face at the given (x, y) points, standing `height` out of z.
    mutating func screwHeads(_ name: String, _ pts: [(String, String)], z: String, diameter: String = CX.mm(7), height: String = CX.mm(1.5)) {
        for (k, p) in pts.enumerated() {
            turn("\(name) \(k + 1)", c: p, base: z, [(CX.zero, CX.zero), ("(\(diameter)) / 2", CX.zero), ("(\(diameter)) / 2 * 0.8", height), (CX.zero, height)])
        }
    }

    // MARK: Symbols

    /// A circle symbol.
    mutating func symCircle(_ view: ComponentSymbolView, _ levels: Set<DetailLevel>, c: (String, String) = (CX.zero, CX.zero), r: String, dashed: Bool = false) {
        symbol(view, levels, dashed: dashed, .circle(c, r))
    }
    /// A rectangle symbol from corner to corner.
    mutating func symRect(_ view: ComponentSymbolView, _ levels: Set<DetailLevel>, _ a: (String, String), _ b: (String, String), dashed: Bool = false) {
        symbol(view, levels, dashed: dashed, .rect(a, b))
    }
    /// A centre mark (cross) of half size `s` at `c`.
    mutating func symCross(_ view: ComponentSymbolView, _ levels: Set<DetailLevel>, c: (String, String) = (CX.zero, CX.zero), s: String) {
        symbol(view, levels, .line(("\(c.0) - (\(s))", c.1), ("\(c.0) + (\(s))", c.1)), .line((c.0, "\(c.1) - (\(s))"), (c.0, "\(c.1) + (\(s))")))
    }
    /// A line symbol.
    mutating func symLine(_ view: ComponentSymbolView, _ levels: Set<DetailLevel>, _ a: (String, String), _ b: (String, String), dashed: Bool = false) {
        symbol(view, levels, dashed: dashed, .line(a, b))
    }

    /// The usual symbol set of a round plan-frame item (a foot, a caster, a glide): its outline and centre mark in plan
    /// at every level, its side outline at Coarse.
    mutating func roundFootSymbols(r: String, top: String, bottom: String) {
        symCircle(.face, CBL.all, r: r)
        symCross(.face, CBL.coarse, s: "(\(r)) * 0.5")
        symRect(.side, CBL.coarse, (bottom, CBE.neg(r)), (top, r))
    }

    /// The usual symbol set of a rectangular face-frame item: its outline on the face at Coarse (with a centre mark)
    /// and its outline in plan (looking down onto X–Z).
    mutating func boxSymbols(x: (String, String), y: (String, String), z: (String, String)) {
        symRect(.face, CBL.all, (x.0, y.0), (x.1, y.1))
        symRect(.top, CBL.coarse, (x.0, z.0), (x.1, z.1))
        symRect(.side, CBL.coarse, (z.0, y.0), (z.1, y.1))
    }

    /// Redraws every circle-profile solid (FM5's families use them) as a smooth 24-sided polygon with the same
    /// centre and radius formulas, so small round hardware isn't drawn as a triangle.
    mutating func smoothCircles() {
        for k in definition.family.solids.indices {
            guard case .circle(let c, let r) = definition.family.solids[k].profile else { continue }
            func text(_ b: FamilyBound) -> String { if case .expr(let e) = b { return e }; return CX.zero }
            definition.family.solids[k].profile = .polygon(ComponentKit.circle(center: (text(c.x), text(c.y)), radius: r, segments: 24))
        }
    }

    // MARK: Library data

    /// Removes a type an upgrade redefines (FM5 types are kept unless redefined).
    mutating func dropType(_ name: String) { definition.types.removeAll { $0.name == name } }

    /// Standard catalogue text: "Generic <name>, <type>".
    static func gen(_ model: String) -> String { "GEN-\(model)" }
}
