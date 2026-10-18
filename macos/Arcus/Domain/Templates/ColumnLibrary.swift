import Foundation
import ArcusGeometry
import ArcusCalc

/// Architectural and structural column families with imperial and metric types (original Arcus content).
///
/// Section dimensions are the published nominal values of common standard shapes (U.S. wide-flange, HSS and pipe;
/// European IPE/HEA/HEB, SHS/RHS/CHS; Indian ISMB/ISHB), modelled without root fillets or corner radii.
/// Profiles use the family extrusion forms: I and H shapes are 12-point polygons; hollow sections are a solid
/// extrusion with a void extrusion cut from it, so the evaluated profile has a hole (3D and plan).
///
/// Every column family has an instance "Height" (the column tool sets it from the base and top constraints),
/// placed at the column's location with its base at Z = 0.
public enum ColumnLibrary {
    static func x(_ s: String) -> FamilyBound { .expr(s) }
    static func len(_ name: String, _ isInstance: Bool = false, builtIn: Bool = false) -> FamilyParameter {
        FamilyParameter(name: name, type: .length, isInstance: isInstance, group: .dimensions, isBuiltIn: builtIn)
    }
    static let inch = 0.0254

    public typealias Entry = OpeningLibrary.Entry

    /// Every column family for a unit system.
    public static func families(_ system: UnitSystem) -> [Entry] {
        let im = system == .imperial
        let finish = ["Material": "Plaster"]
        let concrete = ["Material": "Concrete, Cast-in-Place"]
        let steel = ["Material": "Steel, Structural"]
        return [
            Entry(family: rectangular(system), materials: finish),
            Entry(family: square(system), materials: finish),
            Entry(family: round(system), materials: finish),
            Entry(family: classical(system), materials: ["Material": "Limestone"]),
            Entry(family: octagonal(system), materials: finish),
            Entry(family: pilaster(system), materials: finish),
            Entry(family: concreteRectangular(system), materials: concrete),
            Entry(family: concreteRound(system), materials: concrete),
            Entry(family: iSection(system), materials: steel),
            Entry(family: hollowRectangular(system), materials: steel),
            Entry(family: hollowRound(system), materials: steel),
            Entry(family: timber(system, glulam: false), materials: ["Material": im ? "Wood - Dimensional Lumber" : "Timber Stud"]),
            Entry(family: timber(system, glulam: true), materials: ["Material": "Glued-Laminated Timber (Glulam)"]),
        ]
    }

    // MARK: Scaffolding

    static func column(_ name: String, _ template: FamilyTemplate, _ description: String, _ params: [FamilyParameter]) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: template)
        f.description = description
        f.parameters = params + [len("Height", true, builtIn: true), FamilyParameter(name: "Material", type: .elementRef(.materials), group: .materials)]
        f.referencePlanes = [
            FamilyReferencePlane(name: "Center (Left/Right)", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
            FamilyReferencePlane(name: "Center (Front/Back)", axis: .y, offset: "0", strength: .centerFrontBack, definesOrigin: true),
            FamilyReferencePlane(name: "Bottom", axis: .z, offset: "0", strength: .bottom, definesOrigin: true),
            FamilyReferencePlane(name: "Top", axis: .z, offset: "Height", strength: .top),
        ]
        f.dimensions = [FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
        return f
    }
    static func extrusion(_ name: String, _ profile: FamilySolid.Profile, void: Bool = false, z0: String = "0", z1: String = "Height", plan: Bool = true) -> FamilySolid {
        FamilySolid(name: name, profile: profile, zMin: z0 == "0" ? .plane("Bottom") : x(z0), zMax: z1 == "Height" ? .plane("Top") : x(z1),
                    materialParameter: void ? nil : "Material", subcategory: .general, isVoid: void, visibleInPlan: plan)
    }
    static func rectProfile(_ w: String, _ d: String) -> FamilySolid.Profile {
        .rectangle(xMin: x("-(\(w)) / 2"), xMax: x("(\(w)) / 2"), yMin: x("-(\(d)) / 2"), yMax: x("(\(d)) / 2"))
    }
    /// I/H section: depth along Y, flanges along X.
    static func iProfile() -> FamilySolid.Profile {
        let bf = "Flange Width / 2", d = "Depth / 2", tw = "Web Thickness / 2", tf = "Flange Thickness"
        return .polygon([
            FamilyPoint("-\(bf)", "-\(d)"), FamilyPoint(bf, "-\(d)"), FamilyPoint(bf, "-\(d) + \(tf)"), FamilyPoint(tw, "-\(d) + \(tf)"),
            FamilyPoint(tw, "\(d) - \(tf)"), FamilyPoint(bf, "\(d) - \(tf)"), FamilyPoint(bf, d), FamilyPoint("-\(bf)", d),
            FamilyPoint("-\(bf)", "\(d) - \(tf)"), FamilyPoint("-\(tw)", "\(d) - \(tf)"), FamilyPoint("-\(tw)", "-\(d) + \(tf)"), FamilyPoint("-\(bf)", "-\(d) + \(tf)"),
        ])
    }

    /// Type rows. `dims` are in inches (imperial) or millimeters (metric), matched to `keys`.
    static func types(_ system: UnitSystem, _ keys: [String], _ rows: [(String, [Double])], height: Double? = nil) -> [FamilyTypeDefinition] {
        let k = system == .imperial ? inch : 0.001
        return rows.map { name, dims in
            var v: [String: ParamValue] = ["Height": .double(height ?? (system == .imperial ? 10 * 12 * inch : 3.0))]
            for (key, d) in zip(keys, dims) { v[key] = .double(d * k) }
            return FamilyTypeDefinition(name: name, values: v)
        }
    }
    static func inchName(_ a: Double, _ b: Double) -> String { "\(OpeningLibrary.inchText(a)) x \(OpeningLibrary.inchText(b))" }
    static func mmName(_ a: Double, _ b: Double) -> String { "\(Int(a)) x \(Int(b))" }

    // MARK: Architectural columns

    static func rectangular(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Rectangular", .column, "Rectangular architectural column or column enclosure.", [len("Width", builtIn: true), len("Depth", builtIn: true)])
        f.solids = [extrusion("Shaft", rectProfile("Width", "Depth"))]
        let rows: [(Double, Double)] = s == .imperial ? [(12, 12), (12, 18), (16, 16), (18, 18), (18, 24), (24, 24)]
            : [(230, 230), (230, 300), (230, 450), (300, 300), (300, 450), (400, 400), (450, 450), (600, 600)]
        f.types = types(s, ["Width", "Depth"], rows.map { (s == .imperial ? inchName($0.0, $0.1) : mmName($0.0, $0.1), [$0.0, $0.1]) })
        return f
    }

    static func square(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Square", .column, "Square architectural column.", [len("Width", builtIn: true)])
        f.solids = [extrusion("Shaft", rectProfile("Width", "Width"))]
        let rows: [Double] = s == .imperial ? [10, 12, 14, 16, 18, 24] : [250, 300, 350, 400, 450, 500, 600]
        f.types = types(s, ["Width"], rows.map { (s == .imperial ? inchName($0, $0) : mmName($0, $0), [$0]) })
        return f
    }

    static func diameterName(_ s: UnitSystem, _ d: Double) -> String { s == .imperial ? "\(OpeningLibrary.inchText(d)) Diameter" : "\(Int(d)) Diameter" }

    static func round(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Round", .column, "Round architectural column.", [len("Diameter", builtIn: true)])
        f.solids = [extrusion("Shaft", .circle(center: FamilyPoint("0", "0"), radius: "Diameter / 2"))]
        let rows: [Double] = s == .imperial ? [10, 12, 14, 16, 18, 24] : [230, 300, 350, 400, 450, 600]
        f.types = types(s, ["Diameter"], rows.map { (diameterName(s, $0), [$0]) })
        return f
    }

    /// Round shaft on a square plinth and moulded base, with a moulded capital and square abacus.
    static func classical(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Round with Base and Capital", .column, "Round column with a square plinth, moulded base, capital and abacus.",
                       [len("Diameter", builtIn: true), len("Base Width"), len("Base Height"), len("Capital Height")])
        var plinth = FamilySolid(name: "Plinth", profile: rectProfile("Base Width", "Base Width"), zMin: .plane("Bottom"), zMax: x("Base Height * 0.5"),
                                 materialParameter: "Material", visibleInPlan: false)
        plinth.visibleAt = [.coarse, .medium, .fine]
        let base = FamilySolid(name: "Base Moulding", profile: .revolve(FamilyRevolve(profile: [
            FamilyPoint("0", "0"), FamilyPoint("Diameter * 0.66", "0"), FamilyPoint("Diameter * 0.66", "Base Height * 0.2"),
            FamilyPoint("Diameter * 0.56", "Base Height * 0.35"), FamilyPoint("Diameter / 2", "Base Height * 0.5"), FamilyPoint("0", "Base Height * 0.5"),
        ])), zMin: x("Base Height * 0.5"), zMax: x("Base Height * 0.5"), materialParameter: "Material", visibleInPlan: false)
        let shaft = FamilySolid(name: "Shaft", profile: .circle(center: FamilyPoint("0", "0"), radius: "Diameter / 2"), zMin: x("Base Height"),
                                zMax: x("Height - Capital Height"), materialParameter: "Material")
        let capital = FamilySolid(name: "Capital", profile: .revolve(FamilyRevolve(profile: [
            FamilyPoint("0", "0"), FamilyPoint("Diameter / 2", "0"), FamilyPoint("Diameter * 0.58", "Capital Height * 0.3"),
            FamilyPoint("Diameter * 0.66", "Capital Height * 0.6"), FamilyPoint("0", "Capital Height * 0.6"),
        ])), zMin: x("Height - Capital Height"), zMax: x("Height - Capital Height"), materialParameter: "Material", visibleInPlan: false)
        let abacus = FamilySolid(name: "Abacus", profile: rectProfile("Base Width", "Base Width"), zMin: x("Height - Capital Height * 0.4"), zMax: .plane("Top"),
                                 materialParameter: "Material", visibleInPlan: false)
        f.solids = [plinth, base, shaft, capital, abacus]
        let rows: [(Double, Double, Double, Double)] = s == .imperial ? [(12, 18, 10, 10), (16, 22, 12, 12), (20, 28, 14, 14)]
            : [(300, 450, 250, 250), (400, 560, 300, 300), (500, 700, 350, 350)]
        f.types = types(s, ["Diameter", "Base Width", "Base Height", "Capital Height"], rows.map { (diameterName(s, $0.0), [$0.0, $0.1, $0.2, $0.3]) })
        return f
    }

    static func octagonal(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Octagonal", .column, "Regular octagonal column; Width is measured across flats.", [len("Width", builtIn: true)])
        let a = "Width / 2", b = "Width * 0.20710678"
        f.solids = [extrusion("Shaft", .polygon([
            FamilyPoint(a, "-\(b)"), FamilyPoint(a, b), FamilyPoint(b, a), FamilyPoint("-\(b)", a),
            FamilyPoint("-\(a)", b), FamilyPoint("-\(a)", "-\(b)"), FamilyPoint("-\(b)", "-\(a)"), FamilyPoint(b, "-\(a)"),
        ]))]
        let rows: [Double] = s == .imperial ? [12, 16, 18, 24] : [300, 400, 450, 600]
        f.types = types(s, ["Width"], rows.map { ((s == .imperial ? OpeningLibrary.inchText($0) : "\(Int($0))") + " Across Flats", [$0]) })
        return f
    }

    static func pilaster(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Column - Pilaster", .column, "Pilaster projecting from a wall face; place it on the face (the back face is at the insertion point).",
                       [len("Width", builtIn: true), len("Projection")])
        f.solids = [extrusion("Pilaster", .rectangle(xMin: x("-Width / 2"), xMax: x("Width / 2"), yMin: x("0"), yMax: x("Projection")))]
        let rows: [(Double, Double)] = s == .imperial ? [(12, 4), (16, 4), (16, 8), (24, 8)] : [(300, 100), (400, 115), (450, 230), (600, 230)]
        f.types = types(s, ["Width", "Projection"], rows.map { (s == .imperial ? inchName($0.0, $0.1) : mmName($0.0, $0.1), [$0.0, $0.1]) })
        return f
    }

    // MARK: Structural columns

    static func concreteRectangular(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Concrete Column - Rectangular", .structuralColumn, "Cast-in-place concrete column, rectangular.",
                       [len("Width", builtIn: true), len("Depth", builtIn: true)])
        f.solids = [extrusion("Column", rectProfile("Width", "Depth"))]
        let rows: [(Double, Double)] = s == .imperial ? [(12, 12), (12, 18), (14, 14), (16, 16), (18, 18), (20, 20), (24, 24), (24, 36)]
            : [(230, 230), (230, 300), (230, 450), (300, 300), (300, 450), (300, 600), (400, 400), (450, 450), (500, 500), (600, 600)]
        f.types = types(s, ["Width", "Depth"], rows.map { (s == .imperial ? inchName($0.0, $0.1) : mmName($0.0, $0.1), [$0.0, $0.1]) })
        return f
    }

    static func concreteRound(_ s: UnitSystem) -> FamilyDefinition {
        var f = column("Concrete Column - Round", .structuralColumn, "Cast-in-place concrete column, round.", [len("Diameter", builtIn: true)])
        f.solids = [extrusion("Column", .circle(center: FamilyPoint("0", "0"), radius: "Diameter / 2"))]
        let rows: [Double] = s == .imperial ? [12, 16, 18, 20, 24, 30] : [300, 350, 400, 450, 500, 600]
        f.types = types(s, ["Diameter"], rows.map { (diameterName(s, $0), [$0]) })
        return f
    }

    /// Wide-flange / I / H sections: (name, d, bf, tw, tf) in inches or millimeters.
    public static func iSectionRows(_ s: UnitSystem) -> [(String, Double, Double, Double, Double)] {
        s == .imperial ? [
            ("W8x24", 7.93, 6.50, 0.245, 0.400), ("W8x31", 8.00, 8.00, 0.285, 0.435), ("W8x40", 8.25, 8.07, 0.360, 0.560),
            ("W10x33", 9.73, 7.96, 0.290, 0.435), ("W10x39", 9.92, 7.99, 0.315, 0.530), ("W10x49", 9.98, 10.0, 0.340, 0.560),
            ("W10x60", 10.2, 10.1, 0.420, 0.680), ("W12x40", 11.9, 8.01, 0.295, 0.515), ("W12x53", 12.1, 10.0, 0.345, 0.575),
            ("W12x65", 12.1, 12.0, 0.390, 0.605), ("W12x79", 12.4, 12.1, 0.470, 0.735), ("W14x48", 13.8, 8.03, 0.340, 0.595),
            ("W14x61", 13.9, 10.0, 0.375, 0.645), ("W14x90", 14.0, 14.5, 0.440, 0.710), ("W14x120", 14.5, 14.7, 0.590, 0.940),
        ] : [
            ("IPE 200", 200, 100, 5.6, 8.5), ("IPE 240", 240, 120, 6.2, 9.8), ("IPE 300", 300, 150, 7.1, 10.7), ("IPE 360", 360, 170, 8.0, 12.7),
            ("IPE 400", 400, 180, 8.6, 13.5),
            ("HEA 160", 152, 160, 6.0, 9.0), ("HEA 200", 190, 200, 6.5, 10.0), ("HEA 240", 230, 240, 7.5, 12.0), ("HEA 300", 290, 300, 8.5, 14.0),
            ("HEB 160", 160, 160, 8.0, 13.0), ("HEB 200", 200, 200, 9.0, 15.0), ("HEB 240", 240, 240, 10.0, 17.0), ("HEB 300", 300, 300, 11.0, 19.0),
            ("ISMB 200", 200, 100, 5.7, 10.8), ("ISMB 250", 250, 125, 6.9, 12.5), ("ISMB 300", 300, 140, 7.5, 12.4), ("ISMB 400", 400, 140, 8.9, 16.0),
            ("ISMB 450", 450, 150, 9.4, 17.4),
            ("ISHB 150", 150, 150, 5.4, 9.0), ("ISHB 200", 200, 200, 6.1, 9.0), ("ISHB 250", 250, 250, 6.9, 9.7), ("ISHB 300", 300, 250, 7.6, 10.6),
            ("ISHB 350", 350, 250, 8.3, 11.6), ("ISHB 400", 400, 250, 9.1, 12.7),
        ]
    }

    static func iSection(_ s: UnitSystem) -> FamilyDefinition {
        var f = column(s == .imperial ? "Steel Column - Wide Flange" : "Steel Column - I Section", .structuralColumn,
                       s == .imperial ? "Hot-rolled wide-flange (W) steel column." : "Hot-rolled I and H section steel column (IPE, HEA, HEB, ISMB, ISHB).",
                       [len("Depth", builtIn: true), len("Flange Width", builtIn: true), len("Web Thickness"), len("Flange Thickness")])
        f.solids = [extrusion("Section", iProfile())]
        f.types = types(s, ["Depth", "Flange Width", "Web Thickness", "Flange Thickness"], iSectionRows(s).map { ($0.0, [$0.1, $0.2, $0.3, $0.4]) })
        return f
    }

    /// Rectangular and square hollow sections: (name, width, depth, design wall thickness).
    public static func hollowRectangularRows(_ s: UnitSystem) -> [(String, Double, Double, Double)] {
        s == .imperial ? [
            ("HSS4x4x1/4", 4, 4, 0.233), ("HSS6x6x1/4", 6, 6, 0.233), ("HSS6x6x3/8", 6, 6, 0.349), ("HSS8x8x3/8", 8, 8, 0.349),
            ("HSS8x8x1/2", 8, 8, 0.465), ("HSS10x10x1/2", 10, 10, 0.465), ("HSS12x12x1/2", 12, 12, 0.465),
            ("HSS8x4x3/8", 4, 8, 0.349), ("HSS10x6x1/2", 6, 10, 0.465), ("HSS12x8x1/2", 8, 12, 0.465),
        ] : [
            ("SHS 100x100x5", 100, 100, 5), ("SHS 150x150x8", 150, 150, 8), ("SHS 200x200x10", 200, 200, 10), ("SHS 250x250x10", 250, 250, 10),
            ("SHS 300x300x12.5", 300, 300, 12.5), ("RHS 200x100x8", 100, 200, 8), ("RHS 250x150x10", 150, 250, 10), ("RHS 300x200x10", 200, 300, 10),
        ]
    }

    static func hollowRectangular(_ s: UnitSystem) -> FamilyDefinition {
        var f = column(s == .imperial ? "Steel Column - HSS Rectangular" : "Steel Column - Hollow Rectangular", .structuralColumn,
                       s == .imperial ? "Square and rectangular hollow structural section (HSS) column." : "Square and rectangular hollow section (SHS/RHS) column.",
                       [len("Width", builtIn: true), len("Depth", builtIn: true), len("Wall Thickness")])
        f.solids = [extrusion("Tube", rectProfile("Width", "Depth")),
                    extrusion("Hollow", rectProfile("Width - 2 * Wall Thickness", "Depth - 2 * Wall Thickness"), void: true, z0: "-0.01 m", z1: "Height + 0.01 m")]
        f.types = types(s, ["Width", "Depth", "Wall Thickness"], hollowRectangularRows(s).map { ($0.0, [$0.1, $0.2, $0.3]) })
        return f
    }

    /// Round hollow sections and pipe: (name, outside diameter, design wall thickness).
    public static func hollowRoundRows(_ s: UnitSystem) -> [(String, Double, Double)] {
        s == .imperial ? [
            ("Pipe 4 Std.", 4.5, 0.221), ("Pipe 5 Std.", 5.563, 0.241), ("Pipe 6 Std.", 6.625, 0.261), ("Pipe 6 X-Strong", 6.625, 0.403),
            ("Pipe 8 Std.", 8.625, 0.300), ("Pipe 10 Std.", 10.75, 0.340), ("Pipe 12 Std.", 12.75, 0.349),
        ] : [
            ("CHS 114.3x6.3", 114.3, 6.3), ("CHS 168.3x8", 168.3, 8), ("CHS 219.1x10", 219.1, 10), ("CHS 273x10", 273, 10), ("CHS 323.9x12.5", 323.9, 12.5),
        ]
    }

    static func hollowRound(_ s: UnitSystem) -> FamilyDefinition {
        var f = column(s == .imperial ? "Steel Column - Pipe" : "Steel Column - Hollow Circular", .structuralColumn,
                       s == .imperial ? "Round steel pipe column." : "Circular hollow section (CHS) column.",
                       [len("Outside Diameter", builtIn: true), len("Wall Thickness")])
        f.solids = [extrusion("Tube", .circle(center: FamilyPoint("0", "0"), radius: "Outside Diameter / 2")),
                    extrusion("Hollow", .circle(center: FamilyPoint("0", "0"), radius: "Outside Diameter / 2 - Wall Thickness"), void: true, z0: "-0.01 m", z1: "Height + 0.01 m")]
        f.types = types(s, ["Outside Diameter", "Wall Thickness"], hollowRoundRows(s).map { ($0.0, [$0.1, $0.2]) })
        return f
    }

    static func timber(_ s: UnitSystem, glulam: Bool) -> FamilyDefinition {
        let name = s == .imperial ? (glulam ? "Wood Column - Glulam" : "Wood Column - Sawn") : (glulam ? "Timber Column - Glulam" : "Timber Column - Sawn")
        var f = column(name, .structuralColumn, glulam ? "Glued-laminated timber column." : "Solid sawn timber post.",
                       [len("Width", builtIn: true), len("Depth", builtIn: true)])
        f.solids = [extrusion("Column", rectProfile("Width", "Depth"))]
        let rows: [(String, Double, Double)]
        if s == .imperial {
            rows = glulam ? [(inchName(5.125, 6), 5.125, 6), (inchName(6.75, 7.5), 6.75, 7.5), (inchName(6.75, 9), 6.75, 9), (inchName(8.75, 9), 8.75, 9),
                             (inchName(8.75, 10.5), 8.75, 10.5)]
                : [("4x4", 3.5, 3.5), ("4x6", 3.5, 5.5), ("6x6", 5.5, 5.5), ("6x8", 5.5, 7.5), ("8x8", 7.5, 7.5), ("10x10", 9.5, 9.5)]
        } else {
            rows = glulam ? [(mmName(140, 140), 140, 140), (mmName(160, 160), 160, 160), (mmName(200, 200), 200, 200), (mmName(240, 240), 240, 240),
                             (mmName(280, 280), 280, 280)]
                : [(mmName(100, 100), 100, 100), (mmName(150, 150), 150, 150), (mmName(150, 200), 150, 200), (mmName(200, 200), 200, 200), (mmName(250, 250), 250, 250)]
        }
        f.types = types(s, ["Width", "Depth"], rows.map { ($0.0, [$0.1, $0.2]) })
        return f
    }
}
