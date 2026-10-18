import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

// W4-FAMED: Family Editor model logic behind the window: renames that keep references, plane deletion and dragging,
// type management, canvas camera maths and hit-testing.

@Suite("Family editing (editor model logic)")
struct FamilyEditingTests {
    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

    /// A table: Width-labelled Left/Right with a centre plane held by EQ, Height-labelled Bottom/Top, a top form locked to
    /// the planes and a leg placed by a formula of Width.
    static func table() -> FamilyDefinition {
        var f = FamilyDefinition(name: "Table", template: .furniture)
        f.parameters = [FamilyParameter(name: "Width", type: .length), FamilyParameter(name: "Height", type: .length),
                        FamilyParameter(name: "Frame Width", type: .length), FamilyParameter(name: "Leg Inset", type: .length, formula: "Frame Width / 2"),
                        FamilyParameter(name: "Show Legs", type: .bool), FamilyParameter(name: "Mark", type: .text)]
        f.types = [FamilyTypeDefinition(name: "1200", values: ["Width": .double(1.2), "Height": .double(0.75), "Frame Width": .double(0.1), "Show Legs": .bool(true)]),
                   FamilyTypeDefinition(name: "1800", values: ["Width": .double(1.8), "Height": .double(0.75), "Frame Width": .double(0.12), "Show Legs": .bool(true)])]
        f.referencePlanes = [FamilyReferencePlane(name: "Left", axis: .x, offset: "-0.6"),
                             FamilyReferencePlane(name: "Center", axis: .x, offset: "0", strength: .centerLeftRight, definesOrigin: true),
                             FamilyReferencePlane(name: "Right", axis: .x, offset: "0.6"),
                             FamilyReferencePlane(name: "Front", axis: .y, offset: "-0.4"), FamilyReferencePlane(name: "Back", axis: .y, offset: "0.4"),
                             FamilyReferencePlane(name: "Bottom", axis: .z, offset: "0", definesOrigin: true),
                             FamilyReferencePlane(name: "Top", axis: .z, offset: "Height"),
                             FamilyReferencePlane(name: "Leg", axis: .x, offset: "Width / 2 - Leg Inset")]
        f.dimensions = [FamilyDimension(planeA: "Left", planeB: "Right", labelParameter: "Width"), .equality("Left", "Center", "Right"),
                        FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")]
        f.solids = [FamilySolid(name: "Top", profile: .rectangle(xMin: .plane("Left"), xMax: .plane("Right"), yMin: .plane("Front"), yMax: .plane("Back")),
                                zMin: .expr("Height - 30 mm"), zMax: .plane("Top")),
                    FamilySolid(name: "Leg", profile: .rectangle(xMin: .expr("Width / 2 - Leg Inset - 50 mm"), xMax: .plane("Leg"), yMin: .expr("-0.05"), yMax: .expr("0.05")),
                                zMin: .plane("Bottom"), zMax: .expr("Height - 30 mm"))]
        f.solids[1].visibilityParameter = "Show Legs"
        f.planLines = [FamilyLine(shape: .line(FamilyPoint(.plane("Left"), .expr("Width / 2")), FamilyPoint(.plane("Right"), .expr("0"))))]
        f.labels = [FamilyLabel(position: FamilyPoint("0", "0"), parameterName: "Mark")]
        return f
    }

    // MARK: Names and numbers

    @Test func numberTextIsShortAndRoundTrips() {
        #expect(FamilyEditing.numberText(0.45) == "0.45")
        #expect(FamilyEditing.numberText(-1.2) == "-1.2")
        #expect(FamilyEditing.numberText(0) == "0")
        #expect(FamilyEditing.numberText(-0.0000001) == "0")
        #expect(FamilyEditing.numberText(1.23456789) == "1.234568")
        #expect(FamilyEditing.number("0.45") == 0.45)
        #expect(FamilyEditing.number("Width / 2") == nil)
    }

    @Test func uniqueAndNumberedNames() {
        let taken: Set<String> = ["Plane 3", "Type 2", "Extrusion 1"]
        #expect(FamilyEditing.uniqueName("Type", taken: taken.contains) == "Type")
        #expect(FamilyEditing.uniqueName("Type 2", taken: taken.contains) == "Type 2 2")
        #expect(FamilyEditing.numberedName("Plane", count: 2, taken: taken.contains) == "Plane 4")
        #expect(FamilyEditing.numberedName("Extrusion", count: 0, taken: taken.contains) == "Extrusion 2")
        #expect(FamilyEditing.isValidName("Door Height"))
        #expect(!FamilyEditing.isValidName("2nd"))
        #expect(!FamilyEditing.isValidName("Width*2"))
    }

    @Test func formulaTokenReplacementRespectsBoundariesAndLongerNames() {
        let known = ["Width", "Frame Width", "Leg Inset"]
        #expect(FamilyEditing.replacingName(in: "Width / 2 - Leg Inset", "Width", with: "W", known: known) == "W / 2 - Leg Inset")
        #expect(FamilyEditing.replacingName(in: "Frame Width * 2 + Width", "Width", with: "W", known: known) == "Frame Width * 2 + W")
        #expect(FamilyEditing.replacingName(in: "Widths + Width2", "Width", with: "W", known: known) == "Widths + Width2")
        #expect(FamilyEditing.replacingName(in: "if(Width > 1 m, Width, 1 m)", "Width", with: "Length", known: known) == "if(Length > 1 m, Length, 1 m)")
        #expect(FamilyEditing.replacingName(in: "Frame Width / 2", "Frame Width", with: "Rail", known: known) == "Rail / 2")
    }

    // MARK: Parameter rename

    @Test func renameParameterUpdatesEveryReference() {
        var f = Self.table()
        #expect(FamilyEditing.renameParameter(&f, "Width", to: "Length"))
        #expect(f.parameter(named: "Width") == nil)
        #expect(f.types[0].values["Length"] == .double(1.2) && f.types[0].values["Width"] == nil)
        #expect(f.dimensions[0].labelParameter == "Length")
        #expect(f.referencePlanes.first { $0.name == "Leg" }?.offset == "Length / 2 - Leg Inset")
        #expect(f.parameter(named: "Frame Width") != nil, "a longer name containing the old one is untouched")
        if case .line(let a, _) = f.planLines[0].shape { #expect(a.y == .expr("Length / 2")) } else { Issue.record("line lost") }
        // The renamed family evaluates exactly as before.
        let before = FamilyEvaluator.evaluate(Self.table(), typeName: "1200"), after = FamilyEvaluator.evaluate(f, typeName: "1200")
        #expect(after.errors.isEmpty)
        #expect(Self.approx(before.planes["Leg"]!, after.planes["Leg"]!))
        #expect(Self.approx(before.planes["Right"]!, after.planes["Right"]!))
        #expect(FamilyEvaluator.flexTest(f).isEmpty)
        // Invalid or taken names are refused.
        #expect(!FamilyEditing.renameParameter(&f, "Length", to: "Height"))
        #expect(!FamilyEditing.renameParameter(&f, "Length", to: "1x"))
        #expect(!FamilyEditing.renameParameter(&f, "Nope", to: "X"))
    }

    @Test func renameParameterUpdatesVisibilityMaterialLabelAndBindings() {
        var f = Self.table()
        var nested = FamilyDefinition(name: "Knob", template: .genericModel)
        nested.parameters = [FamilyParameter(name: "Size", type: .length)]
        nested.types = [FamilyTypeDefinition(name: "S", values: ["Size": .double(0.02)])]
        f.nestedFamilies = [nested]
        var inst = NestedFamilyInstance(familyName: "Knob", bindings: ["Size": "Frame Width / 4"])
        inst.visibilityParameter = "Show Legs"
        f.nestedInstances = [inst]
        #expect(FamilyEditing.renameParameter(&f, "Show Legs", to: "Legs"))
        #expect(f.solids[1].visibilityParameter == "Legs")
        #expect(f.nestedInstances[0].visibilityParameter == "Legs")
        #expect(FamilyEditing.renameParameter(&f, "Frame Width", to: "Rail"))
        #expect(f.nestedInstances[0].bindings["Size"] == "Rail / 4")
        #expect(f.parameter(named: "Leg Inset")?.formula == "Rail / 2")
        #expect(FamilyEditing.renameParameter(&f, "Mark", to: "Tag Text"))
        #expect(f.labels[0].parameterName == "Tag Text")
    }

    @Test func deleteParameterClearsUsesButKeepsFormulasForFlexTest() {
        var f = Self.table()
        FamilyEditing.deleteParameter(&f, "Show Legs")
        #expect(f.solids[1].visibilityParameter == nil)
        #expect(f.types[0].values["Show Legs"] == nil)
        FamilyEditing.deleteParameter(&f, "Frame Width")
        #expect(f.parameter(named: "Leg Inset")?.formula == "Frame Width / 2")
        #expect(!FamilyEvaluator.flexTest(f).isEmpty, "the dangling formula is reported")
    }

    // MARK: Plane rename and delete

    @Test func renamePlaneUpdatesDimensionsAndLockedBounds() {
        var f = Self.table()
        #expect(FamilyEditing.renamePlane(&f, "Right", to: "East"))
        #expect(f.dimensions[0].planeB == "East" && f.dimensions[1].planeC == "East")
        if case .rectangle(_, let x1, _, _) = f.solids[0].profile { #expect(x1 == .plane("East")) } else { Issue.record("profile") }
        if case .line(_, let b) = f.planLines[0].shape { #expect(b.x == .plane("East")) } else { Issue.record("line") }
        let ev = FamilyEvaluator.evaluate(f, typeName: "1200")
        #expect(ev.errors.isEmpty)
        #expect(Self.approx(ev.planes["East"]!, 0.6))
        #expect(!FamilyEditing.renamePlane(&f, "East", to: "Left"), "taken")
        #expect(!FamilyEditing.renamePlane(&f, "East", to: ""), "blank")
    }

    @Test func deletePlaneBakesLockedBoundsAndDropsItsDimensions() {
        var f = Self.table()
        let positions = FamilyEvaluator.evaluate(f, typeName: "1200").planes
        let baked = FamilyEditing.deletePlane(&f, "Top", positions: positions)
        #expect(baked == 1)
        #expect(!f.referencePlanes.contains { $0.name == "Top" })
        #expect(f.dimensions.count == 2 && !f.dimensions.contains { $0.planeB == "Top" })
        #expect(f.solids[0].zMax == .expr("0.75"))
        let ev = FamilyEvaluator.evaluate(f, typeName: "1200")
        #expect(ev.errors.isEmpty)
        #expect(Self.approx(ev.solids[0].zMax, 0.75))
        // Origin planes can't be deleted.
        #expect(FamilyEditing.deletePlane(&f, "Center", positions: positions) == 0)
        #expect(f.referencePlanes.contains { $0.name == "Center" })
    }

    @Test func newPlaneNamingAndDimensionPairing() {
        let f = Self.table()
        let p = FamilyEditing.newPlane(f, axis: .y, at: 0.12345678)
        #expect(p.name == "Plane 9" && p.axis == .y && p.offset == "0.123457")
        #expect(FamilyEditing.dimension(f, between: "Front", and: "Back") != nil)
        #expect(FamilyEditing.dimension(f, between: "Front", and: "Top") == nil, "different axes")
        #expect(FamilyEditing.dimension(f, between: "Front", and: "Front") == nil)
    }

    // MARK: Dragging planes

    @Test func planeMoveChoosesParameterOffsetOrRefusal() {
        let f = Self.table()
        let positions = FamilyEvaluator.evaluate(f, typeName: "1200").planes
        // Right is driven by Width (labelled from Left): dragging it changes Width to the new distance.
        #expect(FamilyEditing.planeMove(f, plane: "Right", to: 0.9, positions: positions) == .parameter("Width", 1.5))
        #expect(FamilyEditing.planeMove(f, plane: "Top", to: 0.9, positions: positions) == .parameter("Height", 0.9))
        // Front has a numeric offset and no constraint: the offset is rewritten.
        #expect(FamilyEditing.planeMove(f, plane: "Front", to: -0.45, positions: positions) == .offset("-0.45"))
        // The origin, an EQ-held middle plane and a formula-placed plane refuse.
        if case .refused = FamilyEditing.planeMove(f, plane: "Center", to: 0.1, positions: positions) {} else { Issue.record("origin moved") }
        if case .refused = FamilyEditing.planeMove(f, plane: "Leg", to: 0.1, positions: positions) {} else { Issue.record("formula plane moved") }
        var g = f
        g.dimensions[0].labelParameter = nil; g.dimensions[0].isLocked = true
        if case .refused = FamilyEditing.planeMove(g, plane: "Right", to: 0.9, positions: positions) {} else { Issue.record("locked plane moved") }
        var eq = f
        eq.referencePlanes[1].definesOrigin = false
        eq.referencePlanes[0].definesOrigin = true
        if case .refused(let why) = FamilyEditing.planeMove(eq, plane: "Center", to: 0.1, positions: positions) { #expect(why.contains("EQ")) } else { Issue.record("EQ plane moved") }
    }

    // MARK: Types

    @Test func typeAddRenameDeleteKeepValuesAndRefuseBadNames() {
        var f = Self.table()
        #expect(FamilyEditing.addType(&f, named: "2400", copying: "1800"))
        #expect(f.type(named: "2400")?.values["Width"] == .double(1.8))
        #expect(!FamilyEditing.addType(&f, named: "2400"), "duplicate")
        #expect(!FamilyEditing.addType(&f, named: "  "), "blank")
        #expect(FamilyEditing.renameType(&f, "2400", to: "Long"))
        #expect(f.type(named: "Long") != nil && f.type(named: "2400") == nil)
        #expect(!FamilyEditing.renameType(&f, "Long", to: "1200"), "taken")
        #expect(FamilyEditing.deleteType(&f, "Long"))
        #expect(FamilyEditing.deleteType(&f, "1800"))
        #expect(!FamilyEditing.deleteType(&f, "1200"), "the last type stays")
        #expect(f.types.count == 1)
    }

    // MARK: Forms, lines, labels, delete

    @Test func sketchedExtrusionLinesAndLabels() {
        var f = Self.table()
        let s = FamilyEditing.newExtrusion(f, rect: Rect2(min: Vec2(-0.2, -0.1), max: Vec2(0.3, 0.15)), zMin: 0, zMax: 0.4, void: false)
        #expect(s.name == "Extrusion 3" && !s.isVoid)
        if case .rectangle(let x0, let x1, let y0, let y1) = s.profile { #expect(x0 == .expr("-0.2") && x1 == .expr("0.3") && y0 == .expr("-0.1") && y1 == .expr("0.15")) } else { Issue.record("profile") }
        f.solids.append(s)
        let v = FamilyEditing.newExtrusion(f, rect: Rect2(min: .zero, max: Vec2(0.1, 0.1)), zMin: 0, zMax: 0.1, void: true)
        #expect(v.name == "Void 4" && v.isVoid)
        let ev = FamilyEvaluator.evaluate(f, typeName: "1200")
        #expect(ev.errors.isEmpty)
        #expect(ev.solids.contains { $0.sourceID == s.id && Self.approx($0.zMax, 0.4) })
        let l = FamilyEditing.newLine(from: Vec2(0, 0), to: Vec2(0.5, 0.25))
        if case .line(let a, let b) = l.shape { #expect(a.x == .expr("0") && b.x == .expr("0.5") && b.y == .expr("0.25")) } else { Issue.record("line") }
        let lb = FamilyEditing.newLabel(at: Vec2(0.1, 0.2), parameter: nil, text: "Hello")
        #expect(lb.parameterName == nil && lb.staticText == "Hello")
        let copy = FamilyEditing.duplicate(f.solids[1])
        #expect(copy.name == "Leg Copy" && copy.id != f.solids[1].id && copy.visibilityParameter == "Show Legs")
    }

    @Test func deleteByItem() {
        var f = Self.table()
        let positions = FamilyEvaluator.evaluate(f, typeName: "1200").planes
        let solid = f.solids[1].id, line = f.planLines[0].id, label = f.labels[0].id, dim = f.dimensions[2].id
        #expect(FamilyEditing.delete(.solid(solid), from: &f, positions: positions) && f.solids.count == 1)
        #expect(FamilyEditing.delete(.line(line), from: &f, positions: positions) && f.planLines.isEmpty)
        #expect(FamilyEditing.delete(.label(label), from: &f, positions: positions) && f.labels.isEmpty)
        #expect(FamilyEditing.delete(.dimension(dim), from: &f, positions: positions) && f.dimensions.count == 2)
        #expect(FamilyEditing.delete(.plane("Front"), from: &f, positions: positions) && !f.referencePlanes.contains { $0.name == "Front" })
        #expect(!FamilyEditing.delete(.plane("Center"), from: &f, positions: positions), "origin")
        #expect(!FamilyEditing.delete(.solid("missing"), from: &f, positions: positions))
        var g = Self.table()
        g.parameters[0].isBuiltIn = true
        #expect(!FamilyEditing.delete(.parameter("Width"), from: &g, positions: positions), "built-in")
        #expect(FamilyEditing.delete(.parameter("Mark"), from: &g, positions: positions) && g.parameter(named: "Mark") == nil)
    }

    // MARK: Camera

    @Test func cameraRoundTripsZoomsAboutCursorAndFits() {
        let size = Vec2(800, 600)
        let cam = FamilyEditing.Camera(center: Vec2(1, 2), scale: 200)
        let p = Vec2(1.5, 2.25)
        let s = cam.toScreen(p, size: size)
        #expect(Self.approx(s.x, 500) && Self.approx(s.y, 250))
        let back = cam.toModel(s, size: size)
        #expect(Self.approx(back.x, p.x) && Self.approx(back.y, p.y))
        let zoomed = cam.zoomed(by: 2, at: s, size: size)
        #expect(Self.approx(zoomed.scale, 400))
        let under = zoomed.toModel(s, size: size)
        #expect(Self.approx(under.x, p.x) && Self.approx(under.y, p.y), "the point under the cursor stays put")
        let panned = cam.panned(by: Vec2(100, -50))
        #expect(Self.approx(panned.center.x, 0.5) && Self.approx(panned.center.y, 1.75))
        let fit = FamilyEditing.Camera.fitting(Rect2(min: Vec2(-1, -0.5), max: Vec2(1, 0.5)), size: size, inset: 50)
        #expect(Self.approx(fit.center.x, 0) && Self.approx(fit.center.y, 0))
        #expect(Self.approx(fit.scale, 350), "limited by the width: (800 - 100) / 2")
        let empty = FamilyEditing.Camera.fitting(.empty, size: size)
        #expect(empty.scale > 0 && empty.scale.isFinite)
        #expect(cam.zoomed(by: 1e9, at: s, size: size).scale == 200_000)
        #expect(cam.zoomed(by: 1e-9, at: s, size: size).scale == 5)
    }

    // MARK: Hit-testing

    @Test func hitTestingPlanesAndOutlines() {
        let planes = [FamilyEditing.PlaneLine(name: "Left", vertical: true, value: -0.6), .init(name: "Right", vertical: true, value: 0.6), .init(name: "Front", vertical: false, value: -0.4)]
        #expect(FamilyEditing.hitPlane(planes, at: Vec2(0.59, 0), tolerance: 0.02) == "Right")
        #expect(FamilyEditing.hitPlane(planes, at: Vec2(0.0, -0.39), tolerance: 0.02) == "Front")
        #expect(FamilyEditing.hitPlane(planes, at: Vec2(0.0, 0.0), tolerance: 0.02) == nil)
        #expect(FamilyEditing.hitPlane(planes, at: Vec2(-0.61, -0.395), tolerance: 0.02) == "Front", "the nearer plane wins")
        let big = [Vec2(-1, -1), Vec2(1, -1), Vec2(1, 1), Vec2(-1, 1)]
        let small = [Vec2(-0.2, -0.2), Vec2(0.2, -0.2), Vec2(0.2, 0.2), Vec2(-0.2, 0.2)]
        let outlines: [(item: FamilyEditing.Item, points: [Vec2], closed: Bool)] = [(.solid("big"), big, true), (.solid("small"), small, true), (.line("l"), [Vec2(2, 0), Vec2(3, 0)], false)]
        #expect(FamilyEditing.hitOutline(outlines, at: .zero, tolerance: 0.01) == .solid("small"), "the smaller containing outline wins")
        #expect(FamilyEditing.hitOutline(outlines, at: Vec2(0.8, 0.8), tolerance: 0.01) == .solid("big"))
        #expect(FamilyEditing.hitOutline(outlines, at: Vec2(2.5, 0.005), tolerance: 0.01) == .line("l"))
        #expect(FamilyEditing.hitOutline(outlines, at: Vec2(2.5, 0.5), tolerance: 0.01) == nil)
        #expect(Self.approx(FamilyEditing.distance(Vec2(0, 1), toPolyline: [Vec2(-1, 0), Vec2(1, 0)], closed: false), 1))
        #expect(Self.approx(FamilyEditing.distance(Vec2(2, 0), toPolyline: [Vec2(-1, 0), Vec2(1, 0)], closed: false), 1))
        #expect(Self.approx(FamilyEditing.distance(Vec2(0, -1), toPolyline: small, closed: true), 0.8))
    }

    @Test func evaluatedContentCarriesSourceIdentity() {
        let f = Self.table()
        let ev = FamilyEvaluator.evaluate(f, typeName: "1200")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        #expect(Set(ev.solids.compactMap(\.sourceID)) == Set(f.solids.map(\.id)))
        #expect(ev.planLines.first?.sourceID == f.planLines[0].id)
        #expect(ev.labels.first?.sourceID == f.labels[0].id)
        var hidden = f
        hidden.types[0].values["Show Legs"] = .bool(false)
        let ev2 = FamilyEvaluator.evaluate(hidden, typeName: "1200")
        #expect(ev2.solids.map(\.sourceID) == [f.solids[0].id], "a hidden form is absent, and identities stay correct")
    }
}
