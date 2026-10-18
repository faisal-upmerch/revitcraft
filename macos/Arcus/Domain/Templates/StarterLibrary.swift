import Foundation
import ArcusGeometry

/// Built-in Arcus family library (original content). Families are plain data built here.
public enum StarterLibrary {
    // MARK: Helpers

    static func p(_ name: String) -> FamilyBound { .plane(name) }
    static func x(_ s: String) -> FamilyBound { .expr(s) }
    static func len(_ name: String, _ isInstance: Bool = false, group: ParameterGroup = .dimensions, formula: String? = nil, builtIn: Bool = false) -> FamilyParameter {
        FamilyParameter(name: name, type: .length, isInstance: isInstance, group: group, formula: formula, isBuiltIn: builtIn)
    }
    static func mat(_ name: String) -> FamilyParameter {
        FamilyParameter(name: name, type: .elementRef(.materials), isInstance: false, group: .materials)
    }
    static func box(_ name: String, _ x0: FamilyBound, _ x1: FamilyBound, _ y0: FamilyBound, _ y1: FamilyBound, _ z0: FamilyBound, _ z1: FamilyBound,
                    material: String? = nil, sub: FamilySubcategory = .general, plan: Bool = true) -> FamilySolid {
        FamilySolid(name: name, profile: .rectangle(xMin: x0, xMax: x1, yMin: y0, yMax: y1), zMin: z0, zMax: z1,
                    materialParameter: material, subcategory: sub, visibleInPlan: plan)
    }
    static func line(_ a: (String, String), _ b: (String, String), _ sub: FamilySubcategory = .general, weight: Int = 1) -> FamilyLine {
        FamilyLine(shape: .line(FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)), subcategory: sub, weight: weight)
    }
    static func rectLines(_ x0: String, _ y0: String, _ x1: String, _ y1: String, _ sub: FamilySubcategory = .general, weight: Int = 1) -> [FamilyLine] {
        [line((x0, y0), (x1, y0), sub, weight: weight), line((x1, y0), (x1, y1), sub, weight: weight),
         line((x1, y1), (x0, y1), sub, weight: weight), line((x0, y1), (x0, y0), sub, weight: weight)]
    }
    static func planes(_ list: [(String, FamilyAxis, String, ReferenceStrength)]) -> [FamilyReferencePlane] {
        list.map { FamilyReferencePlane(name: $0.0, axis: $0.1, offset: $0.2, strength: $0.3, definesOrigin: $0.2 == "0") }
    }

    // MARK: Doors

    public static func singleDoor() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Door - Single Flush", template: .door)
        f.description = "Single-leaf flush door with timber frame."
        f.parameters = [
            len("Width", builtIn: true), len("Height", builtIn: true), len("Frame Width"), len("Frame Depth"), len("Panel Thickness"),
            len("Rough Width", formula: "Width + 2 * Frame Width"), len("Rough Height", formula: "Height + Frame Width"),
            mat("Frame Material"), mat("Panel Material"),
        ]
        f.types = [
            FamilyTypeDefinition(name: "900 x 2100", values: ["Width": .double(0.9), "Height": .double(2.1), "Frame Width": .double(0.05), "Frame Depth": .double(0.12), "Panel Thickness": .double(0.04)]),
            FamilyTypeDefinition(name: "820 x 2040", values: ["Width": .double(0.82), "Height": .double(2.04), "Frame Width": .double(0.05), "Frame Depth": .double(0.12), "Panel Thickness": .double(0.04)]),
            FamilyTypeDefinition(name: "1000 x 2100", values: ["Width": .double(1.0), "Height": .double(2.1), "Frame Width": .double(0.05), "Frame Depth": .double(0.12), "Panel Thickness": .double(0.04)]),
        ]
        f.referencePlanes = planes([("Center (Left/Right)", .x, "0", .centerLeftRight), ("Left", .x, "-Width / 2", .left), ("Right", .x, "Width / 2", .right),
                                    ("Center (Front/Back)", .y, "0", .centerFrontBack), ("Bottom", .z, "0", .bottom), ("Top", .z, "Height", .top)])
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
        f.solids = [
            box("Left Jamb", x("-Width / 2 - Frame Width"), p("Left"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Bottom"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Right Jamb", p("Right"), x("Width / 2 + Frame Width"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Bottom"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Head", p("Left"), p("Right"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Top"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Panel", p("Left"), p("Right"), x("-Panel Thickness / 2"), x("Panel Thickness / 2"), p("Bottom"), p("Top"), material: "Panel Material", sub: .panel, plan: false),
        ]
        f.planLines = rectLines("-Width / 2 - Frame Width", "-Frame Depth / 2", "-Width / 2", "Frame Depth / 2", .frame)
            + rectLines("Width / 2", "-Frame Depth / 2", "Width / 2 + Frame Width", "Frame Depth / 2", .frame)
            + rectLines("-Width / 2", "-Frame Depth / 2 - Width", "-Width / 2 + Panel Thickness", "-Frame Depth / 2", .panel)
            + [FamilyLine(shape: .arc(center: FamilyPoint("-Width / 2", "-Frame Depth / 2"), radius: "Width", startDegrees: "-90", sweepDegrees: "90"), subcategory: .swing)]
        f.opening = FamilyOpening(xMin: x("-Width / 2 - Frame Width"), xMax: x("Width / 2 + Frame Width"), zMin: p("Bottom"), zMax: x("Height + Frame Width"))
        return f
    }

    public static func doubleDoor() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Door - Double Flush", template: .door)
        f.description = "Double-leaf flush door."
        f.parameters = [len("Width", builtIn: true), len("Height", builtIn: true), len("Frame Width"), len("Frame Depth"), len("Panel Thickness"),
                        len("Leaf Width", formula: "Width / 2"), mat("Frame Material"), mat("Panel Material")]
        f.types = [
            FamilyTypeDefinition(name: "1800 x 2100", values: ["Width": .double(1.8), "Height": .double(2.1), "Frame Width": .double(0.05), "Frame Depth": .double(0.12), "Panel Thickness": .double(0.045)]),
            FamilyTypeDefinition(name: "1500 x 2100", values: ["Width": .double(1.5), "Height": .double(2.1), "Frame Width": .double(0.05), "Frame Depth": .double(0.12), "Panel Thickness": .double(0.045)]),
        ]
        f.referencePlanes = planes([("Center (Left/Right)", .x, "0", .centerLeftRight), ("Left", .x, "-Width / 2", .left), ("Right", .x, "Width / 2", .right),
                                    ("Bottom", .z, "0", .bottom), ("Top", .z, "Height", .top)])
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
        f.solids = [
            box("Left Jamb", x("-Width / 2 - Frame Width"), p("Left"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Bottom"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Right Jamb", p("Right"), x("Width / 2 + Frame Width"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Bottom"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Head", p("Left"), p("Right"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Top"), x("Height + Frame Width"), material: "Frame Material", sub: .frame),
            box("Left Leaf", p("Left"), x("-0.002"), x("-Panel Thickness / 2"), x("Panel Thickness / 2"), p("Bottom"), p("Top"), material: "Panel Material", sub: .panel, plan: false),
            box("Right Leaf", x("0.002"), p("Right"), x("-Panel Thickness / 2"), x("Panel Thickness / 2"), p("Bottom"), p("Top"), material: "Panel Material", sub: .panel, plan: false),
        ]
        f.planLines = rectLines("-Width / 2 - Frame Width", "-Frame Depth / 2", "-Width / 2", "Frame Depth / 2", .frame)
            + rectLines("Width / 2", "-Frame Depth / 2", "Width / 2 + Frame Width", "Frame Depth / 2", .frame)
            + [line(("-Width / 2", "-Frame Depth / 2"), ("-Width / 2", "-Frame Depth / 2 - Leaf Width"), .panel),
               line(("Width / 2", "-Frame Depth / 2"), ("Width / 2", "-Frame Depth / 2 - Leaf Width"), .panel),
               FamilyLine(shape: .arc(center: FamilyPoint("-Width / 2", "-Frame Depth / 2"), radius: "Leaf Width", startDegrees: "-90", sweepDegrees: "90"), subcategory: .swing),
               FamilyLine(shape: .arc(center: FamilyPoint("Width / 2", "-Frame Depth / 2"), radius: "Leaf Width", startDegrees: "180", sweepDegrees: "90"), subcategory: .swing)]
        f.opening = FamilyOpening(xMin: x("-Width / 2 - Frame Width"), xMax: x("Width / 2 + Frame Width"), zMin: p("Bottom"), zMax: x("Height + Frame Width"))
        return f
    }

    // MARK: Windows

    public static func casementWindow() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Window - Casement", template: .window)
        f.description = "Single casement window with aluminium frame."
        f.parameters = [len("Width", builtIn: true), len("Height", builtIn: true), len("Default Sill Height"), len("Frame Width"), len("Frame Depth"),
                        len("Glass Thickness"), len("Glass Area", formula: "(Width - 2 * Frame Width) * (Height - 2 * Frame Width) / 1 m"),
                        mat("Frame Material"), mat("Glass Material")]
        f.parameters[6].type = .length
        f.types = [
            FamilyTypeDefinition(name: "1200 x 1500", values: ["Width": .double(1.2), "Height": .double(1.5), "Default Sill Height": .double(0.9), "Frame Width": .double(0.06), "Frame Depth": .double(0.1), "Glass Thickness": .double(0.024)]),
            FamilyTypeDefinition(name: "600 x 1200", values: ["Width": .double(0.6), "Height": .double(1.2), "Default Sill Height": .double(0.9), "Frame Width": .double(0.06), "Frame Depth": .double(0.1), "Glass Thickness": .double(0.024)]),
            FamilyTypeDefinition(name: "1800 x 1500", values: ["Width": .double(1.8), "Height": .double(1.5), "Default Sill Height": .double(0.9), "Frame Width": .double(0.06), "Frame Depth": .double(0.1), "Glass Thickness": .double(0.024)]),
            FamilyTypeDefinition(name: "2400 x 2100 Glazed Wall", values: ["Width": .double(2.4), "Height": .double(2.1), "Default Sill Height": .double(0.3), "Frame Width": .double(0.07), "Frame Depth": .double(0.12), "Glass Thickness": .double(0.028)]),
        ]
        f.referencePlanes = planes([("Center (Left/Right)", .x, "0", .centerLeftRight), ("Left", .x, "-Width / 2", .left), ("Right", .x, "Width / 2", .right),
                                    ("Sill", .z, "0", .bottom), ("Head", .z, "Height", .top)])
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Sill", planeB: "Head", labelParameter: "Height")]
        f.solids = [
            box("Left Frame", p("Left"), x("-Width / 2 + Frame Width"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Sill"), p("Head"), material: "Frame Material", sub: .frame),
            box("Right Frame", x("Width / 2 - Frame Width"), p("Right"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Sill"), p("Head"), material: "Frame Material", sub: .frame),
            box("Sill Frame", x("-Width / 2 + Frame Width"), x("Width / 2 - Frame Width"), x("-Frame Depth / 2"), x("Frame Depth / 2"), p("Sill"), x("Frame Width"), material: "Frame Material", sub: .frame),
            box("Head Frame", x("-Width / 2 + Frame Width"), x("Width / 2 - Frame Width"), x("-Frame Depth / 2"), x("Frame Depth / 2"), x("Height - Frame Width"), p("Head"), material: "Frame Material", sub: .frame),
            box("Glass", x("-Width / 2 + Frame Width"), x("Width / 2 - Frame Width"), x("-Glass Thickness / 2"), x("Glass Thickness / 2"), x("Frame Width"), x("Height - Frame Width"), material: "Glass Material", sub: .glass, plan: false),
        ]
        f.planLines = rectLines("-Width / 2", "-Frame Depth / 2", "-Width / 2 + Frame Width", "Frame Depth / 2", .frame)
            + rectLines("Width / 2 - Frame Width", "-Frame Depth / 2", "Width / 2", "Frame Depth / 2", .frame)
            + [line(("-Width / 2 + Frame Width", "-Glass Thickness / 2"), ("Width / 2 - Frame Width", "-Glass Thickness / 2"), .glass),
               line(("-Width / 2 + Frame Width", "Glass Thickness / 2"), ("Width / 2 - Frame Width", "Glass Thickness / 2"), .glass)]
        f.opening = FamilyOpening(xMin: p("Left"), xMax: p("Right"), zMin: p("Sill"), zMax: p("Head"))
        return f
    }

    // MARK: Components

    static func furniture(_ name: String, template: FamilyTemplate, types: [(String, Double, Double, Double)], build: (inout FamilyDefinition) -> Void) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: template)
        f.parameters = [len("Width", builtIn: true), len("Depth", builtIn: true), len("Height", builtIn: true), mat("Material")]
        f.types = types.map { FamilyTypeDefinition(name: $0.0, values: ["Width": .double($0.1), "Depth": .double($0.2), "Height": .double($0.3)]) }
        f.referencePlanes = planes([("Left", .x, "-Width / 2", .left), ("Right", .x, "Width / 2", .right), ("Front", .y, "-Depth / 2", .front),
                                    ("Back", .y, "Depth / 2", .back), ("Bottom", .z, "0", .bottom), ("Top", .z, "Height", .top)])
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), FamilyDimension(planeA: "Front", planeB: "Back", labelParameter: "Depth")]
        build(&f)
        return f
    }

    public static func desk() -> FamilyDefinition {
        furniture("Desk", template: .furniture, types: [("1500 x 750", 1.5, 0.75, 0.74), ("1200 x 600", 1.2, 0.6, 0.74)]) { f in
            f.solids = [
                box("Top", p("Left"), p("Right"), p("Front"), p("Back"), x("Height - 0.03 m"), p("Top"), material: "Material"),
                box("Leg 1", p("Left"), x("-Width / 2 + 0.05 m"), p("Front"), x("-Depth / 2 + 0.05 m"), p("Bottom"), x("Height - 0.03 m"), material: "Material", plan: false),
                box("Leg 2", x("Width / 2 - 0.05 m"), p("Right"), p("Front"), x("-Depth / 2 + 0.05 m"), p("Bottom"), x("Height - 0.03 m"), material: "Material", plan: false),
                box("Leg 3", p("Left"), x("-Width / 2 + 0.05 m"), x("Depth / 2 - 0.05 m"), p("Back"), p("Bottom"), x("Height - 0.03 m"), material: "Material", plan: false),
                box("Leg 4", x("Width / 2 - 0.05 m"), p("Right"), x("Depth / 2 - 0.05 m"), p("Back"), p("Bottom"), x("Height - 0.03 m"), material: "Material", plan: false),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
        }
    }

    public static func chair() -> FamilyDefinition {
        furniture("Chair", template: .furniture, types: [("Task Chair", 0.5, 0.5, 0.85), ("Dining Chair", 0.45, 0.5, 0.82)]) { f in
            f.solids = [
                box("Seat", p("Left"), p("Right"), p("Front"), x("Depth / 2 - 0.05 m"), x("Height * 0.5"), x("Height * 0.5 + 0.04 m"), material: "Material"),
                box("Back", p("Left"), p("Right"), x("Depth / 2 - 0.05 m"), p("Back"), x("Height * 0.5"), p("Top"), material: "Material"),
                box("Base", x("-0.04"), x("0.04"), x("-0.04"), x("0.04"), p("Bottom"), x("Height * 0.5"), material: "Material", plan: false),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2 - 0.05 m") + rectLines("-Width / 2", "Depth / 2 - 0.05 m", "Width / 2", "Depth / 2")
        }
    }

    public static func table() -> FamilyDefinition {
        furniture("Table - Dining", template: .furniture, types: [("1800 x 900", 1.8, 0.9, 0.75), ("1200 x 800", 1.2, 0.8, 0.75)]) { f in
            f.solids = [
                box("Top", p("Left"), p("Right"), p("Front"), p("Back"), x("Height - 0.04 m"), p("Top"), material: "Material"),
                box("Leg 1", x("-Width / 2 + 0.05 m"), x("-Width / 2 + 0.12 m"), x("-Depth / 2 + 0.05 m"), x("-Depth / 2 + 0.12 m"), p("Bottom"), x("Height - 0.04 m"), material: "Material", plan: false),
                box("Leg 2", x("Width / 2 - 0.12 m"), x("Width / 2 - 0.05 m"), x("-Depth / 2 + 0.05 m"), x("-Depth / 2 + 0.12 m"), p("Bottom"), x("Height - 0.04 m"), material: "Material", plan: false),
                box("Leg 3", x("-Width / 2 + 0.05 m"), x("-Width / 2 + 0.12 m"), x("Depth / 2 - 0.12 m"), x("Depth / 2 - 0.05 m"), p("Bottom"), x("Height - 0.04 m"), material: "Material", plan: false),
                box("Leg 4", x("Width / 2 - 0.12 m"), x("Width / 2 - 0.05 m"), x("Depth / 2 - 0.12 m"), x("Depth / 2 - 0.05 m"), p("Bottom"), x("Height - 0.04 m"), material: "Material", plan: false),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
        }
    }

    public static func bed() -> FamilyDefinition {
        furniture("Bed", template: .furniture, types: [("Double 1600", 1.6, 2.1, 0.55), ("Single 900", 0.9, 2.0, 0.5)]) { f in
            f.solids = [
                box("Frame", p("Left"), p("Right"), p("Front"), p("Back"), x("0.1"), x("Height * 0.65"), material: "Material"),
                box("Mattress", x("-Width / 2 + 0.02 m"), x("Width / 2 - 0.02 m"), x("-Depth / 2 + 0.02 m"), x("Depth / 2 - 0.1 m"), x("Height * 0.65"), p("Top")),
                box("Headboard", p("Left"), p("Right"), x("Depth / 2 - 0.08 m"), p("Back"), p("Bottom"), x("1.0"), material: "Material"),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
                + rectLines("-Width / 2 + 0.1 m", "Depth / 2 - 0.55 m", "Width / 2 - 0.1 m", "Depth / 2 - 0.15 m")
                + [line(("-Width / 2", "Depth / 2 - 0.65 m"), ("Width / 2", "Depth / 2 - 0.65 m"))]
        }
    }

    public static func sofa() -> FamilyDefinition {
        furniture("Sofa", template: .furniture, types: [("3 Seat", 2.2, 0.9, 0.8), ("2 Seat", 1.6, 0.9, 0.8)]) { f in
            f.solids = [
                box("Base", p("Left"), p("Right"), p("Front"), p("Back"), x("0.1"), x("Height * 0.55"), material: "Material"),
                box("Back", p("Left"), p("Right"), x("Depth / 2 - 0.2 m"), p("Back"), x("Height * 0.55"), p("Top"), material: "Material"),
                box("Arm L", p("Left"), x("-Width / 2 + 0.18 m"), p("Front"), x("Depth / 2 - 0.2 m"), x("0.45"), x("0.62"), material: "Material"),
                box("Arm R", x("Width / 2 - 0.18 m"), p("Right"), p("Front"), x("Depth / 2 - 0.2 m"), x("0.45"), x("0.62"), material: "Material"),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
                + [line(("-Width / 2", "Depth / 2 - 0.2 m"), ("Width / 2", "Depth / 2 - 0.2 m")),
                   line(("-Width / 2 + 0.18 m", "-Depth / 2"), ("-Width / 2 + 0.18 m", "Depth / 2 - 0.2 m")),
                   line(("Width / 2 - 0.18 m", "-Depth / 2"), ("Width / 2 - 0.18 m", "Depth / 2 - 0.2 m"))]
        }
    }

    public static func baseCabinet() -> FamilyDefinition {
        furniture("Base Cabinet", template: .casework, types: [("600", 0.6, 0.6, 0.9), ("900", 0.9, 0.6, 0.9), ("Counter 2400", 2.4, 0.6, 0.9)]) { f in
            f.solids = [
                box("Toe Kick", p("Left"), p("Right"), x("-Depth / 2 + 0.07 m"), p("Back"), p("Bottom"), x("0.1"), material: "Material", plan: false),
                box("Carcass", p("Left"), p("Right"), x("-Depth / 2 + 0.02 m"), p("Back"), x("0.1"), x("Height - 0.04 m"), material: "Material"),
                box("Countertop", p("Left"), p("Right"), p("Front"), p("Back"), x("Height - 0.04 m"), p("Top")),
            ]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
                + [line(("-Width / 2", "-Depth / 2 + 0.02 m"), ("Width / 2", "-Depth / 2 + 0.02 m"))]
        }
    }

    public static func upperCabinet() -> FamilyDefinition {
        furniture("Upper Cabinet", template: .casework, types: [("600", 0.6, 0.35, 0.7), ("900", 0.9, 0.35, 0.7)]) { f in
            f.solids = [box("Carcass", p("Left"), p("Right"), p("Front"), p("Back"), x("1.45"), x("1.45 m + Height"), material: "Material")]
            var l = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2", .hidden)
            for i in l.indices { l[i].subcategory = .hidden }
            f.planLines = l + [line(("-Width / 2", "-Depth / 2"), ("Width / 2", "Depth / 2"), .hidden)]
        }
    }

    public static func toilet() -> FamilyDefinition {
        furniture("WC Pan", template: .plumbingFixture, types: [("Standard", 0.38, 0.7, 0.8)]) { f in
            f.solids = [
                box("Cistern", p("Left"), p("Right"), x("Depth / 2 - 0.18 m"), p("Back"), x("Height * 0.5"), p("Top"), material: "Material"),
                FamilySolid(name: "Bowl", profile: .circle(center: FamilyPoint("0", "-0.02"), radius: "Width / 2"), zMin: p("Bottom"), zMax: x("Height * 0.5"), materialParameter: "Material"),
            ]
            f.planLines = rectLines("-Width / 2", "Depth / 2 - 0.18 m", "Width / 2", "Depth / 2")
                + [FamilyLine(shape: .arc(center: FamilyPoint("0", "-0.02"), radius: "Width / 2", startDegrees: "0", sweepDegrees: "360"))]
        }
    }

    public static func basin() -> FamilyDefinition {
        furniture("Basin", template: .plumbingFixture, types: [("Vanity 600", 0.6, 0.45, 0.85)]) { f in
            f.solids = [box("Vanity", p("Left"), p("Right"), p("Front"), p("Back"), x("0.15"), p("Top"), material: "Material")]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
                + [FamilyLine(shape: .arc(center: FamilyPoint("0", "-0.02"), radius: "Width / 2 - 0.1 m", startDegrees: "0", sweepDegrees: "360"))]
        }
    }

    public static func bathtub() -> FamilyDefinition {
        furniture("Bath", template: .plumbingFixture, types: [("1700 x 750", 1.7, 0.75, 0.55)]) { f in
            f.solids = [box("Tub", p("Left"), p("Right"), p("Front"), p("Back"), p("Bottom"), p("Top"), material: "Material")]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2") + rectLines("-Width / 2 + 0.07 m", "-Depth / 2 + 0.07 m", "Width / 2 - 0.07 m", "Depth / 2 - 0.07 m")
        }
    }

    public static func genericBox() -> FamilyDefinition {
        furniture("Generic Box", template: .genericModel, types: [("1000 x 1000 x 1000", 1, 1, 1)]) { f in
            f.solids = [box("Box", p("Left"), p("Right"), p("Front"), p("Back"), p("Bottom"), p("Top"), material: "Material")]
            f.planLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2")
        }
    }

    // MARK: Annotation families

    public static func tagFamily(_ name: String, categories: [Category], label: String, shape: String, width: String = "0.009") -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: .tag)
        f.taggedCategories = categories
        f.types = [FamilyTypeDefinition(name: "Standard", values: [:])]
        let h = "0.0025"
        switch shape {
        case "circle":
            f.annotationLines = [FamilyLine(shape: .arc(center: FamilyPoint("0", "0"), radius: "0.0035", startDegrees: "0", sweepDegrees: "360"))]
            f.fills = [FamilyFill(points: (0..<24).map { i in FamilyPoint("0.0035 * cos(\(i * 15))", "0.0035 * sin(\(i * 15))") }, isMasking: true)]
        case "hexagon":
            let pts = (0..<6).map { i -> (String, String) in ("0.0045 * cos(\(i * 60))", "0.0032 * sin(\(i * 60))") }
            f.annotationLines = (0..<6).map { line(pts[$0], pts[($0 + 1) % 6]) }
            f.fills = [FamilyFill(points: pts.map { FamilyPoint($0.0, $0.1) }, isMasking: true)]
        case "triangle":
            let pts = [("-0.004", "-0.0025"), ("0.004", "-0.0025"), ("0", "0.0045")]
            f.annotationLines = (0..<3).map { line(pts[$0], pts[($0 + 1) % 3]) }
            f.fills = [FamilyFill(points: pts.map { FamilyPoint($0.0, $0.1) }, isMasking: true)]
        case "diamond":
            let pts = [("-0.0045", "0"), ("0", "-0.003"), ("0.0045", "0"), ("0", "0.003")]
            f.annotationLines = (0..<4).map { line(pts[$0], pts[($0 + 1) % 4]) }
            f.fills = [FamilyFill(points: pts.map { FamilyPoint($0.0, $0.1) }, isMasking: true)]
        default:
            f.annotationLines = rectLines("-\(width) / 2", "-0.002", "\(width) / 2", "0.002")
            f.fills = [FamilyFill(points: [FamilyPoint("-\(width) / 2", "-0.002"), FamilyPoint("\(width) / 2", "-0.002"), FamilyPoint("\(width) / 2", "0.002"), FamilyPoint("-\(width) / 2", "0.002")], isMasking: true)]
        }
        f.labels = [FamilyLabel(position: FamilyPoint("0", "0"), parameterName: label, height: Double(h)!, sample: "1")]
        return f
    }

    public static func roomTag() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Room Tag", template: .tag)
        f.taggedCategories = [.rooms]
        f.types = [FamilyTypeDefinition(name: "Name and Number", values: [:]), FamilyTypeDefinition(name: "Name, Number and Area", values: [:])]
        f.labels = [
            FamilyLabel(position: FamilyPoint("0", "0.0022"), parameterName: "Name", height: 0.0028, bold: true, sample: "ROOM"),
            FamilyLabel(position: FamilyPoint("0", "-0.0014"), parameterName: "Number", height: 0.0022, sample: "101"),
        ]
        f.annotationLines = rectLines("-0.0035", "-0.003", "0.0035", "0.0002")
        return f
    }

    public static func roomTagWithArea() -> FamilyDefinition {
        var f = roomTag()
        f.name = "Room Tag - Area"
        f.types = [FamilyTypeDefinition(name: "Name, Number and Area", values: [:])]
        f.labels.append(FamilyLabel(position: FamilyPoint("0", "-0.0048"), parameterName: "Area", height: 0.0018, sample: "20.00 m²"))
        return f
    }

    public static func titleBlock(_ name: String, width w: Double, height h: Double) -> FamilyDefinition {
        var f = FamilyDefinition(name: name, template: .titleBlock)
        f.types = [FamilyTypeDefinition(name: name, values: [:])]
        func n(_ v: Double) -> String { String(format: "%.4f", v) }
        let left = 0.02, m = 0.01
        let stripW = min(0.19, w * 0.22)
        let sx = w - m - stripW
        var lines = rectLines(n(left), n(m), n(w - m), n(h - m), weight: 5)
        lines += [line((n(sx), n(m)), (n(sx), n(h - m)), weight: 3)]
        // Strip rows from the bottom up.
        let rows: [(Double, String?, String, Double, Bool)] = [
            (0.045, "Sheet Number", "SHEET", 0.010, true),
            (0.032, "Sheet Name", "TITLE", 0.0045, true),
            (0.022, "Scale", "SCALE", 0.0028, false),
            (0.022, "Sheet Issue Date", "DATE", 0.0028, false),
            (0.022, "Drawn By", "DRAWN", 0.0028, false),
            (0.022, "Checked By", "CHECKED", 0.0028, false),
            (0.022, "Current Revision", "REVISION", 0.0028, false),
            (0.028, "Project Number", "PROJECT NO.", 0.0035, false),
            (0.036, "Project Name", "PROJECT", 0.0045, true),
            (0.028, "Client Name", "CLIENT", 0.0032, false),
        ]
        var y = m
        var labels: [FamilyLabel] = []
        for (rh, param, caption, textH, bold) in rows {
            let top = y + rh
            lines.append(line((n(sx), n(top)), (n(w - m), n(top)), weight: 2))
            labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.004), n(top - 0.004)), parameterName: nil, staticText: caption, height: 0.0016, alignment: .left))
            labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.006), n(y + rh * 0.42)), parameterName: param, height: textH, alignment: .left, bold: bold, sample: caption))
            y = top
        }
        // Revision schedule area and practice name at the top of the strip.
        labels.append(FamilyLabel(position: FamilyPoint(n(sx + 0.004), n(h - m - 0.02)), parameterName: "Revision Schedule", height: 0.0018))
        labels.append(FamilyLabel(position: FamilyPoint(n(sx + stripW / 2), n(h - m - 0.008)), parameterName: "Organization", height: 0.004, alignment: .center, bold: true))
        f.annotationLines = lines
        f.labels = labels
        f.parameters = [len("Sheet Width", true), len("Sheet Height", true)]
        return f
    }

    public static func northArrow() -> FamilyDefinition {
        var f = FamilyDefinition(name: "North Arrow", template: .genericAnnotation)
        f.types = [FamilyTypeDefinition(name: "Standard", values: [:])]
        f.annotationLines = [FamilyLine(shape: .arc(center: FamilyPoint("0", "0"), radius: "0.008", startDegrees: "0", sweepDegrees: "360"))]
        f.fills = [FamilyFill(points: [FamilyPoint("0", "0.01"), FamilyPoint("0.004", "-0.006"), FamilyPoint("0", "-0.003")], pattern: .solid)]
        f.annotationLines += [line(("0", "0.01"), ("-0.004", "-0.006")), line(("-0.004", "-0.006"), ("0", "-0.003"))]
        f.labels = [FamilyLabel(position: FamilyPoint("0", "0.0135"), parameterName: nil, staticText: "N", height: 0.0035, bold: true)]
        return f
    }

    public static func breakLine() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Break Line", template: .detailComponent)
        f.parameters = [len("Length", true)]
        f.types = [FamilyTypeDefinition(name: "Standard", values: ["Length": .double(1.0)])]
        f.fills = [FamilyFill(points: [FamilyPoint("-Length / 2", "0"), FamilyPoint("Length / 2", "0"), FamilyPoint("Length / 2", "0.3"), FamilyPoint("-Length / 2", "0.3")], isMasking: true)]
        f.annotationLines = [line(("-Length / 2", "0"), ("-0.05", "0")), line(("-0.05", "0"), ("-0.02", "0.08")), line(("-0.02", "0.08"), ("0.02", "-0.08")),
                             line(("0.02", "-0.08"), ("0.05", "0")), line(("0.05", "0"), ("Length / 2", "0"))]
        return f
    }

    public static func woodBlocking() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Wood Blocking", template: .detailComponent)
        f.parameters = [len("Width"), len("Depth")]
        f.types = [FamilyTypeDefinition(name: "45 x 90", values: ["Width": .double(0.045), "Depth": .double(0.09)]),
                   FamilyTypeDefinition(name: "45 x 140", values: ["Width": .double(0.045), "Depth": .double(0.14)])]
        f.annotationLines = rectLines("-Width / 2", "-Depth / 2", "Width / 2", "Depth / 2") + [line(("-Width / 2", "-Depth / 2"), ("Width / 2", "Depth / 2")), line(("-Width / 2", "Depth / 2"), ("Width / 2", "-Depth / 2"))]
        return f
    }

    public static func handrailProfile() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Handrail - Rectangular", template: .profile)
        f.parameters = [len("Width"), len("Height")]
        f.types = [FamilyTypeDefinition(name: "50 x 50", values: ["Width": .double(0.05), "Height": .double(0.05)])]
        f.profileLoop = [FamilyPoint("-Width / 2", "-Height / 2"), FamilyPoint("Width / 2", "-Height / 2"), FamilyPoint("Width / 2", "Height / 2"), FamilyPoint("-Width / 2", "Height / 2")]
        return f
    }

    /// Every built-in family.
    public static var all: [FamilyDefinition] {
        [singleDoor(), doubleDoor(), casementWindow(), desk(), chair(), table(), bed(), sofa(), baseCabinet(), upperCabinet(), toilet(), basin(), bathtub(), genericBox(),
         tagFamily("Door Tag", categories: [.doors], label: "Mark", shape: "rect"),
         tagFamily("Window Tag", categories: [.windows], label: "Type Mark", shape: "hexagon"),
         tagFamily("Wall Tag", categories: [.walls], label: "Type Mark", shape: "diamond"),
         tagFamily("Revision Tag", categories: [.revisionClouds], label: "Revision Number", shape: "triangle"),
         tagFamily("Generic Mark Tag", categories: [.furniture, .casework, .genericModels, .plumbingFixtures, .columns, .structuralColumns, .structuralFraming, .floors, .ceilings, .roofs, .stairs, .railings], label: "Mark", shape: "circle"),
         roomTag(), roomTagWithArea(),
         titleBlock("A1 Title Block", width: 0.841, height: 0.594), titleBlock("A3 Title Block", width: 0.42, height: 0.297),
         titleBlock("ARCH D Title Block", width: 0.9144, height: 0.6096),
         northArrow(), breakLine(), woodBlocking(), handrailProfile()]
    }
}
