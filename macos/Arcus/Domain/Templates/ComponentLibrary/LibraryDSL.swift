import Foundation
import ArcusGeometry

// Small builder vocabulary used to write the component library's families as data. Everything here is internal;
// the public surface is `ComponentLibrary` and `ComponentLibraryLoader`.

/// A linear expression Σ kᵢ·parameterᵢ + c (meters), written out as a family formula.
struct LX: Hashable, Sendable {
    var terms: [String: Double] = [:]
    var c: Double = 0

    init(_ c: Double) { self.c = c }
    init(_ name: String, _ k: Double = 1, _ c: Double = 0) { terms = [name: k]; self.c = c }

    private static let order = ["Width": 0, "Depth": 1, "Height": 2]

    /// Family formula text: "Width * 0.5 - 0.05 m", "-Depth * 0.5", or a bare number for constants.
    var formula: String {
        let names = terms.keys.filter { abs(terms[$0]!) > 1e-12 }
            .sorted { (Self.order[$0] ?? 9, $0) < (Self.order[$1] ?? 9, $1) }
        var s = ""
        for n in names {
            let k = terms[n]!
            let body = abs(abs(k) - 1) < 1e-12 ? n : "\(n) * \(LX.num(abs(k)))"
            if s.isEmpty { s = k < 0 ? "-" + body : body } else { s += k < 0 ? " - \(body)" : " + \(body)" }
        }
        if s.isEmpty { return LX.num(c) }
        if abs(c) > 1e-12 { s += c < 0 ? " - \(LX.num(-c)) m" : " + \(LX.num(c)) m" }
        return s
    }

    static func num(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    /// Value for concrete parameter values (used for sanity checks and previews).
    func value(_ params: [String: Double]) -> Double {
        terms.reduce(c) { $0 + $1.value * (params[$1.key] ?? 0) }
    }

    var bound: FamilyBound { .expr(formula) }

    static func + (a: LX, b: LX) -> LX {
        var r = a
        for (k, v) in b.terms { r.terms[k, default: 0] += v }
        r.c += b.c
        return r
    }
    static func - (a: LX, b: LX) -> LX { a + (-b) }
    static prefix func - (a: LX) -> LX { a * -1 }
    static func * (a: LX, k: Double) -> LX { LX(terms: a.terms.mapValues { $0 * k }, c: a.c * k) }
    static func + (a: LX, k: Double) -> LX { var r = a; r.c += k; return r }
    static func - (a: LX, k: Double) -> LX { var r = a; r.c -= k; return r }
    private init(terms: [String: Double], c: Double) { self.terms = terms; self.c = c }
}

/// Default appearance roles for library families. Each role becomes a material type parameter ("Upholstery
/// Material", …) whose default is a project material created (or reused by name) when the family is first loaded.
enum LM: String, CaseIterable, Sendable {
    case fabric, fabricAccent, leather, wood, woodDark, woodLight, laminate, lacquer, metal, chrome, steelDark, brass
    case glass, mirror, porcelain, stone, plastic, plasticDark, mattress, bedding, cushion, foliage, foliageDark, bark
    case concrete, rubber, paint, paintAccent, lens, skin, clothing, clothingDark, water, soil, rope, paperShade, marking, markingBlue, signFace
    case signRed, signGreen, signBlue, appliance, applianceDark, screen, terracotta

    var paramName: String {
        switch self {
        case .fabric: "Upholstery Material"
        case .fabricAccent: "Accent Fabric Material"
        case .leather: "Leather Material"
        case .wood: "Wood Material"
        case .woodDark: "Dark Wood Material"
        case .woodLight: "Light Wood Material"
        case .laminate: "Laminate Material"
        case .lacquer: "Finish Material"
        case .metal: "Metal Material"
        case .chrome: "Chrome Material"
        case .steelDark: "Dark Metal Material"
        case .brass: "Brass Material"
        case .glass: "Glass Material"
        case .mirror: "Mirror Material"
        case .porcelain: "Porcelain Material"
        case .stone: "Stone Material"
        case .plastic: "Plastic Material"
        case .plasticDark: "Dark Plastic Material"
        case .mattress: "Mattress Material"
        case .bedding: "Bedding Material"
        case .cushion: "Cushion Material"
        case .foliage: "Foliage Material"
        case .foliageDark: "Dark Foliage Material"
        case .bark: "Trunk Material"
        case .concrete: "Concrete Material"
        case .rubber: "Rubber Material"
        case .paint: "Body Material"
        case .paintAccent: "Trim Material"
        case .lens: "Lens Material"
        case .skin: "Figure Material"
        case .clothing: "Clothing Material"
        case .clothingDark: "Dark Clothing Material"
        case .water: "Water Material"
        case .soil: "Soil Material"
        case .rope: "Cord Material"
        case .paperShade: "Shade Material"
        case .marking: "Marking Material"
        case .markingBlue: "Accessible Marking Material"
        case .signFace: "Sign Face Material"
        case .signRed: "Sign Red Material"
        case .signGreen: "Sign Green Material"
        case .signBlue: "Sign Blue Material"
        case .appliance: "Appliance Material"
        case .applianceDark: "Appliance Trim Material"
        case .screen: "Screen Material"
        case .terracotta: "Pot Material"
        }
    }

    var material: ComponentMaterial {
        func m(_ n: String, _ c: MaterialClass, _ hex: UInt32, _ t: Double = 0) -> ComponentMaterial {
            ComponentMaterial(name: n, materialClass: c, color: RGBColor(hex: hex), transparency: t)
        }
        switch self {
        case .fabric: return m("Upholstery - Warm Grey", .generic, 0x8E8A84)
        case .fabricAccent: return m("Upholstery - Slate Blue", .generic, 0x5C6F86)
        case .leather: return m("Leather - Tan", .generic, 0x8C5A36)
        case .wood: return m("Timber - Oak", .wood, 0xB88A5A)
        case .woodDark: return m("Timber - Walnut", .wood, 0x6B4A32)
        case .woodLight: return m("Timber - Birch", .wood, 0xD9BE92)
        case .laminate: return m("Laminate - White", .plastic, 0xECEAE4)
        case .lacquer: return m("Lacquer - Soft White", .paint, 0xF1EFEA)
        case .metal: return m("Brushed Steel", .metal, 0xA7ACB1)
        case .chrome: return m("Chrome", .metal, 0xD4D8DC)
        case .steelDark: return m("Powder Coat - Charcoal", .metal, 0x3A3D41)
        case .brass: return m("Brass - Satin", .metal, 0xB89A5A)
        case .glass: return m("Glass", .glass, 0x9FC4D6, 0.7)
        case .mirror: return m("Mirror", .glass, 0xC9D6DD, 0.1)
        case .porcelain: return m("Vitreous China - White", .ceramic, 0xF5F4F0)
        case .stone: return m("Stone - Quartz Light", .stone, 0xE3DFD8)
        case .plastic: return m("Plastic - White", .plastic, 0xEEEEEC)
        case .plasticDark: return m("Plastic - Black", .plastic, 0x2A2B2D)
        case .mattress: return m("Mattress Ticking", .generic, 0xEDE9E1)
        case .bedding: return m("Bedding - Linen", .generic, 0xD9D2C4)
        case .cushion: return m("Cushion - Natural", .generic, 0xC9B79A)
        case .foliage: return m("Foliage - Green", .generic, 0x5E8A45)
        case .foliageDark: return m("Foliage - Deep Green", .generic, 0x3E6436)
        case .bark: return m("Bark", .wood, 0x6A5140)
        case .concrete: return m("Concrete, Precast", .concrete, 0xB5B1A9)
        case .rubber: return m("Rubber - Black", .plastic, 0x222222)
        case .paint: return m("Vehicle Paint - Silver", .paint, 0xAEB4BA)
        case .paintAccent: return m("Vehicle Trim - Dark", .paint, 0x33373C)
        case .lens: return m("Diffuser - Opal", .plastic, 0xFBF8EE, 0.15)
        case .skin: return m("Entourage - Figure", .generic, 0xB9BDC4)
        case .clothing: return m("Entourage - Light", .generic, 0x9AA6B5)
        case .clothingDark: return m("Entourage - Dark", .generic, 0x5B6573)
        case .water: return m("Water", .liquid, 0x6FA3C8, 0.4)
        case .soil: return m("Soil - Planting", .earth, 0x5A4633)
        case .rope: return m("Cord - Black", .plastic, 0x1E1E1E)
        case .paperShade: return m("Shade - Paper", .generic, 0xF4EEDF)
        case .marking: return m("Pavement Marking - White", .paint, 0xF4F4F0)
        case .markingBlue: return m("Pavement Marking - Blue", .paint, 0x2F5DA8)
        case .signFace: return m("Sign Face - White", .paint, 0xF7F7F5)
        case .signRed: return m("Sign Face - Red", .paint, 0xC7302B)
        case .signGreen: return m("Sign Face - Green", .paint, 0x2E8B57)
        case .signBlue: return m("Sign Face - Blue", .paint, 0x2F5DA8)
        case .appliance: return m("Appliance - Stainless", .metal, 0xC4C8CC)
        case .applianceDark: return m("Appliance - Black Glass", .glass, 0x1F2226)
        case .screen: return m("Screen - Black", .glass, 0x141619)
        case .terracotta: return m("Terracotta", .ceramic, 0xB86B4B)
        }
    }
}

/// Size system of a library type name.
enum SZ { case metric, imperial, neutral }

/// Builds one library family: standard Width/Depth/Height type parameters plus extras, solids, plan symbols and
/// typed sizes with their regions.
struct FB {
    var f: FamilyDefinition
    var category: Category
    var group: String
    var regions: [LibraryRegion]
    var keywords: [String]
    var usedMaterials: [LM] = []
    var typeSpecs: [ComponentLibraryType] = []
    var extras: [String] = []
    /// Yes/No parameter controlling the visibility of solids and plan lines added while it is set.
    var visibility: String?

    /// `extra` names additional length type parameters; `instance` names length instance parameters
    /// (their type values are the defaults).
    init(_ name: String, _ template: FamilyTemplate, group: String, regions: [LibraryRegion] = [.global], keywords: [String] = [],
         extra: [String] = [], instance: [String] = [], _ description: String) {
        f = FamilyDefinition(name: name, template: template)
        f.description = description
        category = template.category
        self.group = group
        self.regions = regions
        self.keywords = keywords
        extras = extra + instance
        f.parameters = [FB.len("Width", builtIn: true), FB.len("Depth", builtIn: true), FB.len("Height", builtIn: true)]
            + extra.map { FB.len($0) } + instance.map { FB.len($0, instance: true) }
        f.referencePlanes = [
            FamilyReferencePlane(name: "Center (Left/Right)", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
            FamilyReferencePlane(name: "Left", axis: .x, offset: "-Width / 2", strength: .left),
            FamilyReferencePlane(name: "Right", axis: .x, offset: "Width / 2", strength: .right),
            FamilyReferencePlane(name: "Center (Front/Back)", axis: .y, offset: "0", strength: .centerFrontBack, definesOrigin: true),
            FamilyReferencePlane(name: "Front", axis: .y, offset: "-Depth / 2", strength: .front),
            FamilyReferencePlane(name: "Back", axis: .y, offset: "Depth / 2", strength: .back),
            FamilyReferencePlane(name: "Bottom", axis: .z, offset: "0", strength: .bottom, definesOrigin: true),
            FamilyReferencePlane(name: "Top", axis: .z, offset: "Height", strength: .top),
        ]
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"),
                        FamilyDimension(planeA: "Front", planeB: "Back", labelParameter: "Depth"),
                        FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
    }

    static func len(_ n: String, builtIn: Bool = false, instance: Bool = false) -> FamilyParameter {
        FamilyParameter(name: n, type: .length, isInstance: instance, group: .dimensions, isBuiltIn: builtIn)
    }

    // MARK: Solids

    private mutating func use(_ m: LM) -> String {
        if !usedMaterials.contains(m) {
            usedMaterials.append(m)
            f.parameters.append(FamilyParameter(name: m.paramName, type: .elementRef(.materials), isInstance: false, group: .materials))
        }
        return m.paramName
    }

    private mutating func add(_ name: String, _ profile: FamilySolid.Profile, _ z0: LX, _ z1: LX, _ m: LM, plan: Bool) {
        let param = use(m)
        var s = FamilySolid(name: name, profile: profile, zMin: z0.bound, zMax: z1.bound, materialParameter: param, visibleInPlan: plan)
        s.visibilityParameter = visibility
        f.solids.append(s)
    }

    /// Adds a Yes/No type parameter (for `visibility`) and sets it on every type with `value(width)`.
    mutating func flag(_ name: String, _ value: (Double) -> Bool) {
        if f.parameter(named: name) == nil {
            f.parameters.append(FamilyParameter(name: name, type: .bool, isInstance: false, group: .graphics))
        }
        for i in f.types.indices {
            let w = f.types[i].values["Width"]?.doubleValue ?? 0
            f.types[i].values[name] = .bool(value(w))
        }
    }

    static func pt(_ x: LX, _ y: LX) -> FamilyPoint { FamilyPoint(x.bound, y.bound) }

    mutating func box(_ name: String, _ x0: LX, _ x1: LX, _ y0: LX, _ y1: LX, _ z0: LX, _ z1: LX, _ m: LM, plan: Bool = true) {
        add(name, .rectangle(xMin: x0.bound, xMax: x1.bound, yMin: y0.bound, yMax: y1.bound), z0, z1, m, plan: plan)
    }

    /// Void box: cuts the solid extrusions it overlaps (bowls, basins, recesses).
    mutating func voidBox(_ name: String, _ x0: LX, _ x1: LX, _ y0: LX, _ y1: LX, _ z0: LX, _ z1: LX) {
        var s = FamilySolid(name: name, profile: .rectangle(xMin: x0.bound, xMax: x1.bound, yMin: y0.bound, yMax: y1.bound),
                            zMin: z0.bound, zMax: z1.bound, isVoid: true, visibleInPlan: false)
        s.visibilityParameter = visibility
        f.solids.append(s)
    }
    /// Void prism over a plan polygon.
    mutating func voidPrism(_ name: String, _ pts: [(LX, LX)], _ z0: LX, _ z1: LX) {
        var s = FamilySolid(name: name, profile: .polygon(pts.map { FB.pt($0.0, $0.1) }), zMin: z0.bound, zMax: z1.bound, isVoid: true, visibleInPlan: false)
        s.visibilityParameter = visibility
        f.solids.append(s)
    }

    /// Vertical disc facing ±Y (signs, portholes, fan grilles): centered at (cx, cy) with its center at height zc.
    mutating func vDisc(_ name: String, _ cx: LX, _ cy: LX, _ zc: LX, _ r: LX, thickness t: Double, _ m: LM, sides: Int = 16, plan: Bool = false) {
        let sides = max(sides, 32) // VIS: discs read round (the view refines them further at Fine)
        vShape(name, (0..<sides).map { i in
            let a = (Double(i) / Double(sides) * 360 + 90) * .pi / 180
            return (r * cos(a), r * sin(a))
        }, cx, cy, zc, thickness: t, m, plan: plan)
    }

    /// Vertical plate facing ±Y with an outline given as (x, z) offsets from (cx, zc), `thickness` deep about cy.
    mutating func vShape(_ name: String, _ pts: [(LX, LX)], _ cx: LX, _ cy: LX, _ zc: LX, thickness t: Double, _ m: LM, plan: Bool = false) {
        // A sweep along +Y: profile x is to the left of the path (world -X), profile y is height above the solid's base.
        let minZ = pts.map { $0.1 }
        var low = minZ[0]
        for z in minZ.dropFirst() where z.value(["Width": 1, "Depth": 1, "Height": 1]) < low.value(["Width": 1, "Depth": 1, "Height": 1]) { low = z }
        let prof = pts.map { (-$0.0, $0.1 - low) }
        sweep(name, [(cx, cy - t / 2), (cx, cy + t / 2)], prof, zc + low, m, plan: plan)
    }

    /// Vertical cylinder.
    mutating func cyl(_ name: String, _ cx: LX, _ cy: LX, _ r: LX, _ z0: LX, _ z1: LX, _ m: LM, plan: Bool = true) {
        add(name, .circle(center: FB.pt(cx, cy), radius: r.formula), z0, z1, m, plan: plan)
    }

    /// Vertical prism over a plan polygon.
    mutating func prism(_ name: String, _ pts: [(LX, LX)], _ z0: LX, _ z1: LX, _ m: LM, plan: Bool = true) {
        add(name, .polygon(pts.map { FB.pt($0.0, $0.1) }), z0, z1, m, plan: plan)
    }

    /// Solid of revolution about a vertical axis at (cx, cy); `profile` is (radius, height above z0).
    mutating func revolve(_ name: String, _ profile: [(LX, LX)], _ cx: LX, _ cy: LX, _ z0: LX, _ m: LM, plan: Bool = true) {
        let rv = FamilyRevolve(profile: profile.map { FB.pt($0.0, $0.1) }, axis: FB.pt(cx, cy))
        add(name, .revolve(rv), z0, z0 + 0.01, m, plan: plan)
    }

    /// Loft between two plan loops.
    mutating func blend(_ name: String, _ bottom: [(LX, LX)], _ top: [(LX, LX)], _ z0: LX, _ z1: LX, _ m: LM, plan: Bool = true) {
        add(name, .blend(FamilyBlend(bottom: bottom.map { FB.pt($0.0, $0.1) }, top: top.map { FB.pt($0.0, $0.1) })), z0, z1, m, plan: plan)
    }

    /// Loft between two centered rectangles (half sizes).
    mutating func taper(_ name: String, _ cx: LX, _ cy: LX, bottom: (LX, LX), top: (LX, LX), _ z0: LX, _ z1: LX, _ m: LM, plan: Bool = true) {
        func r(_ h: (LX, LX)) -> [(LX, LX)] { [(cx - h.0, cy - h.1), (cx + h.0, cy - h.1), (cx + h.0, cy + h.1), (cx - h.0, cy + h.1)] }
        blend(name, r(bottom), r(top), z0, z1, m, plan: plan)
    }

    /// Horizontal round bar from `a` to `b` (plan points) with its axis at height `z` (the path may have more points).
    mutating func bar(_ name: String, _ path: [(LX, LX)], z: LX, r: LX, _ m: LM, sides: Int = 10, plan: Bool = true) {
        let sides = max(sides, 24) // VIS: round bars, not prisms (the view refines them further at Fine)
        let prof = (0..<sides).map { i -> FamilyPoint in
            let a = Double(i) / Double(sides) * 2 * .pi
            return FB.pt(r * cos(a), r * sin(a) + r)
        }
        let sw = FamilySweep(path: path.map { FB.pt($0.0, $0.1) }, profile: prof)
        add(name, .sweep(sw), z - r, z - r + 0.01, m, plan: plan)
    }

    /// Horizontal sweep of an arbitrary profile (x = offset left of the path, y = height above `z0`).
    mutating func sweep(_ name: String, _ path: [(LX, LX)], _ profile: [(LX, LX)], _ z0: LX, _ m: LM, plan: Bool = true) {
        let sw = FamilySweep(path: path.map { FB.pt($0.0, $0.1) }, profile: profile.map { FB.pt($0.0, $0.1) })
        add(name, .sweep(sw), z0, z0 + 0.01, m, plan: plan)
    }

    /// Sphere-like revolve (a polygonal ball) centered at (cx, cy, zc).
    mutating func ball(_ name: String, _ cx: LX, _ cy: LX, _ zc: LX, _ r: LX, _ m: LM, plan: Bool = true, steps: Int = 8) {
        var prof: [(LX, LX)] = [(LX(0), LX(0))]
        let steps = max(steps, 12) // VIS: balls and casters read round
        for i in 1..<steps {
            let a = Double(i) / Double(steps) * .pi
            prof.append((r * sin(a), r - r * cos(a)))
        }
        prof.append((LX(0), r * 2))
        revolve(name, prof, cx, cy, zc - r, m, plan: plan)
    }

    // MARK: Plan symbols

    mutating func line(_ x0: LX, _ y0: LX, _ x1: LX, _ y1: LX, _ sub: FamilySubcategory = .general) {
        var l = FamilyLine(shape: .line(FB.pt(x0, y0), FB.pt(x1, y1)), subcategory: sub)
        l.visibilityParameter = visibility
        f.planLines.append(l)
    }
    mutating func rect(_ x0: LX, _ y0: LX, _ x1: LX, _ y1: LX, _ sub: FamilySubcategory = .general) {
        line(x0, y0, x1, y0, sub); line(x1, y0, x1, y1, sub); line(x1, y1, x0, y1, sub); line(x0, y1, x0, y0, sub)
    }
    mutating func poly(_ pts: [(LX, LX)], closed: Bool = true, _ sub: FamilySubcategory = .general) {
        guard pts.count >= 2 else { return }
        for i in 0..<(pts.count - 1) { line(pts[i].0, pts[i].1, pts[i + 1].0, pts[i + 1].1, sub) }
        if closed, pts.count > 2 { line(pts[pts.count - 1].0, pts[pts.count - 1].1, pts[0].0, pts[0].1, sub) }
    }
    mutating func arc(_ cx: LX, _ cy: LX, _ r: LX, _ start: Double, _ sweep: Double, _ sub: FamilySubcategory = .general) {
        var l = FamilyLine(shape: .arc(center: FB.pt(cx, cy), radius: r.formula, startDegrees: LX.num(start), sweepDegrees: LX.num(sweep)),
                           subcategory: sub)
        l.visibilityParameter = visibility
        f.planLines.append(l)
    }
    mutating func circle(_ cx: LX, _ cy: LX, _ r: LX, _ sub: FamilySubcategory = .general) { arc(cx, cy, r, 0, 360, sub) }
    /// Rectangle with rounded corners of radius `r`.
    mutating func rrect(_ x0: LX, _ y0: LX, _ x1: LX, _ y1: LX, _ r: LX, _ sub: FamilySubcategory = .general) {
        line(x0 + r, y0, x1 - r, y0, sub); line(x1, y0 + r, x1, y1 - r, sub)
        line(x1 - r, y1, x0 + r, y1, sub); line(x0, y1 - r, x0, y0 + r, sub)
        arc(x1 - r, y0 + r, r, 270, 90, sub); arc(x1 - r, y1 - r, r, 0, 90, sub)
        arc(x0 + r, y1 - r, r, 90, 90, sub); arc(x0 + r, y0 + r, r, 180, 90, sub)
    }
    /// Plan outline of the full Width x Depth box.
    mutating func outline() { rect(W(-0.5), D(-0.5), W(0.5), D(0.5)) }

    // MARK: Types

    /// Adds a type. Sizes are meters; `extra` gives values for the extra parameters (meters).
    mutating func type(_ name: String, _ sz: SZ, _ w: Double, _ d: Double, _ h: Double, _ extra: [String: Double] = [:],
                       regions: [LibraryRegion]? = nil) {
        var values: [String: ParamValue] = ["Width": .double(w), "Depth": .double(d), "Height": .double(h)]
        for (k, v) in extra { values[k] = .double(v) }
        f.types.append(FamilyTypeDefinition(name: name, values: values))
        let system: LibrarySizeSystem = sz == .metric ? .metric : sz == .imperial ? .imperial : .neutral
        typeSpecs.append(ComponentLibraryType(name: name, regions: regions ?? self.regions, system: system, width: w, depth: d, height: h))
    }
    /// Imperial type: sizes in inches.
    mutating func inch(_ name: String, _ w: Double, _ d: Double, _ h: Double, _ extra: [String: Double] = [:], regions: [LibraryRegion]? = nil) {
        type(name, .imperial, w * 0.0254, d * 0.0254, h * 0.0254, extra.mapValues { $0 * 0.0254 }, regions: regions)
    }
    /// Metric type: sizes in millimeters.
    mutating func mm(_ name: String, _ w: Double, _ d: Double, _ h: Double, _ extra: [String: Double] = [:], regions: [LibraryRegion]? = nil) {
        type(name, .metric, w / 1000, d / 1000, h / 1000, extra.mapValues { $0 / 1000 }, regions: regions)
    }
    /// Size-neutral type: sizes in meters, name without units.
    mutating func any(_ name: String, _ w: Double, _ d: Double, _ h: Double, _ extra: [String: Double] = [:], regions: [LibraryRegion]? = nil) {
        type(name, .neutral, w, d, h, extra, regions: regions)
    }

    var item: ComponentLibraryItem {
        var allRegions: [LibraryRegion] = []
        for t in typeSpecs { for r in t.regions where !allRegions.contains(r) { allRegions.append(r) } }
        for r in regions where !allRegions.contains(r) { allRegions.append(r) }
        var mats: [String: ComponentMaterial] = [:]
        for m in usedMaterials { mats[m.paramName] = m.material }
        return ComponentLibraryItem(family: f, category: category, group: group, regions: allRegions, keywords: keywords,
                                    types: typeSpecs, materials: mats)
    }
}

// MARK: - Expression shorthands (fractions of the family's size plus a fixed offset in meters)

/// f·Width + o
func W(_ f: Double, _ o: Double = 0) -> LX { LX("Width", f, o) }
/// f·Depth + o
func D(_ f: Double, _ o: Double = 0) -> LX { LX("Depth", f, o) }
/// f·Height + o
func H(_ f: Double, _ o: Double = 0) -> LX { LX("Height", f, o) }
/// f·parameter + o
func P(_ name: String, _ f: Double = 1, _ o: Double = 0) -> LX { LX(name, f, o) }
/// A fixed length in meters.
func K(_ v: Double) -> LX { LX(v) }

/// Inch and foot type-name helpers: in(84) → 84", ft(9) → 9'.
func inch(_ v: Double) -> String { "\(LX.num(v))\"" }
func ft(_ v: Double) -> String { "\(LX.num(v))'" }
