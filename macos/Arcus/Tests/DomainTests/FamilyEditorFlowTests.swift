import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// End-to-end Family Editor workflow (ARCUS-088): New Family from a category template, reference planes, labeled
/// dimensions, type/instance/formula parameters, types, forms, flex, Load into Project, placement and reload.
///
/// Each step goes through the same Domain calls the editor panes make (`FamilyEditorModel.edit` mutates the
/// `FamilyDefinition`; the preview and Flex Test call `FamilyEvaluator`; Load into Project calls `FamilyProjectLoader`).
@Suite("Family editor flow")
struct FamilyEditorFlowTests {
    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-9) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    // MARK: Editor actions (mirrors of the pane code, which lives in the app target)

    /// Manage ▸ New Family… for a template seeded from the Generic Box starter (`FamilyTemplates.make`).
    static func newFamily(_ template: FamilyTemplate, name: String) -> FamilyDefinition {
        var f = StarterLibrary.genericBox()
        f.template = template
        f.types = [f.types.first ?? FamilyTypeDefinition(name: "Type 1", values: [:])]
        f.addTemplateOriginConstraints()
        f.name = name
        return f
    }

    /// Planes & Dimensions ▸ Add Dimension, then Label ▸ Add Parameter… (`FamilyConstraintsPane.createLabelParameter`):
    /// a type length parameter holding each type's current distance, driving the dimension.
    static func labelWithNewParameter(_ f: inout FamilyDefinition, _ a: String, _ b: String, _ name: String) {
        f.dimensions.append(FamilyDimension(planeA: a, planeB: b))
        var distances: [String: Double] = [:]
        for t in f.types {
            let ev = FamilyEvaluator.evaluate(f, typeName: t.name)
            if let pa = ev.planes[a], let pb = ev.planes[b] { distances[t.name] = abs(pb - pa) }
        }
        let planes = FamilyEvaluator.evaluate(f, typeName: f.types[0].name).planes
        f.parameters.append(FamilyParameter(name: name, type: .length))
        for i in f.types.indices { f.types[i].values[name] = .double(distances[f.types[i].name] ?? 0) }
        let i = f.dimensions.count - 1, before = f.dimensions[i]
        f.dimensions[i].labelParameter = name
        f.dimensions[i].fixLabelDirection(planes, after: before)
    }

    /// Planes & Dimensions ▸ Add Dimension, then Label ▸ an existing parameter (`FamilyEditorModel.updateDimension`).
    static func labelDimension(_ f: inout FamilyDefinition, _ a: String, _ b: String, _ name: String) {
        let planes = FamilyEvaluator.evaluate(f, typeName: f.types[0].name).planes
        var d = FamilyDimension(planeA: a, planeB: b)
        let before = d
        d.labelParameter = name
        d.fixLabelDirection(planes, after: before)
        f.dimensions.append(d)
    }

    static func setValue(_ f: inout FamilyDefinition, type: String, _ values: [String: ParamValue]) {
        guard let i = f.types.firstIndex(where: { $0.name == type }) else { return }
        for (k, v) in values { f.types[i].values[k] = v }
    }

    /// Family Types ▸ Duplicate (copies the current type's values under a new name).
    static func duplicateType(_ f: inout FamilyDefinition, _ from: String, as name: String) {
        f.types.append(FamilyTypeDefinition(name: name, values: f.type(named: from)?.values ?? [:]))
    }

    static func rect(_ name: String, _ x0: FamilyBound, _ x1: FamilyBound, _ y0: FamilyBound, _ y1: FamilyBound,
                     _ z0: FamilyBound, _ z1: FamilyBound) -> FamilySolid {
        FamilySolid(name: name, profile: .rectangle(xMin: x0, xMax: x1, yMin: y0, yMax: y1), zMin: z0, zMax: z1, materialParameter: "Material")
    }

    /// A side table authored step by step in the editor: a top locked to planes, two legs sized by a labeled
    /// "Leg Size" dimension and a "Leg Height" formula, an instance-positioned shelf switched by a Yes/No parameter.
    static func sideTable() -> FamilyDefinition {
        var f = newFamily(.furniture, name: "Side Table")
        // Types pane: rename the seeded type and set its size.
        f.types[0].name = "600 x 600"
        setValue(&f, type: "600 x 600", ["Width": .double(0.6), "Depth": .double(0.6), "Height": .double(0.5)])
        // Forms pane: drop the template box.
        f.solids.removeAll { $0.name == "Box" }
        // Planes & Dimensions: an underside plane held below Top by a new "Top Thickness" label.
        f.referencePlanes.append(FamilyReferencePlane(name: "Underside", axis: .z, offset: "0.45"))
        labelWithNewParameter(&f, "Underside", "Top", "Top Thickness")
        setValue(&f, type: "600 x 600", ["Top Thickness": .double(0.03)])
        // Leg planes inside Left and Right, both labeled with one "Leg Size" parameter.
        f.referencePlanes.append(FamilyReferencePlane(name: "Leg L", axis: .x, offset: "-0.25"))
        f.referencePlanes.append(FamilyReferencePlane(name: "Leg R", axis: .x, offset: "0.25"))
        labelWithNewParameter(&f, "Left", "Leg L", "Leg Size")
        labelDimension(&f, "Leg R", "Right", "Leg Size")
        // Parameters: formulas (length and area with units) and instance parameters.
        f.parameters.append(FamilyParameter(name: "Leg Height", type: .length, formula: "Height - Top Thickness"))
        f.parameters.append(FamilyParameter(name: "Top Area", type: .area, group: .dimensions, formula: "Width * Depth"))
        f.parameters.append(FamilyParameter(name: "Shelf Height", type: .length, isInstance: true))
        f.parameters.append(FamilyParameter(name: "Show Shelf", type: .bool, isInstance: true, group: .graphics))
        setValue(&f, type: "600 x 600", ["Shelf Height": .double(0.15), "Show Shelf": .bool(true)])
        // Forms.
        f.solids = [
            rect("Top", .plane("Left"), .plane("Right"), .plane("Front"), .plane("Back"), .plane("Underside"), .plane("Top")),
            rect("Leg 1", .plane("Left"), .plane("Leg L"), .plane("Front"), .expr("-Depth / 2 + Leg Size"), .plane("Bottom"), .expr("Leg Height")),
            rect("Leg 2", .plane("Leg R"), .plane("Right"), .expr("Depth / 2 - Leg Size"), .plane("Back"), .plane("Bottom"), .plane("Underside")),
            {
                var s = rect("Shelf", .plane("Leg L"), .plane("Leg R"), .plane("Front"), .plane("Back"), .expr("Shelf Height"), .expr("Shelf Height + 20 mm"))
                s.visibilityParameter = "Show Shelf"
                return s
            }(),
        ]
        // More types.
        duplicateType(&f, "600 x 600", as: "1200 x 600")
        setValue(&f, type: "1200 x 600", ["Width": .double(1.2)])
        duplicateType(&f, "600 x 600", as: "Tall 600")
        setValue(&f, type: "Tall 600", ["Height": .double(0.75), "Top Thickness": .double(0.04), "Leg Size": .double(0.06)])
        return f
    }

    static func solid(_ e: EvaluatedFamily, _ name: String) -> EvaluatedFamily.Solid? { e.solids.first { $0.name == name } }

    // MARK: Authoring

    @Test func newFamilyTemplateStartsFlexCleanWithAnchoredOrigin() throws {
        let f = Self.newFamily(.furniture, name: "Side Table")
        #expect(f.template.category == .furniture)
        #expect(f.types.count == 1)
        #expect(Set(f.referencePlanes.map(\.name)).isSuperset(of: ["Left", "Right", "Front", "Back", "Bottom", "Top"]))
        #expect(f.referencePlanes.filter(\.definesOrigin).map(\.axis).sorted { $0.rawValue < $1.rawValue } == [.x, .y, .z])
        #expect(FamilyEvaluator.flexTest(f) == [])
        // Applying the template constraints twice changes nothing.
        var again = f
        again.addTemplateOriginConstraints()
        #expect(again == f)
    }

    /// The starters New Family seeds 3D templates from keep their geometry and flex cleanly once anchored.
    @Test func templateAnchoringLeavesEveryStarterUnchanged() throws {
        for starter in [StarterLibrary.genericBox(), StarterLibrary.singleDoor(), StarterLibrary.casementWindow(),
                        StarterLibrary.baseCabinet(), StarterLibrary.basin()] {
            var anchored = starter
            anchored.addTemplateOriginConstraints()
            #expect(FamilyEvaluator.flexTest(anchored) == [], "\(starter.name)")
            for t in starter.types {
                let a = FamilyEvaluator.evaluate(starter, typeName: t.name), b = FamilyEvaluator.evaluate(anchored, typeName: t.name)
                #expect(a.bounds.min.distance(to: b.bounds.min) < 1e-9 && a.bounds.max.distance(to: b.bounds.max) < 1e-9, "\(starter.name) \(t.name)")
                for (name, v) in a.planes { #expect(Self.approx(b.planes[name], v), "\(starter.name) \(name)") }
            }
        }
    }

    /// Without an origin plane on X, the solver's closest-to-sketch solution shifted every plane when a new labeled
    /// dimension disagreed with its sketch, moving the family off its insertion point.
    @Test func labelingANewPlaneKeepsTheFamilyOnItsInsertionPoint() throws {
        var bare = StarterLibrary.genericBox()
        bare.referencePlanes.append(FamilyReferencePlane(name: "Leg L", axis: .x, offset: "-0.4"))
        bare.parameters.append(FamilyParameter(name: "Leg Size", type: .length))
        bare.types[0].values["Leg Size"] = .double(0.05)
        bare.dimensions.append(FamilyDimension(planeA: "Left", planeB: "Leg L", labelParameter: "Leg Size"))
        let drift = FamilyEvaluator.evaluate(bare, typeName: bare.types[0].name)
        #expect(!Self.approx(drift.planes["Left"], -0.5), "reproduces the unanchored template")

        var anchored = bare
        anchored.addTemplateOriginConstraints()
        let e = FamilyEvaluator.evaluate(anchored, typeName: anchored.types[0].name)
        #expect(e.errors.isEmpty)
        #expect(Self.approx(e.planes["Left"], -0.5) && Self.approx(e.planes["Right"], 0.5))
        #expect(Self.approx(e.planes["Leg L"], -0.45))
        #expect(Self.approx(e.planes["Center (Left/Right)"], 0))
        // A Top-relative dimension no longer lifts Top off Height.
        anchored.referencePlanes.append(FamilyReferencePlane(name: "Underside", axis: .z, offset: "0.9"))
        anchored.dimensions.append(FamilyDimension(planeA: "Underside", planeB: "Top", labelParameter: "Leg Size"))
        let z = FamilyEvaluator.evaluate(anchored, typeName: anchored.types[0].name)
        #expect(Self.approx(z.planes["Top"], 1) && Self.approx(z.planes["Underside"], 0.95))
    }

    /// A label's side is fixed when it is applied. Before, it was re-read from the sketched offsets on every evaluation,
    /// so flexing Top below Underside's numeric sketch (Height 50%) flipped Underside above Top and collapsed the top.
    @Test func labeledDimensionsKeepTheirSideWhenFlexed() throws {
        let f = Self.sideTable()
        let added = f.dimensions.filter { ["Top Thickness", "Leg Size"].contains($0.labelParameter ?? "") }
        #expect(added.count == 3 && added.allSatisfy { $0.direction == 1 })
        let low = FamilyEvaluator.evaluate(Self.flexed(f, "600 x 600", ["Height": .double(0.25), "Width": .double(0.3)]), typeName: "600 x 600")
        #expect(low.errors.isEmpty)
        #expect(Self.approx(low.planes["Underside"], 0.22) && Self.approx(low.planes["Top"], 0.25))
        #expect(Self.approx(low.planes["Leg L"], -0.1) && Self.approx(low.planes["Leg R"], 0.1))

        // Families written without a direction keep the sketch-derived side (and the flip the flex test reports).
        var legacy = f
        for i in legacy.dimensions.indices { legacy.dimensions[i].direction = nil }
        let old = FamilyEvaluator.evaluate(Self.flexed(legacy, "600 x 600", ["Height": .double(0.25)]), typeName: "600 x 600")
        #expect(Self.approx(old.planes["Underside"], 0.28))
        #expect(old.errors.contains { $0.contains("“Top” has zero or negative height") })

        // The direction round-trips and is omitted when unset, so older readers see an unchanged dimension.
        let json = try JSONEncoder().encode(f)
        #expect(try JSONDecoder().decode(FamilyDefinition.self, from: json) == f)
        let plain = try JSONEncoder().encode(FamilyDimension(planeA: "A", planeB: "B", labelParameter: "W"))
        #expect(!String(decoding: plain, as: UTF8.self).contains("direction"))
    }

    static func flexed(_ f: FamilyDefinition, _ type: String, _ values: [String: ParamValue]) -> FamilyDefinition {
        var g = f
        setValue(&g, type: type, values)
        return g
    }

    @Test func authoredFamilyFlexesEveryType() throws {
        let f = Self.sideTable()
        #expect(f.types.map(\.name) == ["600 x 600", "1200 x 600", "Tall 600"])
        #expect(f.parameter(named: "Top Thickness")?.isInstance == false)
        #expect(f.parameter(named: "Shelf Height")?.isInstance == true)
        let cases: [(String, w: Double, d: Double, h: Double, tt: Double, leg: Double)] = [
            ("600 x 600", 0.6, 0.6, 0.5, 0.03, 0.05), ("1200 x 600", 1.2, 0.6, 0.5, 0.03, 0.05), ("Tall 600", 0.6, 0.6, 0.75, 0.04, 0.06),
        ]
        for c in cases {
            let e = FamilyEvaluator.evaluate(f, typeName: c.0)
            #expect(e.errors.isEmpty, "\(c.0): \(e.errors)")
            #expect(e.warnings.isEmpty)
            let b = e.bounds
            #expect(Self.approx(b.min.x, -c.w / 2) && Self.approx(b.max.x, c.w / 2), "\(c.0) width")
            #expect(Self.approx(b.min.y, -c.d / 2) && Self.approx(b.max.y, c.d / 2), "\(c.0) depth")
            #expect(Self.approx(b.min.z, 0) && Self.approx(b.max.z, c.h), "\(c.0) height")
            #expect(Self.approx(e.planes["Underside"], c.h - c.tt))
            #expect(Self.approx(e.planes["Leg L"], -c.w / 2 + c.leg) && Self.approx(e.planes["Leg R"], c.w / 2 - c.leg))
            #expect(Self.approx(e.length("Leg Height"), c.h - c.tt))
            #expect(Self.approx(e.length("Top Area"), c.w * c.d))
            let top = try #require(Self.solid(e, "Top"))
            #expect(Self.approx(top.zMin, c.h - c.tt) && Self.approx(top.zMax, c.h))
            let leg = try #require(Self.solid(e, "Leg 1"))
            #expect(Self.approx(leg.profile.bounds.width, c.leg) && Self.approx(leg.profile.bounds.height, c.leg))
            #expect(Self.approx(leg.zMax, c.h - c.tt))
            let shelf = try #require(Self.solid(e, "Shelf"))
            #expect(Self.approx(shelf.zMin, 0.15) && Self.approx(shelf.zMax, 0.17))
            #expect(Self.approx(shelf.profile.bounds.width, c.w - 2 * c.leg))
        }
        let flex = FamilyEvaluator.flexTest(f)
        #expect(flex == [], "\(flex)")
        // Instance values override the type's defaults; the Yes/No parameter hides the shelf.
        let raised = FamilyEvaluator.evaluate(f, typeName: "600 x 600", instance: ["Shelf Height": .double(0.3)])
        #expect(Self.approx(Self.solid(raised, "Shelf")?.zMin, 0.3))
        let hidden = FamilyEvaluator.evaluate(f, typeName: "600 x 600", instance: ["Show Shelf": .bool(false)])
        #expect(Self.solid(hidden, "Shelf") == nil && hidden.solids.count == 3)
        // A type value for an instance parameter is only its default: instance overrides of type parameters are ignored.
        let ignored = FamilyEvaluator.evaluate(f, typeName: "600 x 600", instance: ["Width": .double(2)])
        #expect(Self.approx(ignored.bounds.max.x, 0.3))
    }

    @Test func flexTestGatesBrokenFamilies() throws {
        // Circular formulas.
        var cyc = Self.sideTable()
        cyc.parameters.append(FamilyParameter(name: "A", type: .length, formula: "B + 1 mm"))
        cyc.parameters.append(FamilyParameter(name: "B", type: .length, formula: "A"))
        #expect(FamilyEvaluator.flexTest(cyc).contains { $0.hasPrefix("Circular formula chain") })
        // Unit mismatch in a formula.
        var unit = Self.sideTable()
        unit.parameters.append(FamilyParameter(name: "Bad", type: .length, formula: "Width * Depth"))
        #expect(!FamilyEvaluator.evaluate(unit, typeName: "600 x 600").errors.isEmpty)
        // Deleting a parameter (Types pane ▸ trash) leaves formulas and expressions that used it failing the flex test.
        var deleted = Self.sideTable()
        deleted.parameters.removeAll { $0.name == "Top Thickness" }
        for i in deleted.types.indices { deleted.types[i].values.removeValue(forKey: "Top Thickness") }
        for i in deleted.dimensions.indices where deleted.dimensions[i].labelParameter == "Top Thickness" { deleted.dimensions[i].labelParameter = nil }
        #expect(FamilyEvaluator.flexTest(deleted).contains { $0.contains("Leg Height") })
        // Deleting a plane (Planes & Dimensions ▸ trash) leaves forms locked to it reported.
        var noPlane = Self.sideTable()
        noPlane.referencePlanes.removeAll { $0.name == "Underside" }
        noPlane.dimensions.removeAll { [$0.planeA, $0.planeB, $0.planeC].contains("Underside") }
        #expect(FamilyEvaluator.flexTest(noPlane).contains { $0.contains("Reference plane “Underside” does not exist") })
        // Legs that meet in the middle when flexed to 150% leave the shelf with no width.
        var tight = Self.sideTable()
        Self.setValue(&tight, type: "600 x 600", ["Leg Size": .double(0.2)])
        let tightFlex = FamilyEvaluator.flexTest(tight)
        #expect(tightFlex == ["Flexing “Leg Size” to 150% in type “600 x 600”: Solid “Shelf” has zero width or depth for this type."], "\(tightFlex)")
    }

    // MARK: Load into Project

    static func placeInstance(_ m: inout BIMModel, _ ids: ProjectTemplates.Ids, family: FamilyDefinition, type: String,
                              at p: Vec2, rotation: Double = 0) throws -> (family: ElementID, type: ElementID, instance: ElementID) {
        var fid = ElementID(0), tid = ElementID(0), inst = ElementID(0)
        try Fx.commit(&m) { tx in
            fid = FamilyProjectLoader.load(family, replacing: tx.model.family(named: family.name)?.id, in: tx)
            tid = try #require(tx.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == type }?.id)
            inst = tx.create(.furniture, data: .component(ComponentData(location: p, rotation: rotation)), typeID: tid, levelID: ids.levels[0])
        }
        return (fid, tid, inst)
    }

    static func worldBounds(_ id: ElementID, _ m: BIMModel) -> Box3 {
        guard let e = m[id] else { return .empty }
        return ComponentGeometry.meshParts(e, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }

    @Test func loadIntoProjectCreatesTypesAndPlacedInstancesFollowParameters() throws {
        var (m, ids) = Fx.template()
        let fam = Self.sideTable()
        let (fid, tid, inst) = try Self.placeInstance(&m, ids, family: fam, type: "1200 x 600", at: Vec2(5, 2))
        #expect(m[fid]?.family == fam)
        let types = m.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        #expect(Set(types.map(\.name)) == ["600 x 600", "1200 x 600", "Tall 600"])
        #expect(types.allSatisfy { $0.typeData?.instanceCategory == .furniture && $0.typeData?.familyName == "Side Table" })
        #expect(m[tid]?.typeData?.params[Parameters.familyParamID("Width")] == .double(1.2))

        let z0 = m.elevation(ofLevel: ids.levels[0])
        let b = Self.worldBounds(inst, m)
        #expect(Self.approx(b.min.x, 4.4) && Self.approx(b.max.x, 5.6))
        #expect(Self.approx(b.min.y, 1.7) && Self.approx(b.max.y, 2.3))
        #expect(Self.approx(b.min.z, z0) && Self.approx(b.max.z, z0 + 0.5))
        #expect(ComponentGeometry.meshParts(m[inst]!, m).count == 4)

        // Properties: instance parameters on the instance, type parameters (formulas read-only) on the type.
        let instanceNames = Set(Parameters.instanceEntries(m[inst]!, m).map(\.name))
        #expect(instanceNames.isSuperset(of: ["Shelf Height", "Show Shelf"]) && !instanceNames.contains("Width"))
        let legHeight = try #require(Parameters.typeEntries(m[tid]!, m).first { $0.name == "Leg Height" })
        #expect(legHeight.isReadOnly && Self.approx(legHeight.value?.doubleValue, 0.47))

        // Instance edits move and hide the shelf; a project type edit flexes every instance of the type.
        try Fx.commit(&m) { tx in
            try Parameters.set(Parameters.familyParamID("Shelf Height"), to: .double(0.3), on: inst, in: tx)
            try Parameters.set(Parameters.familyParamID("Height"), to: .double(0.7), on: tid, in: tx)
        }
        let parts = ComponentGeometry.meshParts(m[inst]!, m)
        #expect(parts.contains { Self.approx($0.mesh.bounds.min.z, z0 + 0.3) })
        #expect(Self.approx(Self.worldBounds(inst, m).max.z, z0 + 0.7))
        // The type's formula values follow the project's type values, not the values stored in the family file.
        let legAfter = try #require(Parameters.typeEntries(m[tid]!, m).first { $0.name == "Leg Height" })
        #expect(Self.approx(legAfter.value?.doubleValue, 0.67))
        #expect(Self.approx(Parameters.value(Parameters.familyParamID("Leg Height"), of: m[inst]!, m)?.doubleValue, 0.67))
        #expect(Parameters.value(Parameters.familyParamID("Height"), of: m[tid]!, m) == .double(0.7))
        var scratch = m
        #expect(throws: ParameterError.self) {
            try Fx.commit(&scratch) { tx in try Parameters.set(Parameters.familyParamID("Leg Height"), to: .double(0.1), on: tid, in: tx) }
        }
        try Fx.commit(&m) { tx in try Parameters.set(Parameters.familyParamID("Show Shelf"), to: .bool(false), on: inst, in: tx) }
        #expect(ComponentGeometry.meshParts(m[inst]!, m).count == 3)

        // Rotated placement swaps the plan extents.
        let (_, _, turned) = try Self.placeInstance(&m, ids, family: fam, type: "1200 x 600", at: Vec2(0, 0), rotation: .pi / 2)
        let r = Self.worldBounds(turned, m)
        #expect(Self.approx(r.max.x - r.min.x, 0.6, 1e-6) && Self.approx(r.max.y - r.min.y, 1.2, 1e-6))
    }

    // MARK: Reload

    /// The family edited after loading: wider base type, a new type parameter driving a new apron form, and a new name.
    static func editedSideTable() -> FamilyDefinition {
        var f = sideTable()
        setValue(&f, type: "600 x 600", ["Width": .double(0.7)])
        f.parameters.append(FamilyParameter(name: "Apron Height", type: .length))
        for i in f.types.indices { f.types[i].values["Apron Height"] = .double(0.08) }
        f.solids.append(rect("Apron", .plane("Leg L"), .plane("Leg R"), .expr("-Depth / 2"), .expr("-Depth / 2 + 20 mm"),
                             .expr("Leg Height - Apron Height"), .plane("Underside")))
        f.types.append(FamilyTypeDefinition(name: "Low 600", values: f.types[0].values.merging(["Height": .double(0.4)]) { $1 }))
        f.name = "Side Table Mk2"
        return f
    }

    @Test func reloadingAnEditedFamilyUpdatesPlacedInstances() throws {
        var (base, ids) = Fx.template()
        let (fid, tid, inst) = try Self.placeInstance(&base, ids, family: Self.sideTable(), type: "600 x 600", at: Vec2(0, 0))
        let edited = Self.editedSideTable()
        let apron = Parameters.familyParamID("Apron Height")

        // Keep Project Values: the existing type keeps Width 0.6, but new forms, parameters and types arrive.
        var keep = base
        try Fx.commit(&keep) { tx in FamilyProjectLoader.load(edited, replacing: fid, mode: .keepProjectValues, in: tx) }
        #expect(keep[fid]?.family == edited && keep[fid]?.name == "Side Table Mk2")
        #expect(keep.elements(.elementTypes).filter { $0.typeData?.familyID == fid }.allSatisfy { $0.typeData?.familyName == "Side Table Mk2" })
        #expect(keep.elements(.elementTypes).contains { $0.typeData?.familyID == fid && $0.name == "Low 600" })
        #expect(keep[tid]?.typeData?.params[Parameters.familyParamID("Width")] == .double(0.6))
        #expect(keep[tid]?.typeData?.params[apron] == .double(0.08))
        #expect(Parameters.value(apron, of: keep[inst]!, keep) == .double(0.08))
        let kb = Self.worldBounds(inst, keep)
        #expect(Self.approx(kb.max.x - kb.min.x, 0.6))
        let kept = ComponentGeometry.meshParts(keep[inst]!, keep)
        #expect(kept.count == 5)
        #expect(kept.contains { Self.approx($0.mesh.bounds.min.z, 0.47 - 0.08) && Self.approx($0.mesh.bounds.max.z, 0.47) })

        // Use Family Values: the existing type takes the family's Width.
        var over = base
        try Fx.commit(&over) { tx in FamilyProjectLoader.load(edited, replacing: fid, mode: .overwriteValues, in: tx) }
        let ob = Self.worldBounds(inst, over)
        #expect(Self.approx(ob.max.x - ob.min.x, 0.7))
        #expect(over.elements(.furniture).filter { $0.typeID == tid }.count == 1)

        // A project-side type value survives Keep Project Values and is replaced by Use Family Values.
        var tuned = base
        try Fx.commit(&tuned) { tx in try Parameters.set(Parameters.familyParamID("Leg Size"), to: .double(0.08), on: tid, in: tx) }
        var tunedKeep = tuned, tunedOver = tuned
        try Fx.commit(&tunedKeep) { tx in FamilyProjectLoader.load(edited, replacing: fid, mode: .keepProjectValues, in: tx) }
        try Fx.commit(&tunedOver) { tx in FamilyProjectLoader.load(edited, replacing: fid, mode: .overwriteValues, in: tx) }
        #expect(tunedKeep[tid]?.typeData?.params[Parameters.familyParamID("Leg Size")] == .double(0.08))
        #expect(Self.approx(tunedOver[tid]?.typeData?.params[Parameters.familyParamID("Leg Size")]?.doubleValue, 0.05))
    }

    @Test func reloadingTheSameFamilyIsANoOp() throws {
        var (m, ids) = Fx.template()
        let fam = Self.sideTable()
        let (fid, _, _) = try Self.placeInstance(&m, ids, family: fam, type: "600 x 600", at: Vec2(0, 0))
        let before = m
        let (record, _) = try Fx.commit(&m) { tx in FamilyProjectLoader.load(fam, replacing: fid, mode: .overwriteValues, in: tx) }
        #expect(record.changes.isEmpty)
        #expect(m.elements(.elementTypes).count == before.elements(.elementTypes).count)
        #expect(m.elements(.families).count == before.elements(.families).count)
    }
}
