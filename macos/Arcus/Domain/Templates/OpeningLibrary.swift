import Foundation
import ArcusGeometry
import ArcusCalc

/// Standard door and window families with imperial and metric types (original Arcus content; sizes are common
/// industry nominal sizes, names are generic).
///
/// Family coordinates follow `FamilyDefinition`: X along the host wall, +Y toward the exterior, Z up from the sill
/// (windows) or the floor (doors). Doors swing toward −Y (the interior).
public enum OpeningLibrary {
    static func p(_ n: String) -> FamilyBound { .plane(n) }
    static func x(_ s: String) -> FamilyBound { .expr(s) }
    static func len(_ name: String, _ isInstance: Bool = false, builtIn: Bool = false) -> FamilyParameter {
        FamilyParameter(name: name, type: .length, isInstance: isInstance, group: .dimensions, isBuiltIn: builtIn)
    }
    static func mat(_ name: String) -> FamilyParameter { FamilyParameter(name: name, type: .elementRef(.materials), group: .materials) }
    static func box(_ name: String, _ x0: String, _ x1: String, _ y0: String, _ y1: String, _ z0: String, _ z1: String,
                    material: String?, sub: FamilySubcategory, plan: Bool = false) -> FamilySolid {
        FamilySolid(name: name, profile: .rectangle(xMin: x(x0), xMax: x(x1), yMin: x(y0), yMax: x(y1)), zMin: x(z0), zMax: x(z1),
                    materialParameter: material, subcategory: sub, visibleInPlan: plan)
    }
    static func line(_ a: (String, String), _ b: (String, String), _ sub: FamilySubcategory = .general) -> FamilyLine {
        FamilyLine(shape: .line(FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)), subcategory: sub)
    }
    static func rect(_ x0: String, _ y0: String, _ x1: String, _ y1: String, _ sub: FamilySubcategory) -> [FamilyLine] {
        [line((x0, y0), (x1, y0), sub), line((x1, y0), (x1, y1), sub), line((x1, y1), (x0, y1), sub), line((x0, y1), (x0, y0), sub)]
    }
    static func arc(_ cx: String, _ cy: String, _ r: String, _ start: String, _ sweep: String) -> FamilyLine {
        FamilyLine(shape: .arc(center: FamilyPoint(cx, cy), radius: r, startDegrees: start, sweepDegrees: sweep), subcategory: .swing)
    }

    // MARK: Sizes and names

    static let inch = 0.0254
    static func i(_ v: Double) -> Double { v * inch }

    /// `36"`, `4 1/2"` — whole and simple fractional inches.
    public static func inchText(_ v: Double) -> String {
        let whole = Int(v.rounded(.down))
        let frac = v - Double(whole)
        let eighths = Int((frac * 8).rounded())
        guard eighths > 0 else { return "\(whole)\"" }
        var n = eighths, d = 8
        while n % 2 == 0 { n /= 2; d /= 2 }
        return whole == 0 ? "\(n)/\(d)\"" : "\(whole) \(n)/\(d)\""
    }
    /// `9'-0"` for a size in inches.
    public static func feetText(_ v: Double) -> String {
        let ft = Int((v / 12).rounded(.down))
        return "\(ft)'-\(inchText(v - Double(ft) * 12))"
    }
    /// Imperial door/window type name: `36" x 80"`.
    static func inches(_ w: Double, _ h: Double) -> String { "\(inchText(w)) x \(inchText(h))" }
    /// Metric type name: `900 x 2100`.
    static func millimeters(_ w: Double, _ h: Double) -> String { "\(Int(w.rounded())) x \(Int(h.rounded()))" }

    /// A size row: width and height in inches (imperial) or millimeters (metric), plus optional suffix and extra values (SI).
    struct Size {
        var w: Double, h: Double, suffix: String = "", extra: [String: Double] = [:], feet = false
    }
    static func types(_ system: UnitSystem, _ sizes: [Size], defaults: [String: Double]) -> [FamilyTypeDefinition] {
        sizes.map { s in
            let imperial = system == .imperial
            let w = imperial ? i(s.w) : s.w / 1000, h = imperial ? i(s.h) : s.h / 1000
            var name = imperial ? (s.feet ? "\(feetText(s.w)) x \(feetText(s.h))" : inches(s.w, s.h)) : millimeters(s.w, s.h)
            if !s.suffix.isEmpty { name += " " + s.suffix }
            var values: [String: ParamValue] = ["Width": .double(w), "Height": .double(h)]
            for (k, v) in defaults { values[k] = .double(v) }
            for (k, v) in s.extra { values[k] = .double(v) }
            return FamilyTypeDefinition(name: name, values: values)
        }
    }
    static func sz(_ w: Double, _ h: Double, _ suffix: String = "", feet: Bool = false, _ extra: [String: Double] = [:]) -> Size {
        Size(w: w, h: h, suffix: suffix, extra: extra, feet: feet)
    }

    // MARK: Library entry

    /// A family with its default materials (parameter → library material name) and fire ratings per type name.
    public struct Entry: Sendable {
        public var family: FamilyDefinition
        public var materials: [String: String]
        public var fireRatings: [String: String] = [:]
    }

    /// Every door family for a unit system.
    public static func doors(_ system: UnitSystem) -> [Entry] {
        let wood = ["Frame Material": "Hardwood", "Panel Material": "Wood - Flush Door Veneer"]
        let glazedWood = ["Frame Material": "Hardwood", "Panel Material": "Hardwood, Oak White", "Glass Material": "Glass"]
        let shopfront = ["Frame Material": "Aluminum, Anodized Black", "Panel Material": "Aluminum, Anodized Black", "Glass Material": "Glass, Tempered"]
        let steel = ["Frame Material": "Steel, Galvanized", "Panel Material": "Steel, Painted White"]
        let fire = ["Frame Material": "Steel, Painted White", "Panel Material": "Wood - Flush Door Veneer", "Glass Material": "Glass, Fire-Rated"]
        var out: [Entry] = [
            Entry(family: singleFlush(system), materials: wood),
            Entry(family: singlePanel(system), materials: ["Frame Material": "Hardwood", "Panel Material": "Paint - White"]),
            Entry(family: singleGlazed(system, half: false), materials: glazedWood),
            Entry(family: singleGlazed(system, half: true), materials: glazedWood),
            Entry(family: doubleFlush(system), materials: wood),
            Entry(family: doubleGlazed(system), materials: glazedWood),
            Entry(family: slidingGlass(system), materials: ["Frame Material": "Aluminum", "Panel Material": "Aluminum", "Glass Material": "Glass, Tempered"]),
            Entry(family: bypass(system), materials: wood),
            Entry(family: pocket(system), materials: wood),
            Entry(family: bifold(system, leaves: 2), materials: wood),
            Entry(family: bifold(system, leaves: 4), materials: wood),
            Entry(family: barn(system), materials: ["Frame Material": "Hardwood", "Panel Material": "Hardwood, Oak White", "Track Material": "Steel, Painted Black"]),
            Entry(family: dutch(system), materials: ["Frame Material": "Hardwood", "Panel Material": "Paint - White"]),
            Entry(family: overheadSectional(system), materials: steel),
            Entry(family: rollUp(system), materials: ["Frame Material": "Steel, Galvanized", "Panel Material": "Steel, Galvanized"]),
            Entry(family: storefront(system, double: false), materials: shopfront),
            Entry(family: storefront(system, double: true), materials: shopfront),
        ]
        var fr1 = Entry(family: fireRated(system, double: false), materials: fire)
        var fr2 = Entry(family: fireRated(system, double: true), materials: fire)
        for t in fr1.family.types { fr1.fireRatings[t.name] = rating(in: t.name) }
        for t in fr2.family.types { fr2.fireRatings[t.name] = rating(in: t.name) }
        out += [fr1, fr2]
        return out
    }

    /// Every window family for a unit system.
    public static func windows(_ system: UnitSystem) -> [Entry] {
        let alu = ["Frame Material": "Aluminum", "Glass Material": "Glass"]
        let vinyl = ["Frame Material": system == .imperial ? "uPVC Frame, White" : "Aluminum", "Glass Material": "Glass"]
        return [
            Entry(family: fixedWindow(system, picture: false), materials: alu),
            Entry(family: fixedWindow(system, picture: true), materials: alu),
            Entry(family: casement(system), materials: alu),
            Entry(family: casementDouble(system), materials: alu),
            Entry(family: projectedSash(system, awning: true), materials: alu),
            Entry(family: projectedSash(system, awning: false), materials: alu),
            Entry(family: hung(system, double: false), materials: vinyl),
            Entry(family: hung(system, double: true), materials: vinyl),
            Entry(family: sliding(system, tracks: 2), materials: alu),
            Entry(family: sliding(system, tracks: 3), materials: alu),
            Entry(family: bay(system), materials: ["Frame Material": system == .imperial ? "Hardwood, Oak White" : "Hardwood", "Glass Material": "Glass"]),
            Entry(family: louvered(system, ventilator: false), materials: alu),
            Entry(family: louvered(system, ventilator: true), materials: alu),
        ]
    }

    static func rating(in name: String) -> String {
        guard let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close else { return "" }
        return String(name[name.index(after: open)..<close])
    }

    // MARK: Door scaffolding

    static func doorDefaults(_ system: UnitSystem, frame: Double? = nil, depth: Double? = nil, panel: Double? = nil) -> [String: Double] {
        system == .imperial
            ? ["Frame Width": frame ?? i(2), "Frame Depth": depth ?? i(4.875), "Panel Thickness": panel ?? i(1.75)]
            : ["Frame Width": frame ?? 0.05, "Frame Depth": depth ?? 0.12, "Panel Thickness": panel ?? 0.04]
    }

    /// Parameters, reference planes, frame (jambs and head), plan jambs and opening shared by all doors.
    static func door(_ name: String, _ description: String, extra: [FamilyParameter] = [], frame: Bool = true) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: .door)
        f.description = description
        f.parameters = [len("Width", builtIn: true), len("Height", builtIn: true), len("Frame Width"), len("Frame Depth"), len("Panel Thickness")]
            + extra + [mat("Frame Material"), mat("Panel Material")]
        f.referencePlanes = [
            FamilyReferencePlane(name: "Center (Left/Right)", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
            FamilyReferencePlane(name: "Left", axis: .x, offset: "-Width / 2", strength: .left),
            FamilyReferencePlane(name: "Right", axis: .x, offset: "Width / 2", strength: .right),
            FamilyReferencePlane(name: "Center (Front/Back)", axis: .y, offset: "0", strength: .centerFrontBack, definesOrigin: true),
            FamilyReferencePlane(name: "Bottom", axis: .z, offset: "0", strength: .bottom, definesOrigin: true),
            FamilyReferencePlane(name: "Top", axis: .z, offset: "Height", strength: .top),
        ]
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
        if frame {
            f.solids = [
                FamilySolid(name: "Left Jamb", profile: .rectangle(xMin: x("-Width / 2 - Frame Width"), xMax: p("Left"), yMin: x("-Frame Depth / 2"), yMax: x("Frame Depth / 2")),
                            zMin: p("Bottom"), zMax: x("Height + Frame Width"), materialParameter: "Frame Material", subcategory: .frame),
                FamilySolid(name: "Right Jamb", profile: .rectangle(xMin: p("Right"), xMax: x("Width / 2 + Frame Width"), yMin: x("-Frame Depth / 2"), yMax: x("Frame Depth / 2")),
                            zMin: p("Bottom"), zMax: x("Height + Frame Width"), materialParameter: "Frame Material", subcategory: .frame),
                FamilySolid(name: "Head", profile: .rectangle(xMin: p("Left"), xMax: p("Right"), yMin: x("-Frame Depth / 2"), yMax: x("Frame Depth / 2")),
                            zMin: p("Top"), zMax: x("Height + Frame Width"), materialParameter: "Frame Material", subcategory: .frame),
            ]
            f.planLines = rect("-Width / 2 - Frame Width", "-Frame Depth / 2", "-Width / 2", "Frame Depth / 2", .frame)
                + rect("Width / 2", "-Frame Depth / 2", "Width / 2 + Frame Width", "Frame Depth / 2", .frame)
        }
        f.opening = FamilyOpening(xMin: x("-Width / 2 - Frame Width"), xMax: x("Width / 2 + Frame Width"), zMin: p("Bottom"), zMax: x("Height + Frame Width"))
        return f
    }

    /// A flush leaf between x0 and x1 (expressions), centered on `y`.
    static func flushLeaf(_ name: String, _ x0: String, _ x1: String, z0: String = "0", z1: String = "Height", y: String = "0") -> FamilySolid {
        box(name, x0, x1, "\(y) - Panel Thickness / 2", "\(y) + Panel Thickness / 2", z0, z1, material: "Panel Material", sub: .panel)
    }

    /// A glazed leaf: stiles, top and bottom rails and glass, between x0 and x1, centered on `y`.
    static func glazedLeaf(_ prefix: String, _ x0: String, _ x1: String, bottomRail: String = "Bottom Rail", y: String = "0") -> [FamilySolid] {
        let y0 = "\(y) - Panel Thickness / 2", y1 = "\(y) + Panel Thickness / 2"
        return [
            box("\(prefix)Stile L", x0, "\(x0) + Stile Width", y0, y1, "0", "Height", material: "Panel Material", sub: .panel),
            box("\(prefix)Stile R", "\(x1) - Stile Width", x1, y0, y1, "0", "Height", material: "Panel Material", sub: .panel),
            box("\(prefix)Top Rail", "\(x0) + Stile Width", "\(x1) - Stile Width", y0, y1, "Height - Stile Width", "Height", material: "Panel Material", sub: .panel),
            box("\(prefix)Bottom Rail", "\(x0) + Stile Width", "\(x1) - Stile Width", y0, y1, "0", bottomRail, material: "Panel Material", sub: .panel),
            box("\(prefix)Glass", "\(x0) + Stile Width", "\(x1) - Stile Width", "\(y) - Glass Thickness / 2", "\(y) + Glass Thickness / 2",
                bottomRail, "Height - Stile Width", material: "Glass Material", sub: .glass),
        ]
    }

    /// Plan leaf swung open 90° to the interior with its swing arc: hinge on the left (or right) jamb.
    static func swing(_ hingeX: String, leaf: String, right: Bool = false) -> [FamilyLine] {
        let yo = "-Frame Depth / 2"
        let x1 = right ? "\(hingeX) - Panel Thickness" : "\(hingeX) + Panel Thickness"
        return rect(hingeX, "\(yo) - \(leaf)", x1, yo, .panel)
            + [arc(hingeX, yo, leaf, right ? "180" : "-90", "90")]
    }

    static var glazedParams: [FamilyParameter] { [len("Stile Width"), len("Bottom Rail"), len("Glass Thickness"), mat("Glass Material")] }
    static func glazedDefaults(_ system: UnitSystem) -> [String: Double] {
        system == .imperial ? ["Stile Width": i(4.5), "Bottom Rail": i(9.5), "Glass Thickness": i(0.25)]
            : ["Stile Width": 0.12, "Bottom Rail": 0.22, "Glass Thickness": 0.006]
    }

    // MARK: Doors

    static func singleFlush(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Single Flush", "Single-leaf flush door.")
        f.solids.append(flushLeaf("Panel", "-Width / 2", "Width / 2"))
        f.planLines += swing("-Width / 2", leaf: "Width")
        f.types = system == .imperial
            ? types(system, [sz(24, 80), sz(28, 80), sz(30, 80), sz(32, 80), sz(34, 80), sz(36, 80), sz(30, 84), sz(32, 84), sz(36, 84), sz(42, 84), sz(36, 96)],
                    defaults: doorDefaults(system))
            : types(system, [sz(900, 2100), sz(820, 2040), sz(1000, 2100), sz(700, 2040), sz(750, 2100), sz(800, 2040), sz(800, 2100), sz(900, 2040),
                             sz(900, 2400), sz(1000, 2400)], defaults: doorDefaults(system))
        return f
    }

    static func singlePanel(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Single Panel", "Single-leaf door with four raised panels.", extra: [len("Stile Width")])
        f.solids.append(flushLeaf("Leaf", "-Width / 2", "Width / 2"))
        for side in ["1", "-1"] {
            let y0 = side == "1" ? "Panel Thickness / 2" : "-Panel Thickness / 2 - 0.008 m"
            let y1 = side == "1" ? "Panel Thickness / 2 + 0.008 m" : "-Panel Thickness / 2"
            for (xa, xb) in [("-Width / 2 + Stile Width", "-Stile Width / 4"), ("Stile Width / 4", "Width / 2 - Stile Width")] {
                f.solids.append(box("Raised Panel Lower", xa, xb, y0, y1, "Stile Width * 1.5", "Height * 0.42", material: "Panel Material", sub: .panel))
                f.solids.append(box("Raised Panel Upper", xa, xb, y0, y1, "Height * 0.5", "Height - Stile Width", material: "Panel Material", sub: .panel))
            }
        }
        f.planLines += swing("-Width / 2", leaf: "Width")
        var d = doorDefaults(system)
        d["Stile Width"] = system == .imperial ? i(4.5) : 0.11
        f.types = system == .imperial
            ? types(system, [sz(30, 80), sz(32, 80), sz(36, 80), sz(36, 84)], defaults: d)
            : types(system, [sz(800, 2100), sz(900, 2100), sz(1000, 2100)], defaults: d)
        return f
    }

    static func singleGlazed(_ system: UnitSystem, half: Bool) -> FamilyDefinition {
        var f = door(half ? "Door - Single Half Glazed" : "Door - Single Glazed",
                     half ? "Single-leaf door, solid below and glazed above." : "Single-leaf full-lite glazed door.", extra: glazedParams)
        f.solids += glazedLeaf("", "-Width / 2", "Width / 2", bottomRail: half ? "Height * 0.45" : "Bottom Rail")
        f.planLines += swing("-Width / 2", leaf: "Width")
        let d = doorDefaults(system).merging(glazedDefaults(system)) { a, _ in a }
        f.types = system == .imperial
            ? types(system, half ? [sz(32, 80), sz(36, 80)] : [sz(32, 80), sz(36, 80), sz(36, 84)], defaults: d)
            : types(system, half ? [sz(800, 2100), sz(900, 2100)] : [sz(900, 2100), sz(1000, 2100)], defaults: d)
        return f
    }

    static func doubleFlush(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Double Flush", "Double-leaf flush door.", extra: [FamilyParameter(name: "Leaf Width", type: .length, formula: "Width / 2")])
        f.solids += [flushLeaf("Left Leaf", "-Width / 2", "-0.002 m"), flushLeaf("Right Leaf", "0.002 m", "Width / 2")]
        f.planLines += swing("-Width / 2", leaf: "Leaf Width") + swing("Width / 2", leaf: "Leaf Width", right: true)
        var d = doorDefaults(system)
        if system == .metric { d["Panel Thickness"] = 0.045 }
        f.types = system == .imperial
            ? types(system, [sz(48, 80), sz(60, 80), sz(60, 84), sz(72, 80), sz(72, 84), sz(72, 96)], defaults: d)
            : types(system, [sz(1800, 2100), sz(1500, 2100), sz(1200, 2100), sz(1800, 2400), sz(2000, 2400)], defaults: d)
        return f
    }

    static func doubleGlazed(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Double Glazed", "Pair of full-lite glazed doors (French doors).",
                     extra: glazedParams + [FamilyParameter(name: "Leaf Width", type: .length, formula: "Width / 2")])
        f.solids += glazedLeaf("Left ", "-Width / 2", "-0.002 m") + glazedLeaf("Right ", "0.002 m", "Width / 2")
        f.planLines += swing("-Width / 2", leaf: "Leaf Width") + swing("Width / 2", leaf: "Leaf Width", right: true)
        let d = doorDefaults(system).merging(glazedDefaults(system)) { a, _ in a }
        f.types = system == .imperial
            ? types(system, [sz(48, 80), sz(60, 80), sz(72, 80), sz(72, 96)], defaults: d)
            : types(system, [sz(1200, 2100), sz(1500, 2100), sz(1800, 2100)], defaults: d)
        return f
    }

    /// Two panels in two tracks: the outer one fixed, the inner one sliding.
    static func slidingGlass(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Sliding Glass", "Two-panel sliding glass door: one fixed panel, one sliding panel.", extra: glazedParams)
        let ye = "Panel Thickness / 2 + 0.003 m", yi = "-Panel Thickness / 2 - 0.003 m"
        f.solids += glazedLeaf("Fixed ", "-Width / 2", "Stile Width / 2", y: ye) + glazedLeaf("Sliding ", "-Stile Width / 2", "Width / 2", y: yi)
        f.planLines += rect("-Width / 2", "\(ye) - Panel Thickness / 2", "Stile Width / 2", "\(ye) + Panel Thickness / 2", .panel)
            + rect("-Stile Width / 2", "\(yi) - Panel Thickness / 2", "Width / 2", "\(yi) + Panel Thickness / 2", .panel)
            + [line(("Width / 4", "-Frame Depth / 2 - 0.1 m"), ("-Width / 4", "-Frame Depth / 2 - 0.1 m"), .swing),
               line(("-Width / 4", "-Frame Depth / 2 - 0.1 m"), ("-Width / 4 + 0.08 m", "-Frame Depth / 2 - 0.06 m"), .swing)]
        let d = doorDefaults(system, depth: system == .imperial ? i(6) : 0.15).merging(glazedDefaults(system)) { a, _ in a }
        f.types = system == .imperial
            ? types(system, [sz(60, 80), sz(72, 80), sz(96, 80), sz(72, 96)], defaults: d)
            : types(system, [sz(1800, 2100), sz(2400, 2100), sz(3000, 2400)], defaults: d)
        return f
    }

    static func bypass(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Bypass Sliding", "Two flush panels sliding past each other in two tracks (closets).")
        let ye = "Panel Thickness / 2 + 0.003 m", yi = "-Panel Thickness / 2 - 0.003 m"
        f.solids += [flushLeaf("Outer Panel", "-Width / 2", "0.025 m", y: ye), flushLeaf("Inner Panel", "-0.025 m", "Width / 2", y: yi)]
        f.planLines += rect("-Width / 2", "\(ye) - Panel Thickness / 2", "0.025 m", "\(ye) + Panel Thickness / 2", .panel)
            + rect("-0.025 m", "\(yi) - Panel Thickness / 2", "Width / 2", "\(yi) + Panel Thickness / 2", .panel)
        f.types = system == .imperial
            ? types(system, [sz(48, 80), sz(60, 80), sz(72, 80)], defaults: doorDefaults(system, panel: i(1.375)))
            : types(system, [sz(1200, 2040), sz(1500, 2100), sz(1800, 2100)], defaults: doorDefaults(system, panel: 0.035))
        return f
    }

    static func pocket(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Pocket", "Single panel sliding into a pocket in the wall.")
        f.solids.append(flushLeaf("Panel", "-Width / 2", "Width / 2"))
        // Plan: the panel half open, the pocket shown hidden.
        f.planLines += rect("-Width", "-Panel Thickness / 2", "0", "Panel Thickness / 2", .panel)
            + rect("-Width * 1.5 - Frame Width", "-Panel Thickness", "-Width / 2 - Frame Width", "Panel Thickness", .hidden)
        f.types = system == .imperial
            ? types(system, [sz(28, 80), sz(30, 80), sz(32, 80), sz(36, 80)], defaults: doorDefaults(system, panel: i(1.375)))
            : types(system, [sz(750, 2040), sz(800, 2040), sz(900, 2100)], defaults: doorDefaults(system, panel: 0.035))
        return f
    }

    static func bifold(_ system: UnitSystem, leaves: Int) -> FamilyDefinition {
        var f = door(leaves == 2 ? "Door - Bifold 2-Leaf" : "Door - Bifold 4-Leaf",
                     leaves == 2 ? "Two folding leaves hinged to one jamb." : "Four folding leaves, two hinged to each jamb.")
        for k in 0..<leaves {
            let a = Double(k) / Double(leaves), b = Double(k + 1) / Double(leaves)
            f.solids.append(flushLeaf("Leaf \(k + 1)", "-Width / 2 + Width * \(a) + 0.002 m", "-Width / 2 + Width * \(b) - 0.002 m"))
        }
        // Plan: each pair of leaves folded to 60°.
        let yo = "-Frame Depth / 2"
        let pair = leaves == 2 ? "Width" : "Width / 2"
        f.planLines += [line(("-Width / 2", yo), ("-Width / 2 + \(pair) / 4", "\(yo) - \(pair) * 0.433"), .panel),
                        line(("-Width / 2 + \(pair) / 4", "\(yo) - \(pair) * 0.433"), ("-Width / 2 + \(pair) / 2", yo), .panel)]
        if leaves == 4 {
            f.planLines += [line(("Width / 2", yo), ("Width / 2 - \(pair) / 4", "\(yo) - \(pair) * 0.433"), .panel),
                            line(("Width / 2 - \(pair) / 4", "\(yo) - \(pair) * 0.433"), ("Width / 2 - \(pair) / 2", yo), .panel)]
        }
        let d = doorDefaults(system, panel: system == .imperial ? i(1.125) : 0.028)
        f.types = system == .imperial
            ? types(system, leaves == 2 ? [sz(24, 80), sz(30, 80), sz(36, 80)] : [sz(48, 80), sz(60, 80), sz(72, 80)], defaults: d)
            : types(system, leaves == 2 ? [sz(600, 2040), sz(800, 2040), sz(900, 2040)] : [sz(1200, 2040), sz(1500, 2040), sz(1800, 2040)], defaults: d)
        return f
    }

    static func barn(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Barn", "Surface-mounted sliding panel on an exposed track, on the interior face.",
                     extra: [len("Host Thickness", true), len("Overlap"), mat("Track Material")])
        let y1 = "-Host Thickness / 2 - 0.02 m", y0 = "-Host Thickness / 2 - 0.02 m - Panel Thickness"
        let left = "-Width / 2 - Frame Width - Overlap", right = "Width / 2 + Frame Width + Overlap"
        f.solids += [
            box("Panel", left, right, y0, y1, "0.01 m", "Height + Frame Width + 0.05 m", material: "Panel Material", sub: .panel, plan: false),
            box("Track", left, "Width * 1.5 + Frame Width * 2 + Overlap", y0, y1, "Height + Frame Width + 0.05 m", "Height + Frame Width + 0.1 m",
                material: "Track Material", sub: .frame),
        ]
        f.planLines += rect(left, y0, right, y1, .panel) + [line((right, "\(y1) + 0.005 m"), ("Width * 1.5 + Frame Width * 2 + Overlap", "\(y1) + 0.005 m"), .hidden)]
        var d = doorDefaults(system, panel: system == .imperial ? i(1.5) : 0.04)
        d["Host Thickness"] = system == .imperial ? i(4.5) : 0.1
        d["Overlap"] = system == .imperial ? i(2) : 0.05
        f.types = system == .imperial
            ? types(system, [sz(36, 84), sz(42, 84), sz(48, 96)], defaults: d)
            : types(system, [sz(900, 2100), sz(1000, 2100), sz(1200, 2400)], defaults: d)
        return f
    }

    static func dutch(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Dutch", "Single door split into independently opening upper and lower leaves.")
        f.solids += [flushLeaf("Lower Leaf", "-Width / 2", "Width / 2", z0: "0", z1: "Height / 2 - 0.002 m"),
                     flushLeaf("Upper Leaf", "-Width / 2", "Width / 2", z0: "Height / 2 + 0.002 m", z1: "Height")]
        f.planLines += swing("-Width / 2", leaf: "Width")
        f.types = system == .imperial
            ? types(system, [sz(32, 80), sz(36, 80)], defaults: doorDefaults(system))
            : types(system, [sz(900, 2100)], defaults: doorDefaults(system))
        return f
    }

    static func overheadSectional(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Overhead Sectional", "Sectional garage door on overhead tracks.")
        for k in 0..<4 {
            f.solids.append(flushLeaf("Section \(k + 1)", "-Width / 2", "Width / 2", z0: "Height * \(Double(k) / 4)", z1: "Height * \(Double(k + 1) / 4) - 0.003 m"))
        }
        let yo = "-Frame Depth / 2"
        f.planLines += rect("-Width / 2", "-Panel Thickness / 2", "Width / 2", "Panel Thickness / 2", .panel)
            + [line(("-Width / 2", yo), ("-Width / 2", "\(yo) - Height"), .hidden), line(("Width / 2", yo), ("Width / 2", "\(yo) - Height"), .hidden),
               line(("-Width / 2", "\(yo) - Height"), ("Width / 2", "\(yo) - Height"), .hidden)]
        let d = doorDefaults(system, frame: system == .imperial ? i(3.5) : 0.09, depth: system == .imperial ? i(5.5) : 0.14,
                             panel: system == .imperial ? i(2) : 0.042)
        f.types = system == .imperial
            ? types(system, [sz(96, 84, feet: true), sz(108, 84, feet: true), sz(108, 96, feet: true), sz(192, 84, feet: true), sz(192, 96, feet: true),
                             sz(216, 96, feet: true)], defaults: d)
            : types(system, [sz(2400, 2100), sz(2700, 2100), sz(3000, 2400), sz(4800, 2100), sz(5000, 2400)], defaults: d)
        return f
    }

    static func rollUp(_ system: UnitSystem) -> FamilyDefinition {
        var f = door("Door - Roll-Up Shutter", "Coiling slatted shutter with a coil hood on the interior face.",
                     extra: [len("Host Thickness", true), len("Coil Hood")])
        f.solids.append(flushLeaf("Curtain", "-Width / 2", "Width / 2"))
        let hy0 = "-Host Thickness / 2 - Coil Hood", hy1 = "-Host Thickness / 2"
        f.solids.append(box("Coil Hood", "-Width / 2 - Frame Width", "Width / 2 + Frame Width", hy0, hy1, "Height + Frame Width", "Height + Frame Width + Coil Hood",
                            material: "Frame Material", sub: .frame))
        f.planLines += rect("-Width / 2", "-Panel Thickness / 2", "Width / 2", "Panel Thickness / 2", .panel)
            + rect("-Width / 2 - Frame Width", hy0, "Width / 2 + Frame Width", hy1, .hidden)
        var d = doorDefaults(system, frame: system == .imperial ? i(4) : 0.1, depth: system == .imperial ? i(4) : 0.1, panel: system == .imperial ? i(1) : 0.025)
        d["Host Thickness"] = system == .imperial ? i(8) : 0.23
        d["Coil Hood"] = system == .imperial ? i(18) : 0.45
        f.types = system == .imperial
            ? types(system, [sz(96, 96, feet: true), sz(120, 120, feet: true), sz(144, 144, feet: true), sz(144, 168, feet: true), sz(168, 168, feet: true)], defaults: d)
            : types(system, [sz(2400, 2400), sz(3000, 3000), sz(3600, 3600), sz(4000, 4000)], defaults: d)
        return f
    }

    static func storefront(_ system: UnitSystem, double: Bool) -> FamilyDefinition {
        var f = door(double ? "Door - Storefront Double" : "Door - Storefront Single",
                     double ? "Pair of aluminum-framed glass entrance doors." : "Aluminum-framed glass entrance door.",
                     extra: glazedParams + (double ? [FamilyParameter(name: "Leaf Width", type: .length, formula: "Width / 2")] : []))
        if double {
            f.solids += glazedLeaf("Left ", "-Width / 2", "-0.002 m") + glazedLeaf("Right ", "0.002 m", "Width / 2")
            f.planLines += swing("-Width / 2", leaf: "Leaf Width") + swing("Width / 2", leaf: "Leaf Width", right: true)
        } else {
            f.solids += glazedLeaf("", "-Width / 2", "Width / 2")
            f.planLines += swing("-Width / 2", leaf: "Width")
        }
        let d = system == .imperial
            ? ["Frame Width": i(1.75), "Frame Depth": i(4.5), "Panel Thickness": i(1.75), "Stile Width": i(3.5), "Bottom Rail": i(10), "Glass Thickness": i(0.5)]
            : ["Frame Width": 0.05, "Frame Depth": 0.12, "Panel Thickness": 0.05, "Stile Width": 0.09, "Bottom Rail": 0.25, "Glass Thickness": 0.012]
        f.types = system == .imperial
            ? types(system, double ? [sz(72, 84), sz(72, 96)] : [sz(36, 84), sz(42, 84), sz(36, 96)], defaults: d)
            : types(system, double ? [sz(1800, 2100), sz(2000, 2400)] : [sz(1000, 2100), sz(1000, 2400)], defaults: d)
        return f
    }

    /// Flush leaf with a narrow vision lite, built around the lite so the glass shows.
    static func visionLeaf(_ prefix: String, _ x0: String, _ x1: String) -> [FamilySolid] {
        let c = "((\(x0)) + (\(x1))) / 2"
        let vx0 = "\(c) - Vision Width / 2", vx1 = "\(c) + Vision Width / 2"
        let vz0 = "Height * 0.55", vz1 = "Height * 0.55 + Vision Height"
        return [
            flushLeaf("\(prefix)Leaf Left", x0, vx0),
            flushLeaf("\(prefix)Leaf Right", vx1, x1),
            flushLeaf("\(prefix)Leaf Below Lite", vx0, vx1, z0: "0", z1: vz0),
            flushLeaf("\(prefix)Leaf Above Lite", vx0, vx1, z0: vz1, z1: "Height"),
            box("\(prefix)Vision Lite", vx0, vx1, "-Glass Thickness / 2", "Glass Thickness / 2", vz0, vz1, material: "Glass Material", sub: .glass),
        ]
    }

    static func fireRated(_ system: UnitSystem, double: Bool) -> FamilyDefinition {
        var f = door(double ? "Door - Fire Rated Double" : "Door - Fire Rated Single",
                     double ? "Fire-rated pair of flush doors with vision lites in a steel frame." : "Fire-rated flush door with a vision lite in a steel frame.",
                     extra: [len("Vision Width"), len("Vision Height"), len("Glass Thickness"), mat("Glass Material")]
                        + (double ? [FamilyParameter(name: "Leaf Width", type: .length, formula: "Width / 2")] : []))
        if double {
            f.solids += visionLeaf("Left ", "-Width / 2", "-0.002 m") + visionLeaf("Right ", "0.002 m", "Width / 2")
            f.planLines += swing("-Width / 2", leaf: "Leaf Width") + swing("Width / 2", leaf: "Leaf Width", right: true)
        } else {
            f.solids += visionLeaf("", "-Width / 2", "Width / 2")
            f.planLines += swing("-Width / 2", leaf: "Width")
        }
        var d = doorDefaults(system)
        if system == .imperial {
            d["Vision Width"] = i(4); d["Vision Height"] = i(24); d["Glass Thickness"] = i(0.25)
            f.types = types(system, double ? [sz(72, 84, "(90 min)"), sz(60, 84, "(90 min)"), sz(72, 84, "(60 min)")]
                            : [sz(36, 84, "(20 min)"), sz(36, 84, "(60 min)"), sz(36, 84, "(90 min)"), sz(42, 84, "(90 min)"), sz(36, 80, "(20 min)")], defaults: d)
        } else {
            d["Vision Width"] = 0.15; d["Vision Height"] = 0.6; d["Glass Thickness"] = 0.008
            f.types = types(system, double ? [sz(1800, 2100, "(60 min)"), sz(2000, 2100, "(120 min)")]
                            : [sz(900, 2100, "(30 min)"), sz(1000, 2100, "(60 min)"), sz(1000, 2100, "(120 min)")], defaults: d)
        }
        return f
    }

    // MARK: Window scaffolding

    static func windowDefaults(_ system: UnitSystem, sill: Double) -> [String: Double] {
        system == .imperial
            ? ["Default Sill Height": i(sill), "Frame Width": i(2.25), "Frame Depth": i(4), "Glass Thickness": i(1), "Sash Width": i(2)]
            : ["Default Sill Height": sill / 1000, "Frame Width": 0.06, "Frame Depth": 0.1, "Glass Thickness": 0.024, "Sash Width": 0.05]
    }

    static func window(_ name: String, _ description: String, extra: [FamilyParameter] = [], frame: Bool = true) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: .window)
        f.description = description
        f.parameters = [len("Width", builtIn: true), len("Height", builtIn: true), len("Default Sill Height"), len("Frame Width"), len("Frame Depth"),
                        len("Glass Thickness"), len("Sash Width")] + extra + [mat("Frame Material"), mat("Glass Material")]
        f.referencePlanes = [
            FamilyReferencePlane(name: "Center (Left/Right)", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
            FamilyReferencePlane(name: "Left", axis: .x, offset: "-Width / 2", strength: .left),
            FamilyReferencePlane(name: "Right", axis: .x, offset: "Width / 2", strength: .right),
            FamilyReferencePlane(name: "Sill", axis: .z, offset: "0", strength: .bottom, definesOrigin: true),
            FamilyReferencePlane(name: "Head", axis: .z, offset: "Height", strength: .top),
        ]
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Sill", planeB: "Head", labelParameter: "Height")]
        if frame {
            let y0 = "-Frame Depth / 2", y1 = "Frame Depth / 2"
            f.solids = [
                box("Left Frame", "-Width / 2", "-Width / 2 + Frame Width", y0, y1, "0", "Height", material: "Frame Material", sub: .frame, plan: true),
                box("Right Frame", "Width / 2 - Frame Width", "Width / 2", y0, y1, "0", "Height", material: "Frame Material", sub: .frame, plan: true),
                box("Sill Frame", "-Width / 2 + Frame Width", "Width / 2 - Frame Width", y0, y1, "0", "Frame Width", material: "Frame Material", sub: .frame),
                box("Head Frame", "-Width / 2 + Frame Width", "Width / 2 - Frame Width", y0, y1, "Height - Frame Width", "Height", material: "Frame Material", sub: .frame),
            ]
            f.planLines = rect("-Width / 2", y0, "-Width / 2 + Frame Width", y1, .frame) + rect("Width / 2 - Frame Width", y0, "Width / 2", y1, .frame)
        }
        f.opening = FamilyOpening(xMin: p("Left"), xMax: p("Right"), zMin: p("Sill"), zMax: p("Head"))
        return f
    }

    /// An operable sash (four sash members and glass) between x0…x1 and z0…z1, centered on `y`, `depth` deep.
    static func sash(_ prefix: String, _ x0: String, _ x1: String, _ z0: String, _ z1: String, y: String = "0", depth: String = "Frame Depth * 0.6") -> [FamilySolid] {
        let y0 = "\(y) - \(depth) / 2", y1 = "\(y) + \(depth) / 2"
        return [
            box("\(prefix)Sash L", x0, "\(x0) + Sash Width", y0, y1, z0, z1, material: "Frame Material", sub: .frame),
            box("\(prefix)Sash R", "\(x1) - Sash Width", x1, y0, y1, z0, z1, material: "Frame Material", sub: .frame),
            box("\(prefix)Sash Bottom", "\(x0) + Sash Width", "\(x1) - Sash Width", y0, y1, z0, "\(z0) + Sash Width", material: "Frame Material", sub: .frame),
            box("\(prefix)Sash Top", "\(x0) + Sash Width", "\(x1) - Sash Width", y0, y1, "\(z1) - Sash Width", z1, material: "Frame Material", sub: .frame),
            glass("\(prefix)Glass", "\(x0) + Sash Width", "\(x1) - Sash Width", "\(z0) + Sash Width", "\(z1) - Sash Width", y: y),
        ]
    }
    static func glass(_ name: String, _ x0: String, _ x1: String, _ z0: String, _ z1: String, y: String = "0") -> FamilySolid {
        box(name, x0, x1, "\(y) - Glass Thickness / 2", "\(y) + Glass Thickness / 2", z0, z1, material: "Glass Material", sub: .glass)
    }
    static func glassLines(_ x0: String, _ x1: String, y: String = "0") -> [FamilyLine] {
        [line((x0, "\(y) - Glass Thickness / 2"), (x1, "\(y) - Glass Thickness / 2"), .glass),
         line((x0, "\(y) + Glass Thickness / 2"), (x1, "\(y) + Glass Thickness / 2"), .glass)]
    }
    static let innerL = "-Width / 2 + Frame Width", innerR = "Width / 2 - Frame Width", innerB = "Frame Width", innerT = "Height - Frame Width"

    // MARK: Windows

    static func fixedWindow(_ system: UnitSystem, picture: Bool) -> FamilyDefinition {
        var f = window(picture ? "Window - Picture" : "Window - Fixed",
                       picture ? "Large fixed picture window with a deep frame." : "Fixed glazed window.")
        f.solids.append(glass("Glass", innerL, innerR, innerB, innerT))
        f.planLines += glassLines(innerL, innerR)
        if picture {
            var d = windowDefaults(system, sill: system == .imperial ? 18 : 450)
            d["Frame Width"] = system == .imperial ? i(3) : 0.08
            f.types = system == .imperial ? types(system, [sz(60, 48), sz(72, 60), sz(96, 60)], defaults: d)
                : types(system, [sz(1800, 1500), sz(2400, 1800), sz(3000, 2100)], defaults: d)
        } else {
            f.types = system == .imperial
                ? types(system, [sz(24, 36), sz(24, 48), sz(36, 48), sz(48, 48), sz(36, 60), sz(48, 60), sz(72, 48)], defaults: windowDefaults(system, sill: 36))
                : types(system, [sz(600, 900), sz(900, 1200), sz(1200, 1200), sz(1200, 1500), sz(1800, 1200), sz(2400, 1500)], defaults: windowDefaults(system, sill: 900))
        }
        return f
    }

    /// The single casement keeps the starter family's name and parameters (so existing type values stay valid).
    static func casement(_ system: UnitSystem) -> FamilyDefinition {
        var f = window("Window - Casement", "Single casement window.")
        f.solids += sash("", innerL, innerR, innerB, innerT)
        f.planLines += glassLines(innerL, innerR)
        f.types = system == .imperial
            ? types(system, [sz(24, 36), sz(24, 48), sz(30, 48), sz(30, 60), sz(36, 60), sz(48, 60), sz(72, 60)], defaults: windowDefaults(system, sill: 36))
                + types(system, [sz(96, 84, "Glazed Wall")], defaults: windowDefaults(system, sill: 12))
            : types(system, [sz(1200, 1500), sz(600, 1200), sz(1800, 1500)], defaults: windowDefaults(system, sill: 900))
                + types(system, [sz(2400, 2100, "Glazed Wall")], defaults: windowDefaults(system, sill: 300).merging(["Frame Width": 0.07, "Frame Depth": 0.12, "Glass Thickness": 0.028]) { _, b in b })
                + types(system, [sz(600, 900), sz(900, 1200), sz(600, 1500)], defaults: windowDefaults(system, sill: 900))
        return f
    }

    static func casementDouble(_ system: UnitSystem) -> FamilyDefinition {
        var f = window("Window - Casement Double", "Pair of casement sashes either side of a center mullion.")
        f.solids.append(box("Mullion", "-Frame Width / 2", "Frame Width / 2", "-Frame Depth / 2", "Frame Depth / 2", innerB, innerT, material: "Frame Material", sub: .frame, plan: true))
        f.solids += sash("Left ", innerL, "-Frame Width / 2", innerB, innerT) + sash("Right ", "Frame Width / 2", innerR, innerB, innerT)
        f.planLines += glassLines(innerL, "-Frame Width / 2") + glassLines("Frame Width / 2", innerR)
            + rect("-Frame Width / 2", "-Frame Depth / 2", "Frame Width / 2", "Frame Depth / 2", .frame)
        f.types = system == .imperial
            ? types(system, [sz(48, 48), sz(48, 60), sz(60, 48), sz(72, 60)], defaults: windowDefaults(system, sill: 36))
            : types(system, [sz(1200, 1200), sz(1200, 1500), sz(1500, 1500), sz(1800, 1500)], defaults: windowDefaults(system, sill: 900))
        return f
    }

    static func projectedSash(_ system: UnitSystem, awning: Bool) -> FamilyDefinition {
        var f = window(awning ? "Window - Awning" : "Window - Hopper",
                       awning ? "Top-hinged sash opening outward." : "Bottom-hinged sash opening inward.")
        f.solids += sash("", innerL, innerR, innerB, innerT)
        f.planLines += glassLines(innerL, innerR)
        if awning {
            f.types = system == .imperial ? types(system, [sz(36, 24), sz(48, 24), sz(36, 20)], defaults: windowDefaults(system, sill: 48))
                : types(system, [sz(900, 600), sz(1200, 600)], defaults: windowDefaults(system, sill: 1200))
        } else {
            f.types = system == .imperial ? types(system, [sz(32, 16), sz(32, 24), sz(36, 20)], defaults: windowDefaults(system, sill: 18))
                : types(system, [sz(900, 450), sz(1200, 600)], defaults: windowDefaults(system, sill: 450))
        }
        return f
    }

    static func hung(_ system: UnitSystem, double: Bool) -> FamilyDefinition {
        var f = window(double ? "Window - Double Hung" : "Window - Single Hung",
                       double ? "Two vertically sliding sashes." : "Fixed upper sash over a vertically sliding lower sash.")
        f.solids += sash("Upper ", innerL, innerR, "Height / 2 - Sash Width / 2", innerT, y: "Frame Depth / 5", depth: "Frame Depth * 0.35")
            + sash("Lower ", innerL, innerR, innerB, "Height / 2 + Sash Width / 2", y: "-Frame Depth / 5", depth: "Frame Depth * 0.35")
        f.planLines += glassLines(innerL, innerR, y: "Frame Depth / 5") + glassLines(innerL, innerR, y: "-Frame Depth / 5")
        var d = windowDefaults(system, sill: system == .imperial ? 30 : 900)
        d["Glass Thickness"] = system == .imperial ? i(0.75) : 0.018
        f.types = system == .imperial
            ? types(system, double ? [sz(24, 36), sz(28, 48), sz(30, 54), sz(32, 62), sz(36, 62), sz(36, 72)] : [sz(24, 36), sz(28, 54), sz(32, 54), sz(36, 60), sz(36, 72)], defaults: d)
            : types(system, double ? [sz(600, 1200), sz(900, 1500), sz(900, 1800)] : [sz(600, 1200), sz(900, 1500)], defaults: d)
        return f
    }

    static func sliding(_ system: UnitSystem, tracks n: Int) -> FamilyDefinition {
        var f = window(n == 2 ? "Window - Sliding 2-Track" : "Window - Sliding 3-Track",
                       n == 2 ? "Two sashes sliding in two tracks." : "Three sashes in three tracks (two glazed, often one mesh shutter).")
        let depth = "Frame Depth / \(n + 1)"
        for k in 0..<n {
            let a = Double(k) / Double(n), b = Double(k + 1) / Double(n)
            let x0 = k == 0 ? innerL : "\(innerL) + (Width - 2 * Frame Width) * \(a) - Sash Width / 2"
            let x1 = k == n - 1 ? innerR : "\(innerL) + (Width - 2 * Frame Width) * \(b) + Sash Width / 2"
            let y = "-Frame Depth / 2 + Frame Depth * \((Double(k) + 0.5) / Double(n))"
            f.solids += sash("Sash \(k + 1) ", x0, x1, innerB, innerT, y: y, depth: depth)
            f.planLines += glassLines(x0, x1, y: y)
        }
        var d = windowDefaults(system, sill: system == .imperial ? 36 : 900)
        d["Glass Thickness"] = system == .imperial ? i(0.25) : 0.006
        d["Frame Depth"] = system == .imperial ? i(n == 2 ? 3.25 : 4.5) : (n == 2 ? 0.08 : 0.11)
        f.types = system == .imperial
            ? types(system, n == 2 ? [sz(36, 24), sz(48, 36), sz(48, 48), sz(60, 36), sz(72, 48)] : [sz(72, 48), sz(96, 48), sz(96, 60)], defaults: d)
            : types(system, n == 2 ? [sz(1200, 900), sz(1200, 1200), sz(1500, 1200), sz(1800, 1200)] : [sz(1800, 1200), sz(2100, 1200), sz(2400, 1500)], defaults: d)
        return f
    }

    /// Three-sided bay projecting to the exterior at 45°, with a seat board and head board.
    static func bay(_ system: UnitSystem) -> FamilyDefinition {
        var f = window("Window - Bay", "Three-sided bay projecting outward at 45 degrees.", extra: [len("Bay Depth")], frame: false)
        // Plan corners: A (−W/2, 0) → B (−W/2 + D, D) → C (W/2 − D, D) → E (W/2, 0).
        let ax = "-Width / 2", bx = "-Width / 2 + Bay Depth", cx = "Width / 2 - Bay Depth", ex = "Width / 2", d = "Bay Depth"
        let outline = [FamilyPoint(ax, "0"), FamilyPoint(ex, "0"), FamilyPoint(cx, d), FamilyPoint(bx, d)]
        f.solids += [
            FamilySolid(name: "Seat Board", profile: .polygon(outline), zMin: x("0"), zMax: x("Frame Width"), materialParameter: "Frame Material", subcategory: .sill, visibleInPlan: false),
            FamilySolid(name: "Head Board", profile: .polygon(outline), zMin: x("Height - Frame Width"), zMax: x("Height"), materialParameter: "Frame Material", subcategory: .frame, visibleInPlan: false),
        ]
        for (name, px, py) in [("Post A", ax, "0"), ("Post B", bx, d), ("Post C", cx, d), ("Post E", ex, "0")] {
            f.solids.append(box(name, "\(px) - Frame Width / 2", "\(px) + Frame Width / 2", "\(py) - Frame Width / 2", "\(py) + Frame Width / 2",
                                "Frame Width", "Height - Frame Width", material: "Frame Material", sub: .frame, plan: true))
        }
        let s = "Glass Thickness * 0.35355339"
        func strip(_ name: String, _ p: (String, String), _ q: (String, String), diagonal: Int) -> FamilySolid {
            // diagonal: +1 for A→B (normal (−1, 1)/√2), −1 for C→E (normal (1, 1)/√2), 0 for B→C (normal (0, 1)).
            let pts: [FamilyPoint]
            switch diagonal {
            case 1: pts = [FamilyPoint("\(p.0) - \(s)", "\(p.1) + \(s)"), FamilyPoint("\(q.0) - \(s)", "\(q.1) + \(s)"),
                           FamilyPoint("\(q.0) + \(s)", "\(q.1) - \(s)"), FamilyPoint("\(p.0) + \(s)", "\(p.1) - \(s)")]
            case -1: pts = [FamilyPoint("\(p.0) + \(s)", "\(p.1) + \(s)"), FamilyPoint("\(q.0) + \(s)", "\(q.1) + \(s)"),
                            FamilyPoint("\(q.0) - \(s)", "\(q.1) - \(s)"), FamilyPoint("\(p.0) - \(s)", "\(p.1) - \(s)")]
            default: pts = [FamilyPoint(p.0, "\(p.1) - Glass Thickness / 2"), FamilyPoint(q.0, "\(q.1) - Glass Thickness / 2"),
                            FamilyPoint(q.0, "\(q.1) + Glass Thickness / 2"), FamilyPoint(p.0, "\(p.1) + Glass Thickness / 2")]
            }
            return FamilySolid(name: name, profile: .polygon(pts), zMin: x("Frame Width"), zMax: x("Height - Frame Width"),
                               materialParameter: "Glass Material", subcategory: .glass, visibleInPlan: false)
        }
        f.solids += [strip("Glass Left", (ax, "0"), (bx, d), diagonal: 1), strip("Glass Front", (bx, d), (cx, d), diagonal: 0),
                     strip("Glass Right", (cx, d), (ex, "0"), diagonal: -1)]
        f.planLines += [line((ax, "0"), (bx, d), .frame), line((bx, d), (cx, d), .frame), line((cx, d), (ex, "0"), .frame),
                        line((ax, "0"), (ex, "0"), .sill)]
        var dd = windowDefaults(system, sill: system == .imperial ? 18 : 450)
        dd["Bay Depth"] = system == .imperial ? i(18) : 0.45
        f.types = system == .imperial ? types(system, [sz(72, 60), sz(96, 60)], defaults: dd)
            : types(system, [sz(1800, 1500), sz(2400, 1500)], defaults: dd)
        return f
    }

    /// Glass louvres (jalousie) as tilted slats swept across the opening.
    static func louvered(_ system: UnitSystem, ventilator: Bool) -> FamilyDefinition {
        var f = window(ventilator ? "Window - Ventilator" : "Window - Louvered",
                       ventilator ? "Small high-level louvred ventilator for bathrooms and stores." : "Adjustable glass louvres (jalousie).")
        let n = ventilator ? 4 : 8
        let pitch = "(Height - 2 * Frame Width) / \(n)"
        for k in 0..<n {
            let z = "Frame Width + (Height - 2 * Frame Width) * \(Double(k) / Double(n))"
            let profile = [FamilyPoint("Frame Depth * 0.4", "0"), FamilyPoint("Frame Depth * 0.4", "Glass Thickness"),
                           FamilyPoint("-Frame Depth * 0.4", "\(pitch) * 0.9 + Glass Thickness"), FamilyPoint("-Frame Depth * 0.4", "\(pitch) * 0.9")]
            var s = FamilySolid(name: "Louvre \(k + 1)", profile: .sweep(FamilySweep(path: [FamilyPoint(innerL, "0"), FamilyPoint(innerR, "0")], profile: profile)),
                                zMin: x(z), zMax: x(z), materialParameter: "Glass Material", subcategory: .glass, visibleInPlan: false)
            s.visibleAt = [.medium, .fine]
            f.solids.append(s)
        }
        f.planLines += [line((innerL, "-Frame Depth * 0.4"), (innerR, "Frame Depth * 0.4"), .glass)]
        var d = windowDefaults(system, sill: system == .imperial ? (ventilator ? 72 : 36) : (ventilator ? 1650 : 900))
        d["Glass Thickness"] = system == .imperial ? i(0.25) : 0.006
        f.types = system == .imperial
            ? types(system, ventilator ? [sz(24, 18), sz(30, 18)] : [sz(24, 36), sz(36, 48)], defaults: d)
            : (ventilator ? types(system, [sz(600, 450)], defaults: d) + types(system, [sz(900, 600)], defaults: windowDefaults(system, sill: 1500).merging(["Glass Thickness": 0.006]) { _, b in b })
                : types(system, [sz(600, 900), sz(900, 1200)], defaults: d))
        return f
    }
}
